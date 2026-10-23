--[[
    SleepyHub Orion — Rivals
    Best-effort combat core + weapon mods + Orion UI with feature icons
]]

if getgenv and getgenv().SleepyOrionUnload then
    pcall(getgenv().SleepyOrionUnload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local ICONS = {
    silent   = "rbxassetid://6031075931",
    aimbot   = "rbxassetid://6034684937",
    gun      = "rbxassetid://6034684937",
    melee    = "rbxassetid://6034508291",
    esp      = "rbxassetid://6034287594",
    recoil   = "rbxassetid://6031229350",
    settings = "rbxassetid://6031280882",
}

local FLAGS = {
    silent_enabled = true,
    silent_fov = 180,
    silent_show_fov = true,
    silent_team_check = true,
    silent_wall_check = false,
    silent_hitpart = "Head",
    silent_prediction = 0.155,
    silent_hitchance = 100,
    silent_priority = "Crosshair",
    silent_sticky = true,

    aimbot_enabled = false,
    aimbot_fov = 140,
    aimbot_show_fov = false,
    aimbot_smooth = 0.14,
    aimbot_team_check = true,
    aimbot_wall_check = false,
    aimbot_hitpart = "Head",
    aimbot_prediction = 0.13,
    aimbot_key = Enum.KeyCode.E,
    aimbot_hold = true,

    no_recoil = true,
    no_spread = true,
    anti_shake = true,
    recoil_scale = 0,

    melee_enabled = false,
    melee_range = 14,
    melee_face = true,
    melee_cooldown = 0.1,

    esp_enabled = true,
    esp_team = false,
    esp_chams = true,
    esp_color = Color3.fromRGB(0, 162, 255),
    esp_enemy = Color3.fromRGB(255, 70, 70),

    max_distance = 1400,
}

local STATE = {
    target = nil,
    stickyTarget = nil,
    stickyUntil = 0,
    aimbotDown = false,
    mouseDown = false,
    lastMelee = 0,
    chams = {},
    unloaded = false,
    recoilAnchor = nil,
}

local function charOf(p) return p and p.Character end
local function rootOf(p)
    local c = charOf(p)
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function humOf(p)
    local c = charOf(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function isAlive(p)
    local h = humOf(p)
    return h and h.Health > 0
end

local function sameTeam(p)
    if LocalPlayer.Team and p.Team and LocalPlayer.Team == p.Team then return true end
    local a = LocalPlayer:GetAttribute("Team") or LocalPlayer:GetAttribute("TeamId")
    local b = p:GetAttribute("Team") or p:GetAttribute("TeamId")
    if a ~= nil and b ~= nil then return a == b end
    return false
end

local function getHitPart(character, mode)
    if not character then return nil end
    mode = mode or "Head"
    if mode == "Head" then
        return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    elseif mode == "HRP" then
        return character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")
    elseif mode == "Closest" then
        local mousePos = UserInputService:GetMouseLocation()
        local best, bestD
        for _, name in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso" }) do
            local part = character:FindFirstChild(name)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                    if not bestD or d < bestD then bestD, best = d, part end
                end
            end
        end
        return best or character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    end
    return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function visibleCheck(fromPos, toPart)
    if not toPart then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if LocalPlayer.Character then exclude[#exclude + 1] = LocalPlayer.Character end
    if toPart.Parent then exclude[#exclude + 1] = toPart.Parent end
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    local hit = Workspace:Raycast(fromPos, toPart.Position - fromPos, params)
    if not hit then return true end
    return hit.Instance and toPart.Parent and hit.Instance:IsDescendantOf(toPart.Parent)
end

local velHistory = {}
local function predictPos(part, t, pl)
    if not part then return nil end
    t = math.max(t or 0, 0)
    local vel = part.AssemblyLinearVelocity
    local acc = Vector3.zero
    if pl then
        local key = pl.UserId
        local hist = velHistory[key]
        local now = os.clock()
        if hist and now - hist.t < 0.2 then
            local dt = math.max(now - hist.t, 1 / 120)
            acc = (vel - hist.v) / dt
            if acc.Magnitude > 120 then acc = acc.Unit * 120 end
        end
        velHistory[key] = { v = vel, t = now }
    end
    return part.Position + vel * t + acc * (0.5 * t * t)
end

local function screenDistToMouse(worldPos)
    local sp = Camera:WorldToViewportPoint(worldPos)
    local mousePos = UserInputService:GetMouseLocation()
    if sp.Z < 0 then return math.huge, false end
    return (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude, true
end

local function scoreTarget(pl, part, mode)
    local myRoot = rootOf(LocalPlayer)
    if not myRoot or not part then return math.huge end
    local predT = mode == "silent" and FLAGS.silent_prediction or FLAGS.aimbot_prediction
    local pred = predictPos(part, predT, pl)
    local dist3 = (pred - myRoot.Position).Magnitude
    if dist3 > FLAGS.max_distance then return math.huge end
    local sd = select(1, screenDistToMouse(pred))
    local useFov = mode == "silent" and FLAGS.silent_fov or FLAGS.aimbot_fov
    if sd > useFov then return math.huge end
    if mode == "silent" and FLAGS.silent_wall_check and not visibleCheck(Camera.CFrame.Position, part) then
        return math.huge
    end
    if mode == "aimbot" and FLAGS.aimbot_wall_check and not visibleCheck(Camera.CFrame.Position, part) then
        return math.huge
    end
    local hum = humOf(pl)
    local health = hum and hum.Health or 100
    local priority = FLAGS.silent_priority
    if priority == "Distance" then return dist3 end
    if priority == "Health" then return health * 2 + dist3 * 0.02 end
    return sd * 1.55 + dist3 * 0.015 + health * 0.008
end

local function getBestTarget(mode)
    local teamFlag = mode == "silent" and FLAGS.silent_team_check or FLAGS.aimbot_team_check
    local hitMode = mode == "silent" and FLAGS.silent_hitpart or FLAGS.aimbot_hitpart

    if mode == "silent" and FLAGS.silent_sticky and STATE.stickyTarget and os.clock() < STATE.stickyUntil then
        local pl = STATE.stickyTarget
        if isAlive(pl) and not (teamFlag and sameTeam(pl)) then
            local part = getHitPart(charOf(pl), hitMode)
            if part and scoreTarget(pl, part, mode) < math.huge then
                return pl, part
            end
        end
        STATE.stickyTarget = nil
    end

    local best, bestScore, bestPart
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) and not (teamFlag and sameTeam(pl)) then
            local part = getHitPart(charOf(pl), hitMode)
            if part then
                local sc = scoreTarget(pl, part, mode)
                if sc < (bestScore or math.huge) then
                    bestScore, best, bestPart = sc, pl, part
                end
            end
        end
    end
    if mode == "silent" and best then
        STATE.stickyTarget = best
        STATE.stickyUntil = os.clock() + 0.35
    end
    STATE.target = best
    return best, bestPart
end

local function drawing(class, props)
    local ok, obj = pcall(function() return Drawing.new(class) end)
    if not ok or not obj then return nil end
    for k, v in pairs(props or {}) do pcall(function() obj[k] = v end) end
    return obj
end

local silentFov = drawing("Circle", {
    Thickness = 1.6, NumSides = 64, Radius = 180, Filled = false,
    Color = Color3.fromRGB(0, 162, 255), Transparency = 0.85, Visible = false,
})
local aimbotFov = drawing("Circle", {
    Thickness = 1.6, NumSides = 64, Radius = 140, Filled = false,
    Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7, Visible = false,
})

local function updateFovCircles()
    local mp = UserInputService:GetMouseLocation()
    if silentFov then
        silentFov.Position = mp
        silentFov.Radius = FLAGS.silent_fov
        silentFov.Visible = FLAGS.silent_enabled and FLAGS.silent_show_fov and not STATE.unloaded
    end
    if aimbotFov then
        aimbotFov.Position = mp
        aimbotFov.Radius = FLAGS.aimbot_fov
        aimbotFov.Visible = FLAGS.aimbot_enabled and FLAGS.aimbot_show_fov and not STATE.unloaded
    end
end

local function silentAimPoint()
    if not FLAGS.silent_enabled then return nil end
    if FLAGS.silent_hitchance < 100 and math.random(1, 100) > FLAGS.silent_hitchance then
        return nil
    end
    local _, part = getBestTarget("silent")
    if not part then return nil end
    return predictPos(part, FLAGS.silent_prediction, STATE.target), part
end

pcall(function()
    local mt = getrawmetatable(game)
    if not mt then return end
    local oldIndex = mt.__index
    if type(setreadonly) == "function" then setreadonly(mt, false) end
    local wrapper = function(self, key)
        if not STATE.unloaded and FLAGS.silent_enabled and self == Mouse and (key == "Hit" or key == "Target") then
            local point, part = silentAimPoint()
            if point then
                if key == "Hit" then return CFrame.new(point) end
                if key == "Target" and part then return part end
            end
        end
        return oldIndex(self, key)
    end
    mt.__index = (newcclosure and newcclosure(wrapper)) or wrapper
    if type(setreadonly) == "function" then setreadonly(mt, true) end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        STATE.mouseDown = true
        STATE.recoilAnchor = Camera.CFrame
    end
    if gp then return end
    if input.KeyCode == FLAGS.aimbot_key then STATE.aimbotDown = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        STATE.mouseDown = false
        STATE.recoilAnchor = nil
    end
    if input.KeyCode == FLAGS.aimbot_key then STATE.aimbotDown = false end
end)

RunService.RenderStepped:Connect(function(dt)
    if STATE.unloaded then return end
    updateFovCircles()
    if FLAGS.aimbot_enabled and (not FLAGS.aimbot_hold or STATE.aimbotDown) then
        local _, part = getBestTarget("aimbot")
        if part then
            local pred = predictPos(part, FLAGS.aimbot_prediction, STATE.target)
            local goal = CFrame.new(Camera.CFrame.Position, pred)
            local smooth = math.clamp(FLAGS.aimbot_smooth, 0.02, 1)
            Camera.CFrame = Camera.CFrame:Lerp(goal, 1 - math.exp(-dt / smooth))
        end
    end
end)

local function stripShake()
    if not FLAGS.anti_shake and not FLAGS.no_recoil then return end
    pcall(function()
        for _, name in ipairs({ "CameraShake", "Shake", "Recoil", "CameraRecoil", "ShakeCamera" }) do
            local o = Camera:FindFirstChild(name)
            if o then o:Destroy() end
        end
    end)
end

local function weaponAttributePatch()
    local char = LocalPlayer.Character
    if not char then return end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            if FLAGS.no_recoil then
                for _, n in ipairs({ "Recoil", "RecoilStrength", "VerticalRecoil", "HorizontalRecoil", "CameraRecoil" }) do
                    local v = tool:FindFirstChild(n)
                    if v and v:IsA("NumberValue") then pcall(function() v.Value = FLAGS.recoil_scale end) end
                    pcall(function() tool:SetAttribute(n, FLAGS.recoil_scale) end)
                end
            end
            if FLAGS.no_spread then
                for _, n in ipairs({ "Spread", "Bloom", "Accuracy", "HipSpread", "AimSpread", "MaxSpread" }) do
                    local v = tool:FindFirstChild(n)
                    if v and v:IsA("NumberValue") then pcall(function() v.Value = 0 end) end
                    pcall(function() tool:SetAttribute(n, 0) end)
                end
            end
        end
    end
end

RunService.RenderStepped:Connect(function()
    if STATE.unloaded then return end
    stripShake()
    weaponAttributePatch()
    if FLAGS.no_recoil and STATE.mouseDown and STATE.recoilAnchor then
        local cur = Camera.CFrame
        local anchor = STATE.recoilAnchor
        local x0 = select(1, anchor:ToOrientation())
        local _, y1 = cur:ToOrientation()
        local xCur = select(1, cur:ToOrientation())
        local scale = math.clamp(FLAGS.recoil_scale, 0, 1)
        local x = x0 * (1 - scale) + xCur * scale
        local pos = cur.Position
        Camera.CFrame = CFrame.fromOrientation(x, y1, 0) + pos
        STATE.recoilAnchor = CFrame.fromOrientation(x0, y1, 0) + pos
    end
end)

local function tryMelee()
    if not FLAGS.melee_enabled then return end
    local now = os.clock()
    if now - STATE.lastMelee < FLAGS.melee_cooldown then return end
    local myRoot = rootOf(LocalPlayer)
    if not myRoot then return end
    local best, bestDist
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) and not (FLAGS.silent_team_check and sameTeam(pl)) then
            local r = rootOf(pl)
            if r then
                local d = (r.Position - myRoot.Position).Magnitude
                if d <= FLAGS.melee_range and (not bestDist or d < bestDist) then
                    bestDist, best = d, pl
                end
            end
        end
    end
    if not best then return end
    local tr = rootOf(best)
    if not tr then return end
    if FLAGS.melee_face then
        local behind = tr.Position - tr.CFrame.LookVector * 2.5
        myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(behind.X, myRoot.Position.Y, behind.Z))
    end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
    STATE.lastMelee = now
end

RunService.Heartbeat:Connect(function()
    if not STATE.unloaded then pcall(tryMelee) end
end)

local function clearEsp(pl)
    if STATE.chams[pl] then
        pcall(function() STATE.chams[pl]:Destroy() end)
        STATE.chams[pl] = nil
    end
end

local function ensureChams(pl)
    if not FLAGS.esp_chams then clearEsp(pl) return end
    local char = charOf(pl)
    if not char then return end
    local h = STATE.chams[pl]
    if h and h.Parent then
        h.Adornee = char
        h.FillColor = sameTeam(pl) and FLAGS.esp_color or FLAGS.esp_enemy
        return
    end
    local hl = Instance.new("Highlight")
    hl.Name = "_SleepyEsp"
    hl.Adornee = char
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.FillColor = sameTeam(pl) and FLAGS.esp_color or FLAGS.esp_enemy
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function() hl.Parent = (gethui and gethui()) or CoreGui end)
    if not hl.Parent then
        hl.Parent = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 1)
    end
    STATE.chams[pl] = hl
end

RunService.RenderStepped:Connect(function()
    if STATE.unloaded then return end
    if not FLAGS.esp_enabled then
        for pl in pairs(STATE.chams) do clearEsp(pl) end
        return
    end
    local seen = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and isAlive(pl) and (FLAGS.esp_team or not sameTeam(pl)) then
            seen[pl] = true
            ensureChams(pl)
        end
    end
    for pl in pairs(STATE.chams) do
        if not seen[pl] then clearEsp(pl) end
    end
end)

Players.PlayerRemoving:Connect(clearEsp)

local OrionLib
do
    local urls = {
        "https://raw.githubusercontent.com/Seven7-lua/Roblox/refs/heads/main/Librarys/Orion/Orion.lua",
        "https://raw.githubusercontent.com/Robloxexploiter691/Mobilefriendlyorion/main/Orion",
        "https://raw.githubusercontent.com/shlexware/Orion/main/source",
    }
    for _, url in ipairs(urls) do
        local ok, res = pcall(function() return loadstring(game:HttpGet(url))() end)
        if ok and res then OrionLib = res break end
    end
    if not OrionLib then error("[SleepyHub Orion] Orion UI failed to load") end
end

local Window = OrionLib:MakeWindow({
    Name = "SleepyHub Orion | Rivals",
    HidePremium = true,
    SaveConfig = true,
    ConfigFolder = "SleepyOrionRivals",
    IntroEnabled = false,
    Icon = ICONS.gun,
})

local TabSilent = Window:MakeTab({ Name = "Silent Aim", Icon = ICONS.silent, PremiumOnly = false })
local TabAim = Window:MakeTab({ Name = "Aimbot", Icon = ICONS.aimbot, PremiumOnly = false })
local TabGun = Window:MakeTab({ Name = "Gun Mods", Icon = ICONS.recoil, PremiumOnly = false })
local TabMelee = Window:MakeTab({ Name = "Melee", Icon = ICONS.melee, PremiumOnly = false })
local TabEsp = Window:MakeTab({ Name = "ESP", Icon = ICONS.esp, PremiumOnly = false })
local TabSettings = Window:MakeTab({ Name = "Settings", Icon = ICONS.settings, PremiumOnly = false })

TabSilent:AddParagraph("Silent Aim", "Predictive FOV silent · sticky target · mouse hook")
TabSilent:AddToggle({ Name = "Enable Silent Aim", Default = true, Callback = function(v) FLAGS.silent_enabled = v end })
TabSilent:AddToggle({ Name = "Show FOV Circle", Default = true, Callback = function(v) FLAGS.silent_show_fov = v end })
TabSilent:AddToggle({ Name = "Team Check", Default = true, Callback = function(v) FLAGS.silent_team_check = v end })
TabSilent:AddToggle({ Name = "Wall Check", Default = false, Callback = function(v) FLAGS.silent_wall_check = v end })
TabSilent:AddToggle({ Name = "Sticky Target", Default = true, Callback = function(v) FLAGS.silent_sticky = v end })
TabSilent:AddSlider({ Name = "FOV", Min = 20, Max = 500, Default = 180, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "px", Callback = function(v) FLAGS.silent_fov = v end })
TabSilent:AddSlider({ Name = "Prediction", Min = 0, Max = 40, Default = 16, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "", Callback = function(v) FLAGS.silent_prediction = v / 100 end })
TabSilent:AddSlider({ Name = "Hit Chance", Min = 1, Max = 100, Default = 100, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "%", Callback = function(v) FLAGS.silent_hitchance = v end })
TabSilent:AddDropdown({ Name = "Hit Part", Default = "Head", Options = {"Head","HRP","Closest"}, Callback = function(v) FLAGS.silent_hitpart = v end })
TabSilent:AddDropdown({ Name = "Priority", Default = "Crosshair", Options = {"Crosshair","Distance","Health"}, Callback = function(v) FLAGS.silent_priority = v end })

TabAim:AddParagraph("Aimbot", "Camera smooth-aim with gun FOV assist")
TabAim:AddToggle({ Name = "Enable Aimbot", Default = false, Callback = function(v) FLAGS.aimbot_enabled = v end })
TabAim:AddToggle({ Name = "Show FOV Circle", Default = false, Callback = function(v) FLAGS.aimbot_show_fov = v end })
TabAim:AddToggle({ Name = "Team Check", Default = true, Callback = function(v) FLAGS.aimbot_team_check = v end })
TabAim:AddToggle({ Name = "Wall Check", Default = false, Callback = function(v) FLAGS.aimbot_wall_check = v end })
TabAim:AddToggle({ Name = "Hold Key (E)", Default = true, Callback = function(v) FLAGS.aimbot_hold = v end })
TabAim:AddSlider({ Name = "FOV", Min = 20, Max = 400, Default = 140, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "px", Callback = function(v) FLAGS.aimbot_fov = v end })
TabAim:AddSlider({ Name = "Smoothness", Min = 1, Max = 50, Default = 14, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "", Callback = function(v) FLAGS.aimbot_smooth = v / 100 end })
TabAim:AddSlider({ Name = "Prediction", Min = 0, Max = 40, Default = 13, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "", Callback = function(v) FLAGS.aimbot_prediction = v / 100 end })
TabAim:AddDropdown({ Name = "Hit Part", Default = "Head", Options = {"Head","HRP","Closest"}, Callback = function(v) FLAGS.aimbot_hitpart = v end })

TabGun:AddParagraph("Weapon Mods", "No Recoil · No Spread · Anti Camera Shake")
TabGun:AddToggle({ Name = "No Recoil", Default = true, Callback = function(v) FLAGS.no_recoil = v end })
TabGun:AddToggle({ Name = "No Spread", Default = true, Callback = function(v) FLAGS.no_spread = v end })
TabGun:AddToggle({ Name = "Anti Camera Shake", Default = true, Callback = function(v) FLAGS.anti_shake = v end })
TabGun:AddSlider({ Name = "Recoil Amount", Min = 0, Max = 100, Default = 0, Color = Color3.fromRGB(255,255,255), Increment = 1, ValueName = "%", Callback = function(v) FLAGS.recoil_scale = v / 100 end })

TabMelee:AddParagraph("Melee Aura", "Range hit + optional face-back")
TabMelee:AddToggle({ Name = "Melee Aura", Default = false, Callback = function(v) FLAGS.melee_enabled = v end })
TabMelee:AddToggle({ Name = "Face Back (Backstab)", Default = true, Callback = function(v) FLAGS.melee_face = v end })
TabMelee:AddSlider({ Name = "Range", Min = 6, Max = 25, Default = 14, Color = Color3.fromRGB(255,255,255), Increment = 0.5, ValueName = "studs", Callback = function(v) FLAGS.melee_range = v end })

TabEsp:AddParagraph("ESP", "Enemy chams through walls")
TabEsp:AddToggle({ Name = "Enable ESP", Default = true, Callback = function(v) FLAGS.esp_enabled = v end })
TabEsp:AddToggle({ Name = "Chams", Default = true, Callback = function(v) FLAGS.esp_chams = v end })
TabEsp:AddToggle({ Name = "Show Teammates", Default = false, Callback = function(v) FLAGS.esp_team = v end })

TabSettings:AddParagraph("System", "Hub controls")
TabSettings:AddSlider({ Name = "Max Target Distance", Min = 100, Max = 2000, Default = 1400, Color = Color3.fromRGB(255,255,255), Increment = 50, ValueName = "studs", Callback = function(v) FLAGS.max_distance = v end })
TabSettings:AddButton({
    Name = "Unload Hub",
    Callback = function()
        STATE.unloaded = true
        if silentFov then pcall(function() silentFov:Remove() end) end
        if aimbotFov then pcall(function() aimbotFov:Remove() end) end
        for pl in pairs(STATE.chams) do clearEsp(pl) end
        pcall(function() OrionLib:Destroy() end)
        if getgenv then getgenv().SleepyOrionUnload = nil end
    end,
})

getgenv().SleepyOrionUnload = function()
    STATE.unloaded = true
    if silentFov then pcall(function() silentFov:Remove() end) end
    if aimbotFov then pcall(function() aimbotFov:Remove() end) end
    for pl in pairs(STATE.chams) do clearEsp(pl) end
    pcall(function() OrionLib:Destroy() end)
end

OrionLib:MakeNotification({
    Name = "SleepyHub Orion",
    Content = "Silent · Aimbot · Gun Mods · ESP loaded",
    Image = ICONS.gun,
    Time = 4,
})
pcall(function() OrionLib:Init() end)
print("[SleepyHub Orion] Rivals ready")
