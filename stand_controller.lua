-- MoonStand-style stand controller
-- ==============================
-- Configuration
-- ==============================
local StandConfig = getgenv().StandConfig or {
    ScriptName = "MoonStand Controller",
    Owner = "YourUsername",           -- Sole controller
    DisableRendering = false,
    BlackScreen = false,
    FPSCap = 60,

    AllowedGuns = {
        Revolver = CFrame.new(-638.75, 18.8500004, -118.175011, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        AK = CFrame.new(-587.529358, 5.39480686, -753.717712, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        SMG = CFrame.new(-577.123413, 5.47666788, -718.031433, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        AR = CFrame.new(-591.824158, 5.46046877, -744.731628, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        DoubleBarrel = CFrame.new(-1039.59985, 18.8513641, -256.449951, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        Shotgun = CFrame.new(-578.623657, 5.47212696, -725.131531, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        Flamethrower = CFrame.new(-157.122437, 50.9120102, -104.93145),
        TacticalShotgun = CFrame.new(470.877533, 45.1272316, -620.630676),
        RPG = CFrame.new(118.664856, -29.6487694, -272.349792),
        DrumGun = CFrame.new(-83.548996, 19.7020588, -82.1449585),
        Bat = CFrame.new(380, 49, -283),
        MediumArmor = CFrame.new(528, 50, -637),
        HighMediumArmor = CFrame.new(-939, -25, 571),
    },

    Whitelist = {},
    LoaderUrl = "https://example.com/stand/core.lua",
}

-- Expose config globally so a loader could mutate before requiring
getgenv().StandConfig = StandConfig

local COMMAND_PREFIX = "."

local function warnf(msg)
    warn("[Stand] " .. msg)
end

-- ==============================
-- Core Loader (simulated)
-- ==============================
local ok, err = pcall(function()
    loadstring(game:HttpGet(StandConfig.LoaderUrl))()
end)

if not ok then
    warnf("Core load failed: " .. tostring(err))
end

-- ==============================
-- Stand Controller
-- ==============================
local StandController = {}
StandController.__index = StandController

function StandController.new(config)
    local self = setmetatable({}, StandController)
    self.config = config
    self.whitelist = {}
    self.autoStomp = false

    for _, user in ipairs(config.Whitelist or {}) do
        self.whitelist[user:lower()] = true
    end

    return self
end

function StandController:isAuthorized(name)
    if not name then
        return false
    end

    name = name:lower()

    if name == (self.config.Owner or ""):lower() then
        return true
    end

    return self.whitelist[name] == true
end

function StandController:addWhitelist(user)
    if user and user ~= "" then
        self.whitelist[user:lower()] = true
    end
end

function StandController:removeWhitelist(user)
    if user and user ~= "" then
        self.whitelist[user:lower()] = nil
    end
end

function StandController:applyFeatureToggles()
    if self.config.DisableRendering then
        -- Placeholder: actual rendering disablement would go here
        print("[Stand] Rendering disabled")
    end

    if self.config.BlackScreen then
        -- Placeholder: actual black screen effect would go here
        print("[Stand] Black screen enabled")
    end

    if self.config.FPSCap and type(self.config.FPSCap) == "number" then
        print("[Stand] FPS capped at " .. tostring(self.config.FPSCap))
    end
end

function StandController:announce(text)
    print("[Stand] " .. text)
end

function StandController:startAutoStomp()
    if self.autoStomp then return end
    self.autoStomp = true

    game:GetService("RunService"):BindToRenderStep(
        "MoonStand-AutoStomp",
        0,
        function()
            game:GetService("ReplicatedStorage")
                :WaitForChild("MainEvent")
                :FireServer("Stomp")
        end
    )

    self:announce("Auto Stomp enabled")
end

function StandController:stopAutoStomp()
    if not self.autoStomp then return end
    self.autoStomp = false

    game:GetService("RunService"):UnbindFromRenderStep("MoonStand-AutoStomp")
    self:announce("Auto Stomp disabled")
end

-- ==============================
-- Command Parsing & Dispatch
-- ==============================
function StandController:executeCommand(command, args, speaker)
    local handler = self.commands[command]
    if handler then
        handler(self, args, speaker)
    else
        warnf("Unknown command: " .. tostring(command))
    end
end

function StandController:parseChat(msg, speaker)
    if type(msg) ~= "string" then return end
    if msg:sub(1, 1) ~= COMMAND_PREFIX then return end
    if not self:isAuthorized(speaker) then return end

    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local raw = args[1]
    if not raw or #raw < 2 then return end

    local command = raw:sub(2):lower()
    table.remove(args, 1)

    self:executeCommand(command, args, speaker)
end

-- ==============================
-- Command Handlers
-- ==============================
local function summonHandler(self)
    self:announce("Stand summoned/visible")
end

local function visibilityHandler(self)
    self:announce("Stand visibility toggled")
end

local function repairHandler(self)
    self:announce("Stand repaired")
end

local function rejoinHandler(self)
    self:announce("Rejoining server")
end

local function sayHandler(self, args)
    self:announce(table.concat(args, " "))
end

local function dashHandler(self)
    self:announce("Dash engaged")
end

local function blockHandler(self)
    self:announce("Block raised")
end

local function lightAttackHandler(self)
    self:announce("Light attack")
end

local function lockTargetHandler(self)
    self:announce("Lock target")
end

local function autoKillHandler(self)
    self:announce("Auto-kill engaged")
end

local function skyHandler(self)
    self:announce("Sky effect triggered")
end

local function flingHandler(self)
    self:announce("Fling executed")
end

local function auraHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state ~= "on" and state ~= "off" then
        return warnf("Usage: .a on|off")
    end

    self:announce("Aura toggled " .. state)
end

local function sentryHandler(self)
    self:announce("Sentry deployed")
end

local function blasterSentryHandler(self)
    self:announce("Blaster sentry deployed")
end

local function assistHandler(self)
    self:announce("Assist mode engaged")
end

local function tpLocationHandler(self, args)
    local location = table.concat(args, " ")
    self:announce("Teleporting to location: " .. location)
end

local function tpPlayerHandler(self, args)
    if #args >= 2 then
        self:announce("Teleporting " .. args[1] .. " to " .. args[2])
    else
        warnf("Usage: .t <player1> <player2>")
    end
end

local function whitelistHandler(self, args)
    local user = args[1]
    if user then
        self:addWhitelist(user)
        self:announce("Whitelisted user " .. user)
    else
        warnf("Usage: .wl <user>")
    end
end

local function unwhitelistHandler(self, args)
    local user = args[1]
    if user then
        self:removeWhitelist(user)
        self:announce("Removed user from whitelist: " .. user)
    else
        warnf("Usage: .unwl <user>")
    end
end

local function autoStompHandler(self, args)
    local state = args[1] and args[1]:lower()

    if state == "on" then
        self:startAutoStomp()
    elseif state == "off" then
        self:stopAutoStomp()
    else
        warnf("Usage: .stomp on|off")
    end
end

local function gunHandler(self, args)
    local gunName = table.concat(args, "")
    if gunName == "" then
        return warnf("Usage: .gun <name>")
    end

    local cf = self.config.AllowedGuns[gunName]
    if not cf then
        return warnf("Unknown gun: " .. gunName)
    end

    local lp = game.Players.LocalPlayer
    local char = lp.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = cf
        self:announce("Teleported to " .. gunName)
    end
end

function StandController:initCommands()
    -- Commands are resolved through this table.
    -- Only the Owner or whitelisted users may invoke them.
    -- Aliases intentionally map to shared handlers.
    self.commands = {
        -- Summon / Visibility
        summon = summonHandler,
        s = summonHandler,
        v = visibilityHandler,

        -- Utility / System
        repair = repairHandler,
        rejoin = rejoinHandler,
        say = sayHandler,

        -- Movement / Combat
        d = dashHandler,
        b = blockHandler,
        l = lightAttackHandler,
        lk = lockTargetHandler,
        akill = autoKillHandler,

        -- World Interaction / Effects
        sky = skyHandler,
        fling = flingHandler,
        ["a"] = auraHandler,

        -- Sentry / Support
        sentry = sentryHandler,
        bsentry = blasterSentryHandler,
        assist = assistHandler,

        -- Teleportation
        tp = tpLocationHandler,
        t = tpPlayerHandler,

        -- Whitelist Management
        wl = whitelistHandler,
        unwl = unwhitelistHandler,

        -- Automation
        stomp = autoStompHandler,
        autostomp = autoStompHandler,
        gun = gunHandler,
    }
end

function StandController:start()
    self:applyFeatureToggles()
    self:initCommands()
    -- In a real environment, connect this to Player.Chatted or a similar event
    self:announce(self.config.ScriptName .. " bound to " .. tostring(self.config.Owner))
end

-- Instantiate and start the controller
local controller = StandController.new(StandConfig)
controller:start()

-- Example of manual chat parsing; replace with event hooks in production
-- controller:parseChat(".summon", StandConfig.Owner)

return controller
