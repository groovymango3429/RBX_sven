--[[
  TreeSpawner  [MODULE SCRIPT]
  ===========
  Procedural tree placement system for terrain chunks.
  
  Features:
  • Density-based clustering using Perlin noise (forests vs open plains)
  • Only spawns on grass terrain, not on steep slopes, water, or rock
  • Natural spacing rules prevent trees from spawning too close together
  • Random tree model selection from Trees folder
  • Random Y-axis rotation and scale variation for variety
  
  Usage:
    Call TreeSpawner.spawnTreesInChunk(chunk, workspace.Trees) after 
    terrain generation to populate grass areas with trees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder = Shared:WaitForChild("World")
local EnvironmentFolder = Shared:WaitForChild("Environment")

local ChunkConstants = require(WorldFolder:WaitForChild("ChunkConstants"))
local BlockRegistry = require(WorldFolder:WaitForChild("BlockRegistry"))
local NoiseConfig = require(WorldFolder:WaitForChild("NoiseConfig"))
local WorldGenConfig = require(WorldFolder:WaitForChild("WorldGenConfig"))
local BiomeDefinitions = require(WorldFolder:WaitForChild("BiomeDefinitions"))

local CHUNK_SIZE = ChunkConstants.CHUNK_SIZE
local CHUNK_HEIGHT = ChunkConstants.CHUNK_HEIGHT
local BLOCK_SIZE = ChunkConstants.BLOCK_SIZE

local ID_GRASS = BlockRegistry.getId("grass")

local treeConfig = WorldGenConfig.Trees
local TREE_DENSITY_SCALE = treeConfig.TREE_DENSITY_SCALE
local TREE_DENSITY_SEED = treeConfig.TREE_DENSITY_SEED
local TREE_CLUSTER_THRESHOLD = treeConfig.TREE_CLUSTER_THRESHOLD
local MIN_TREE_SPACING = treeConfig.MIN_TREE_SPACING
local MAX_SLOPE_FOR_TREES = treeConfig.MAX_SLOPE_FOR_TREES
local SCALE_MIN = treeConfig.SCALE_MIN
local SCALE_MAX = treeConfig.SCALE_MAX

local TreeSpawner = {}

-- Debug flag to control verbosity of per-chunk logging
local DEBUG_VERBOSE = true

-- Cache for tree models loaded from the Trees folder
local treeModels = nil
local treeModelsFolder = nil

-- Recently spawned tree positions for spacing checks (world coordinates)
-- Format: { [chunkKey] = { {x=wx, z=wz}, ... } }
local recentTreePositions = {}

-- Debug tracking for tree spawn attempts
local debugStats = {
	attempts = 0,
	successfulSpawns = 0,
	failedDensity = 0,
	failedChance = 0,
	failedSpacing = 0,
	failedNoSurface = 0,
	failedNotGrass = 0,
	failedSlope = 0,
}

--- Load tree models from the Trees folder
local function loadTreeModels()
	if treeModels then
		return treeModels
	end
	
	treeModels = {}
	
	-- Find the Trees folder
	local treesFolder = EnvironmentFolder:FindFirstChild("Trees")
	if not treesFolder then
		warn("[TreeSpawner] Trees folder not found in Shared/Environment/")
		print("[TreeSpawner] DEBUG: EnvironmentFolder path:", EnvironmentFolder:GetFullName())
		print("[TreeSpawner] DEBUG: EnvironmentFolder children:", table.concat(
			(function()
				local names = {}
				for _, child in ipairs(EnvironmentFolder:GetChildren()) do
					table.insert(names, child.Name)
				end
				return names
			end)(),
			", "
		))
		return treeModels
	end
	
	treeModelsFolder = treesFolder
	
	-- Collect all Model descendants
	for _, child in ipairs(treesFolder:GetDescendants()) do
		if child:IsA("Model") then
			table.insert(treeModels, child)
		end
	end
	
	if #treeModels == 0 then
		warn("[TreeSpawner] No tree models found in Trees folder. Add tree models to spawn trees.")
	else
		print(string.format("[TreeSpawner] DEBUG: Loaded %d tree models from %s", #treeModels, treesFolder:GetFullName()))
	end
	
	return treeModels
end

--- Get tree density at a world position using Perlin noise
local function getTreeDensity(wx, wz)
	local noiseValue = math.noise(wx * TREE_DENSITY_SCALE, wz * TREE_DENSITY_SCALE, TREE_DENSITY_SEED)
	-- Map from [-1, 1] to [0, 1]
	return (noiseValue + 1) * 0.5
end

--- Check if a position is too close to recently spawned trees
local function isTooCloseToExistingTree(wx, wz, cx, cz)
	local minSpacingSq = MIN_TREE_SPACING * MIN_TREE_SPACING
	
	-- Check current chunk and neighboring chunks
	for dx = -1, 1 do
		for dz = -1, 1 do
			local checkCx = cx + dx
			local checkCz = cz + dz
			local chunkKey = checkCx .. "," .. checkCz
			local positions = recentTreePositions[chunkKey]
			
			if positions then
				for _, pos in ipairs(positions) do
					local distSq = (wx - pos.x)^2 + (wz - pos.z)^2
					if distSq < minSpacingSq then
						return true
					end
				end
			end
		end
	end
	
	return false
end

--- Record a tree spawn position for spacing checks
local function recordTreePosition(wx, wz, cx, cz)
	local chunkKey = cx .. "," .. cz
	if not recentTreePositions[chunkKey] then
		recentTreePositions[chunkKey] = {}
	end
	table.insert(recentTreePositions[chunkKey], {x = wx, z = wz})
end

--- Calculate terrain slope at a position by sampling nearby heights
-- Returns slope as rise/run ratio
local function calculateSlope(chunk, x, z, wx, wz)
	-- Sample heights in a cross pattern
	local centerH = 0
	local leftH = 0
	local rightH = 0
	local upH = 0
	local downH = 0
	
	-- Get height at center
	for y = CHUNK_HEIGHT - 1, 0, -1 do
		local idx = x * (CHUNK_HEIGHT * CHUNK_SIZE) + y * CHUNK_SIZE + z + 1
		if chunk.blocks[idx] ~= 0 then
			centerH = y
			break
		end
	end
	
	-- Sample nearby heights (we'll use noise sampling since we may not have adjacent chunks)
	leftH = NoiseConfig.GetHeight(wx - 1, wz)
	rightH = NoiseConfig.GetHeight(wx + 1, wz)
	upH = NoiseConfig.GetHeight(wx, wz - 1)
	downH = NoiseConfig.GetHeight(wx, wz + 1)
	
	-- Calculate max slope in any direction
	local slopeX = math.max(math.abs(leftH - centerH), math.abs(rightH - centerH))
	local slopeZ = math.max(math.abs(upH - centerH), math.abs(downH - centerH))
	
	return math.max(slopeX, slopeZ)
end

--- Check if a block at (x, y, z) in chunk is grass surface
local function isGrassSurface(chunk, x, y, z)
	local idx = x * (CHUNK_HEIGHT * CHUNK_SIZE) + y * CHUNK_SIZE + z + 1
	local blockId = chunk.blocks[idx]
	
	if blockId ~= ID_GRASS then
		return false
	end
	
	-- Check that the block above is air
	if y + 1 < CHUNK_HEIGHT then
		local aboveIdx = x * (CHUNK_HEIGHT * CHUNK_SIZE) + (y + 1) * CHUNK_SIZE + z + 1
		if chunk.blocks[aboveIdx] ~= 0 then
			return false
		end
	end
	
	return true
end

--- Find the surface Y coordinate at chunk-local (x, z)
local function findSurfaceY(chunk, x, z)
	for y = CHUNK_HEIGHT - 1, 0, -1 do
		local idx = x * (CHUNK_HEIGHT * CHUNK_SIZE) + y * CHUNK_SIZE + z + 1
		if chunk.blocks[idx] ~= 0 then
			return y
		end
	end
	return nil
end

--- Spawn a single tree at the given world position
local function spawnTree(wx, wy, wz, parentFolder)
	local models = loadTreeModels()
	if #models == 0 then
		print("[TreeSpawner] DEBUG: No tree models available")
		return false
	end
	
	-- Pick a random tree model
	local randomIndex = math.random(1, #models)
	local treeModel = models[randomIndex]
	
	-- Clone the tree
	local tree = treeModel:Clone()
	
	-- Check if PrimaryPart exists
	if not tree.PrimaryPart then
		warn(string.format("[TreeSpawner] DEBUG: Tree model '%s' has no PrimaryPart! Attempting to set automatically.", treeModel.Name))
		-- Attempt to find a suitable part to use as anchor
		local parts = tree:GetDescendants()
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") then
				tree.PrimaryPart = part
				print(string.format("[TreeSpawner] DEBUG: Set PrimaryPart to '%s' for tree '%s'", part.Name, tree.Name))
				break
			end
		end
	end
	
	-- Apply random scale variation
	local randomScale = SCALE_MIN + (math.random() * (SCALE_MAX - SCALE_MIN))
	if tree.PrimaryPart then
		local primaryCFrame = tree.PrimaryPart.CFrame
		
		-- Scale all parts in the model
		for _, part in ipairs(tree:GetDescendants()) do
			if part:IsA("BasePart") then
				-- Get the offset CFrame (position + rotation) relative to PrimaryPart
				local offset = primaryCFrame:ToObjectSpace(part.CFrame)
				
				-- Scale the part size
				part.Size = part.Size * randomScale
				
				-- Scale only the position offset, preserve rotation
				-- (offset - offset.Position) extracts the rotational component by removing the position
				local scaledOffset = CFrame.new(offset.Position * randomScale) * (offset - offset.Position)
				part.CFrame = primaryCFrame:ToWorldSpace(scaledOffset)
			end
		end
	end
	
	-- Position the tree (convert block coordinates to world position)
	-- wy is provided as the block-level surface index (surfaceY + 1), so surface world Y is wy * BLOCK_SIZE
	local surfaceWorldY = wy * BLOCK_SIZE

	if tree.PrimaryPart then
		-- Compute model bottom relative to PrimaryPart so we can place the model's lowest point on the surface
		local primaryCFrame = tree.PrimaryPart.CFrame
		local minBottom = math.huge
		for _, part in ipairs(tree:GetDescendants()) do
			if part:IsA("BasePart") then
				local offset = primaryCFrame:ToObjectSpace(part.CFrame)
				local bottom = offset.Position.Y - (part.Size.Y / 2)
				if bottom < minBottom then
					minBottom = bottom
				end
			end
		end

		if minBottom == math.huge then
			-- No parts found for some reason; fallback to simple placement
			minBottom = 0
		end

		-- Determine target PrimaryPart Y so that model bottom sits exactly on surfaceWorldY
		local targetPrimaryY = surfaceWorldY - minBottom

		-- Apply random Y-axis rotation and pivot PrimaryPart to the computed world position
		local randomRotation = math.random() * 360
		local targetCFrame = CFrame.new(wx * BLOCK_SIZE, targetPrimaryY, wz * BLOCK_SIZE) * CFrame.Angles(0, math.rad(randomRotation), 0)
		tree:PivotTo(targetCFrame)
	else
		-- If still no PrimaryPart, fallback to using model extents so tree base sits above surface
		local extents = tree:GetExtentsSize()
		local fallbackPrimaryY = surfaceWorldY + (extents.Y / 2)
		local randomRotation = math.random() * 360
		local fallbackCFrame = CFrame.new(wx * BLOCK_SIZE, fallbackPrimaryY, wz * BLOCK_SIZE) * CFrame.Angles(0, math.rad(randomRotation), 0)
		tree:PivotTo(fallbackCFrame)
		warn(string.format("[TreeSpawner] DEBUG: Tree '%s' still has no PrimaryPart after attempting to set one! Using extents fallback.", tree.Name))
	end
	
	-- Parent to the world
	tree.Parent = parentFolder
	
	return true
end

--- Main entry point: Spawn trees in a generated chunk
-- @param chunk ChunkData - The generated chunk data
-- @param parentFolder Instance - The folder to parent spawned trees to (e.g., workspace.Trees)
function TreeSpawner.spawnTreesInChunk(chunk, parentFolder)
	if not chunk then
		warn("[TreeSpawner] No chunk provided")
		return
	end
	
	local cx = chunk.cx
	local cz = chunk.cz
	local originX = cx * CHUNK_SIZE
	local originZ = cz * CHUNK_SIZE
	
	if DEBUG_VERBOSE then
		print(string.format("[TreeSpawner] DEBUG: Starting tree spawn for chunk (%d, %d) | Origin: (%d, %d)", 
			cx, cz, originX, originZ))
	end
	
	-- Reset debug stats for this chunk
	local chunkStats = {
		attempts = 0,
		successfulSpawns = 0,
		failedDensity = 0,
		failedChance = 0,
		failedSpacing = 0,
		failedNoSurface = 0,
		failedNotGrass = 0,
		failedSlope = 0,
	}
	
	-- Sample tree spawning with some spacing for performance (not every block)
	local sampleStride = 2  -- Check every 2 blocks
	
	for x = 0, CHUNK_SIZE - 1, sampleStride do
		local wx = originX + x
		for z = 0, CHUNK_SIZE - 1, sampleStride do
			local wz = originZ + z
			chunkStats.attempts = chunkStats.attempts + 1
			
			-- Sequential checks using a skip flag (avoid goto)
			local shouldSpawn = true

			-- ── Biome check ────────────────────────────────────────────────────
			-- Read the biome ID stored by ChunkGenerator and look up its
			-- tree density multiplier.  Biomes with multiplier 0 never grow trees.
			local biomeId = chunk:getBiome(x, z)
			local biomeDef = BiomeDefinitions.getById(biomeId)
			local biomeDensityMult = biomeDef and biomeDef.treeDensityMult or 1.0

			if biomeDensityMult <= 0 then
				shouldSpawn = false
				chunkStats.failedDensity = chunkStats.failedDensity + 1
			end
			
			-- ── Base density check ─────────────────────────────────────────────
			local density = getTreeDensity(wx, wz)
			if shouldSpawn and density < TREE_CLUSTER_THRESHOLD then
				shouldSpawn = false
				chunkStats.failedDensity = chunkStats.failedDensity + 1
			end
			
			-- ── Random chance based on density × biome multiplier ──────────────
			-- biomeDensityMult scales the per-spot probability so forests are
			-- dense and savannas are sparse while using the same noise field.
			if shouldSpawn then
				local baseChance = (density - TREE_CLUSTER_THRESHOLD) / (1 - TREE_CLUSTER_THRESHOLD)
				local spawnChance = baseChance * biomeDensityMult
				if spawnChance <= 0 or math.random() > spawnChance * 0.3 then  -- 30% max spawn rate in dense areas
					shouldSpawn = false
					chunkStats.failedChance = chunkStats.failedChance + 1
				end
			end
			
			-- ── Spacing check ──────────────────────────────────────────────────
			if shouldSpawn and isTooCloseToExistingTree(wx, wz, cx, cz) then
				shouldSpawn = false
				chunkStats.failedSpacing = chunkStats.failedSpacing + 1
			end
			
			-- ── Find surface Y ─────────────────────────────────────────────────
			local surfaceY = nil
			if shouldSpawn then
				surfaceY = findSurfaceY(chunk, x, z)
				if not surfaceY then
					shouldSpawn = false
					chunkStats.failedNoSurface = chunkStats.failedNoSurface + 1
				end
			end

			-- ── Biome height gate ──────────────────────────────────────────────
			-- Optionally restrict trees to a biome-specific Y range.
			if shouldSpawn and biomeDef and biomeDef.treeHeightMin and biomeDef.treeHeightMax then
				if surfaceY < biomeDef.treeHeightMin or surfaceY > biomeDef.treeHeightMax then
					shouldSpawn = false
					chunkStats.failedNotGrass = chunkStats.failedNotGrass + 1
				end
			end
			
			-- ── Surface-type check ─────────────────────────────────────────────
			if shouldSpawn and not isGrassSurface(chunk, x, surfaceY, z) then
				shouldSpawn = false
				chunkStats.failedNotGrass = chunkStats.failedNotGrass + 1
			end
			
			-- ── Slope check ────────────────────────────────────────────────────
			if shouldSpawn then
				local slope = calculateSlope(chunk, x, z, wx, wz)
				if slope > MAX_SLOPE_FOR_TREES then
					shouldSpawn = false
					chunkStats.failedSlope = chunkStats.failedSlope + 1
				end
			end
			
			-- ── Spawn ──────────────────────────────────────────────────────────
			if shouldSpawn then
				if spawnTree(wx, surfaceY + 1, wz, parentFolder) then
					recordTreePosition(wx, wz, cx, cz)
					chunkStats.successfulSpawns = chunkStats.successfulSpawns + 1
				end
			end
		end
	end
	
	-- Update global stats
	debugStats.attempts = debugStats.attempts + chunkStats.attempts
	debugStats.successfulSpawns = debugStats.successfulSpawns + chunkStats.successfulSpawns
	debugStats.failedDensity = debugStats.failedDensity + chunkStats.failedDensity
	debugStats.failedChance = debugStats.failedChance + chunkStats.failedChance
	debugStats.failedSpacing = debugStats.failedSpacing + chunkStats.failedSpacing
	debugStats.failedNoSurface = debugStats.failedNoSurface + chunkStats.failedNoSurface
	debugStats.failedNotGrass = debugStats.failedNotGrass + chunkStats.failedNotGrass
	debugStats.failedSlope = debugStats.failedSlope + chunkStats.failedSlope
	
	if DEBUG_VERBOSE then
		print(string.format(
			"[TreeSpawner] DEBUG: Chunk (%d, %d) complete - Spawned: %d | Attempts: %d | Failed: density=%d, chance=%d, spacing=%d, no_surface=%d, not_grass=%d, slope=%d",
			cx, cz, chunkStats.successfulSpawns, chunkStats.attempts,
			chunkStats.failedDensity, chunkStats.failedChance, chunkStats.failedSpacing,
			chunkStats.failedNoSurface, chunkStats.failedNotGrass, chunkStats.failedSlope
		))
	end
end

--- Clear cached tree positions for a chunk (call when chunk is unloaded)
function TreeSpawner.clearChunkCache(cx, cz)
	local chunkKey = cx .. "," .. cz
	recentTreePositions[chunkKey] = nil
end

--- Get debug statistics for tree spawning
function TreeSpawner.getDebugStats()
	return debugStats
end

--- Print debug statistics summary
function TreeSpawner.printDebugStats()
	print("[TreeSpawner] ========== TREE SPAWNING STATISTICS ==========")
	print(string.format("[TreeSpawner] Total attempts: %d", debugStats.attempts))
	print(string.format("[TreeSpawner] Successful spawns: %d (%.1f%%)", 
		debugStats.successfulSpawns, 
		debugStats.attempts > 0 and (debugStats.successfulSpawns / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - Density: %d (%.1f%%)", 
		debugStats.failedDensity,
		debugStats.attempts > 0 and (debugStats.failedDensity / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - Random Chance: %d (%.1f%%)", 
		debugStats.failedChance,
		debugStats.attempts > 0 and (debugStats.failedChance / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - Spacing: %d (%.1f%%)", 
		debugStats.failedSpacing,
		debugStats.attempts > 0 and (debugStats.failedSpacing / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - No Surface: %d (%.1f%%)", 
		debugStats.failedNoSurface,
		debugStats.attempts > 0 and (debugStats.failedNoSurface / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - Not Grass: %d (%.1f%%)", 
		debugStats.failedNotGrass,
		debugStats.attempts > 0 and (debugStats.failedNotGrass / debugStats.attempts * 100) or 0))
	print(string.format("[TreeSpawner] Failed - Slope: %d (%.1f%%)", 
		debugStats.failedSlope,
		debugStats.attempts > 0 and (debugStats.failedSlope / debugStats.attempts * 100) or 0))
	print("[TreeSpawner] ============================================")
end

return TreeSpawner
