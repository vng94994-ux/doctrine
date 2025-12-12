local env = getgenv()
local COMMAND_PREFIX = "."

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

local function normalizeName(name)
    return string.lower((name or ""):gsub("[^%w]", ""))
end

local gunShopPaths = {
    rifle = workspace.Ignored.Shop["[Rifle] - $1694"],
    aug = workspace.Ignored.Shop["[AUG] - $2131"],
    flint = workspace.Ignored.Shop["[Flintlock] - $1421"],
    flintlock = workspace.Ignored.Shop["[Flintlock] - $1421"],
    db = workspace.Ignored.Shop["[Double-Barrel SG] - $1475"],
    lmg = workspace.Ignored.Shop["[LMG] - $4098"],
}

local ammoShopPaths = {
    rifle = workspace.Ignored.Shop["5 [Rifle Ammo] - $273"],
    aug = workspace.Ignored.Shop["90 [AUG Ammo] - $87"],
    flint = workspace.Ignored.Shop["6 [Flintlock Ammo] - $163"],
    flintlock = workspace.Ignored.Shop["6 [Flintlock Ammo] - $163"],
    db = workspace.Ignored.Shop["18 [Double-Barrel SG Ammo] - $55"],
    lmg = workspace.Ignored.Shop["200 [LMG Ammo] - $328"],
}

local maskShopPaths = {
    mask = workspace.Ignored.Shop["[Breathing Mask] - $66"],
}

local gunAliases = {
    rifle = { "rifle", "ar" },
    aug = { "aug" },
    flint = { "flint", "flintlock" },
    flintlock = { "flint", "flintlock" },
    db = { "db", "doublebarrelsg", "doublebarrel" },
    lmg = { "lmg" },
}

local function normalizeGunKey(name)
    local key = normalizeName(name)
    for canon, aliases in pairs(gunAliases) do
        for _, alias in ipairs(aliases) do
            if key == normalizeName(alias) then
                return canon
            end
        end
    end
    return key
end

local function getChar(plr)
    return plr and plr.Character
end

local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function resolvePlayer(query)
    if not query or query == "" then
        return nil
    end
    local lower = string.lower(query)
    for _, plr in ipairs(Players:GetPlayers()) do
        if string.lower(plr.Name) == lower or string.lower(plr.DisplayName) == lower then
            return plr
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if string.find(string.lower(plr.Name), lower, 1, true) or string.find(string.lower(plr.DisplayName), lower, 1, true) then
            return plr
        end
    end
    return nil
end

local StandController = {}
StandController.__index = StandController

function StandController.new()
    local self = setmetatable({}, StandController)
    self.ownerName = tostring(env.Owner or "")
    self.allowedGuns = {}
    self.gunAliasLookup = {}
    self.allowedCanon = {}
    for _, g in ipairs(env.Guns or env.Gguns or {}) do
        local canon = normalizeGunKey(g)
        self.allowedCanon[canon] = true
        for _, alias in ipairs(gunAliases[canon] or { canon }) do
            local norm = normalizeName(alias)
            self.allowedGuns[norm] = true
            self.gunAliasLookup[norm] = canon
        end
    end

    self.state = {
        followOwner = false,
        stay = false,
        voided = true,
        loopkillTarget = nil,
        loopknockTarget = nil,
        aura = false,
        akill = false,
        assistTargets = {},
        whitelist = {},
        auraWhitelist = {},
        sentry = false,
        bsentry = false,
        fp = false,
        maskEnabled = false,
        lastTarget = nil,
        abortCombat = false,
        inCombat = false,
    }

    self.aimlockEnabled = true
    self.aimlockActive = false
    self.aimlockTarget = nil
    self.aimPart = "HumanoidRootPart"
    self.predictionVelocity = 6
    self.aimRadius = 30
    self.teamCheck = false

    self.voidConnection = nil
    self.followConnection = nil
    self.heartbeatConnection = nil
    self.chatConnections = {}

    self.mainEvent = ReplicatedStorage:FindFirstChild("MainEvent")

    self.danceAnimationId = "rbxassetid://15610015346"
    self.animationTrack = nil

    self.isBuyingGuns = false
    self.isBuyingAmmo = false
    self.isBuyingMask = false

    self.commandHandlers = {}
    self:initCommands()
    self:initializeAimlock()

    return self
end

function StandController:announce(msg)
    print("[Stand] " .. tostring(msg))
end

function StandController:isAuthorized(plrName)
    if not plrName then
        return false
    end
    if string.lower(plrName) == string.lower(self.ownerName) then
        return true
    end
    return self.state.whitelist[string.lower(plrName)] == true
end

function StandController:addWhitelist(user)
    if not user then
        return
    end
    self.state.whitelist[string.lower(user)] = true
end

function StandController:removeWhitelist(user)
    if not user then
        return
    end
    self.state.whitelist[string.lower(user)] = nil
end

function StandController:applyVoid()
    local char = getChar(lp)
    local root = getRoot(char)
    if root then
        root.CFrame = CFrame.new(
            math.random(-5000000, 5000000),
            math.random(100000, 300000),
            math.random(-5000000, 5000000)
        )
    end
    self.state.voided = true
end

function StandController:voidLoop()
    if self.voidConnection then
        self.voidConnection:Disconnect()
    end
    self.voidConnection = RunService.Heartbeat:Connect(function()
        if not self.state.voided then
            return
        end
        local char = getChar(lp)
        local root = getRoot(char)
        if root then
            root.CFrame = CFrame.new(
                math.random(-5000000, 5000000),
                math.random(100000, 300000),
                math.random(-5000000, 5000000)
            )
        end
        self:ensureDancePlaying()
    end)
end

function StandController:ensureDancePlaying()
    local char = getChar(lp)
    local hum = getHumanoid(char)
    if not hum then
        return
    end
    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    if not self.animationTrack or self.animationTrack.Parent ~= animator then
        local anim = Instance.new("Animation")
        anim.AnimationId = self.danceAnimationId
        self.animationTrack = animator:LoadAnimation(anim)
        self.animationTrack.Looped = true
        self.animationTrack.Priority = Enum.AnimationPriority.Action
        self.animationTrack:Play()
    elseif not self.animationTrack.IsPlaying then
        self.animationTrack:Play()
    end
end

function StandController:startFollow()
    self.state.voided = false
    self.state.followOwner = true
    if self.followConnection then
        self.followConnection:Disconnect()
    end
    self.followConnection = RunService.Heartbeat:Connect(function()
        if not self.state.followOwner then
            return
        end
        local owner = Players:FindFirstChild(self.ownerName)
        local ownerChar = getChar(owner)
        local ownerRoot = getRoot(ownerChar)
        local char = getChar(lp)
        local root = getRoot(char)
        if ownerRoot and root then
            local target = ownerRoot.CFrame * CFrame.new(0, 1.5, -5)
            root.CFrame = root.CFrame:Lerp(target, 0.35)
            self:ensureDancePlaying()
        end
    end)
end

function StandController:staySummon()
    self.state.voided = false
    self.state.followOwner = false
    if self.followConnection then
        self.followConnection:Disconnect()
    end
    local owner = Players:FindFirstChild(self.ownerName)
    local ownerChar = getChar(owner)
    local ownerRoot = getRoot(ownerChar)
    local root = getRoot(getChar(lp))
    if ownerRoot and root then
        root.CFrame = ownerRoot.CFrame * CFrame.new(0, 1.5, -5)
        self:ensureDancePlaying()
    end
end

function StandController:stopFollow()
    self.state.followOwner = false
    if self.followConnection then
        self.followConnection:Disconnect()
        self.followConnection = nil
    end
end

function StandController:interruptCombat()
    self.state.loopkillTarget = nil
    self.state.loopknockTarget = nil
    self.state.aura = false
    self.state.akill = false
    self.state.abortCombat = true
    self:stopAimlock()
end

function StandController:initializeAimlock()
    self.aimlockEnabled = true
    self.aimlockActive = false
    self.aimlockTarget = nil
    self.aimPart = env.AimPart or "HumanoidRootPart"
    self.predictionVelocity = env.PredictionVelocity or 6
    self.aimRadius = env.AimRadius or 30
    self.teamCheck = env.TeamCheck or false
end

function StandController:getNearestTarget()
    local candidates = {}
    local diffs = {}
    local cam = workspace.CurrentCamera
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character and plr.Character:FindFirstChild("Head") then
            if not self.teamCheck or plr.Team ~= lp.Team then
                local dist = (plr.Character.Head.Position - cam.CFrame.Position).Magnitude
                local ray = Ray.new(cam.CFrame.Position, (lp:GetMouse().Hit.p - cam.CFrame.Position).unit * dist)
                local _, hitPos = workspace:FindPartOnRay(ray, workspace)
                local diff = math.floor((hitPos - plr.Character.Head.Position).Magnitude)
                candidates[plr.Name .. tostring(dist)] = {plr = plr, diff = diff}
                table.insert(diffs, diff)
            end
        end
    end
    if #diffs == 0 then
        return nil
    end
    local best = math.min(unpack(diffs))
    if best > self.aimRadius then
        return nil
    end
    for _, v in pairs(candidates) do
        if v.diff == best then
            return v.plr
        end
    end
    return nil
end

function StandController:startAimlock(target)
    if not self.aimlockEnabled then
        return
    end
    if not target or not target.Character then
        return
    end
    self.aimlockActive = true
    self.aimlockTarget = target
end

function StandController:stopAimlock()
    self.aimlockActive = false
    self.aimlockTarget = nil
end

function StandController:updateAimlock()
    if not self.aimlockActive then
        return
    end
    local target = self.aimlockTarget
    local char = getChar(lp)
    local root = getRoot(char)
    if not target or not target.Character or not root then
        self:stopAimlock()
        return
    end
    local aimPart = target.Character:FindFirstChild(self.aimPart) or getRoot(target.Character) or target.Character:FindFirstChild("Head")
    if not aimPart then
        self:stopAimlock()
        return
    end
    local predicted = aimPart.Position + (aimPart.Velocity / self.predictionVelocity)
    root.CFrame = CFrame.lookAt(root.Position, predicted)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool:FindFirstChild("Handle") then
        tool.Handle.CFrame = CFrame.lookAt(tool.Handle.Position, predicted)
    end
end

function StandController:isKO(plr)
    if not plr or not plr.Character then
        return false
    end
    local effects = plr.Character:FindFirstChild("BodyEffects")
    if not effects then
        return false
    end
    local ko = effects:FindFirstChild("K.O")
    local dead = effects:FindFirstChild("Dead")
    return (ko and ko.Value) or (dead and dead.Value) or false
end

function StandController:equipGunByName(name)
    if not name then
        return nil
    end
    local canon = normalizeGunKey(name)
    if not self.allowedCanon[canon] then
        return nil
    end
    local char = getChar(lp)
    local backpack = lp:FindFirstChild("Backpack")
    local function find()
        if char then
            for _, t in ipairs(char:GetChildren()) do
                local canonForTool = self.gunAliasLookup[normalizeName(t.Name)]
                if t:IsA("Tool") and canonForTool == canon then
                    return t
                end
            end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                local canonForTool = self.gunAliasLookup[normalizeName(t.Name)]
                if t:IsA("Tool") and canonForTool == canon then
                    return t
                end
            end
        end
        return nil
    end
    local tool = find()
    if tool and char and tool.Parent ~= char then
        tool.Parent = char
    end
    return tool, canon
end

function StandController:ensureAmmo(tool, gunKey)
    if not tool then
        return tool, gunKey
    end
    local ammoValue
    for _, name in ipairs({ "Ammo", "AmmoCount", "Clip", "AmmoInGun" }) do
        local v = tool:FindFirstChild(name)
        if v and v.Value ~= nil then
            ammoValue = v
            break
        end
    end
    if ammoValue and ammoValue.Value <= 0 then
        self:autoBuyAmmo(gunKey)
        local refreshed, canon = self:equipGunByName(gunKey)
        if refreshed then
            tool = refreshed
            gunKey = canon or gunKey
        end
    end
    return tool, gunKey
end

local function getDetectorAndHead(model)
    if not model then
        return nil, nil
    end
    local head = model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart", true)
    local detector = model:FindFirstChildOfClass("ClickDetector") or (head and head:FindFirstChildOfClass("ClickDetector"))
    return detector, head
end

local function fireDetector(detector)
    if detector and fireclickdetector then
        fireclickdetector(detector)
    end
end

function StandController:toolMatchesAllowed(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end
    local canon = self.gunAliasLookup[normalizeName(tool.Name)]
    if canon and self.allowedCanon[canon] then
        return canon
    end
    return nil
end

function StandController:hasAnyAllowedGun()
    local char = getChar(lp)
    local backpack = lp:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if self:toolMatchesAllowed(t) then
                return true
            end
        end
    end
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if self:toolMatchesAllowed(t) then
                return true
            end
        end
    end
    return false
end

function StandController:fireWeapon()
    local char = getChar(lp)
    if not char then
        return
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
    end
end

function StandController:equipAnyAllowed(allowPurchase)
    local char = getChar(lp)
    if not char then
        return nil
    end
    local backpack = lp:FindFirstChild("Backpack")

    local function isAllowed(tool)
        return self:toolMatchesAllowed(tool)
    end

    local function findAllowed()
        if char then
            for _, t in ipairs(char:GetChildren()) do
                local canon = isAllowed(t)
                if canon then
                    return t, canon
                end
            end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                local canon = isAllowed(t)
                if canon then
                    return t, canon
                end
            end
        end
        return nil, nil
    end

    local tool, canon = findAllowed()
    if not tool and allowPurchase and not self.isBuyingGuns then
        self:autoBuyGuns()
        for _ = 1, 80 do
            tool, canon = findAllowed()
            if tool then
                break
            end
            task.wait(0.1)
        end
    end

    if tool and tool.Parent ~= char then
        tool.Parent = char
    end
    return tool, canon
end

function StandController:shootTarget(target)
    if not target then
        return
    end
    self.state.abortCombat = false
    self.state.inCombat = true
    local gun, gunKey = self:equipAnyAllowed(true)
    if not gun then
        self.state.inCombat = false
        return
    end

    self.state.voided = false
    self:startAimlock(target)

    local char = getChar(lp)
    local root = getRoot(char)

    while root and target and target.Character and not self:isKO(target) and not self.state.abortCombat do
        local targetRoot = getRoot(target.Character)
        if not targetRoot then
            break
        end

        gun, gunKey = self:ensureAmmo(gun, gunKey)
        if not gun then
            gun, gunKey = self:equipAnyAllowed(true)
        end
        if not gun then
            break
        end

        root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -2)
        if gun.Parent ~= char then
            gun.Parent = char
        end
        gun:Activate()
        RunService.Heartbeat:Wait()
        char = getChar(lp)
        root = getRoot(char)
        self:ensureDancePlaying()
    end

    self:stopAimlock()
    self.state.inCombat = false
    self.state.abortCombat = false
end

function StandController:knock(target)
    if not target then
        return
    end
    self:startAimlock(target)
    self:shootTarget(target)
end

function StandController:kill(target)
    if not target then
        return
    end
    self:startAimlock(target)
    self:shootTarget(target)
    if self:isKO(target) then
        self:stomp(target)
    end
end

function StandController:stomp(target)
    local root = getRoot(getChar(lp))
    local targetRoot = getRoot(getChar(target))
    if root and targetRoot then
        root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -2)
    end
    if self.mainEvent then
        self.mainEvent:FireServer("Stomp")
    end
end

function StandController:bring(target)
    local root = getRoot(getChar(lp))
    local troot = getRoot(getChar(target))
    if root and troot then
        troot.CFrame = root.CFrame * CFrame.new(0, 0, -2)
    end
end

function StandController:sky(target)
    local troot = getRoot(getChar(target))
    if troot then
        troot.Velocity = Vector3.new(0, 200, 0)
    end
end

function StandController:fling(target)
    local troot = getRoot(getChar(target))
    if troot then
        troot.Velocity = Vector3.new(500, 500, 500)
    end
end

function StandController:autoBuyMask()
    if self.isBuyingMask then
        return
    end
    self.isBuyingMask = true

    local char = getChar(lp)
    local root = getRoot(char)
    local hum = getHumanoid(char)
    if not char or not root or not hum then
        self.isBuyingMask = false
        return
    end

    self.state.voided = false
    hum:UnequipTools()

    local function locateMask()
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Accessory") and string.find(string.lower(item.Name), "mask") then
                return item
            end
            if item:IsA("Tool") and string.find(string.lower(item.Name), "mask") then
                return item
            end
        end
        local bp = lp:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") and string.find(string.lower(item.Name), "mask") then
                    return item
                end
            end
        end
        return nil
    end

    local owned = locateMask()
    if not owned then
        local model = maskShopPaths.mask
        local detector, head = getDetectorAndHead(model)
        if detector and head then
            local original = root.CFrame
            root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
            for _ = 1, 10 do
                fireDetector(detector)
                task.wait(0.12)
            end
            for _ = 1, 50 do
                owned = locateMask()
                if owned then
                    break
                end
                task.wait(0.1)
            end
            root.CFrame = original
        end
    end

    if owned and owned:IsA("Tool") then
        owned.Parent = char
        task.wait(0.1)
        pcall(function()
            owned:Activate()
        end)
    elseif owned and owned:IsA("Accessory") then
        owned.Parent = char
    end

    self:autoBuyGuns()
    self.isBuyingMask = false
end

function StandController:autoBuyGuns()
    if self.isBuyingGuns then
        return
    end
    self.isBuyingGuns = true

    local char = getChar(lp)
    local root = getRoot(char)
    local hum = getHumanoid(char)
    if not char or not root or not hum then
        self.isBuyingGuns = false
        return
    end

    self.state.voided = false
    hum:UnequipTools()
    task.wait(0.05)
    local backpack = lp:FindFirstChild("Backpack")

    local function locateGun(canon)
        if char then
            for _, t in ipairs(char:GetChildren()) do
                local matchCanon = self:toolMatchesAllowed(t)
                if matchCanon == canon then
                    return t
                end
            end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                local matchCanon = self:toolMatchesAllowed(t)
                if matchCanon == canon then
                    return t
                end
            end
        end
        return nil
    end

    local requested = env.Guns or env.Gguns or {}
    for _, gunName in ipairs(requested) do
        local canon = normalizeGunKey(gunName)
        if self.allowedCanon[canon] then
            local existing = locateGun(canon)
            if not existing then
                local model = gunShopPaths[canon]
                local detector, head = getDetectorAndHead(model)
                if detector and head then
                    local original = root.CFrame
                    root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
                    for _ = 1, 10 do
                        fireDetector(detector)
                        task.wait(0.1)
                    end
                    for _ = 1, 60 do
                        existing = locateGun(canon)
                        if existing then
                            break
                        end
                        task.wait(0.1)
                    end
                    if original then
                        root.CFrame = original
                    end
                end
            end
            if existing and existing.Parent ~= char then
                existing.Parent = char
            end
        end
    end

    self.isBuyingGuns = false
    self:ensureDancePlaying()
end

function StandController:autoBuyAmmo(gunName)
    if self.isBuyingAmmo then
        return
    end
    self.isBuyingAmmo = true

    local char = getChar(lp)
    local root = getRoot(char)
    local hum = getHumanoid(char)
    if not char or not root or not hum then
        self.isBuyingAmmo = false
        return
    end

    self.state.voided = false
    hum:UnequipTools()
    local lower = gunName and normalizeGunKey(gunName)
    if not lower then
        self.isBuyingAmmo = false
        return
    end

    if not ammoShopPaths[lower] then
        self.isBuyingAmmo = false
        return
    end

    local model = ammoShopPaths[lower]
    local detector, head = getDetectorAndHead(model)
    if detector and head then
        local original = root.CFrame
        root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
        for _ = 1, 8 do
            fireDetector(detector)
            task.wait(0.1)
        end
        task.wait(0.2)
        local refreshed = self:equipGunByName(lower)
        if refreshed and refreshed.Parent ~= char then
            refreshed.Parent = char
        end
        if original then
            root.CFrame = original
        end
    end

    self.isBuyingAmmo = false
    self:ensureDancePlaying()
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
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    local command = args[1]:sub(2):lower()
    table.remove(args, 1)
    self:executeCommand(command, args, speaker)
end

function StandController:executeCommand(cmd, args)
    local handler = self.commandHandlers[cmd]
    if handler then
        handler(self, args)
    end
end

function StandController:initCommands()
    local handlers = {}

    handlers["summon"] = function(self)
        self:interruptCombat()
        self:startFollow()
    end

    handlers["s"] = function(self, args)
        if args and args[1] then
            local target = resolvePlayer(args[1])
            if target then
                self:stomp(target)
                return
            end
        end
        self:interruptCombat()
        self:staySummon()
    end

    handlers["v"] = function(self)
        self:interruptCombat()
        self.state.followOwner = false
        self.state.assistTargets = {}
        self:stopFollow()
        self:applyVoid()
    end

    handlers["repair"] = function(self)
        self:stopAimlock()
        self.state.loopkillTarget = nil
        self.state.loopknockTarget = nil
        self.state.aura = false
        self.state.akill = false
        self:ensureDancePlaying()
    end

    handlers["rejoin"] = function()
        game:GetService("TeleportService"):Teleport(game.PlaceId)
    end

    handlers["mask"] = function(self, args)
        if args[1] and args[1]:lower() == "on" then
            self.state.maskEnabled = true
            self:autoBuyMask()
            self:autoBuyGuns()
        else
            self.state.maskEnabled = false
        end
    end

    handlers["say"] = function(self, args)
        local message = table.concat(args, " ")
        if #message > 0 then
            game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, "All")
        end
    end

    handlers["d"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self.state.abortCombat = false
            self.state.lastTarget = target
            self:startAimlock(target)
            self:knock(target)
        end
    end

    handlers["l"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self.state.abortCombat = false
            self.state.loopkillTarget = target
        end
    end

    handlers["lk"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self.state.abortCombat = false
            self.state.loopknockTarget = target
        end
    end

    handlers["akill"] = function(self, args)
        local state = args[1] and args[1]:lower()
        self.state.akill = state == "on"
        if self.state.akill then
            self.state.abortCombat = false
        end
    end

    handlers["a"] = function(self, args)
        local state = args[1] and args[1]:lower()
        self.state.aura = state == "on"
        if self.state.aura then
            self.state.abortCombat = false
        end
    end

    handlers["awl"] = function(self, args)
        if args[1] then
            self.state.auraWhitelist[string.lower(args[1])] = true
        end
    end

    handlers["unawl"] = function(self, args)
        if args[1] then
            self.state.auraWhitelist[string.lower(args[1])] = nil
        end
    end

    handlers["wl"] = function(self, args)
        self:addWhitelist(args[1])
    end

    handlers["unwl"] = function(self, args)
        self:removeWhitelist(args[1])
    end

    handlers["b"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:bring(target)
        end
    end

    handlers["sky"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:sky(target)
        end
    end

    handlers["fling"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:fling(target)
        end
    end

    handlers["tp"] = function(self, args)
        local locations = {
            rifle = CFrame.new(-591.824158, 5.46046877, -744.731628),
            armor = CFrame.new(528, 50, -637),
            mil = CFrame.new(-1039.59985, 18.8513641, -256.449951),
        }
        local loc = args[1] and locations[string.lower(args[1])]
        local root = getRoot(getChar(lp))
        if loc and root then
            root.CFrame = loc
        end
    end

    handlers["t"] = function(self, args)
        local p1 = resolvePlayer(args[1] or "")
        local p2 = resolvePlayer(args[2] or "")
        if p1 and p2 then
            local r2 = getRoot(getChar(p2))
            if r2 then
                local r1 = getRoot(getChar(p1))
                if r1 then
                    r1.CFrame = r2.CFrame + Vector3.new(0, 2, 0)
                end
            end
        end
    end

    handlers["sentry"] = function(self, args)
        local state = args[1] and args[1]:lower() == "on"
        self.state.sentry = state
    end

    handlers["bsentry"] = function(self, args)
        local state = args[1] and args[1]:lower() == "on"
        self.state.bsentry = state
    end

    handlers["assist"] = function(self, args)
        local target = resolvePlayer(args[1] or "")
        if target then
            self.state.assistTargets[string.lower(target.Name)] = target
        end
    end

    handlers["unassist"] = function(self, args)
        if args[1] then
            self.state.assistTargets[string.lower(args[1])] = nil
        end
    end

    handlers["fp"] = function(self, args)
        local state = args[1] and args[1]:lower() == "on"
        self.state.fp = state
    end

    self.commandHandlers = handlers
end

function StandController:loopSystems()
    if self.heartbeatConnection then
        self.heartbeatConnection:Disconnect()
    end
    self.heartbeatConnection = RunService.Heartbeat:Connect(function()
        self:ensureDancePlaying()
        self:updateAimlock()
        if self.state.abortCombat then
            self.state.loopkillTarget = nil
            self.state.loopknockTarget = nil
            return
        end
        if self.state.loopkillTarget then
            if self:isKO(self.state.loopkillTarget) then
                self:stomp(self.state.loopkillTarget)
                self.state.loopkillTarget = nil
            else
                self:kill(self.state.loopkillTarget)
            end
        end
        if self.state.loopknockTarget then
            if self:isKO(self.state.loopknockTarget) then
                self.state.loopknockTarget = nil
            else
                self:knock(self.state.loopknockTarget)
            end
        end
        if self.state.akill then
            local target = self:getNearestTarget()
            if target then
                self:kill(target)
            end
        end
        if self.state.aura then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and not self.state.auraWhitelist[string.lower(plr.Name)] then
                    if not self:isKO(plr) then
                        self:kill(plr)
                    end
                end
            end
        end
    end)
end

function StandController:connectChat()
    for _, c in ipairs(self.chatConnections) do
        c:Disconnect()
    end
    self.chatConnections = {}
    local function hook(plr)
        if plr and string.lower(plr.Name) == string.lower(self.ownerName) then
            local conn = plr.Chatted:Connect(function(msg)
                self:parseChat(msg, plr.Name)
            end)
            table.insert(self.chatConnections, conn)
        end
    end
    hook(Players:FindFirstChild(self.ownerName))
    table.insert(self.chatConnections, Players.PlayerAdded:Connect(function(plr)
        if string.lower(plr.Name) == string.lower(self.ownerName) then
            hook(plr)
        end
    end))
end

function StandController:start()
    self:announce("Waiting for commands from " .. self.ownerName)
    self.state.abortCombat = false
    self:applyVoid()
    self:voidLoop()
    self:ensureDancePlaying()
    self:connectChat()
    self:loopSystems()
    self:autoBuyGuns()
    table.insert(self.chatConnections, lp.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 5)
        self:ensureDancePlaying()
        self:autoBuyGuns()
        if self.state.maskEnabled then
            self:autoBuyMask()
        end
    end))
end

local controller = StandController.new()
controller:start()
