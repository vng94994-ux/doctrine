local env = getgenv()
local COMMAND_PREFIX = "."

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local StandController = {}
StandController.__index = StandController

function StandController.new()
    local self = setmetatable({}, StandController)
    self.ownerName = tostring(env.Owner or "")
    self.allowedGuns = {}
    for _, g in ipairs(env.Gguns or {}) do
        self.allowedGuns[string.lower(g)] = true
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

    self.commandHandlers = {}
    self:initCommands()
    self:initializeAimlock()

    return self
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
    if not self.animationTrack then
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
    local lower = string.lower(name)
    if not self.allowedGuns[lower] then
        return nil
    end
    local char = getChar(lp)
    local backpack = lp:FindFirstChild("Backpack")
    local tool = nil
    if char then
        tool = char:FindFirstChildWhichIsA("Tool", true)
        if tool and string.lower(tool.Name) == lower then
            return tool
        end
    end
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") and string.lower(t.Name) == lower then
                tool = t
                break
            end
        end
    end
    if tool and char then
        tool.Parent = char
    end
    return tool
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

function StandController:shootTarget(target)
    if not target then
        return
    end
    self:startAimlock(target)
    local char = getChar(lp)
    local root = getRoot(char)
    local targetRoot = getRoot(getChar(target))
    while targetRoot and root and not self:isKO(target) do
        root.CFrame = CFrame.lookAt(root.Position, targetRoot.Position)
        self:fireWeapon()
        RunService.Heartbeat:Wait()
        targetRoot = getRoot(getChar(target))
    end
    self:stopAimlock()
end

function StandController:knock(target)
    if not target then
        return
    end
    local gun = self:equipAnyAllowed()
    if not gun then
        return
    end
    self:shootTarget(target)
end

function StandController:kill(target)
    if not target then
        return
    end
    local gun = self:equipAnyAllowed()
    if not gun then
        return
    end
    self:shootTarget(target)
    if self:isKO(target) then
        self:stomp(target)
    end
end

function StandController:equipAnyAllowed()
    local char = getChar(lp)
    if not char then
        return nil
    end
    local backpack = lp:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and self.allowedGuns[string.lower(t.Name)] then
                return t
            end
        end
    end
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if t:IsA("Tool") and self.allowedGuns[string.lower(t.Name)] then
                t.Parent = char
                return t
            end
        end
    end
    self:autoBuyGuns()
    return nil
end

function StandController:stomp(target)
    local root = getRoot(getChar(lp))
    local targetRoot = getRoot(getChar(target))
    if root and targetRoot then
        root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -2)
    end
    local mainEvent = self.mainEvent
    if mainEvent then
        mainEvent:FireServer("Stomp")
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
    local shop = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
    if not shop then
        return
    end
    local mask
    for _, item in ipairs(shop:GetChildren()) do
        if string.find(item.Name, "Mask") and item:FindFirstChildOfClass("ClickDetector") then
            mask = item
            break
        end
    end
    local char = getChar(lp)
    local root = getRoot(char)
    if mask and root then
        root.CFrame = mask:FindFirstChildWhichIsA("BasePart").CFrame + Vector3.new(0, 3, 0)
        for _ = 1, 5 do
            fireclickdetector(mask:FindFirstChildOfClass("ClickDetector"))
        end
        self:applyVoid()
    end
end

function StandController:autoBuyGuns()
    local shop = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
    if not shop then
        return
    end
    local char = getChar(lp)
    local root = getRoot(char)
    if not char or not root then
        return
    end
    for gunName, _ in pairs(self.allowedGuns) do
        local has = false
        for _, t in ipairs(lp.Backpack:GetChildren()) do
            if t:IsA("Tool") and string.lower(t.Name) == gunName then
                has = true
                break
            end
        end
        if not has then
            for _, item in ipairs(shop:GetChildren()) do
                if string.find(string.lower(item.Name), gunName) and item:FindFirstChildOfClass("ClickDetector") then
                    local part = item:FindFirstChildWhichIsA("BasePart") or item
                    root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                    for _ = 1, 6 do
                        fireclickdetector(item:FindFirstChildOfClass("ClickDetector"))
                    end
                    break
                end
            end
        end
    end
    self:applyVoid()
end

function StandController:autoBuyAmmo(gunName)
    local shop = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
    if not shop then
        return
    end
    local char = getChar(lp)
    local root = getRoot(char)
    if not char or not root then
        return
    end
    local ammoKeywords = {
        rifle = "Rifle Ammo",
        aug = "AUG Ammo",
        flintlock = "Flintlock Ammo",
        db = "Double-Barrel",
        lmg = "LMG Ammo",
    }
    local keyword = ammoKeywords[gunName]
    if not keyword then
        return
    end
    for _, item in ipairs(shop:GetChildren()) do
        if string.find(string.lower(item.Name), string.lower(keyword)) and item:FindFirstChildOfClass("ClickDetector") then
            local part = item:FindFirstChildWhichIsA("BasePart") or item
            root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
            for _ = 1, 6 do
                fireclickdetector(item:FindFirstChildOfClass("ClickDetector"))
            end
            break
        end
    end
    self:applyVoid()
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
        self:startFollow()
    end

    handlers["s"] = function(self, args)
        if args and args[1] then
            local target = Players:FindFirstChild(args[1])
            if target then
                self:stomp(target)
                return
            end
        end
        self:staySummon()
    end

    handlers["v"] = function(self)
        self.state.followOwner = false
        self.state.loopkillTarget = nil
        self.state.loopknockTarget = nil
        self.state.aura = false
        self.state.akill = false
        self:stopAimlock()
        self:stopFollow()
        self.state.assistTargets = {}
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
        local target = Players:FindFirstChild(args[1])
        if target then
            self.state.lastTarget = target
            self:startAimlock(target)
            self:knock(target)
        end
    end

    handlers["l"] = function(self, args)
        local target = Players:FindFirstChild(args[1])
        if target then
            self.state.loopkillTarget = target
        end
    end

    handlers["lk"] = function(self, args)
        local target = Players:FindFirstChild(args[1])
        if target then
            self.state.loopknockTarget = target
        end
    end

    handlers["akill"] = function(self, args)
        local state = args[1] and args[1]:lower()
        self.state.akill = state == "on"
    end

    handlers["a"] = function(self, args)
        local state = args[1] and args[1]:lower()
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
        local target = Players:FindFirstChild(args[1])
        if target then
            self:bring(target)
        end
    end

    handlers["sky"] = function(self, args)
        local target = Players:FindFirstChild(args[1])
        if target then
            self:sky(target)
        end
    end

    handlers["fling"] = function(self, args)
        local target = Players:FindFirstChild(args[1])
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
        local p1 = Players:FindFirstChild(args[1] or "")
        local p2 = Players:FindFirstChild(args[2] or "")
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
        local target = Players:FindFirstChild(args[1] or "")
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
        if plr and plr.Name == self.ownerName then
            local conn = plr.Chatted:Connect(function(msg)
                self:parseChat(msg, plr.Name)
            end)
            table.insert(self.chatConnections, conn)
        end
    end
    hook(Players:FindFirstChild(self.ownerName))
    table.insert(self.chatConnections, Players.PlayerAdded:Connect(function(plr)
        if plr.Name == self.ownerName then
            hook(plr)
        end
    end))
end

function StandController:start()
    self:announce("Waiting for commands from " .. self.ownerName)
    self:applyVoid()
    self:voidLoop()
    self:ensureDancePlaying()
    self:connectChat()
    self:loopSystems()
    self:autoBuyGuns()
end

local controller = StandController.new()
controller:start()
