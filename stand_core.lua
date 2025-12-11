-- MoonStand core (loader seeds globals; logic resides here)
-- Reads configuration exclusively from getgenv().

local env = getgenv()
local COMMAND_PREFIX = "."

local StandController = {}
StandController.__index = StandController

local function warnf(msg)
    warn("[Stand] " .. msg)
end

local function players()
    return game:GetService("Players")
end

local function runService()
    return game:GetService("RunService")
end

local function replicatedStorage()
    return game:GetService("ReplicatedStorage")
end

local function tweenService()
    return game:GetService("TweenService")
end

local function getLocalPlayer()
    return players().LocalPlayer
end

local function getCharacter(plr)
    return plr and plr.Character
end

local function getHumanoid(char)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHead(char)
    return char and char:FindFirstChild("Head")
end

local function stringLower(str)
    return type(str) == "string" and str:lower() or str
end

local function findPlayerByFragment(fragment)
    if not fragment or fragment == "" then
        return nil
    end

    fragment = fragment:lower()
    local lp = getLocalPlayer()
    for _, plr in ipairs(players():GetPlayers()) do
        if plr ~= lp and plr.Name:lower():find(fragment, 1, true) then
            return plr
        end
    end

    return nil
end

function StandController.new()
    local self = setmetatable({}, StandController)

    self.owner = env.Owner
    self.allowedGuns = {}
    for _, name in ipairs(env.Guns or {}) do
        if type(name) == "string" then
            self.allowedGuns[name:lower()] = true
        end
    end

    self.state = {
        followOwner = false,
        stay = false,
        voided = true,
        aura = false,
        akill = false,
        auraWhitelist = {},
        whitelist = {},
        sentry = false,
        bsentry = false,
        fp = false,
        mask = false,
        loopkillTarget = nil,
        loopknockTarget = nil,
        assistTargets = {},
        lastTarget = nil,
        targetForBring = nil,
        targetForStomp = nil,
        targetForSky = nil,
        targetForFling = nil,
        silentAim = true,
    }

    self.connections = {}
    self.voidBase = CFrame.new(0, 15000, 0)
    self.mainEvent = replicatedStorage():FindFirstChild("MainEvent")
    self.danceAnimationId = "rbxassetid://15610015346"

    self.actions = {}

    return self
end

function StandController:announce(text)
    print(("[Stand] %s"):format(text))
end

function StandController:isAuthorized(name)
    if not name then
        return false
    end

    if self.owner and name:lower() == self.owner:lower() then
        return true
    end

    return self.state.whitelist[name:lower()] == true
end

function StandController:addWhitelist(user)
    if not user then
        return
    end
    self.state.whitelist[user:lower()] = true
end

function StandController:removeWhitelist(user)
    if not user then
        return
    end
    self.state.whitelist[user:lower()] = nil
end

-- Initialization helpers
function StandController:applyCFrame(root, cf)
    if not root or not cf then
        return
    end

    root.CFrame = cf
end

function StandController:randomVoidCFrame()
    local offset = Vector3.new(
        math.random(-200000, 200000),
        math.random(30000, 60000),
        math.random(-200000, 200000)
    )
    return CFrame.new(offset)
end

function StandController:teleportVoid()
    local lp = getLocalPlayer()
    local root = getRoot(getCharacter(lp))
    if root then
        self:applyCFrame(root, self:randomVoidCFrame())
    end
    self.state.voided = true
end

function StandController:preloadAnimations()
    local humanoid = getHumanoid(getCharacter(getLocalPlayer()))
    if not humanoid then
        return
    end

    if self.danceAnimationId then
        local anim = Instance.new("Animation")
        anim.AnimationId = self.danceAnimationId
        local track = humanoid:LoadAnimation(anim)
        track:Stop()
        self.cachedDanceTrack = track
    end
end

function StandController:buyGunIfMissing(name)
    local lp = getLocalPlayer()
    local backpack = lp:FindFirstChild("Backpack")
    local char = getCharacter(lp)
    local function hasTool(container)
        if not container then
            return false
        end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and stringLower(tool.Name) == name then
                return true
            end
        end
        return false
    end

    if hasTool(backpack) or hasTool(char) then
        return true
    end

    if self.mainEvent then
        pcall(function()
            self.mainEvent:FireServer("BuyItem", name)
        end)
    end

    return hasTool(backpack) or hasTool(char)
end

function StandController:autoAcquireGuns()
    for gun in pairs(self.allowedGuns) do
        self:buyGunIfMissing(gun)
    end
end

function StandController:equipAllowedTool()
    local lp = getLocalPlayer()
    local char = getCharacter(lp)
    local humanoid = getHumanoid(char)
    if not humanoid then
        return nil
    end

    local backpack = lp:FindFirstChild("Backpack")
    local function findTool(container)
        if not container then
            return nil
        end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and self.allowedGuns[stringLower(tool.Name)] then
                return tool
            end
        end
        return nil
    end

    local equipped = humanoid:FindFirstChildOfClass("Tool")
    if equipped and self.allowedGuns[stringLower(equipped.Name)] then
        return equipped
    end

    local found = findTool(char) or findTool(backpack)
    if found then
        humanoid:EquipTool(found)
        return found
    end

    return nil
end

function StandController:autoReload(tool)
    if not tool then
        return
    end
    local ammo = tool:FindFirstChild("Ammo")
    if ammo and ammo:IsA("IntValue") and ammo.Value <= 0 then
        if self.mainEvent then
            pcall(function()
                self.mainEvent:FireServer("Reload", tool)
            end)
        end
    end
end

function StandController:aimAtTarget(target)
    local char = getCharacter(getLocalPlayer())
    local root = getRoot(char)
    local targetChar = getCharacter(target)
    if not (root and targetChar) then
        return
    end

    local targetRoot = getRoot(targetChar)
    local targetHead = getHead(targetChar)
    local focus = (targetHead and targetHead.Position) or (targetRoot and targetRoot.Position)
    if not focus then
        return
    end

    root.CFrame = CFrame.lookAt(root.Position, focus)
    local cam = workspace.CurrentCamera
    if cam then
        cam.CFrame = CFrame.new(cam.CFrame.Position, focus)
    end
end

function StandController:isKO(plr)
    local char = getCharacter(plr)
    if not char then
        return false
    end
    local effects = char:FindFirstChild("BodyEffects")
    if not effects then
        return false
    end
    local ko = effects:FindFirstChild("K.O")
    local dead = effects:FindFirstChild("Dead")
    return (ko and ko.Value) or (dead and dead.Value) or false
end

function StandController:shootTarget(target)
    local tool = self:equipAllowedTool()
    if not tool then
        return
    end

    self:autoReload(tool)
    self:aimAtTarget(target)
    pcall(function()
        tool:Activate()
    end)
end

function StandController:moveTowardTarget(target)
    local lp = getLocalPlayer()
    local root = getRoot(getCharacter(lp))
    local targetRoot = getRoot(getCharacter(target))
    if root and targetRoot then
        local desired = targetRoot.CFrame * CFrame.new(0, 4, -5)
        root.CFrame = desired
    end
end

function StandController:knockTarget(target)
    if not target then
        return true
    end
    if self:isKO(target) then
        return true
    end

    self:shootTarget(target)
    self:moveTowardTarget(target)
    return self:isKO(target)
end

function StandController:stompTarget(target)
    if self.mainEvent then
        pcall(function()
            self.mainEvent:FireServer("Stomp")
        end)
    end
end

function StandController:forceDance()
    if self.cachedDanceTrack then
        self.cachedDanceTrack.Looped = true
        self.cachedDanceTrack.Priority = Enum.AnimationPriority.Action
        if not self.cachedDanceTrack.IsPlaying then
            self.cachedDanceTrack:Play()
        end
        return
    end

    local humanoid = getHumanoid(getCharacter(getLocalPlayer()))
    if not humanoid then
        return
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = self.danceAnimationId
    local track = humanoid:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:Play()
    self.cachedDanceTrack = track
end

function StandController:ensureDancePlaying()
    if self.cachedDanceTrack and not self.cachedDanceTrack.IsPlaying then
        self.cachedDanceTrack:Play()
    elseif not self.cachedDanceTrack then
        self:forceDance()
    end
end

function StandController:bringTarget(target)
    local lpRoot = getRoot(getCharacter(getLocalPlayer()))
    local tRoot = getRoot(getCharacter(target))
    if lpRoot and tRoot then
        self:applyCFrame(tRoot, lpRoot.CFrame + Vector3.new(0, 3, 0))
    end
end

-- Loop updates
function StandController:updateVoidIdle(dt)
    if not self.state.voided then
        return
    end

    self:teleportVoid()
end

function StandController:updateFollow(dt)
    if self.state.voided then
        return
    end
    if self.state.stay then
        return
    end

    local owner = players():FindFirstChild(self.owner or "")
    local ownerRoot = getRoot(getCharacter(owner))
    local lpRoot = getRoot(getCharacter(getLocalPlayer()))
    if ownerRoot and lpRoot and self.state.followOwner then
        local targetCF = ownerRoot.CFrame * CFrame.new(0, 4, -5)
        lpRoot.CFrame = lpRoot.CFrame:Lerp(targetCF, 0.35)
    end
end

function StandController:updateAssist()
    if self.state.voided then
        return
    end
    for username in pairs(self.state.assistTargets) do
        local target = players():FindFirstChild(username)
        if target then
            self:moveTowardTarget(target)
        end
    end
end

function StandController:updateAura()
    if self.state.voided then
        return
    end
    if not self.state.aura then
        return
    end
    for _, target in ipairs(players():GetPlayers()) do
        if target ~= getLocalPlayer() and stringLower(target.Name) ~= stringLower(self.owner) then
            if not self.state.auraWhitelist[target.Name:lower()] and not self.state.whitelist[target.Name:lower()] then
                self:shootTarget(target)
            end
        end
    end
end

function StandController:updateCombat()
    if self.state.voided then
        return
    end
    if self.state.loopknockTarget then
        local target = players():FindFirstChild(self.state.loopknockTarget)
        if target then
            if self:knockTarget(target) then
                self.state.loopknockTarget = nil
            end
        end
    end

    if self.state.loopkillTarget then
        local target = players():FindFirstChild(self.state.loopkillTarget)
        if target then
            if self:knockTarget(target) then
                self:stompTarget(target)
                self:forceDance()
                self.state.loopkillTarget = nil
            end
        end
    end

    if self.state.akill and self.state.lastTarget then
        local target = players():FindFirstChild(self.state.lastTarget)
        if target and self:knockTarget(target) then
            self:stompTarget(target)
            self:forceDance()
        end
    end
end

function StandController:update(dt)
    self:ensureDancePlaying()
    self:updateVoidIdle(dt)
    self:updateFollow(dt)
    self:updateAssist()
    self:updateAura()
    self:updateCombat()
end

function StandController:startLoops()
    if self.connections.loop then
        self.connections.loop:Disconnect()
    end

    self.connections.loop = runService().Heartbeat:Connect(function(dt)
        self:update(dt)
    end)
end

function StandController:stopLoops()
    for _, conn in pairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
end

-- Command parsing
local function normalizeParts(message)
    local parts = {}
    for word in message:gmatch('%S+') do
        if word:sub(1, 1) == '"' and word:sub(-1) == '"' then
            table.insert(parts, word:sub(2, -2))
        else
            table.insert(parts, word)
        end
    end
    return parts
end

function StandController:executeCommand(command, args)
    local handler = self.commands[command]
    if handler then
        handler(self, args)
    else
        warnf("Unknown command: " .. command)
    end
end

function StandController:parseChat(msg, speaker)
    if type(msg) ~= "string" then
        return
    end
    if msg:sub(1, 1) ~= COMMAND_PREFIX then
        return
    end
    if not self:isAuthorized(speaker) then
        return
    end

    local parts = normalizeParts(msg)
    local raw = parts[1]
    if not raw or #raw < 2 then
        return
    end
    local command = raw:sub(2):lower()
    table.remove(parts, 1)
    self:executeCommand(command, parts)
end

function StandController:hookChat()
    local function bind(plr)
        if not plr or plr.Name:lower() ~= (self.owner or ""):lower() then
            return
        end
        if self.connections.chat then
            self.connections.chat:Disconnect()
        end
        self.connections.chat = plr.Chatted:Connect(function(msg)
            self:parseChat(msg, plr.Name)
        end)
    end

    for _, plr in ipairs(players():GetPlayers()) do
        bind(plr)
    end

    if self.connections.playerAdded then
        self.connections.playerAdded:Disconnect()
    end
    self.connections.playerAdded = players().PlayerAdded:Connect(bind)
end

-- Command handlers
local function summonHandler(self, args)
    self.state.voided = false
    self.state.followOwner = true
    self.state.stay = false

    local owner = players():FindFirstChild(self.owner or "")
    local ownerRoot = getRoot(getCharacter(owner))
    local root = getRoot(getCharacter(getLocalPlayer()))
    if ownerRoot and root then
        root.CFrame = ownerRoot.CFrame * CFrame.new(0, 4, -5)
    end

    if args[1] and args[1]:lower() == "stay" then
        self.state.followOwner = false
        self.state.stay = true
    end
end

local function stayHandler(self)
    self.state.voided = false
    self.state.followOwner = false
    self.state.stay = true

    local owner = players():FindFirstChild(self.owner or "")
    local ownerRoot = getRoot(getCharacter(owner))
    local root = getRoot(getCharacter(getLocalPlayer()))
    if ownerRoot and root then
        root.CFrame = ownerRoot.CFrame * CFrame.new(0, 4, -5)
    end
end

local function voidHandler(self)
    self.state.followOwner = false
    self.state.stay = false
    self.state.loopkillTarget = nil
    self.state.loopknockTarget = nil
    self.state.akill = false
    self.state.assistTargets = {}
    self.state.aura = false
    self.state.lastTarget = nil
    self.state.targetForBring = nil
    self.state.targetForStomp = nil
    self.state.targetForSky = nil
    self.state.targetForFling = nil
    self.state.voided = true
    self:teleportVoid()
end

local function repairHandler(self)
    self.state.loopkillTarget = nil
    self.state.loopknockTarget = nil
    self.state.akill = false
    self.state.aura = false
    self.state.assistTargets = {}
    self.state.followOwner = false
    self.state.stay = false
    self.state.voided = true
    self:teleportVoid()
end

local function rejoinHandler(self)
    local tp = game:GetService("TeleportService")
    pcall(function()
        tp:Teleport(game.PlaceId, getLocalPlayer())
    end)
end

local function maskHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        self.state.mask = true
    elseif state == "off" then
        self.state.mask = false
    else
        warnf("Usage: .mask on/off")
    end
end

local function sayHandler(self, args)
    local message = table.concat(args, " ")
    if message == "" then
        return
    end
    local chat = replicatedStorage():FindFirstChild("DefaultChatSystemChatEvents")
    if chat and chat:FindFirstChild("SayMessageRequest") then
        chat.SayMessageRequest:FireServer(message, "All")
    end
end

local function knockHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.lastTarget = target.Name
        self.state.loopknockTarget = target.Name
    end
end

local function bringHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.targetForBring = target.Name
        self:aimAtTarget(target)
        self:bringTarget(target)
    end
end

local function stompHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.targetForStomp = target.Name
        self:aimAtTarget(target)
        if self:knockTarget(target) then
            self:stompTarget(target)
        end
    end
end

local function loopkillHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.loopkillTarget = target.Name
        self.state.lastTarget = target.Name
    end
end

local function loopknockHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.loopknockTarget = target.Name
        self.state.lastTarget = target.Name
    end
end

local function akillHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        if self.state.lastTarget then
            self.state.akill = true
        else
            warnf("No target locked for akill")
        end
    elseif state == "off" then
        self.state.akill = false
    else
        warnf("Usage: .akill on/off")
    end
end

local function skyHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.targetForSky = target.Name
        local root = getRoot(getCharacter(target))
        if root then
            self:aimAtTarget(target)
            root.Velocity = Vector3.new(0, 200, 0)
        end
    end
end

local function flingHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.targetForFling = target.Name
        local root = getRoot(getCharacter(target))
        if root then
            self:aimAtTarget(target)
            root.Velocity = Vector3.new(300, 300, 300)
        end
    end
end

local function auraHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        self.state.aura = true
    elseif state == "off" then
        self.state.aura = false
    else
        warnf("Usage: .a on/off")
    end
end

local function awlHandler(self, args)
    local target = findPlayerByFragment(args[1]) or { Name = args[1] or "" }
    if target.Name ~= "" then
        self.state.auraWhitelist[target.Name:lower()] = true
    end
end

local function unawlHandler(self, args)
    local target = findPlayerByFragment(args[1]) or { Name = args[1] or "" }
    if target.Name ~= "" then
        self.state.auraWhitelist[target.Name:lower()] = nil
    end
end

local function sentryHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        self.state.sentry = true
    elseif state == "off" then
        self.state.sentry = false
    else
        warnf("Usage: .sentry on/off")
    end
end

local function bsentryHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        if self.state.sentry then
            self.state.bsentry = true
        else
            warnf("Enable sentry first")
        end
    elseif state == "off" then
        self.state.bsentry = false
    else
        warnf("Usage: .bsentry on/off")
    end
end

local function assistHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.assistTargets[target.Name] = true
    end
end

local function unassistHandler(self, args)
    local target = findPlayerByFragment(args[1])
    if target then
        self.state.assistTargets[target.Name] = nil
    end
end

local function fpHandler(self, args)
    local state = args[1] and args[1]:lower()
    if state == "on" then
        self.state.fp = true
    elseif state == "off" then
        self.state.fp = false
    else
        warnf("Usage: .fp on/off")
    end
end

local teleportLocations = {
    rifle = CFrame.new(-638.75, 18.85, -118.18),
    lmg = CFrame.new(-577.12, 5.48, -718.03),
    rev = CFrame.new(-587.53, 5.39, -753.71),
    db = CFrame.new(-1039.6, 18.85, -256.45),
    rpg = CFrame.new(118.66, -29.65, -272.35),
    armor = CFrame.new(528, 50, -637),
    mil = CFrame.new(470.88, 45.13, -620.63),
}

local function tpHandler(self, args)
    local location = args[1] and args[1]:lower()
    local cf = teleportLocations[location or ""]
    if not cf then
        return
    end
    local root = getRoot(getCharacter(getLocalPlayer()))
    if root then
        root.CFrame = cf
    end
end

local function tetherHandler(self, args)
    local p1 = findPlayerByFragment(args[1])
    local p2 = findPlayerByFragment(args[2])
    if p1 and p2 then
        local root = getRoot(getCharacter(p1))
        local targetRoot = getRoot(getCharacter(p2))
        if root and targetRoot then
            root.CFrame = targetRoot.CFrame + Vector3.new(0, 2, 0)
        end
    end
end

local function wlHandler(self, args)
    local target = findPlayerByFragment(args[1]) or { Name = args[1] or "" }
    if target.Name ~= "" then
        self:addWhitelist(target.Name)
    end
end

local function unwlHandler(self, args)
    local target = findPlayerByFragment(args[1]) or { Name = args[1] or "" }
    if target.Name ~= "" then
        self:removeWhitelist(target.Name)
    end
end

function StandController:initCommands()
    self.commands = {
        -- Summon & Void
        summon = summonHandler,
        s = stayHandler,
        v = voidHandler,

        -- Stand Maintenance
        repair = repairHandler,
        rejoin = rejoinHandler,
        mask = maskHandler,
        say = sayHandler,

        -- Combat
        d = knockHandler,
        b = bringHandler,
        l = loopkillHandler,
        lk = loopknockHandler,
        akill = akillHandler,
        sky = skyHandler,
        fling = flingHandler,
        a = auraHandler,
        awl = awlHandler,
        unawl = unawlHandler,

        -- Protection
        sentry = sentryHandler,
        bsentry = bsentryHandler,
        assist = assistHandler,
        unassist = unassistHandler,
        fp = fpHandler,

        -- Teleports
        tp = tpHandler,
        t = tetherHandler,

        -- Permissions
        wl = wlHandler,
        unwl = unwlHandler,
    }

    -- Map stomp to ".s <user>" without conflicting with stay command
    self.commands["s"] = function(controller, args)
        if args and #args > 0 then
            return stompHandler(controller, args)
        end
        return stayHandler(controller)
    end
end

function StandController:start()
    if not self.owner or self.owner == "" then
        warnf("Owner not configured")
        return
    end

    self:preloadAnimations()
    self:forceDance()
    self:autoAcquireGuns()
    self:equipAllowedTool()
    self:teleportVoid()
    self:hookChat()
    self:initCommands()
    self:startLoops()
    self:announce((env.Script or "MoonStand") .. " awaiting commands from " .. self.owner)
end

local controller = StandController.new()
controller:start()

return controller
