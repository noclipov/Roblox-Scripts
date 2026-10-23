repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334] = true, [10662098230] = true, [10808838353] = true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, LandingBoostPercent=5, LandingSoftVY=30, AbsCap=200,
    MaxTurnAngle=45, PredMaxDist=100, PredMinScale=0.3,
    PredFadeInSpeed=4, PredFadeOutSpeed=3, PredToleranceTime=0.25,
    PredMinVisibleDist=15,
    LightBrightness=3.0, LightAmbientVal=140, LightExposure=0.4,
}

local Theme = {
    Bg         = Color3.fromRGB(12, 16, 24),
    BgDeep     = Color3.fromRGB(8, 12, 20),
    CardBg     = Color3.fromRGB(18, 24, 34),
    Surface    = Color3.fromRGB(26, 34, 51),
    SurfaceHi  = Color3.fromRGB(34, 44, 66),
    Border     = Color3.fromRGB(255, 255, 255),

    Accent     = Color3.fromRGB(56, 189, 248),
    AccentLight= Color3.fromRGB(125, 211, 252),
    AccentDark = Color3.fromRGB(2, 132, 199),
    Accent2    = Color3.fromRGB(167, 139, 250),
    Success    = Color3.fromRGB(16, 185, 129),
    Danger     = Color3.fromRGB(239, 68, 68),
    
    Text       = Color3.fromRGB(243, 244, 246),
    TextDim    = Color3.fromRGB(132, 146, 166),
    TextMuted  = Color3.fromRGB(90, 100, 120),

    MacRed     = Color3.fromRGB(255, 95, 87),
    MacYellow  = Color3.fromRGB(254, 188, 46),
}

local Connections = {}
local State = {
    BhopEnabled=false, IsHoldingJump=false, SlopeBoostEnabled=false,
    LandPredEnabled=false, LandingBoostEnabled=false, LightingBoostEnabled=false,
}

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
local CachedPredPos = nil
local FadeState = "hidden"
local FadeProgress = 0
local lastPredSuccess = 0
local lastPredUpdate = 0
local lastPlayerUpdate = 0

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
    if typeof(colors) == "table" then
        if #colors == 2 then
            g.Color = ColorSequence.new(colors[1], colors[2])
        else
            local kp = {}
            for i, c in ipairs(colors) do
                table.insert(kp, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
            end
            g.Color = ColorSequence.new(kp)
        end
    else
        g.Color = ColorSequence.new(colors)
    end
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
    x.Parent = p; return x
end

local function Tween(inst, props, t, style, dir)
    TweenService:Create(inst, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function GetEvents() return ReplicatedStorage:FindFirstChild("Events") end

-- ============ Core Logic ============
local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    if hum.Health <= 0 then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.FallingDown then return true end
    if hum.FloorMaterial == Enum.Material.Air then
        local f = {}
        if LocalPlayer.Character then table.insert(f, LocalPlayer.Character) end
        local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = f; p.IgnoreWater = true
        local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -3, 0), p)
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
    return clamped
end

local PRED_RAY = RaycastParams.new(); PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude; PRED_RAY.IgnoreWater = true

local function PredictLanding(hrp, hum, maxTime)
    if not hrp then return nil end
    maxTime = maxTime or 2.5
    local feetOffset = 2.5
    if hum and hum:IsA("Humanoid") then
        local ok, hh = pcall(function() return hum.HipHeight end)
        if ok and typeof(hh) == "number" and hh > 0 then feetOffset = hh end
    end
    local pos = hrp.Position - Vector3.new(0, feetOffset, 0)
    local vel = hrp.AssemblyLinearVelocity; local g = Workspace.Gravity; local dt = 0.04; local steps = math.ceil(maxTime / dt)
    local f = {}; if LocalPlayer.Character then table.insert(f, LocalPlayer.Character) end
    PRED_RAY.FilterDescendantsInstances = f
    for _ = 1, steps do
        local np = pos + vel * dt + Vector3.new(0, -0.5 * g * dt * dt, 0)
        local nv = Vector3.new(vel.X, vel.Y - g * dt, vel.Z)
        local d = np - pos
        if d.Magnitude > 0.01 then
            local hit = Workspace:Raycast(pos, d, PRED_RAY)
            if hit then
                if hit.Normal.Y > 0.4 then return hit.Position end
                return nil
            end
        end
        pos = np; vel = nv
    end
    return nil
end

local function ResetBhopState() TargetSpeed = 0; LastGameDir = nil end

local function TryBhop(dt)
    local char = LocalPlayer.Character
    if not char then ResetBhopState(); WasAirborne = false; TrackedHrp = nil; TrackedLV = nil; CurrentStatus = "NO CHAR"; return end
    local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then ResetBhopState(); WasAirborne = false; CurrentStatus = "IDLE"; return end
    if TrackedHrp ~= hrp then
        TrackedHrp = hrp; TrackedLV = FindGameLV(char); ResetBhopState(); WasAirborne = false
    elseif not TrackedLV or TrackedLV.Parent ~= hrp then TrackedLV = FindGameLV(char) end
    if not State.BhopEnabled then ResetBhopState(); WasAirborne = IsAirborne(hum, hrp); ClampVelocity(hrp); CurrentStatus = "DISABLED"; return end
    
    local airborne = IsAirborne(hum, hrp); local humState = hum:GetState()
    local gameHoriz = ReadGameHoriz(TrackedLV, hrp); local gameSpeed = gameHoriz.Magnitude
    local gameDir = (gameSpeed > 0.5) and gameHoriz.Unit or nil
    
    if airborne and not WasAirborne then
        if (humState == Enum.HumanoidStateType.Jumping) and State.IsHoldingJump then
            local base = math.max(TargetSpeed, gameSpeed)
            if base > 3 then
                local mult = CFG.GainPercent / 100; local headroom = CFG.MaxSpeed - base
                local actual = math.min(base * mult, math.max(0, headroom))
                TargetSpeed = base + actual; LastGameDir = gameDir
            end
        end
    end
    if airborne and gameDir and LastGameDir then
        local align = math.clamp(LastGameDir:Dot(gameDir), -1, 1)
        if math.deg(math.acos(align)) > CFG.MaxTurnAngle then TargetSpeed = 0 end
    end
    if airborne and gameDir then LastGameDir = gameDir end
    
    local braking = airborne and TargetSpeed > 0 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
    if braking then TargetSpeed = math.max(CFG.MinSpeed, TargetSpeed - CFG.BrakeRate * dt) end
    
    if airborne and TargetSpeed >= 1 and gameDir then
        WriteGameHoriz(TrackedLV, hrp, gameDir * math.min(TargetSpeed, CFG.MaxSpeed))
    elseif not airborne and TargetSpeed >= 1 and State.IsHoldingJump then
        local dir = gameDir
        if not dir and hum.MoveDirection.Magnitude > 0.01 then
            local md = hum.MoveDirection; local flat = Vector3.new(md.X, 0, md.Z)
            if flat.Magnitude > 0.01 then dir = flat.Unit end
        end
        if dir then WriteGameHoriz(TrackedLV, hrp, dir * math.min(TargetSpeed, CFG.MaxSpeed)) end
    end
    
    if not airborne and State.IsHoldingJump and hum.FloorMaterial ~= Enum.Material.Air and humState ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true); hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if airborne and UserInputService:IsKeyDown(Enum.KeyCode.X) then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    
    if not airborne and WasAirborne and State.LandingBoostEnabled and TargetSpeed > 0 and not LastLandingBoosted then
        local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
        if vy <= CFG.LandingSoftVY then
            local bonus = TargetSpeed * (CFG.LandingBoostPercent / 100); local headroom = CFG.MaxSpeed - TargetSpeed
            TargetSpeed = TargetSpeed + math.min(bonus, math.max(0, headroom)); LastLandingBoosted = true
        end
    end
    if not airborne then LastLandingBoosted = false; LastGameDir = nil end
    if not airborne and not State.IsHoldingJump then ResetBhopState() end
    
    if braking then CurrentStatus = "BRAKE"
    elseif airborne and TargetSpeed > 0 then CurrentStatus = "GAIN"
    elseif airborne then CurrentStatus = "AIR"
    else CurrentStatus = "IDLE" end
    
    WasAirborne = airborne; ClampVelocity(hrp)
end

-- Углы наклона для Slope Boost (30-70 градусов)
local SLOPE = { 
    Cooldown=0.55, MinSpeed=25, Gain=1.15, GainPerSpeed=0.01, MaxGain=2.2, 
    SpeedRef=40, UpComponent=1.0, MinRise=1.5, 
    NormalMin=math.cos(math.rad(70)),
    NormalMax=math.cos(math.rad(30)),
    AirRay=20, GroundRay=12 
}
local DOWN_AIR = Vector3.new(0, -SLOPE.AirRay, 0); local DOWN_GROUND = Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new(); SlopeRay.FilterType = Enum.RaycastFilterType.Exclude; SlopeRay.IgnoreWater = true
pcall(function() SlopeRay.RespectCanCollide = true end)

local function RefreshSlopeFilter()
    local f = {}; if LocalPlayer.Character then table.insert(f, LocalPlayer.Character) end
    local map = Workspace:FindFirstChild("Map")
    if map then
        local parts = map:FindFirstChild("Parts")
        if parts then
            local props = parts:FindFirstChild("ImmovableProps")
            if props then table.insert(f, props) end
        end
    end
    SlopeRay.FilterDescendantsInstances = f
end

local function SampleGround(origin, dir)
    local r = Workspace:Raycast(origin, dir, SlopeRay)
    if not r or not r.Instance then return nil, nil end
    return r.Position.Y, r
end

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock(); if now - LastSlopeBoost < SLOPE.Cooldown then return end
    local char = LocalPlayer.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart"); local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    RefreshSlopeFilter()
    local vel = hrp.AssemblyLinearVelocity; if vel.Y < 2 then return end
    local flat = Vector3.new(vel.X, 0, vel.Z); local speed = flat.Magnitude; if speed < 0.1 then return end
    local fw = flat.Unit; local base = hrp.Position
    local hB = SampleGround(base - fw * 2.0, DOWN_AIR)
    local hA1, frontRay = SampleGround(base + fw * 1.0, DOWN_AIR)
    local hA2 = SampleGround(base + fw * 2.5, DOWN_AIR)
    local hA3 = SampleGround(base + fw * 4.0, DOWN_AIR)
    if not (hB and hA1 and hA2 and frontRay) then
        hB = SampleGround(base - fw * 2.0, DOWN_GROUND)
        hA1, frontRay = SampleGround(base + fw * 1.0, DOWN_GROUND)
        hA2 = SampleGround(base + fw * 2.5, DOWN_GROUND)
        hA3 = SampleGround(base + fw * 4.0, DOWN_GROUND)
    end
    if not (hB and hA1 and hA2 and frontRay) then return end
    local r1, r2 = hA1 - hB, hA2 - hB; local r3 = hA3 and (hA3 - hB) or r2
    if r1 <= 0 or r2 <= 0 then return end
    if r1 < SLOPE.MinRise or r2 < SLOPE.MinRise * 0.7 then return end
    if r1 > r2 * 2.0 then return end
    if r3 < SLOPE.MinRise * 0.5 and r2 < SLOPE.MinRise then return end
    
    local upDot = frontRay.Normal:Dot(Vector3.new(0, 1, 0))
    if upDot >= SLOPE.NormalMax or upDot <= SLOPE.NormalMin then return end
    
    LastSlopeBoost = now
    task.spawn(function()
        task.wait(0.03)
        if not State.SlopeBoostEnabled or not State.IsHoldingJump or not hrp.Parent then return end
        local v2 = hrp.AssemblyLinearVelocity; if v2.Y < 0 then return end
        local sp = Vector3.new(v2.X, 0, v2.Z).Magnitude; local over = math.max(0, sp - SLOPE.SpeedRef)
        local g = math.min(SLOPE.Gain + over * SLOPE.GainPerSpeed, SLOPE.MaxGain)
        hrp.AssemblyLinearVelocity = (fw + Vector3.new(0, SLOPE.UpComponent, 0)).Unit * math.max(sp, SLOPE.MinSpeed) * g
    end)
end

local function SaveLighting()
    if LightingSaved then return end
    LightingSaved = { Brightness=Lighting.Brightness, Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, ExposureCompensation=Lighting.ExposureCompensation, ClockTime=Lighting.ClockTime }
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

local function fadeAlpha(base) if FadeProgress <= 0 then return 1 end; if FadeProgress >= 1 then return base end; return 1 - FadeProgress * (1 - base) end
local function DestroyPredPart() if not PredData then return end; if PredData.ring then pcall(function() PredData.ring:Destroy() end) end; if PredData.dot then pcall(function() PredData.dot:Destroy() end) end; PredData = nil; CachedPredPos = nil end
local function EnsurePredPart()
    if PredData and PredData.ring and PredData.ring.Parent then return PredData end
    DestroyPredPart()
    local ring = Instance.new("Part"); ring.Name = "ZP_Pred_Ring"; ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.10, 3.5, 3.5); ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
    ring.Material = Enum.Material.Neon; ring.Color = Theme.Accent; ring.Transparency = 1; ring.TopSurface = Enum.SurfaceType.Smooth; ring.BottomSurface = Enum.SurfaceType.Smooth
    local hl = Instance.new("Highlight"); hl.FillColor = Theme.Accent; hl.FillTransparency = 1; hl.OutlineColor = Theme.AccentLight; hl.OutlineTransparency = 1
    hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = ring; hl.Parent = ring
    local dot = Instance.new("Part"); dot.Name = "ZP_Pred_Dot"; dot.Shape = Enum.PartType.Ball; dot.Size = Vector3.new(0.7, 0.7, 0.7)
    dot.Anchored = true; dot.CanCollide = false; dot.CanQuery = false; dot.CanTouch = false; dot.Material = Enum.Material.Neon; dot.Color = Theme.AccentLight; dot.Transparency = 1
    ring.Parent = Workspace; dot.Parent = Workspace
    PredData = { ring=ring, dot=dot, hl=hl }; return PredData
end
local function UpdateLandingPrediction()
    local now = os.clock(); local dt = now - lastPredUpdate; if dt < 0.033 then return end; lastPredUpdate = now
    local predPos, hrp
    if State.LandPredEnabled then
        local char = LocalPlayer.Character
        if char then
            hrp = char:FindFirstChild("HumanoidRootPart"); local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and IsAirborne(hum, hrp) then
                local c = PredictLanding(hrp, hum, 2.5)
                if c and (hrp.Position - c).Magnitude >= CFG.PredMinVisibleDist then predPos = c end
            end
        end
    end
    if predPos then
        lastPredSuccess = now; CachedPredPos = predPos
        if FadeState == "hidden" then FadeState = "showing"; FadeProgress = 0 elseif FadeState == "hiding" then FadeState = "showing" end
    else
        if (FadeState == "showing" or FadeState == "visible") and (now - lastPredSuccess > CFG.PredToleranceTime) then FadeState = "hiding" end
    end
    if FadeState == "showing" then FadeProgress = math.min(1, FadeProgress + dt * CFG.PredFadeInSpeed); if FadeProgress >= 1 then FadeState = "visible" end
    elseif FadeState == "hiding" then FadeProgress = math.max(0, FadeProgress - dt * CFG.PredFadeOutSpeed); if FadeProgress <= 0 then FadeState = "hidden"; DestroyPredPart(); return end end
    if FadeState == "hidden" or not CachedPredPos then return end
    if not hrp then local char = LocalPlayer.Character; hrp = char and char:FindFirstChild("HumanoidRootPart") end
    if not hrp then return end
    local data = EnsurePredPart()
    local dist = (hrp.Position - CachedPredPos).Magnitude
    local scale = math.clamp(1 - (dist / CFG.PredMaxDist) * (1 - CFG.PredMinScale), CFG.PredMinScale, 1)
    local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 3); local ringSize = (3.5 + pulse * 0.7) * scale
    data.ring.Size = Vector3.new(0.10, ringSize, ringSize)
    data.ring.CFrame = CFrame.new(CachedPredPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
    data.ring.Transparency = fadeAlpha(0.35 + pulse * 0.20)
    local dotSize = 0.7 * (0.6 + 0.4 * scale); data.dot.Size = Vector3.new(dotSize, dotSize, dotSize)
    data.dot.CFrame = CFrame.new(CachedPredPos + Vector3.new(0, 0.30, 0)); data.dot.Transparency = fadeAlpha(0.15 + pulse * 0.15)
    data.hl.FillTransparency = fadeAlpha(0.65 + pulse * 0.20); data.hl.OutlineTransparency = fadeAlpha(0.35 + pulse * 0.25)
end

local function TeleportToPlayer(target)
    if target == LocalPlayer then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local targetChar = target.Character
    if targetChar then
        local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
        if targetHrp then
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            hrp.CFrame = targetHrp.CFrame * CFrame.new(0, 0, 3)
        end
    end
end

CleanupPrevious()

-- ==========================================
-- UI SETUP
-- ==========================================
local ScreenGui = New("ScreenGui", {
    Name = "NoclipovUI", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = SafeParent(),
})

local WIN_W, WIN_H = 460, 640
local WM_W, WM_H = 220, 64

local LauncherIcon = New("TextButton", {
    Name = "LauncherIcon", Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0, Text = "N", TextColor3 = Theme.Text, TextSize = 18,
    Font = Enum.Font.GothamBold, AutoButtonColor = false, Parent = ScreenGui,
})
Corner(LauncherIcon, 12)
Gradient(LauncherIcon, { Theme.AccentLight, Theme.AccentDark }, 45)
Stroke(LauncherIcon, Theme.AccentLight, 1, 0.4)

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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

-- ============ WATERMARK ============
local WatermarkFrame = New("Frame", {
    Name = "Watermark", Size = UDim2.new(0, WM_W, 0, WM_H), Position = UDim2.new(0, 16, 0, 16),
    BackgroundColor3 = Theme.CardBg, BackgroundTransparency = 0.15, BorderSizePixel = 0, Active = true, Parent = ScreenGui,
})
Corner(WatermarkFrame, 10)
Stroke(WatermarkFrame, Theme.Border, 1, 0.9)
Pad(WatermarkFrame, 8, 12, 8, 12)

local WmSpeedCol = New("Frame", { Size = UDim2.new(0.33, 0, 0, 34), BackgroundTransparency = 1, Parent = WatermarkFrame })
local WmTargetCol = New("Frame", { Size = UDim2.new(0.33, 0, 0, 34), Position = UDim2.new(0.33, 0, 0, 0), BackgroundTransparency = 1, Parent = WatermarkFrame })
local WmStatusCol = New("Frame", { Size = UDim2.new(0.34, 0, 0, 34), Position = UDim2.new(0.66, 0, 0, 0), BackgroundTransparency = 1, Parent = WatermarkFrame })

New("TextLabel", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Text = "SPEED", TextColor3 = Theme.TextDim, TextSize = 8, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, Parent = WmSpeedCol })
local WmSpeedVal = New("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 14), BackgroundTransparency = 1, Text = "0.0", TextColor3 = Theme.Text, TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = WmSpeedCol })

New("TextLabel", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Text = "TARGET", TextColor3 = Theme.TextDim, TextSize = 8, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, Parent = WmTargetCol })
local WmTargetVal = New("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 14), BackgroundTransparency = 1, Text = "0", TextColor3 = Theme.Accent, TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = WmTargetCol })

New("TextLabel", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Text = "STATE", TextColor3 = Theme.TextDim, TextSize = 8, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Right, Parent = WmStatusCol })
local WmStatusVal = New("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 14), BackgroundTransparency = 1, Text = "IDLE", TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = WmStatusCol })

local WmProgressBg = New("Frame", { Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = Theme.BgDeep, BorderSizePixel = 0, Parent = WatermarkFrame })
Corner(WmProgressBg, 2)
local WmProgressFill = New("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = WmProgressBg })
Corner(WmProgressFill, 2)
Gradient(WmProgressFill, { Theme.AccentLight, Theme.AccentDark }, 0)

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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

-- ============ MAIN WINDOW ============
local MainFrame = New("Frame", {
    Name = "MainFrame", Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, ClipsDescendants = true, Active = true, Parent = ScreenGui,
})
Corner(MainFrame, 16)
Stroke(MainFrame, Theme.Border, 1, 0.94)

local Header = New("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = MainFrame })
Corner(Header, 16)
New("Frame", { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = Header })
New("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = Header })

local logoDot = New("Frame", { Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(0, 16, 0.5, -3), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = Header })
Corner(logoDot, 3)
New("UIStroke", { Color = Theme.Accent, Thickness = 4, Transparency = 0.7, Parent = logoDot })

New("TextLabel", { Size = UDim2.new(0, 160, 1, 0), Position = UDim2.new(0, 28, 0, 0), BackgroundTransparency = 1, Text = "NOCLIPOV", TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header })
New("TextLabel", { Size = UDim2.new(0, 160, 1, 0), Position = UDim2.new(0, 110, 0, 0), BackgroundTransparency = 1, Text = "// DASHBOARD", TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header })

local LightsGroup = New("Frame", { Size = UDim2.new(0, 34, 0, 12), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), BackgroundTransparency = 1, Parent = Header })
New("UIListLayout", { Padding = UDim.new(0, 8), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = LightsGroup })

local function CreateTrafficLight(color, cb)
    local btn = New("TextButton", { Size = UDim2.new(0, 12, 0, 12), BackgroundColor3 = color, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = LightsGroup })
    Corner(btn, 6)
    Stroke(btn, Color3.new(0, 0, 0), 1, 0.7)
    btn.MouseEnter:Connect(function() Tween(btn, { Size = UDim2.new(0, 13, 0, 13) }, 0.12) end)
    btn.MouseLeave:Connect(function() Tween(btn, { Size = UDim2.new(0, 12, 0, 12) }, 0.12) end)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

local TabBarHolder = New("Frame", { Size = UDim2.new(1, -32, 0, 40), Position = UDim2.new(0, 16, 0, 62), BackgroundTransparency = 1, Parent = MainFrame })
local TabBar = New("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.BgDeep, BorderSizePixel = 0, Parent = TabBarHolder })
Corner(TabBar, 10)
Stroke(TabBar, Theme.Border, 1, 0.94)
Pad(TabBar, 4, 4, 4, 4)

local SlidingPill = New("Frame", { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, ZIndex = 1, Parent = TabBar })
Corner(SlidingPill, 7)
Stroke(SlidingPill, Theme.Border, 1, 0.9)

local Content = New("ScrollingFrame", {
    Name = "Content", Size = UDim2.new(1, -32, 1, -126), Position = UDim2.new(0, 16, 0, 110),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.5, Parent = MainFrame,
})
New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Content })

local function AnimateStagger(page)
    local i = 0
    for _, child in ipairs(page:GetChildren()) do
        if child:IsA("GuiObject") then
            local origPos = child.Position
            local origTrans = child.BackgroundTransparency
            child.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset + 10)
            if child.Name ~= "InvBtn" then child.BackgroundTransparency = 1 end
            task.delay(i * 0.03, function()
                Tween(child, { Position = origPos, BackgroundTransparency = origTrans }, 0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
            end)
            i = i + 1
        end
    end
end

local function DrawIcon(parent, iconData)
    if not iconData then return end
    if type(iconData) == "string" and not (iconData == "bhop" or iconData == "slope" or iconData == "land" or iconData == "pred" or iconData == "power" or iconData == "sun") then
        New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = iconData, TextColor3 = Theme.TextDim, TextSize = 16, Font = Enum.Font.GothamBold, Parent = parent })
        return
    end

    local function line(size, pos, rot)
        local f = New("Frame", { Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.TextDim, BorderSizePixel = 0, Parent = parent })
        Corner(f, 1)
        if rot then f.Rotation = rot end
    end
    
    if iconData == "bhop" then
        line(UDim2.new(0,6,0,2), UDim2.new(0,10,0,10), 45)
        line(UDim2.new(0,6,0,2), UDim2.new(0,18,0,10), -45)
        line(UDim2.new(0,6,0,2), UDim2.new(0,10,0,16), 45)
        line(UDim2.new(0,6,0,2), UDim2.new(0,18,0,16), -45)
    elseif iconData == "slope" then line(UDim2.new(0,14,0,2), UDim2.new(0,14,0,14), 45)
    elseif iconData == "land" then line(UDim2.new(0,2,0,10), UDim2.new(0,14,0,10), 0); line(UDim2.new(0,8,0,2), UDim2.new(0,14,0,16), 0)
    elseif iconData == "pred" then line(UDim2.new(0,10,0,2), UDim2.new(0,14,0,14), 0); line(UDim2.new(0,2,0,10), UDim2.new(0,14,0,14), 0)
    elseif iconData == "power" then line(UDim2.new(0,4,0,6), UDim2.new(0,12,0,12), 30); line(UDim2.new(0,4,0,6), UDim2.new(0,16,0,18), 30)
    end
end

local function CreateToggleCard(parent, title, desc, default, iconData, cb)
    local card = New("Frame", { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Theme.CardBg, BorderSizePixel = 0, Parent = parent })
    Corner(card, 12)
    local stroke = Stroke(card, Theme.Border, 1, 0.94)

    local iconBox = New("Frame", { Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(0, 14, 0.5, -14), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = card })
    Corner(iconBox, 8)
    DrawIcon(iconBox, iconData)

    New("TextLabel", { Size = UDim2.new(1, -110, 0, 16), Position = UDim2.new(0, 52, 0, 12), BackgroundTransparency = 1, Text = title, TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    New("TextLabel", { Size = UDim2.new(1, -120, 0, 24), Position = UDim2.new(0, 52, 0, 32), BackgroundTransparency = 1, Text = desc, TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = card })

    local toggled = default
    local sw = New("TextButton", { Size = UDim2.new(0, 40, 0, 22), Position = UDim2.new(1, -56, 0.5, -11), BackgroundColor3 = toggled and Theme.Accent or Theme.Surface, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card })
    Corner(sw, 11)
    local swStroke = Stroke(sw, toggled and Theme.AccentLight or Theme.Border, 1, toggled and 0.4 or 0.94)
    local knob = New("Frame", { Size = UDim2.new(0, 18, 0, 18), Position = toggled and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9), BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = sw })
    Corner(knob, 9)

    sw.MouseButton1Click:Connect(function()
        toggled = not toggled
        Tween(sw, { BackgroundColor3 = toggled and Theme.Accent or Theme.Surface }, 0.2)
        Tween(knob, { Position = toggled and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }, 0.22)
        Tween(swStroke, { Color = toggled and Theme.AccentLight or Theme.Border, Transparency = toggled and 0.4 or 0.94 }, 0.2)
        cb(toggled)
    end)
    
    card.MouseEnter:Connect(function() Tween(card, { BackgroundColor3 = Theme.Surface }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.8 }, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, { BackgroundColor3 = Theme.CardBg }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.94 }, 0.15) end)
end

local function CreateSliderCard(parent, title, desc, min, max, default, iconData, cb, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    local card = New("Frame", { Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = Theme.CardBg, BorderSizePixel = 0, Parent = parent })
    Corner(card, 12)
    local stroke = Stroke(card, Theme.Border, 1, 0.94)
    Pad(card, 12, 16, 12, 16)

    local iconBox = New("Frame", { Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = card })
    Corner(iconBox, 8)
    DrawIcon(iconBox, iconData)

    New("TextLabel", { Size = UDim2.new(1, -90, 0, 16), Position = UDim2.new(0, 38, 0, 0), BackgroundTransparency = 1, Text = title, TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    New("TextLabel", { Size = UDim2.new(1, -100, 0, 24), Position = UDim2.new(0, 38, 0, 18), BackgroundTransparency = 1, Text = desc, TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = card })

    local pill = New("Frame", { Size = UDim2.new(0, 44, 0, 20), Position = UDim2.new(1, -44, 0, 0), BackgroundColor3 = Theme.BgDeep, BorderSizePixel = 0, Parent = card })
    Corner(pill, 10)
    Stroke(pill, Theme.Accent, 1, 0.6)
    local val = New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = string.format("%." .. decimals .. "f", default), TextColor3 = Theme.AccentLight, TextSize = 10, Font = Enum.Font.Code, Parent = pill })

    local track = New("TextButton", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 1, -6), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card })
    Corner(track, 3)
    local fill = New("Frame", { Size = UDim2.new((default - min) / (max - min), 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = track })
    Corner(fill, 3)
    Gradient(fill, { Theme.AccentLight, Theme.AccentDark }, 0)
    local knob = New("Frame", { Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0), BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = track })
    Corner(knob, 7)
    Stroke(knob, Theme.Accent, 2, 0)

    local dragging = false
    local function setV(input)
        local posX = math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
        local pct = posX / track.AbsoluteSize.X
        local v = min + (max - min) * pct
        v = math.floor(v * mult + 0.5) / mult
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = string.format("%." .. decimals .. "f", v)
        cb(v)
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true; setV(input) end
    end)
    Connections["SM_" .. title] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then setV(input) end
    end)
    Connections["SE_" .. title] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    card.MouseEnter:Connect(function() Tween(card, { BackgroundColor3 = Theme.Surface }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.8 }, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, { BackgroundColor3 = Theme.CardBg }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.94 }, 0.15) end)
end

local function CreateButtonCard(parent, title, desc, cb)
    local card = New("TextButton", { Name = "InvBtn", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = parent })
    Corner(card, 12)
    Gradient(card, { Theme.AccentLight, Theme.AccentDark }, 0)
    Stroke(card, Theme.AccentLight, 1, 0.5)

    New("TextLabel", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 8), BackgroundTransparency = 1, Text = title, TextColor3 = Theme.BgDeep, TextSize = 14, Font = Enum.Font.GothamBold, Parent = card })
    New("TextLabel", { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 26), BackgroundTransparency = 1, Text = desc, TextColor3 = Theme.BgDeep, TextTransparency = 0.3, TextSize = 10, Font = Enum.Font.Gotham, TextWrapped = true, Parent = card })

    card.MouseEnter:Connect(function() Tween(card, { Size = UDim2.new(1, 2, 0, 54), Position = UDim2.new(0, -1, 0, -1) }, 0.12) end)
    card.MouseLeave:Connect(function() Tween(card, { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 0, 0) }, 0.12) end)
    card.MouseButton1Click:Connect(function()
        Tween(card, { BackgroundTransparency = 0.15 }, 0.08)
        task.wait(0.08)
        Tween(card, { BackgroundTransparency = 0 }, 0.18)
        cb()
    end)
end

-- ============ TABS ============
local Tabs = {}
local ActiveTab = nil

local function CreateTab(label, name)
    local idx = #Tabs + 1
    local btn = New("TextButton", { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new((idx-1)*0.25, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 2, Parent = TabBar })
    local lbl = New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = string.upper(label), TextColor3 = Theme.TextDim, TextSize = 10, Font = Enum.Font.GothamBold, ZIndex = 2, Parent = btn })
    
    local page = New("ScrollingFrame", { Name = name .. "Page", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, Visible = false, Parent = Content })
    New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
    
    local tab = { Button=btn, Page=page, Label=lbl, Name=name, Index=idx }
    
    btn.MouseButton1Click:Connect(function()
        for _, t in ipairs(Tabs) do
            t.Page.Visible = false
            Tween(t.Label, { TextColor3 = Theme.TextDim }, 0.18)
        end
        page.Visible = true
        Tween(lbl, { TextColor3 = Theme.Text }, 0.18)
        Tween(SlidingPill, { Position = UDim2.new((idx-1)*0.25, 0, 0, 0) }, 0.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
        ActiveTab = tab
        if name == "Players" then
            UpdatePlayersList() 
        else
            AnimateStagger(page)
        end
    end)
    
    btn.MouseEnter:Connect(function()
        if ActiveTab == tab then return end
        Tween(lbl, { TextColor3 = Theme.Text }, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        if ActiveTab == tab then return end
        Tween(lbl, { TextColor3 = Theme.TextDim }, 0.15)
    end)
    
    table.insert(Tabs, tab)
    return page
end

local PlayPage = CreateTab("Play", "Play")
local TunePage = CreateTab("Tune", "Tune")
local VisPage  = CreateTab("Visual", "Vis")
local PlayersPage = CreateTab("Players", "Players")

-- === Play Page ===
CreateToggleCard(PlayPage, "Auto BunnyHop", "Автоматический прыжок при удержании Space", State.BhopEnabled, "🐇", function(v)
    State.BhopEnabled = v
    if not v then ResetBhopState() end
end)
CreateToggleCard(PlayPage, "Slope Boost", "Ускорение при столкновении со склоном (30-70°)", State.SlopeBoostEnabled, "⛷️", function(v)
    State.SlopeBoostEnabled = v
    if not v then LastSlopeBoost = 0 end
end)
CreateToggleCard(PlayPage, "Landing Boost", "Добавляет скорость при мягком приземлении", State.LandingBoostEnabled, "🪂", function(v)
    State.LandingBoostEnabled = v
end)
CreateToggleCard(PlayPage, "Landing Prediction", "Показывает точку падения маркером", State.LandPredEnabled, "🎯", function(v)
    State.LandPredEnabled = v
end)
CreateButtonCard(PlayPage, "INSTANT REVIVE", "Мгновенное восстановление персонажа", TriggerSelfRevive)

-- === Tune Page ===
CreateSliderCard(TunePage, "Gain Percent", "Процент прибавки за прыжок", 1, 20, CFG.GainPercent, "⚡", function(v) CFG.GainPercent = v end)
CreateSliderCard(TunePage, "Max Speed", "Максимальная скорость", 50, 250, CFG.MaxSpeed, "🚀", function(v) CFG.MaxSpeed = v end)
CreateSliderCard(TunePage, "Vertical Cap", "Лимит по оси Y", 40, 100, CFG.VertCap, "📈", function(v) CFG.VertCap = v end)
CreateSliderCard(TunePage, "Max Turn Angle", "Угол сброса буста", 15, 180, CFG.MaxTurnAngle, "📐", function(v) CFG.MaxTurnAngle = v end)
CreateSliderCard(TunePage, "Brake Rate", "Скорость торможения (Shift)", 20, 200, CFG.BrakeRate, "🛑", function(v) CFG.BrakeRate = v end)
CreateSliderCard(TunePage, "Min Speed", "Минимальная скорость", 5, 50, CFG.MinSpeed, "🐢", function(v) CFG.MinSpeed = v end)
CreateSliderCard(TunePage, "Fast Fall Force", "Сила падения (X)", 30, 300, CFG.FastFallForce, "⬇️", function(v) CFG.FastFallForce = v end)
CreateSliderCard(TunePage, "Land Boost %", "Прибавка при посадке", 0, 20, CFG.LandingBoostPercent, "📊", function(v) CFG.LandingBoostPercent = v end)
CreateSliderCard(TunePage, "Land Soft VY", "Порог мягкой посадки", 10, 60, CFG.LandingSoftVY, "📉", function(v) CFG.LandingSoftVY = v end)

-- === Visual Page ===
CreateToggleCard(VisPage, "Lighting Boost", "Улучшает освещение в игре", State.LightingBoostEnabled, "💡", function(v)
    State.LightingBoostEnabled = v
    if v then ApplyLighting() else RestoreLighting() end
end)
CreateSliderCard(VisPage, "Brightness", "Яркость", 1, 8, CFG.LightBrightness, "☀️", function(v)
    CFG.LightBrightness = v
    if State.LightingBoostEnabled then pcall(function() Lighting.Brightness = v end) end
end, 1)
CreateSliderCard(VisPage, "Ambient", "Фоновое освещение", 0, 255, CFG.LightAmbientVal, "🌤️", function(v)
    CFG.LightAmbientVal = v
    if State.LightingBoostEnabled then
        local c = Color3.fromRGB(v, v, v)
        pcall(function() Lighting.Ambient = c; Lighting.OutdoorAmbient = c end)
    end
end)
CreateSliderCard(VisPage, "Exposure", "Экспозиция камеры", -1, 2, CFG.LightExposure, "👁️", function(v)
    CFG.LightExposure = v
    if State.LightingBoostEnabled then pcall(function() Lighting.ExposureCompensation = v end) end
end, 2)

-- === Players Page Logic ===
local function CreatePlayerCard(parent, target)
    local isDead = false
    if target.Character then
        local hum = target.Character:FindFirstChildOfClass("Humanoid")
        if hum then isDead = hum.Health <= 0 end
    else
        isDead = true
    end
    
    local statusStr = isDead and "Мертв" or "Жив"
    local statusCol = isDead and Theme.Danger or Theme.Success

    local card = New("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.CardBg, BorderSizePixel = 0, Parent = parent })
    Corner(card, 12)
    local stroke = Stroke(card, Theme.Border, 1, 0.94)
    
    local iconBox = New("Frame", { Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(0, 14, 0.5, -14), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = card })
    Corner(iconBox, 8)
    New("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = string.sub(target.Name, 1, 1):upper(), TextColor3 = Theme.TextDim, TextSize = 14, Font = Enum.Font.GothamBold, Parent = iconBox })
    
    New("TextLabel", { Size = UDim2.new(1, -120, 0, 16), Position = UDim2.new(0, 52, 0, 10), BackgroundTransparency = 1, Text = target.Name, TextColor3 = Theme.Text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    New("TextLabel", { Size = UDim2.new(1, -120, 0, 14), Position = UDim2.new(0, 52, 0, 26), BackgroundTransparency = 1, Text = statusStr, TextColor3 = statusCol, TextSize = 10, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
    
    local tpBtn = New("TextButton", { Size = UDim2.new(0, 44, 0, 26), Position = UDim2.new(1, -56, 0.5, -13), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Text = "TP", TextColor3 = Theme.Text, TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = false, Parent = card })
    Corner(tpBtn, 8)
    Gradient(tpBtn, { Theme.AccentLight, Theme.AccentDark }, 0)
    
    tpBtn.MouseButton1Click:Connect(function()
        TeleportToPlayer(target)
    end)
    
    card.MouseEnter:Connect(function() Tween(card, { BackgroundColor3 = Theme.Surface }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.8 }, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, { BackgroundColor3 = Theme.CardBg }, 0.15); Tween(stroke, { Color = Theme.Border, Transparency = 0.94 }, 0.15) end)
end

function UpdatePlayersList()
    for _, child in ipairs(PlayersPage:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    
    local plrs = Players:GetPlayers()
    
    -- Безопасная сортировка (живые сверху, мертвые снизу)
    table.sort(plrs, function(a, b)
        local aDead = false
        if a.Character then
            local hum = a.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then aDead = true end
        end
        
        local bDead = false
        if b.Character then
            local hum = b.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then bDead = true end
        end
        
        if aDead == bDead then
            return a.Name:lower() < b.Name:lower()
        end
        return not aDead -- false (жив) идет перед true (мертв)
    end)
    
    for _, plr in ipairs(plrs) do
        if plr ~= LocalPlayer then
            CreatePlayerCard(PlayersPage, plr)
        end
    end
end

-- Активация вкладок
if Tabs[1] then
    Tabs[1].Page.Visible = true
    Tabs[1].Label.TextColor3 = Theme.Text
    ActiveTab = Tabs[1]
    SlidingPill.Position = UDim2.new(0, 0, 0, 0)
    task.delay(0.1, function() AnimateStagger(Tabs[1].Page) end)
end

local IsVisible = true
local function showWindow()
    IsVisible = true
    MainFrame.Visible = true
    MainFrame.Size = UDim2.new(0, WIN_W * 0.95, 0, WIN_H * 0.95)
    MainFrame.Position = UDim2.new(0.5, -WIN_W * 0.475, 0.5, -WIN_H * 0.475)
    Tween(MainFrame, { Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2) }, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end
local function hideWindow() IsVisible = false; MainFrame.Visible = false end

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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

LauncherIcon.MouseButton1Click:Connect(function() if IsVisible then hideWindow() else showWindow() end end)

-- Input & Loops
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

Connections.LandPredLoop = RunService.Heartbeat:Connect(UpdateLandingPrediction)

Connections.StatusLoop = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastPredUpdate < 0.05 then return end
    lastPredUpdate = now
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local v = hrp.AssemblyLinearVelocity
        local spd = Vector3.new(v.X, 0, v.Z).Magnitude
        
        WmSpeedVal.Text = string.format("%.1f", spd)
        WmTargetVal.Text = string.format("%.0f", TargetSpeed)
        
        local pct = math.clamp(spd / math.max(CFG.MaxSpeed, 1), 0, 1)
        Tween(WmProgressFill, { Size = UDim2.new(pct, 0, 1, 0) }, 0.1)
        
        WmStatusVal.Text = CurrentStatus
        local col = Theme.TextMuted
        if CurrentStatus == "GAIN" then col = Theme.Success
        elseif CurrentStatus == "BRAKE" then col = Theme.Danger
        elseif CurrentStatus == "AIR" then col = Theme.Accent end
        WmStatusVal.TextColor3 = col
        
        if CurrentStatus == "GAIN" then
            WmProgressFill.BackgroundColor3 = Theme.Success
        else
            WmProgressFill.BackgroundColor3 = Theme.Accent
        end
        return
    end
    WmSpeedVal.Text = "-"
    WmTargetVal.Text = "-"
    WmStatusVal.Text = "-"
    WmStatusVal.TextColor3 = Theme.TextMuted
    Tween(WmProgressFill, { Size = UDim2.new(0, 0, 1, 0) }, 0.1)
end)

Connections.PlayersUpdateLoop = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastPlayerUpdate > 1 then
        lastPlayerUpdate = now
        if ActiveTab and ActiveTab.Name == "Players" then
            UpdatePlayersList()
        end
    end
end)

MainFrame.Visible = false
task.wait(0.05)
showWindow()

function Cleanup()
    for k in pairs(State) do if type(State[k]) == "boolean" then State[k] = false end end
    for _, conn in pairs(Connections) do if typeof(conn) == "RBXScriptConnection" and conn.Connected then pcall(function() conn:Disconnect() end) end end
    table.clear(Connections)
    ResetBhopState(); WasAirborne = false; TrackedHrp = nil; TrackedLV = nil; DestroyPredPart(); RestoreLighting(); FadeState = "hidden"; FadeProgress = 0
    if ScreenGui then pcall(function() ScreenGui:Destroy() end) end
    if ENV.__ZettaCleanup == Cleanup then ENV.__ZettaCleanup = nil end
end
ENV.__ZettaCleanup = Cleanup