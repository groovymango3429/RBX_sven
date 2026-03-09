--[[
  MapLoader  [MODULE SCRIPT]
  =========
  Connects a player-supplied button to the server-side map generation system
  and drives a loading-screen UI while all chunks are being streamed AND
  rendered on the client.

  ── How to use ──────────────────────────────────────────────────────────────
  Call MapLoader.setup(config) from any LocalScript, passing references to
  the UI elements you have built inside your ScreenGui.

  Example (from a separate LocalScript inside StarterPlayerScripts or StarterGui):

    local Players    = game:GetService("Players")
    local playerGui  = Players.LocalPlayer:WaitForChild("PlayerGui")
    local myGui      = playerGui:WaitForChild("MapScreenGui")

    local MapLoader = require(
      game:GetService("Players").LocalPlayer
          :WaitForChild("PlayerScripts")
          :WaitForChild("WorldClient")
          :WaitForChild("MapLoader")
    )

    MapLoader.setup({
      button       = myGui:WaitForChild("GenerateButton"),
      loadingFrame = myGui:WaitForChild("LoadingFrame"),
      loadingBar   = myGui:WaitForChild("LoadingFrame"):WaitForChild("BarFill"),
    })

  ── Accurate loading bar ─────────────────────────────────────────────────────
  The progress bar is split into two phases:
    • Phase 1 (server generation, 0 → 90 %):
        Driven by MapGenProgress events.  Each chunk sent = one tick.
    • Phase 2 (client rendering, 90 → 100 %):
        The loading screen stays visible until ChunkRenderer has finished
        drawing every chunk.  Call MapLoader.connectRenderer(ChunkRenderer)
        from ClientMain after both modules are initialised so MapLoader can
        register a render-complete callback.

  If connectRenderer() is never called the screen hides as soon as the
  server finishes sending (original behaviour — safe fallback).

  ── config fields ────────────────────────────────────────────────────────────
    button       GuiButton | nil
        The TextButton or ImageButton the player clicks to start generation.
        If omitted, the trigger is disabled (useful for auto-starting via code).

    loadingFrame GuiObject | nil
        A Frame (or any GuiObject) that acts as the loading screen container.
        MapLoader will set its Visible property.

    loadingBar   GuiObject | nil
        A Frame whose Size.X.Scale is lerped from 0 → 1 as chunks are sent.
        Typically a coloured bar sitting inside a background frame.
        MapLoader only updates Size — position, colour, etc. are yours to set.

  ── Return value ─────────────────────────────────────────────────────────────
  setup() returns a disconnect() function.  Call it if you ever want to
  remove the event listeners (e.g. when swapping to a different UI layout).

  ── Changing the UI without editing this script ──────────────────────────────
  Simply call setup() again with different references.  Each call replaces
  the previous connections.  The core generation logic lives entirely on the
  server (StreamingService) and is never modified by UI changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local WorldRem = Remotes:WaitForChild("World")

-- Remote used by the client to ask the server to start generation.
local _requestRemote  = WorldRem:WaitForChild("RequestMapGeneration", 10)
-- Remote used by the server to report per-chunk progress (done, total).
local _progressRemote = WorldRem:WaitForChild("MapGenProgress",       10)

-- (no client debug logging by default)

if not _requestRemote then
	warn("[MapLoader] RequestMapGeneration RemoteEvent not found — map generation disabled.")
end
if not _progressRemote then
	warn("[MapLoader] MapGenProgress RemoteEvent not found — loading bar disabled.")
end

-- ────────────────────────────────────────────────────────────────────────────

-- Optional ChunkRenderer reference set via connectRenderer().
-- When present, the loading screen waits for all chunks to be rendered before
-- hiding, giving an accurate two-phase progress bar.
local _chunkRenderer = nil

-- Brief pause (seconds) after the bar visually reaches 100 % before hiding
-- the loading frame, so the player sees the completed bar.
local LOADING_BAR_COMPLETION_DELAY = 0.15

local MapLoader = {}

--- connectRenderer: Link MapLoader to ChunkRenderer for render-phase tracking.
-- Call this once from ClientMain after both modules are initialised.
-- @param renderer  ChunkRenderer module (table with setExpectedChunks / setOnAllRendered)
function MapLoader.connectRenderer(renderer)
	_chunkRenderer = renderer
end

--- setup: Wire up UI elements to the map-generation system.
-- @param config table
--   {
--     button       : GuiButton | nil,
--     loadingFrame : GuiObject | nil,
--     loadingBar   : GuiObject | nil,
--   }
-- @return function  disconnect()
function MapLoader.setup(config)
	config = config or {}

	local button       = config.button
	local loadingFrame = config.loadingFrame
	local loadingBar   = config.loadingBar

	local connections = {}

	-- ── Helpers ──────────────────────────────────────────────────────────────

	-- Update the loading bar's horizontal fill (fraction 0 → 1).
	local function setProgress(fraction)
		if loadingBar then
			loadingBar.Size = UDim2.new(
				math.clamp(fraction, 0, 1), 0,
				loadingBar.Size.Y.Scale, loadingBar.Size.Y.Offset
			)
		end
	end

	-- Show or hide the loading frame.
	local function setLoadingVisible(visible)
		if loadingFrame then
			loadingFrame.Visible = visible
		end
	end

	-- ── Progress listener ─────────────────────────────────────────────────────
	-- Phase 1: server fires MapGenProgress(done, total) after each chunk is sent.
	--   → Bar fills from 0 to 90 %.
	-- Phase 2: ChunkRenderer fires its onAllRendered callback when every chunk
	--   has been drawn on screen.
	--   → Bar completes to 100 % and loading screen is hidden.
	if _progressRemote then
		connections[#connections + 1] = _progressRemote.OnClientEvent:Connect(
			function(done, total)
				if total > 0 then
					-- Phase 1: server generation fills 0 → 90 % of the bar.
					setProgress((done / total) * 0.9)
				end

				if done >= total then
					-- Server has sent all chunks.
					if _chunkRenderer then
						-- Phase 2: wait for ChunkRenderer to finish drawing them.
						_chunkRenderer.setExpectedChunks(total)
						_chunkRenderer.setOnAllRendered(function()
							setProgress(1)
							task.wait(LOADING_BAR_COMPLETION_DELAY)
							setLoadingVisible(false)
							print("[MapLoader] Map fully rendered ✓")
						end)
					else
						-- Fallback: no renderer connected — hide immediately.
						setProgress(1)
						setLoadingVisible(false)
						print("[MapLoader] Map generation complete ✓")
					end
				end
			end
		)
	end

	-- ── Button connection ─────────────────────────────────────────────────────
	-- Clicking the button resets the bar, shows the loading frame, and asks
	-- the server to start generating.
	if button then
		connections[#connections + 1] = button.Activated:Connect(function()
			if not _requestRemote then
				warn("[MapLoader] RequestMapGeneration remote not found — cannot start generation.")
				return
			end
			setProgress(0)
			setLoadingVisible(true)
			-- Reset renderer state so a re-generation starts tracking from scratch.
			if _chunkRenderer then
				_chunkRenderer.setExpectedChunks(0)
			end
			_requestRemote:FireServer()
			print("[MapLoader] Map generation requested.")
		end)
	else
		warn("[MapLoader] No button provided to MapLoader.setup() — click trigger disabled.")
	end

	-- ── Disconnect helper ─────────────────────────────────────────────────────
	return function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end
end

--- triggerGeneration: Programmatically start generation without a button click.
-- Optionally shows the loading frame and resets the bar.
-- Useful for auto-starting generation (e.g. for a single-player experience).
-- @param loadingFrame GuiObject | nil   — frame to show while generating
-- @param loadingBar   GuiObject | nil   — bar to reset to 0
function MapLoader.triggerGeneration(loadingFrame, loadingBar)
	if not _requestRemote then
		warn("[MapLoader] RequestMapGeneration remote not found — cannot start generation.")
		return
	end
	if loadingBar then
		loadingBar.Size = UDim2.new(0, 0, loadingBar.Size.Y.Scale, loadingBar.Size.Y.Offset)
	end
	if loadingFrame then
		loadingFrame.Visible = true
	end
	if _chunkRenderer then
		_chunkRenderer.setExpectedChunks(0)
	end
	_requestRemote:FireServer()
	print("[MapLoader] Map generation triggered programmatically.")
end

return MapLoader
