-- MoonStand loader: defines globals and loads external core
-- Only configuration and core fetch should live here.

getgenv().Script = "MoonStand"
getgenv().Owner = "USERNAME_HERE"

getgenv().DisableRendering = false
getgenv().BlackScreen = false
getgenv().FPSCap = 60

getgenv().Guns = {
    "rifle",
    "lmg",
    "rev",
    "db",
    "rpg",
}

-- Load external core logic
loadstring(game:HttpGet("https://raw.githubusercontent.com/vng94994-ux/doctrine/refs/heads/main/stand_core.lua"))()
