-- MoonStand core script (refactored)
local env = getgenv()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local lp = Players.LocalPlayer
local mainEvent = ReplicatedStorage:FindFirstChild("MainEvent")
local mouse = lp:GetMouse()

local function safe(f)
    local ok, res = pcall(f)
    return ok, res
end

local function normalizeName(name)
    if not name then
        return ""
    end
    return string.lower((name:gsub("[^%w]", "")))
end

-- build allowed guns
local allowedList = {}
for _, g in ipairs(env.Guns or env.Gguns or {}) do
    allowedList[normalizeName(g)] = true
end

local shop = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
local gunShopPaths = shop and {
    rifle = shop["[Rifle] - $1694"],
    aug = shop["[AUG] - $2131"],
    flintlock = shop["[Flintlock] - $1421"],
    flint = shop["[Flintlock] - $1421"],
    db = shop["[Double-Barrel SG] - $1475"],
    lmg = shop["[LMG] - $4098"],
}

local ammoShopPaths = shop and {
    rifle = shop["5 [Rifle Ammo] - $273"],
    aug = shop["90 [AUG Ammo] - $87"],
    flintlock = shop["6 [Flintlock Ammo] - $163"],
    flint = shop["6 [Flintlock Ammo] - $163"],
    db = shop["18 [Double-Barrel SG Ammo] - $55"],
    lmg = shop["200 [LMG Ammo] - $328"],
}

local maskShopPaths = shop and {
    mask = shop["[Breathing Mask] - $66"],
}

local StandController = {}
StandController.__index = StandController

function StandController.new()
    local self = setmetatable({}, StandController)
    self.ownerName = tostring(env.Owner or "")
    self.state = {
        mode = nil,
        voided = true,
        followOwner = false,
        stay = false,
        maskEnabled = false,
        loopkillTarget = nil,
        loopknockTarget = nil,
        aura = false,
        akill = false,
        auraWhitelist = {},
        whitelist = {},
    }
    self.connections = {}
    self.animationId = "rbxassetid://15610015346"
    self.animTrack = nil
    self.aimTarget = nil
    self.aimEnabled = false
    self.isBuyingGuns = false
    self.isBuyingAmmo = false
    self.reloadCooldown = 0
    self:setupSilentAimHook()
    return self
end

function StandController:disconnectAll()
    for _, c in ipairs(self.connections) do
        c:Disconnect()
    end
    self.connections = {}
end

function StandController:stopAllModes()
    self.state.mode = nil
    self.state.loopkillTarget = nil
    self.state.loopknockTarget = nil
    self.state.aura = false
    self.state.akill = false
    self.aimTarget = nil
    self.aimEnabled = false
end

function StandController:setMode(mode)
    self:stopAllModes()
    self.state.mode = mode
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

function StandController:ensureAnimation()
    local char = getChar(lp)
    local hum = getHumanoid(char)
    if not hum then
        return
    end
    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    if not self.animTrack or self.animTrack.Parent ~= animator then
        local anim = Instance.new("Animation")
        anim.AnimationId = self.animationId
        self.animTrack = animator:LoadAnimation(anim)
        self.animTrack.Priority = Enum.AnimationPriority.Action
        self.animTrack.Looped = true
        self.animTrack:Play()
    elseif not self.animTrack.IsPlaying then
        self.animTrack:Play()
    end
end

function StandController:teleport(cf)
    local root = getRoot(getChar(lp))
    if root then
        root.CFrame = cf
    end
end

function StandController:void()
    self:setMode("void")
    self.state.voided = true
    self.state.followOwner = false
    self.state.stay = false
    self.aimEnabled = false
    local root = getRoot(getChar(lp))
    if root then
        root.CFrame = CFrame.new(math.random(-5000000, 5000000), math.random(100000, 300000), math.random(-5000000, 5000000))
    end
end

function StandController:summon(follow)
    self:setMode("follow")
    self.state.voided = false
    self.state.followOwner = follow
    self.state.stay = not follow
    local owner = Players:FindFirstChild(self.ownerName)
    local ownerRoot = getRoot(getChar(owner))
    if ownerRoot then
        self:teleport(ownerRoot.CFrame * CFrame.new(0, 1.5, -5))
    end
end

function StandController:updateFollow()
    if not self.state.followOwner then
        return
    end
    local owner = Players:FindFirstChild(self.ownerName)
    local ownerRoot = getRoot(getChar(owner))
    local root = getRoot(getChar(lp))
    if ownerRoot and root then
        local target = ownerRoot.CFrame * CFrame.new(0, 1.5, -5)
        root.CFrame = root.CFrame:Lerp(target, 0.35)
    end
end

function StandController:addWhitelist(name)
    if name then
        self.state.whitelist[normalizeName(name)] = true
    end
end

function StandController:removeWhitelist(name)
    if name then
        self.state.whitelist[normalizeName(name)] = nil
    end
end

function StandController:isAuthorized(name)
    if not name then
        return false
    end
    if normalizeName(name) == normalizeName(self.ownerName) then
        return true
    end
    return self.state.whitelist[normalizeName(name)] == true
end

function StandController:resolvePlayer(query)
    if not query then
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

function StandController:findShopParts(model)
    if not model then
        return nil, nil
    end
    local head = model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart", true)
    local cd = model:FindFirstChildOfClass("ClickDetector")
    return head, cd
end

function StandController:unequipTools()
    local char = getChar(lp)
    local hum = getHumanoid(char)
    if hum then
        pcall(function()
            hum:UnequipTools()
        end)
    end
end

function StandController:autoBuyMask()
    if self.isBuyingMask or not maskShopPaths then
        return
    end
    self.isBuyingMask = true
    self:unequipTools()
    local char = getChar(lp)
    local root = getRoot(char)
    local model = maskShopPaths.mask
    local head, cd = self:findShopParts(model)
    if root and head and cd then
        local old = root.CFrame
        root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
        for _ = 1, 8 do
            fireclickdetector(cd)
            task.wait(0.1)
        end
        local backpack = lp:FindFirstChild("Backpack")
        local maskTool
        for _ = 1, 30 do
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    if item:IsA("Tool") and string.find(string.lower(item.Name), "mask") then
                        maskTool = item
                        break
                    end
                end
            end
            if maskTool then
                break
            end
            task.wait(0.1)
        end
        if maskTool then
            maskTool.Parent = char
            task.wait()
            pcall(function()
                maskTool:Activate()
            end)
        end
        if old then
            root.CFrame = old
        end
    end
    self.isBuyingMask = false
end

function StandController:autoBuyAmmo(gunName)
    if self.isBuyingAmmo or not gunName then
        return
    end
    local lower = normalizeName(gunName)
    local model = ammoShopPaths and ammoShopPaths[lower]
    if not model then
        return
    end
    self.isBuyingAmmo = true
    self:unequipTools()
    local char = getChar(lp)
    local root = getRoot(char)
    local head, cd = self:findShopParts(model)
    if root and head and cd then
        local old = root.CFrame
        root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
        for _ = 1, 8 do
            fireclickdetector(cd)
            task.wait(0.1)
        end
        if old then
            root.CFrame = old
        end
    end
    self.isBuyingAmmo = false
end

function StandController:autoBuyGuns()
    if self.isBuyingGuns or not gunShopPaths then
        return
    end
    self.isBuyingGuns = true
    self:unequipTools()
    local char = getChar(lp)
    local root = getRoot(char)
    local backpack = lp:FindFirstChild("Backpack")
    local function hasGun(lower)
        if char then
            for _, t in ipairs(char:GetChildren()) do
                if t:IsA("Tool") and normalizeName(t.Name) == lower then
                    return t
                end
            end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") and normalizeName(t.Name) == lower then
                    return t
                end
            end
        end
        return nil
    end
    for gunKey, path in pairs(gunShopPaths) do
        if allowedList[gunKey] and not hasGun(gunKey) then
            local head, cd = self:findShopParts(path)
            if root and head and cd then
                local old = root.CFrame
                root.CFrame = head.CFrame + Vector3.new(0, 3, 0)
                for _ = 1, 8 do
                    fireclickdetector(cd)
                    task.wait(0.1)
                end
                for _ = 1, 40 do
                    local tool = hasGun(gunKey)
                    if tool then
                        tool.Parent = char
                        break
                    end
                    task.wait(0.1)
                end
                if old then
                    root.CFrame = old
                end
            end
        end
    end
    self.isBuyingGuns = false
end

function StandController:equipAnyAllowed(allowBuyDuringCombat)
    local char = getChar(lp)
    local backpack = lp:FindFirstChild("Backpack")
    local function findAllowed()
        if char then
            for _, t in ipairs(char:GetChildren()) do
                if t:IsA("Tool") and allowedList[normalizeName(t.Name)] then
                    return t
                end
            end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") and allowedList[normalizeName(t.Name)] then
                    return t
                end
            end
        end
        return nil
    end
    local tool = findAllowed()
    local canBuy = allowBuyDuringCombat or (not self:isInCombat())
    if not tool and canBuy and not self.isBuyingGuns then
        self:autoBuyGuns()
        for _ = 1, 40 do
            tool = findAllowed()
            if tool then
                break
            end
            task.wait(0.1)
        end
    end
    if tool and tool.Parent ~= char then
        tool.Parent = char
    end
    return tool
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
    return (ko and ko.Value) or (dead and dead.Value)
end

function StandController:getNearestTarget()
    local best, dist
    local char = getChar(lp)
    local root = getRoot(char)
    if not root then
        return nil
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not self:isKO(plr) then
            local pRoot = getRoot(plr.Character)
            if pRoot then
                local d = (pRoot.Position - root.Position).Magnitude
                if not dist or d < dist then
                    dist = d
                    best = plr
                end
            end
        end
    end
    return best
end

function StandController:isInCombat()
    return self.state.mode == "kill" or self.state.mode == "knock" or self.state.mode == "loopkill" or self.state.mode == "loopknock" or self.state.mode == "aura" or self.state.mode == "akill"
end

function StandController:updateAim(target)
    self.aimTarget = target
    self.aimEnabled = target ~= nil
end

function StandController:predictPosition(part)
    if not part then
        return nil
    end
    local ping = 0
    local net = Stats:FindFirstChild("PerformanceStats")
    if net and net:FindFirstChild("Ping") then
        ping = tonumber(net.Ping:GetValue()) or 0
    end
    local factor = math.clamp(ping / 1000, 0, 0.35)
    local vel = part.AssemblyLinearVelocity or part.Velocity or Vector3.new()
    return part.Position + (vel * factor)
end

function StandController:setupSilentAimHook()
    local mt = getrawmetatable(game)
    if not mt then
        return
    end
    local old = mt.__index
    setreadonly(mt, false)
    mt.__index = function(t, k)
        if self.aimEnabled and t == mouse and (k == "Hit" or k == "Target") then
            local target = self.aimTarget
            if target and target.Character then
                local part = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Head")
                if part and not self:isKO(target) then
                    local pos = self:predictPosition(part) or part.Position
                    return CFrame.new(pos)
                end
            end
        end
        return old(t, k)
    end
    setreadonly(mt, true)
end

function StandController:autoReload(tool)
    if not tool or tick() - self.reloadCooldown < 0.5 then
        return
    end
    local ammo
    for _, n in ipairs({"Ammo", "AmmoCount", "Clip", "AmmoInGun"}) do
        local v = tool:FindFirstChild(n)
        if v and v.Value ~= nil then
            ammo = v
            break
        end
    end
    if ammo and ammo.Value <= 0 and mainEvent then
        self.reloadCooldown = tick()
        mainEvent:FireServer("Reload", tool)
        task.wait(0.2)
    end
end

function StandController:fireTool(tool)
    if tool and tool:IsA("Tool") then
        tool:Activate()
    end
end

function StandController:shootTarget(target, doStomp)
    if not target then
        return
    end
    self:setMode(doStomp and "kill" or "knock")
    self.state.voided = false
    self:updateAim(target)
    local char = getChar(lp)
    local root = getRoot(char)
    local tool = self:equipAnyAllowed(true)
    if not tool then
        return
    end
    while target and target.Character and root and not self:isKO(target) and self.state.mode do
        local tRoot = getRoot(target.Character)
        if not tRoot then
            break
        end
        tool = self:equipAnyAllowed() or tool
        self:autoReload(tool)
        root.CFrame = tRoot.CFrame * CFrame.new(0, 0, -3)
        self:fireTool(tool)
        RunService.Heartbeat:Wait()
        char = getChar(lp)
        root = getRoot(char)
    end
    self:updateAim(nil)
    if doStomp and target and self:isKO(target) then
        local tRoot = getRoot(target.Character)
        local r = getRoot(getChar(lp))
        if tRoot and r and mainEvent then
            r.CFrame = tRoot.CFrame * CFrame.new(0, 0, -2)
            mainEvent:FireServer("Stomp")
        end
    end
end

function StandController:loopKill(target)
    self:setMode("loopkill")
    while self.state.mode == "loopkill" and target do
        self:shootTarget(target, true)
        if self.state.mode ~= "loopkill" then
            break
        end
        task.wait(0.2)
    end
end

function StandController:loopKnock(target)
    self:setMode("loopknock")
    while self.state.mode == "loopknock" and target do
        self:shootTarget(target, false)
        if self.state.mode ~= "loopknock" then
            break
        end
        task.wait(0.2)
    end
end

function StandController:bring(target)
    if not target then
        return
    end
    local tRoot = getRoot(target.Character)
    local root = getRoot(getChar(lp))
    if root and tRoot then
        self:setMode("bring")
        tRoot.CFrame = root.CFrame * CFrame.new(0, 0, -2)
    end
end

function StandController:handleCommand(cmd, args)
    if cmd == "v" then
        self:stopAllModes()
        self:void()
        return
    elseif cmd == "summon" then
        self:stopAllModes()
        self:summon(true)
        return
    elseif cmd == "mask" then
        local state = args[1] and args[1]:lower()
        if state == "on" then
            self:stopAllModes()
            self.state.maskEnabled = true
            self:autoBuyMask()
            self:autoBuyGuns()
        elseif state == "off" then
            self.state.maskEnabled = false
        end
        return
    end
    if cmd == "s" then
        if args[1] then
            local target = self:resolvePlayer(args[1])
            if target then
                self:stopAllModes()
                self:shootTarget(target, true)
            end
        end
        return
    end
    if cmd == "d" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            self:shootTarget(target, false)
        end
        return
    end
    if cmd == "l" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            task.spawn(function()
                self:loopKill(target)
            end)
        end
        return
    end
    if cmd == "lk" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            task.spawn(function()
                self:loopKnock(target)
            end)
        end
        return
    end
    if cmd == "akill" then
        local state = args[1] and args[1]:lower()
        if state == "on" then
            self:setMode("akill")
        else
            self:stopAllModes()
        end
        return
    end
    if cmd == "a" then
        local state = args[1] and args[1]:lower()
        if state == "on" then
            self:setMode("aura")
        else
            self:stopAllModes()
        end
        return
    end
    if cmd == "awl" then
        if args[1] then
            self.state.auraWhitelist[normalizeName(args[1])] = true
        end
        return
    end
    if cmd == "unawl" then
        if args[1] then
            self.state.auraWhitelist[normalizeName(args[1])] = nil
        end
        return
    end
    if cmd == "b" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            self:bring(target)
        end
        return
    end
    if cmd == "sky" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            self:sky(target)
        end
        return
    end
    if cmd == "fling" then
        local target = self:resolvePlayer(args[1])
        if target then
            self:stopAllModes()
            self:fling(target)
        end
        return
    end
    if cmd == "say" then
        local msg = table.concat(args, " ")
        if #msg > 0 then
            local evt = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            if evt and evt:FindFirstChild("SayMessageRequest") then
                evt.SayMessageRequest:FireServer(msg, "All")
            end
        end
        return
    end
    if cmd == "wl" then
        self:addWhitelist(args[1])
        return
    end
    if cmd == "unwl" then
        self:removeWhitelist(args[1])
        return
    end
    if cmd == "repair" then
        self:stopAllModes()
        self:ensureAnimation()
        return
    end
    if cmd == "rejoin" then
        game:GetService("TeleportService"):Teleport(game.PlaceId)
        return
    end
end

function StandController:parseChat(msg, speaker)
    if type(msg) ~= "string" or msg:sub(1, 1) ~= "." then
        return
    end
    if not self:isAuthorized(speaker) then
        return
    end
    local args = {}
    for w in msg:gmatch("%S+") do
        table.insert(args, w)
    end
    local command = args[1]:sub(2):lower()
    table.remove(args, 1)
    self:handleCommand(command, args)
end

function StandController:bindChat()
    self:disconnectAll()
    local function hook(plr)
        if plr and normalizeName(plr.Name) == normalizeName(self.ownerName) then
            local conn = plr.Chatted:Connect(function(msg)
                self:parseChat(msg, plr.Name)
            end)
            table.insert(self.connections, conn)
        end
    end
    hook(Players:FindFirstChild(self.ownerName))
    table.insert(self.connections, Players.PlayerAdded:Connect(function(plr)
        hook(plr)
    end))
end

function StandController:startLoops()
    if self.loopConn then
        self.loopConn:Disconnect()
    end
    self.loopConn = RunService.Heartbeat:Connect(function()
        self:ensureAnimation()
        if not self.state.voided then
            self:updateFollow()
        end
        if self.state.maskEnabled then
            self:autoBuyMask()
        end
        if self.state.mode == "akill" then
            local t = self:getNearestTarget()
            if t then
                self:shootTarget(t, true)
            end
        elseif self.state.mode == "aura" then
            local victim = nil
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and not self.state.auraWhitelist[normalizeName(plr.Name)] and not self:isKO(plr) then
                    victim = plr
                    break
                end
            end
            if victim then
                self:shootTarget(victim, true)
            end
        end
    end)
end

function StandController:start()
    self:bindChat()
    self:void()
    self:ensureAnimation()
    self:autoBuyMask()
    self:autoBuyGuns()
    if self.charConn then
        self.charConn:Disconnect()
    end
    self.charConn = lp.CharacterAdded:Connect(function()
        task.wait(0.25)
        self:ensureAnimation()
        if self.state.maskEnabled then
            self:autoBuyMask()
        end
        self:autoBuyGuns()
    end)
    self:startLoops()
end

local controller = StandController.new()
controller:start()
