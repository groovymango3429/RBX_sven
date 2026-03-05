

 game inspired by 7 Days to Die.
> Full voxel world, zombie AI, crafting, horde nights, vehicles, and electricity.

## Prerequisites

- [Rojo](https://rojo.space/) v7+ — syncs this project into Roblox Studio
- [Wally](https://github.com/UpliftGames/wally) — installs Lua packages (optional)
- Roblox Studio

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/yourname/deadland.git
cd deadland

# 2. Install packages (or manually drop them into src/ReplicatedStorage/Packages/)
wally install

# 3. Open Roblox Studio, then in a terminal:
rojo serve default.project.json

# 4. In Studio, connect to Rojo via the Rojo plugin
# 5. Press Play!
```

## Project Structure

```
DeadLand/
├── default.project.json       ← Rojo project file (maps files → Studio Explorer)
├── wally.toml                 ← Package manager config
├── src/
│   ├── ReplicatedStorage/
│   │   ├── Packages/          ← Third-party libraries (install via Wally)
│   │   ├── Shared/            ← ModuleScripts shared by server + client
│   │   │   ├── Core/          ← ServiceLocator, Signal, Maid, Logger, etc.
│   │   │   ├── World/         ← BlockRegistry, ChunkData, BiomeDefinitions
│   │   │   ├── Entity/        ← EntityDefinitions, DamageCalc, ArmorDefs
│   │   │   ├── Items/         ← ItemDatabase, WeaponDefs, ConsumableDefs
│   │   │   ├── Crafting/      ← RecipeDatabase, CraftingValidator
│   │   │   ├── Character/     ← SkillDefs, PerkDefs, BuffProcessor
│   │   │   ├── Quests/        ← QuestDatabase, QuestValidator
│   │   │   ├── Environment/   ← WeatherDefs, FarmingDefs
│   │   │   ├── Vehicles/      ← VehicleDefinitions, FuelSystem
│   │   │   └── Electricity/   ← ElectricComponentDefs, PowerGridCalc
│   │   ├── Remotes/           ← RemoteEvents and RemoteFunctions (by system)
│   │   └── Mods/              ← Drop mod packages here
│   ├── ServerScriptService/
│   │   ├── GameManager        ← Server boot orchestrator (the ONLY server Script)
│   │   ├── Managers/          ← All server manager ModuleScripts
│   │   ├── World/             ← Chunk gen, SI, streaming, persistence
│   │   ├── AI/                ← Zombie state machines, navigation, spawning
│   │   ├── Horde/             ← 7-day scheduler, heat map, wave configs
│   │   ├── Combat/            ← Hit validation, damage pipeline, loot drops
│   │   ├── Persistence/       ← ProfileStore, DataMigration, AutoSave
│   │   ├── Economy/           ← Trader service, price fluctuation
│   │   ├── Cmdr/              ← Admin command server + Commands/
│   │   └── ModSupport/        ← ModLoader, ModValidator, DatabaseMerger
│   ├── StarterPlayerScripts/
│   │   ├── ClientMain         ← Client boot orchestrator
│   │   ├── Core/              ← InputHandler, CameraController, NetworkClient
│   │   ├── UI/                ← All 25+ UI panel controllers
│   │   ├── WorldClient/       ← ChunkRenderer, WeatherRenderer
│   │   ├── CombatClient/      ← WeaponClient, VFX, ScreenEffects
│   │   └── Audio/             ← AudioClient, MusicController, Soundscape
│   └── StarterCharacterScripts/
│       ├── CharacterSetup     ← Runs on respawn to configure humanoid
│       └── Character/         ← AnimationController, MovementController, etc.
```

## Script Color Key

| Color | Type | Runs On |
|-------|------|---------|
| 🟠 Orange | `Script` (.server.lua) | Server only |
| 🔵 Blue | `LocalScript` (.client.lua) | Each player's machine |
| 🟣 Violet | `ModuleScript` (.lua) | Wherever require()d |
| 🩷 Pink | `RemoteEvent / RemoteFunction` | Network boundary |

## Re-exports Explained

Several modules in `Shared/Core/` are **re-exports** of packages.
For example, `Shared/Core/Signal.lua` simply does:
```lua
return require(game.ReplicatedStorage.Packages.MadworkSignal)
```
This means all systems use `require(Shared.Core.Signal)` — if you swap the
underlying library you only change ONE file, not every system.

Same pattern for: `Maid`, `Promise`, `TableUtil`.

## Required Packages

Install via Wally or manually into `src/ReplicatedStorage/Packages/`.
See `src/ReplicatedStorage/Packages/README.md` for full list.

## Architecture Reference

See the included `DeadLand_Architecture_v2.docx` for the full system design document.

## Development Phases

| Phase | Weeks | Focus |
|-------|-------|-------|
| P0 | 1–2 | Scaffolding & packages |
| P1 | 3–6 | Chunk world foundation |
| P2 | 7–10 | Character & inventory |
| P3 | 11–15 | Combat & entities |
| P4 | 16–19 | World depth & loot |
| P5 | 20–23 | Crafting & progression |
| P6 | 24–27 | Horde system |
| P7 | 28–32 | Economy & quests |
| P8 | 33–36 | Vehicles & electricity |
| P9 | 37–39 | Environment & farming |
| P10 | 40–44 | Polish & audio |
| P11 | 45–48 | Anti-cheat & mods |
| P12 | 49–54 | Beta & release |

## Contributing

1. Every system gets its own `ModuleScript` — no logic in Scripts or LocalScripts
2. All server state is authoritative — clients only render
3. Use `Signal` (not BindableEvents) for internal events
4. Register all connections with a `Maid` — no memory leaks
5. All player data flows through `ProfileStore` → `ReplicaService`
