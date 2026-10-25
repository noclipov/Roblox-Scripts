repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334] = true, [10662098230] = true, [10808838353] = true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return
end

local BASE_FOLDER = "Noclipov/evade"
local CONFIG_PATH = BASE_FOLDER .. "/Config.json"
local MOVEMENT_BASE = BASE_FOLDER .. "/movement"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local Stats             = game:GetService("Stats")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

local IsVisible = true
local Cleanup = function() end

local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, LandingBoostPercent=5, LandingSoftVY=30, AbsCap=200,
    MaxTurnAngle=45, PredMaxDist=100, PredMinScale=0.3,
    PredFadeInSpeed=5, PredFadeOutSpeed=9, PredToleranceTime=0.25,
    PredMinVisibleDist=15,
    LightBrightness=3.0, LightAmbientVal=140, LightExposure=0.4,
    MarkerMaxDist=150,
}

-- ================= THEME =================
local Theme = {
    BgRoot     = Color3.fromRGB(14, 16, 23),
    BgLight    = Color3.fromRGB(30, 34, 46),
    BgDark     = Color3.fromRGB(22, 26, 36),
    BgDeep     = Color3.fromRGB(17, 20, 28),

    SidebarBg  = Color3.fromRGB(13, 16, 22),
    SidebarHi  = Color3.fromRGB(24, 28, 38),

    CardBg     = Color3.fromRGB(40, 45, 60),
    CardBgTop  = Color3.fromRGB(48, 54, 72),
    CardHover  = Color3.fromRGB(52, 58, 76),
    Surface    = Color3.fromRGB(52, 58, 76),
    SurfaceHi  = Color3.fromRGB(66, 73, 94),

    Border     = Color3.fromRGB(76, 84, 108),
    BorderHi   = Color3.fromRGB(108, 120, 148),

    Accent     = Color3.fromRGB(96, 208, 196),
    AccentDark = Color3.fromRGB(54, 150, 142),
    AccentSoft = Color3.fromRGB(140, 232, 220),
    AccentDeep = Color3.fromRGB(34, 108, 100),

    Success    = Color3.fromRGB(120, 216, 144),
    Danger     = Color3.fromRGB(240, 124, 124),
    Warning    = Color3.fromRGB(240, 196, 112),
    Info       = Color3.fromRGB(120, 176, 240),

    Text       = Color3.fromRGB(228, 234, 245),
    TextBright = Color3.fromRGB(250, 252, 255),
    TextDim    = Color3.fromRGB(172, 182, 200),
    TextMuted  = Color3.fromRGB(128, 140, 162),
    TextFaint  = Color3.fromRGB(92, 102, 124),

    MacRed     = Color3.fromRGB(240, 116, 116),
    MacYellow  = Color3.fromRGB(240, 196, 108),
    MacGreen   = Color3.fromRGB(120, 212, 140),
}

local State = {
    BhopEnabled=false, JumpAccelEnabled=false, IsHoldingJump=false,
    SlopeBoostEnabled=false, LandPredEnabled=false,
    LandingBoostEnabled=false, LightingBoostEnabled=false,
    WatermarkEnabled=false, MarkersEnabled=false,
    RecorderStatusEnabled=false,
}

local UI = {}
local Connections = {}

local SessionStats = { StartTime = os.clock(), MaxSpeed = 0 }
local displaySpeed = 0
local function FormatTime(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local BhopState = {
    TargetSpeed = 0, WasAirborne = false, TrackedHrp = nil, TrackedLV = nil,
    LastGameDir = nil, LastLandingBoosted = false, LastSlopeBoost = 0,
    CurrentStatus = "IDLE", LightingSaved = nil
}

local PredState = {
    Data = nil, SmoothCFrame = nil, FadeState = "hidden", FadeProgress = 0,
    LastSuccess = 0, LastUpdate = 0, ArcParts = {}, IdleTime = 0,
}

local lastOrphanSweep = 0
local awaitingBind = nil
local ToggleRefs, SliderRefs, HotkeyButtons = {}, {}, {}

local RECORD_HZ = 1 / 30
local RecorderState = {
    IsRecording = false, StartTime = 0, Frames = {}, FrameAccum = 0,
    Cache = nil, Saved = {}, InputEnabled = false,
}

local PlaybackState = {
    Active = false, Phase = "idle", AlignPos = nil, AlignOri = nil, Attach0 = nil,
    Frames = nil, Duration = 0, StartTime = 0, RecName = nil, WasBhopEnabled = false,
    WasPredEnabled = false, WasPredToggleState = false,
    ApproachStart = nil, ApproachEnd = nil, ApproachLook = nil,
    ApproachDuration = 0, ApproachStartTime = 0, ApproachStuckCheck = 0,
    StartMarker = nil,
}

local MarkerParts = {}
local UnsavedMarker = nil
local PLAY_RADIUS = 10
local PLAYBACK_ABORT_DIST = 30
local PlaybackPath = { parts = {}, active = false }

local DragState = { Active = false, Frame = nil, StartPos = nil, DragStart = nil, Size = nil, OnEnd = nil, Moved = false }
local launcherDragEndTime = 0

local SaveConfig, LoadConfig, RefreshRecorderList
local HotkeysList = {
    { id = "Bhop", title = "Toggle Bhop", default = Enum.KeyCode.B },
    { id = "Accel", title = "Toggle Jump Accel", default = Enum.KeyCode.J },
    { id = "Slope", title = "Toggle Slope Boost", default = Enum.KeyCode.V },
    { id = "Land", title = "Toggle Landing Boost", default = Enum.KeyCode.N },
    { id = "Pred", title = "Toggle Prediction", default = Enum.KeyCode.M },
    { id = "Record", title = "Toggle Record", default = Enum.KeyCode.F },
    { id = "Playback", title = "Play Nearby", default = Enum.KeyCode.P },
    { id = "Light", title = "Toggle Lighting", default = Enum.KeyCode.L },
    { id = "Brake", title = "Brake (Hold)", default = Enum.KeyCode.LeftShift },
    { id = "Fall", title = "Fast Fall (Hold)", default = Enum.KeyCode.X },
    { id = "UI", title = "Toggle UI", default = Enum.KeyCode.RightShift }
}
local Hotkeys = {}
for _, item in ipairs(HotkeysList) do Hotkeys[item.id] = item.default end

-- ================= HELPERS =================
local function SafeParent()
    if gethui then local ok, hui = pcall(gethui); if ok and hui then return hui end end
    return CoreGui
end

local function CleanupPrevious()
    if type(ENV.__ZettaCleanup) == "function" then pcall(ENV.__ZettaCleanup) end
    ENV.__ZettaCleanup = nil
    local parents = {}
    if gethui then local ok, hui = pcall(gethui); if ok and hui then table.insert(parents, hui) end end
    pcall(function() table.insert(parents, LocalPlayer:FindFirstChild("PlayerGui")) end)
    pcall(function() table.insert(parents, CoreGui) end)
    for _, parent in ipairs(parents) do
        local existing = parent and parent:FindFirstChild("NoclipovUI")
        if existing then pcall(function() existing:Destroy() end) end
    end
end

local function New(class, props)
    local inst = Instance.new(class); for k, v in pairs(props or {}) do inst[k] = v end; return inst
end
local function Corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = p; return c end
local function Gradient(p, colors, rotation)
    local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(colors[1], colors[2])
    g.Rotation = rotation or 0; g.Parent = p; return g
end
local function Stroke(p, color, thick, transp)
    local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = thick or 1; s.Transparency = transp or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end
local function Pad(p, t, r, b, l)
    local x = Instance.new("UIPadding"); x.PaddingTop=UDim.new(0,t or 0); x.PaddingBottom=UDim.new(0,b or 0)
    x.PaddingLeft=UDim.new(0,l or 0); x.PaddingRight=UDim.new(0,r or 0); x.Parent = p; return p
end
local function AddShadow(p, opts)
    opts = opts or {}
    local ok, shadow = pcall(function() return Instance.new("UIShadow") end)
    if ok and shadow then
        pcall(function()
            shadow.Color = opts.color or Color3.new(0, 0, 0)
            shadow.Transparency = opts.transparency or 0.6
            shadow.BlurRadius = opts.blur or 24
            shadow.Offset = opts.offset or Vector2.new(0, 6)
            shadow.Spread = opts.spread or 0
            shadow.Parent = p
        end)
    end
end
local function Tween(inst, props, t, style, dir)
    TweenService:Create(inst, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

-- ================= INTERACTION =================
local function EnsureUIScale(inst)
    local s = inst:FindFirstChildOfClass("UIScale")
    if not s then s = Instance.new("UIScale"); s.Scale = 1; s.Parent = inst end
    return s
end

local function ApplyHover(inst, opts)
    opts = opts or {}
    local uiscale = EnsureUIScale(inst)
    local hoverScale = opts.scale or 1.015
    local dur = opts.duration or 0.16
    local targetStroke = opts.stroke
    local baseStrokeColor = targetStroke and targetStroke.Color
    local baseStrokeTransp = targetStroke and targetStroke.Transparency
    local targetBg = opts.bg
    local baseBg = targetBg and targetBg.BackgroundColor3
    local baseBgTransp = targetBg and targetBg.BackgroundTransparency

    inst.MouseEnter:Connect(function()
        Tween(uiscale, { Scale = hoverScale }, dur)
        if targetStroke then
            Tween(targetStroke, { Color = opts.hoverStrokeColor or Theme.Accent, Transparency = opts.hoverStrokeTransp or 0.4 }, dur)
        end
        if targetBg then
            Tween(targetBg, { BackgroundColor3 = opts.hoverBgColor or Theme.CardHover, BackgroundTransparency = opts.hoverBgTransp or baseBgTransp }, dur)
        end
    end)
    inst.MouseLeave:Connect(function()
        Tween(uiscale, { Scale = 1 }, dur)
        if targetStroke then
            Tween(targetStroke, { Color = baseStrokeColor, Transparency = baseStrokeTransp }, dur)
        end
        if targetBg then
            Tween(targetBg, { BackgroundColor3 = baseBg, BackgroundTransparency = baseBgTransp }, dur)
        end
    end)
end

local function ApplyPress(inst, opts)
    opts = opts or {}
    local uiscale = EnsureUIScale(inst)
    local pressScale = opts.pressScale or 0.97
    local hoverScale = opts.hoverScale or 1.015
    local isHovered = false
    inst.MouseEnter:Connect(function() isHovered = true end)
    inst.MouseLeave:Connect(function() isHovered = false end)
    inst.MouseButton1Down:Connect(function() Tween(uiscale, { Scale = pressScale }, 0.08) end)
    inst.MouseButton1Up:Connect(function() Tween(uiscale, { Scale = isHovered and hoverScale or 1 }, 0.14) end)
end

-- ================= UNIVERSAL UI =================
local function MakeFrame(parent, props)
    local p = { Name = "Frame", Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0,0,0,0),
        AnchorPoint = Vector2.zero, BackgroundColor3 = Theme.CardBg,
        BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = parent }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("Frame", p)
end
local function MakeLabel(parent, props)
    local p = { Name = "Label", Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0,0,0,0),
        BackgroundTransparency = 1, Text = "", TextColor3 = Theme.Text,
        TextSize = 14, Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, Parent = parent }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("TextLabel", p)
end

-- ================= DRAGGABLE =================
local function MakeDraggable(frame, dragArea, isAllowedFunc, onEndFunc)
    dragArea.InputBegan:Connect(function(input)
        if isAllowedFunc and not isAllowedFunc(input) then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            DragState.Active = true; DragState.Moved = false; DragState.Frame = frame
            DragState.DragStart = Vector2.new(input.Position.X, input.Position.Y)
            DragState.StartPos = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y)
            DragState.Size = frame.AbsoluteSize
            DragState.OnEnd = onEndFunc; DragState.AllowFn = isAllowedFunc
        end
    end)
end

UserInputService.InputChanged:Connect(function(input)
    if not DragState.Active then return end
    if DragState.AllowFn and not DragState.AllowFn(input) then
        DragState.Active = false; DragState.Frame = nil; return
    end
    if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - DragState.DragStart
    if math.abs(delta.X) < 4 and math.abs(delta.Y) < 4 then return end
    DragState.Moved = true
    local ps = UI.ScreenGui.AbsoluteSize
    local x = math.clamp(DragState.StartPos.X + delta.X, 0, ps.X - DragState.Size.X)
    local y = math.clamp(DragState.StartPos.Y + delta.Y, 0, ps.Y - DragState.Size.Y)
    DragState.Frame.Position = UDim2.fromOffset(x, y)
end)

UserInputService.InputEnded:Connect(function(input)
    if not DragState.Active then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local onEnd = DragState.OnEnd; local moved = DragState.Moved
        DragState.Active = false; DragState.Frame = nil; DragState.Moved = false
        if onEnd then onEnd(moved) end
    end
end)

-- ================= STYLE =================
local function StyleCard(card, opts)
    opts = opts or {}
    Corner(card, opts.radius or 14)
    Gradient(card, { Theme.CardBgTop, Theme.CardBg }, 45)
    local stroke = Stroke(card, Theme.Border, 1, opts.strokeTransp or 0.78)
    ApplyHover(card, {
        scale = opts.hoverScale or 1.008,
        stroke = stroke,
        hoverStrokeColor = Theme.Accent,
        hoverStrokeTransp = 0.45,
        duration = 0.22,
    })
    return stroke
end

local function StylePanel(panel, opts)
    opts = opts or {}
    Corner(panel, opts.radius or 14)
    Gradient(panel, { Color3.fromRGB(34, 38, 52), Theme.BgDeep }, 45)
    local stroke = Stroke(panel, Theme.Border, 1, opts.strokeTransp or 0.65)
    AddShadow(panel, { transparency = 0.5, blur = 32, offset = Vector2.new(0, 10) })
    return stroke
end

-- ================= CORE LOGIC =================
local CHAR_RAY = RaycastParams.new(); CHAR_RAY.FilterType = Enum.RaycastFilterType.Exclude; CHAR_RAY.IgnoreWater = true
local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.FallingDown then return true end
    if hum.FloorMaterial == Enum.Material.Air then
        CHAR_RAY.FilterDescendantsInstances = { LocalPlayer.Character }
        return Workspace:Raycast(hrp.Position, Vector3.new(0, -3, 0), CHAR_RAY) == nil
    end
    return false
end

local function TriggerSelfRevive()
    local events = ReplicatedStorage:FindFirstChild("Events"); if not events then return end
    local revive = events:FindFirstChild("Revive"); if revive then pcall(function() revive:FireServer() end) end
    local setMode = events:FindFirstChild("SetPlayerMode"); if setMode then pcall(function() setMode:FireServer(true) end) end
    local ch = events:FindFirstChild("Character"); if ch and ch:FindFirstChild("Revive") then pcall(function() ch.Revive:FireServer() end) end
end

local function FindGameLV(char)
    if not char then return nil end
    local planeBest, anyFallback
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("LinearVelocity") and d.Attachment0 and d.RelativeTo == Enum.ActuatorRelativeTo.World then
            local m = d.VelocityConstraintMode
            if m == Enum.VelocityConstraintMode.Plane then
                if d.Enabled then return d end; planeBest = planeBest or d
            elseif m == Enum.VelocityConstraintMode.Vector then anyFallback = anyFallback or d end
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
    if horiz.Magnitude > CFG.AbsCap then horiz = horiz.Unit * CFG.AbsCap; clamped = true end
    if math.abs(y) > CFG.VertCap then y = (y > 0) and CFG.VertCap or -CFG.VertCap; clamped = true end
    local nv = Vector3.new(horiz.X, y, horiz.Z)
    if nv.Magnitude > CFG.AbsCap then nv = nv.Unit * CFG.AbsCap; clamped = true end
    if clamped then hrp.AssemblyLinearVelocity = nv end
end

local function ResetBhopState() BhopState.TargetSpeed = 0; BhopState.LastGameDir = nil end

local function TryBhop(dt)
    local char = LocalPlayer.Character
    if not char then ResetBhopState(); BhopState.WasAirborne = false; BhopState.TrackedHrp = nil; BhopState.TrackedLV = nil; BhopState.CurrentStatus = "NO CHAR"; return end
    local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then ResetBhopState(); BhopState.WasAirborne = false; BhopState.CurrentStatus = "IDLE"; return end
    if BhopState.TrackedHrp ~= hrp then
        BhopState.TrackedHrp = hrp; BhopState.TrackedLV = FindGameLV(char); ResetBhopState(); BhopState.WasAirborne = false
    elseif not BhopState.TrackedLV or BhopState.TrackedLV.Parent ~= hrp then BhopState.TrackedLV = FindGameLV(char) end
    if not State.BhopEnabled then ResetBhopState(); BhopState.WasAirborne = IsAirborne(hum, hrp); ClampVelocity(hrp); BhopState.CurrentStatus = "DISABLED"; return end
    local airborne = IsAirborne(hum, hrp); local humState = hum:GetState()
    local gameHoriz = ReadGameHoriz(BhopState.TrackedLV, hrp); local gameSpeed = gameHoriz.Magnitude
    local gameDir = (gameSpeed > 0.5) and gameHoriz.Unit or nil
    if airborne and not BhopState.WasAirborne then
        if (humState == Enum.HumanoidStateType.Jumping) and State.IsHoldingJump then
            local base = math.max(BhopState.TargetSpeed, gameSpeed)
            if base > 3 then
                if State.JumpAccelEnabled then
                    local boost = base * (CFG.GainPercent / 100)
                    BhopState.TargetSpeed = math.max(base, math.min(base + boost, CFG.MaxSpeed))
                else BhopState.TargetSpeed = base end
                BhopState.LastGameDir = gameDir
            end
        end
    end
    if airborne and gameDir and BhopState.LastGameDir then
        local align = math.clamp(BhopState.LastGameDir:Dot(gameDir), -1, 1)
        if math.deg(math.acos(align)) > CFG.MaxTurnAngle then BhopState.TargetSpeed = 0 end
    end
    if airborne and gameDir then BhopState.LastGameDir = gameDir end
    local braking = airborne and BhopState.TargetSpeed > 0 and Hotkeys["Brake"] and UserInputService:IsKeyDown(Hotkeys["Brake"])
    if braking then BhopState.TargetSpeed = math.max(CFG.MinSpeed, BhopState.TargetSpeed - CFG.BrakeRate * dt) end
    if airborne and BhopState.TargetSpeed >= 1 and gameDir then
        WriteGameHoriz(BhopState.TrackedLV, hrp, gameDir * BhopState.TargetSpeed)
    elseif not airborne and BhopState.TargetSpeed >= 1 and State.IsHoldingJump then
        local dir = gameDir
        if not dir and hum.MoveDirection.Magnitude > 0.01 then
            local flat = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
            if flat.Magnitude > 0.01 then dir = flat.Unit end
        end
        if dir then WriteGameHoriz(BhopState.TrackedLV, hrp, dir * BhopState.TargetSpeed) end
    end
    if not airborne and State.IsHoldingJump and hum.FloorMaterial ~= Enum.Material.Air and humState ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true); hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if airborne and Hotkeys["Fall"] and UserInputService:IsKeyDown(Hotkeys["Fall"]) then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    if not airborne and BhopState.WasAirborne and State.LandingBoostEnabled and BhopState.TargetSpeed > 0 and not BhopState.LastLandingBoosted then
        local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
        if vy <= CFG.LandingSoftVY then
            local headroom = math.max(0, CFG.MaxSpeed - BhopState.TargetSpeed)
            BhopState.TargetSpeed = BhopState.TargetSpeed + math.min(BhopState.TargetSpeed * (CFG.LandingBoostPercent / 100), headroom)
            BhopState.LastLandingBoosted = true
        end
    end
    if not airborne then BhopState.LastLandingBoosted = false; BhopState.LastGameDir = nil end
    if not airborne and not State.IsHoldingJump then ResetBhopState() end
    BhopState.CurrentStatus = braking and "BRAKE" or (airborne and BhopState.TargetSpeed > 0 and "GAIN" or (airborne and "AIR" or "IDLE"))
    BhopState.WasAirborne = airborne; ClampVelocity(hrp)
end

-- === Slope Boost ===
local SLOPE = { Cooldown=0.55, MinSpeed=25, Gain=1.15, GainPerSpeed=0.01, MaxGain=2.2, SpeedRef=40, UpComponent=1.0, MinRise=1.5, NormalMin=math.cos(math.rad(70)), NormalMax=math.cos(math.rad(30)), AirRay=20, GroundRay=12 }
local DOWN_AIR, DOWN_GROUND = Vector3.new(0, -SLOPE.AirRay, 0), Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new(); SlopeRay.FilterType = Enum.RaycastFilterType.Exclude; SlopeRay.IgnoreWater = true

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock(); if now - BhopState.LastSlopeBoost < SLOPE.Cooldown then return end
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
    local r1 = hA1.Position.Y - hB.Position.Y; local r2 = hA2.Position.Y - hB.Position.Y
    local r3 = hA3 and (hA3.Position.Y - hB.Position.Y) or r2
    if r1 <= 0 or r2 <= 0 or r1 < SLOPE.MinRise or r2 < SLOPE.MinRise * 0.7 or r1 > r2 * 2.0 then return end
    if r3 < SLOPE.MinRise * 0.5 and r2 < SLOPE.MinRise then return end
    local upDot = hA1.Normal.Y
    if upDot >= SLOPE.NormalMax or upDot <= SLOPE.NormalMin then return end
    BhopState.LastSlopeBoost = now
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
    if not BhopState.LightingSaved then
        BhopState.LightingSaved = { Brightness=Lighting.Brightness, Ambient=Lighting.Ambient, OutdoorAmbient=Lighting.OutdoorAmbient, ExposureCompensation=Lighting.ExposureCompensation, ClockTime=Lighting.ClockTime }
    end
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
    if not BhopState.LightingSaved then return end
    pcall(function()
        Lighting.Brightness = BhopState.LightingSaved.Brightness; Lighting.Ambient = BhopState.LightingSaved.Ambient
        Lighting.OutdoorAmbient = BhopState.LightingSaved.OutdoorAmbient; Lighting.ExposureCompensation = BhopState.LightingSaved.ExposureCompensation
        Lighting.ClockTime = BhopState.LightingSaved.ClockTime
    end)
    BhopState.LightingSaved = nil
end

-- === Prediction ===
local PRED_RAY = RaycastParams.new(); PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude; PRED_RAY.IgnoreWater = true

local function PredictLanding(hrp, hum, maxTime)
    local hipHeight = hum.HipHeight > 0 and hum.HipHeight or 2
    local pos = hrp.Position - Vector3.new(0, hipHeight, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity; local dt = 0.03
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
                if hit.Normal.Y > 0.4 then return hit.Position, path, (i - 1) * dt, vel end
                return nil, nil
            end
        end
        pos = np; vel = nv
    end
    return nil, nil
end

local function DestroyPred()
    if PredState.Data then
        for _, key in ipairs({"dot", "ring", "fill", "halo"}) do
            local p = PredState.Data[key]
            if p then pcall(function() p:Destroy() end) end
        end
        PredState.Data = nil
    end
    for _, p in ipairs(PredState.ArcParts) do pcall(function() p:Destroy() end) end
    table.clear(PredState.ArcParts); PredState.SmoothCFrame = nil
end

local function SweepOrphanPredParts(force)
    if not force then
        if State.LandPredEnabled then return end
        if PredState.FadeState ~= "hidden" then return end
        if PredState.Data then return end
        if #PredState.ArcParts > 0 then return end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and (obj.Name:match("^Noclipov_Pred_") or obj.Name:match("^Noclipov_LandPred_")) then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function EnsurePred()
    if PredState.Data and PredState.Data.dot and PredState.Data.dot.Parent then return PredState.Data end
    DestroyPred()
    local halo = Instance.new("Part")
    halo.Name = "Noclipov_LandPred_Halo"; halo.Shape = Enum.PartType.Cylinder
    halo.Size = Vector3.new(0.06, 5.2, 5.2); halo.Anchored = true
    halo.CanCollide = false; halo.CanQuery = false; halo.CanTouch = false
    halo.Material = Enum.Material.Neon; halo.Color = Theme.AccentSoft
    halo.Transparency = 1; halo.Parent = Workspace
    local ring = Instance.new("Part")
    ring.Name = "Noclipov_LandPred_Ring"; ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.1, 3.6, 3.6); ring.Anchored = true
    ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
    ring.Material = Enum.Material.Neon; ring.Color = Theme.Accent
    ring.Transparency = 1; ring.Parent = Workspace
    local fill = Instance.new("Part")
    fill.Name = "Noclipov_LandPred_Fill"; fill.Shape = Enum.PartType.Cylinder
    fill.Size = Vector3.new(0.13, 3.2, 3.2); fill.Anchored = true
    fill.CanCollide = false; fill.CanQuery = false; fill.CanTouch = false
    fill.Material = Enum.Material.Neon; fill.Color = Theme.AccentSoft
    fill.Transparency = 1; fill.Parent = Workspace
    local dot = Instance.new("Part")
    dot.Name = "Noclipov_LandPred_Dot"; dot.Shape = Enum.PartType.Ball
    dot.Size = Vector3.new(0.5, 0.5, 0.5); dot.Anchored = true
    dot.CanCollide = false; dot.CanQuery = false; dot.CanTouch = false
    dot.Material = Enum.Material.Neon; dot.Color = Theme.Text
    dot.Transparency = 1; dot.Parent = Workspace
    for i = 1, 22 do
        local p = Instance.new("Part")
        p.Name = "Noclipov_LandPred_Arc"; p.Shape = Enum.PartType.Block
        p.Size = Vector3.new(0.05, 0.05, 1); p.Anchored = true
        p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.Neon; p.Color = Theme.Accent
        p.Transparency = 1; p.Parent = Workspace
        table.insert(PredState.ArcParts, p)
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Noclipov_LandPred_Label"
    billboard.Size = UDim2.new(0, 140, 0, 60); billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    billboard.AlwaysOnTop = true; billboard.LightInfluence = 0
    billboard.Parent = dot
    local bBg = Instance.new("Frame")
    bBg.Size = UDim2.new(1, 0, 1, 0); bBg.BackgroundColor3 = Theme.BgDeep
    bBg.BackgroundTransparency = 1; bBg.BorderSizePixel = 0; bBg.Parent = billboard
    Corner(bBg, 10); Stroke(bBg, Theme.Accent, 1, 0.7)
    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0.5, 0, 0, 2); accentLine.Position = UDim2.new(0.25, 0, 0, 5)
    accentLine.BackgroundColor3 = Theme.Accent; accentLine.BorderSizePixel = 0
    accentLine.BackgroundTransparency = 1; accentLine.Parent = bBg
    Corner(accentLine, 1)
    local labelTitle = Instance.new("TextLabel")
    labelTitle.Size = UDim2.new(1, 0, 0, 10); labelTitle.Position = UDim2.new(0, 0, 0, 11)
    labelTitle.BackgroundTransparency = 1; labelTitle.Text = "L A N D I N G"
    labelTitle.TextColor3 = Theme.TextMuted; labelTitle.TextSize = 8
    labelTitle.Font = Enum.Font.GothamBold; labelTitle.TextTransparency = 1; labelTitle.Parent = bBg
    local labelTime = Instance.new("TextLabel")
    labelTime.Size = UDim2.new(1, 0, 0, 22); labelTime.Position = UDim2.new(0, 0, 0, 22)
    labelTime.BackgroundTransparency = 1; labelTime.Text = "0.0s"
    labelTime.TextColor3 = Theme.Text; labelTime.TextSize = 17
    labelTime.Font = Enum.Font.GothamBold; labelTime.TextTransparency = 1; labelTime.Parent = bBg
    local labelSpeed = Instance.new("TextLabel")
    labelSpeed.Size = UDim2.new(1, 0, 0, 10); labelSpeed.Position = UDim2.new(0, 0, 0, 45)
    labelSpeed.BackgroundTransparency = 1; labelSpeed.Text = "0 u/s"
    labelSpeed.TextColor3 = Theme.TextDim; labelSpeed.TextSize = 9
    labelSpeed.Font = Enum.Font.Code; labelSpeed.TextTransparency = 1; labelSpeed.Parent = bBg
    PredState.Data = {
        dot = dot, ring = ring, fill = fill, halo = halo, billboard = billboard,
        labelTitle = labelTitle, labelTime = labelTime, labelSpeed = labelSpeed,
        labelBg = bBg, labelStroke = bBg:FindFirstChildOfClass("UIStroke"), accentLine = accentLine,
    }
    return PredState.Data
end

local function fadeAlpha(base)
    if PredState.FadeProgress <= 0 then return 1 end
    if PredState.FadeProgress >= 1 then return base end
    return 1 - PredState.FadeProgress * (1 - base)
end

local function UpdatePrediction(dt)
    if not State.LandPredEnabled and PredState.FadeState == "hidden" and not PredState.Data then return end
    if PlaybackState.Active then
        if PredState.FadeState ~= "hidden" then
            PredState.FadeState = "hidden"; PredState.FadeProgress = 0; DestroyPred()
        end
        return
    end
    local now = os.clock()
    if now - PredState.LastUpdate < 0.033 then return end
    local frameDt = now - PredState.LastUpdate; PredState.LastUpdate = now
    local predPos, path, predTime, impactVel
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if State.LandPredEnabled and hrp and hum and IsAirborne(hum, hrp) then
        local c, p, t, v = PredictLanding(hrp, hum, 2.5)
        if c and (hrp.Position - c).Magnitude >= CFG.PredMinVisibleDist then predPos = c; path = p; predTime = t; impactVel = v end
    end
    if predPos then
        PredState.LastSuccess = now; PredState.IdleTime = 0
        if PredState.FadeState == "hidden" then PredState.FadeState = "showing"; PredState.FadeProgress = 0
        elseif PredState.FadeState == "hiding" then PredState.FadeState = "showing" end
    else
        if (PredState.FadeState == "showing" or PredState.FadeState == "visible") and (now - PredState.LastSuccess > CFG.PredToleranceTime) then PredState.FadeState = "hiding" end
    end
    if PredState.FadeState == "showing" then
        PredState.FadeProgress = math.min(1, PredState.FadeProgress + frameDt * CFG.PredFadeInSpeed)
        if PredState.FadeProgress >= 1 then PredState.FadeState = "visible" end
    elseif PredState.FadeState == "hiding" then
        PredState.FadeProgress = math.max(0, PredState.FadeProgress - frameDt * CFG.PredFadeOutSpeed)
        if PredState.FadeProgress <= 0 then PredState.FadeState = "hidden"; DestroyPred(); return end
    end
    if PredState.FadeState == "hidden" then
        PredState.IdleTime = PredState.IdleTime + frameDt
        if PredState.IdleTime > 2 and PredState.Data then DestroyPred() end
        return
    end
    if not hrp then return end
    local data = EnsurePred()
    if predPos then
        local targetCF = CFrame.new(predPos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
        if not PredState.SmoothCFrame then PredState.SmoothCFrame = targetCF end
        PredState.SmoothCFrame = PredState.SmoothCFrame:Lerp(targetCF, math.clamp(frameDt * 15, 0, 1))
        local dist = (hrp.Position - PredState.SmoothCFrame.Position).Magnitude
        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2)
        local pulse2 = 0.5 + 0.5 * math.sin(now * math.pi * 1.3 + 1.5)
        local progress = 0
        if predTime then
            local denom = math.max(predTime + 0.01, 0.4)
            progress = math.clamp(1 - (predTime / denom), 0, 1)
        end
        data.halo.CFrame = PredState.SmoothCFrame
        data.halo.Transparency = fadeAlpha(0.88 - pulse2 * 0.08)
        data.ring.CFrame = PredState.SmoothCFrame
        data.ring.Transparency = fadeAlpha(0.55 + pulse * 0.15)
        local fillDia = math.max(0.15, (1 - progress) * 3.2)
        data.fill.Size = Vector3.new(0.13, fillDia, fillDia)
        data.fill.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
        data.fill.Transparency = fadeAlpha(0.4 + pulse * 0.1)
        data.dot.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.18, 0))
        data.dot.Transparency = fadeAlpha(0.25 + pulse * 0.1)
        local billboardVisible = dist > 25
        if data.billboard then data.billboard.Enabled = billboardVisible end
        if billboardVisible then
            local bbAlpha = fadeAlpha(0)
            if data.labelTime then
                data.labelTime.Text = string.format("%.1fs", predTime or 0)
                data.labelTime.TextTransparency = bbAlpha
                data.labelTime.TextColor3 = (predTime and predTime < 0.5) and Theme.Warning or Theme.Text
            end
            if data.labelSpeed then
                local impactSpeed = impactVel and math.abs(impactVel.Y) or 0
                data.labelSpeed.Text = string.format("%d u/s", math.floor(impactSpeed))
                data.labelSpeed.TextTransparency = bbAlpha
                data.labelSpeed.TextColor3 = impactSpeed > 100 and Theme.Danger or impactSpeed > 60 and Theme.Warning or Theme.TextDim
            end
            if data.labelTitle then data.labelTitle.TextTransparency = bbAlpha end
            if data.accentLine then data.accentLine.BackgroundTransparency = bbAlpha + 0.3 end
            if data.labelBg then data.labelBg.BackgroundTransparency = fadeAlpha(0.35) end
            if data.labelStroke then data.labelStroke.Transparency = fadeAlpha(0.7) end
        end
        if path and #path > 2 then
            local N = #path; local numSeg = #PredState.ArcParts
            for i, seg in ipairs(PredState.ArcParts) do
                local idx1 = math.clamp(math.floor((i - 1) / numSeg * (N - 1)) + 1, 1, N - 1)
                local idx2 = math.clamp(math.floor(i / numSeg * (N - 1)) + 1, idx1 + 1, N)
                local A = path[idx1]; local B = path[idx2]
                local len = (B - A).Magnitude
                if len > 0.05 then
                    local t = (i - 1) / (numSeg - 1)
                    local midT = 1 - math.abs(t * 2 - 1)
                    local thick = 0.02 + midT * 0.06
                    seg.Size = Vector3.new(thick, thick, len)
                    seg.CFrame = CFrame.new((A + B) / 2, B)
                    seg.Color = Theme.Accent:Lerp(Theme.AccentSoft, t)
                    seg.Transparency = fadeAlpha(0.85 - midT * 0.35)
                else seg.Transparency = 1 end
            end
        else
            for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
        end
    else
        for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
    end
end

-- ================= FILE HELPERS =================
local function GetMapName()
    local ok, name = pcall(function()
        local map = workspace:FindFirstChild("Map"); if not map then return nil end
        return map:GetAttribute("MapName")
    end)
    if ok and type(name) == "string" and name ~= "" then return (name:gsub("[^%w_%-]", "_")) end
    return "Unknown"
end

local function EnsureBaseFolders()
    pcall(function() if isfolder and not isfolder("Noclipov") then makefolder("Noclipov") end end)
    pcall(function() if isfolder and not isfolder(BASE_FOLDER) then makefolder(BASE_FOLDER) end end)
    pcall(function() if isfolder and not isfolder(MOVEMENT_BASE) then makefolder(MOVEMENT_BASE) end end)
end

local function RecEnsureFolder()
    EnsureBaseFolders()
    local mapName = GetMapName()
    pcall(function()
        if isfolder and makefolder then
            local mapFolder = MOVEMENT_BASE .. "/" .. mapName
            if not isfolder(mapFolder) then makefolder(mapFolder) end
        end
    end)
end

local function RecSaveToFile(name, frames, duration)
    RecEnsureFolder()
    local data = { version = 1, name = name, mapName = GetMapName(), createdAt = os.time(), duration = duration, frameCount = #frames, frames = frames }
    local encoded
    if not pcall(function() encoded = HttpService:JSONEncode(data) end) then return false end
    if not encoded then return false end
    return pcall(writefile, MOVEMENT_BASE .. "/" .. GetMapName() .. "/" .. name .. ".json", encoded)
end

local function RecListFiles()
    local folder = MOVEMENT_BASE .. "/" .. GetMapName()
    RecEnsureFolder()
    local files = {}
    pcall(function() if listfiles and isfolder and isfolder(folder) then files = listfiles(folder) end end)
    return files
end

local function RecLoadAll()
    local list = {}
    for _, path in ipairs(RecListFiles()) do
        if type(path) == "string" and path:match("%.json$") then
            local content
            pcall(function() content = readfile(path) end)
            if content then
                local decoded
                pcall(function() decoded = HttpService:JSONDecode(content) end)
                if decoded then
                    local fname = path:match("([^/\\]+)%.json$") or "unknown"
                    table.insert(list, { name = fname, path = path, duration = decoded.duration or 0, frameCount = decoded.frameCount or #(decoded.frames or {}) })
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return list
end

local function RecDeleteFile(path) pcall(delfile, path) end

local function RecReadFirstFrame(path)
    local content
    pcall(function() content = readfile(path) end)
    if not content then return nil end
    local decoded
    pcall(function() decoded = HttpService:JSONDecode(content) end)
    if not decoded or not decoded.frames or not decoded.frames[1] then return nil end
    local f = decoded.frames[1]
    return Vector3.new(f.px, f.py, f.pz), decoded
end

local function RecSetInputEnabled(enabled)
    RecorderState.InputEnabled = enabled
    if not UI.RecNameBox then return end
    UI.RecNameBox.TextEditable = enabled
    UI.RecNameBox.TextColor3 = enabled and Theme.Text or Theme.TextMuted
    UI.RecNameBox.BackgroundTransparency = enabled and 0.3 or 0.7
    if UI.RecSaveLbl then UI.RecSaveLbl.TextColor3 = enabled and Theme.BgDeep or Theme.TextMuted; UI.RecSaveLbl.TextTransparency = enabled and 0 or 0.4 end
    if UI.RecSaveBtn then UI.RecSaveBtn.BackgroundTransparency = enabled and 0.05 or 0.75 end
    if UI.RecCancelLbl then UI.RecCancelLbl.TextColor3 = enabled and Theme.Text or Theme.TextMuted; UI.RecCancelLbl.TextTransparency = enabled and 0 or 0.4 end
    if UI.RecCancelBtn then UI.RecCancelBtn.BackgroundTransparency = enabled and 0.1 or 0.75 end
end

local function TrimLeadingStatic(frames, threshold)
    threshold = threshold or 1.0
    if #frames < 3 then return frames end
    local p0 = Vector3.new(frames[1].px, frames[1].py, frames[1].pz)
    local lastStaticIdx = 1; local anyMoved = false
    for i = 2, #frames do
        local p = Vector3.new(frames[i].px, frames[i].py, frames[i].pz)
        if (p - p0).Magnitude > threshold then anyMoved = true; break end
        lastStaticIdx = i
    end
    if not anyMoved then return {} end
    if lastStaticIdx == 1 then return frames end
    local trimmed = {}
    local offsetT = frames[lastStaticIdx].t
    for i = lastStaticIdx, #frames do
        local f = frames[i]
        table.insert(trimmed, { t = f.t - offsetT, px = f.px, py = f.py, pz = f.pz, vx = f.vx, vy = f.vy, vz = f.vz, lx = f.lx, ly = f.ly, lz = f.lz })
    end
    return trimmed
end

local function TrimTrailingStatic(frames, threshold)
    threshold = threshold or 1.0
    if #frames < 3 then return frames end
    local pEnd = Vector3.new(frames[#frames].px, frames[#frames].py, frames[#frames].pz)
    local firstStaticIdx = #frames
    for i = #frames - 1, 1, -1 do
        local p = Vector3.new(frames[i].px, frames[i].py, frames[i].pz)
        if (p - pEnd).Magnitude > threshold then break end
        firstStaticIdx = i
    end
    if firstStaticIdx == #frames then return frames end
    if firstStaticIdx <= 2 then return frames end
    local trimmed = {}
    for i = 1, firstStaticIdx do table.insert(trimmed, frames[i]) end
    return trimmed
end

local function CanStartRecording()
    local char = LocalPlayer.Character
    if not char then return false, "No character" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false, "No humanoid" end
    if hum.FloorMaterial == Enum.Material.Air or IsAirborne(hum, hrp) then return false, "Player in air" end
    if hrp.AssemblyLinearVelocity.Magnitude > 2 then return false, "Player is moving" end
    return true
end

local function RecStart()
    if RecorderState.IsRecording or PlaybackState.Active then return end
    local ok, reason = CanStartRecording()
    if not ok then
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = reason; UI.RecStatusLabel.TextColor3 = Theme.Warning end
        return
    end
    RecorderState.IsRecording = true
    RecorderState.StartTime = os.clock()
    RecorderState.Frames = {}
    RecorderState.FrameAccum = 0
    RecorderState.Cache = nil
    RecSetInputEnabled(false)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "● REC"; UI.RecStatusLabel.TextColor3 = Theme.Danger end
end

local function RecStop(cache)
    if not RecorderState.IsRecording then return end
    RecorderState.IsRecording = false
    local frames = RecorderState.Frames
    local duration = os.clock() - RecorderState.StartTime
    RecorderState.Frames = {}; RecorderState.FrameAccum = 0
    if cache and #frames >= 2 then
        local trimmed = TrimLeadingStatic(frames, 1.0)
        if #trimmed == 0 then
            RecorderState.Cache = nil
            if UI.RecStatusLabel then UI.RecStatusLabel.Text = "No movement recorded"; UI.RecStatusLabel.TextColor3 = Theme.Warning end
            RecSetInputEnabled(false); return
        end
        local trimmed2 = TrimTrailingStatic(trimmed, 1.0)
        if #trimmed2 < 2 then
            RecorderState.Cache = nil
            if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Too short"; UI.RecStatusLabel.TextColor3 = Theme.Warning end
            RecSetInputEnabled(false); return
        end
        local newDuration = trimmed2[#trimmed2].t
        RecorderState.Cache = { frames = trimmed2, duration = newDuration, frameCount = #trimmed2 }
        local trimmedCount = #frames - #trimmed2
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = trimmedCount > 0 and string.format("Ready: %.1fs · %d (trimmed %d)", newDuration, #trimmed2, trimmedCount) or string.format("Ready: %.1fs · %d frames", newDuration, #trimmed2)
            UI.RecStatusLabel.TextColor3 = Theme.Success
        end
        RecSetInputEnabled(true); CreateUnsavedMarker(trimmed2)
    else
        RecorderState.Cache = nil
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted end
        RecSetInputEnabled(false)
    end
end

-- ================= MARKERS =================
local function CreateMarkerVisual(pos, color, isUnsaved)
    local base = Instance.new("Part")
    base.Shape = Enum.PartType.Cylinder
    base.Size = Vector3.new(0.08, 3.0, 3.0)
    base.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
    base.Anchored = true; base.CanCollide = false; base.CanQuery = false; base.CanTouch = false
    base.Material = Enum.Material.Neon; base.Color = color; base.Transparency = 0.55; base.Parent = Workspace

    local pulse = Instance.new("Part")
    pulse.Shape = Enum.PartType.Cylinder
    pulse.Size = Vector3.new(0.06, 3.0, 3.0)
    pulse.CFrame = base.CFrame
    pulse.Anchored = true; pulse.CanCollide = false; pulse.CanQuery = false; pulse.CanTouch = false
    pulse.Material = Enum.Material.Neon; pulse.Color = color; pulse.Transparency = 0.4; pulse.Parent = Workspace

    local crystal = Instance.new("Part")
    crystal.Shape = Enum.PartType.Ball
    crystal.Size = Vector3.new(0.7, 0.7, 0.7)
    crystal.Position = pos + Vector3.new(0, 0.3, 0)
    crystal.Anchored = true; crystal.CanCollide = false; crystal.CanQuery = false; crystal.CanTouch = false
    crystal.Material = Enum.Material.Neon; crystal.Color = color; crystal.Transparency = 0.1; crystal.Parent = Workspace

    local glow = Instance.new("Part")
    glow.Shape = Enum.PartType.Ball
    glow.Size = Vector3.new(1.3, 1.3, 1.3)
    glow.Position = crystal.Position
    glow.Anchored = true; glow.CanCollide = false; glow.CanQuery = false; glow.CanTouch = false
    glow.Material = Enum.Material.Neon; glow.Color = color; glow.Transparency = 0.88; glow.Parent = Workspace

    local beam = Instance.new("Part")
    beam.Size = Vector3.new(0.08, 2.2, 0.08)
    beam.Position = pos + Vector3.new(0, 1.4, 0)
    beam.Anchored = true; beam.CanCollide = false; beam.CanQuery = false; beam.CanTouch = false
    beam.Material = Enum.Material.Neon; beam.Color = color; beam.Transparency = 0.7; beam.Parent = Workspace

    local light = Instance.new("PointLight")
    light.Color = color; light.Range = 12; light.Brightness = 1.5; light.Shadows = false
    light.Parent = crystal

    return { base = base, pulse = pulse, crystal = crystal, glow = glow, beam = beam, light = light, pos = pos }
end

local function DestroyMarkerVisual(m)
    if not m then return end
    for _, key in ipairs({"base", "pulse", "crystal", "glow", "beam"}) do
        if m[key] then pcall(function() m[key]:Destroy() end) end
    end
    if m.billboard then pcall(function() m.billboard:Destroy() end) end
end

local function BuildMarkerBillboard(crystalPart, title, subtitle, color, isUnsaved)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 190, 0, 48)
    bb.StudsOffset = Vector3.new(0, 2.4, 0)
    bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.Parent = crystalPart
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0); bg.BackgroundColor3 = Theme.BgDeep
    bg.BackgroundTransparency = 0.15; bg.BorderSizePixel = 0; bg.Parent = bb
    Corner(bg, 9); Stroke(bg, color, 1, 0.35)
    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 3, 0, 22); accentBar.Position = UDim2.new(0, 0, 0.5, -11)
    accentBar.BackgroundColor3 = color; accentBar.BorderSizePixel = 0; accentBar.Parent = bg
    Corner(accentBar, 1.5)
    if isUnsaved then
        local badge = Instance.new("Frame")
        badge.Size = UDim2.new(0, 46, 0, 12); badge.Position = UDim2.new(1, -50, 0, 4)
        badge.BackgroundColor3 = color; badge.BackgroundTransparency = 0.2; badge.BorderSizePixel = 0; badge.Parent = bg
        Corner(badge, 3)
        MakeLabel(badge, { Text = "UNSAVED", TextColor3 = Theme.BgDeep, TextSize = 7, TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold })
    end
    MakeLabel(bg, { Size = UDim2.new(1, -60, 0, 16), Position = UDim2.new(0, 10, 0, 6), Text = title, TextSize = 13, TextColor3 = Theme.Text, TextTruncate = Enum.TextTruncate.AtEnd })
    MakeLabel(bg, { Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 10, 0, 25), Text = subtitle, TextColor3 = Theme.TextDim, TextSize = 10, Font = Enum.Font.Gotham })
    return bb
end

local function DestroyMarker(name)
    local m = MarkerParts[name]
    if not m then return end
    DestroyMarkerVisual(m); MarkerParts[name] = nil
end

local function CreateMarker(rec)
    local startPos, decoded = RecReadFirstFrame(rec.path)
    if not startPos or not decoded then return end
    local visual = CreateMarkerVisual(startPos, Theme.Accent, false)
    visual.billboard = BuildMarkerBillboard(visual.crystal, rec.name, string.format("%.1fs · %d frames", rec.duration, rec.frameCount), Theme.Accent, false)
    visual.rec = rec; visual.startPos = startPos; visual.isFar = false
    visual.pulsePhase = math.random() * 2; visual.pulseBaseSize = 3.0
    MarkerParts[rec.name] = visual
end

local function RefreshMarkers()
    for name in pairs(MarkerParts) do DestroyMarker(name) end
    if not State.MarkersEnabled then return end
    for _, rec in ipairs(RecorderState.Saved) do CreateMarker(rec) end
end

local function SetMarkersVisible(v)
    State.MarkersEnabled = v
    if v then RefreshMarkers()
    else for name in pairs(MarkerParts) do DestroyMarker(name) end end
end

local function DestroyUnsavedMarker()
    if not UnsavedMarker then return end
    DestroyMarkerVisual(UnsavedMarker); UnsavedMarker = nil
end

function CreateUnsavedMarker(frames)
    DestroyUnsavedMarker()
    if not frames or #frames < 1 then return end
    local f = frames[1]
    local pos = Vector3.new(f.px, f.py, f.pz)
    local visual = CreateMarkerVisual(pos, Theme.Warning, true)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "Unsaved Recording", string.format("%.1fs · %d frames", frames[#frames].t, #frames), Theme.Warning, true)
    visual.startPos = pos; visual.isFar = false; visual.pulsePhase = 0; visual.pulseBaseSize = 3.0; visual.isUnsaved = true
    UnsavedMarker = visual
end

local function DestroyPlaybackStartMarker()
    if not PlaybackState.StartMarker then return end
    DestroyMarkerVisual(PlaybackState.StartMarker); PlaybackState.StartMarker = nil
end

local function CreatePlaybackStartMarker(pos)
    DestroyPlaybackStartMarker()
    local visual = CreateMarkerVisual(pos, Theme.Success, false)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "START POINT", PlaybackState.RecName or "?", Theme.Success, false)
    visual.isFar = false; visual.pulsePhase = 0; visual.pulseBaseSize = 3.0
    PlaybackState.StartMarker = visual
end

-- ================= PLAYBACK PATH =================
local function ClearPlaybackPath()
    for _, p in ipairs(PlaybackPath.parts) do pcall(function() p:Destroy() end) end
    table.clear(PlaybackPath.parts); PlaybackPath.active = false
end

local function CreatePlaybackPath(frames, count)
    ClearPlaybackPath()
    if not frames or #frames < 2 then return end
    count = count or 50
    local total = #frames
    for i = 1, count do
        local idx = math.clamp(math.floor((i - 1) / (count - 1) * (total - 1)) + 1, 1, total)
        local f = frames[idx]
        local p = Instance.new("Part")
        p.Name = "Noclipov_PlaybackPath_" .. i; p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.22, 0.22, 0.22); p.Position = Vector3.new(f.px, f.py, f.pz)
        p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.Neon; p.Color = Theme.Accent; p.Transparency = 0.7; p.Parent = Workspace
        p:SetAttribute("t", f.t); table.insert(PlaybackPath.parts, p)
    end
    PlaybackPath.active = true
end

local function UpdatePlaybackPath(elapsed)
    if not PlaybackPath.active then return end
    local now = os.clock()
    for _, p in ipairs(PlaybackPath.parts) do
        if p.Parent then
            local t = p:GetAttribute("t") or 0
            if elapsed > t then
                local alpha = math.clamp((elapsed - t) / 1.2, 0, 1)
                p.Transparency = 0.7 + alpha * 0.3
                p.Size = Vector3.new(0.22 - alpha * 0.12, 0.22 - alpha * 0.12, 0.22 - alpha * 0.12)
            else
                p.Transparency = 0.55 + (0.5 + 0.5 * math.sin(now * math.pi * 3 + t * 2)) * 0.15
            end
        end
    end
end

-- ================= PLAYBACK =================
local function CreatePlaybackConstraints(hrp, pos, lookVec)
    local attach0 = Instance.new("Attachment")
    attach0.Name = "Noclipov_PB_Attach"; attach0.Parent = hrp
    local alignPos = Instance.new("AlignPosition")
    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
    alignPos.Attachment0 = attach0
    alignPos.MaxForce = 1e6; alignPos.Responsiveness = 200
    alignPos.ApplyAtCenterOfMass = false
    alignPos.Position = pos; alignPos.Parent = hrp
    local alignOri = Instance.new("AlignOrientation")
    alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOri.Attachment0 = attach0
    alignOri.MaxTorque = 1e6; alignOri.Responsiveness = 200
    alignOri.CFrame = CFrame.lookAt(pos, pos + lookVec)
    alignOri.Parent = hrp
    return attach0, alignPos, alignOri
end

local function StopPlayback(silent)
    if not PlaybackState.Active then return end
    local wasBhop = PlaybackState.WasBhopEnabled
    local wasPred = PlaybackState.WasPredEnabled
    local wasPredToggle = PlaybackState.WasPredToggleState
    PlaybackState.Active = false; PlaybackState.Phase = "idle"
    pcall(function() if PlaybackState.AlignPos then PlaybackState.AlignPos:Destroy() end end)
    pcall(function() if PlaybackState.AlignOri then PlaybackState.AlignOri:Destroy() end end)
    pcall(function() if PlaybackState.Attach0 then PlaybackState.Attach0:Destroy() end end)
    PlaybackState.AlignPos = nil; PlaybackState.AlignOri = nil; PlaybackState.Attach0 = nil
    PlaybackState.Frames = nil; PlaybackState.RecName = nil; PlaybackState.WasBhopEnabled = false
    PlaybackState.ApproachStart = nil; PlaybackState.ApproachEnd = nil; PlaybackState.ApproachLook = nil
    PlaybackState.WasPredEnabled = false; PlaybackState.WasPredToggleState = false
    ClearPlaybackPath(); DestroyPlaybackStartMarker()
    if not silent and wasBhop then if ToggleRefs["Auto BunnyHop"] then ToggleRefs["Auto BunnyHop"](true) end end
    if wasPred and not silent then
        State.LandPredEnabled = true
        if ToggleRefs["Landing Prediction"] and wasPredToggle then pcall(function() ToggleRefs["Landing Prediction"](true) end) end
    end
    if UI.RecStatusLabel and not silent then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted end
end

local function StartPlayback(recName, frames, duration)
    if PlaybackState.Active then StopPlayback() end
    if not frames or #frames < 2 or RecorderState.IsRecording then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum then return end

    PlaybackState.WasBhopEnabled = State.BhopEnabled
    if State.BhopEnabled then State.BhopEnabled = false; if ToggleRefs["Auto BunnyHop"] then ToggleRefs["Auto BunnyHop"](false) end end
    PlaybackState.WasPredEnabled = State.LandPredEnabled
    PlaybackState.WasPredToggleState = State.LandPredEnabled
    if State.LandPredEnabled then
        State.LandPredEnabled = false
        if ToggleRefs["Landing Prediction"] then ToggleRefs["Landing Prediction"](false) end
        DestroyPred(); PredState.FadeState = "hidden"; PredState.FadeProgress = 0
    end

    PlaybackState.RecName = recName
    local firstFrame = frames[1]
    local firstPos = Vector3.new(firstFrame.px, firstFrame.py, firstFrame.pz)
    local firstLook = Vector3.new(firstFrame.lx, firstFrame.ly, firstFrame.lz)
    if firstLook.Magnitude < 0.01 then firstLook = Vector3.new(0, 0, -1) end

    CreatePlaybackStartMarker(firstPos)
    PlaybackState.Active = true
    PlaybackState.Frames = frames
    PlaybackState.Duration = duration or frames[#frames].t

    if hum.WalkSpeed < 8 then pcall(function() hum.WalkSpeed = 16 end) end

    local dist = (firstPos - hrp.Position).Magnitude
    if dist < 3 then
        PlaybackState.Phase = "play"
        PlaybackState.StartTime = os.clock()
        PlaybackState.Attach0, PlaybackState.AlignPos, PlaybackState.AlignOri = CreatePlaybackConstraints(hrp, firstPos, firstLook.Unit)
    else
        PlaybackState.Phase = "approach"
        PlaybackState.ApproachStart = hrp.Position
        PlaybackState.ApproachEnd = firstPos
        PlaybackState.ApproachLook = firstLook.Unit
        PlaybackState.ApproachDuration = math.clamp(dist / 20, 1.0, 15.0)
        PlaybackState.ApproachStartTime = os.clock()
        PlaybackState.ApproachStuckCheck = 0
        pcall(function() hum:MoveTo(firstPos) end)
    end
    CreatePlaybackPath(frames, 50)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "▶ Playing: " .. recName; UI.RecStatusLabel.TextColor3 = Theme.Accent end
end

local function TryStartNearbyPlayback()
    if PlaybackState.Active then StopPlayback(); return end
    if RecorderState.IsRecording then
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Stop recording first"; UI.RecStatusLabel.TextColor3 = Theme.Warning end
        return
    end
    if RecorderState.Cache then
        local frames = RecorderState.Cache.frames
        if not frames or #frames < 2 then return end
        StartPlayback("[unsaved]", frames, RecorderState.Cache.duration)
        return
    end
    local char = LocalPlayer.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local nearestRec, nearestDecoded, nearestDist = nil, nil, math.huge
    for _, rec in ipairs(RecorderState.Saved) do
        local pos, decoded = RecReadFirstFrame(rec.path)
        if pos and decoded then
            local d = (hrp.Position - pos).Magnitude
            if d < nearestDist then nearestDist = d; nearestRec = rec; nearestDecoded = decoded end
        end
    end
    if not nearestRec or nearestDist > PLAY_RADIUS then
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = string.format("No marker within %d studs", PLAY_RADIUS); UI.RecStatusLabel.TextColor3 = Theme.Warning
            task.delay(2, function()
                if UI.RecStatusLabel and not PlaybackState.Active and not RecorderState.IsRecording then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted end
            end)
        end
        return
    end
    StartPlayback(nearestRec.name, nearestDecoded.frames, nearestDecoded.duration)
end

local function UpdatePlayback()
    if not PlaybackState.Active then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum then StopPlayback(); return end

    if PlaybackState.Phase == "approach" then
        local elapsed = os.clock() - PlaybackState.ApproachStartTime
        local dist = (hrp.Position - PlaybackState.ApproachEnd).Magnitude
        if dist < 4 or elapsed > PlaybackState.ApproachDuration + 8 then
            PlaybackState.Phase = "play"
            PlaybackState.StartTime = os.clock()
            PlaybackState.Attach0, PlaybackState.AlignPos, PlaybackState.AlignOri = CreatePlaybackConstraints(hrp, PlaybackState.ApproachEnd, PlaybackState.ApproachLook)
            return
        end
        if elapsed > 1.5 and PlaybackState.ApproachStuckCheck == 0 then
            local moved = (hrp.Position - PlaybackState.ApproachStart).Magnitude
            if moved < 2 then
                PlaybackState.Phase = "play"
                PlaybackState.StartTime = os.clock()
                PlaybackState.Attach0, PlaybackState.AlignPos, PlaybackState.AlignOri = CreatePlaybackConstraints(hrp, PlaybackState.ApproachEnd, PlaybackState.ApproachLook)
                PlaybackState.ApproachStuckCheck = 1
                return
            else PlaybackState.ApproachStuckCheck = -1 end
        end
        if hum.WalkSpeed < 8 then pcall(function() hum.WalkSpeed = 16 end) end
        pcall(function() hum:MoveTo(PlaybackState.ApproachEnd) end)
        return
    end

    local frames = PlaybackState.Frames
    if not frames or #frames < 2 then StopPlayback(); return end
    local elapsed = os.clock() - PlaybackState.StartTime
    if elapsed >= PlaybackState.Duration then StopPlayback(); return end

    if PlaybackState.AlignPos and PlaybackState.AlignPos.Parent then
        local dist = (hrp.Position - PlaybackState.AlignPos.Position).Magnitude
        if dist > PLAYBACK_ABORT_DIST then
            StopPlayback()
            if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Playback aborted (too far)"; UI.RecStatusLabel.TextColor3 = Theme.Warning end
            return
        end
    end

    local lo, hi = 1, #frames
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if frames[mid].t <= elapsed then lo = mid else hi = mid end
    end
    local A = frames[lo]; local B = frames[hi]
    local dtAB = B.t - A.t
    local alpha = dtAB > 0 and math.clamp((elapsed - A.t) / dtAB, 0, 1) or 0
    local targetPos = Vector3.new(A.px + (B.px - A.px) * alpha, A.py + (B.py - A.py) * alpha, A.pz + (B.pz - A.pz) * alpha)
    local lookVec = Vector3.new(A.lx + (B.lx - A.lx) * alpha, A.ly + (B.ly - A.ly) * alpha, A.lz + (B.lz - A.lz) * alpha)
    if lookVec.Magnitude < 0.01 then lookVec = Vector3.new(0, 0, -1) end
    if PlaybackState.AlignPos and PlaybackState.AlignPos.Parent then PlaybackState.AlignPos.Position = targetPos end
    if PlaybackState.AlignOri and PlaybackState.AlignOri.Parent then PlaybackState.AlignOri.CFrame = CFrame.lookAt(targetPos, targetPos + lookVec.Unit) end
    UpdatePlaybackPath(elapsed)
end

-- ================= UI SETUP =================
CleanupPrevious()
EnsureBaseFolders()

UI.ScreenGui = New("ScreenGui", { Name = "NoclipovUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = SafeParent() })

local WIN_W, WIN_H = 660, 720
local SIDEBAR_W = 160
local HEADER_H = 62
local PAD = 16
local WM_W, WM_H = 320, 172
local RM_W, RM_H = 320, 172

local function DrawIcon(parent, iconData)
    if not iconData then return end
    MakeLabel(parent, { Text = iconData, TextColor3 = Theme.TextDim, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })
end

local function MakeIconBadge(parent, size, pos, iconData)
    if not iconData then return nil, nil end
    local box = MakeFrame(parent, {
        Size = UDim2.new(0, size, 0, size),
        Position = pos,
        BackgroundColor3 = Theme.SurfaceHi,
        BackgroundTransparency = 0.15
    })
    Corner(box, math.floor(size * 0.32))
    Gradient(box, { Theme.SurfaceHi, Theme.CardBg }, 45)
    local stroke = Stroke(box, Theme.Border, 1, 0.55)
    DrawIcon(box, iconData)
    return box, stroke
end

-- ================= IMPROVED SWITCH =================
local function MakeSwitch(parent, default, cb, opts)
    opts = opts or {}
    local swW, swH = opts.width or 48, opts.height or 26
    local knobSize = opts.knobSize or 20
    local padRight = opts.padRight or 16
    local toggled = default

    local glowRing = MakeFrame(parent, {
        Size = UDim2.new(0, swW + 14, 0, swH + 14),
        Position = UDim2.new(1, -(swW + padRight + 7), 0.5, -(swH + 14) / 2),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = toggled and 0.9 or 1,
        ZIndex = 2
    })
    Corner(glowRing, (swH + 14) / 2)
    AddShadow(glowRing, { color = Theme.Accent, transparency = toggled and 0.35 or 1, blur = 20, offset = Vector2.new(0, 0) })

    local sw = New("TextButton", {
        Size = UDim2.new(0, swW, 0, swH),
        Position = UDim2.new(1, -(swW + padRight), 0.5, -swH / 2),
        BackgroundColor3 = toggled and Theme.AccentDark or Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0, Text = "",
        AutoButtonColor = false, Parent = parent, ZIndex = 3,
        ClipsDescendants = true,
    })
    Corner(sw, math.floor(swH / 2))
    local swGradient = Gradient(sw, { Theme.AccentSoft, Theme.AccentDark }, toggled and 0 or 180)
    local swStroke = Stroke(sw, toggled and Theme.AccentSoft or Theme.Border, 1.2, toggled and 0.25 or 0.55)

    local knobPosOn = UDim2.new(1, -(knobSize + 3), 0.5, -knobSize / 2)
    local knobPosOff = UDim2.new(0, 3, 0.5, -knobSize / 2)

    local knob = MakeFrame(sw, {
        Size = UDim2.new(0, knobSize, 0, knobSize),
        Position = toggled and knobPosOn or knobPosOff,
        BackgroundColor3 = Color3.fromRGB(240, 244, 252),
        ZIndex = 4
    })
    Corner(knob, math.floor(knobSize / 2))
    Gradient(knob, { Color3.fromRGB(252, 254, 255), Color3.fromRGB(216, 222, 236) }, 90)
    Stroke(knob, Color3.new(0, 0, 0), 1, 0.9)

    local knobDot = MakeFrame(knob, {
        Size = UDim2.new(0, 6, 0, 6),
        Position = UDim2.new(0.5, -3, 0.5, -3),
        BackgroundColor3 = Theme.AccentDark,
        BackgroundTransparency = toggled and 0 or 1,
        ZIndex = 5
    })
    Corner(knobDot, 3)

    local function set(val)
        toggled = val
        Tween(sw, { BackgroundColor3 = toggled and Theme.AccentDark or Theme.Surface }, 0.24)
        Tween(knob, { Position = toggled and knobPosOn or knobPosOff }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        Tween(swStroke, { Color = toggled and Theme.AccentSoft or Theme.Border, Transparency = toggled and 0.25 or 0.55 }, 0.22)
        Tween(knobDot, { BackgroundTransparency = toggled and 0 or 1 }, 0.22)
        Tween(glowRing, { BackgroundTransparency = toggled and 0.9 or 1 }, 0.3)
        if swGradient then swGradient.Rotation = toggled and 0 or 180 end
        if cb then cb(toggled) end
    end

    sw.MouseButton1Click:Connect(function()
        set(not toggled)
        if SaveConfig then SaveConfig() end
    end)

    return set
end

-- ================= IMPROVED SLIDER =================
local function MakeSlider(parent, min, max, default, cb, opts)
    opts = opts or {}
    local decimals = opts.decimals or 0
    local mult = 10 ^ decimals
    local pillW = opts.pillWidth or 62

    local pill = MakeFrame(parent, {
        Size = UDim2.new(0, pillW, 0, 22),
        Position = UDim2.new(1, -pillW, 0, 2),
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.15,
        ZIndex = 2
    })
    Corner(pill, 11); Stroke(pill, Theme.Accent, 1, 0.6)
    Gradient(pill, { Theme.BgDeep, Color3.fromRGB(26, 30, 42) }, 90)
    local val = MakeLabel(pill, {
        Text = string.format("%." .. decimals .. "f", default),
        TextColor3 = Theme.Accent, TextSize = 11, Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Center
    })

    local track = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 1, -12),
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = parent,
        ZIndex = 3
    })
    Corner(track, 5); Stroke(track, Theme.Border, 1, 0.7)

    for i = 1, 4 do
        local tick = MakeFrame(track, {
            Size = UDim2.new(0, 1, 0, 4),
            Position = UDim2.new(i / 5, 0, 0.5, -2),
            BackgroundColor3 = Theme.BorderHi,
            BackgroundTransparency = 0.55,
            ZIndex = 3,
        })
    end

    local fill = MakeFrame(track, {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0,
        ZIndex = 3
    })
    Corner(fill, 5); Gradient(fill, { Theme.AccentDeep, Theme.AccentSoft }, 0)

    local knobGlow = MakeFrame(track, {
        Size = UDim2.new(0, 24, 0, 24),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.85, ZIndex = 4
    })
    Corner(knobGlow, 12)
    AddShadow(knobGlow, { color = Theme.Accent, transparency = 0.5, blur = 14, offset = Vector2.new(0, 0) })

    local knob = MakeFrame(track, {
        Size = UDim2.new(0, 16, 0, 16),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        BackgroundColor3 = Theme.Text, ZIndex = 5
    })
    Corner(knob, 8); Stroke(knob, Theme.Accent, 2, 0.15)
    Gradient(knob, { Color3.fromRGB(252, 254, 255), Color3.fromRGB(214, 220, 232) }, 90)

    local function updateUI(v)
        v = math.clamp(v, min, max); v = math.floor(v * mult + 0.5) / mult
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        knobGlow.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = string.format("%." .. decimals .. "f", v)
        if cb then cb(v) end
    end

    local dragging = false
    local function handleInput(input)
        updateUI(min + (max - min) * (math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X) / track.AbsoluteSize.X))
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; handleInput(input)
            Tween(knob, { Size = UDim2.new(0, 18, 0, 18) }, 0.12)
            Tween(knobGlow, { BackgroundTransparency = 0.7, Size = UDim2.new(0, 28, 0, 28) }, 0.14)
            Tween(pill, { BackgroundTransparency = 0.05, BackgroundColor3 = Theme.Surface }, 0.15)
            if opts.onDragStart then opts.onDragStart() end
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            handleInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            Tween(knob, { Size = UDim2.new(0, 16, 0, 16) }, 0.1)
            Tween(knobGlow, { BackgroundTransparency = 0.85, Size = UDim2.new(0, 24, 0, 24) }, 0.14)
            Tween(pill, { BackgroundTransparency = 0.15, BackgroundColor3 = Theme.BgDeep }, 0.15)
            if opts.onDragEnd then opts.onDragEnd() end
            if SaveConfig then SaveConfig() end
        end
    end)

    return updateUI
end

local function MakeKeycap(parent, defaultKey, actionId, opts)
    opts = opts or {}
    local w, h = opts.width or 78, opts.height or 28

    local holder = MakeFrame(parent, {
        Size = UDim2.new(0, w, 0, h),
        Position = UDim2.new(1, -w, 0.5, -h / 2),
        BackgroundTransparency = 1, ZIndex = 2
    })
    Corner(holder, 7)

    local bottom = MakeFrame(holder, {
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 3),
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.3, ZIndex = 1
    })
    Corner(bottom, 7)

    local bindBtn = New("TextButton", {
        Size = UDim2.new(1, 0, 1, -3),
        BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Text = defaultKey and defaultKey.Name or "None",
        TextColor3 = defaultKey and Theme.Text or Theme.TextMuted,
        TextSize = 11, Font = Enum.Font.Code, AutoButtonColor = false,
        ZIndex = 2, Parent = holder
    })
    Corner(bindBtn, 6)
    local bindStroke = Stroke(bindBtn, Theme.Border, 1, 0.55)
    Gradient(bindBtn, { Theme.SurfaceHi, Theme.Surface }, 45)

    ApplyHover(bindBtn, {
        scale = 1.05,
        stroke = bindStroke,
        hoverStrokeColor = Theme.Accent,
        hoverStrokeTransp = 0.3,
    })
    ApplyPress(bindBtn, { pressScale = 0.96, hoverScale = 1.05 })

    HotkeyButtons[actionId] = bindBtn

    bindBtn.MouseButton1Click:Connect(function()
        awaitingBind = actionId
        bindBtn.Text = "..."
        bindBtn.TextColor3 = Theme.Accent
        Tween(bindBtn, { BackgroundColor3 = Theme.AccentDark }, 0.12)
    end)
    bindBtn.MouseButton2Click:Connect(function()
        Hotkeys[actionId] = nil
        bindBtn.Text = "None"
        bindBtn.TextColor3 = Theme.TextMuted
        Tween(bindBtn, { BackgroundColor3 = Theme.Surface }, 0.12)
        if SaveConfig then SaveConfig() end
    end)

    return bindBtn
end

-- ================= LAUNCHER =================
UI.LauncherIcon = New("TextButton", {
    Name = "LauncherIcon", Size = UDim2.new(0, 52, 0, 52),
    Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0,
    Text = "N", TextColor3 = Theme.TextBright, TextSize = 22,
    Font = Enum.Font.GothamBold, AutoButtonColor = false, ZIndex = 2, Parent = UI.ScreenGui
})
Corner(UI.LauncherIcon, 15)
Gradient(UI.LauncherIcon, { Theme.Accent, Theme.AccentDeep }, 45)
local launcherStroke = Stroke(UI.LauncherIcon, Theme.AccentSoft, 1.2, 0.4)
AddShadow(UI.LauncherIcon, { color = Theme.Accent, transparency = 0.5, blur = 28, offset = Vector2.new(0, 8) })
ApplyHover(UI.LauncherIcon, { scale = 1.06, stroke = launcherStroke, hoverStrokeColor = Theme.AccentSoft, hoverStrokeTransp = 0.1 })
ApplyPress(UI.LauncherIcon, { pressScale = 0.94, hoverScale = 1.06 })
MakeDraggable(UI.LauncherIcon, UI.LauncherIcon, nil, function(moved)
    if SaveConfig then SaveConfig() end
    if moved then launcherDragEndTime = os.clock() end
end)

-- ================= WATERMARK (REDESIGNED) =================
UI.WatermarkFrame = MakeFrame(UI.ScreenGui, {
    Name = "Watermark", Size = UDim2.new(0, WM_W, 0, WM_H),
    Position = UDim2.new(0, 16, 0, 16),
    BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.05,
    Active = true, Visible = State.WatermarkEnabled
})
StylePanel(UI.WatermarkFrame)
Pad(UI.WatermarkFrame, 16, 18, 14, 18)

local wmHeader = MakeFrame(UI.WatermarkFrame, { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 })
MakeLabel(wmHeader, {
    Size = UDim2.new(1, -80, 1, 0), Text = "N O C L I P O V",
    TextSize = 10, TextColor3 = Theme.Text, Font = Enum.Font.GothamBold
})

UI.WmLivePill = MakeFrame(wmHeader, {
    Size = UDim2.new(0, 66, 0, 14),
    Position = UDim2.new(1, -66, 0, 0),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.3,
    ZIndex = 2
})
Corner(UI.WmLivePill, 7)
Stroke(UI.WmLivePill, Theme.Border, 1, 0.55)
UI.WmLiveDot = MakeFrame(UI.WmLivePill, {
    Size = UDim2.new(0, 5, 0, 5),
    Position = UDim2.new(0, 8, 0.5, -2.5),
    BackgroundColor3 = Theme.TextMuted, ZIndex = 3
})
Corner(UI.WmLiveDot, 2.5)
UI.WmLiveLabel = MakeLabel(UI.WmLivePill, {
    Size = UDim2.new(1, -16, 1, 0),
    Position = UDim2.new(0, 17, 0, 0),
    Text = "IDLE", TextSize = 8,
    Font = Enum.Font.GothamBold,
    TextColor3 = Theme.TextMuted
})

local wmDiv1 = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.65
})
Gradient(wmDiv1, { Theme.Border, Theme.BgDeep }, 0)

local wmHero = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 50),
    Position = UDim2.new(0, 0, 0, 31),
    BackgroundTransparency = 1
})
UI.WmSpeedVal = MakeLabel(wmHero, {
    Size = UDim2.new(1, 0, 0, 34),
    Text = "0.0",
    TextColor3 = Theme.TextBright,
    TextSize = 32, Font = Enum.Font.GothamBold
})
MakeLabel(wmHero, {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 36),
    Text = "U N I T S   /   S E C O N D",
    TextColor3 = Theme.TextMuted, TextSize = 8,
    Font = Enum.Font.GothamBold
})

local wmDiv2 = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0, 89),
    BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.65
})
Gradient(wmDiv2, { Theme.Border, Theme.BgDeep }, 0)

local wmMiniGrid = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 32),
    Position = UDim2.new(0, 0, 0, 98),
    BackgroundTransparency = 1
})
local colW = 0.25
local function MakeMiniStat(parent, x, label)
    local col = MakeFrame(parent, {
        Size = UDim2.new(colW, -2, 1, 0),
        Position = UDim2.new(x + 0.002, 0, 0, 0),
        BackgroundTransparency = 1
    })
    local val = MakeLabel(col, {
        Size = UDim2.new(1, 0, 0, 18),
        Text = "--", TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextColor3 = Theme.Text
    })
    MakeLabel(col, {
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 0, 21),
        Text = label, TextSize = 7,
        TextColor3 = Theme.TextMuted,
        Font = Enum.Font.GothamBold
    })
    return val
end
UI.WmFpsVal  = MakeMiniStat(wmMiniGrid, 0,     "F P S")
UI.WmPingVal = MakeMiniStat(wmMiniGrid, colW,  "P I N G")
UI.WmMaxVal  = MakeMiniStat(wmMiniGrid, colW*2,"M A X")
UI.WmTimeVal = MakeMiniStat(wmMiniGrid, colW*3,"T I M E")

local WmSpeedBarBg = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 4),
    Position = UDim2.new(0, 0, 1, -4),
    BackgroundColor3 = Theme.BgLight,
    BackgroundTransparency = 0.4
})
Corner(WmSpeedBarBg, 2); Stroke(WmSpeedBarBg, Theme.Border, 1, 0.65)
UI.WmSpeedBarFill = MakeFrame(WmSpeedBarBg, {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Accent
})
Corner(UI.WmSpeedBarFill, 2)
Gradient(UI.WmSpeedBarFill, { Theme.Accent, Theme.AccentSoft }, 0)

MakeDraggable(UI.WatermarkFrame, UI.WatermarkFrame,
    function() return IsVisible end,
    function() if SaveConfig then SaveConfig() end end)

-- ================= RECORDER STATUS (REDESIGNED) =================
UI.RecorderStatusFrame = MakeFrame(UI.ScreenGui, {
    Name = "RecorderStatus", Size = UDim2.new(0, RM_W, 0, RM_H),
    Position = UDim2.new(0, 16, 0, 200),
    BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.05,
    Active = true, Visible = State.RecorderStatusEnabled
})
StylePanel(UI.RecorderStatusFrame)
Pad(UI.RecorderStatusFrame, 16, 18, 14, 18)

local recHeaderRow = MakeFrame(UI.RecorderStatusFrame, { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 })
MakeLabel(recHeaderRow, {
    Size = UDim2.new(1, -80, 1, 0),
    Text = "R E C O R D E R",
    TextSize = 10, TextColor3 = Theme.Accent,
    Font = Enum.Font.GothamBold
})
UI.RecStatusPill = MakeFrame(recHeaderRow, {
    Size = UDim2.new(0, 66, 0, 14),
    Position = UDim2.new(1, -66, 0, 0),
    BackgroundColor3 = Theme.Surface,
    BackgroundTransparency = 0.3,
    ZIndex = 2
})
Corner(UI.RecStatusPill, 7)
Stroke(UI.RecStatusPill, Theme.Border, 1, 0.55)
UI.RecStatusPillDot = MakeFrame(UI.RecStatusPill, {
    Size = UDim2.new(0, 5, 0, 5),
    Position = UDim2.new(0, 8, 0.5, -2.5),
    BackgroundColor3 = Theme.TextMuted, ZIndex = 3
})
Corner(UI.RecStatusPillDot, 2.5)
UI.RecStatusPillLabel = MakeLabel(UI.RecStatusPill, {
    Size = UDim2.new(1, -16, 1, 0),
    Position = UDim2.new(0, 17, 0, 0),
    Text = "IDLE", TextSize = 8,
    Font = Enum.Font.GothamBold,
    TextColor3 = Theme.TextMuted
})

local recDiv = MakeFrame(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.65
})
Gradient(recDiv, { Theme.Border, Theme.BgDeep }, 0)

local recHero = MakeFrame(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 50),
    Position = UDim2.new(0, 0, 0, 31),
    BackgroundTransparency = 1
})
local durCol = MakeFrame(recHero, { Size = UDim2.new(0.5, -6, 1, 0), BackgroundTransparency = 1 })
UI.RecDurationVal = MakeLabel(durCol, {
    Size = UDim2.new(1, 0, 0, 34),
    Text = "--", TextSize = 26,
    Font = Enum.Font.GothamBold,
    TextColor3 = Theme.TextBright
})
MakeLabel(durCol, {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 36),
    Text = "D U R A T I O N", TextSize = 8,
    TextColor3 = Theme.TextMuted,
    Font = Enum.Font.GothamBold
})
local framesCol = MakeFrame(recHero, {
    Size = UDim2.new(0.5, -6, 1, 0),
    Position = UDim2.new(0.5, 6, 0, 0),
    BackgroundTransparency = 1
})
UI.RecFramesVal = MakeLabel(framesCol, {
    Size = UDim2.new(1, 0, 0, 34),
    Text = "--", TextSize = 26,
    Font = Enum.Font.GothamBold,
    TextColor3 = Theme.TextBright,
    TextXAlignment = Enum.TextXAlignment.Right
})
MakeLabel(framesCol, {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 36),
    Text = "F R A M E S", TextSize = 8,
    TextColor3 = Theme.TextMuted,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Right
})

local recDiv2 = MakeFrame(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0, 89),
    BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.65
})
Gradient(recDiv2, { Theme.Border, Theme.BgDeep }, 0)

UI.RecInfoLabel = MakeLabel(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 0, 0, 98),
    Text = "Idle", TextColor3 = Theme.TextDim,
    TextSize = 13, Font = Enum.Font.GothamBold,
    TextTruncate = Enum.TextTruncate.AtEnd
})
UI.RecSubLabel = MakeLabel(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 0, 118),
    Text = "", TextColor3 = Theme.TextMuted,
    TextSize = 9, Font = Enum.Font.Gotham,
    TextTruncate = Enum.TextTruncate.AtEnd
})

UI.RecProgBg = MakeFrame(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 4),
    Position = UDim2.new(0, 0, 1, -4),
    BackgroundColor3 = Theme.BgLight,
    BackgroundTransparency = 0.4,
    Visible = false
})
Corner(UI.RecProgBg, 2); Stroke(UI.RecProgBg, Theme.Border, 1, 0.65)
UI.RecProgFill = MakeFrame(UI.RecProgBg, {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Accent
})
Corner(UI.RecProgFill, 2)
Gradient(UI.RecProgFill, { Theme.Accent, Theme.AccentSoft }, 0)

MakeDraggable(UI.RecorderStatusFrame, UI.RecorderStatusFrame,
    function() return IsVisible end,
    function() if SaveConfig then SaveConfig() end end)

local function UpdateRecorderStatus()
    if not UI.RecorderStatusFrame.Visible then return end
    local now = os.clock()
    local pillText, pillColor

    if RecorderState.IsRecording then
        local dur = now - RecorderState.StartTime
        pillText, pillColor = "REC", Theme.Danger
        UI.RecDurationVal.Text = string.format("%.1fs", dur)
        UI.RecDurationVal.TextColor3 = Theme.Danger
        UI.RecFramesVal.Text = tostring(#RecorderState.Frames)
        UI.RecFramesVal.TextColor3 = Theme.Text
        UI.RecInfoLabel.Text = "Recording..."
        UI.RecInfoLabel.TextColor3 = Theme.Danger
        UI.RecSubLabel.Text = string.format("Press %s to stop", (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—")
        UI.RecSubLabel.TextColor3 = Theme.TextDim
        UI.RecProgBg.Visible = false
        UI.RecStatusPill.BackgroundTransparency = 0.75 + math.sin(now * math.pi * 3) * 0.15
    elseif PlaybackState.Active then
        UI.RecFramesVal.Text = tostring(#(PlaybackState.Frames or {}))
        UI.RecFramesVal.TextColor3 = Theme.Text
        if PlaybackState.Phase == "approach" then
            local a = math.clamp((now - PlaybackState.ApproachStartTime) / PlaybackState.ApproachDuration, 0, 1)
            pillText, pillColor = "WALK", Theme.Accent
            UI.RecDurationVal.Text = "--"
            UI.RecDurationVal.TextColor3 = Theme.TextMuted
            UI.RecInfoLabel.Text = PlaybackState.RecName or "?"
            UI.RecInfoLabel.TextColor3 = Theme.Text
            UI.RecSubLabel.Text = string.format("Walking · %.0f%%", a * 100)
            UI.RecSubLabel.TextColor3 = Theme.Accent
            UI.RecProgBg.Visible = true
            UI.RecProgFill.Size = UDim2.new(a, 0, 1, 0)
        else
            local elapsed = now - PlaybackState.StartTime
            local pct = math.clamp(elapsed / math.max(0.01, PlaybackState.Duration or 1), 0, 1)
            pillText, pillColor = "PLAY", Theme.Accent
            UI.RecDurationVal.Text = string.format("%.1fs", elapsed)
            UI.RecDurationVal.TextColor3 = Theme.Accent
            UI.RecInfoLabel.Text = PlaybackState.RecName or "?"
            UI.RecInfoLabel.TextColor3 = Theme.Text
            UI.RecSubLabel.Text = string.format("%.1fs / %.1fs · %.0f%%", elapsed, PlaybackState.Duration or 0, pct * 100)
            UI.RecSubLabel.TextColor3 = Theme.TextDim
            UI.RecProgBg.Visible = true
            UI.RecProgFill.Size = UDim2.new(pct, 0, 1, 0)
        end
        UI.RecStatusPill.BackgroundTransparency = 0.3
    elseif RecorderState.Cache then
        pillText, pillColor = "READY", Theme.Success
        UI.RecDurationVal.Text = string.format("%.1fs", RecorderState.Cache.duration)
        UI.RecDurationVal.TextColor3 = Theme.Success
        UI.RecFramesVal.Text = tostring(RecorderState.Cache.frameCount)
        UI.RecFramesVal.TextColor3 = Theme.Text
        UI.RecInfoLabel.Text = "Ready to save"
        UI.RecInfoLabel.TextColor3 = Theme.Success
        UI.RecSubLabel.Text = string.format("Save in REC tab · %s to play", (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—")
        UI.RecSubLabel.TextColor3 = Theme.TextDim
        UI.RecProgBg.Visible = false
        UI.RecStatusPill.BackgroundTransparency = 0.3
    else
        pillText, pillColor = "IDLE", Theme.TextMuted
        UI.RecDurationVal.Text = "--"
        UI.RecDurationVal.TextColor3 = Theme.TextMuted
        UI.RecFramesVal.Text = "--"
        UI.RecFramesVal.TextColor3 = Theme.TextMuted
        UI.RecInfoLabel.Text = "Idle"
        UI.RecInfoLabel.TextColor3 = Theme.TextDim
        UI.RecSubLabel.Text = string.format("%s: rec · %s: play · %d saved",
            (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—",
            (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—",
            #RecorderState.Saved)
        UI.RecSubLabel.TextColor3 = Theme.TextMuted
        UI.RecProgBg.Visible = false
        UI.RecStatusPill.BackgroundTransparency = 0.3
    end

    UI.RecStatusPill.BackgroundColor3 = pillColor
    UI.RecStatusPillDot.BackgroundColor3 = pillColor
    UI.RecStatusPillLabel.Text = pillText
    UI.RecStatusPillLabel.TextColor3 = pillColor
end

-- ================= MAIN WINDOW =================
UI.MainFrame = MakeFrame(UI.ScreenGui, {
    Name = "MainFrame", Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3 = Theme.BgLight, BackgroundTransparency = 0.03,
    ClipsDescendants = true, Active = true
})
Corner(UI.MainFrame, 18)
Gradient(UI.MainFrame, { Theme.BgLight, Theme.BgDark }, 45)
AddShadow(UI.MainFrame, { transparency = 0.4, blur = 48, offset = Vector2.new(0, 16) })
Stroke(UI.MainFrame, Theme.Border, 1, 0.5)

UI.Header = MakeFrame(UI.MainFrame, { Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.15 })
Corner(UI.Header, 18)
MakeFrame(UI.Header, { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.15 })
local headerBorder = MakeFrame(UI.Header, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.7 })
Gradient(headerBorder, { Theme.Border, Theme.BgDeep }, 0)

local logoGlow = MakeFrame(UI.Header, { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 14, 0.5, -13), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.82 })
Corner(logoGlow, 13)
AddShadow(logoGlow, { color = Theme.Accent, transparency = 0.4, blur = 20, offset = Vector2.new(0, 0) })
local logoDot = MakeFrame(UI.Header, { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 21, 0.5, -6), BackgroundColor3 = Theme.Accent })
Corner(logoDot, 6); Stroke(logoDot, Theme.AccentSoft, 2, 0.55)
Gradient(logoDot, { Theme.AccentSoft, Theme.AccentDark }, 45)

MakeLabel(UI.Header, { Size = UDim2.new(0, 100, 1, 0), Position = UDim2.new(0, 44, 0, 0), Text = "NOCLIPOV", TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = Theme.Text })
MakeLabel(UI.Header, { Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(0, 134, 0, 0), Text = "// PANEL", TextColor3 = Theme.TextMuted, TextSize = 10, Font = Enum.Font.Code })

local verBadge = MakeFrame(UI.Header, { Size = UDim2.new(0, 44, 0, 20), Position = UDim2.new(0, 196, 0.5, -10), BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.15 })
Corner(verBadge, 6); Stroke(verBadge, Theme.Border, 1, 0.55)
Gradient(verBadge, { Theme.SurfaceHi, Theme.Surface }, 45)
MakeLabel(verBadge, { Text = "v6.0", TextColor3 = Theme.Accent, TextSize = 9, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Center })

local LightsGroup = MakeFrame(UI.Header, { Size = UDim2.new(0, 48, 0, 15), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), BackgroundTransparency = 1 })
New("UIListLayout", { Padding = UDim.new(0, 10), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = LightsGroup })

local function CreateTrafficLight(color, hoverSymbol, cb)
    local btn = New("TextButton", { Size = UDim2.new(0, 14, 0, 14), BackgroundColor3 = color, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = LightsGroup })
    Corner(btn, 7); Stroke(btn, Color3.new(0,0,0), 1, 0.75)
    local inner = MakeLabel(btn, { Text = "", TextColor3 = Color3.fromRGB(60, 30, 30), TextSize = 9, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
    local uiscale = Instance.new("UIScale"); uiscale.Scale = 1; uiscale.Parent = btn
    btn.MouseEnter:Connect(function()
        Tween(uiscale, { Scale = 1.18 }, 0.12)
        if inner then inner.Text = hoverSymbol; Tween(inner, { TextTransparency = 0.35 }, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        Tween(uiscale, { Scale = 1 }, 0.12)
        if inner then Tween(inner, { TextTransparency = 1 }, 0.12) end
    end)
    btn.MouseButton1Click:Connect(cb)
end

-- ================= SIDEBAR =================
UI.Sidebar = MakeFrame(UI.MainFrame, {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundColor3 = Theme.SidebarBg,
    BackgroundTransparency = 0,
    ZIndex = 1,
})

local sideDivider = MakeFrame(UI.Sidebar, {
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = Theme.Border,
    BackgroundTransparency = 0.65,
})
Gradient(sideDivider, { Theme.Border, Theme.SidebarBg }, 90)

Pad(UI.Sidebar, 10, 12, 12, 12)

UI.TabContainer = MakeFrame(UI.Sidebar, {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
})
New("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = UI.TabContainer,
})

UI.Content = New("ScrollingFrame", {
    Name = "Content",
    Size = UDim2.new(1, -(SIDEBAR_W + PAD * 2 + 12), 1, -(HEADER_H + PAD * 2)),
    Position = UDim2.new(0, SIDEBAR_W + PAD, 0, HEADER_H + PAD),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    Parent = UI.MainFrame,
    AutomaticCanvasSize = Enum.AutomaticSize.None,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ElasticBehavior = Enum.ElasticBehavior.Never,
    ScrollingDirection = Enum.ScrollingDirection.Y,
})

local SB_W = 4
UI.ScrollBarTrack = MakeFrame(UI.MainFrame, {
    Name = "ScrollBarTrack",
    Size = UDim2.new(0, SB_W, 1, -(HEADER_H + PAD * 2)),
    Position = UDim2.new(1, -12, 0, HEADER_H + PAD),
    BackgroundColor3 = Theme.BgDeep,
    BackgroundTransparency = 0.7,
    ZIndex = 10,
    Visible = false,
})
Corner(UI.ScrollBarTrack, SB_W/2)
Stroke(UI.ScrollBarTrack, Theme.Border, 1, 0.8)
UI.ScrollBarThumb = MakeFrame(UI.ScrollBarTrack, {
    Name = "ScrollBarThumb",
    Size = UDim2.new(1, 0, 0.2, 0),
    BackgroundColor3 = Theme.Accent,
    BackgroundTransparency = 0.15,
    ZIndex = 11,
})
Corner(UI.ScrollBarThumb, SB_W/2)
Stroke(UI.ScrollBarThumb, Theme.AccentSoft, 1, 0.5)

local function UpdateScrollBar()
    if not UI.Content.ScrollingEnabled then UI.ScrollBarTrack.Visible = false; return end
    local viewH = UI.Content.AbsoluteSize.Y
    local canvasH = UI.Content.CanvasSize.Y.Offset
    if canvasH <= viewH or canvasH == 0 or viewH == 0 then UI.ScrollBarTrack.Visible = false; return end
    UI.ScrollBarTrack.Visible = true
    local thumbH = math.max(0.08, viewH / canvasH)
    local maxScroll = canvasH - viewH
    UI.ScrollBarThumb.Size = UDim2.new(1, 0, thumbH, 0)
    UI.ScrollBarThumb.Position = UDim2.new(0, 0,
        maxScroll > 0 and math.clamp(UI.Content.CanvasPosition.Y / maxScroll, 0, 1) * (1 - thumbH) or 0, 0)
end
UI.Content:GetPropertyChangedSignal("CanvasPosition"):Connect(UpdateScrollBar)
UI.Content:GetPropertyChangedSignal("CanvasSize"):Connect(UpdateScrollBar)
UI.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateScrollBar)

local sbDragging, sbStartY, sbStartCanvasY = false, 0, 0
UI.ScrollBarTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sbDragging = true; sbStartY = input.Position.Y; sbStartCanvasY = UI.Content.CanvasPosition.Y
        Tween(UI.ScrollBarThumb, { BackgroundColor3 = Theme.AccentSoft }, 0.12)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not sbDragging then return end
    if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then return end
    local maxScroll = math.max(0, UI.Content.CanvasSize.Y.Offset - UI.Content.AbsoluteSize.Y)
    if maxScroll == 0 then return end
    local scrollPerPixel = maxScroll / math.max(1, UI.ScrollBarTrack.AbsoluteSize.Y - UI.ScrollBarThumb.AbsoluteSize.Y)
    UI.Content.CanvasPosition = Vector2.new(0, math.clamp(sbStartCanvasY + (input.Position.Y - sbStartY) * scrollPerPixel, 0, maxScroll))
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sbDragging = false; Tween(UI.ScrollBarThumb, { BackgroundColor3 = Theme.Accent }, 0.12)
    end
end)

local ActiveTab = nil
local function UpdateContentScroll()
    if not ActiveTab or not ActiveTab.Page then return end
    local pageY = ActiveTab.Page.AbsoluteSize.Y; local frameY = UI.Content.AbsoluteSize.Y
    if pageY < 1 then task.delay(0.05, UpdateContentScroll); return end
    UI.Content.CanvasSize = UDim2.new(0, 0, 0, pageY + 4)
    if pageY <= frameY + 2 then
        UI.Content.ScrollingEnabled = false
        if UI.Content.CanvasPosition.Y ~= 0 then UI.Content.CanvasPosition = Vector2.new(0, 0) end
    else UI.Content.ScrollingEnabled = true end
    UpdateScrollBar()
end

-- ================= CARDS =================
local function CreateCardText(card, title, desc, x, titleY, descY, rightMargin)
    MakeLabel(card, { Size = UDim2.new(1, -rightMargin, 0, 17), Position = UDim2.new(0, x, 0, titleY), Text = title, TextSize = 13, Font = Enum.Font.GothamBold })
    MakeLabel(card, { Size = UDim2.new(1, -rightMargin, 0, 14), Position = UDim2.new(0, x, 0, descY), Text = desc, TextColor3 = Theme.TextDim, TextSize = 11, Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd })
end

local function CreateCardShell(parent, opts)
    opts = opts or {}
    local card = MakeFrame(parent, {
        Name = opts.name or "Card",
        Size = UDim2.new(1, 0, 0, opts.height or 70),
        BackgroundColor3 = Theme.CardBg,
        BackgroundTransparency = 0.05
    })
    local stroke = StyleCard(card, { radius = opts.radius or 14, hoverScale = opts.hoverScale or 1.008 })
    if opts.padding then Pad(card, opts.padding[1], opts.padding[2], opts.padding[3], opts.padding[4]) end
    return card, stroke
end

local function CreateToggleCard(parent, title, desc, default, iconData, cb)
    local card, stroke = CreateCardShell(parent, { height = 76, hoverScale = 1.008 })
    local _, iconStroke = MakeIconBadge(card, 36, UDim2.new(0, 18, 0.5, -18), iconData)
    local textX = iconData and 66 or 20
    local textRight = iconData and 138 or 88
    CreateCardText(card, title, desc, textX, 16, 38, textRight)

    local setToggle = MakeSwitch(card, default, function(v)
        Tween(stroke, { Color = v and Theme.Accent or Theme.Border, Transparency = v and 0.4 or 0.78 }, 0.22)
        stroke.Thickness = v and 1.5 or 1
        if iconStroke then
            Tween(iconStroke, { Color = v and Theme.Accent or Theme.Border, Transparency = v and 0.3 or 0.55 }, 0.22)
        end
        cb(v)
    end)
    ToggleRefs[title] = setToggle
end

local function CreateSliderCard(parent, title, desc, min, max, default, iconData, cb, decimals)
    local card, stroke = CreateCardShell(parent, { height = 98, padding = {14, 16, 14, 18}, hoverScale = 1.008 })
    MakeIconBadge(card, 34, UDim2.new(0, 0, 0, 0), iconData)
    local textX = iconData and 46 or 0
    local textRight = iconData and 115 or 75
    CreateCardText(card, title, desc, textX, 0, 19, textRight)

    local updateUI = MakeSlider(card, min, max, default, cb, {
        decimals = decimals or 0,
        onDragStart = function()
            Tween(stroke, { Color = Theme.Accent, Transparency = 0.5 }, 0.15)
            stroke.Thickness = 1.5
        end,
        onDragEnd = function()
            Tween(stroke, { Color = Theme.Border, Transparency = 0.78 }, 0.15)
            stroke.Thickness = 1
        end,
    })
    SliderRefs[title] = updateUI
end

local function CreateButtonCard(parent, title, desc, cb)
    local card = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = parent
    })
    Corner(card, 14)
    Gradient(card, { Theme.Accent, Theme.AccentDeep }, 45)
    local stroke = Stroke(card, Theme.AccentSoft, 1.2, 0.35)
    AddShadow(card, { color = Theme.Accent, transparency = 0.7, blur = 22, offset = Vector2.new(0, 6) })
    ApplyHover(card, { scale = 1.02, stroke = stroke, hoverStrokeColor = Theme.AccentSoft, hoverStrokeTransp = 0.1 })
    ApplyPress(card, { pressScale = 0.98, hoverScale = 1.02 })

    MakeLabel(card, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 10), Text = title, TextColor3 = Theme.BgDeep, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center })
    MakeLabel(card, { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 32), Text = desc, TextColor3 = Theme.BgDeep, TextTransparency = 0.1, TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })

    card.MouseButton1Click:Connect(cb)
end

local function CreateHotkeyCard(parent, title, actionId, defaultKey)
    local card = CreateCardShell(parent, { height = 50, padding = {12, 16, 12, 18}, hoverScale = 1.008 })
    MakeLabel(card, { Size = UDim2.new(1, -95, 1, 0), Text = title, TextSize = 13, Font = Enum.Font.GothamBold })
    MakeKeycap(card, defaultKey, actionId)
end

local function CreateSection(parent, text)
    local holder = MakeFrame(parent, { Name = "SectionHolder", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 })
    local bar = MakeFrame(holder, { Size = UDim2.new(0, 3, 0, 13), Position = UDim2.new(0, 6, 0.5, -6.5), BackgroundColor3 = Theme.Accent })
    Corner(bar, 1.5)
    Gradient(bar, { Theme.AccentSoft, Theme.AccentDark }, 90)
    MakeLabel(holder, { Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 18, 0, 0), Text = string.upper(text), TextColor3 = Theme.TextDim, TextSize = 10, Font = Enum.Font.GothamBold })
end

-- ================= TABS (SIDEBAR) =================
local Tabs = {}

local function SwitchTab(idx)
    local tab = Tabs[idx]
    if not tab or ActiveTab == tab then return end

    if ActiveTab then
        Tween(ActiveTab.BgPill, { BackgroundTransparency = 1 }, 0.22)
        Tween(ActiveTab.Label, { TextColor3 = Theme.TextDim }, 0.22)
        Tween(ActiveTab.IconLabel, { TextColor3 = Theme.TextMuted }, 0.22)
        Tween(ActiveTab.AccentBar, { BackgroundTransparency = 1 }, 0.22)
        ActiveTab.Page.Visible = false
    end

    tab.Page.Visible = true
    Tween(tab.BgPill, { BackgroundTransparency = 0.15 }, 0.28)
    Tween(tab.Label, { TextColor3 = Theme.Text }, 0.22)
    Tween(tab.IconLabel, { TextColor3 = Theme.Accent }, 0.22)
    Tween(tab.AccentBar, { BackgroundTransparency = 0 }, 0.22)

    ActiveTab = tab
    task.delay(0.05, UpdateContentScroll)
    task.delay(0.35, UpdateContentScroll)
    if tab.Name == "Moves" and RefreshRecorderList then
        task.delay(0.1, function() RecorderState.Saved = RecLoadAll(); RefreshRecorderList() end)
    end
end

local function CreateTab(label, name, icon)
    local idx = #Tabs + 1

    local btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.SidebarBg,
        BackgroundTransparency = 1,
        BorderSizePixel = 0, Text = "",
        AutoButtonColor = false,
        LayoutOrder = idx,
        Parent = UI.TabContainer,
        ZIndex = 2,
    })
    Corner(btn, 10)

    local bgPill = MakeFrame(btn, {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.CardBg,
        BackgroundTransparency = 1,
        ZIndex = 1,
    })
    Corner(bgPill, 10)
    Gradient(bgPill, { Theme.SurfaceHi, Theme.SidebarHi }, 45)

    local accentBar = MakeFrame(btn, {
        Size = UDim2.new(0, 3, 0, 24),
        Position = UDim2.new(0, 0, 0.5, -12),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        ZIndex = 5,
    })
    Corner(accentBar, 2)
    Gradient(accentBar, { Theme.AccentSoft, Theme.AccentDark }, 90)

    local iconBox = MakeFrame(btn, {
        Size = UDim2.new(0, 26, 0, 26),
        Position = UDim2.new(0, 12, 0.5, -13),
        BackgroundColor3 = Theme.SidebarHi,
        BackgroundTransparency = 0.3,
        ZIndex = 3,
    })
    Corner(iconBox, 8)
    local iconLabel = MakeLabel(iconBox, {
        Text = icon,
        TextColor3 = Theme.TextMuted,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 3,
    })

    local lbl = MakeLabel(btn, {
        Size = UDim2.new(1, -46, 1, 0),
        Position = UDim2.new(0, 46, 0, 0),
        Text = string.upper(label),
        TextColor3 = Theme.TextDim,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        ZIndex = 3,
    })

    local page = MakeFrame(UI.Content, {
        Name = name .. "Page",
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1, Visible = false,
    })
    page.AutomaticSize = Enum.AutomaticSize.Y
    New("UIListLayout", {
        Padding = UDim.new(0, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })
    Pad(page, 0, 12, 12, 6)

    local tabData = {
        Button = btn, Page = page,
        Label = lbl, IconLabel = iconLabel,
        BgPill = bgPill, AccentBar = accentBar,
        Name = name, Index = idx,
    }
    table.insert(Tabs, tabData)

    btn.MouseButton1Click:Connect(function() SwitchTab(idx) end)
    btn.MouseEnter:Connect(function()
        if ActiveTab ~= tabData then
            Tween(bgPill, { BackgroundTransparency = 0.82 }, 0.15)
            Tween(lbl, { TextColor3 = Theme.Text }, 0.15)
            Tween(iconLabel, { TextColor3 = Theme.Text }, 0.15)
        end
    end)
    btn.MouseLeave:Connect(function()
        if ActiveTab ~= tabData then
            Tween(bgPill, { BackgroundTransparency = 1 }, 0.15)
            Tween(lbl, { TextColor3 = Theme.TextDim }, 0.15)
            Tween(iconLabel, { TextColor3 = Theme.TextMuted }, 0.15)
        end
    end)

    return page
end

local PlayPage    = CreateTab("Play",    "Play",    "🏃")
local TunePage    = CreateTab("Tune",    "Tune",    "⚙️")
local VisPage     = CreateTab("Visual",  "Vis",     "✨")
local HotkeysPage = CreateTab("Keys",    "Keys",    "⌨️")
local RecPage     = CreateTab("REC",     "Moves",   "🎬")

if Tabs[1] then
    Tabs[1].Page.Visible = true
    Tabs[1].Label.TextColor3 = Theme.Text
    Tabs[1].IconLabel.TextColor3 = Theme.Accent
    Tabs[1].BgPill.BackgroundTransparency = 0.15
    Tabs[1].AccentBar.BackgroundTransparency = 0
    ActiveTab = Tabs[1]
end

-- === Play Page ===
CreateSection(PlayPage, "Movement")
CreateToggleCard(PlayPage, "Auto BunnyHop", "Автоматический прыжок при удержании Space", State.BhopEnabled, "🐇", function(v) State.BhopEnabled = v; if not v then ResetBhopState() end end)
CreateToggleCard(PlayPage, "Jump Acceleration", "Увеличивает скорость при каждом прыжке", State.JumpAccelEnabled, "⚡", function(v) State.JumpAccelEnabled = v end)

CreateSection(PlayPage, "Boosts")
CreateToggleCard(PlayPage, "Slope Boost", "Ускорение при столкновении со склоном (30-70°)", State.SlopeBoostEnabled, "⛷️", function(v) State.SlopeBoostEnabled = v end)
CreateToggleCard(PlayPage, "Landing Boost", "Добавляет скорость при мягком приземлении", State.LandingBoostEnabled, "🪂", function(v) State.LandingBoostEnabled = v end)

CreateSection(PlayPage, "Utility")
CreateButtonCard(PlayPage, "INSTANT REVIVE", "Мгновенное восстановление персонажа", TriggerSelfRevive)

-- === Tune Page ===
CreateSection(TunePage, "Speed")
CreateSliderCard(TunePage, "Gain Percent", "Процент прибавки за прыжок", 1, 20, CFG.GainPercent, "⚡", function(v) CFG.GainPercent = v end)
CreateSliderCard(TunePage, "Max Speed", "Максимальная скорость скриптового буста", 50, 250, CFG.MaxSpeed, "🚀", function(v) CFG.MaxSpeed = v end)
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
    if not v then PredState.FadeState = "hidden"; PredState.FadeProgress = 0; PredState.IdleTime = 0; DestroyPred() end
end)

CreateSection(VisPage, "Lighting")
CreateToggleCard(VisPage, "Lighting Boost", "Улучшает освещение в игре", State.LightingBoostEnabled, "💡", function(v) State.LightingBoostEnabled = v; if v then ApplyLighting() else RestoreLighting() end end)
CreateSliderCard(VisPage, "Brightness", "Яркость", 1, 8, CFG.LightBrightness, "☀️", function(v) CFG.LightBrightness = v; if State.LightingBoostEnabled then pcall(function() Lighting.Brightness = v end) end end, 1)
CreateSliderCard(VisPage, "Ambient", "Фоновое освещение", 0, 255, CFG.LightAmbientVal, "🌤️", function(v) CFG.LightAmbientVal = v; if State.LightingBoostEnabled then local c = Color3.fromRGB(v, v, v); pcall(function() Lighting.Ambient = c; Lighting.OutdoorAmbient = c end) end end)
CreateSliderCard(VisPage, "Exposure", "Экспозиция камеры", -1, 2, CFG.LightExposure, "👁️", function(v) CFG.LightExposure = v; if State.LightingBoostEnabled then pcall(function() Lighting.ExposureCompensation = v end) end end, 2)

CreateSection(VisPage, "Interface")
CreateToggleCard(VisPage, "Status Window", "Монитор скорости, FPS и пинга", State.WatermarkEnabled, "📊", function(v) State.WatermarkEnabled = v; UI.WatermarkFrame.Visible = v end)
CreateToggleCard(VisPage, "Recorder Status", "Movement recorder monitor window", State.RecorderStatusEnabled, "🎬", function(v) State.RecorderStatusEnabled = v; UI.RecorderStatusFrame.Visible = v end)

-- === Hotkeys Page ===
CreateSection(HotkeysPage, "Keybinds")
MakeLabel(HotkeysPage, { Size = UDim2.new(1, 0, 0, 22), Text = "ЛКМ — назначить клавишу, ПКМ — сбросить", TextColor3 = Theme.TextDim, TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true })
for _, item in ipairs(HotkeysList) do CreateHotkeyCard(HotkeysPage, item.title, item.id, Hotkeys[item.id]) end

-- === Recorder Page ===
CreateSection(RecPage, "Info")
UI.RecHelpLabel = MakeLabel(RecPage, { Size = UDim2.new(1, 0, 0, 34), Text = string.format("%s: record · %s: play nearby", (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—", (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—"), TextColor3 = Theme.TextDim, TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true })

CreateSection(RecPage, "Display")
CreateToggleCard(RecPage, "Show Markers", "Displays saved paths in world", State.MarkersEnabled, "📍", function(v) SetMarkersVisible(v) end)
CreateSliderCard(RecPage, "Marker Range", "Max distance to show markers", 20, 500, CFG.MarkerMaxDist, "📏", function(v) CFG.MarkerMaxDist = v end)

CreateSection(RecPage, "Status")
local statusCard = CreateCardShell(RecPage, { height = 58, padding = {14, 16, 14, 18} })
UI.RecStatusLabel = MakeLabel(statusCard, { Size = UDim2.new(1, 0, 0, 16), Text = "Idle", TextColor3 = Theme.TextMuted, TextSize = 12, Font = Enum.Font.GothamBold })
MakeLabel(statusCard, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 20), Text = "Captures pos & vel at 30 Hz", TextColor3 = Theme.TextMuted, TextSize = 9, Font = Enum.Font.Gotham })

CreateSection(RecPage, "Save")
UI.RecNameBox = New("TextBox", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.BgDeep, BackgroundTransparency = 0.65,
    BorderSizePixel = 0, Text = "", PlaceholderText = "Recording name...",
    PlaceholderColor3 = Theme.TextMuted, TextColor3 = Theme.TextMuted,
    TextSize = 13, Font = Enum.Font.Gotham, TextEditable = false,
    ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = RecPage
})
Corner(UI.RecNameBox, 12); Stroke(UI.RecNameBox, Theme.Border, 1, 0.6); Pad(UI.RecNameBox, 0, 14, 0, 14)

local btnRow = MakeFrame(RecPage, { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 })
New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = btnRow })

UI.RecSaveBtn = New("TextButton", { Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.75, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = 1, Parent = btnRow })
Corner(UI.RecSaveBtn, 12); Gradient(UI.RecSaveBtn, { Theme.Accent, Theme.AccentDark }, 45); Stroke(UI.RecSaveBtn, Theme.AccentSoft, 1, 0.35)
UI.RecSaveLbl = MakeLabel(UI.RecSaveBtn, { Text = "SAVE", TextColor3 = Theme.TextMuted, TextSize = 12, Font = Enum.Font.GothamBold, TextTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Center })

UI.RecCancelBtn = New("TextButton", { Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.75, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = 2, Parent = btnRow })
Corner(UI.RecCancelBtn, 12); Stroke(UI.RecCancelBtn, Theme.Border, 1, 0.7)
UI.RecCancelLbl = MakeLabel(UI.RecCancelBtn, { Text = "CANCEL", TextColor3 = Theme.TextMuted, TextSize = 12, Font = Enum.Font.GothamBold, TextTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Center })

local saveBtnStroke = UI.RecSaveBtn:FindFirstChildOfClass("UIStroke")
ApplyHover(UI.RecSaveBtn, { scale = 1.02, stroke = saveBtnStroke, hoverStrokeColor = Theme.AccentSoft, hoverStrokeTransp = 0.1 })
ApplyPress(UI.RecSaveBtn, { pressScale = 0.97, hoverScale = 1.02 })
local cancelBtnStroke = UI.RecCancelBtn:FindFirstChildOfClass("UIStroke")
ApplyHover(UI.RecCancelBtn, { scale = 1.02, stroke = cancelBtnStroke, hoverStrokeColor = Theme.Accent, hoverStrokeTransp = 0.4 })
ApplyPress(UI.RecCancelBtn, { pressScale = 0.97, hoverScale = 1.02 })

UI.RecSaveBtn.MouseButton1Click:Connect(function()
    if not RecorderState.InputEnabled or not RecorderState.Cache then return end
    local name = (UI.RecNameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[^%w_%-%(%) ]", "")
    if name == "" then UI.RecNameBox.PlaceholderText = "Enter a valid name"; return end
    for _, rec in ipairs(RecorderState.Saved) do
        if rec.name == name then UI.RecNameBox.PlaceholderText = "Name already in use"; return end
    end
    if RecSaveToFile(name, RecorderState.Cache.frames, RecorderState.Cache.duration) then
        RecorderState.Cache = nil
        DestroyUnsavedMarker()
        UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
        RecSetInputEnabled(false)
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Saved: " .. name; UI.RecStatusLabel.TextColor3 = Theme.Success end
        task.spawn(function() task.wait(0.05); RecorderState.Saved = RecLoadAll(); RefreshRecorderList() end)
    else
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Save failed"; UI.RecStatusLabel.TextColor3 = Theme.Danger end
    end
end)

UI.RecCancelBtn.MouseButton1Click:Connect(function()
    if not RecorderState.InputEnabled then return end
    RecorderState.Cache = nil
    DestroyUnsavedMarker()
    UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
    RecSetInputEnabled(false)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted end
end)

CreateSection(RecPage, "Recordings")
UI.RecListContainer = MakeFrame(RecPage, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 })
UI.RecListContainer.AutomaticSize = Enum.AutomaticSize.Y
New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = UI.RecListContainer })

RecSetInputEnabled(false)

local function CreateRecordingCard(parent, rec)
    local card = MakeFrame(parent, { Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 0.05, Active = true })
    local stroke = StyleCard(card, { radius = 12 })
    Pad(card, 12, 16, 12, 16)

    local iconBox = MakeFrame(card, { Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(0, 0, 0.5, -19), BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.15 })
    Corner(iconBox, 10); Stroke(iconBox, Theme.Border, 1, 0.55)
    Gradient(iconBox, { Theme.SurfaceHi, Theme.Surface }, 45)
    MakeLabel(iconBox, { Text = "🎬", TextColor3 = Theme.TextDim, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })

    MakeLabel(card, { Size = UDim2.new(1, -145, 0, 16), Position = UDim2.new(0, 48, 0, 9), Text = rec.name, TextSize = 13, Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd })
    MakeLabel(card, { Size = UDim2.new(1, -145, 0, 12), Position = UDim2.new(0, 48, 0, 27), Text = string.format("%.1fs · %d frames", rec.duration, rec.frameCount), TextColor3 = Theme.TextDim, TextSize = 10, Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd })
    MakeLabel(card, { Size = UDim2.new(1, -145, 0, 10), Position = UDim2.new(0, 48, 0, 42), Text = "Click to play", TextColor3 = Theme.TextFaint, TextSize = 9, Font = Enum.Font.Gotham })

    local playBtn = New("TextButton", { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(1, -80, 0.5, -17), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.35, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card })
    Corner(playBtn, 9)
    local playStroke = Stroke(playBtn, Theme.Accent, 1, 0.35)
    MakeLabel(playBtn, { Text = "▶", TextColor3 = Theme.BgDeep, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })
    ApplyHover(playBtn, { scale = 1.1, stroke = playStroke, hoverStrokeColor = Theme.AccentSoft, hoverStrokeTransp = 0.1 })
    ApplyPress(playBtn, { pressScale = 0.92, hoverScale = 1.1 })
    playBtn.MouseButton1Click:Connect(function()
        local _, decoded = RecReadFirstFrame(rec.path)
        if decoded then StartPlayback(rec.name, decoded.frames, decoded.duration) end
    end)

    local delBtn = New("TextButton", { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(1, -36, 0.5, -17), BackgroundColor3 = Theme.Surface, BackgroundTransparency = 0.15, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = card })
    Corner(delBtn, 9); local delStroke = Stroke(delBtn, Theme.Border, 1, 0.55)
    MakeLabel(delBtn, { Text = "🗑", TextColor3 = Theme.TextDim, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })
    ApplyHover(delBtn, { scale = 1.1, stroke = delStroke, hoverStrokeColor = Theme.Danger, hoverStrokeTransp = 0.3 })
    ApplyPress(delBtn, { pressScale = 0.92, hoverScale = 1.1 })
    delBtn.MouseButton1Click:Connect(function()
        RecDeleteFile(rec.path); DestroyMarker(rec.name)
        task.spawn(function() task.wait(0.05); RecorderState.Saved = RecLoadAll(); RefreshRecorderList() end)
    end)
end

RefreshRecorderList = function()
    if not UI.RecListContainer then return end
    for _, child in ipairs(UI.RecListContainer:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    if #RecorderState.Saved == 0 then
        local emptyCard = MakeFrame(UI.RecListContainer, { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 0.4 })
        Corner(emptyCard, 12); Stroke(emptyCard, Theme.Border, 1, 0.8)
        MakeLabel(emptyCard, { Text = "No recordings yet", TextColor3 = Theme.TextMuted, TextSize = 11, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Center })
    else
        for _, rec in ipairs(RecorderState.Saved) do CreateRecordingCard(UI.RecListContainer, rec) end
    end
    if State.MarkersEnabled then RefreshMarkers() end
    task.delay(0.05, UpdateContentScroll)
end

task.spawn(function() task.wait(); RecorderState.Saved = RecLoadAll(); if RefreshRecorderList then RefreshRecorderList() end end)

MakeDraggable(UI.MainFrame, UI.Header, function(input)
    local relX = input.Position.X - UI.Header.AbsolutePosition.X
    return not (relX >= UI.Header.AbsoluteSize.X - 70)
end, function() if SaveConfig then SaveConfig() end end)

-- ================= SAVE / LOAD =================
local ToggleMap = {
    BhopEnabled = "Auto BunnyHop", JumpAccelEnabled = "Jump Acceleration",
    SlopeBoostEnabled = "Slope Boost", LandingBoostEnabled = "Landing Boost",
    LandPredEnabled = "Landing Prediction", LightingBoostEnabled = "Lighting Boost",
    WatermarkEnabled = "Status Window", MarkersEnabled = "Show Markers",
    RecorderStatusEnabled = "Recorder Status",
}
local SliderMap = {
    GainPercent = "Gain Percent", MaxSpeed = "Max Speed", VertCap = "Vertical Cap",
    MaxTurnAngle = "Max Turn Angle", BrakeRate = "Brake Rate", MinSpeed = "Min Speed",
    FastFallForce = "Fast Fall Force", LandingBoostPercent = "Land Boost %",
    LandingSoftVY = "Land Soft VY", LightBrightness = "Brightness",
    LightAmbientVal = "Ambient", LightExposure = "Exposure",
    MarkerMaxDist = "Marker Range",
}

local function UDim2ToTable(u) return { XScale = u.X.Scale, XOffset = u.X.Offset, YScale = u.Y.Scale, YOffset = u.Y.Offset } end
local function TableToUDim2(t)
    if type(t) ~= "table" then return nil end
    return UDim2.new(tonumber(t.XScale) or 0, tonumber(t.XOffset) or 0, tonumber(t.YScale) or 0, tonumber(t.YOffset) or 0)
end

local function Log(msg) pcall(function() warn("[Noclipov] " .. tostring(msg)) end) end

local writeInFlight = false
local writeQueued = false

local function BuildSaveData()
    local data = {
        IsVisible = IsVisible,
        MainFramePos = UDim2ToTable(UI.MainFrame.Position),
        LauncherPos = UDim2ToTable(UI.LauncherIcon.Position),
        WatermarkPos = UDim2ToTable(UI.WatermarkFrame.Position),
        RecorderStatusPos = UDim2ToTable(UI.RecorderStatusFrame.Position),
        Hotkeys = {}, Toggles = {}, Sliders = {}
    }
    for _, item in ipairs(HotkeysList) do
        data.Hotkeys[item.id] = Hotkeys[item.id] and Hotkeys[item.id].Name or "None"
    end
    for k, v in pairs(State) do if type(v) == "boolean" then data.Toggles[k] = v end end
    for k, v in pairs(CFG) do if type(v) == "number" then data.Sliders[k] = v end end
    return data
end

local function DoSaveConfigNow()
    EnsureBaseFolders()
    local data = BuildSaveData()
    local encOk, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not encOk or type(encoded) ~= "string" then Log("SAVE FAIL: JSONEncode: " .. tostring(encoded)); return false end
    local writeOk, writeErr = pcall(writefile, CONFIG_PATH, encoded)
    if not writeOk then Log("SAVE FAIL: writefile: " .. tostring(writeErr) .. " | path=" .. CONFIG_PATH); return false end
    return true
end

SaveConfig = function()
    writeQueued = true
    if writeInFlight then return end
    writeInFlight = true
    task.spawn(function()
        while writeQueued do
            writeQueued = false
            pcall(DoSaveConfigNow)
        end
        writeInFlight = false
    end)
end

LoadConfig = function()
    EnsureBaseFolders()
    local content = nil
    local source = "none"
    pcall(function()
        if isfile and isfile(CONFIG_PATH) then
            content = readfile(CONFIG_PATH); source = "isfile+readfile"
        end
    end)
    if not content or #tostring(content) == 0 then
        pcall(function() content = readfile(CONFIG_PATH); source = "direct readfile" end)
    end
    if not content or #tostring(content) == 0 then Log("LOAD: no content (" .. source .. ")"); return end
    local jsonOk, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not jsonOk or type(data) ~= "table" then Log("LOAD FAIL: invalid JSON (len=" .. #content .. ")"); return end
    if data.IsVisible ~= nil then IsVisible = data.IsVisible == true end
    local p = TableToUDim2(data.MainFramePos); if p then UI.MainFrame.Position = p end
    p = TableToUDim2(data.LauncherPos); if p then UI.LauncherIcon.Position = p end
    p = TableToUDim2(data.WatermarkPos); if p then UI.WatermarkFrame.Position = p end
    p = TableToUDim2(data.RecorderStatusPos); if p then UI.RecorderStatusFrame.Position = p end
    if type(data.Hotkeys) == "table" then
        for id, keyName in pairs(data.Hotkeys) do
            if keyName == "None" then
                Hotkeys[id] = nil
                if HotkeyButtons[id] then HotkeyButtons[id].Text = "None"; HotkeyButtons[id].TextColor3 = Theme.TextMuted end
            elseif type(keyName) == "string" and Enum.KeyCode[keyName] then
                Hotkeys[id] = Enum.KeyCode[keyName]
                if HotkeyButtons[id] then HotkeyButtons[id].Text = keyName; HotkeyButtons[id].TextColor3 = Theme.Text end
            end
        end
    end
    if type(data.Toggles) == "table" then
        for stateKey, uiName in pairs(ToggleMap) do
            local v = data.Toggles[stateKey]
            if v ~= nil and ToggleRefs[uiName] then ToggleRefs[uiName](v == true) end
        end
    end
    if type(data.Sliders) == "table" then
        for cfgKey, uiName in pairs(SliderMap) do
            local v = data.Sliders[cfgKey]
            if v ~= nil and type(v) == "number" then
                CFG[cfgKey] = v
                if SliderRefs[uiName] then SliderRefs[uiName](v) end
            end
        end
    end
    Log("LOAD OK from " .. source .. " (len=" .. #content .. ")")
end

-- ================= WINDOW CONTROLS =================
local function showWindow()
    IsVisible = true; UI.MainFrame.Visible = true
    local targetPos = UI.MainFrame.Position
    UI.MainFrame.Size = UDim2.new(0, WIN_W * 0.95, 0, WIN_H * 0.95)
    UI.MainFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + 24)
    Tween(UI.MainFrame, { Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = targetPos }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    task.delay(0.4, UpdateContentScroll)
    if SaveConfig then SaveConfig() end
end

local function hideWindow()
    IsVisible = false; UI.MainFrame.Visible = false; if SaveConfig then SaveConfig() end
end

CreateTrafficLight(Theme.MacYellow, "—", function() hideWindow() end)
CreateTrafficLight(Theme.MacRed, "×", function() Cleanup() end)
UI.LauncherIcon.MouseButton1Click:Connect(function()
    if os.clock() - launcherDragEndTime < 0.15 then return end
    if IsVisible then hideWindow() else showWindow() end
end)

local function ResetCharacterState()
    DestroyPred(); PredState.FadeState = "hidden"; PredState.FadeProgress = 0; PredState.IdleTime = 0; PredState.LastSuccess = 0
    StopPlayback()
end

Connections.CharRemoving = LocalPlayer.CharacterRemoving:Connect(function()
    ResetCharacterState()
    if RecorderState.IsRecording then
        RecorderState.IsRecording = false; RecorderState.Frames = {}; RecorderState.FrameAccum = 0; RecorderState.Cache = nil
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Interrupted"; UI.RecStatusLabel.TextColor3 = Theme.Warning end
        RecSetInputEnabled(false)
    end
end)
Connections.CharAdded = LocalPlayer.CharacterAdded:Connect(function()
    ResetCharacterState()
    task.delay(1, function() RecorderState.Saved = RecLoadAll(); if RefreshRecorderList then RefreshRecorderList() end end)
end)

-- ================= INPUT =================
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
        local bindMap = { Bhop="Auto BunnyHop", Accel="Jump Acceleration", Slope="Slope Boost", Land="Landing Boost", Pred="Landing Prediction", Light="Lighting Boost" }
        for bindId, uiName in pairs(bindMap) do
            if Hotkeys[bindId] and k == Hotkeys[bindId] and ToggleRefs[uiName] then
                local stateKey = nil
                for sk, un in pairs(ToggleMap) do if un == uiName then stateKey = sk; break end end
                if stateKey then ToggleRefs[uiName](not State[stateKey]) end
                return
            end
        end
        if Hotkeys["Record"] and k == Hotkeys["Record"] then if RecorderState.IsRecording then RecStop(true) else RecStart() end; return end
        if Hotkeys["Playback"] and k == Hotkeys["Playback"] then TryStartNearbyPlayback(); return end
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
    if PlaybackState.Active then return end
    if State.BhopEnabled then TryBhop(dt) end
    if State.SlopeBoostEnabled then TrySlopeBoost() end
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then ClampVelocity(hrp) end
    end
end)

Connections.RecorderLoop = RunService.Heartbeat:Connect(function(dt)
    if not RecorderState.IsRecording then return end
    RecorderState.FrameAccum = RecorderState.FrameAccum + dt
    if RecorderState.FrameAccum < RECORD_HZ then return end
    RecorderState.FrameAccum = RecorderState.FrameAccum - RECORD_HZ
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local t = os.clock() - RecorderState.StartTime
    local cf = hrp.CFrame; local v = hrp.AssemblyLinearVelocity
    table.insert(RecorderState.Frames, {
        t = t, px = cf.X, py = cf.Y, pz = cf.Z,
        vx = v.X, vy = v.Y, vz = v.Z,
        lx = cf.LookVector.X, ly = cf.LookVector.Y, lz = cf.LookVector.Z,
    })
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = string.format("● REC  %.1fs · %d", t, #RecorderState.Frames) end
end)

Connections.PlaybackLoop = RunService.Heartbeat:Connect(function() UpdatePlayback() end)

local lastRecHelpUpdate = 0
local lastRecStatusUpdate = 0
Connections.RecStatusLoop = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastRecStatusUpdate > 0.05 then
        lastRecStatusUpdate = now; UpdateRecorderStatus()
    end
    if now - lastRecHelpUpdate > 0.5 then
        lastRecHelpUpdate = now
        if UI.RecHelpLabel then
            local newText = string.format("%s: record · %s: play nearby", (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—", (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—")
            if UI.RecHelpLabel.Text ~= newText then UI.RecHelpLabel.Text = newText end
        end
    end
end)

Connections.MarkerLoop = RunService.Heartbeat:Connect(function()
    if not State.MarkersEnabled and not UnsavedMarker and not PlaybackState.StartMarker then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hrpPos = hrp.Position; local now = os.clock()
    local maxDist = CFG.MarkerMaxDist or 150

    for _, m in pairs(MarkerParts) do
        local dist = (hrpPos - m.startPos).Magnitude
        local far = dist > maxDist
        if far ~= m.isFar then
            m.isFar = far
            if m.base then m.base.Transparency = far and 1 or 0.55 end
            if m.pulse then m.pulse.Transparency = far and 1 or 0.4 end
            if m.crystal then m.crystal.Transparency = far and 1 or 0.1 end
            if m.glow then m.glow.Transparency = far and 1 or 0.88 end
            if m.beam then m.beam.Transparency = far and 1 or 0.7 end
            if m.light then m.light.Enabled = not far end
            if m.billboard then m.billboard.Enabled = not far end
        end
        if not far and m.pulse and m.crystal then
            local pulseT = ((now + (m.pulsePhase or 0)) % 2) / 2
            local size = (m.pulseBaseSize or 3.0) * (1 + pulseT * 2)
            m.pulse.Size = Vector3.new(0.06, size, size)
            m.pulse.Transparency = 0.2 + pulseT * 0.7
            local pulse2 = 0.5 + 0.5 * math.sin(now * math.pi * 3 + (m.pulsePhase or 0))
            m.crystal.Transparency = 0.05 + pulse2 * 0.15
            if m.light then m.light.Brightness = 1.2 + pulse2 * 0.6 end
        end
    end

    if UnsavedMarker then
        local dist = (hrpPos - UnsavedMarker.startPos).Magnitude
        local far = dist > maxDist
        if far ~= UnsavedMarker.isFar then
            UnsavedMarker.isFar = far
            if UnsavedMarker.base then UnsavedMarker.base.Transparency = far and 1 or 0.55 end
            if UnsavedMarker.pulse then UnsavedMarker.pulse.Transparency = far and 1 or 0.4 end
            if UnsavedMarker.crystal then UnsavedMarker.crystal.Transparency = far and 1 or 0.1 end
            if UnsavedMarker.glow then UnsavedMarker.glow.Transparency = far and 1 or 0.88 end
            if UnsavedMarker.beam then UnsavedMarker.beam.Transparency = far and 1 or 0.7 end
            if UnsavedMarker.light then UnsavedMarker.light.Enabled = not far end
            if UnsavedMarker.billboard then UnsavedMarker.billboard.Enabled = not far end
        end
    end
end)

Connections.PulseLoop = RunService.Heartbeat:Connect(function()
    if UI.WatermarkFrame.Visible and UI.WmLivePill and UI.WmLivePill.Parent then
        local isActive = (BhopState.CurrentStatus == "GAIN" or BhopState.CurrentStatus == "BRAKE" or BhopState.CurrentStatus == "AIR")
        if isActive then
            UI.WmLivePill.BackgroundTransparency = 0.2 + math.sin(os.clock() * math.pi * 2.5) * 0.12
        else
            UI.WmLivePill.BackgroundTransparency = 0.3
        end
    end
    if logoGlow and logoGlow.Parent then
        logoGlow.BackgroundTransparency = 0.75 + (0.5 + 0.5 * math.sin(os.clock() * math.pi * 1.4)) * 0.15
    end
end)

local lastUIUpdate = 0
local lastTelemetryUpdate = 0
local fpsFrames, fpsAccum = 0, 0

Connections.StatusLoop = RunService.Heartbeat:Connect(function(dt)
    if UI.WatermarkFrame.Visible then
        fpsFrames = fpsFrames + 1
        fpsAccum = fpsAccum + dt
        local nowT = os.clock()
        if nowT - lastTelemetryUpdate > 0.5 then
            lastTelemetryUpdate = nowT
            if fpsAccum > 0 then UI.WmFpsVal.Text = tostring(math.floor(fpsFrames / fpsAccum + 0.5)) end
            fpsFrames, fpsAccum = 0, 0
            pcall(function()
                local ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                UI.WmPingVal.Text = tostring(ping)
                UI.WmPingVal.TextColor3 = ping < 80 and Theme.Success or ping < 150 and Theme.Warning or Theme.Danger
            end)
        end
    end
    local now = os.clock()
    if now - lastOrphanSweep > 1.0 then lastOrphanSweep = now; SweepOrphanPredParts() end
    if now - lastUIUpdate < 0.05 then return end
    lastUIUpdate = now
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and UI.WatermarkFrame.Visible then
        local spd = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
        if spd > SessionStats.MaxSpeed then SessionStats.MaxSpeed = spd end
        displaySpeed = displaySpeed + (spd - displaySpeed) * math.min(1, dt * 15)
        UI.WmSpeedVal.Text = string.format("%.1f", displaySpeed)
        UI.WmMaxVal.Text = string.format("%.0f", CFG.MaxSpeed)
        UI.WmTimeVal.Text = FormatTime(now - SessionStats.StartTime)

        local pct = math.clamp(displaySpeed / math.max(1, CFG.MaxSpeed), 0, 1)
        UI.WmSpeedBarFill.Size = UDim2.new(pct, 0, 1, 0)
        UI.WmSpeedBarFill.BackgroundColor3 = pct >= 0.9 and Theme.Success or Theme.Accent

        local st = BhopState.CurrentStatus
        local sText, sColor
        if st == "GAIN" then sText, sColor = "GAIN", Theme.Success
        elseif st == "BRAKE" then sText, sColor = "BRAKE", Theme.Danger
        elseif st == "AIR" then sText, sColor = "AIR", Theme.Accent
        elseif st == "NO CHAR" then sText, sColor = "N/A", Theme.Warning
        elseif st == "DISABLED" then sText, sColor = "OFF", Theme.TextMuted
        elseif st == "IDLE" then sText, sColor = "IDLE", Theme.TextMuted
        else sText, sColor = st or "—", Theme.TextMuted end
        UI.WmLiveLabel.Text = sText
        UI.WmLiveLabel.TextColor3 = sColor
        UI.WmLiveDot.BackgroundColor3 = sColor
    elseif not hrp and UI.WatermarkFrame.Visible then
        UI.WmSpeedVal.Text = "-"
        UI.WmLiveLabel.Text = "—"
        UI.WmLiveLabel.TextColor3 = Theme.TextMuted
        UI.WmLiveDot.BackgroundColor3 = Theme.TextMuted
        UI.WmSpeedBarFill.Size = UDim2.new(0, 0, 1, 0)
    end
    UpdatePrediction(dt)
end)

-- ================= MAP CHANGE DETECTION =================
local MapWatch = { LastMapName = GetMapName(), AttrConn = nil, ReloadDebounce = nil }

local function HandleMapChange()
    if MapWatch.ReloadDebounce then return end
    MapWatch.ReloadDebounce = true
    task.delay(0.2, function()
        MapWatch.ReloadDebounce = nil
        MapWatch.LastMapName = GetMapName()

        if RecorderState.IsRecording then
            RecorderState.IsRecording = false
            RecorderState.Frames = {}; RecorderState.FrameAccum = 0; RecorderState.Cache = nil
            RecSetInputEnabled(false); DestroyUnsavedMarker()
            if UI.RecStatusLabel then
                UI.RecStatusLabel.Text = "Interrupted (map changed)"
                UI.RecStatusLabel.TextColor3 = Theme.Warning
            end
        end
        if PlaybackState.Active then StopPlayback() end

        RecorderState.Saved = RecLoadAll()
        if RefreshRecorderList then RefreshRecorderList() end
        if State.MarkersEnabled then RefreshMarkers() end

        pcall(function() print("[Noclipov] Map changed → " .. GetMapName() .. " (" .. #RecorderState.Saved .. " recordings)") end)
    end)
end

local function BindMapAttribute(map)
    if MapWatch.AttrConn then
        pcall(function() MapWatch.AttrConn:Disconnect() end); MapWatch.AttrConn = nil
    end
    if not map then return end
    MapWatch.AttrConn = map:GetAttributeChangedSignal("MapName"):Connect(function()
        local newName = GetMapName()
        if newName ~= MapWatch.LastMapName then
            MapWatch.LastMapName = newName; HandleMapChange()
        end
    end)
end

local function TryBindMapFromWorkspace()
    local map = workspace:FindFirstChild("Map")
    if map then BindMapAttribute(map) end
end

Connections.MapChildAdded = workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then BindMapAttribute(child); HandleMapChange() end
end)

Connections.MapChildRemoved = workspace.ChildRemoved:Connect(function(child)
    if child.Name == "Map" then MapWatch.LastMapName = "Unknown"; HandleMapChange() end
end)

TryBindMapFromWorkspace()

Connections.MapWatchSafety = task.spawn(function()
    local lastSafety = GetMapName()
    while UI.ScreenGui and UI.ScreenGui.Parent do
        task.wait(5)
        local now = GetMapName()
        if now ~= lastSafety then
            lastSafety = now
            if now ~= MapWatch.LastMapName then MapWatch.LastMapName = now; HandleMapChange() end
        end
        local map = workspace:FindFirstChild("Map")
        if map and not MapWatch.AttrConn then BindMapAttribute(map) end
    end
end)

task.spawn(function()
    while UI.ScreenGui.Parent do
        task.wait(0.3)
        if IsVisible and ActiveTab then UpdateContentScroll() end
    end
end)

-- ================= INIT =================
SweepOrphanPredParts(true)
UI.MainFrame.Visible = false
LoadConfig()
if SaveConfig then SaveConfig() end
if IsVisible then showWindow() else UI.MainFrame.Visible = false end

Cleanup = function()
    pcall(function() DoSaveConfigNow() end)
    for k in pairs(State) do if type(State[k]) == "boolean" then State[k] = false end end
    for _, conn in pairs(Connections) do if typeof(conn) == "RBXScriptConnection" and conn.Connected then pcall(function() conn:Disconnect() end) end end
    table.clear(Connections)
    if MapWatch and MapWatch.AttrConn then pcall(function() MapWatch.AttrConn:Disconnect() end) end
    ResetBhopState(); BhopState.WasAirborne = false; BhopState.TrackedHrp = nil; BhopState.TrackedLV = nil; DestroyPred(); RestoreLighting()
    StopPlayback(true); ClearPlaybackPath(); DestroyPlaybackStartMarker(); DestroyUnsavedMarker()
    for name in pairs(MarkerParts) do DestroyMarker(name) end
    if UI.ScreenGui then pcall(function() UI.ScreenGui:Destroy() end) end
    if ENV.__ZettaCleanup == Cleanup then ENV.__ZettaCleanup = nil end
end
ENV.__ZettaCleanup = Cleanup