-- MoonStand loader: defines globals and loads external core
-- Only configuration and core fetch should live here.

-- Required MoonStand globals
getgenv().Script = "Get Moon Stand for free at discord.gg/mfyCBWWExF"
getgenv().Owner = "YOUR_USERNAME_HERE"
getgenv().DisableRendering = false
getgenv().BlackScreen = false
getgenv().FPSCap = 60

-- Allowed gun names (lowercase strings only)
getgenv().Guns = {
    "rifle",
    "aug",
    "flintlock",
    "lmg",
    "db",
}

-- Basic validation before loading the core
if type(getgenv().Owner) ~= "string" or getgenv().Owner == "" then
    warn("[Stand Loader] Owner must be configured before loading.")
    return
end

if type(getgenv().Guns) ~= "table" then
    warn("[Stand Loader] Guns must be provided as a list/table.")
    return
end

-- Load external core logic
-- Replace REPO_RAW_CORE_URL with the raw GitHub URL for stand_core.lua
loadstring(game:HttpGet("REPO_RAW_CORE_URL"))()
