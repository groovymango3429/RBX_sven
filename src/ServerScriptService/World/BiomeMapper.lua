--[[
  BiomeMapper  [MODULE SCRIPT]
  ===========
  Maps a world-space (x, z) position to a biome ID by finding the nearest
  biome centroid in (temperature, humidity) climate space.

  Algorithm
  ---------
  Each biome has a preferred (tempCenter, humidCenter) coordinate.  For a
  given position we sample temperature and humidity via NoiseConfig, then
  pick the biome whose centroid is closest (Euclidean distance).  Because
  the underlying noise varies smoothly, biome boundaries naturally follow
  gradual climate gradients rather than hard-cutoff lines.

  Altitude overrides (snow peaks, rocky hillsides) are NOT handled here —
  ChunkGenerator applies those on top of the returned biome ID.

  Public API
  ----------
  BiomeMapper.getBiomeAt(wx, wz)  →  biomeId  (number, 0-based)
  BiomeMapper.getClimate(wx, wz)  →  temperature, humidity  (both 0–1)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local WorldFolder       = Shared:WaitForChild("World")

local NoiseConfig       = require(WorldFolder:WaitForChild("NoiseConfig"))
local BiomeDefinitions  = require(WorldFolder:WaitForChild("BiomeDefinitions"))

local BiomeMapper = {}

-- ── Pre-build centroid list for fast nearest-biome lookup ────────────────────
-- We build this once at module load time so getBiomeAt never allocates tables.
local _centroids = {}
for id, def in pairs(BiomeDefinitions.Biomes) do
	table.insert(_centroids, {
		id = id,
		tc = def.tempCenter,
		hc = def.humidCenter,
	})
end

-- ── Private helper ────────────────────────────────────────────────────────────

--- _nearestBiome: Return the biome ID whose centroid is closest to (temp, humid).
local function _nearestBiome(temp, humid)
	local bestId     = 0
	local bestDistSq = math.huge
	for _, entry in ipairs(_centroids) do
		local dt     = temp  - entry.tc
		local dh     = humid - entry.hc
		local distSq = dt * dt + dh * dh
		if distSq < bestDistSq then
			bestDistSq = distSq
			bestId     = entry.id
		end
	end
	return bestId
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- getBiomeAt: Return the dominant biome ID at world position (wx, wz).
-- This is a pure function — callers that call it many times for the same
-- position (e.g., ChunkGenerator's column-pre-compute pass) should cache
-- the result themselves rather than relying on an internal cache here.
function BiomeMapper.getBiomeAt(wx, wz)
	local temp  = NoiseConfig.GetTemperature(wx, wz)
	local humid = NoiseConfig.GetHumidity(wx, wz)
	return _nearestBiome(temp, humid)
end

--- getClimate: Return raw (temperature, humidity) for a position.
-- Useful for debugging or external biome-blending logic.
function BiomeMapper.getClimate(wx, wz)
	return NoiseConfig.GetTemperature(wx, wz), NoiseConfig.GetHumidity(wx, wz)
end

return BiomeMapper
