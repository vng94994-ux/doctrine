local env = getgenv()
local COMMAND_PREFIX = "."

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local Stats = game:GetService("Stats")

local lp = Players.LocalPlayer
local Mouse = lp:GetMouse()

local Aiming = getgenv().Aiming or {
    Enabled = false,
    ShowFOV = true,
    FOV = 60,
    FOVSides = 12,
    FOVColour = Color3.fromRGB(231, 84, 128),
    VisibleCheck = true,
    HitChance = 100,
    Selected = nil,
    SelectedPart = nil,
    TargetPart = { "Head", "HumanoidRootPart" },
    Ignored = {
        Teams = {{ Team = lp.Team, TeamColor = lp.TeamColor }},
        Players = { lp },
    },
}
getgenv().Aiming = Aiming

do
    pcall(function()
        local circle = Drawing.new("Circle")
        circle.Thickness = 2
        circle.Filled = false
        Aiming.FOVCircle = circle
    end)
end

function Aiming.Update()
    local circle = Aiming.FOVCircle
    if not circle then
        return
    end
    circle.Visible = Aiming.ShowFOV and Aiming.Enabled
    circle.Radius = Aiming.FOV * 3
    local inset = GuiService:GetGuiInset()
    circle.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    circle.Color = Aiming.FOVColour
end

RunService.Heartbeat:Connect(function()
    if Aiming.Enabled then
        Aiming.Update()
    end
end)

local function isVisible(part)
    if not Aiming.VisibleCheck then
        return true
    end
    local origin = Workspace.CurrentCamera.CFrame.Position
    local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    local ray = Ray.new(origin, direction)
    local hit = Workspace:FindPartOnRayWithIgnoreList(ray, { lp.Character })
    return hit == nil or hit:IsDescendantOf(lp.Character) or hit:IsDescendantOf(part.Parent)
end

local function getClosestPart(char)
    for _, name in ipairs(Aiming.TargetPart) do
        local p = char:FindFirstChild(name)
        if p then
            return p
        end
    end
    return nil
end

local function canSelect(plr)
    if plr == lp then
        return false
    end
    for _, ignored in ipairs(Aiming.Ignored.Players or {}) do
        if ignored == plr then
            return false
        end
    end
    if plr.Team and lp.Team and plr.Team == lp.Team then
        return false
    end
    return true
end

function Aiming.GetClosestPlayerToCursor()
    local closest, distance = nil, Aiming.FOV * 3
    for _, plr in ipairs(Players:GetPlayers()) do
        if canSelect(plr) and plr.Character then
            local part = getClosestPart(plr.Character)
            if part then
                local pos, onScreen = Workspace.CurrentCamera:WorldToScreenPoint(part.Position)
                if onScreen then
                    local diff = (Vector2.new(pos.X, pos.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                    if diff <= distance and isVisible(part) then
                        closest = plr
                        distance = diff
                    end
                end
            end
        end
    end
    Aiming.Selected = closest
    Aiming.SelectedPart = closest and getClosestPart(closest.Character) or nil
    return closest
end

function Aiming.Check()
    return Aiming.Enabled and Aiming.Selected and Aiming.SelectedPart
end

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

local function getPingSeconds()
    local value = nil
    pcall(function()
        local perf = Stats.PerformanceStats:FindFirstChild("Ping")
        if perf and perf.GetValue then
            value = perf:GetValue()
        end
        if not value then
            local dataPing = Stats.Network.ServerStatsItem["Data Ping"]
            if dataPing and dataPing.GetValue then
                value = dataPing:GetValue()
            end
        end
    end)
    return (value or 50) / 1000
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
local controllerRef

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

    self.silentActive = false
    self.silentPredictionScalar = 1
    self.reloadCooldown = {}

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
        if not self.state.voided or self.activeMode ~= "void" then
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
    self:setMode("summon")
    self.state.voided = false
    self.state.followOwner = true
    if self.followConnection then
        self.followConnection:Disconnect()
    end
    self.followConnection = RunService.Heartbeat:Connect(function()
        if self.activeMode ~= "summon" or not self.state.followOwner then
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
    self:setMode("stay")
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
    self.state.inCombat = false
    self:stopAimlock()
end

function StandController:stopAllModes()
    self:interruptCombat()
    self.isBuyingAmmo = false
    self.isBuyingGuns = false
    self.isBuyingMask = false
    self.state.followOwner = false
    self.state.stay = false
    self.state.assistTargets = {}
    self.activeMode = nil
    Aiming.Enabled = false
    if self.followConnection then
        self.followConnection:Disconnect()
        self.followConnection = nil
    end
end

function StandController:setMode(mode)
    self:stopAllModes()
    self.activeMode = mode
end

function StandController:initializeAimlock()
    self.aimlockEnabled = true
    self.aimlockTarget = nil
end

function StandController:getNearestTarget()
    return Aiming.GetClosestPlayerToCursor()
end

function StandController:startAimlock(target)
    if not self.aimlockEnabled then
        return
    end
    if not target or not target.Character then
        return
    end
    self.silentActive = true
    Aiming.Enabled = true
    Aiming.Selected = target
    Aiming.SelectedPart = target.Character and (target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Head"))
    self.aimlockTarget = target
end

function StandController:stopAimlock()
    Aiming.Enabled = false
    Aiming.Selected = nil
    Aiming.SelectedPart = nil
    self.aimlockTarget = nil
    self.silentActive = false
end

function StandController:updateAimlock()
    if not Aiming.Check() then
        return
    end
    local char = getChar(lp)
    local root = getRoot(char)
    if not root then
        self:stopAimlock()
        return
    end
    local part = Aiming.SelectedPart
    if not part then
        self:stopAimlock()
        return
    end
    local predicted = part.Position + (part.AssemblyLinearVelocity * ((getPingSeconds() * self.predictionVelocity) * self.silentPredictionScalar))
    root.CFrame = CFrame.lookAt(root.Position, predicted)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool:FindFirstChild("Handle") then
        tool.Handle.CFrame = CFrame.lookAt(tool.Handle.Position, predicted)
    end
end

function StandController:getTargetPart()
    local target = self.aimlockTarget
    if not target or not target.Character or self:isKO(target) then
        return nil
    end
    local part = target.Character:FindFirstChild(self.aimPart)
    if not part then
        part = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Head") or target.Character:FindFirstChild("HumanoidRootPart")
    end
    return part
end

function StandController:getPredictedAimPosition()
    local part = self:getTargetPart()
    if not part then
        return nil
    end
    local pingFactor = getPingSeconds() * self.predictionVelocity * self.silentPredictionScalar
    local vel = part.AssemblyLinearVelocity or part.Velocity
    local predicted = part.Position + (vel * pingFactor)
    return predicted, part
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
        self:reloadTool(tool)
        task.wait(0.15)
        if ammoValue.Value <= 0 then
            self:autoBuyAmmo(gunKey)
            local refreshed, canon = self:equipGunByName(gunKey)
            if refreshed then
                tool = refreshed
                gunKey = canon or gunKey
            end
        end
    end
    return tool, gunKey
end

function StandController:reloadTool(tool)
    if not tool or not self.mainEvent then
        return
    end
    local key = tool
    local now = tick()
    if self.reloadCooldown[key] and (now - self.reloadCooldown[key] < 0.6) then
        return
    end
    self.reloadCooldown[key] = now
    pcall(function()
        self.mainEvent:FireServer("Reload", tool)
    end)
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
    local priority = { summon = true, v = true, mask = true }
    if priority[command] then
        self:stopAllModes()
        self:executeCommand(command, args, speaker)
        return
    end

    self:stopAllModes()
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
        self:setMode("summon")
        self:startFollow()
    end

    handlers["s"] = function(self, args)
        if args and args[1] then
            local target = resolvePlayer(args[1])
            if target then
                self:setMode("stomp")
                self:stomp(target)
            end
        end
    end

    handlers["v"] = function(self)
        self:setMode("void")
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
        self:setMode("mask")
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
            self:setMode("combat")
            self.state.lastTarget = target
            self:startAimlock(target)
            self:knock(target)
        end
    end

    handlers["l"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:setMode("loopkill")
            self.state.loopkillTarget = target
        end
    end

    handlers["lk"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:setMode("loopknock")
            self.state.loopknockTarget = target
        end
    end

    handlers["akill"] = function(self, args)
        local state = args[1] and args[1]:lower()
        self:setMode(state == "on" and "akill" or nil)
        self.state.akill = state == "on"
    end

    handlers["a"] = function(self, args)
        local state = args[1] and args[1]:lower()
        self:setMode(state == "on" and "aura" or nil)
        self.state.aura = state == "on"
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
            self:setMode("bring")
            self:bring(target)
        end
    end

    handlers["sky"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:setMode("sky")
            self:sky(target)
        end
    end

    handlers["fling"] = function(self, args)
        local target = resolvePlayer(args[1])
        if target then
            self:setMode("fling")
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
        if self.activeMode == "loopkill" and self.state.loopkillTarget then
            if self:isKO(self.state.loopkillTarget) then
                self:stomp(self.state.loopkillTarget)
                self.state.loopkillTarget = nil
                self:stopAimlock()
            else
                self:kill(self.state.loopkillTarget)
            end
        elseif self.activeMode == "loopknock" and self.state.loopknockTarget then
            if self:isKO(self.state.loopknockTarget) then
                self.state.loopknockTarget = nil
                self:stopAimlock()
            else
                self:knock(self.state.loopknockTarget)
            end
        elseif self.activeMode == "akill" and self.state.akill then
            local target = self:getNearestTarget()
            if target then
                self:startAimlock(target)
                self:kill(target)
            end
        elseif self.activeMode == "aura" and self.state.aura then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and not self.state.auraWhitelist[string.lower(plr.Name)] and not self:isKO(plr) then
                    self:startAimlock(plr)
                    self:kill(plr)
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
    self:setMode("void")
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
controllerRef = controller

do
    local mt = getrawmetatable(game)
    if mt and setreadonly then
        local old = mt.__index
        setreadonly(mt, false)
        mt.__index = function(t, k)
            if controllerRef and controllerRef.silentActive and (k == "Hit" or k == "Target") and t == Mouse then
                local pos, part = controllerRef:getPredictedAimPosition()
                if pos and part then
                    if k == "Hit" then
                        return CFrame.new(pos)
                    elseif k == "Target" then
                        return part
                    end
                end
            end
            if old then
                return old(t, k)
            end
            return nil
        end
        setreadonly(mt, true)
    end
end
