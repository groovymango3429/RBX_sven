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

-- Cache for tree models loaded from the Trees folder
local treeModels = nil
local treeModelsFolder = nil

-- Recently spawned tree positions for spacing checks (world coordinates)
-- Format: { [chunkKey] = { {x=wx, z=wz}, ... } }
local recentTreePositions = {}

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
		return false
	end
	
	-- Pick a random tree model
	local randomIndex = math.random(1, #models)
	local treeModel = models[randomIndex]
	
	-- Clone the tree
	local tree = treeModel:Clone()
	
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
				local scaledOffset = CFrame.new(offset.Position * randomScale) * (offset - offset.Position)
				part.CFrame = primaryCFrame:ToWorldSpace(scaledOffset)
			end
		end
	end
	
	-- Position the tree (convert block coordinates to world position)
	local worldPos = Vector3.new(wx * BLOCK_SIZE, wy * BLOCK_SIZE, wz * BLOCK_SIZE)
	if tree.PrimaryPart then
		-- Apply random Y-axis rotation
		local randomRotation = math.random() * 360
		local rotatedCFrame = CFrame.new(worldPos) * CFrame.Angles(0, math.rad(randomRotation), 0)
		tree:PivotTo(rotatedCFrame)
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
	
	-- Sample tree spawning with some spacing for performance (not every block)
	local sampleStride = 2  -- Check every 2 blocks
	
	for x = 0, CHUNK_SIZE - 1, sampleStride do
		local wx = originX + x
		for z = 0, CHUNK_SIZE - 1, sampleStride do
			local wz = originZ + z
			
			-- Check tree density (clustering)
			local density = getTreeDensity(wx, wz)
			if density < TREE_CLUSTER_THRESHOLD then
				-- This area is too sparse for trees
				goto continue
			end
			
			-- Random chance based on density (not every valid spot gets a tree)
			local spawnChance = (density - TREE_CLUSTER_THRESHOLD) / (1 - TREE_CLUSTER_THRESHOLD)
			if math.random() > spawnChance * 0.3 then  -- 30% max spawn rate in dense areas
				goto continue
			end
			
			-- Check spacing
			if isTooCloseToExistingTree(wx, wz, cx, cz) then
				goto continue
			end
			
			-- Find surface Y
			local surfaceY = findSurfaceY(chunk, x, z)
			if not surfaceY then
				goto continue
			end
			
			-- Check if surface is grass
			if not isGrassSurface(chunk, x, surfaceY, z) then
				goto continue
			end
			
			-- Check slope
			local slope = calculateSlope(chunk, x, z, wx, wz)
			if slope > MAX_SLOPE_FOR_TREES then
				goto continue
			end
			
			-- Spawn the tree
			if spawnTree(wx, surfaceY + 1, wz, parentFolder) then
				recordTreePosition(wx, wz, cx, cz)
			end
			
			::continue::
		end
	end
end

--- Clear cached tree positions for a chunk (call when chunk is unloaded)
function TreeSpawner.clearChunkCache(cx, cz)
	local chunkKey = cx .. "," .. cz
	recentTreePositions[chunkKey] = nil
end

return TreeSpawner
