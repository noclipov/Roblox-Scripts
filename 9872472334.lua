repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334] = true, [10662098230] = true, [10808838353] = true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return
end

local success, settings = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/settings.lua?t=" .. tick()))()
end)
if not success or not settings then
    settings = { save = function() end, get = function() return nil end }
end
local CONFIG_FILE = "NoclipovUI_Config"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local Stats             = game:GetService("Stats")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

local IsVisible = true

local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, LandingBoostPercent=5, LandingSoftVY=30, AbsCap=200,
    MaxTurnAngle=45, PredMaxDist=100, PredMinScale=0.3,
    PredFadeInSpeed=5, PredFadeOutSpeed=9, PredToleranceTime=0.25,
    PredMinVisibleDist=15,
    LightBrightness=3.0, LightAmbientVal=140, LightExposure=0.4,
}

local Theme = {
    BgLight    = Color3.fromRGB(30, 35, 43),
    BgDark     = Color3.fromRGB(22, 26, 32),
    BgDeep     = Color3.fromRGB(15, 18, 23),

    CardBg     = Color3.fromRGB(38, 44, 54),
    Surface    = Color3.fromRGB(48, 55, 67),
    Border     = Color3.fromRGB(74, 82, 96),

    Accent     = Color3.fromRGB(94, 168, 156),
    AccentDark = Color3.fromRGB(70, 130, 122),
    AccentSoft = Color3.fromRGB(120, 195, 182),
    AccentDeep = Color3.fromRGB(52, 90, 84),

    Success    = Color3.fromRGB(122, 184, 130),
    Danger     = Color3.fromRGB(224, 122, 122),
    Warning    = Color3.fromRGB(224, 180, 92),

    Text       = Color3.fromRGB(228, 231, 236),
    TextDim    = Color3.fromRGB(156, 163, 175),
    TextMuted  = Color3.fromRGB(107, 114, 128),

    MacRed     = Color3.fromRGB(224, 115, 115),
    MacYellow  = Color3.fromRGB(224, 180, 92),
}

local State = {
    BhopEnabled=false, JumpAccelEnabled=false, IsHoldingJump=false, 
    SlopeBoostEnabled=false, LandPredEnabled=false, 
    LandingBoostEnabled=false, LightingBoostEnabled=false,
    WatermarkEnabled=false,
}

local Connections = {}
local TargetSpeed = 0
local WasAirborne = false
local TrackedHrp = nil
local TrackedLV = nil
local LastGameDir = nil
local LastLandingBoosted = false
local LastSlopeBoost = 0
local CurrentStatus = "IDLE"
local LightingSaved = nil

local PredData = nil
local SmoothPredCFrame = nil
local FadeState = "hidden"
local FadeProgress = 0
local lastPredSuccess = 0
local lastPredUpdate = 0
local ArcParts = {}
local awaitingBind = nil
local lastOrphanSweep = 0
local PredIdleTime = 0
local lastPredTime = 0
local lastImpactSpeed = 0
local predFlightMaxTime = 0

local ToggleRefs, SliderRefs, HotkeyButtons = {}, {}, {}
local SaveConfig, LoadConfig

local HotkeysList = {
    { id = "Bhop", title = "Toggle Bhop", default = Enum.KeyCode.B },
    { id = "Accel", title = "Toggle Jump Accel", default = Enum.KeyCode.J },
    { id = "Slope", title = "Toggle Slope Boost", default = Enum.KeyCode.V },
    { id = "Land", title = "Toggle Landing Boost", default = Enum.KeyCode.N },
    { id = "Pred", title = "Toggle Prediction", default = Enum.KeyCode.M },
    { id = "Light", title = "Toggle Lighting", default = Enum.KeyCode.L },
    { id = "Brake", title = "Brake (Hold)", default = Enum.KeyCode.LeftShift },
    { id = "Fall", title = "Fast Fall (Hold)", default = Enum.KeyCode.X },
    { id = "UI", title = "Toggle UI", default = Enum.KeyCode.RightShift }
}

local Hotkeys = {}
for _, item in ipairs(HotkeysList) do Hotkeys[item.id] = item.default end

-- ============ Helpers ============
local function SafeParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    if syn and syn.protect_gui then
        local sg = Instance.new("ScreenGui"); syn.protect_gui(sg); return sg
    end
    return CoreGui
end

local function CleanupPrevious()
    if type(ENV.__ZettaCleanup) == "function" then pcall(ENV.__ZettaCleanup) end
    ENV.__ZettaCleanup = nil
    local parents = {}
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then table.insert(parents, hui) end
    end
    pcall(function() table.insert(parents, LocalPlayer:FindFirstChild("PlayerGui")) end)
    pcall(function() table.insert(parents, CoreGui) end)
    for _, parent in ipairs(parents) do
        local existing = parent and parent:FindFirstChild("NoclipovUI")
        if existing then pcall(function() existing:Destroy() end) end
    end
end

local function New(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    return inst
end

local function Corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c
end

local function Gradient(p, colors, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(colors[1], colors[2])
    g.Rotation = rotation or 0
    g.Parent = p
    return g
end

local function Stroke(p, color, thick, transp)
    local s = Instance.new("UIStroke")
    s.Color = color; s.Thickness = thick or 1; s.Transparency = transp or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end

local function Pad(p, t, r, b, l)
    local x = Instance.new("UIPadding")
    x.PaddingTop=UDim.new(0,t or 0); x.PaddingBottom=UDim.new(0,b or 0)
    x.PaddingLeft=UDim.new(0,l or 0); x.PaddingRight=UDim.new(0,r or 0)
    x.Parent = p; return p
end

local function AddShadow(p)
    local ok, shadow = pcall(function() return Instance.new("UIShadow") end)
    if ok and shadow then
        pcall(function()
            shadow.Color = Color3.new(0, 0, 0)
            shadow.Transparency = 0.35
            shadow.BlurRadius = 22
            shadow.Offset = Vector2.new(0, 6)
            shadow.Parent = p
        end)
    else
        local s = Instance.new("UIStroke")
        s.Color = Color3.new(0, 0, 0); s.Thickness = 3; s.Transparency = 0.55
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p
    end
end

local function AddHoverScale(card, targetScale)
    targetScale = targetScale or 1.012
    local scale = Instance.new("UIScale")
    scale.Scale = 1; scale.Parent = card
    card.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.18), { Scale = targetScale }):Play() end)
    card.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.18), { Scale = 1 }):Play() end)
end

local function Tween(inst, props, t, style, dir)
    TweenService:Create(inst, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function GetEvents() return ReplicatedStorage:FindFirstChild("Events") end

-- ============ Core Logic ============
local CHAR_RAY = RaycastParams.new()
CHAR_RAY.FilterType = Enum.RaycastFilterType.Exclude
CHAR_RAY.IgnoreWater = true

local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.FallingDown then return true end
    if hum.FloorMaterial == Enum.Material.Air then
        CHAR_RAY.FilterDescendantsInstances = { LocalPlayer.Character }
        local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -3, 0), CHAR_RAY)
        return hit == nil
    end
    return false
end

local function TriggerSelfRevive()
    local events = GetEvents()
    if not events then return end
    local revive = events:FindFirstChild("Revive")
    if revive then pcall(function() revive:FireServer() end) end
    local setMode = events:FindFirstChild("SetPlayerMode")
    if setMode then pcall(function() setMode:FireServer(true) end) end
    local ch = events:FindFirstChild("Character")
    if ch and ch:FindFirstChild("Revive") then pcall(function() ch.Revive:FireServer() end) end
end

local function FindGameLV(char)
    if not char then return nil end
    local planeBest, anyFallback
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("LinearVelocity") and d.Attachment0 and d.RelativeTo == Enum.ActuatorRelativeTo.World then
            local m = d.VelocityConstraintMode
            if m == Enum.VelocityConstraintMode.Plane then
                if d.Enabled then return d end
                planeBest = planeBest or d
            elseif m == Enum.VelocityConstraintMode.Vector then
                anyFallback = anyFallback or d
            end
        end
    end
    return planeBest or anyFallback
end

local function ReadGameHoriz(lv, hrp)
    if lv and lv.Parent then
        if lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane then
            local p = lv.PlaneVelocity; return Vector3.new(p.X, 0, p.Y)
        elseif lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Vector then
            local v = lv.VectorVelocity; return Vector3.new(v.X, 0, v.Z)
        end
    end
    local v = hrp.AssemblyLinearVelocity; return Vector3.new(v.X, 0, v.Z)
end

local function WriteGameHoriz(lv, hrp, horiz)
    if lv and lv.Parent then
        if lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane then
            lv.PlaneVelocity = Vector2.new(horiz.X, horiz.Z)
        elseif lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Vector then
            local v = lv.VectorVelocity; lv.VectorVelocity = Vector3.new(horiz.X, v.Y, horiz.Z)
        end
    end
    local v = hrp.AssemblyLinearVelocity
    hrp.AssemblyLinearVelocity = Vector3.new(horiz.X, v.Y, horiz.Z)
end

local function ClampVelocity(hrp)
    local av = hrp.AssemblyLinearVelocity
    local horiz = Vector3.new(av.X, 0, av.Z); local y = av.Y; local clamped = false
    if horiz.Magnitude > CFG.MaxSpeed then horiz = horiz.Unit * CFG.MaxSpeed; clamped = true end
    if math.abs(y) > CFG.VertCap then y = (y > 0) and CFG.VertCap or -CFG.VertCap; clamped = true end
    local nv = Vector3.new(horiz.X, y, horiz.Z)
    if nv.Magnitude > CFG.AbsCap then nv = nv.Unit * CFG.AbsCap; clamped = true end
    if clamped then hrp.AssemblyLinearVelocity = nv end
end

local function ResetBhopState() TargetSpeed = 0; LastGameDir = nil end

local function TryBhop(dt)
    local char = LocalPlayer.Character
    if not char then ResetBhopState(); WasAirborne = false; TrackedHrp = nil; TrackedLV = nil; CurrentStatus = "NO CHAR"; return end
    local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then ResetBhopState(); WasAirborne = false; CurrentStatus = "IDLE"; return end
    
    if TrackedHrp ~= hrp then
        TrackedHrp = hrp; TrackedLV = FindGameLV(char); ResetBhopState(); WasAirborne = false
    elseif not TrackedLV or TrackedLV.Parent ~= hrp then 
        TrackedLV = FindGameLV(char) 
    end
    if not State.BhopEnabled then 
        ResetBhopState(); WasAirborne = IsAirborne(hum, hrp); ClampVelocity(hrp); CurrentStatus = "DISABLED"; return 
    end
    
    local airborne = IsAirborne(hum, hrp); local humState = hum:GetState()
    local gameHoriz = ReadGameHoriz(TrackedLV, hrp); local gameSpeed = gameHoriz.Magnitude
    local gameDir = (gameSpeed > 0.5) and gameHoriz.Unit or nil
    
    if airborne and not WasAirborne then
        if (humState == Enum.HumanoidStateType.Jumping) and State.IsHoldingJump then
            local base = math.max(TargetSpeed, gameSpeed)
            if base > 3 then
                if State.JumpAccelEnabled then
                    local headroom = CFG.MaxSpeed - base
                    TargetSpeed = base + math.min(base * (CFG.GainPercent / 100), headroom)
                else
                    TargetSpeed = base
                end
                LastGameDir = gameDir
            end
        end
    end
    if airborne and gameDir and LastGameDir then
        local align = math.clamp(LastGameDir:Dot(gameDir), -1, 1)
        if math.deg(math.acos(align)) > CFG.MaxTurnAngle then TargetSpeed = 0 end
    end
    if airborne and gameDir then LastGameDir = gameDir end
    
    local braking = airborne and TargetSpeed > 0 and Hotkeys["Brake"] and UserInputService:IsKeyDown(Hotkeys["Brake"])
    if braking then TargetSpeed = math.max(CFG.MinSpeed, TargetSpeed - CFG.BrakeRate * dt) end
    
    if airborne and TargetSpeed >= 1 and gameDir then
        WriteGameHoriz(TrackedLV, hrp, gameDir * math.min(TargetSpeed, CFG.MaxSpeed))
    elseif not airborne and TargetSpeed >= 1 and State.IsHoldingJump then
        local dir = gameDir
        if not dir and hum.MoveDirection.Magnitude > 0.01 then
            local flat = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
            if flat.Magnitude > 0.01 then dir = flat.Unit end
        end
        if dir then WriteGameHoriz(TrackedLV, hrp, dir * math.min(TargetSpeed, CFG.MaxSpeed)) end
    end
    
    if not airborne and State.IsHoldingJump and hum.FloorMaterial ~= Enum.Material.Air and humState ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true); hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    
    if airborne and Hotkeys["Fall"] and UserInputService:IsKeyDown(Hotkeys["Fall"]) then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    
    if not airborne and WasAirborne and State.LandingBoostEnabled and TargetSpeed > 0 and not LastLandingBoosted then
        local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
        if vy <= CFG.LandingSoftVY then
            local headroom = CFG.MaxSpeed - TargetSpeed
            TargetSpeed = TargetSpeed + math.min(TargetSpeed * (CFG.LandingBoostPercent / 100), headroom)
            LastLandingBoosted = true
        end
    end
    if not airborne then LastLandingBoosted = false; LastGameDir = nil end
    if not airborne and not State.IsHoldingJump then ResetBhopState() end
    
    CurrentStatus = braking and "BRAKE" or (airborne and TargetSpeed > 0 and "GAIN" or (airborne and "AIR" or "IDLE"))
    WasAirborne = airborne; ClampVelocity(hrp)
end

-- === Slope Boost ===
local SLOPE = { Cooldown=0.55, MinSpeed=25, Gain=1.15, GainPerSpeed=0.01, MaxGain=2.2, SpeedRef=40, UpComponent=1.0, MinRise=1.5, NormalMin=math.cos(math.rad(70)), NormalMax=math.cos(math.rad(30)), AirRay=20, GroundRay=12 }
local DOWN_AIR, DOWN_GROUND = Vector3.new(0, -SLOPE.AirRay, 0), Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new(); SlopeRay.FilterType = Enum.RaycastFilterType.Exclude; SlopeRay.IgnoreWater = true

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock(); if now - LastSlopeBoost < SLOPE.Cooldown then return end
    local char = LocalPlayer.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart"); local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    
    SlopeRay.FilterDescendantsInstances = { char }
    local vel = hrp.AssemblyLinearVelocity; if vel.Y < 2 then return end
    local flat = Vector3.new(vel.X, 0, vel.Z); local speed = flat.Magnitude; if speed < 0.1 then return end
    local fw = flat.Unit; local base = hrp.Position
    
    local hB = Workspace:Raycast(base - fw * 2.0, DOWN_AIR, SlopeRay)
    local hA1 = Workspace:Raycast(base + fw * 1.0, DOWN_AIR, SlopeRay)
    local hA2 = Workspace:Raycast(base + fw * 2.5, DOWN_AIR, SlopeRay)
    local hA3 = Workspace:Raycast(base + fw * 4.0, DOWN_AIR, SlopeRay)
    
    if not (hB and hA1 and hA2) then
        hB = Workspace:Raycast(base - fw * 2.0, DOWN_GROUND, SlopeRay)
        hA1 = Workspace:Raycast(base + fw * 1.0, DOWN_GROUND, SlopeRay)
        hA2 = Workspace:Raycast(base + fw * 2.5, DOWN_GROUND, SlopeRay)
        hA3 = Workspace:Raycast(base + fw * 4.0, DOWN_GROUND, SlopeRay)
    end
    if not (hB and hA1 and hA2) then return end
    
    local r1 = hA1.Position.Y - hB.Position.Y
    local r2 = hA2.Position.Y - hB.Position.Y
    local r3 = hA3 and (hA3.Position.Y - hB.Position.Y) or r2
    
    if r1 <= 0 or r2 <= 0 or r1 < SLOPE.MinRise or r2 < SLOPE.MinRise * 0.7 or r1 > r2 * 2.0 then return end
    if r3 < SLOPE.MinRise * 0.5 and r2 < SLOPE.MinRise then return end
    
    local upDot = hA1.Normal.Y
    if upDot >= SLOPE.NormalMax or upDot <= SLOPE.NormalMin then return end
    
    LastSlopeBoost = now
    task.spawn(function()
        task.wait(0.03)
        if not State.SlopeBoostEnabled or not State.IsHoldingJump or not hrp.Parent then return end
        local v2 = hrp.AssemblyLinearVelocity; if v2.Y < 0 then return end
        local sp = Vector3.new(v2.X, 0, v2.Z).Magnitude
        local over = math.max(0, sp - SLOPE.SpeedRef)
        local g = math.min(SLOPE.Gain + over * SLOPE.GainPerSpeed, SLOPE.MaxGain)
        hrp.AssemblyLinearVelocity = (fw + Vector3.new(0, SLOPE.UpComponent, 0)).Unit * math.max(sp, SLOPE.MinSpeed) * g
    end)
end

-- === Lighting ===
local function SaveLighting()
    if not LightingSaved then LightingSaved = { Brightness=Lighting.Brightness, Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, ExposureCompensation=Lighting.ExposureCompensation, ClockTime=Lighting.ClockTime } end
end
local function ApplyLighting()
    if not State.LightingBoostEnabled then return end
    SaveLighting()
    pcall(function()
        Lighting.Brightness = CFG.LightBrightness
        local c = Color3.fromRGB(CFG.LightAmbientVal, CFG.LightAmbientVal, CFG.LightAmbientVal)
        Lighting.Ambient = c; Lighting.OutdoorAmbient = c; Lighting.ExposureCompensation = CFG.LightExposure
    end)
end
local function RestoreLighting()
    if not LightingSaved then return end
    pcall(function()
        Lighting.Brightness = LightingSaved.Brightness; Lighting.Ambient = LightingSaved.Ambient
        Lighting.OutdoorAmbient = LightingSaved.OutdoorAmbient; Lighting.ExposureCompensation = LightingSaved.ExposureCompensation
        Lighting.ClockTime = LightingSaved.ClockTime
    end)
    LightingSaved = nil
end

-- === Prediction System ===
local PRED_RAY = RaycastParams.new(); PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude; PRED_RAY.IgnoreWater = true

local function PredictLanding(hrp, hum, maxTime)
    local hipHeight = hum.HipHeight > 0 and hum.HipHeight or 2
    local pos = hrp.Position - Vector3.new(0, hipHeight, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity
    local dt = 0.03
    local steps = math.floor(maxTime / dt)
    PRED_RAY.FilterDescendantsInstances = { LocalPlayer.Character }
    
    local path = {}
    for i = 1, steps do
        local np = pos + vel * dt + Vector3.new(0, -0.5 * g * dt * dt, 0)
        local nv = Vector3.new(vel.X, vel.Y - g * dt, vel.Z)
        local d = np - pos
        table.insert(path, np)
        
        if d.Magnitude > 0.01 then
            local hit = Workspace:Raycast(pos, d, PRED_RAY)
            if hit then
                if hit.Normal.Y > 0.4 then 
                    return hit.Position, path, (i - 1) * dt, vel
                end
                return nil, nil
            end
        end
        pos = np; vel = nv
    end
    return nil, nil
end

local function DestroyPred()
    if PredData then 
        pcall(function() if PredData.dot then PredData.dot:Destroy() end end)
        PredData = nil 
    end
    for _, p in ipairs(ArcParts) do pcall(function() p:Destroy() end) end
    table.clear(ArcParts)
    SmoothPredCFrame = nil
end

local PRED_NAMES = { ZP_Pred_Dot = true, ZP_Pred_Arc = true }
local function SweepOrphanPredParts()
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and PRED_NAMES[obj.Name] then
            local tracked = false
            if PredData and obj == PredData.dot then tracked = true end
            if not tracked then
                for _, p in ipairs(ArcParts) do if obj == p then tracked = true; break end end
            end
            if not tracked then pcall(function() obj:Destroy() end) end
        end
    end
end

local function EnsurePred()
    if PredData and PredData.dot and PredData.dot.Parent then return PredData end
    DestroyPred()
    
    -- Landing marker (small sphere with accent color)
    local dot = Instance.new("Part")
    dot.Name = "ZP_Pred_Dot"
    dot.Shape = Enum.PartType.Ball
    dot.Size = Vector3.new(0.35, 0.35, 0.35)
    dot.Anchored = true
    dot.CanCollide = false; dot.CanQuery = false; dot.CanTouch = false
    dot.Material = Enum.Material.Neon; dot.Color = Theme.Accent
    dot.Transparency = 1; dot.Parent = Workspace
    
    -- Trail segments (16 boxes connecting path points, comet style)
    for i = 1, 16 do
        local p = Instance.new("Part")
        p.Name = "ZP_Pred_Arc"
        p.Shape = Enum.PartType.Block
        p.Size = Vector3.new(0.05, 0.05, 1)  -- length updated per frame
        p.Anchored = true
        p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.Neon
        p.Color = Theme.Accent
        p.Transparency = 1; p.Parent = Workspace
        table.insert(ArcParts, p)
    end
    
    local BB_W, BB_H = 120, 120
    local CX, CY = 60, 62
    local RING_R = 38
    local SEG_COUNT = 48
    local SEG_LEN = 6
    local SEG_THICK = 4
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ZP_Pred_Label"
    billboard.Size = UDim2.new(0, BB_W, 0, BB_H)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Parent = dot
    
    local bBg = Instance.new("Frame")
    bBg.Size = UDim2.new(1, 0, 1, 0)
    bBg.BackgroundColor3 = Theme.BgDeep
    bBg.BackgroundTransparency = 1
    bBg.BorderSizePixel = 0
    bBg.Parent = billboard
    local bCorner = Instance.new("UICorner"); bCorner.CornerRadius = UDim.new(0, 12); bCorner.Parent = bBg
    local bStroke = Instance.new("UIStroke"); bStroke.Color = Theme.Accent; bStroke.Thickness = 1; bStroke.Transparency = 0.8; bStroke.Parent = bBg
    
    local labelTitle = Instance.new("TextLabel")
    labelTitle.Size = UDim2.new(1, 0, 0, 12)
    labelTitle.Position = UDim2.new(0, 0, 0, 4)
    labelTitle.BackgroundTransparency = 1
    labelTitle.Text = "LANDING"
    labelTitle.TextColor3 = Theme.TextMuted
    labelTitle.TextSize = 8
    labelTitle.Font = Enum.Font.GothamBold
    labelTitle.TextTransparency = 1
    labelTitle.Parent = bBg
    
    local segments = {}
    for i = 1, SEG_COUNT do
        local angleDeg = -90 + (i - 1) * (360 / SEG_COUNT)
        local angleRad = math.rad(angleDeg)
        local x = CX + RING_R * math.cos(angleRad)
        local y = CY + RING_R * math.sin(angleRad)
        
        local seg = Instance.new("Frame")
        seg.Size = UDim2.new(0, SEG_LEN, 0, SEG_THICK)
        seg.AnchorPoint = Vector2.new(0.5, 0.5)
        seg.Position = UDim2.new(0, x, 0, y)
        seg.Rotation = angleDeg + 90
        seg.BackgroundColor3 = Theme.AccentDeep
        seg.BackgroundTransparency = 1
        seg.BorderSizePixel = 0
        seg.Parent = bBg
        local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = seg
        
        table.insert(segments, seg)
    end
    
    local labelTime = Instance.new("TextLabel")
    labelTime.Size = UDim2.new(0, 76, 0, 24)
    labelTime.Position = UDim2.new(0, CX - 38, 0, CY - 12)
    labelTime.BackgroundTransparency = 1
    labelTime.Text = "0.0s"
    labelTime.TextColor3 = Theme.Text
    labelTime.TextSize = 17
    labelTime.Font = Enum.Font.GothamBold
    labelTime.TextTransparency = 1
    labelTime.Parent = bBg
    
    local labelSpeed = Instance.new("TextLabel")
    labelSpeed.Size = UDim2.new(1, 0, 0, 12)
    labelSpeed.Position = UDim2.new(0, 0, 0, 104)
    labelSpeed.BackgroundTransparency = 1
    labelSpeed.Text = "0 u/s"
    labelSpeed.TextColor3 = Theme.TextDim
    labelSpeed.TextSize = 9
    labelSpeed.Font = Enum.Font.Code
    labelSpeed.TextTransparency = 1
    labelSpeed.Parent = bBg
    
    PredData = {
        dot = dot,
        billboard = billboard,
        segments = segments,
        labelTitle = labelTitle, labelTime = labelTime, labelSpeed = labelSpeed,
        labelBg = bBg, labelStroke = bStroke,
        segCount = SEG_COUNT,
    }
    return PredData
end

local function fadeAlpha(base) 
    if FadeProgress <= 0 then return 1 end
    if FadeProgress >= 1 then return base end
    return 1 - FadeProgress * (1 - base)
end

local function UpdatePrediction(dt)
    local now = os.clock()
    if now - lastPredUpdate < 0.033 then return end
    local frameDt = now - lastPredUpdate
    lastPredUpdate = now
    
    local predPos, path, predTime, impactVel = nil, nil, nil, nil
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    
    if State.LandPredEnabled and hrp and hum and IsAirborne(hum, hrp) then
        local c, p, t, v = PredictLanding(hrp, hum, 2.5)
        if c and (hrp.Position - c).Magnitude >= CFG.PredMinVisibleDist then 
            predPos = c; path = p; predTime = t; impactVel = v
        end
    end
    
    if predPos then
        lastPredSuccess = now; PredIdleTime = 0
        if FadeState == "hidden" then 
            FadeState = "showing"; FadeProgress = 0; predFlightMaxTime = 0
        elseif FadeState == "hiding" then 
            FadeState = "showing" 
        end
    else
        if (FadeState == "showing" or FadeState == "visible") and (now - lastPredSuccess > CFG.PredToleranceTime) then FadeState = "hiding" end
    end
    
    if FadeState == "showing" then 
        FadeProgress = math.min(1, FadeProgress + frameDt * CFG.PredFadeInSpeed)
        if FadeProgress >= 1 then FadeState = "visible" end
    elseif FadeState == "hiding" then 
        FadeProgress = math.max(0, FadeProgress - frameDt * CFG.PredFadeOutSpeed)
        if FadeProgress <= 0 then FadeState = "hidden"; DestroyPred(); return end 
    end
    
    if FadeState == "hidden" then 
        PredIdleTime = PredIdleTime + frameDt
        if PredIdleTime > 2 and PredData then DestroyPred() end
        return 
    end
    if not hrp then return end
    
    local data = EnsurePred()
    if predPos then
        local targetCF = CFrame.new(predPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
        if not SmoothPredCFrame then SmoothPredCFrame = targetCF end
        SmoothPredCFrame = SmoothPredCFrame:Lerp(targetCF, math.clamp(frameDt * 15, 0, 1))
        
        local dist = (hrp.Position - SmoothPredCFrame.Position).Magnitude
        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2)
        
        -- Marker: sphere pulsing gently
        data.dot.CFrame = CFrame.new(SmoothPredCFrame.Position + Vector3.new(0, 0.15, 0))
        data.dot.Transparency = fadeAlpha(0.38 + pulse * 0.12)
        
        if predTime then
            if predFlightMaxTime == 0 or predTime > predFlightMaxTime then
                predFlightMaxTime = math.max(predTime, 0.4)
            end
        end
        
        -- Progress: 0 = start (full ring), 1 = landing (empty ring)
        local progress = 0
        if predTime and predFlightMaxTime > 0 then
            progress = math.clamp(1 - (predTime / predFlightMaxTime), 0, 1)
        end
        
        local billboardVisible = dist > 25
        if data.billboard then data.billboard.Enabled = billboardVisible end
        
        if billboardVisible then
            if predTime then lastPredTime = predTime end
            if impactVel then lastImpactSpeed = math.abs(impactVel.Y) end
            
            local bbAlpha = fadeAlpha(0)
            
            -- Warning colors based on landing time
            if data.labelTime then
                data.labelTime.Text = string.format("%.1fs", lastPredTime or 0)
                data.labelTime.TextTransparency = bbAlpha
                if lastPredTime and lastPredTime < 0.5 then
                    data.labelTime.TextColor3 = Theme.Warning
                else
                    data.labelTime.TextColor3 = Theme.Text
                end
            end
            
            -- Impact speed color-coded by danger level
            if data.labelSpeed then
                data.labelSpeed.Text = string.format("%d u/s", math.floor(lastImpactSpeed or 0))
                data.labelSpeed.TextTransparency = bbAlpha
                if lastImpactSpeed > 100 then
                    data.labelSpeed.TextColor3 = Theme.Danger
                elseif lastImpactSpeed > 60 then
                    data.labelSpeed.TextColor3 = Theme.Warning
                else
                    data.labelSpeed.TextColor3 = Theme.TextDim
                end
            end
            
            if data.labelTitle then data.labelTitle.TextTransparency = bbAlpha end
            if data.labelBg then data.labelBg.BackgroundTransparency = fadeAlpha(0.55) end
            if data.labelStroke then data.labelStroke.Transparency = fadeAlpha(0.8) end
            
            -- Inverted ring (drains clockwise as landing approaches)
            if data.segments then
                local segCount = data.segCount
                for i, seg in ipairs(data.segments) do
                    local segStart = (i - 1) / segCount
                    local segEnd = i / segCount
                    if progress <= segStart then
                        seg.BackgroundTransparency = fadeAlpha(0.15)
                        seg.BackgroundColor3 = Theme.Accent
                    elseif progress >= segEnd then
                        seg.BackgroundTransparency = fadeAlpha(0.88)
                        seg.BackgroundColor3 = Theme.AccentDeep
                    else
                        local partial = (progress - segStart) / (segEnd - segStart)
                        seg.BackgroundTransparency = fadeAlpha(0.15 + partial * 0.73)
                        seg.BackgroundColor3 = Theme.Accent
                    end
                end
            end
        end
        
        -- Trail: connected box segments (comet effect)
        if path and #path > 2 then
            local N = #path
            local numSeg = #ArcParts
            for i, seg in ipairs(ArcParts) do
                local idx1 = math.clamp(math.floor((i - 1) / numSeg * (N - 1)) + 1, 1, N - 1)
                local idx2 = math.clamp(math.floor(i / numSeg * (N - 1)) + 1, idx1 + 1, N)
                local A = path[idx1]
                local B = path[idx2]
                local len = (B - A).Magnitude
                if len > 0.05 then
                    local t = (i - 1) / (numSeg - 1)
                    local thick = 0.055 - t * 0.03
                    seg.Size = Vector3.new(thick, thick, len)
                    seg.CFrame = CFrame.new((A + B) / 2, B)
                    seg.Color = Theme.Accent:Lerp(Theme.AccentSoft, t)
                    seg.Transparency = fadeAlpha(0.8 - t * 0.25)
                else
                    seg.Transparency = 1
                end
            end
        else
            for _, p in ipairs(ArcParts) do p.Transparency = 1 end
        end
    else
        for _, p in ipairs(ArcParts) do p.Transparency = 1 end
    end
end

CleanupPrevious()

-- ==========================================
-- UI SETUP
-- ==========================================
local ScreenGui = New("ScreenGui", { Name = "NoclipovUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = SafeParent() })

local WIN_W, WIN_H = 470, 660
local WM_W, WM_H = 280, 80

-- ============ UI Helpers ============
local function DrawIcon(parent, iconData)
    if not iconData then return end
    if type(iconData) == "string" and not (iconData == "bhop" or iconData == "slope" or iconData == "land" or iconData == "pred" or iconData == "power" or iconData == "sun") then
        New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = iconData, TextColor3 = Theme.TextDim, TextSize = 18, Font = Enum.Font.GothamBold, Parent = parent })
        return
    end
    local function line(size, pos, rot)
        local f = New("Frame", { Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.TextDim, BorderSizePixel = 0, Parent = parent })
        Corner(f, 1); if rot then f.Rotation = rot end
    end
    if iconData == "bhop" then
        line(UDim2.new(0,6,0,2), UDim2.new(0,10,0,10), 45); line(UDim2.new(0,6,0,2), UDim2.new(0,18,0,10), -45)
        line(UDim2.new(0,6,0,2), UDim2.new(0,10,0,16), 45); line(UDim2.new(0,6,0,2), UDim2.new(0,18,0,16), -45)
    elseif iconData == "slope" then line(UDim2.new(0,14,0,2), UDim2.new(0,14,0,14), 45)
    elseif iconData == "land" then line(UDim2.new(0,2,0,10), UDim2.new(0,14,0,10), 0); line(UDim2.new(0,8,0,2), UDim2.new(0,14,0,16), 0)
    elseif iconData == "pred" then line(UDim2.new(0,10,0,2), UDim2.new(0,14,0,14), 0); line(UDim2.new(0,2,0,10), UDim2.new(0,14,0,14), 0)
    elseif iconData == "power" then line(UDim2.new(0,4,0,6), UDim2.new(0,12,0,12), 30); line(UDim2.new(0,4,0,6), UDim2.new(0,16,0,18), 30)
    end
end

local function CreateCardShell(parent, opts)
    opts = opts or {}
    local card = New("Frame", {
        Name = opts.name or "Card",
        Size = UDim2.new(1, 0, 0, opts.height or 70),
        BackgroundColor3 = Theme.CardBg,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Parent = parent,
    })
    Corner(card, 11)
    local stroke = Stroke(card, Theme.Border, 1, 0.85)
    if opts.padding then
        local p = opts.padding
        Pad(card, p[1], p[2], p[3], p[4])
    end
    AddHoverScale(card, opts.hoverScale or 1.008)
    card.MouseEnter:Connect(function() Tween(card, { BackgroundColor3 = Theme.Surface }, 0.15); Tween(stroke, { Transparency = 0.7 }, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, { BackgroundColor3 = Theme.CardBg }, 0.15); Tween(stroke, { Transparency = 0.85 }, 0.15) end)
    return card, stroke
end

local function CreateIconBadge(parent, size, pos, iconData)
    local box = New("Frame", {
        Size = UDim2.new(0, size, 0, size), Position = pos,
        BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, Parent = parent,
    })
    Corner(box, math.floor(size * 0.26))
    local stroke = Stroke(box, Theme.Border, 1, 0.7)
    DrawIcon(box, iconData)
    return box, stroke
end

local function CreateCardText(parent, title, desc, x, titleY, descY, rightMargin)
    local t = New("TextLabel", {
        Size = UDim2.new(1, -rightMargin, 0, 17), Position = UDim2.new(0, x, 0, titleY),
        BackgroundTransparency = 1, Text = title, TextColor3 = Theme.Text, TextSize = 14,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
    })
    New("TextLabel", {
        Size = UDim2.new(1, -rightMargin, 0, 14), Position = UDim2.new(0, x, 0, descY),
        BackgroundTransparency = 1, Text = desc, TextColor3 = Theme.TextDim, TextSize = 11,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent,
    })
    return t
end

local function CreateSection(parent, text)
    local holder = New("Frame", { Name = "SectionHolder", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = parent })
    New("Frame", { Size = UDim2.new(0, 3, 0, 3), Position = UDim2.new(0, 4, 0.5, -1.5), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = holder })
    New("TextLabel", { Size = UDim2.new(0, 200, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1, Text = string.upper(text), TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = holder })
    -- Gradient divider line (accent → border)
    local div = New("Frame", { Size = UDim2.new(1, -230, 0, 1), Position = UDim2.new(0, 220, 0.5, 0), BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = holder })
    Gradient(div, { Theme.Accent, Theme.Border }, 0)
end

-- ============ LAUNCHER ============
local LauncherIcon = New("TextButton", {
    Name = "LauncherIcon", Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0, Text = "N", TextColor3 = Theme.Text, TextSize = 20,
    Font = Enum.Font.GothamBold, AutoButtonColor = false, ZIndex = 2, Parent = ScreenGui,
})
Corner(LauncherIcon, 12)
Gradient(LauncherIcon, { Theme.Accent, Theme.AccentDark }, 45)
Stroke(LauncherIcon, Theme.AccentSoft, 1, 0.6)
AddShadow(LauncherIcon)

do
    local dragging, dragStart, startPos
    LauncherIcon.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPos = Vector2.new(LauncherIcon.AbsolutePosition.X, LauncherIcon.AbsolutePosition.Y)
        end
    end)
    Connections.LauncherDragMove = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if math.abs(delta.X) < 5 and math.abs(delta.Y) < 5 then return end
        local ps = ScreenGui.AbsoluteSize
        LauncherIcon.Position = UDim2.new(0, math.clamp(startPos.X + delta.X, 0, ps.X - 44), 0, math.clamp(startPos.Y + delta.Y, 0, ps.Y - 44))
    end)
    Connections.LauncherDragEnd = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            dragging = false; if SaveConfig then SaveConfig() end
        end
    end)
end

-- ============ WATERMARK (compact 280x80) ============
local WatermarkFrame = New("Frame", {
    Name = "Watermark", Size = UDim2.new(0, WM_W, 0, WM_H), Position = UDim2.new(0, 16, 0, 16),
    BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.08, BorderSizePixel = 0, Active = true, ZIndex = 1, 
    Visible = State.WatermarkEnabled,
    Parent = ScreenGui,
})
Corner(WatermarkFrame, 11)
Gradient(WatermarkFrame, { Theme.BgDeep, Theme.BgDark }, 90)
Stroke(WatermarkFrame, Theme.Border, 1, 0.7)
AddShadow(WatermarkFrame)
Pad(WatermarkFrame, 10, 12, 10, 12)

-- Header (no //MONITOR, tighter)
New("TextLabel", { Size = UDim2.new(0, 100, 0, 14), BackgroundTransparency = 1, Text = "NOCLIPOV", TextColor3 = Theme.Text, TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = WatermarkFrame })
New("TextLabel", { Size = UDim2.new(0, 50, 0, 14), Position = UDim2.new(1, -50, 0, 0), BackgroundTransparency = 1, Text = "v4.0", TextColor3 = Theme.Accent, TextSize = 9, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Right, Parent = WatermarkFrame })

-- Separator
local wmSep = New("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0, 16), BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = WatermarkFrame })
Gradient(wmSep, { Theme.Accent, Theme.Border }, 0)

-- Metrics row
local WmGrid = New("Frame", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 20), BackgroundTransparency = 1, Parent = WatermarkFrame })
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Top, Parent = WmGrid })

local function CreateMetric(parent, width, labelText, initialValue, align)
    align = align or Enum.TextXAlignment.Left
    local col = New("Frame", { Size = UDim2.new(0, width, 1, 0), BackgroundTransparency = 1, Parent = parent })
    New("TextLabel", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, Text = labelText, TextColor3 = Theme.TextMuted, TextSize = 8, Font = Enum.Font.GothamBold, TextXAlignment = align, Parent = col })
    local val = New("TextLabel", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 10), BackgroundTransparency = 1, Text = initialValue, TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = align, Parent = col })
    return val
end

local WmSpeedVal = CreateMetric(WmGrid, 55, "SPEED", "0.0")

local WmStateCol = New("Frame", { Size = UDim2.new(0, 82, 1, 0), BackgroundTransparency = 1, Parent = WmGrid })
New("TextLabel", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, Text = "STATE", TextColor3 = Theme.TextMuted, TextSize = 8, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = WmStateCol })
local WmStateRow = New("Frame", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 10), BackgroundTransparency = 1, Parent = WmStateCol })
local WmStatusDot = New("Frame", { Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BackgroundColor3 = Theme.TextMuted, BorderSizePixel = 0, Parent = WmStateRow })
Corner(WmStatusDot, 3)
New("UIStroke", { Color = Theme.TextMuted, Thickness = 1, Transparency = 0.4, Parent = WmStatusDot })
local WmStatusVal = New("TextLabel", { Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = "IDLE", TextColor3 = Theme.TextMuted, TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = WmStateRow })

local WmFpsVal = CreateMetric(WmGrid, 34, "FPS", "60")
local WmPingVal = CreateMetric(WmGrid, 42, "PING", "--", Enum.TextXAlignment.Right)

-- Speed bar
local WmSpeedBarBg = New("Frame", {
    Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 0, 52),
    BackgroundColor3 = Theme.BgLight, BackgroundTransparency = 0.5,
    BorderSizePixel = 0, Parent = WatermarkFrame,
})
Corner(WmSpeedBarBg, 2)
Stroke(WmSpeedBarBg, Theme.Border, 1, 0.7)

local WmSpeedBarFill = New("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0, Parent = WmSpeedBarBg,
})
Corner(WmSpeedBarFill, 2)
Gradient(WmSpeedBarFill, { Theme.Accent, Theme.AccentSoft }, 0)

do
    local dragging, dragStart, startPos
    WatermarkFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPos = Vector2.new(WatermarkFrame.AbsolutePosition.X, WatermarkFrame.AbsolutePosition.Y)
        end
    end)
    Connections.WmDragMove = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if math.abs(delta.X) < 5 and math.abs(delta.Y) < 5 then return end
        local ps = ScreenGui.AbsoluteSize
        WatermarkFrame.Position = UDim2.new(0, math.clamp(startPos.X + delta.X, 0, ps.X - WM_W), 0, math.clamp(startPos.Y + delta.Y, 0, ps.Y - WM_H))
    end)
    Connections.WmDragEnd = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            dragging = false; if SaveConfig then SaveConfig() end
        end
    end)
end

-- ============ MAIN WINDOW ============
local MainFrame = New("Frame", {
    Name = "MainFrame", Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3 = Theme.BgLight, BackgroundTransparency = 0.05, BorderSizePixel = 0, ClipsDescendants = true, Active = true, ZIndex = 1, Parent = ScreenGui,
})
Corner(MainFrame, 16)
Gradient(MainFrame, { Theme.BgLight, Theme.BgDark }, 90)
AddShadow(MainFrame)
Stroke(MainFrame, Theme.Border, 1, 0.7)

local Header = New("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = MainFrame })
Corner(Header, 16)
New("Frame", { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = Header })
New("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = Header })

local logoDot = New("Frame", { Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(0, 16, 0.5, -4), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = Header })
Corner(logoDot, 4)
New("UIStroke", { Color = Theme.AccentSoft, Thickness = 2, Transparency = 0.65, Parent = logoDot })

New("TextLabel", { Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(0, 32, 0, 0), BackgroundTransparency = 1, Text = "NOCLIPOV", TextColor3 = Theme.Text, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header })
New("TextLabel", { Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(0, 106, 0, 0), BackgroundTransparency = 1, Text = "// PANEL", TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header })

local verBadge = New("Frame", { Size = UDim2.new(0, 34, 0, 16), Position = UDim2.new(0, 165, 0.5, -8), BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = Header })
Corner(verBadge, 4)
Stroke(verBadge, Theme.Border, 1, 0.5)
New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "v4.0", TextColor3 = Theme.TextDim, TextSize = 9, Font = Enum.Font.Code, Parent = verBadge })

local LightsGroup = New("Frame", { Size = UDim2.new(0, 34, 0, 12), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), BackgroundTransparency = 1, Parent = Header })
New("UIListLayout", { Padding = UDim.new(0, 8), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = LightsGroup })

local function CreateTrafficLight(color, cb)
    local btn = New("TextButton", { Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = color, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = LightsGroup })
    Corner(btn, 6)
    Stroke(btn, Color3.new(0, 0, 0), 1, 0.6)
    btn.MouseEnter:Connect(function() Tween(btn, { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, -1, 0, -1) }, 0.12) end)
    btn.MouseLeave:Connect(function() Tween(btn, { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 0, 0, 0) }, 0.12) end)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

local TabBarHolder = New("Frame", { Size = UDim2.new(1, -32, 0, 42), Position = UDim2.new(0, 16, 0, 64), BackgroundTransparency = 1, Parent = MainFrame })
local TabBar = New("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = TabBarHolder })
Corner(TabBar, 11)
Pad(TabBar, 4, 4, 4, 4)
Stroke(TabBar, Theme.Border, 1, 0.85)

local SlidingPill = New("Frame", { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.CardBg, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 1, Parent = TabBar })
Corner(SlidingPill, 8)
Gradient(SlidingPill, { Theme.Surface, Theme.CardBg }, 90)
Stroke(SlidingPill, Theme.Border, 1, 0.6)

local Content = New("ScrollingFrame", {
    Name = "Content", Size = UDim2.new(1, -44, 1, -126), Position = UDim2.new(0, 16, 0, 114),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, 
    Parent = MainFrame,
    AutomaticCanvasSize = Enum.AutomaticSize.None,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ElasticBehavior = Enum.ElasticBehavior.Never,
    ScrollingDirection = Enum.ScrollingDirection.Y,
})

local SB_W = 4
local ScrollBarTrack = New("Frame", {
    Name = "ScrollBarTrack",
    Size = UDim2.new(0, SB_W, 1, -126),
    Position = UDim2.new(1, -18, 0, 114),
    BackgroundColor3 = Theme.BgDeep,
    BackgroundTransparency = 0.75,
    BorderSizePixel = 0,
    ZIndex = 10,
    Visible = false,
    Parent = MainFrame,
})
Corner(ScrollBarTrack, SB_W/2)
Stroke(ScrollBarTrack, Theme.Border, 1, 0.85)

local ScrollBarThumb = New("Frame", {
    Name = "ScrollBarThumb",
    Size = UDim2.new(1, 0, 0.2, 0),
    BackgroundColor3 = Theme.Accent,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    ZIndex = 11,
    Parent = ScrollBarTrack,
})
Corner(ScrollBarThumb, SB_W/2)
Stroke(ScrollBarThumb, Theme.AccentSoft, 1, 0.55)

local function UpdateScrollBar()
    if not Content.ScrollingEnabled then
        ScrollBarTrack.Visible = false
        return
    end
    local viewH = Content.AbsoluteSize.Y
    local canvasH = Content.CanvasSize.Y.Offset
    if canvasH <= viewH or canvasH == 0 or viewH == 0 then
        ScrollBarTrack.Visible = false
        return
    end
    ScrollBarTrack.Visible = true
    local ratio = viewH / canvasH
    local thumbH = math.max(0.08, ratio)
    local maxScroll = canvasH - viewH
    local pct = maxScroll > 0 and math.clamp(Content.CanvasPosition.Y / maxScroll, 0, 1) or 0
    ScrollBarThumb.Size = UDim2.new(1, 0, thumbH, 0)
    ScrollBarThumb.Position = UDim2.new(0, 0, pct * (1 - thumbH), 0)
end

Content:GetPropertyChangedSignal("CanvasPosition"):Connect(UpdateScrollBar)
Content:GetPropertyChangedSignal("CanvasSize"):Connect(UpdateScrollBar)
Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateScrollBar)

local sbDragging, sbStartY, sbStartCanvasY = false, 0, 0
ScrollBarTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sbDragging = true
        sbStartY = input.Position.Y
        sbStartCanvasY = Content.CanvasPosition.Y
        Tween(ScrollBarThumb, { BackgroundColor3 = Theme.AccentSoft }, 0.12)
    end
end)
Connections.SBDrag = UserInputService.InputChanged:Connect(function(input)
    if not sbDragging then return end
    if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
    local canvasH = Content.CanvasSize.Y.Offset
    local viewH = Content.AbsoluteSize.Y
    local maxScroll = math.max(0, canvasH - viewH)
    if maxScroll == 0 then return end
    local trackH = ScrollBarTrack.AbsoluteSize.Y
    local thumbH = ScrollBarThumb.AbsoluteSize.Y
    local scrollPerPixel = maxScroll / math.max(1, trackH - thumbH)
    local newY = math.clamp(sbStartCanvasY + (input.Position.Y - sbStartY) * scrollPerPixel, 0, maxScroll)
    Content.CanvasPosition = Vector2.new(0, newY)
end)
Connections.SBDragEnd = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sbDragging = false
        Tween(ScrollBarThumb, { BackgroundColor3 = Theme.Accent }, 0.12)
    end
end)

local ActiveTab = nil

local function UpdateContentScroll()
    if not ActiveTab or not ActiveTab.Page then return end
    local page = ActiveTab.Page
    local pageY = page.AbsoluteSize.Y
    local frameY = Content.AbsoluteSize.Y
    if pageY < 1 then task.delay(0.05, UpdateContentScroll); return end
    Content.CanvasSize = UDim2.new(0, 0, 0, pageY + 4)
    if pageY <= frameY + 2 then
        Content.ScrollingEnabled = false
        if Content.CanvasPosition.Y ~= 0 then Content.CanvasPosition = Vector2.new(0, 0) end
    else
        Content.ScrollingEnabled = true
    end
    UpdateScrollBar()
end

-- ============ TOGGLE CARD ============
local function CreateToggleCard(parent, title, desc, default, iconData, cb)
    local card, stroke = CreateCardShell(parent, { height = 70, hoverScale = 1.008 })
    local _, iconStroke = CreateIconBadge(card, 32, UDim2.new(0, 16, 0.5, -16), iconData)
    CreateCardText(card, title, desc, 58, 13, 32, 120)

    local toggled = default
    local sw = New("TextButton", {
        Size = UDim2.new(0, 44, 0, 24), Position = UDim2.new(1, -60, 0.5, -12),
        BackgroundColor3 = toggled and Theme.Accent or Theme.Surface, BackgroundTransparency = 0.1,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card,
    })
    Corner(sw, 12)
    local swStroke = Stroke(sw, toggled and Theme.AccentSoft or Theme.Border, 1, 0.5)
    local knob = New("Frame", {
        Size = UDim2.new(0, 20, 0, 20),
        Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = sw,
    })
    Corner(knob, 10)
    Stroke(knob, Theme.Border, 1, 0.6)
    local knobDot = New("Frame", {
        Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(0.5, -3, 0.5, -3),
        BackgroundColor3 = Theme.AccentDark, BackgroundTransparency = toggled and 0 or 1,
        BorderSizePixel = 0, Parent = knob,
    })
    Corner(knobDot, 3)

    local function setToggle(val)
        toggled = val
        Tween(sw, { BackgroundColor3 = toggled and Theme.Accent or Theme.Surface }, 0.2)
        Tween(knob, { Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10) }, 0.2, Enum.EasingStyle.Quart)
        Tween(swStroke, { Color = toggled and Theme.AccentSoft or Theme.Border, Transparency = toggled and 0.4 or 0.5 }, 0.2)
        Tween(stroke, { Color = toggled and Theme.Accent or Theme.Border, Transparency = toggled and 0.4 or 0.85 }, 0.2)
        if toggled then stroke.Thickness = 1.5 else stroke.Thickness = 1 end
        Tween(iconStroke, { Color = toggled and Theme.Accent or Theme.Border, Transparency = toggled and 0.3 or 0.7 }, 0.2)
        Tween(knobDot, { BackgroundTransparency = toggled and 0 or 1 }, 0.2)
        cb(toggled)
    end
    ToggleRefs[title] = setToggle

    sw.MouseButton1Click:Connect(function() setToggle(not toggled); if SaveConfig then SaveConfig() end end)
end

-- ============ SLIDER CARD ============
local function CreateSliderCard(parent, title, desc, min, max, default, iconData, cb, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    local card, stroke = CreateCardShell(parent, { height = 88, padding = {12, 14, 12, 14}, hoverScale = 1.008 })
    CreateIconBadge(card, 30, UDim2.new(0, 0, 0, 0), iconData)
    CreateCardText(card, title, desc, 38, 0, 17, 100)

    local pill = New("Frame", { Size = UDim2.new(0, 52, 0, 22), Position = UDim2.new(1, -52, 0, 4), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = card })
    Corner(pill, 11)
    Stroke(pill, Theme.Accent, 1, 0.5)
    local val = New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = string.format("%." .. decimals .. "f", default), TextColor3 = Theme.Accent, TextSize = 11, Font = Enum.Font.Code, Parent = pill })

    local track = New("TextButton", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.2, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card })
    Corner(track, 4)
    Stroke(track, Theme.Border, 1, 0.7)
    local fill = New("Frame", { Size = UDim2.new((default - min) / (max - min), 0, 1, 0), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.05, BorderSizePixel = 0, Parent = track })
    Corner(fill, 4)
    Gradient(fill, { Theme.Accent, Theme.AccentSoft }, 90)
    local knob = New("Frame", { Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0), BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = track })
    Corner(knob, 7)
    Stroke(knob, Theme.Accent, 2, 0.15)

    local function updateUI(v)
        v = math.clamp(v, min, max)
        v = math.floor(v * mult + 0.5) / mult
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = string.format("%." .. decimals .. "f", v)
        cb(v)
    end
    SliderRefs[title] = updateUI

    local dragging = false
    local function handleInput(input)
        local posX = math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
        updateUI(min + (max - min) * (posX / track.AbsoluteSize.X))
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            dragging = true; handleInput(input)
            Tween(knob, { Size = UDim2.new(0, 16, 0, 16) }, 0.1)
            Tween(stroke, { Color = Theme.Accent, Transparency = 0.5 }, 0.15)
            stroke.Thickness = 1.5
        end
    end)
    Connections["SM_" .. title] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then handleInput(input) end
    end)
    Connections["SE_" .. title] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            dragging = false
            Tween(knob, { Size = UDim2.new(0, 14, 0, 14) }, 0.1)
            Tween(stroke, { Color = Theme.Border, Transparency = 0.85 }, 0.15)
            stroke.Thickness = 1
            if SaveConfig then SaveConfig() end
        end
    end)
end

-- ============ BUTTON CARD ============
local function CreateButtonCard(parent, title, desc, cb)
    local card = New("TextButton", { Name = "InvBtn", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.05, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = parent })
    Corner(card, 11)
    Gradient(card, { Theme.Accent, Theme.AccentDark }, 90)
    Stroke(card, Theme.AccentSoft, 1, 0.4)
    AddHoverScale(card, 1.015)

    New("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 8), BackgroundTransparency = 1, Text = title, TextColor3 = Theme.BgDeep, TextSize = 14, Font = Enum.Font.GothamBold, Parent = card })
    New("TextLabel", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 30), BackgroundTransparency = 1, Text = desc, TextColor3 = Theme.BgDeep, TextTransparency = 0.2, TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true, Parent = card })

    card.MouseButton1Click:Connect(function()
        local orig = card.BackgroundTransparency
        Tween(card, { BackgroundTransparency = 0.3 }, 0.08)
        task.wait(0.08)
        Tween(card, { BackgroundTransparency = orig }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        cb()
    end)
end

-- ============ HOTKEY CARD ============
local function CreateHotkeyCard(parent, title, actionId, defaultKey)
    local card, stroke = CreateCardShell(parent, { height = 46, padding = {10, 14, 10, 14}, hoverScale = 1.008 })
    New("TextLabel", { Size = UDim2.new(1, -90, 1, 0), BackgroundTransparency = 1, Text = title, TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    
    local keycapHolder = New("Frame", { Size = UDim2.new(0, 74, 0, 26), Position = UDim2.new(1, -74, 0.5, -13), BackgroundTransparency = 1, Parent = card })
    Corner(keycapHolder, 7)
    New("Frame", { Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 0, 2), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 0, Parent = keycapHolder })
    Corner(keycapHolder:FindFirstChildOfClass("Frame"), 7)
    
    local bindBtn = New("TextButton", {
        Size = UDim2.new(1, 0, 1, -2), Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.1, BorderSizePixel = 0,
        Text = defaultKey and defaultKey.Name or "None",
        TextColor3 = defaultKey and Theme.Text or Theme.TextMuted,
        TextSize = 11, Font = Enum.Font.Code, AutoButtonColor = false, ZIndex = 2, Parent = keycapHolder,
    })
    Corner(bindBtn, 6)
    Stroke(bindBtn, Theme.Border, 1, 0.5)
    
    HotkeyButtons[actionId] = bindBtn
    
    bindBtn.MouseButton1Click:Connect(function()
        awaitingBind = actionId; bindBtn.Text = "..."; bindBtn.TextColor3 = Theme.Accent
        Tween(bindBtn, { BackgroundColor3 = Theme.AccentDark }, 0.12)
    end)
    bindBtn.MouseButton2Click:Connect(function()
        Hotkeys[actionId] = nil; bindBtn.Text = "None"; bindBtn.TextColor3 = Theme.TextMuted
        Tween(bindBtn, { BackgroundColor3 = Theme.Surface }, 0.12)
        if SaveConfig then SaveConfig() end
    end)
end

-- ============ TABS ============
local Tabs = {}

local function AnimateStagger(page)
    local i = 0
    for _, child in ipairs(page:GetChildren()) do
        if child:IsA("GuiObject") then
            if child.Name == "SectionHolder" then
                for _, sub in ipairs(child:GetChildren()) do
                    if sub:IsA("TextLabel") then
                        sub.TextTransparency = 1
                        task.delay(i * 0.025, function() Tween(sub, { TextTransparency = 0 }, 0.25, Enum.EasingStyle.Cubic) end)
                    end
                end
            else
                local origTrans = child.BackgroundTransparency
                child.BackgroundTransparency = 1
                task.delay(i * 0.025, function() Tween(child, { BackgroundTransparency = origTrans }, 0.25, Enum.EasingStyle.Cubic) end)
            end
            i = i + 1
        end
    end
end

local function SwitchTab(idx)
    local tab = Tabs[idx]
    if not tab or ActiveTab == tab then return end
    for _, t in ipairs(Tabs) do
        t.Page.Visible = false
        Tween(t.Label, { TextColor3 = Theme.TextDim }, 0.2)
    end
    tab.Page.Visible = true
    Tween(tab.Label, { TextColor3 = Theme.Accent }, 0.2)
    Tween(SlidingPill, { Position = UDim2.new((idx-1)*0.25, 0, 0, 0) }, 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    ActiveTab = tab
    AnimateStagger(tab.Page)
    task.delay(0.05, UpdateContentScroll)
    task.delay(0.35, UpdateContentScroll)
end

local function CreateTab(label, name)
    local idx = #Tabs + 1
    local btn = New("TextButton", { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new((idx-1)*0.25, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 2, Parent = TabBar })
    local lbl = New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = string.upper(label), TextColor3 = Theme.TextDim, TextSize = 11, Font = Enum.Font.GothamBold, ZIndex = 2, Parent = btn })
    
    local page = New("Frame", { 
        Name = name .. "Page", Size = UDim2.new(1, 0, 0, 0), 
        BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = Content,
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
    Pad(page, 0, 12, 8, 6)
    
    table.insert(Tabs, { Button=btn, Page=page, Label=lbl, Name=name, Index=idx })
    
    btn.MouseButton1Click:Connect(function() SwitchTab(idx) end)
    btn.MouseEnter:Connect(function() if ActiveTab ~= Tabs[idx] then Tween(lbl, { TextColor3 = Theme.Text }, 0.15) end end)
    btn.MouseLeave:Connect(function() if ActiveTab ~= Tabs[idx] then Tween(lbl, { TextColor3 = Theme.TextDim }, 0.15) end end)
    
    return page
end

local PlayPage = CreateTab("Play", "Play")
local TunePage = CreateTab("Tune", "Tune")
local VisPage  = CreateTab("Visual", "Vis")
local HotkeysPage = CreateTab("Keys", "Keys")

-- === Play Page ===
CreateSection(PlayPage, "Movement")
CreateToggleCard(PlayPage, "Auto BunnyHop", "Автоматический прыжок при удержании Space", State.BhopEnabled, "🐇", function(v)
    State.BhopEnabled = v; if not v then ResetBhopState() end
end)
CreateToggleCard(PlayPage, "Jump Acceleration", "Увеличивает скорость при каждом прыжке", State.JumpAccelEnabled, "⚡", function(v) State.JumpAccelEnabled = v end)

CreateSection(PlayPage, "Boosts")
CreateToggleCard(PlayPage, "Slope Boost", "Ускорение при столкновении со склоном (30-70°)", State.SlopeBoostEnabled, "⛷️", function(v) State.SlopeBoostEnabled = v end)
CreateToggleCard(PlayPage, "Landing Boost", "Добавляет скорость при мягком приземлении", State.LandingBoostEnabled, "🪂", function(v) State.LandingBoostEnabled = v end)

CreateSection(PlayPage, "Utility")
CreateButtonCard(PlayPage, "INSTANT REVIVE", "Мгновенное восстановление персонажа", TriggerSelfRevive)

-- === Tune Page ===
CreateSection(TunePage, "Speed")
CreateSliderCard(TunePage, "Gain Percent", "Процент прибавки за прыжок", 1, 20, CFG.GainPercent, "⚡", function(v) CFG.GainPercent = v end)
CreateSliderCard(TunePage, "Max Speed", "Максимальная скорость", 50, 250, CFG.MaxSpeed, "🚀", function(v) CFG.MaxSpeed = v end)
CreateSliderCard(TunePage, "Min Speed", "Минимальная скорость", 5, 50, CFG.MinSpeed, "🐢", function(v) CFG.MinSpeed = v end)

CreateSection(TunePage, "Control")
CreateSliderCard(TunePage, "Vertical Cap", "Лимит по оси Y", 40, 100, CFG.VertCap, "📈", function(v) CFG.VertCap = v end)
CreateSliderCard(TunePage, "Max Turn Angle", "Угол сброса буста", 15, 180, CFG.MaxTurnAngle, "📐", function(v) CFG.MaxTurnAngle = v end)
CreateSliderCard(TunePage, "Brake Rate", "Скорость торможения (Shift)", 20, 200, CFG.BrakeRate, "🛑", function(v) CFG.BrakeRate = v end)

CreateSection(TunePage, "Fall & Landing")
CreateSliderCard(TunePage, "Fast Fall Force", "Сила падения (X)", 30, 300, CFG.FastFallForce, "⬇️", function(v) CFG.FastFallForce = v end)
CreateSliderCard(TunePage, "Land Boost %", "Прибавка при посадке", 0, 20, CFG.LandingBoostPercent, "📊", function(v) CFG.LandingBoostPercent = v end)
CreateSliderCard(TunePage, "Land Soft VY", "Порог мягкой посадки", 10, 60, CFG.LandingSoftVY, "📉", function(v) CFG.LandingSoftVY = v end)

-- === Visual Page ===
CreateSection(VisPage, "Effects")
CreateToggleCard(VisPage, "Landing Prediction", "Круговой таймер до приземления", State.LandPredEnabled, "🎯", function(v)
    State.LandPredEnabled = v
    if not v then FadeState = "hidden"; FadeProgress = 0; PredIdleTime = 0; DestroyPred() end
end)

CreateSection(VisPage, "Lighting")
CreateToggleCard(VisPage, "Lighting Boost", "Улучшает освещение в игре", State.LightingBoostEnabled, "💡", function(v)
    State.LightingBoostEnabled = v; if v then ApplyLighting() else RestoreLighting() end
end)
CreateSliderCard(VisPage, "Brightness", "Яркость", 1, 8, CFG.LightBrightness, "☀️", function(v)
    CFG.LightBrightness = v; if State.LightingBoostEnabled then pcall(function() Lighting.Brightness = v end) end
end, 1)
CreateSliderCard(VisPage, "Ambient", "Фоновое освещение", 0, 255, CFG.LightAmbientVal, "🌤️", function(v)
    CFG.LightAmbientVal = v
    if State.LightingBoostEnabled then local c = Color3.fromRGB(v, v, v); pcall(function() Lighting.Ambient = c; Lighting.OutdoorAmbient = c end) end
end)
CreateSliderCard(VisPage, "Exposure", "Экспозиция камеры", -1, 2, CFG.LightExposure, "👁️", function(v)
    CFG.LightExposure = v; if State.LightingBoostEnabled then pcall(function() Lighting.ExposureCompensation = v end) end
end, 2)

CreateSection(VisPage, "Interface")
CreateToggleCard(VisPage, "Status Window", "Монитор скорости, FPS и пинга", State.WatermarkEnabled, "📊", function(v)
    State.WatermarkEnabled = v
    WatermarkFrame.Visible = v
end)

-- === Hotkeys Page ===
CreateSection(HotkeysPage, "Keybinds")
New("TextLabel", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "ЛКМ — назначить клавишу, ПКМ — сбросить", TextColor3 = Theme.TextDim, TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true, Parent = HotkeysPage })
for _, item in ipairs(HotkeysList) do CreateHotkeyCard(HotkeysPage, item.title, item.id, Hotkeys[item.id]) end

if Tabs[1] then
    Tabs[1].Page.Visible = true; Tabs[1].Label.TextColor3 = Theme.Accent
    ActiveTab = Tabs[1]; SlidingPill.Position = UDim2.new(0, 0, 0, 0)
    task.delay(0.1, function() AnimateStagger(Tabs[1].Page) end)
    task.delay(0.1, UpdateContentScroll)
    task.delay(0.4, UpdateContentScroll)
end

-- ============ SAVE / LOAD ============
local ToggleMap = {
    BhopEnabled = "Auto BunnyHop", JumpAccelEnabled = "Jump Acceleration",
    SlopeBoostEnabled = "Slope Boost", LandingBoostEnabled = "Landing Boost",
    LandPredEnabled = "Landing Prediction", LightingBoostEnabled = "Lighting Boost",
    WatermarkEnabled = "Status Window",
}
local SliderMap = {
    GainPercent = "Gain Percent", MaxSpeed = "Max Speed", VertCap = "Vertical Cap",
    MaxTurnAngle = "Max Turn Angle", BrakeRate = "Brake Rate", MinSpeed = "Min Speed",
    FastFallForce = "Fast Fall Force", LandingBoostPercent = "Land Boost %",
    LandingSoftVY = "Land Soft VY", LightBrightness = "Brightness",
    LightAmbientVal = "Ambient", LightExposure = "Exposure",
}

local function UDim2ToTable(u) return { XScale = u.X.Scale, XOffset = u.X.Offset, YScale = u.Y.Scale, YOffset = u.Y.Offset } end
local function TableToUDim2(t) return t and UDim2.new(t.XScale or 0, t.XOffset or 0, t.YScale or 0, t.YOffset or 0) or nil end

SaveConfig = function()
    local data = {
        IsVisible = IsVisible, MainFramePos = UDim2ToTable(MainFrame.Position),
        LauncherPos = UDim2ToTable(LauncherIcon.Position), WatermarkPos = UDim2ToTable(WatermarkFrame.Position),
        Hotkeys = {}, Toggles = {}, Sliders = {}
    }
    for _, item in ipairs(HotkeysList) do
        local key = Hotkeys[item.id]
        data.Hotkeys[item.id] = key and key.Name or "None"
    end
    for k, v in pairs(State) do if type(v) == "boolean" then data.Toggles[k] = v end end
    for k, v in pairs(CFG) do if type(v) == "number" then data.Sliders[k] = v end end
    settings.save(CONFIG_FILE, data)
end

LoadConfig = function()
    local data = settings.get(CONFIG_FILE)
    if not data then return end

    if data.IsVisible ~= nil then IsVisible = data.IsVisible end
    local p = TableToUDim2(data.MainFramePos); if p then MainFrame.Position = p end
    p = TableToUDim2(data.LauncherPos); if p then LauncherIcon.Position = p end
    p = TableToUDim2(data.WatermarkPos); if p then WatermarkFrame.Position = p end

    if data.Hotkeys then
        for id, keyName in pairs(data.Hotkeys) do
            if keyName == "None" then
                Hotkeys[id] = nil
                if HotkeyButtons[id] then HotkeyButtons[id].Text = "None"; HotkeyButtons[id].TextColor3 = Theme.TextMuted end
            elseif Enum.KeyCode[keyName] then
                Hotkeys[id] = Enum.KeyCode[keyName]
                if HotkeyButtons[id] then HotkeyButtons[id].Text = keyName; HotkeyButtons[id].TextColor3 = Theme.Text end
            end
        end
    end
    
    if data.Toggles then
        for stateKey, uiName in pairs(ToggleMap) do
            if data.Toggles[stateKey] ~= nil and ToggleRefs[uiName] then
                ToggleRefs[uiName](data.Toggles[stateKey])
            end
        end
    end
    
    if data.Sliders then
        for cfgKey, uiName in pairs(SliderMap) do
            if data.Sliders[cfgKey] then CFG[cfgKey] = data.Sliders[cfgKey] end
            if SliderRefs[uiName] then SliderRefs[uiName](CFG[cfgKey]) end
        end
    end
end

-- ============ WINDOW CONTROLS ============
local function showWindow()
    IsVisible = true; MainFrame.Visible = true
    local targetPos = MainFrame.Position
    MainFrame.Size = UDim2.new(0, WIN_W * 0.95, 0, WIN_H * 0.95)
    MainFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + 24)
    Tween(MainFrame, { Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = targetPos }, 0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    task.delay(0.4, UpdateContentScroll)
    if SaveConfig then SaveConfig() end
end

local function hideWindow() 
    IsVisible = false; MainFrame.Visible = false; if SaveConfig then SaveConfig() end
end

CreateTrafficLight(Theme.MacYellow, function() hideWindow() end)
CreateTrafficLight(Theme.MacRed, function() Cleanup() end)

do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if not (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then return end
        local relX = input.Position.X - Header.AbsolutePosition.X
        if relX >= Header.AbsoluteSize.X - 60 then return end
        dragging = true; dragStart = Vector2.new(input.Position.X, input.Position.Y); startPos = MainFrame.Position
    end)
    Connections.TitleDragMove = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
        local d = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end)
    Connections.TitleDragEnd = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
            dragging = false; if SaveConfig then SaveConfig() end
        end
    end)
end

LauncherIcon.MouseButton1Click:Connect(function() if IsVisible then hideWindow() else showWindow() end end)

Connections.CharRemoving = LocalPlayer.CharacterRemoving:Connect(function()
    DestroyPred(); FadeState = "hidden"; FadeProgress = 0; PredIdleTime = 0; lastPredSuccess = 0; predFlightMaxTime = 0
end)
Connections.CharAdded = LocalPlayer.CharacterAdded:Connect(function()
    DestroyPred(); FadeState = "hidden"; FadeProgress = 0; PredIdleTime = 0; lastPredSuccess = 0; predFlightMaxTime = 0
end)

-- ============ INPUT ============
Connections.HotkeysHandler = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if awaitingBind then
        local key = input.KeyCode
        if key ~= Enum.KeyCode.Unknown and key ~= Enum.KeyCode.Space then
            Hotkeys[awaitingBind] = key
            if HotkeyButtons[awaitingBind] then 
                HotkeyButtons[awaitingBind].Text = key.Name
                HotkeyButtons[awaitingBind].TextColor3 = Theme.Text
                Tween(HotkeyButtons[awaitingBind], { BackgroundColor3 = Theme.Surface }, 0.15)
            end
            awaitingBind = nil; if SaveConfig then SaveConfig() end
        end
        return
    end
    
    if UserInputService:GetFocusedTextBox() then return end
    
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local k = input.KeyCode
        local bindMap = {
            Bhop = "Auto BunnyHop", Accel = "Jump Acceleration",
            Slope = "Slope Boost", Land = "Landing Boost",
            Pred = "Landing Prediction", Light = "Lighting Boost",
        }
        for bindId, uiName in pairs(bindMap) do
            if Hotkeys[bindId] and k == Hotkeys[bindId] and ToggleRefs[uiName] then
                local stateKey = nil
                for sk, un in pairs(ToggleMap) do if un == uiName then stateKey = sk; break end end
                if stateKey then ToggleRefs[uiName](not State[stateKey]) end
                return
            end
        end
        if Hotkeys["UI"] and k == Hotkeys["UI"] then if IsVisible then hideWindow() else showWindow() end end
    end
end)

Connections.JumpInputBegan = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = true end
end)
Connections.JumpInputEnded = UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = false end
end)

Connections.Stepped = RunService.Stepped:Connect(function(_, dt)
    if State.BhopEnabled then TryBhop(dt) end
    if State.SlopeBoostEnabled then TrySlopeBoost() end
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then ClampVelocity(hrp) end
    end
end)

-- ============ PULSE ANIMATION ============
Connections.PulseLoop = RunService.Heartbeat:Connect(function()
    if not WmStatusDot or not WmStatusDot.Parent or not WatermarkFrame.Visible then return end
    local isActive = (CurrentStatus == "GAIN" or CurrentStatus == "BRAKE" or CurrentStatus == "AIR")
    if isActive then
        local pulse = 0.5 + 0.5 * math.sin(os.clock() * math.pi * 2.5)
        WmStatusDot.BackgroundTransparency = 0.1 + pulse * 0.35
    else
        WmStatusDot.BackgroundTransparency = 0
    end
end)

-- ============ STATUS / TELEMETRY ============
local lastUIUpdate = 0
local lastTelemetryUpdate = 0
local fpsFrames, fpsAccum = 0, 0

Connections.StatusLoop = RunService.Heartbeat:Connect(function(dt)
    fpsFrames = fpsFrames + 1
    fpsAccum = fpsAccum + dt
    local now = os.clock()

    if now - lastTelemetryUpdate > 0.5 then
        lastTelemetryUpdate = now
        if fpsAccum > 0 then WmFpsVal.Text = tostring(math.floor(fpsFrames / fpsAccum + 0.5)) end
        fpsFrames, fpsAccum = 0, 0
        pcall(function()
            local ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            WmPingVal.Text = tostring(ping)
            WmPingVal.TextColor3 = ping < 80 and Theme.Success or ping < 150 and Theme.Warning or Theme.Danger
        end)
    end

    if now - lastOrphanSweep > 1.0 then
        lastOrphanSweep = now
        if not PredData then SweepOrphanPredParts() end
    end

    if now - lastUIUpdate < 0.05 then return end
    lastUIUpdate = now
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local spd = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
        WmSpeedVal.Text = string.format("%.1f", spd)
        WmStatusVal.Text = CurrentStatus
        
        local color = Theme.TextMuted
        if CurrentStatus == "GAIN" then color = Theme.Success
        elseif CurrentStatus == "BRAKE" then color = Theme.Danger
        elseif CurrentStatus == "AIR" then color = Theme.Accent
        elseif CurrentStatus == "NO CHAR" then color = Theme.Warning
        end
        WmStatusVal.TextColor3 = color
        WmStatusDot.BackgroundColor3 = color
        
        local pct = math.clamp(spd / 150, 0, 1)
        WmSpeedBarFill.Size = UDim2.new(pct, 0, 1, 0)
        if spd >= CFG.MaxSpeed * 0.9 then
            WmSpeedBarFill.BackgroundColor3 = Theme.Success
        else
            WmSpeedBarFill.BackgroundColor3 = Theme.Accent
        end
    else
        WmSpeedVal.Text = "-"
        WmStatusVal.Text = "-"
        WmStatusDot.BackgroundColor3 = Theme.TextMuted
        WmSpeedBarFill.Size = UDim2.new(0, 0, 1, 0)
    end
    
    UpdatePrediction(dt)
end)

task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.3)
        if IsVisible and ActiveTab then UpdateContentScroll() end
    end
end)

MainFrame.Visible = false
LoadConfig()
if IsVisible then showWindow() else MainFrame.Visible = false end

function Cleanup()
    for k in pairs(State) do if type(State[k]) == "boolean" then State[k] = false end end
    for _, conn in pairs(Connections) do if typeof(conn) == "RBXScriptConnection" and conn.Connected then pcall(function() conn:Disconnect() end) end end
    table.clear(Connections)
    ResetBhopState(); WasAirborne = false; TrackedHrp = nil; TrackedLV = nil; DestroyPred(); RestoreLighting()
    if ScreenGui then pcall(function() ScreenGui:Destroy() end) end
    if ENV.__ZettaCleanup == Cleanup then ENV.__ZettaCleanup = nil end
end
ENV.__ZettaCleanup = Cleanup