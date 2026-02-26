# Mods

Place mod packages here as sub-folders. Each mod folder must contain a `ModManifest.lua`.

## Mod Manifest Structure

```lua
return {
  name         = "MyMod",
  version      = "1.0.0",
  author       = "YourName",
  dependencies = {},   -- other mod names this requires
  load_order   = 100,  -- lower numbers load first
}
```

## Mod Sub-Folders

- `Items/`       — Additional ItemDatabase entries  
- `Recipes/`     — Additional RecipeDatabase entries
- `Entities/`    — Additional EntityDefinitions entries
- `Quests/`      — Additional quest chains
- `LootTables/`  — Additional or override loot tables
- `Biomes/`      — New biome definitions
