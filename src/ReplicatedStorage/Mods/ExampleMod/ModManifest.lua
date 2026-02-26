--[[
  ExampleMod/ModManifest.lua  [MODULE SCRIPT]
  =============================================
  Required file for every mod package.
  ModLoader reads this to register and validate the mod.
]]

return {
  name         = "ExampleMod",
  version      = "1.0.0",
  author       = "YourName",
  description  = "An example mod that adds a custom item and recipe.",
  dependencies = {},   -- list other mod names this depends on
  load_order   = 100,  -- lower = loads earlier (core mods use 1-99)
}
