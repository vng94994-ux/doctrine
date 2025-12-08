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
StandController.actions = {}

function StandController.new(config)
    local self = setmetatable({}, StandController)
    self.config = config
    self.whitelist = {}
    self.autoStomp = false
    self.ownerChatConnection = nil
    self.ownerJoinConnection = nil
    self.isInvisible = false
    self.silentAimEnabled = false
    self.silentAimConnection = nil
    self.silentAimTarget = nil

    for _, user in ipairs(config.Whitelist or {}) do
        self.whitelist[user:lower()] = true
    end

    return self
end

local function getHumanoid(character)
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function getLocalCharacter()
    local lp = game:GetService("Players").LocalPlayer
    return lp, lp and lp.Character
end

local function ensureEquippedTool(humanoid, player)
    if not humanoid or not player then
        return nil
    end

    local tool = humanoid:FindFirstChildOfClass("Tool")
    if tool then
        return tool
    end

    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        tool = backpack:FindFirstChildOfClass("Tool")
        if tool then
            humanoid:EquipTool(tool)
            return tool
        end
    end

    return nil
end

local function getRoot(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function isKnocked(targetCharacter)
    if not targetCharacter then
        return false
    end

    local bodyEffects = targetCharacter:FindFirstChild("BodyEffects")
    local koFlag = bodyEffects and bodyEffects:FindFirstChild("K.O")

    return koFlag and koFlag.Value == true
end

local function findTargetPlayer(args)
    local nameFragment = args and args[1]
    local players = game:GetService("Players"):GetPlayers()
    local localPlayer = game:GetService("Players").LocalPlayer

    if nameFragment then
        local lowered = nameFragment:lower()
        for _, plr in ipairs(players) do
            if plr ~= localPlayer and plr.Name:lower():find(lowered, 1, true) then
                return plr
            end
        end
    end

    local closestPlayer = nil
    local closestDistance = math.huge
    local _, localChar = getLocalCharacter()
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

    if localRoot then
        for _, plr in ipairs(players) do
            if plr ~= localPlayer and plr.Character then
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestPlayer = plr
                    end
                end
            end
        end
    end

    return closestPlayer
end

local function moveTowardTarget(localHumanoid, targetRoot)
    if not localHumanoid or not targetRoot then
        return
    end

    pcall(function()
        localHumanoid:MoveTo(targetRoot.Position)
    end)
end

local function activateTool(tool)
    if tool and tool.Activate then
        pcall(function()
            tool:Activate()
        end)
    end
end

function StandController:startSilentAim(target)
    if not self.silentAimEnabled or not target then
        return
    end

    if self.silentAimConnection then
        self.silentAimConnection:Disconnect()
        self.silentAimConnection = nil
    end

    self.silentAimTarget = target

    local runService = game:GetService("RunService")
    self.silentAimConnection = runService.RenderStepped:Connect(function()
        local _, char = getLocalCharacter()
        local root = getRoot(char)
        local targetRoot = target.Character and getRoot(target.Character)
        local camera = workspace.CurrentCamera

        if not root or not targetRoot then
            self:stopSilentAim()
            return
        end

        root.CFrame = CFrame.lookAt(root.Position, targetRoot.Position)
        if camera then
            camera.CFrame = CFrame.new(camera.CFrame.Position, targetRoot.Position)
        end
    end)
end

function StandController:stopSilentAim()
    if self.silentAimConnection then
        self.silentAimConnection:Disconnect()
        self.silentAimConnection = nil
    end

    self.silentAimTarget = nil
end

function StandController:dance()
    local _, char = getLocalCharacter()
    local humanoid = getHumanoid(char)

    if not humanoid then
        return
    end

    local dance = Instance.new("Animation")
    dance.AnimationId = "rbxassetid://3189773368"

    local track = humanoid:LoadAnimation(dance)
    if track then
        track.Looped = false
        track:Play()
    end
end

StandController.actions = {
    summon = function(ctx)
        local _, char = getLocalCharacter()
        if not char then
            return
        end

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = 0
                part.CanCollide = true
            end
        end
    end,

    visibility = function(ctx)
        local controller = ctx.controller
        local _, char = getLocalCharacter()
        if not char then
            return
        end

        controller.isInvisible = not controller.isInvisible
        local transparency = controller.isInvisible and 1 or 0

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = transparency
                part.CanCollide = not controller.isInvisible
            end
        end
    end,

    repair = function(_)
        local _, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
        end
    end,

    rejoin = function(ctx)
        pcall(function()
            local teleportService = game:GetService("TeleportService")
            teleportService:Teleport(game.PlaceId, ctx.player)
        end)
    end,

    say = function(ctx)
        local message = table.concat(ctx.args or {}, " ")
        pcall(function()
            local chatEvents = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
            local sayEvent = chatEvents and chatEvents:FindFirstChild("SayMessageRequest")
            if sayEvent then
                sayEvent:FireServer(message, "All")
            end
        end)
    end,

    dash = function(_)
        local _, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if humanoid and root then
            pcall(function()
                root.Velocity = root.CFrame.LookVector * 80
            end)
        end
    end,

    bring = function(ctx)
        local target = findTargetPlayer(ctx.args)
        local player, char = getLocalCharacter()
        local localRoot = getRoot(char)
        local targetRoot = target and target.Character and getRoot(target.Character)

        if targetRoot and localRoot then
            targetRoot.CFrame = localRoot.CFrame * CFrame.new(0, 0, -3)
        end
    end,

    lightAttack = function(_)
        local player, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        local tool = ensureEquippedTool(humanoid, player)
        activateTool(tool)
    end,

    lockTarget = function(ctx)
        ctx.controller.lockedTarget = findTargetPlayer(ctx.args)
    end,

    autoKill = function(ctx)
        local controller = ctx.controller
        local target = controller.lockedTarget or findTargetPlayer(ctx.args)
        if not target or not target.Character then
            warnf("No valid target for akill")
            return
        end

        local player, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        local tool = ensureEquippedTool(humanoid, player)
        local targetHumanoid = getHumanoid(target.Character)
        local targetRoot = getRoot(target.Character)

        if not (humanoid and tool and targetHumanoid and targetRoot) then
            warnf("Unable to engage akill")
            return
        end

        controller:startSilentAim(target)

        local iterations = 0
        while iterations < 150 and targetHumanoid.Health > 0 and not isKnocked(target.Character) do
            moveTowardTarget(humanoid, targetRoot)
            activateTool(tool)
            task.wait(0.08)
            iterations += 1
        end

        controller:stopSilentAim()

        if isKnocked(target.Character) then
            pcall(function()
                game:GetService("ReplicatedStorage"):WaitForChild("MainEvent"):FireServer("Stomp")
            end)
            controller:dance()
        end
    end,

    knock = function(ctx)
        local controller = ctx.controller
        local target = controller.lockedTarget or findTargetPlayer(ctx.args)
        if not target or not target.Character then
            warnf("No valid target to knock")
            return
        end

        local player, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        local tool = ensureEquippedTool(humanoid, player)
        local targetHumanoid = getHumanoid(target.Character)
        local targetRoot = getRoot(target.Character)

        if not (humanoid and tool and targetHumanoid and targetRoot) then
            warnf("Unable to knock target")
            return
        end

        controller:startSilentAim(target)

        local iterations = 0
        while iterations < 150 and targetHumanoid.Health > 0 and not isKnocked(target.Character) do
            moveTowardTarget(humanoid, targetRoot)
            activateTool(tool)
            task.wait(0.08)
            iterations += 1
        end

        controller:stopSilentAim()
    end,

    sky = function(_)
        local _, char = getLocalCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = root.CFrame + Vector3.new(0, 50, 0)
        end
    end,

    fling = function(_)
        local _, char = getLocalCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            root.Velocity = Vector3.new(0, 0, 0)
            root.RotVelocity = Vector3.new(0, 40, 0)
        end
    end,

    aura = function(ctx)
        local enabled = ctx.enabled == true
        local _, char = getLocalCharacter()
        if not char then
            return
        end

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                part.Material = enabled and Enum.Material.Neon or Enum.Material.Plastic
            end
        end
    end,

    sentry = function(_)
        -- Placeholder for sentry deployment logic
    end,

    blasterSentry = function(_)
        -- Placeholder for blaster sentry deployment logic
    end,

    assist = function(_)
        local _, char = getLocalCharacter()
        local humanoid = getHumanoid(char)
        if humanoid then
            humanoid.WalkSpeed = 24
        end
    end,

    tpLocation = function(ctx)
        local _, char = getLocalCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local location = table.concat(ctx.args or {}, " ")

        if root and location ~= "" then
            local preset = ctx.controller.config.AllowedGuns[location]
            if typeof(preset) == "CFrame" then
                root.CFrame = preset
            end
        end
    end,

    tpPlayers = function(_) end,

    whitelist = function(_) end,

    unwhitelist = function(_) end,

    autoStomp = function(ctx)
        if ctx.enabled then
            ctx.controller:startAutoStomp()
        else
            ctx.controller:stopAutoStomp()
        end
    end,

    gun = function(ctx)
        local _, char = getLocalCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root and ctx.cframe then
            root.CFrame = ctx.cframe
        end
    end,
}

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

function StandController:hookOwnerChat(player)
    if self.ownerChatConnection then
        self.ownerChatConnection:Disconnect()
        self.ownerChatConnection = nil
    end

    self.ownerChatConnection = player.Chatted:Connect(function(message)
        self:parseChat(message, player.Name)
    end)
end

function StandController:setupChatListeners()
    local players = game:GetService("Players")
    local ownerName = (self.config.Owner or ""):lower()

    for _, plr in ipairs(players:GetPlayers()) do
        if plr.Name:lower() == ownerName then
            self:hookOwnerChat(plr)
        end
    end

    if self.ownerJoinConnection then
        self.ownerJoinConnection:Disconnect()
    end

    self.ownerJoinConnection = players.PlayerAdded:Connect(function(plr)
        if plr.Name:lower() == ownerName then
            self:hookOwnerChat(plr)
        end
    end)
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
    if StandController.actions.summon then
        StandController.actions.summon({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Stand summoned/visible")
end

local function visibilityHandler(self)
    if StandController.actions.visibility then
        StandController.actions.visibility({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Stand visibility toggled")
end

local function repairHandler(self)
    if StandController.actions.repair then
        StandController.actions.repair({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Stand repaired")
end

local function rejoinHandler(self)
    if StandController.actions.rejoin then
        StandController.actions.rejoin({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Rejoining server")
end

local function sayHandler(self, args)
    if StandController.actions.say then
        StandController.actions.say({
            player = game.Players.LocalPlayer,
            controller = self,
            args = args,
        })
    end

    self:announce(table.concat(args, " "))
end

local function knockHandler(self, args)
    if StandController.actions.knock then
        StandController.actions.knock({
            player = game.Players.LocalPlayer,
            controller = self,
            args = args,
        })
    end

    self:announce("Knock attempt started")
end

local function bringHandler(self, args)
    if StandController.actions.bring then
        StandController.actions.bring({
            player = game.Players.LocalPlayer,
            controller = self,
            args = args,
        })
    end

    self:announce("Bring executed")
end

local function lightAttackHandler(self)
    if StandController.actions.lightAttack then
        StandController.actions.lightAttack({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Light attack")
end

local function lockTargetHandler(self)
    if StandController.actions.lockTarget then
        StandController.actions.lockTarget({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Lock target")
end

local function autoKillHandler(self)
    if StandController.actions.autoKill then
        StandController.actions.autoKill({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Auto-kill engaged")
end

local function skyHandler(self)
    if StandController.actions.sky then
        StandController.actions.sky({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Sky effect triggered")
end

local function flingHandler(self)
    if StandController.actions.fling then
        StandController.actions.fling({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Fling executed")
end

local function auraHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state ~= "on" and state ~= "off" then
        return warnf("Usage: .a on|off")
    end

    if StandController.actions.aura then
        StandController.actions.aura({
            player = game.Players.LocalPlayer,
            controller = self,
            enabled = state == "on",
            args = args,
        })
    end

    self:announce("Aura toggled " .. state)
end

local function sentryHandler(self)
    if StandController.actions.sentry then
        StandController.actions.sentry({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Sentry deployed")
end

local function blasterSentryHandler(self)
    if StandController.actions.blasterSentry then
        StandController.actions.blasterSentry({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Blaster sentry deployed")
end

local function assistHandler(self)
    if StandController.actions.assist then
        StandController.actions.assist({
            player = game.Players.LocalPlayer,
            controller = self,
        })
    end

    self:announce("Assist mode engaged")
end

local function tpLocationHandler(self, args)
    local location = table.concat(args, " ")

    if StandController.actions.tpLocation then
        StandController.actions.tpLocation({
            player = game.Players.LocalPlayer,
            controller = self,
            args = args,
        })
    end

    self:announce("Teleporting to location: " .. location)
end

local function tpPlayerHandler(self, args)
    if #args >= 2 then
        if StandController.actions.tpPlayers then
            StandController.actions.tpPlayers({
                player = game.Players.LocalPlayer,
                controller = self,
                args = args,
            })
        end

        self:announce("Teleporting " .. args[1] .. " to " .. args[2])
    else
        warnf("Usage: .t <player1> <player2>")
    end
end

local function whitelistHandler(self, args)
    local user = args[1]
    if user then
        self:addWhitelist(user)

        if StandController.actions.whitelist then
            StandController.actions.whitelist({
                player = game.Players.LocalPlayer,
                controller = self,
                args = args,
                user = user,
            })
        end

        self:announce("Whitelisted user " .. user)
    else
        warnf("Usage: .wl <user>")
    end
end

local function unwhitelistHandler(self, args)
    local user = args[1]
    if user then
        self:removeWhitelist(user)

        if StandController.actions.unwhitelist then
            StandController.actions.unwhitelist({
                player = game.Players.LocalPlayer,
                controller = self,
                args = args,
                user = user,
            })
        end

        self:announce("Removed user from whitelist: " .. user)
    else
        warnf("Usage: .unwl <user>")
    end
end

local function autoStompHandler(self, args)
    local state = args[1] and args[1]:lower()

    if state == "on" then
        self:startAutoStomp()

        if StandController.actions.autoStomp then
            StandController.actions.autoStomp({
                player = game.Players.LocalPlayer,
                controller = self,
                args = args,
                enabled = true,
            })
        end
    elseif state == "off" then
        self:stopAutoStomp()

        if StandController.actions.autoStomp then
            StandController.actions.autoStomp({
                player = game.Players.LocalPlayer,
                controller = self,
                args = args,
                enabled = false,
            })
        end
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

        if StandController.actions.gun then
            StandController.actions.gun({
                player = lp,
                controller = self,
                args = args,
                gun = gunName,
                cframe = cf,
            })
        end

        self:announce("Teleported to " .. gunName)
    end
end

local function silentAimHandler(self, args)
    local state = args[1] and args[1]:lower()

    if state == "on" then
        self.silentAimEnabled = true
        self:announce("Silent aim enabled")
    elseif state == "off" then
        self.silentAimEnabled = false
        self:stopSilentAim()
        self:announce("Silent aim disabled")
    else
        warnf("Usage: .silent on|off")
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
        d = knockHandler,
        b = bringHandler,
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
        silent = silentAimHandler,
    }
end

function StandController:start()
    self:applyFeatureToggles()
    self:initCommands()
    self:setupChatListeners()
    self:announce(self.config.ScriptName .. " bound to " .. tostring(self.config.Owner))
end

-- Instantiate and start the controller
local controller = StandController.new(StandConfig)
controller:start()

-- Example of manual chat parsing; replace with event hooks in production
-- controller:parseChat(".summon", StandConfig.Owner)

return controller
