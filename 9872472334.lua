repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334]=true, [10662098230]=true, [10808838353]=true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return
end

local SCRIPT_VERSION  = "9.2"
local UI_NAME         = "NoclipovUI"
local ENV_CLEANUP_KEY = "__NoclipovCleanup"
local ENV_VERSION_KEY = "__NoclipovVersion"
local BASE_FOLDER     = "Noclipov/evade"
local CONFIG_PATH     = BASE_FOLDER .. "/Config.json"
local MOVEMENT_BASE   = BASE_FOLDER .. "/movement"

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
local VirtualUser       = game:GetService("VirtualUser")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

-- ================= VERSION GUARD =================
do
    local oldCleanup = ENV[ENV_CLEANUP_KEY] or ENV.__ZettaCleanup
    if type(oldCleanup) == "function" then pcall(oldCleanup); task.wait() end
    ENV[ENV_CLEANUP_KEY] = nil; ENV.__ZettaCleanup = nil
    ENV[ENV_VERSION_KEY] = SCRIPT_VERSION
end

-- ================= DISPOSER =================
local Disposer = { items = {}, disposed = false, cleaning = false }
function Disposer:track(kind, obj)
    if not obj then return obj end
    if self.disposed then
        pcall(function()
            if kind == "connection" then if obj.Connected then obj:Disconnect() end
            elseif kind == "instance" then if obj.Parent then obj:Destroy() end end
        end)
        return obj
    end
    table.insert(self.items, { kind = kind, obj = obj }); return obj
end
function Disposer:connect(signal, cb) return self:track("connection", signal:Connect(cb)) end
function Disposer:dispose()
    if self.disposed or self.cleaning then return end
    self.cleaning = true; self.disposed = true
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        pcall(function()
            if item.kind == "connection" then
                if item.obj.Connected then item.obj:Disconnect() end
            elseif item.kind == "instance" then
                if item.obj.Parent then item.obj:Destroy() end
            end
        end)
        self.items[i] = nil
    end
    table.clear(self.items); self.cleaning = false
end
local function TrackConnection(conn) return Disposer:track("connection", conn) end

local IsVisible = true
local Cleanup   = function() end

-- ================= CONFIG =================
local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, LandingBoostPercent=5, LandingSoftVY=30, AbsCap=200, MaxTurnAngle=45,
    AdaptiveGainEnabled=false, AdaptiveGainMin=0.4, AdaptiveGainMax=1.6,
    PredMinVisibleDist=15, PredFadeInSpeed=10, PredFadeOutSpeed=14,
    PredToleranceTime=0.4, PredTerminalVel=200, PredMaxSteps=120, PredNormalMin=0.3,
    LightBrightness=3.0, LightAmbientVal=140, LightExposure=0.4,
    MarkerMaxDist=150, PlaybackSpeed=1.0,
    TrimStartOnStop=true, TrimEndOnStop=true, TrimThreshold=1.0,
    CompactMode=false, AntiAfkEnabled=false,
    -- Shaders
    BloomEnabled=false, BloomIntensity=0.5, BloomSize=24, BloomThreshold=0.9,
    ColorCorrectionEnabled=false, CC_Brightness=0, CC_Contrast=0, CC_Saturation=0,
    FogEnabled=false, FogStart=100, FogEnd=500,
    AtmosphereEnabled=false, AtmosDensity=0.3, AtmosHaze=0,
    SunRaysEnabled=false, DOFEnabled=false,
    WeatherSnow=false, WeatherRain=false, WeatherSakura=false, WeatherIntensity=1.0,
}

-- ================= EXTERNAL SHADERS =================
local Shaders = nil
do
    local ok, addOrErr = pcall(function()
        local f = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/refs/heads/main/Libs/additional.lua"))
        return f and f()
    end)
    if ok and type(addOrErr) == "table" and type(addOrErr.load_module) == "function" then
        local ok2, mod = pcall(function() return addOrErr.load_module("shaders.lua", true) end)
        if ok2 and type(mod) == "table" then
            Shaders = mod
        end
    end
    if not Shaders then
        -- Fallback stub — не ломает UI при недоступности модуля
        Shaders = {
            PostEffects = {}, FogSaved = nil, WeatherPart = nil,
            WeatherEmitter = nil, SuppressWeatherToggle = false,
            Init = function() end,
            ApplyBloom = function() end, ApplyColorCorrection = function() end,
            ApplyFog = function() end, ApplyAtmosphere = function() end,
            ApplySunRays = function() end, ApplyDepthOfField = function() end,
            SetWeather = function() end, GetActiveWeather = function() return "none" end,
            UpdateWeatherRate = function() end, UpdatePosition = function() end,
            ApplyAll = function() end, Cleanup = function() end,
        }
        warn("[Noclipov] Shaders module unavailable — using stub")
    end
    if type(Shaders.Init) == "function" then
        pcall(Shaders.Init, CFG, Lighting)
    end
end

-- ================= THEME — CRIMSON =================
-- ================= THEME — SOFT CRIMSON =================
local Theme = {
    BgDarkest    = Color3.fromRGB(18, 16, 20),
    BgMain       = Color3.fromRGB(26, 22, 28),
    BgSidebar    = Color3.fromRGB(22, 18, 24),
    SurfaceBase  = Color3.fromRGB(36, 32, 40),
    SurfaceLight = Color3.fromRGB(46, 40, 50),
    SurfaceHover = Color3.fromRGB(56, 48, 60),
    Accent       = Color3.fromRGB(190, 70, 70),
    AccentHover  = Color3.fromRGB(215, 85, 85),
    AccentDark   = Color3.fromRGB(110, 35, 35),
    AccentSoft   = Color3.fromRGB(235, 130, 130),
    Success      = Color3.fromRGB(80, 200, 120),
    Danger       = Color3.fromRGB(255, 110, 110),
    Warning      = Color3.fromRGB(255, 190, 60),
    Text         = Color3.fromRGB(225, 220, 228),
    TextBright   = Color3.fromRGB(250, 250, 250),
    TextDim      = Color3.fromRGB(160, 155, 165),
    TextMuted    = Color3.fromRGB(120, 115, 125),
    Border       = Color3.fromRGB(55, 48, 58),
    BorderLight  = Color3.fromRGB(80, 70, 85),
}
local SEQ_SWITCH_OFF = ColorSequence.new(Theme.SurfaceBase, Theme.BgDarkest)
local SEQ_SWITCH_ON  = ColorSequence.new(Theme.AccentSoft, Theme.AccentDark)

-- ================= SLIDER SNAPS =================
local SLIDER_SNAPS = {
    ["Gain Percent"]   = {5, 8, 10, 12, 15},
    ["Max Speed"]      = {60, 80, 100, 120, 150, 200, 250},
    ["Min Speed"]      = {10, 15, 20, 25, 30},
    ["Vertical Cap"]   = {50, 55, 60, 80, 100},
    ["Max Turn Angle"] = {30, 45, 60, 90, 120, 180},
    ["Brake Rate"]     = {40, 60, 80, 100, 150},
    ["Fast Fall Force"]= {60, 90, 120, 150, 200},
    ["Land Boost %"]   = {0, 5, 10, 15, 20},
    ["Land Soft VY"]   = {20, 30, 40, 50, 60},
    ["Brightness"]     = {1, 2, 3, 5, 8},
    ["Ambient"]        = {0, 100, 140, 200, 255},
    ["Exposure"]       = {-0.5, 0, 0.4, 1, 2},
    ["Marker Range"]   = {50, 100, 150, 250, 500},
    ["Adaptive Min"]   = {0.3, 0.5, 0.7, 1.0},
    ["Adaptive Max"]   = {1.2, 1.5, 2.0, 2.5},
    ["Playback Speed"] = {0.5, 1.0, 1.5, 2.0, 2.5, 3.0},
    ["Trim Threshold"] = {0.5, 1.0, 2.0, 3.0, 5.0},
    ["Bloom Intensity"]   = {0.3, 0.5, 0.8, 1.0, 1.5},
    ["Bloom Size"]        = {12, 24, 36, 48},
    ["Bloom Threshold"]   = {0.8, 0.9, 1.0, 1.2},
    ["CC Brightness"]     = {-0.3, -0.1, 0, 0.1, 0.2},
    ["CC Contrast"]       = {-0.3, 0, 0.1, 0.2, 0.3},
    ["CC Saturation"]     = {-0.5, -0.2, 0, 0.3, 0.6, 1.0},
    ["Fog Start"]         = {20, 50, 100, 200, 500},
    ["Fog End"]           = {200, 500, 1000, 2000, 5000},
    ["Atmos Density"]     = {0.1, 0.3, 0.5, 0.8, 1.0},
    ["Atmos Haze"]        = {0, 1, 2, 3, 5},
    ["Weather Intensity"] = {0.3, 0.5, 1.0, 1.5, 2.0},
}

-- ================= STATE =================
local State = {
    BhopEnabled=false, JumpAccelEnabled=false, IsHoldingJump=false,
    SlopeBoostEnabled=false, LandPredEnabled=false, LandingBoostEnabled=false,
    LightingBoostEnabled=false, WatermarkEnabled=false, MarkersEnabled=false,
    RecorderStatusEnabled=false,
}
local UI = {}
local SessionStats = { StartTime = os.clock(), MaxSpeed = 0 }
local displaySpeed = 0
local SuppressWeatherToggle = false
local function FormatTime(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local BhopState = {
    TargetSpeed=0, WasAirborne=false, TrackedHrp=nil, TrackedLV=nil,
    LastGameDir=nil, LastLandingBoosted=false, LastSlopeBoost=0,
    CurrentStatus="IDLE", LightingSaved=nil,
}
local PredState = {
    Data=nil, SmoothCFrame=nil, FadeState="hidden", FadeProgress=0,
    LastSuccess=0, LastUpdate=0, ArcParts={}, IdleTime=0,
    CachedImpact=nil, CachedImpactTime=nil, CachedImpactVel=nil,
    CachedImpactAt=0, LastPath=nil, __errLogged=false,
}

local awaitingBind = nil
local ToggleRefs, SliderRefs, HotkeyButtons = {}, {}, {}
local RECORD_HZ = 1 / 30

local RecorderState = {
    IsRecording=false, StartTime=0, Frames={}, FrameAccum=0,
    Cache=nil, Saved={}, InputEnabled=false,
}
local PlaybackState = {
    Active=false, AlignPos=nil, AlignOri=nil, Attach0=nil,
    Frames=nil, Duration=0, StartTime=0, RecName=nil,
    WasBhopEnabled=false, WasPredEnabled=false, WasPredToggleState=false,
    StartMarker=nil, Speed=1.0,
    OriginalAutoRotate=nil, OriginalHrpCollide=nil,
}

local MarkerParts = {}
local UnsavedMarker = nil
local PLAY_RADIUS = 10
local PLAYBACK_ABORT_DIST = 30
local PlaybackPath = { parts={}, active=false }
local launcherDragEndTime = 0

local SaveConfig, LoadConfig, RefreshRecorderList, RefreshMarkers

local function AreMarkersBlocked()
    return RecorderState.IsRecording or RecorderState.Cache ~= nil
end

local HotkeysList = {
    { id="Bhop",     title="Toggle Bhop",          default=Enum.KeyCode.B },
    { id="Accel",    title="Toggle Jump Accel",    default=Enum.KeyCode.J },
    { id="Slope",    title="Toggle Slope Boost",   default=Enum.KeyCode.V },
    { id="Land",     title="Toggle Landing Boost", default=Enum.KeyCode.N },
    { id="Pred",     title="Toggle Prediction",    default=Enum.KeyCode.M },
    { id="Record",   title="Toggle Record",        default=Enum.KeyCode.F },
    { id="Playback", title="Play Nearby",          default=Enum.KeyCode.P },
    { id="Light",    title="Toggle Lighting",      default=Enum.KeyCode.L },
    { id="Brake",    title="Brake (Hold)",         default=Enum.KeyCode.LeftShift },
    { id="Fall",     title="Fast Fall (Hold)",     default=Enum.KeyCode.X },
    { id="UI",       title="Toggle UI",            default=Enum.KeyCode.RightShift },
}
local Hotkeys = {}
for _, item in ipairs(HotkeysList) do Hotkeys[item.id] = item.default end

-- ================= HELPERS =================
local function SafeParent()
    if gethui then local ok, hui = pcall(gethui); if ok and hui then return hui end end
    return CoreGui
end
local function CollectGuiParents()
    local parents = {}
    if gethui then local ok, hui = pcall(gethui); if ok and hui then table.insert(parents, hui) end end
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then table.insert(parents, pg) end
    end)
    pcall(function() table.insert(parents, CoreGui) end)
    return parents
end
local function SweepLegacyWorkspace()
    local function isNoclipovName(name)
        return name:match("^Noclipov") ~= nil or name:match("Marker_") ~= nil
            or name:match("LandPred") ~= nil or name:match("PlaybackPath") ~= nil
            or name:match("WeatherPart") ~= nil
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and isNoclipovName(obj.Name) then
            pcall(function() obj:Destroy() end)
        end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") or obj:IsA("Model") then
            if obj.Name:find("Noclipov") then pcall(function() obj:Destroy() end)
            else
                for _, child in ipairs(obj:GetChildren()) do
                    if (child:IsA("BasePart") or child:IsA("BillboardGui"))
                    and isNoclipovName(child.Name) then
                        pcall(function() child:Destroy() end)
                    end
                end
            end
        end
    end
end
local function DeepCleanupPrevious()
    local oldCleanup = ENV[ENV_CLEANUP_KEY] or ENV.__ZettaCleanup
    if type(oldCleanup) == "function" then pcall(oldCleanup); task.wait() end
    for _, parent in ipairs(CollectGuiParents()) do
        if parent then
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == UI_NAME or child.Name:match("^Noclipov") then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    SweepLegacyWorkspace()
    task.delay(0.5, SweepLegacyWorkspace)
    task.delay(1.5, SweepLegacyWorkspace)
end
local function New(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    return inst
end
local function Corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = p; return c
end
local function Gradient(p, colors, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(colors[1], colors[2])
    g.Rotation = rotation or 0; g.Parent = p; return g
end
local function Stroke(p, color, thick, transp)
    local s = Instance.new("UIStroke")
    s.Color = color; s.Thickness = thick or 1; s.Transparency = transp or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end
local function Pad(p, t, r, b, l)
    local x = Instance.new("UIPadding")
    x.PaddingTop = UDim.new(0, t or 0); x.PaddingBottom = UDim.new(0, b or 0)
    x.PaddingLeft = UDim.new(0, l or 0); x.PaddingRight = UDim.new(0, r or 0)
    x.Parent = p; return p
end
local function AddShadow(p, opts)
    opts = opts or {}
    local ok, shadow = pcall(function() return Instance.new("UIShadow") end)
    if not ok or not shadow then return nil end
    shadow.Color = opts.color or Color3.new(0,0,0)
    shadow.Transparency = opts.transparency or 0.6
    local blurVal = opts.blur or 24
    local spreadVal = opts.spread or 0
    if not pcall(function() shadow.BlurRadius = UDim.new(0, blurVal) end) then
        pcall(function() shadow.BlurRadius = blurVal end)
    end
    if not pcall(function() shadow.Spread = UDim.new(0, spreadVal) end) then
        pcall(function() shadow.Spread = spreadVal end)
    end
    pcall(function() shadow.Offset = opts.offset or Vector2.new(0, 6) end)
    shadow.Parent = p; return shadow
end
local function Tween(inst, props, t, style, dir)
    TweenService:Create(inst, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

-- ================= INTERACTION =================
local ActiveInteraction = nil
local function SetInteraction(handler) ActiveInteraction = handler end
local function EnsureUIScale(inst)
    local s = inst:FindFirstChildOfClass("UIScale")
    if not s then s = Instance.new("UIScale"); s.Scale = 1; s.Parent = inst end
    return s
end
local function ApplyScaleHover(inst, hoverScale, dur)
    local uiscale = EnsureUIScale(inst)
    inst.MouseEnter:Connect(function() Tween(uiscale, { Scale = hoverScale or 1.01 }, dur or 0.18) end)
    inst.MouseLeave:Connect(function() Tween(uiscale, { Scale = 1 }, dur or 0.18) end)
end
local function ApplyHover(inst, opts)
    opts = opts or {}
    local uiscale = EnsureUIScale(inst)
    local baseColor = opts.stroke and opts.stroke.Color
    local baseTransp = opts.stroke and opts.stroke.Transparency
    inst.MouseEnter:Connect(function()
        Tween(uiscale, { Scale = opts.scale or 1.015 }, opts.duration or 0.16)
        if opts.stroke then
            Tween(opts.stroke, { Color = opts.hoverStrokeColor or Theme.Accent, Transparency = opts.hoverStrokeTransp or 0.4 }, 0.16)
        end
    end)
    inst.MouseLeave:Connect(function()
        Tween(uiscale, { Scale = 1 }, opts.duration or 0.16)
        if opts.stroke then
            Tween(opts.stroke, { Color = baseColor, Transparency = baseTransp }, 0.16)
        end
    end)
end
local function ApplyPress(inst, opts)
    opts = opts or {}
    local uiscale = EnsureUIScale(inst)
    inst.MouseButton1Down:Connect(function() Tween(uiscale, { Scale = opts.pressScale or 0.97 }, 0.08) end)
    inst.MouseButton1Up:Connect(function() Tween(uiscale, { Scale = 1 }, 0.14) end)
end

-- ================= UI PRIMITIVES =================
local function MakeFrame(parent, props)
    local p = {
        Name="Frame", Size=UDim2.new(1,0,0,0), Position=UDim2.new(0,0,0,0),
        AnchorPoint=Vector2.zero, BackgroundColor3=Theme.SurfaceBase,
        BackgroundTransparency=0, BorderSizePixel=0, ZIndex=1, Parent=parent,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("Frame", p)
end
local function MakeLabel(parent, props)
    local p = {
        Name="Label", Size=UDim2.new(1,0,1,0), Position=UDim2.new(0,0,0,0),
        BackgroundTransparency=1, Text="", TextColor3=Theme.Text, TextSize=14,
        Font=Enum.Font.GothamMedium, TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center, Parent=parent,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("TextLabel", p)
end
local function MakeDraggable(frame, dragArea, isAllowedFunc, onEndFunc)
    dragArea.InputBegan:Connect(function(input)
        if isAllowedFunc and not isAllowedFunc(input) then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            local startPos = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y)
            local dragStart = Vector2.new(input.Position.X, input.Position.Y)
            local size = frame.AbsoluteSize; local moved = false
            SetInteraction({
                onMove = function(inp)
                    local delta = Vector2.new(inp.Position.X, inp.Position.Y) - dragStart
                    if math.abs(delta.X) < 4 and math.abs(delta.Y) < 4 then return end
                    moved = true
                    local ps = UI.ScreenGui.AbsoluteSize
                    frame.Position = UDim2.fromOffset(
                        math.clamp(startPos.X + delta.X, 0, ps.X - size.X),
                        math.clamp(startPos.Y + delta.Y, 0, ps.Y - size.Y)
                    )
                end,
                onEnd = function() if onEndFunc then onEndFunc(moved) end end,
            })
        end
    end)
end

-- ================= STYLE =================
local function StyleGlassPanel(panel, opts)
    opts = opts or {}
    Corner(panel, opts.radius or 14)
    Gradient(panel, { Theme.SurfaceBase, Theme.BgDarkest }, 135)
    local stroke = Stroke(panel, Theme.BorderLight, 1.2, opts.strokeTransp or 0.5)
    AddShadow(panel, { transparency = 0.4, blur = 40, offset = Vector2.new(0, 12) })
    return stroke
end
local function StyleCard(card, opts)
    opts = opts or {}
    Corner(card, opts.radius or 12)
    Gradient(card, { Theme.SurfaceLight, Theme.SurfaceBase }, 90)
    local stroke = Stroke(card, Theme.Border, 1, 0.8)
    ApplyScaleHover(card, 1.005, 0.2)
    card.MouseEnter:Connect(function()
        Tween(stroke, { Color = Theme.BorderLight, Transparency = 0.6 }, 0.2)
    end)
    card.MouseLeave:Connect(function()
        Tween(stroke, { Color = Theme.Border, Transparency = 0.8 }, 0.2)
    end)
    return stroke
end

-- ================= ANTI-AFK =================
local AntiAfk = { enabled=false, conn=nil }
local function SetAntiAfkEnabled(enabled)
    AntiAfk.enabled = enabled
    if enabled and not AntiAfk.conn then
        AntiAfk.conn = LocalPlayer.Idled:Connect(function()
            if not AntiAfk.enabled then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end

-- ================= MOVEMENT CORE =================
local CHAR_RAY = RaycastParams.new()
CHAR_RAY.FilterType = Enum.RaycastFilterType.Exclude
CHAR_RAY.IgnoreWater = true
pcall(function() CHAR_RAY.RespectCanCollide = true end)

local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping
    or st == Enum.HumanoidStateType.Freefall
    or st == Enum.HumanoidStateType.FallingDown then return true end
    if hum.FloorMaterial == Enum.Material.Air then
        CHAR_RAY.FilterDescendantsInstances = { LocalPlayer.Character }
        return Workspace:Raycast(hrp.Position, Vector3.new(0, -3, 0), CHAR_RAY) == nil
    end
    return false
end
local function TriggerSelfRevive()
    local events = ReplicatedStorage:FindFirstChild("Events"); if not events then return end
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
        if d:IsA("LinearVelocity") and d.Attachment0
        and d.RelativeTo == Enum.ActuatorRelativeTo.World then
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
    local horiz = Vector3.new(av.X, 0, av.Z)
    local y = av.Y; local clamped = false
    if horiz.Magnitude > CFG.AbsCap then horiz = horiz.Unit * CFG.AbsCap; clamped = true end
    if math.abs(y) > CFG.VertCap then y = (y > 0) and CFG.VertCap or -CFG.VertCap; clamped = true end
    local nv = Vector3.new(horiz.X, y, horiz.Z)
    if nv.Magnitude > CFG.AbsCap then nv = nv.Unit * CFG.AbsCap; clamped = true end
    if clamped then hrp.AssemblyLinearVelocity = nv end
end
local function ResetBhopState()
    BhopState.TargetSpeed = 0; BhopState.LastGameDir = nil
end

local function TryBhop(dt)
    local char = LocalPlayer.Character
    if not char then
        ResetBhopState(); BhopState.WasAirborne = false
        BhopState.TrackedHrp = nil; BhopState.TrackedLV = nil
        BhopState.CurrentStatus = "NO CHAR"; return
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then
        ResetBhopState(); BhopState.WasAirborne = false
        BhopState.CurrentStatus = "IDLE"; return
    end
    if BhopState.TrackedHrp ~= hrp then
        BhopState.TrackedHrp = hrp
        BhopState.TrackedLV = FindGameLV(char)
        ResetBhopState(); BhopState.WasAirborne = false
    elseif not BhopState.TrackedLV or BhopState.TrackedLV.Parent ~= hrp then
        BhopState.TrackedLV = FindGameLV(char)
    end
    if not State.BhopEnabled then
        ResetBhopState(); BhopState.WasAirborne = IsAirborne(hum, hrp)
        ClampVelocity(hrp); BhopState.CurrentStatus = "DISABLED"; return
    end
    local airborne = IsAirborne(hum, hrp)
    local humState = hum:GetState()
    local gameHoriz = ReadGameHoriz(BhopState.TrackedLV, hrp)
    local gameSpeed = gameHoriz.Magnitude
    local gameDir   = (gameSpeed > 0.5) and gameHoriz.Unit or nil
    if airborne and not BhopState.WasAirborne then
        if (humState == Enum.HumanoidStateType.Jumping) and State.IsHoldingJump then
            local base = math.max(BhopState.TargetSpeed, gameSpeed)
            if base > 3 then
                if State.JumpAccelEnabled then
                    local gainPct = CFG.GainPercent
                    if CFG.AdaptiveGainEnabled then
                        local norm = math.clamp(base / math.max(CFG.MaxSpeed, 1), 0, 1)
                        local factor = CFG.AdaptiveGainMax - norm * (CFG.AdaptiveGainMax - CFG.AdaptiveGainMin)
                        gainPct = gainPct * factor
                    end
                    local boost = base * (gainPct / 100)
                    BhopState.TargetSpeed = math.max(base, math.min(base + boost, CFG.MaxSpeed))
                else
                    BhopState.TargetSpeed = base
                end
                BhopState.LastGameDir = gameDir
            end
        end
    end
    if airborne and gameDir and BhopState.LastGameDir then
        local align = math.clamp(BhopState.LastGameDir:Dot(gameDir), -1, 1)
        if math.deg(math.acos(align)) > CFG.MaxTurnAngle then BhopState.TargetSpeed = 0 end
    end
    if airborne and gameDir then BhopState.LastGameDir = gameDir end
    local braking = airborne and BhopState.TargetSpeed > 0
        and Hotkeys["Brake"] and UserInputService:IsKeyDown(Hotkeys["Brake"])
    if braking then
        BhopState.TargetSpeed = math.max(CFG.MinSpeed, BhopState.TargetSpeed - CFG.BrakeRate * dt)
    end
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
    if not airborne and State.IsHoldingJump and hum.FloorMaterial ~= Enum.Material.Air
    and humState ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if airborne and Hotkeys["Fall"] and UserInputService:IsKeyDown(Hotkeys["Fall"]) then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    if not airborne and BhopState.WasAirborne and State.LandingBoostEnabled
    and BhopState.TargetSpeed > 0 and not BhopState.LastLandingBoosted then
        local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
        if vy <= CFG.LandingSoftVY then
            local headroom = math.max(0, CFG.MaxSpeed - BhopState.TargetSpeed)
            BhopState.TargetSpeed = BhopState.TargetSpeed + math.min(
                BhopState.TargetSpeed * (CFG.LandingBoostPercent / 100), headroom)
            BhopState.LastLandingBoosted = true
        end
    end
    if not airborne then
        BhopState.LastLandingBoosted = false; BhopState.LastGameDir = nil
    end
    if not airborne and not State.IsHoldingJump then ResetBhopState() end
    BhopState.CurrentStatus = braking and "BRAKE"
        or (airborne and BhopState.TargetSpeed > 0 and "GAIN"
        or (airborne and "AIR" or "IDLE"))
    BhopState.WasAirborne = airborne
    ClampVelocity(hrp)
end

-- ================= SLOPE =================
local SLOPE = {
    Cooldown=0.55, MinSpeed=25, Gain=1.15, GainPerSpeed=0.01, MaxGain=2.2,
    SpeedRef=40, UpComponent=1.0, MinRise=1.5,
    NormalMin=math.cos(math.rad(70)), NormalMax=math.cos(math.rad(30)),
    AirRay=20, GroundRay=12,
}
local DOWN_AIR, DOWN_GROUND = Vector3.new(0, -SLOPE.AirRay, 0), Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new()
SlopeRay.FilterType = Enum.RaycastFilterType.Exclude
SlopeRay.IgnoreWater = true

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock()
    if now - BhopState.LastSlopeBoost < SLOPE.Cooldown then return end
    local char = LocalPlayer.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    SlopeRay.FilterDescendantsInstances = { char }
    local vel = hrp.AssemblyLinearVelocity; if vel.Y < 2 then return end
    local flat = Vector3.new(vel.X, 0, vel.Z)
    local speed = flat.Magnitude; if speed < 0.1 then return end
    local fw = flat.Unit; local base = hrp.Position
    local hB  = Workspace:Raycast(base - fw * 2.0, DOWN_AIR, SlopeRay)
    local hA1 = Workspace:Raycast(base + fw * 1.0, DOWN_AIR, SlopeRay)
    local hA2 = Workspace:Raycast(base + fw * 2.5, DOWN_AIR, SlopeRay)
    if not (hB and hA1 and hA2) then
        hB  = Workspace:Raycast(base - fw * 2.0, DOWN_GROUND, SlopeRay)
        hA1 = Workspace:Raycast(base + fw * 1.0, DOWN_GROUND, SlopeRay)
        hA2 = Workspace:Raycast(base + fw * 2.5, DOWN_GROUND, SlopeRay)
    end
    if not (hB and hA1 and hA2) then return end
    local r1 = hA1.Position.Y - hB.Position.Y
    local r2 = hA2.Position.Y - hB.Position.Y
    if r1 <= 0 or r2 <= 0 or r1 < SLOPE.MinRise or r2 < SLOPE.MinRise * 0.7 or r1 > r2 * 2.0 then return end
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
        hrp.AssemblyLinearVelocity = (fw + Vector3.new(0, SLOPE.UpComponent, 0)).Unit
            * math.max(sp, SLOPE.MinSpeed) * g
    end)
end

-- ================= LIGHTING (legacy basic) =================
local function SaveLighting()
    if not BhopState.LightingSaved then
        BhopState.LightingSaved = {
            Brightness=Lighting.Brightness, Ambient=Lighting.Ambient,
            OutdoorAmbient=Lighting.OutdoorAmbient,
            ExposureCompensation=Lighting.ExposureCompensation,
            ClockTime=Lighting.ClockTime,
        }
    end
end
local function ApplyLighting()
    if not State.LightingBoostEnabled then return end
    SaveLighting()
    pcall(function()
        Lighting.Brightness = CFG.LightBrightness
        local c = Color3.fromRGB(CFG.LightAmbientVal, CFG.LightAmbientVal, CFG.LightAmbientVal)
        Lighting.Ambient = c; Lighting.OutdoorAmbient = c
        Lighting.ExposureCompensation = CFG.LightExposure
    end)
end
local function RestoreLighting()
    if not BhopState.LightingSaved then return end
    pcall(function()
        Lighting.Brightness = BhopState.LightingSaved.Brightness
        Lighting.Ambient = BhopState.LightingSaved.Ambient
        Lighting.OutdoorAmbient = BhopState.LightingSaved.OutdoorAmbient
        Lighting.ExposureCompensation = BhopState.LightingSaved.ExposureCompensation
        Lighting.ClockTime = BhopState.LightingSaved.ClockTime
    end)
    BhopState.LightingSaved = nil
end

-- ================= PREDICTION =================
local PRED_RAY = RaycastParams.new()
PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude
PRED_RAY.IgnoreWater = true
pcall(function() PRED_RAY.RespectCanCollide = true end)

local function getImpactColor(time)
    if not time then return Theme.TextMuted end
    if time < 0.35 then return Theme.Accent
    elseif time < 0.8 then return Theme.Warning
    elseif time < 1.6 then return Color3.fromRGB(255, 235, 80)
    else return Theme.Success end
end
local function PredictLanding(hrp, hum, maxTime)
    local hipHeight = math.max(hum.HipHeight or 0, hrp.Size.Y * 0.5 + 1)
    local pos = hrp.Position - Vector3.new(0, hipHeight, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity
    local terminal = CFG.PredTerminalVel or 200
    local dt = 0.025
    local maxSteps = math.min(math.floor(maxTime / dt), CFG.PredMaxSteps or 120)
    local normalMin = CFG.PredNormalMin or 0.3
    PRED_RAY.FilterDescendantsInstances = { LocalPlayer.Character }
    local path = { pos }
    if vel.Y >= -5 then
        local groundRay = Workspace:Raycast(pos, Vector3.new(0, -hipHeight - 1, 0), PRED_RAY)
        if groundRay and groundRay.Normal.Y > normalMin then
            return groundRay.Position, path, 0.01, vel
        end
    end
    for i = 1, maxSteps do
        local vY = math.max(vel.Y - g * dt, -terminal)
        local nextVel = Vector3.new(vel.X, vY, vel.Z)
        local nextPos = Vector3.new(pos.X + vel.X * dt, pos.Y + vel.Y * dt - 0.5 * g * dt * dt, pos.Z + vel.Z * dt)
        local rayDir = nextPos - pos
        local dist = rayDir.Magnitude
        table.insert(path, nextPos)
        if dist > 0.05 then
            local hit = Workspace:Raycast(pos, rayDir, PRED_RAY)
            if hit then
                if hit.Normal.Y > normalMin then
                    local hitDist = (hit.Position - pos).Magnitude
                    local alpha = math.clamp(hitDist / math.max(dist, 0.01), 0, 1)
                    local hitTime = (i - 1 + alpha) * dt
                    return hit.Position, path, math.max(hitTime, 0.01), nextVel
                elseif hit.Normal.Y <= 0.2 and nextVel.Y <= 0 then
                    return nil, nil
                end
            end
        end
        pos = nextPos; vel = nextVel
    end
    return nil, nil
end
local function DestroyPred()
    if PredState.Data then
        for _, key in ipairs({"root", "ring", "innerRing", "dot", "beam", "billboard", "ringLight"}) do
            local p = PredState.Data[key]
            if p then pcall(function() p:Destroy() end) end
        end
        PredState.Data = nil
    end
    for _, p in ipairs(PredState.ArcParts) do pcall(function() p:Destroy() end) end
    table.clear(PredState.ArcParts)
    PredState.SmoothCFrame = nil; PredState.CachedImpact = nil
    PredState.CachedImpactTime = nil; PredState.CachedImpactVel = nil
    PredState.LastPath = nil
end
local function SweepOrphanPredParts(force)
    if not force then
        if State.LandPredEnabled or PredState.FadeState ~= "hidden"
        or PredState.Data or #PredState.ArcParts > 0 then return end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and (obj.Name:match("^Noclipov_Pred_")
        or obj.Name:match("^Noclipov_LandPred_")) then
            pcall(function() obj:Destroy() end)
        end
    end
end
local function EnsurePred()
    if PredState.Data and PredState.Data.root and PredState.Data.root.Parent then
        return PredState.Data
    end
    DestroyPred()

    local root = Instance.new("Part")
    root.Name = "Noclipov_LandPred_Root"
    root.Size = Vector3.new(0.1, 0.1, 0.1)
    root.Transparency = 1; root.Anchored = true
    root.CanCollide = false; root.CanQuery = false; root.CanTouch = false
    root.Parent = Workspace

    local ring = Instance.new("Part")
    ring.Name = "Noclipov_LandPred_Ring"
    ring.Shape = Enum.PartType.Cylinder; ring.Size = Vector3.new(0.06, 4.5, 4.5)
    ring.Anchored = true; ring.CanCollide = false
    ring.CanQuery = false; ring.CanTouch = false
    ring.Material = Enum.Material.SmoothPlastic
    ring.Color = Theme.Accent; ring.Transparency = 0.15
    ring.Parent = Workspace
    local ringLight = Instance.new("PointLight")
    ringLight.Color = Theme.Accent; ringLight.Range = 3
    ringLight.Brightness = 0.12; ringLight.Shadows = false
    ringLight.Parent = ring

    local innerRing = Instance.new("Part")
    innerRing.Name = "Noclipov_LandPred_InnerRing"
    innerRing.Shape = Enum.PartType.Cylinder; innerRing.Size = Vector3.new(0.04, 3.2, 3.2)
    innerRing.Anchored = true; innerRing.CanCollide = false
    innerRing.CanQuery = false; innerRing.CanTouch = false
    innerRing.Material = Enum.Material.SmoothPlastic
    innerRing.Color = Theme.TextBright; innerRing.Transparency = 0.1
    innerRing.Parent = Workspace

    local dot = Instance.new("Part")
    dot.Name = "Noclipov_LandPred_Dot"
    dot.Shape = Enum.PartType.Ball; dot.Size = Vector3.new(0.55, 0.55, 0.55)
    dot.Anchored = true; dot.CanCollide = false
    dot.CanQuery = false; dot.CanTouch = false
    dot.Material = Enum.Material.SmoothPlastic
    dot.Color = Theme.TextBright; dot.Transparency = 0.05
    dot.Parent = Workspace

    local att0 = Instance.new("Attachment"); att0.Position = Vector3.new(0, 0, 0);  att0.Parent = root
    local att1 = Instance.new("Attachment"); att1.Position = Vector3.new(0, 15, 0); att1.Parent = root
    local beam = Instance.new("Beam")
    beam.Attachment0 = att0; beam.Attachment1 = att1
    beam.Width0 = 0.22; beam.Width1 = 0.05
    beam.Color = ColorSequence.new(Theme.Accent)
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.75),
        NumberSequenceKeypoint.new(0.5, 0.85),
        NumberSequenceKeypoint.new(1, 0.95),
    })
    beam.FaceCamera = true; beam.LightEmission = 0.1; beam.LightInfluence = 0
    beam.Parent = root

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Noclipov_LandPred_Label"
    billboard.Size = UDim2.new(0, 140, 0, 62)
    billboard.StudsOffset = Vector3.new(0, 2.0, 0)
    billboard.AlwaysOnTop = true; billboard.LightInfluence = 0
    billboard.Parent = dot

    local bBg = Instance.new("Frame")
    bBg.Size = UDim2.new(1, 0, 1, 0)
    bBg.BackgroundColor3 = Theme.BgDarkest; bBg.BackgroundTransparency = 0.1
    bBg.BorderSizePixel = 0; bBg.Parent = billboard
    Corner(bBg, 8); local bStroke = Stroke(bBg, Theme.Accent, 1.5, 0.35)

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0.5, 0, 0, 2)
    accentLine.Position = UDim2.new(0.25, 0, 0, 4)
    accentLine.BackgroundColor3 = Theme.Accent; accentLine.BorderSizePixel = 0
    accentLine.BackgroundTransparency = 0.2; accentLine.Parent = bBg
    Corner(accentLine, 1)

    local labelTitle = Instance.new("TextLabel")
    labelTitle.Size = UDim2.new(1, 0, 0, 10); labelTitle.Position = UDim2.new(0, 0, 0, 10)
    labelTitle.BackgroundTransparency = 1
    labelTitle.Text = "T-MINUS"; labelTitle.TextColor3 = Theme.TextMuted
    labelTitle.TextSize = 8; labelTitle.Font = Enum.Font.GothamBold
    labelTitle.TextTransparency = 1; labelTitle.Parent = bBg

    local labelTime = Instance.new("TextLabel")
    labelTime.Size = UDim2.new(1, 0, 0, 22); labelTime.Position = UDim2.new(0, 0, 0, 20)
    labelTime.BackgroundTransparency = 1
    labelTime.Text = "0.0s"; labelTime.TextColor3 = Theme.Text
    labelTime.TextSize = 17; labelTime.Font = Enum.Font.GothamBold
    labelTime.TextTransparency = 1; labelTime.Parent = bBg

    local labelSpeed = Instance.new("TextLabel")
    labelSpeed.Size = UDim2.new(1, 0, 0, 11); labelSpeed.Position = UDim2.new(0, 0, 0, 42)
    labelSpeed.BackgroundTransparency = 1
    labelSpeed.Text = "0 u/s · 0 studs"; labelSpeed.TextColor3 = Theme.TextDim
    labelSpeed.TextSize = 9; labelSpeed.Font = Enum.Font.Code
    labelSpeed.TextTransparency = 1; labelSpeed.Parent = bBg

    for _ = 1, 24 do
        local p = Instance.new("Part")
        p.Name = "Noclipov_LandPred_Arc"
        p.Shape = Enum.PartType.Block; p.Size = Vector3.new(0.06, 0.06, 1)
        p.Anchored = true; p.CanCollide = false
        p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.SmoothPlastic
        p.Color = Theme.Accent; p.Transparency = 1
        p.Parent = Workspace
        table.insert(PredState.ArcParts, p)
    end

    PredState.Data = {
        root=root, ring=ring, ringLight=ringLight, innerRing=innerRing, dot=dot,
        beam=beam, billboard=billboard,
        labelTitle=labelTitle, labelTime=labelTime, labelSpeed=labelSpeed,
        labelBg=bBg, labelStroke=bStroke, accentLine=accentLine,
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
    local frameDt = now - PredState.LastUpdate
    PredState.LastUpdate = now

    local predPos, path, predTime, impactVel
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")

    if State.LandPredEnabled and hrp and hum and IsAirborne(hum, hrp) then
        local ok, c, p, t, v = pcall(PredictLanding, hrp, hum, 3.0)
        if ok and c and p and t then
            local dist = (hrp.Position - c).Magnitude
            if dist >= (CFG.PredMinVisibleDist or 15) then
                predPos = c; path = p; predTime = t; impactVel = v
                PredState.CachedImpact = c; PredState.CachedImpactTime = t
                PredState.CachedImpactVel = v; PredState.CachedImpactAt = now
                PredState.LastPath = p
            end
        end
    end
    if predPos then
        PredState.LastSuccess = now; PredState.IdleTime = 0
        if PredState.FadeState == "hidden" then
            PredState.FadeState = "showing"; PredState.FadeProgress = 0
        elseif PredState.FadeState == "hiding" then
            PredState.FadeState = "showing"
        end
    else
        if State.LandPredEnabled and PredState.CachedImpact
        and (now - (PredState.CachedImpactAt or 0) < 0.25) then
            local cacheDist = (hrp.Position - PredState.CachedImpact).Magnitude
            if cacheDist >= (CFG.PredMinVisibleDist or 15) then
                predPos = PredState.CachedImpact
                predTime = PredState.CachedImpactTime
                impactVel = PredState.CachedImpactVel
                path = PredState.LastPath
                PredState.LastSuccess = now
            else
                if PredState.FadeState ~= "hidden" then PredState.FadeState = "hiding" end
            end
        else
            if (PredState.FadeState == "showing" or PredState.FadeState == "visible")
            and (now - PredState.LastSuccess > (CFG.PredToleranceTime or 0.4)) then
                PredState.FadeState = "hiding"
            end
        end
    end
    if PredState.FadeState == "showing" then
        PredState.FadeProgress = math.min(1, PredState.FadeProgress + frameDt * CFG.PredFadeInSpeed)
        if PredState.FadeProgress >= 1 then PredState.FadeState = "visible" end
    elseif PredState.FadeState == "hiding" then
        PredState.FadeProgress = math.max(0, PredState.FadeProgress - frameDt * CFG.PredFadeOutSpeed)
        if PredState.FadeProgress <= 0 then
            PredState.FadeState = "hidden"; DestroyPred(); return
        end
    end
    if PredState.FadeState == "hidden" then
        PredState.IdleTime = PredState.IdleTime + frameDt
        if PredState.IdleTime > 2 and PredState.Data then DestroyPred() end
        return
    end
    if not hrp then return end

    local data = EnsurePred()
    if predPos then
        local targetCF = CFrame.new(predPos + Vector3.new(0, 0.05, 0))
        if not PredState.SmoothCFrame then PredState.SmoothCFrame = targetCF end
        PredState.SmoothCFrame = PredState.SmoothCFrame:Lerp(targetCF, math.clamp(frameDt * 15, 0, 1))

        local dist  = (hrp.Position - PredState.SmoothCFrame.Position).Magnitude
        local urgency = math.clamp(1 - (predTime or 2) / 2.0, 0, 1)
        local pulseSpeed = 2.0 + urgency * 3.5
        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * pulseSpeed)
        local spinSpeed = 1.2 + urgency * 2.0
        local spin  = now * spinSpeed

        data.root.Position = PredState.SmoothCFrame.Position
        local timeColor = getImpactColor(predTime)

        local ringScale = 4.5 + pulse * (0.15 + urgency * 0.5)
        data.ring.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90))
        data.ring.Transparency = fadeAlpha(0.15 + pulse * 0.08 + urgency * 0.08)
        data.ring.Size = Vector3.new(0.06, ringScale, ringScale)
        data.ring.Color = timeColor

        local innerSize = 3.2 - urgency * 0.8
        data.innerRing.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, -spin * 1.5, math.rad(90))
        data.innerRing.Transparency = fadeAlpha(0.1 + pulse * 0.15 + urgency * 0.05)
        data.innerRing.Size = Vector3.new(0.04, innerSize, innerSize)

        local dotSize = 0.55 + urgency * 0.35
        data.dot.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.3, 0))
        data.dot.Size = Vector3.new(dotSize, dotSize, dotSize)
        data.dot.Transparency = fadeAlpha(0.05 + urgency * 0.05)
        data.dot.Color = timeColor

        if data.beam then data.beam.Color = ColorSequence.new(timeColor) end
        if data.ringLight then
            data.ringLight.Color = timeColor
            data.ringLight.Brightness = 0.08 + pulse * 0.05
        end

        local billboardVisible = dist > 15
        if data.billboard then data.billboard.Enabled = billboardVisible end
        if billboardVisible then
            local bbAlpha = fadeAlpha(0)
            local impactSpeed = impactVel and impactVel.Magnitude or 0
            if data.labelTime then
                data.labelTime.Text = string.format("%.2fs", predTime or 0)
                data.labelTime.TextTransparency = bbAlpha
                data.labelTime.TextColor3 = timeColor
            end
            if data.labelSpeed then
                data.labelSpeed.Text = string.format("%.0f u/s · %.0f studs", impactSpeed, dist)
                data.labelSpeed.TextTransparency = bbAlpha
                data.labelSpeed.TextColor3 = impactSpeed > 100 and Theme.Danger
                    or impactSpeed > 60 and Theme.Warning or Theme.Text
            end
            if data.labelTitle then data.labelTitle.TextTransparency = bbAlpha end
            if data.accentLine then
                data.accentLine.BackgroundTransparency = bbAlpha + 0.2
                data.accentLine.BackgroundColor3 = timeColor
            end
            if data.labelBg then data.labelBg.BackgroundTransparency = fadeAlpha(0.1) end
            if data.labelStroke then
                data.labelStroke.Transparency = fadeAlpha(0.35)
                data.labelStroke.Color = timeColor
            end
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
                    local thick = 0.03 + midT * (0.08 + urgency * 0.05)
                    seg.Size = Vector3.new(thick, thick, len)
                    seg.CFrame = CFrame.new((A + B) / 2, B)
                    seg.Color = timeColor:Lerp(Theme.Accent, t * 0.5)
                    local fadeBase = (0.55 - t * 0.25) - urgency * 0.1
                    seg.Transparency = fadeAlpha(math.max(0.05, fadeBase))
                else
                    seg.Transparency = 1
                end
            end
        else
            for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
        end
    else
        for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
        data.ring.Transparency = 1
        data.innerRing.Transparency = 1
        data.dot.Transparency = 1
        if data.ringLight then data.ringLight.Enabled = false end
        if data.billboard then data.billboard.Enabled = false end
    end
end

-- ================= FILE HELPERS =================
local function GetMapName()
    local ok, name = pcall(function()
        local map = workspace:FindFirstChild("Map")
        if not map then return nil end
        return map:GetAttribute("MapName")
    end)
    if ok and type(name) == "string" and name ~= "" then
        return (name:gsub("[^%w_%-]", "_"))
    end
    return "Unknown"
end
local BASE_FOLDERS_READY = false
local function EnsureBaseFolders()
    if BASE_FOLDERS_READY then return end
    BASE_FOLDERS_READY = true
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
    local data = {
        version=1, name=name, mapName=GetMapName(),
        createdAt=os.time(), duration=duration, frameCount=#frames, frames=frames,
    }
    local encoded
    if not pcall(function() encoded = HttpService:JSONEncode(data) end) then return false end
    if not encoded then return false end
    return pcall(writefile, MOVEMENT_BASE .. "/" .. GetMapName() .. "/" .. name .. ".json", encoded)
end
local function RecListFiles()
    local folder = MOVEMENT_BASE .. "/" .. GetMapName()
    RecEnsureFolder()
    local files = {}
    pcall(function()
        if listfiles and isfolder and isfolder(folder) then files = listfiles(folder) end
    end)
    return files
end
local function RecLoadAll()
    local list = {}
    for _, path in ipairs(RecListFiles()) do
        if type(path) == "string" and path:match("%.json$") then
            local content; pcall(function() content = readfile(path) end)
            if content then
                local decoded; pcall(function() decoded = HttpService:JSONDecode(content) end)
                if decoded then
                    local fname = path:match("([^/\\]+)%.json$") or "unknown"
                    table.insert(list, {
                        name=fname, path=path,
                        duration=decoded.duration or 0,
                        frameCount=decoded.frameCount or #(decoded.frames or {}),
                        mapName=decoded.mapName or "", createdAt=decoded.createdAt,
                    })
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return list
end
local function RecDeleteFile(path) pcall(delfile, path) end
local function RecReadFirstFrame(path)
    local content; pcall(function() content = readfile(path) end)
    if not content then return nil end
    local decoded; pcall(function() decoded = HttpService:JSONDecode(content) end)
    if not decoded or not decoded.frames or not decoded.frames[1] then return nil end
    local f = decoded.frames[1]
    if not f.px or not f.py or not f.pz then return nil end
    return Vector3.new(f.px, f.py, f.pz), decoded
end
local function RecSetInputEnabled(enabled)
    RecorderState.InputEnabled = enabled
    if not UI.RecNameBox then return end
    UI.RecNameBox.TextEditable = enabled
    UI.RecNameBox.TextColor3 = enabled and Theme.Text or Theme.TextMuted
    UI.RecNameBox.BackgroundTransparency = enabled and 0.3 or 0.7
    if UI.RecSaveLbl then
        UI.RecSaveLbl.TextColor3 = enabled and Theme.BgDarkest or Theme.TextMuted
        UI.RecSaveLbl.TextTransparency = enabled and 0 or 0.4
    end
    if UI.RecSaveBtn then UI.RecSaveBtn.BackgroundTransparency = enabled and 0.05 or 0.75 end
    if UI.RecCancelLbl then
        UI.RecCancelLbl.TextColor3 = enabled and Theme.Text or Theme.TextMuted
        UI.RecCancelLbl.TextTransparency = enabled and 0 or 0.4
    end
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
    local trimmed = {}; local offsetT = frames[lastStaticIdx].t
    for i = lastStaticIdx, #frames do
        local f = frames[i]
        table.insert(trimmed, {
            t=f.t - offsetT, px=f.px, py=f.py, pz=f.pz,
            vx=f.vx, vy=f.vy, vz=f.vz, lx=f.lx, ly=f.ly, lz=f.lz,
        })
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
    local char = LocalPlayer.Character; if not char then return false, "No character" end
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
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = reason
            UI.RecStatusLabel.TextColor3 = Theme.Warning
        end
        return
    end
    RecorderState.IsRecording = true
    RecorderState.StartTime = os.clock()
    RecorderState.Frames = {}
    RecorderState.FrameAccum = 0
    RecorderState.Cache = nil
    RecSetInputEnabled(false)
    if UI.RecStatusLabel then
        UI.RecStatusLabel.Text = "● REC"
        UI.RecStatusLabel.TextColor3 = Theme.Danger
    end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
end
local function RecStop(cache)
    if not RecorderState.IsRecording then return end
    RecorderState.IsRecording = false
    local frames = RecorderState.Frames
    RecorderState.Frames = {}
    RecorderState.FrameAccum = 0
    if cache and #frames >= 2 then
        local trimmed = frames
        if CFG.TrimStartOnStop then trimmed = TrimLeadingStatic(trimmed, CFG.TrimThreshold or 1.0) end
        if #trimmed > 0 and CFG.TrimEndOnStop then trimmed = TrimTrailingStatic(trimmed, CFG.TrimThreshold or 1.0) end
        if #trimmed < 2 then
            RecorderState.Cache = nil
            if UI.RecStatusLabel then
                UI.RecStatusLabel.Text = "Too short"
                UI.RecStatusLabel.TextColor3 = Theme.Warning
            end
            RecSetInputEnabled(false)
            if RefreshMarkers then RefreshMarkers() end
            if RefreshRecorderList then task.defer(RefreshRecorderList) end
            return
        end
        local newDuration = trimmed[#trimmed].t
        RecorderState.Cache = { frames=trimmed, duration=newDuration, frameCount=#trimmed }
        local trimmedCount = #frames - #trimmed
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = trimmedCount > 0
                and string.format("Ready: %.1fs · %d (trimmed %d)", newDuration, #trimmed, trimmedCount)
                or  string.format("Ready: %.1fs · %d frames", newDuration, #trimmed)
            UI.RecStatusLabel.TextColor3 = Theme.Success
        end
        RecSetInputEnabled(true); CreateUnsavedMarker(trimmed)
    else
        RecorderState.Cache = nil
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = "Idle"
            UI.RecStatusLabel.TextColor3 = Theme.TextMuted
        end
        RecSetInputEnabled(false)
    end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
end

-- ================= MARKERS =================
local function CreateMarkerVisual(pos, color, isUnsaved)
    local root = Instance.new("Part")
    root.Name = "Noclipov_Marker_Root"
    root.Size = Vector3.new(0.1, 0.1, 0.1)
    root.CFrame = CFrame.new(pos)
    root.Anchored = true; root.CanCollide = false
    root.CanQuery = false; root.CanTouch = false
    root.Transparency = 1; root.Parent = Workspace

    local ring = Instance.new("Part")
    ring.Name = "Noclipov_Marker_Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.03, 3.0, 3.0)
    ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90))
    ring.Anchored = true; ring.CanCollide = false
    ring.CanQuery = false; ring.CanTouch = false
    ring.Material = Enum.Material.SmoothPlastic
    ring.Color = color; ring.Transparency = 0.55
    ring.Parent = Workspace
    local ringGlow = Instance.new("PointLight")
    ringGlow.Color = color; ringGlow.Range = 4
    ringGlow.Brightness = 0.3; ringGlow.Shadows = false
    ringGlow.Parent = ring

    local ringOuter = Instance.new("Part")
    ringOuter.Name = "Noclipov_Marker_RingOuter"
    ringOuter.Shape = Enum.PartType.Cylinder
    ringOuter.Size = Vector3.new(0.02, 3.8, 3.8)
    ringOuter.CFrame = CFrame.new(pos + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
    ringOuter.Anchored = true; ringOuter.CanCollide = false
    ringOuter.CanQuery = false; ringOuter.CanTouch = false
    ringOuter.Material = Enum.Material.SmoothPlastic
    ringOuter.Color = color; ringOuter.Transparency = 0.78
    ringOuter.Parent = Workspace

    local crystal = Instance.new("Part")
    crystal.Name = "Noclipov_Marker_Crystal"
    crystal.Shape = Enum.PartType.Block
    crystal.Size = Vector3.new(0.08, 1.4, 0.08)
    crystal.CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0))
    crystal.Anchored = true; crystal.CanCollide = false
    crystal.CanQuery = false; crystal.CanTouch = false
    crystal.Material = Enum.Material.SmoothPlastic
    crystal.Color = color; crystal.Transparency = 0.25
    crystal.Parent = Workspace

    local cap = Instance.new("Part")
    cap.Name = "Noclipov_Marker_Cap"
    cap.Shape = Enum.PartType.Ball
    cap.Size = Vector3.new(0.35, 0.35, 0.35)
    cap.CFrame = CFrame.new(pos + Vector3.new(0, 2.55, 0))
    cap.Anchored = true; cap.CanCollide = false
    cap.CanQuery = false; cap.CanTouch = false
    cap.Material = Enum.Material.SmoothPlastic
    cap.Color = color; cap.Transparency = 0.1
    cap.Parent = Workspace

    local glow = Instance.new("Part")
    glow.Name = "Noclipov_Marker_Glow"
    glow.Shape = Enum.PartType.Ball
    glow.Size = Vector3.new(1.2, 1.2, 1.2)
    glow.CFrame = cap.CFrame
    glow.Anchored = true; glow.CanCollide = false
    glow.CanQuery = false; glow.CanTouch = false
    glow.Material = Enum.Material.ForceField
    glow.Color = color; glow.Transparency = 0.85
    glow.Parent = Workspace

    local beamAttach0 = Instance.new("Attachment")
    beamAttach0.Position = Vector3.new(0, 0, 0); beamAttach0.Parent = root
    local beamAttach1 = Instance.new("Attachment")
    beamAttach1.Position = Vector3.new(0, 12, 0); beamAttach1.Parent = root
    local pillar = Instance.new("Beam")
    pillar.Attachment0 = beamAttach0; pillar.Attachment1 = beamAttach1
    pillar.Width0 = 0.08; pillar.Width1 = 0.02
    pillar.Color = ColorSequence.new(color)
    pillar.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.85),
        NumberSequenceKeypoint.new(0.5, 0.95),
        NumberSequenceKeypoint.new(1, 1),
    })
    pillar.FaceCamera = true; pillar.LightEmission = 0.4; pillar.LightInfluence = 0
    pillar.Parent = root

    local light = Instance.new("PointLight")
    light.Color = color; light.Range = 6
    light.Brightness = 0.6; light.Shadows = false
    light.Parent = cap

    return {
        root=root, ring=ring, ringGlow=ringGlow, ringOuter=ringOuter,
        crystal=crystal, cap=cap, glow=glow, pillar=pillar, light=light, pos=pos,
    }
end
local function DestroyMarkerVisual(m)
    if not m then return end
    for _, key in ipairs({"root", "ring", "ringOuter", "crystal", "cap", "glow"}) do
        if m[key] then pcall(function() m[key]:Destroy() end) end
    end
    if m.billboard then pcall(function() m.billboard:Destroy() end) end
end
local function BuildMarkerBillboard(crystalPart, title, subtitle, meta, color, isUnsaved)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 190, 0, 56)
    bb.StudsOffset = Vector3.new(0, 3.4, 0)
    bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.Parent = crystalPart

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Theme.BgDarkest
    bg.BackgroundTransparency = 0.15
    bg.BorderSizePixel = 0; bg.Parent = bb
    Corner(bg, 10); Stroke(bg, color, 1, 0.7)

    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 2, 0, 22)
    accentBar.Position = UDim2.new(0, 0, 0.5, -11)
    accentBar.BackgroundColor3 = color
    accentBar.BackgroundTransparency = 0.35
    accentBar.BorderSizePixel = 0; accentBar.Parent = bg
    Corner(accentBar, 1)

    MakeLabel(bg, {
        Size = UDim2.new(1, -60, 0, 16), Position = UDim2.new(0, 10, 0, 6),
        Text = title, TextSize = 12, TextColor3 = Theme.Text,
        Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    if isUnsaved then
        local badge = Instance.new("Frame")
        badge.Size = UDim2.new(0, 50, 0, 14)
        badge.Position = UDim2.new(1, -58, 0, 7)
        badge.BackgroundColor3 = color
        badge.BackgroundTransparency = 0.82
        badge.BorderSizePixel = 0; badge.Parent = bg
        Corner(badge, 4); Stroke(badge, color, 1, 0.4)
        MakeLabel(badge, {
            Text = "UNSAVED", TextColor3 = color,
            TextSize = 7, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    end
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -20, 0, 1)
    div.Position = UDim2.new(0, 10, 0, 26)
    div.BackgroundColor3 = Theme.Border
    div.BorderSizePixel = 0; div.BackgroundTransparency = 0.75
    div.Parent = bg

    MakeLabel(bg, {
        Size = UDim2.new(1, -20, 0, 12), Position = UDim2.new(0, 10, 0, 31),
        Text = subtitle, TextColor3 = Theme.TextDim,
        TextSize = 9, Font = Enum.Font.Code, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    if meta and meta ~= "" then
        MakeLabel(bg, {
            Size = UDim2.new(1, -20, 0, 10), Position = UDim2.new(0, 10, 0, 43),
            Text = meta, TextColor3 = Theme.TextMuted,
            TextSize = 8, Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd,
        })
    end
    return bb
end
local function DestroyMarker(name)
    local m = MarkerParts[name]; if not m then return end
    DestroyMarkerVisual(m); MarkerParts[name] = nil
end
local function CreateMarker(rec)
    local startPos, decoded = RecReadFirstFrame(rec.path)
    if not startPos or not decoded then return end
    local visual = CreateMarkerVisual(startPos, Theme.Accent, false)
    local meta = ""
    if decoded.createdAt then
        local ok, dateStr = pcall(function() return os.date("%d %b %Y · %H:%M", decoded.createdAt) end)
        if ok then meta = dateStr end
    end
    visual.billboard = BuildMarkerBillboard(visual.crystal, rec.name,
        string.format("%.1fs · %d frames", rec.duration, rec.frameCount),
        meta, Theme.Accent, false)
    visual.rec = rec; visual.startPos = startPos
    visual.isFar = false; visual.pulsePhase = math.random() * 2
    visual.pulseBaseSize = 3.0
    MarkerParts[rec.name] = visual
end
RefreshMarkers = function()
    for name in pairs(MarkerParts) do DestroyMarker(name) end
    if not State.MarkersEnabled then return end
    if AreMarkersBlocked() then return end
    for _, rec in ipairs(RecorderState.Saved) do CreateMarker(rec) end
end
local function SetMarkersVisible(v)
    State.MarkersEnabled = v
    if v then RefreshMarkers()
    else for name in pairs(MarkerParts) do DestroyMarker(name) end end
end
local function DestroyUnsavedMarker()
    if not UnsavedMarker then return end
    pcall(function() if UnsavedMarker.pillar then UnsavedMarker.pillar:Destroy() end end)
    pcall(function() if UnsavedMarker.light  then UnsavedMarker.light:Destroy()  end end)
    DestroyMarkerVisual(UnsavedMarker); UnsavedMarker = nil
end
function CreateUnsavedMarker(frames)
    DestroyUnsavedMarker()
    if not frames or #frames < 1 then return end
    local f = frames[1]; local pos = Vector3.new(f.px, f.py, f.pz)
    local visual = CreateMarkerVisual(pos, Theme.Warning, true)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "Unsaved Recording",
        string.format("%.1fs · %d frames", frames[#frames].t, #frames),
        "Save from REC tab to keep", Theme.Warning, true)
    visual.startPos = pos; visual.isFar = false
    visual.pulsePhase = 0; visual.pulseBaseSize = 3.0
    visual.isUnsaved = true; UnsavedMarker = visual
end
local function DestroyPlaybackStartMarker()
    if not PlaybackState.StartMarker then return end
    DestroyMarkerVisual(PlaybackState.StartMarker); PlaybackState.StartMarker = nil
end
local function CreatePlaybackStartMarker(pos)
    DestroyPlaybackStartMarker()
    local visual = CreateMarkerVisual(pos, Theme.Success, false)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "START POINT",
        PlaybackState.RecName or "?", "Playback origin", Theme.Success, false)
    visual.isFar = false; visual.pulsePhase = 0; visual.pulseBaseSize = 3.0
    visual.startPos = pos
    PlaybackState.StartMarker = visual
end

-- ================= PLAYBACK =================
local function ClearPlaybackPath()
    for _, p in ipairs(PlaybackPath.parts) do pcall(function() p:Destroy() end) end
    table.clear(PlaybackPath.parts); PlaybackPath.active = false
end
local function CreatePlaybackPath(frames, count)
    ClearPlaybackPath(); if not frames or #frames < 2 then return end
    count = count or 50; local total = #frames
    for i = 1, count do
        local idx = math.clamp(math.floor((i - 1) / (count - 1) * (total - 1)) + 1, 1, total)
        local f = frames[idx]
        local p = Instance.new("Part")
        p.Name = "Noclipov_PlaybackPath_" .. i
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.22, 0.22, 0.22)
        p.Position = Vector3.new(f.px, f.py, f.pz)
        p.Anchored = true; p.CanCollide = false
        p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.Neon; p.Color = Theme.Accent
        p.Transparency = 0.7; p.Parent = Workspace
        p:SetAttribute("t", f.t)
        table.insert(PlaybackPath.parts, p)
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
function SetPlaybackSpeed(speed)
    speed = math.clamp(tonumber(speed) or 1, 0.5, 3.0)
    if PlaybackState.Active then
        local now = os.clock()
        local curElapsed = (now - PlaybackState.StartTime) * (PlaybackState.Speed or 1)
        PlaybackState.Speed = speed
        PlaybackState.StartTime = now - curElapsed / speed
    else
        PlaybackState.Speed = speed
    end
    CFG.PlaybackSpeed = speed
end
local function StopPlayback(silent)
    if not PlaybackState.Active then return end
    local wasBhop = PlaybackState.WasBhopEnabled
    local wasPred = PlaybackState.WasPredEnabled
    local wasPredToggle = PlaybackState.WasPredToggleState
    PlaybackState.Active = false
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hum and PlaybackState.OriginalAutoRotate ~= nil then
        pcall(function() hum.AutoRotate = PlaybackState.OriginalAutoRotate end)
    end
    if hrp and PlaybackState.OriginalHrpCollide ~= nil then
        pcall(function() hrp.CanCollide = PlaybackState.OriginalHrpCollide end)
    end
    PlaybackState.OriginalAutoRotate = nil; PlaybackState.OriginalHrpCollide = nil
    pcall(function() if PlaybackState.AlignPos then PlaybackState.AlignPos:Destroy() end end)
    pcall(function() if PlaybackState.AlignOri then PlaybackState.AlignOri:Destroy() end end)
    pcall(function() if PlaybackState.Attach0 then PlaybackState.Attach0:Destroy() end end)
    PlaybackState.AlignPos = nil; PlaybackState.AlignOri = nil; PlaybackState.Attach0 = nil
    PlaybackState.Frames = nil; PlaybackState.RecName = nil
    PlaybackState.WasBhopEnabled = false
    PlaybackState.WasPredEnabled = false; PlaybackState.WasPredToggleState = false
    ClearPlaybackPath(); DestroyPlaybackStartMarker()
    if not silent and wasBhop then
        if ToggleRefs["Auto BunnyHop"] then ToggleRefs["Auto BunnyHop"](true) end
    end
    if wasPred and not silent then
        State.LandPredEnabled = true
        if ToggleRefs["Landing Prediction"] and wasPredToggle then
            pcall(function() ToggleRefs["Landing Prediction"](true) end)
        end
    end
    if UI.RecStatusLabel and not silent then
        UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted
    end
end
local function StartPlayback(recName, frames, duration)
    if PlaybackState.Active then StopPlayback() end
    if not frames or #frames < 2 or RecorderState.IsRecording then return end
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum then return end
    PlaybackState.WasBhopEnabled = State.BhopEnabled
    if State.BhopEnabled then
        State.BhopEnabled = false
        if ToggleRefs["Auto BunnyHop"] then ToggleRefs["Auto BunnyHop"](false) end
    end
    PlaybackState.WasPredEnabled = State.LandPredEnabled
    PlaybackState.WasPredToggleState = State.LandPredEnabled
    if State.LandPredEnabled then
        State.LandPredEnabled = false
        if ToggleRefs["Landing Prediction"] then ToggleRefs["Landing Prediction"](false) end
        DestroyPred(); PredState.FadeState = "hidden"; PredState.FadeProgress = 0
    end
    PlaybackState.RecName = recName
    local firstFrame = frames[1]
    local firstPos   = Vector3.new(firstFrame.px, firstFrame.py, firstFrame.pz)
    local firstLook  = Vector3.new(firstFrame.lx, firstFrame.ly, firstFrame.lz)
    if firstLook.Magnitude < 0.01 then firstLook = Vector3.new(0, 0, -1) end
    PlaybackState.OriginalAutoRotate = hum.AutoRotate
    PlaybackState.OriginalHrpCollide = hrp.CanCollide
    hum.AutoRotate = false
    hrp.CanCollide = false
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = CFrame.lookAt(firstPos, firstPos + firstLook.Unit)
    end)
    CreatePlaybackStartMarker(firstPos)
    PlaybackState.Active    = true
    PlaybackState.Frames    = frames
    PlaybackState.Duration  = duration or frames[#frames].t
    PlaybackState.Speed     = CFG.PlaybackSpeed or 1.0
    PlaybackState.StartTime = os.clock()
    CreatePlaybackPath(frames, 50)
    if UI.RecStatusLabel then
        UI.RecStatusLabel.Text = "▶ Playing: " .. recName
        UI.RecStatusLabel.TextColor3 = Theme.Accent
    end
end
local function TryStartNearbyPlayback()
    if PlaybackState.Active then StopPlayback(); return end
    if RecorderState.Cache then
        StartPlayback("Unsaved", RecorderState.Cache.frames, RecorderState.Cache.duration)
        return
    end
    if RecorderState.IsRecording then
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = "Cannot play while recording"
            UI.RecStatusLabel.TextColor3 = Theme.Warning
        end
        return
    end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
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
            UI.RecStatusLabel.Text = string.format("No marker within %d studs", PLAY_RADIUS)
            UI.RecStatusLabel.TextColor3 = Theme.Warning
            task.delay(2, function()
                if UI.RecStatusLabel and not PlaybackState.Active and not RecorderState.IsRecording then
                    UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted
                end
            end)
        end
        return
    end
    StartPlayback(nearestRec.name, nearestDecoded.frames, nearestDecoded.duration)
end
local function UpdatePlayback()
    if not PlaybackState.Active then return end
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum then StopPlayback(); return end
    if hum.Health <= 0 then StopPlayback(); return end
    local frames = PlaybackState.Frames
    if not frames or #frames < 2 then StopPlayback(); return end
    local elapsed = (os.clock() - PlaybackState.StartTime) * (PlaybackState.Speed or 1)
    if elapsed >= PlaybackState.Duration then StopPlayback(); return end
    local lo, hi = 1, #frames
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if frames[mid].t <= elapsed then lo = mid else hi = mid end
    end
    local A = frames[lo]; local B = frames[hi]
    local dtAB = B.t - A.t
    local alpha = dtAB > 0 and math.clamp((elapsed - A.t) / dtAB, 0, 1) or 0
    local targetPos = Vector3.new(
        A.px + (B.px - A.px) * alpha,
        A.py + (B.py - A.py) * alpha,
        A.pz + (B.pz - A.pz) * alpha)
    local lookVec = Vector3.new(
        A.lx + (B.lx - A.lx) * alpha,
        A.ly + (B.ly - A.ly) * alpha,
        A.lz + (B.lz - A.lz) * alpha)
    if lookVec.Magnitude < 0.01 then lookVec = Vector3.new(0, 0, -1) end
    local vx = (A.vx or 0) + ((B.vx or 0) - (A.vx or 0)) * alpha
    local vy = (A.vy or 0) + ((B.vy or 0) - (A.vy or 0)) * alpha
    local vz = (A.vz or 0) + ((B.vz or 0) - (A.vz or 0)) * alpha
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
        hrp.CFrame = CFrame.lookAt(targetPos, targetPos + lookVec.Unit)
    end)
    UpdatePlaybackPath(elapsed)
end

-- ================= UI SETUP =================
DeepCleanupPrevious()
EnsureBaseFolders()

UI.ScreenGui = New("ScreenGui", {
    Name=UI_NAME, ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=SafeParent(),
})

local WIN_W, WIN_H   = 720, 620
local HEADER_H       = 60
local TAB_H          = 48
local PAD            = 16
local WM_W, WM_H     = 280, 148
local WM_H_COMPACT   = 96
local RM_W, RM_H     = 280, 152
local RM_H_COMPACT   = 100

local function DrawIcon(parent, iconData)
    if not iconData then return end
    MakeLabel(parent, { Text=iconData, TextColor3=Theme.TextDim, TextSize=18,
        TextXAlignment=Enum.TextXAlignment.Center, TextYAlignment=Enum.TextYAlignment.Center })
end
local function MakeIconBadge(parent, size, pos, iconData)
    if not iconData then return nil, nil end
    local box = MakeFrame(parent, {
        Size=UDim2.new(0, size, 0, size), Position=pos,
        BackgroundColor3=Theme.SurfaceLight, BackgroundTransparency=0.2,
    })
    Corner(box, math.floor(size * 0.32))
    Gradient(box, { Theme.SurfaceHover, Theme.SurfaceBase }, 45)
    local stroke = Stroke(box, Theme.Border, 1, 0.6)
    DrawIcon(box, iconData)
    return box, stroke
end
local function MakeSwitch(parent, default, cb, opts)
    opts = opts or {}
    local swW, swH = opts.width or 46, opts.height or 26
    local knobSize = opts.knobSize or 20
    local padRight = opts.padRight or 16
    local toggled = default
    local sw = New("TextButton", {
        Size = UDim2.new(0, swW, 0, swH),
        Position = UDim2.new(1, -(swW + padRight), 0.5, -swH / 2),
        BackgroundColor3 = toggled and Theme.AccentDark or Theme.SurfaceBase,
        BackgroundTransparency = 0, BorderSizePixel = 0, Text = "",
        AutoButtonColor = false, Parent = parent, ZIndex = 3, ClipsDescendants = true,
    })
    Corner(sw, math.floor(swH / 2))
    local swGradient = Instance.new("UIGradient")
    swGradient.Color = toggled and SEQ_SWITCH_ON or SEQ_SWITCH_OFF
    swGradient.Parent = sw
    local swStroke = Stroke(sw, toggled and Theme.AccentSoft or Theme.Border, 1, toggled and 0.4 or 0.8)
    local knobPosOn  = UDim2.new(1, -(knobSize + 3), 0.5, -knobSize / 2)
    local knobPosOff = UDim2.new(0, 3, 0.5, -knobSize / 2)
    local knob = MakeFrame(sw, {
        Size = UDim2.new(0, knobSize, 0, knobSize),
        Position = toggled and knobPosOn or knobPosOff,
        BackgroundColor3 = Theme.TextBright, ZIndex = 4,
    })
    Corner(knob, math.floor(knobSize / 2))
    Gradient(knob, { Color3.fromRGB(255,255,255), Color3.fromRGB(220,225,235) }, 90)
    AddShadow(knob, { transparency = 0.6, blur = 8, offset = Vector2.new(0, 2) })
    
    local function set(val, isSilent)
        toggled = val
        local bgColor = toggled and Theme.AccentDark or Theme.SurfaceBase
        local strokeColor = toggled and Theme.AccentSoft or Theme.Border
        local strokeTrans = toggled and 0.4 or 0.8
        local targetPos = toggled and knobPosOn or knobPosOff

        if isSilent then
            sw.BackgroundColor3 = bgColor
            knob.Position = targetPos
            swStroke.Color = strokeColor
            swStroke.Transparency = strokeTrans
            swGradient.Color = toggled and SEQ_SWITCH_ON or SEQ_SWITCH_OFF
        else
            Tween(sw, { BackgroundColor3 = bgColor }, 0.24)
            Tween(knob, { Position = targetPos }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            Tween(swStroke, { Color = strokeColor, Transparency = strokeTrans }, 0.22)
            swGradient.Color = toggled and SEQ_SWITCH_ON or SEQ_SWITCH_OFF
        end
        if cb then cb(toggled) end
    end
    sw.MouseButton1Click:Connect(function() set(not toggled, false); if SaveConfig then SaveConfig() end end)
    return set
end
local function MakeSlider(parent, min, max, default, cb, opts)
    opts = opts or {}
    local decimals = opts.decimals or 0
    local mult = 10 ^ decimals
    local pillW = opts.pillWidth or 58
    local snaps = opts.snaps or {}
    local snapRadiusPx = opts.snapRadius or 5
    local currentV = default

    local pill = MakeFrame(parent, {
        Size=UDim2.new(0, pillW, 0, 22),
        Position=UDim2.new(1, -pillW, 0, 0),
        BackgroundColor3=Theme.BgDarkest, BackgroundTransparency=0.2, ZIndex=2,
    })
    Corner(pill, 11); Stroke(pill, Theme.Border, 1, 0.8)
    local val = MakeLabel(pill, {
        Text=string.format("%." .. decimals .. "f", default),
        TextColor3=Theme.Accent, TextSize=11, Font=Enum.Font.Code,
        TextXAlignment=Enum.TextXAlignment.Center,
    })
    local track = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = Theme.BgDarkest, BackgroundTransparency = 0,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        Parent = parent, ZIndex = 3,
    })
    Corner(track, 3); Stroke(track, Theme.Border, 1, 0.8)
    local fill = MakeFrame(track, {
        Size=UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3=Theme.Accent, BackgroundTransparency=0, ZIndex=3,
    })
    Corner(fill, 3); Gradient(fill, { Theme.AccentDark, Theme.AccentSoft }, 0)
    local knob = MakeFrame(track, {
        Size=UDim2.new(0, 16, 0, 16), AnchorPoint=Vector2.new(0.5, 0.5),
        Position=UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        BackgroundColor3=Theme.TextBright, ZIndex=5,
    })
    Corner(knob, 8); Stroke(knob, Theme.Accent, 2, 0.2)
    AddShadow(knob, { color=Theme.Accent, transparency=0.4, blur=10, offset=Vector2.new(0, 0) })

    local snapMarkers = {}
    for _, sv in ipairs(snaps) do
        if sv >= min and sv <= max then
            local pct = (sv - min) / (max - min)
            local dot = MakeFrame(track, {
                Size = UDim2.new(0, 5, 0, 5),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(pct, 0, 0.5, 0),
                BackgroundColor3 = Theme.TextMuted,
                BackgroundTransparency = 0.4, ZIndex = 2,
            })
            Corner(dot, 3)
            table.insert(snapMarkers, {value = sv, pct = pct, frame = dot})
        end
    end
    
    local function applySnap(rawV)
        if #snapMarkers == 0 then return rawV end
        local trackPx = track.AbsoluteSize.X
        if trackPx <= 0 then return rawV end
        local valuePerPx = (max - min) / trackPx
        local tolerance = snapRadiusPx * valuePerPx
        local bestV, bestDelta = rawV, tolerance + 1
        for _, sm in ipairs(snapMarkers) do
            local d = math.abs(rawV - sm.value)
            if d < bestDelta then bestDelta = d; bestV = sm.value end
        end
        return bestDelta <= tolerance and bestV or rawV
    end
    
    local function refreshSnapMarkerHighlight(currentVal)
        for _, sm in ipairs(snapMarkers) do
            local near = math.abs(currentVal - sm.value) < 0.0001
            sm.frame.BackgroundColor3 = near and Theme.Accent or Theme.TextMuted
            sm.frame.BackgroundTransparency = near and 0 or 0.4
            sm.frame.Size = near and UDim2.new(0, 7, 0, 7) or UDim2.new(0, 5, 0, 5)
        end
    end
    
    local function updateUI(v, applyMagnet)
        v = math.clamp(v, min, max)
        if applyMagnet then v = applySnap(v) end
        currentV = v
        v = math.floor(v * mult + 0.5) / mult
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        val.Text = string.format("%." .. decimals .. "f", v)
        refreshSnapMarkerHighlight(v)
        if cb then cb(v) end
    end
    
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            local raw = min + (max - min) * (math.clamp(
                input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X
            ) / track.AbsoluteSize.X)
            
            -- Клик по треку - применяем магнит сразу
            updateUI(raw, true)
            
            Tween(knob, { Size = UDim2.new(0, 20, 0, 20) }, 0.12)
            if opts.onDragStart then opts.onDragStart() end
            
            SetInteraction({
                onMove = function(inp)
                    local rawMove = min + (max - min) * (math.clamp(
                        inp.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X
                    ) / track.AbsoluteSize.X)
                    -- При перетаскивании магнит отключен
                    updateUI(rawMove, false)
                end,
                onEnd = function()
                    Tween(knob, { Size = UDim2.new(0, 16, 0, 16) }, 0.1)
                    -- При отпускании применяем магнит
                    updateUI(currentV, true)
                    if opts.onDragEnd then opts.onDragEnd() end
                    if SaveConfig then SaveConfig() end
                end,
            })
        end
    end)
    return updateUI
end
local function MakeKeycap(parent, defaultKey, actionId, opts)
    opts = opts or {}
    local w, h = opts.width or 74, opts.height or 26
    local holder = MakeFrame(parent, {
        Size = UDim2.new(0, w, 0, h),
        Position = UDim2.new(1, -w, 0.5, -h / 2),
        BackgroundTransparency = 1, ZIndex = 2,
    })
    Corner(holder, 7)
    local bindBtn = New("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.SurfaceBase, BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = defaultKey and defaultKey.Name or "None",
        TextColor3 = defaultKey and Theme.Text or Theme.TextMuted,
        TextSize = 11, Font = Enum.Font.Code,
        AutoButtonColor = false, ZIndex = 2, Parent = holder,
    })
    Corner(bindBtn, 6); local bindStroke = Stroke(bindBtn, Theme.Border, 1, 0.8)
    ApplyHover(bindBtn, { scale=1.05, stroke=bindStroke, hoverStrokeColor=Theme.Accent, hoverStrokeTransp=0.3 })
    ApplyPress(bindBtn, { pressScale=0.96, hoverScale=1.05 })
    HotkeyButtons[actionId] = bindBtn
    bindBtn.MouseButton1Click:Connect(function()
        awaitingBind = actionId
        bindBtn.Text = "..."; bindBtn.TextColor3 = Theme.Accent
        Tween(bindBtn, { BackgroundColor3 = Theme.AccentDark }, 0.12)
    end)
    bindBtn.MouseButton2Click:Connect(function()
        Hotkeys[actionId] = nil
        bindBtn.Text = "None"; bindBtn.TextColor3 = Theme.TextMuted
        Tween(bindBtn, { BackgroundColor3 = Theme.SurfaceBase }, 0.12)
        if SaveConfig then SaveConfig() end
    end)
    return bindBtn
end

-- ================= LAUNCHER =================
UI.LauncherIcon = New("TextButton", {
    Name = "LauncherIcon", Size = UDim2.new(0, 50, 0, 50),
    Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0,
    Text = "N", TextColor3 = Theme.TextBright, TextSize = 22,
    Font = Enum.Font.GothamBold, AutoButtonColor = false,
    ZIndex = 2, Parent = UI.ScreenGui,
})
Corner(UI.LauncherIcon, 15); Gradient(UI.LauncherIcon, { Theme.Accent, Theme.AccentDark }, 45)
local launcherStroke = Stroke(UI.LauncherIcon, Theme.AccentSoft, 1.2, 0.5)
AddShadow(UI.LauncherIcon, { color=Theme.Accent, transparency=0.5, blur=25, offset=Vector2.new(0, 8) })
ApplyHover(UI.LauncherIcon, { scale=1.06, stroke=launcherStroke, hoverStrokeColor=Theme.AccentSoft, hoverStrokeTransp=0.2 })
ApplyPress(UI.LauncherIcon, { pressScale=0.94, hoverScale=1.06 })
MakeDraggable(UI.LauncherIcon, UI.LauncherIcon, nil, function(moved)
    if SaveConfig then SaveConfig() end
    if moved then launcherDragEndTime = os.clock() end
end)

-- ================= WATERMARK =================
UI.WatermarkFrame = MakeFrame(UI.ScreenGui, {
    Name = "Watermark", Size = UDim2.new(0, WM_W, 0, WM_H),
    Position = UDim2.new(0, 16, 0, 16),
    BackgroundColor3 = Theme.BgDarkest, BackgroundTransparency = 0.05,
    Active = true, Visible = State.WatermarkEnabled,
})
StyleGlassPanel(UI.WatermarkFrame); Pad(UI.WatermarkFrame, 12, 14, 10, 14)

local wmHeader = MakeFrame(UI.WatermarkFrame, {
    Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
})
MakeLabel(wmHeader, {
    Size=UDim2.new(1, -130, 1, 0), Text="NOCLIPOV",
    TextSize=10, TextColor3=Theme.Text, Font=Enum.Font.GothamBold,
})
UI.WmSpeedBadge = MakeFrame(wmHeader, {
    Size=UDim2.new(0, 44, 0, 14),
    Position=UDim2.new(1, -108, 0, 0),
    BackgroundColor3=Theme.Accent, BackgroundTransparency=0.2,
    Visible=false, ZIndex=4,
})
Corner(UI.WmSpeedBadge, 7); Stroke(UI.WmSpeedBadge, Theme.AccentSoft, 1, 0.4)
UI.WmSpeedBadgeLbl = MakeLabel(UI.WmSpeedBadge, {
    Text="×1.00", TextColor3=Theme.BgDarkest, TextSize=9,
    Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center,
})
UI.WmLivePill = MakeFrame(wmHeader, {
    Size = UDim2.new(0, 60, 0, 14), Position = UDim2.new(1, -60, 0, 0),
    BackgroundColor3 = Theme.SurfaceBase, BackgroundTransparency = 0.3, ZIndex = 2,
})
Corner(UI.WmLivePill, 7); Stroke(UI.WmLivePill, Theme.Border, 1, 0.5)
UI.WmLiveDot = MakeFrame(UI.WmLivePill, {
    Size=UDim2.new(0, 5, 0, 5), Position=UDim2.new(0, 7, 0.5, -2.5),
    BackgroundColor3=Theme.TextMuted, ZIndex=3,
}); Corner(UI.WmLiveDot, 2.5)
UI.WmLiveLabel = MakeLabel(UI.WmLivePill, {
    Size=UDim2.new(1, -16, 1, 0), Position=UDim2.new(0, 16, 0, 0),
    Text="IDLE", TextSize=8, Font=Enum.Font.GothamBold, TextColor3=Theme.TextMuted,
})

local wmDiv1 = MakeFrame(UI.WatermarkFrame, {
    Size=UDim2.new(1, 0, 0, 1), Position=UDim2.new(0, 0, 0, 19),
    BackgroundColor3=Theme.Border, BackgroundTransparency=0.6,
}); Gradient(wmDiv1, { Theme.BorderLight, Theme.BgDarkest }, 0)

UI.WmHero = MakeFrame(UI.WatermarkFrame, {
    Size=UDim2.new(1, 0, 0, 52), Position=UDim2.new(0, 0, 0, 25),
    BackgroundTransparency=1,
})
UI.WmSpeedVal = MakeLabel(UI.WmHero, {
    Size=UDim2.new(1, -50, 0, 34), Position=UDim2.new(0, 0, 0, 0),
    Text="0.0", TextColor3=Theme.TextBright, TextSize=30, Font=Enum.Font.GothamBold,
})
MakeLabel(UI.WmHero, {
    Size=UDim2.new(0, 50, 0, 16), Position=UDim2.new(1, -50, 0, 10),
    Text="U/S", TextColor3=Theme.Accent, TextSize=10, Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Right,
})
UI.WmSubSpeedLbl = MakeLabel(UI.WmHero, {
    Size=UDim2.new(1, 0, 0, 10), Position=UDim2.new(0, 0, 0, 38),
    Text="CURRENT SPEED", TextColor3=Theme.TextMuted,
    TextSize=8, Font=Enum.Font.GothamBold,
})

UI.WmDiv2 = MakeFrame(UI.WatermarkFrame, {
    Size=UDim2.new(1, 0, 0, 1), Position=UDim2.new(0, 0, 0, 79),
    BackgroundColor3=Theme.Border, BackgroundTransparency=0.6,
}); Gradient(UI.WmDiv2, { Theme.BorderLight, Theme.BgDarkest }, 0)

UI.WmMiniGrid = MakeFrame(UI.WatermarkFrame, {
    Size=UDim2.new(1, 0, 0, 28), Position=UDim2.new(0, 0, 0, 85),
    BackgroundTransparency=1,
})
local colW = 0.25
local function MakeMiniStat(parent, x, label)
    local col = MakeFrame(parent, {
        Size=UDim2.new(colW, -2, 1, 0),
        Position=UDim2.new(x + 0.002, 0, 0, 0),
        BackgroundTransparency=1,
    })
    local val = MakeLabel(col, {
        Size=UDim2.new(1, 0, 0, 16), Text="--", TextSize=13,
        Font=Enum.Font.GothamBold, TextColor3=Theme.Text,
    })
    MakeLabel(col, {
        Size=UDim2.new(1, 0, 0, 9), Position=UDim2.new(0, 0, 0, 17),
        Text=label, TextSize=7, TextColor3=Theme.TextMuted, Font=Enum.Font.GothamBold,
    })
    return val
end
UI.WmFpsVal  = MakeMiniStat(UI.WmMiniGrid, 0, "FPS")
UI.WmPingVal = MakeMiniStat(UI.WmMiniGrid, colW, "PING")
UI.WmMaxVal  = MakeMiniStat(UI.WmMiniGrid, colW*2, "MAX")
UI.WmTimeVal = MakeMiniStat(UI.WmMiniGrid, colW*3, "TIME")

local WmSpeedBarBg = MakeFrame(UI.WatermarkFrame, {
    Size=UDim2.new(1, 0, 0, 3), Position=UDim2.new(0, 0, 1, -3),
    BackgroundColor3=Theme.BgMain, BackgroundTransparency=0,
})
Corner(WmSpeedBarBg, 1.5); Stroke(WmSpeedBarBg, Theme.Border, 1, 0.6)
UI.WmSpeedBarFill = MakeFrame(WmSpeedBarBg, {
    Size=UDim2.new(0, 0, 1, 0), BackgroundColor3=Theme.Accent,
}); Corner(UI.WmSpeedBarFill, 1.5); Gradient(UI.WmSpeedBarFill, { Theme.Accent, Theme.AccentSoft }, 0)
UI.WmSpeedBarBg = WmSpeedBarBg

MakeDraggable(UI.WatermarkFrame, UI.WatermarkFrame, function() return IsVisible end,
    function() if SaveConfig then SaveConfig() end end)

-- ================= RECORDER STATUS =================
UI.RecorderStatusFrame = MakeFrame(UI.ScreenGui, {
    Name = "RecorderStatus", Size = UDim2.new(0, RM_W, 0, RM_H),
    Position = UDim2.new(0, 16, 0, 180),
    BackgroundColor3 = Theme.BgDarkest, BackgroundTransparency = 0.05,
    Active = true, Visible = State.RecorderStatusEnabled,
})
StyleGlassPanel(UI.RecorderStatusFrame); Pad(UI.RecorderStatusFrame, 12, 14, 12, 14)

local recHeaderRow = MakeFrame(UI.RecorderStatusFrame, {
    Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
})
MakeLabel(recHeaderRow, {
    Size=UDim2.new(1, -66, 1, 0), Text="RECORDER",
    TextSize=10, TextColor3=Theme.Accent, Font=Enum.Font.GothamBold,
})
UI.RecStatusPill = MakeFrame(recHeaderRow, {
    Size = UDim2.new(0, 60, 0, 14), Position = UDim2.new(1, -60, 0, 0),
    BackgroundColor3 = Theme.SurfaceBase, BackgroundTransparency = 0.3, ZIndex = 2,
})
Corner(UI.RecStatusPill, 7); Stroke(UI.RecStatusPill, Theme.Border, 1, 0.5)
UI.RecStatusPillDot = MakeFrame(UI.RecStatusPill, {
    Size=UDim2.new(0, 5, 0, 5), Position=UDim2.new(0, 7, 0.5, -2.5),
    BackgroundColor3=Theme.TextMuted, ZIndex=3,
}); Corner(UI.RecStatusPillDot, 2.5)
UI.RecStatusPillLabel = MakeLabel(UI.RecStatusPill, {
    Size=UDim2.new(1, -16, 1, 0), Position=UDim2.new(0, 16, 0, 0),
    Text="IDLE", TextSize=8, Font=Enum.Font.GothamBold, TextColor3=Theme.TextMuted,
})

local recDiv = MakeFrame(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 1), Position=UDim2.new(0, 0, 0, 19),
    BackgroundColor3=Theme.Border, BackgroundTransparency=0.6,
}); Gradient(recDiv, { Theme.BorderLight, Theme.BgDarkest }, 0)

UI.RecHero = MakeFrame(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 48), Position=UDim2.new(0, 0, 0, 25),
    BackgroundTransparency=1,
})
UI.RecDurCol = MakeFrame(UI.RecHero, {
    Size=UDim2.new(0.5, -4, 1, 0), BackgroundTransparency=1,
})
UI.RecDurationVal = MakeLabel(UI.RecDurCol, {
    Size=UDim2.new(1, 0, 0, 30), Text="--", TextSize=26,
    Font=Enum.Font.GothamBold, TextColor3=Theme.TextBright,
})
MakeLabel(UI.RecDurCol, {
    Size=UDim2.new(1, 0, 0, 10), Position=UDim2.new(0, 0, 0, 32),
    Text="DURATION", TextSize=7, TextColor3=Theme.TextMuted,
    Font=Enum.Font.GothamBold,
})
UI.RecFramesCol = MakeFrame(UI.RecHero, {
    Size=UDim2.new(0.5, -4, 1, 0), Position=UDim2.new(0.5, 4, 0, 0),
    BackgroundTransparency=1,
})
UI.RecFramesVal = MakeLabel(UI.RecFramesCol, {
    Size=UDim2.new(1, 0, 0, 30), Text="--", TextSize=26,
    Font=Enum.Font.GothamBold, TextColor3=Theme.TextBright,
    TextXAlignment=Enum.TextXAlignment.Right,
})
MakeLabel(UI.RecFramesCol, {
    Size=UDim2.new(1, 0, 0, 10), Position=UDim2.new(0, 0, 0, 32),
    Text="FRAMES", TextSize=7, TextColor3=Theme.TextMuted,
    Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Right,
})

local recDiv2 = MakeFrame(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 1), Position=UDim2.new(0, 0, 0, 77),
    BackgroundColor3=Theme.Border, BackgroundTransparency=0.6,
}); Gradient(recDiv2, { Theme.BorderLight, Theme.BgDarkest }, 0)

UI.RecInfoLabel = MakeLabel(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 16), Position=UDim2.new(0, 0, 0, 83),
    Text="Idle", TextColor3=Theme.TextDim, TextSize=12,
    Font=Enum.Font.GothamBold, TextTruncate=Enum.TextTruncate.AtEnd,
})
UI.RecSubLabel = MakeLabel(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 12), Position=UDim2.new(0, 0, 0, 101),
    Text="", TextColor3=Theme.TextMuted, TextSize=9, Font=Enum.Font.Gotham,
    TextTruncate=Enum.TextTruncate.AtEnd,
})
UI.RecProgBg = MakeFrame(UI.RecorderStatusFrame, {
    Size=UDim2.new(1, 0, 0, 3), Position=UDim2.new(0, 0, 1, -3),
    BackgroundColor3=Theme.BgMain, BackgroundTransparency=0, Visible=false,
})
Corner(UI.RecProgBg, 1.5); Stroke(UI.RecProgBg, Theme.Border, 1, 0.6)
UI.RecProgFill = MakeFrame(UI.RecProgBg, {
    Size=UDim2.new(0, 0, 1, 0), BackgroundColor3=Theme.Accent,
}); Corner(UI.RecProgFill, 1.5); Gradient(UI.RecProgFill, { Theme.Accent, Theme.AccentSoft }, 0)

MakeDraggable(UI.RecorderStatusFrame, UI.RecorderStatusFrame, function() return IsVisible end,
    function() if SaveConfig then SaveConfig() end end)

-- ================= COMPACT MODE =================
function ApplyCompactMode(enabled)
    CFG.CompactMode = enabled
    if UI.WatermarkFrame then
        if enabled then
            UI.WatermarkFrame.Size = UDim2.new(0, WM_W, 0, WM_H_COMPACT)
            if UI.WmMiniGrid    then UI.WmMiniGrid.Visible = false end
            if UI.WmDiv2        then UI.WmDiv2.Visible = false end
            if UI.WmSubSpeedLbl then UI.WmSubSpeedLbl.Visible = false end
            if UI.WmHero        then UI.WmHero.Size = UDim2.new(1, 0, 0, 42) end
            if UI.WmSpeedVal    then
                UI.WmSpeedVal.Size = UDim2.new(1, -50, 0, 42)
                UI.WmSpeedVal.TextSize = 34
            end
        else
            UI.WatermarkFrame.Size = UDim2.new(0, WM_W, 0, WM_H)
            if UI.WmMiniGrid    then UI.WmMiniGrid.Visible = true end
            if UI.WmDiv2        then UI.WmDiv2.Visible = true end
            if UI.WmSubSpeedLbl then UI.WmSubSpeedLbl.Visible = true end
            if UI.WmHero        then UI.WmHero.Size = UDim2.new(1, 0, 0, 52) end
            if UI.WmSpeedVal    then
                UI.WmSpeedVal.Size = UDim2.new(1, -50, 0, 34)
                UI.WmSpeedVal.TextSize = 30
            end
        end
    end
    if UI.RecorderStatusFrame then
        if enabled then
            UI.RecorderStatusFrame.Size = UDim2.new(0, RM_W, 0, RM_H_COMPACT)
            if UI.RecFramesCol then UI.RecFramesCol.Visible = false end
            if UI.RecInfoLabel then UI.RecInfoLabel.Visible = false end
            if UI.RecSubLabel  then UI.RecSubLabel.Visible = false end
            if UI.RecDurCol    then UI.RecDurCol.Size = UDim2.new(1, 0, 1, 0) end
            if UI.RecDurationVal then
                UI.RecDurationVal.Size = UDim2.new(1, 0, 1, 0)
                UI.RecDurationVal.TextSize = 34
            end
        else
            UI.RecorderStatusFrame.Size = UDim2.new(0, RM_W, 0, RM_H)
            if UI.RecFramesCol then UI.RecFramesCol.Visible = true end
            if UI.RecInfoLabel then UI.RecInfoLabel.Visible = true end
            if UI.RecSubLabel  then UI.RecSubLabel.Visible = true end
            if UI.RecDurCol    then UI.RecDurCol.Size = UDim2.new(0.5, -4, 1, 0) end
            if UI.RecDurationVal then
                UI.RecDurationVal.Size = UDim2.new(1, 0, 0, 30)
                UI.RecDurationVal.TextSize = 26
            end
        end
    end
end

local function UpdateRecorderStatus()
    if not UI.RecorderStatusFrame.Visible then return end
    local now = os.clock(); local pillText, pillColor
    if RecorderState.IsRecording then
        local dur = now - RecorderState.StartTime
        pillText, pillColor = "REC", Theme.Danger
        UI.RecDurationVal.Text = string.format("%.1fs", dur)
        UI.RecDurationVal.TextColor3 = Theme.Danger
        UI.RecFramesVal.Text = tostring(#RecorderState.Frames)
        UI.RecFramesVal.TextColor3 = Theme.Text
        UI.RecInfoLabel.Text = "Recording..."; UI.RecInfoLabel.TextColor3 = Theme.Danger
        UI.RecSubLabel.Text = string.format("Press %s to stop",
            (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—")
        UI.RecSubLabel.TextColor3 = Theme.TextDim
        UI.RecProgBg.Visible = false
        UI.RecStatusPill.BackgroundTransparency = 0.75 + math.sin(now * math.pi * 3) * 0.15
    elseif PlaybackState.Active then
        UI.RecFramesVal.Text = tostring(#(PlaybackState.Frames or {}))
        UI.RecFramesVal.TextColor3 = Theme.Text
        local elapsed = (now - PlaybackState.StartTime) * (PlaybackState.Speed or 1)
        local pct = math.clamp(elapsed / math.max(0.01, PlaybackState.Duration or 1), 0, 1)
        pillText, pillColor = "PLAY", Theme.Accent
        UI.RecDurationVal.Text = string.format("%.1fs", elapsed)
        UI.RecDurationVal.TextColor3 = Theme.Accent
        UI.RecInfoLabel.Text = PlaybackState.RecName or "?"
        UI.RecInfoLabel.TextColor3 = Theme.Text
        UI.RecSubLabel.Text = string.format("%.1f/%.1fs · %.0f%% · ×%.2f",
            elapsed, PlaybackState.Duration or 0, pct * 100, PlaybackState.Speed or 1)
        UI.RecSubLabel.TextColor3 = Theme.TextDim
        UI.RecProgBg.Visible = true
        UI.RecProgFill.Size = UDim2.new(pct, 0, 1, 0)
        UI.RecStatusPill.BackgroundTransparency = 0.3
    elseif RecorderState.Cache then
        pillText, pillColor = "READY", Theme.Success
        UI.RecDurationVal.Text = string.format("%.1fs", RecorderState.Cache.duration)
        UI.RecDurationVal.TextColor3 = Theme.Success
        UI.RecFramesVal.Text = tostring(RecorderState.Cache.frameCount)
        UI.RecFramesVal.TextColor3 = Theme.Text
        UI.RecInfoLabel.Text = "Ready to save"; UI.RecInfoLabel.TextColor3 = Theme.Success
        UI.RecSubLabel.Text = string.format("Save in REC tab · %s to play",
            (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—")
        UI.RecSubLabel.TextColor3 = Theme.TextDim
        UI.RecProgBg.Visible = false
        UI.RecStatusPill.BackgroundTransparency = 0.3
    else
        pillText, pillColor = "IDLE", Theme.TextMuted
        UI.RecDurationVal.Text = "--"; UI.RecDurationVal.TextColor3 = Theme.TextMuted
        UI.RecFramesVal.Text = "--"; UI.RecFramesVal.TextColor3 = Theme.TextMuted
        UI.RecInfoLabel.Text = "Idle"; UI.RecInfoLabel.TextColor3 = Theme.TextDim
        UI.RecSubLabel.Text = string.format("%s rec · %s play · %d saved",
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
    BackgroundColor3 = Theme.BgMain, BackgroundTransparency = 0.02,
    ClipsDescendants = true, Active = true,
})
Corner(UI.MainFrame, 16); Gradient(UI.MainFrame, { Theme.BgMain, Theme.BgDarkest }, 135)
AddShadow(UI.MainFrame, { transparency=0.4, blur=50, offset=Vector2.new(0, 16) })
Stroke(UI.MainFrame, Theme.BorderLight, 1, 0.4)

UI.Header = MakeFrame(UI.MainFrame, {
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundColor3 = Theme.BgSidebar, BackgroundTransparency = 0.05,
})
Corner(UI.Header, 16)
MakeFrame(UI.Header, {
    Size=UDim2.new(1, 0, 0.5, 0), Position=UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3=Theme.BgSidebar, BackgroundTransparency=0.05,
})
local headerBorder = MakeFrame(UI.Header, {
    Size=UDim2.new(1, 0, 0, 1), Position=UDim2.new(0, 0, 1, -1),
    BackgroundColor3=Theme.Border, BackgroundTransparency=0.6,
}); Gradient(headerBorder, { Theme.BorderLight, Theme.BgSidebar }, 0)

local logoGlow = MakeFrame(UI.Header, {
    Size=UDim2.new(0, 26, 0, 26), Position=UDim2.new(0, 18, 0.5, -13),
    BackgroundColor3=Theme.Accent, BackgroundTransparency=0.85,
})
Corner(logoGlow, 13); AddShadow(logoGlow, { color=Theme.Accent, transparency=0.4, blur=20, offset=Vector2.new(0, 0) })
local logoDot = MakeFrame(UI.Header, {
    Size=UDim2.new(0, 11, 0, 11), Position=UDim2.new(0, 26, 0.5, -5.5),
    BackgroundColor3=Theme.Accent,
})
Corner(logoDot, 5.5); Stroke(logoDot, Theme.AccentSoft, 1, 0.4)
Gradient(logoDot, { Theme.AccentSoft, Theme.AccentDark }, 45)

MakeLabel(UI.Header, {
    Size=UDim2.new(0, 100, 1, 0), Position=UDim2.new(0, 52, 0, 0),
    Text="NOCLIPOV", TextSize=16, Font=Enum.Font.GothamBold,
    TextColor3=Theme.TextBright,
})
local verBadge = MakeFrame(UI.Header, {
    Size=UDim2.new(0, 42, 0, 18), Position=UDim2.new(0, 152, 0.5, -9),
    BackgroundColor3=Theme.SurfaceLight, BackgroundTransparency=0.2,
})
Corner(verBadge, 4); Stroke(verBadge, Theme.Border, 1, 0.5)
MakeLabel(verBadge, {
    Text="v" .. SCRIPT_VERSION, TextColor3=Theme.TextDim,
    TextSize=9, Font=Enum.Font.Code, TextXAlignment=Enum.TextXAlignment.Center,
})

local LightsGroup = MakeFrame(UI.Header, {
    Size=UDim2.new(0, 44, 0, 14), AnchorPoint=Vector2.new(1, 0.5),
    Position=UDim2.new(1, -18, 0.5, 0), BackgroundTransparency=1,
})
New("UIListLayout", {
    Padding=UDim.new(0, 8), FillDirection=Enum.FillDirection.Horizontal,
    VerticalAlignment=Enum.VerticalAlignment.Center, Parent=LightsGroup,
})
local function CreateTrafficLight(color, hoverSymbol, cb)
    local btn = New("TextButton", {
        Size=UDim2.new(0, 12, 0, 12), BackgroundColor3=color,
        BorderSizePixel=0, Text="", AutoButtonColor=false, Parent=LightsGroup,
    })
    Corner(btn, 6); Stroke(btn, Color3.new(0,0,0), 1, 0.8)
    local inner = MakeLabel(btn, {
        Text="", TextColor3=Color3.fromRGB(60, 30, 30), TextSize=8,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center,
        TextTransparency=1,
    })
    local uiscale = Instance.new("UIScale"); uiscale.Scale = 1; uiscale.Parent = btn
    btn.MouseEnter:Connect(function()
        Tween(uiscale, { Scale = 1.2 }, 0.12)
        if inner then inner.Text = hoverSymbol; Tween(inner, { TextTransparency = 0.3 }, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        Tween(uiscale, { Scale = 1 }, 0.12)
        if inner then Tween(inner, { TextTransparency = 1 }, 0.12) end
    end)
    btn.MouseButton1Click:Connect(cb)
end
CreateTrafficLight(Theme.Warning, "—", function() IsVisible=false; UI.MainFrame.Visible=false; if SaveConfig then SaveConfig() end end)
CreateTrafficLight(Theme.Danger, "×", function() Cleanup() end)

-- ================= TAB BAR =================
UI.TabBar = MakeFrame(UI.MainFrame, {
    Name = "TabBar",
    Size = UDim2.new(1, 0, 0, TAB_H),
    Position = UDim2.new(0, 0, 0, HEADER_H),
    BackgroundColor3 = Theme.BgSidebar, BackgroundTransparency = 0.3,
})
Pad(UI.TabBar, 0, 16, 0, 16)
UI.TabContainer = MakeFrame(UI.TabBar, {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
})
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = UI.TabContainer,
})
local tabBarDivider = MakeFrame(UI.MainFrame, {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0, HEADER_H + TAB_H - 1),
    BackgroundColor3 = Theme.Border, BackgroundTransparency = 0.6,
}); Gradient(tabBarDivider, { Theme.BorderLight, Theme.BgDarkest }, 0)

-- ================= CONTENT =================
UI.Content = New("ScrollingFrame", {
    Name = "Content",
    Size = UDim2.new(1, -(PAD * 2 + 12), 1, -(HEADER_H + TAB_H + PAD * 2)),
    Position = UDim2.new(0, PAD, 0, HEADER_H + TAB_H + PAD),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    Parent = UI.MainFrame,
    AutomaticCanvasSize = Enum.AutomaticSize.None,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ElasticBehavior = Enum.ElasticBehavior.Never,
    ScrollingDirection = Enum.ScrollingDirection.Y,
})
local SB_W = 4
UI.ScrollBarTrack = MakeFrame(UI.MainFrame, {
    Name="ScrollBarTrack",
    Size=UDim2.new(0, SB_W, 1, -(HEADER_H + TAB_H + PAD * 2)),
    Position=UDim2.new(1, -12, 0, HEADER_H + TAB_H + PAD),
    BackgroundColor3=Theme.BgDarkest, BackgroundTransparency=0.5,
    ZIndex=10, Visible=false,
})
Corner(UI.ScrollBarTrack, SB_W/2)
UI.ScrollBarThumb = MakeFrame(UI.ScrollBarTrack, {
    Name="ScrollBarThumb", Size=UDim2.new(1, 0, 0.2, 0),
    BackgroundColor3=Theme.Accent, BackgroundTransparency=0.2, ZIndex=11,
})
Corner(UI.ScrollBarThumb, SB_W/2)
local function UpdateScrollBar()
    if not UI.Content.ScrollingEnabled then UI.ScrollBarTrack.Visible = false; return end
    local viewH = UI.Content.AbsoluteSize.Y
    local canvasH = UI.Content.CanvasSize.Y.Offset
    if canvasH <= viewH or canvasH == 0 or viewH == 0 then
        UI.ScrollBarTrack.Visible = false; return
    end
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
UI.ScrollBarTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        local startY = input.Position.Y
        local startCanvasY = UI.Content.CanvasPosition.Y
        Tween(UI.ScrollBarThumb, { BackgroundColor3 = Theme.AccentHover }, 0.12)
        SetInteraction({
            onMove = function(inp)
                local maxScroll = math.max(0, UI.Content.CanvasSize.Y.Offset - UI.Content.AbsoluteSize.Y)
                if maxScroll == 0 then return end
                local scrollPerPixel = maxScroll / math.max(1,
                    UI.ScrollBarTrack.AbsoluteSize.Y - UI.ScrollBarThumb.AbsoluteSize.Y)
                UI.Content.CanvasPosition = Vector2.new(0, math.clamp(
                    startCanvasY + (inp.Position.Y - startY) * scrollPerPixel, 0, maxScroll))
            end,
            onEnd = function() Tween(UI.ScrollBarThumb, { BackgroundColor3 = Theme.Accent }, 0.12) end,
        })
    end
end)
local ActiveTab = nil
local function UpdateContentScroll()
    if not ActiveTab or not ActiveTab.Page then return end
    local pageY = ActiveTab.Page.AbsoluteSize.Y
    local frameY = UI.Content.AbsoluteSize.Y
    if pageY < 1 then task.delay(0.05, UpdateContentScroll); return end
    UI.Content.CanvasSize = UDim2.new(0, 0, 0, pageY + 4)
    if pageY <= frameY + 2 then
        UI.Content.ScrollingEnabled = false
        if UI.Content.CanvasPosition.Y ~= 0 then UI.Content.CanvasPosition = Vector2.new(0, 0) end
    else
        UI.Content.ScrollingEnabled = true
    end
    UpdateScrollBar()
end

-- ================= CARDS =================
local function CreateCardText(card, title, desc, x, titleY, descY, rightMargin)
    MakeLabel(card, {
        Size=UDim2.new(1, -rightMargin, 0, 17), Position=UDim2.new(0, x, 0, titleY),
        Text=title, TextSize=13, Font=Enum.Font.GothamBold,
    })
    MakeLabel(card, {
        Size=UDim2.new(1, -rightMargin, 0, 14), Position=UDim2.new(0, x, 0, descY),
        Text=desc, TextColor3=Theme.TextDim, TextSize=11, Font=Enum.Font.Gotham,
        TextTruncate=Enum.TextTruncate.AtEnd,
    })
end
local function CreateCardShell(parent, opts)
    opts = opts or {}
    local card = MakeFrame(parent, {
        Name=opts.name or "Card",
        Size=UDim2.new(1, 0, 0, opts.height or 70),
        BackgroundColor3=Theme.SurfaceBase, BackgroundTransparency=0,
    })
    local stroke = StyleCard(card, { radius = opts.radius or 12, hoverScale = opts.hoverScale or 1.005 })
    if opts.padding then Pad(card, opts.padding[1], opts.padding[2], opts.padding[3], opts.padding[4]) end
    return card, stroke
end
local function CreateToggleCard(parent, title, desc, default, iconData, cb)
    local card, stroke = CreateCardShell(parent, { height = 64, hoverScale = 1.005 })
    local _, iconStroke = MakeIconBadge(card, 32, UDim2.new(0, 14, 0.5, -16), iconData)
    local textX = iconData and 56 or 16
    local textRight = iconData and 118 or 78
    CreateCardText(card, title, desc, textX, 10, 30, textRight)
    local setToggle = MakeSwitch(card, default, function(v)
        Tween(stroke, { Color = v and Theme.Accent or Theme.Border, Transparency = v and 0.5 or 0.8 }, 0.22)
        if iconStroke then
            Tween(iconStroke, { Color = v and Theme.Accent or Theme.Border, Transparency = v and 0.4 or 0.6 }, 0.22)
        end
        cb(v)
    end)
    ToggleRefs[title] = setToggle
end
local function CreateSliderCard(parent, title, desc, min, max, default, iconData, cb, decimals)
    local card, stroke = CreateCardShell(parent, {
        height = 84, padding = {12, 16, 12, 16}, hoverScale = 1.005,
    })
    MakeIconBadge(card, 32, UDim2.new(0, 0, 0, 0), iconData)
    local textX = iconData and 44 or 0
    local textRight = iconData and 110 or 70
    CreateCardText(card, title, desc, textX, 0, 18, textRight)
    local updateUI = MakeSlider(card, min, max, default, cb, {
        decimals = decimals or 0,
        snaps = SLIDER_SNAPS[title] or {},
        onDragStart = function() Tween(stroke, { Color = Theme.Accent, Transparency = 0.4 }, 0.15) end,
        onDragEnd   = function() Tween(stroke, { Color = Theme.Border, Transparency = 0.8 }, 0.15) end,
    })
    SliderRefs[title] = updateUI
end
local function CreateButtonCard(parent, title, desc, cb)
    local card = New("TextButton", {
        Size=UDim2.new(1, 0, 0, 56),
        BackgroundColor3=Theme.Accent, BackgroundTransparency=0,
        BorderSizePixel=0, Text="", AutoButtonColor=false, Parent=parent,
    })
    Corner(card, 12); Gradient(card, { Theme.Accent, Theme.AccentDark }, 45)
    local stroke = Stroke(card, Theme.AccentSoft, 1, 0.5)
    AddShadow(card, { color=Theme.Accent, transparency=0.6, blur=20, offset=Vector2.new(0, 6) })
    ApplyHover(card, { scale=1.02, stroke=stroke, hoverStrokeColor=Theme.AccentSoft, hoverStrokeTransp=0.1 })
    ApplyPress(card, { pressScale=0.98, hoverScale=1.02 })
    MakeLabel(card, {
        Size=UDim2.new(1, 0, 0, 18), Position=UDim2.new(0, 0, 0, 8),
        Text=title, TextColor3=Theme.BgDarkest, TextSize=13,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center,
    })
    MakeLabel(card, {
        Size=UDim2.new(1, -24, 0, 16), Position=UDim2.new(0, 12, 0, 28),
        Text=desc, TextColor3=Theme.BgDarkest, TextTransparency=0.2, TextSize=10,
        Font=Enum.Font.Gotham, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center,
    })
    card.MouseButton1Click:Connect(cb)
end
local function CreateHotkeyCard(parent, title, actionId, defaultKey)
    local card = CreateCardShell(parent, { height = 46, padding = {10, 16, 10, 16}, hoverScale = 1.005 })
    MakeLabel(card, { Size=UDim2.new(1, -85, 1, 0), Text=title, TextSize=12, Font=Enum.Font.GothamBold })
    MakeKeycap(card, defaultKey, actionId)
end
local function CreateSection(parent, text)
    local holder = MakeFrame(parent, {
        Name="SectionHolder", Size=UDim2.new(1, 0, 0, 24), BackgroundTransparency=1,
    })
    local bar = MakeFrame(holder, {
        Size=UDim2.new(0, 3, 0, 12), Position=UDim2.new(0, 4, 0.5, -6),
        BackgroundColor3=Theme.Accent,
    }); Corner(bar, 1.5)
    MakeLabel(holder, {
        Size=UDim2.new(1, -20, 1, 0), Position=UDim2.new(0, 14, 0, 0),
        Text=string.upper(text), TextColor3=Theme.TextMuted, TextSize=9,
        Font=Enum.Font.GothamBold,
    })
end

-- ================= TABS =================
local Tabs = {}
local SwitchTab
local function CreateTab(label, name, icon, width)
    local idx = #Tabs + 1
    local btn = New("TextButton", {
        Size = UDim2.new(0, width or 82, 0, 36),
        BackgroundColor3 = Theme.SurfaceBase,
        BackgroundTransparency = 1,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        LayoutOrder = idx, Parent = UI.TabContainer, ZIndex = 2,
    })
    Corner(btn, 8)
    local bg = MakeFrame(btn, {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.AccentDark,
        BackgroundTransparency = 1, ZIndex = 1,
    })
    Corner(bg, 8)
    local inner = MakeFrame(btn, {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, ZIndex = 2,
    })
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = inner,
    })
    local iconLabel = MakeLabel(inner, {
        Size = UDim2.new(0, 20, 0, 20),
        Text = icon, TextColor3 = Theme.TextMuted, TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        LayoutOrder = 1, ZIndex = 3,
    })
    local lbl = MakeLabel(inner, {
        Size = UDim2.new(0, 0, 0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = string.upper(label), TextColor3 = Theme.TextDim,
        TextSize = 11, Font = Enum.Font.GothamBold,
        LayoutOrder = 2, ZIndex = 3,
    })
    local page = MakeFrame(UI.Content, {
        Name=name .. "Page", Size=UDim2.new(1, 0, 0, 0),
        BackgroundTransparency=1, Visible=false,
    })
    page.AutomaticSize = Enum.AutomaticSize.Y
    New("UIListLayout", {
        Padding=UDim.new(0, 8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=page,
    }); Pad(page, 0, 12, 8, 4)
    local tabData = {
        Button=btn, Page=page, Label=lbl, IconLabel=iconLabel,
        Bg=bg, Inner=inner, Name=name, Index=idx,
    }
    table.insert(Tabs, tabData)
    btn.MouseButton1Click:Connect(function() SwitchTab(idx) end)
    btn.MouseEnter:Connect(function()
        if ActiveTab ~= tabData then
            Tween(bg, { BackgroundTransparency = 0.85 }, 0.15)
            Tween(lbl, { TextColor3 = Theme.Text }, 0.15)
            Tween(iconLabel, { TextColor3 = Theme.Text }, 0.15)
        end
    end)
    btn.MouseLeave:Connect(function()
        if ActiveTab ~= tabData then
            Tween(bg, { BackgroundTransparency = 1 }, 0.15)
            Tween(lbl, { TextColor3 = Theme.TextDim }, 0.15)
            Tween(iconLabel, { TextColor3 = Theme.TextMuted }, 0.15)
        end
    end)
    return page
end
SwitchTab = function(idx)
    local tab = Tabs[idx]; if not tab or ActiveTab == tab then return end
    if ActiveTab then
        Tween(ActiveTab.Bg, { BackgroundTransparency = 1 }, 0.2)
        Tween(ActiveTab.Label, { TextColor3 = Theme.TextDim }, 0.2)
        Tween(ActiveTab.IconLabel, { TextColor3 = Theme.TextMuted }, 0.2)
        ActiveTab.Page.Visible = false
    end
    tab.Page.Visible = true
    Tween(tab.Bg, { BackgroundTransparency = 0.75 }, 0.2)
    Tween(tab.Label, { TextColor3 = Theme.Text }, 0.2)
    Tween(tab.IconLabel, { TextColor3 = Theme.Accent }, 0.2)
    local page = tab.Page
    local prevPos = page.Position
    page.Position = UDim2.new(prevPos.X.Scale, prevPos.X.Offset, prevPos.Y.Scale, prevPos.Y.Offset + 10)
    Tween(page, { Position = prevPos }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local uiscale = EnsureUIScale(page); uiscale.Scale = 0.98
    Tween(uiscale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    ActiveTab = tab
    task.delay(0.05, UpdateContentScroll)
    task.delay(0.35, UpdateContentScroll)
    if tab.Name == "Moves" and RefreshRecorderList then
        task.defer(function() RecorderState.Saved = RecLoadAll(); RefreshRecorderList() end)
    end
end

local PlayPage    = CreateTab("Play",   "Play",  "🏃", 82)
local TunePage    = CreateTab("Tune",   "Tune",  "⚙",  82)
local VisPage     = CreateTab("Visual", "Vis",   "✨", 96)
local ShaderPage  = CreateTab("Shaders","Shaders","🎨", 100)
local RecPage     = CreateTab("REC",    "Moves", "🎬", 78)
local HotkeysPage = CreateTab("Keys",   "Keys",  "⌨",  82)

-- === Play page ===
CreateSection(PlayPage, "Movement")
CreateToggleCard(PlayPage, "Auto BunnyHop", "Автоматический прыжок при удержании Space",
    State.BhopEnabled, "🐇", function(v) State.BhopEnabled = v; if not v then ResetBhopState() end end)
CreateToggleCard(PlayPage, "Jump Acceleration", "Увеличивает скорость при каждом прыжке",
    State.JumpAccelEnabled, "⚡", function(v) State.JumpAccelEnabled = v end)
CreateSection(PlayPage, "Boosts")
CreateToggleCard(PlayPage, "Slope Boost", "Ускорение при столкновении со склоном",
    State.SlopeBoostEnabled, "⛷", function(v) State.SlopeBoostEnabled = v end)
CreateToggleCard(PlayPage, "Landing Boost", "Добавляет скорость при мягком приземлении",
    State.LandingBoostEnabled, "🪂", function(v) State.LandingBoostEnabled = v end)
CreateSection(PlayPage, "Utility")
CreateButtonCard(PlayPage, "INSTANT REVIVE", "Мгновенное восстановление персонажа", TriggerSelfRevive)
CreateToggleCard(PlayPage, "Anti-AFK", "Предотвращает кик за неактивность",
    CFG.AntiAfkEnabled, "🛡", function(v) CFG.AntiAfkEnabled = v; SetAntiAfkEnabled(v) end)

-- === Tune page ===
CreateSection(TunePage, "Speed")
CreateSliderCard(TunePage, "Gain Percent", "Процент прибавки за прыжок", 1, 20,
    CFG.GainPercent, "⚡", function(v) CFG.GainPercent = v end)
CreateSliderCard(TunePage, "Max Speed", "Максимальная скорость скриптового буста", 50, 250,
    CFG.MaxSpeed, "🚀", function(v) CFG.MaxSpeed = v end)
CreateSliderCard(TunePage, "Min Speed", "Минимальная скорость", 5, 50,
    CFG.MinSpeed, "🐢", function(v) CFG.MinSpeed = v end)
CreateSection(TunePage, "Adaptive Gain")
CreateToggleCard(TunePage, "Enable Adaptive Gain", "Масштабирует gain по текущей скорости",
    CFG.AdaptiveGainEnabled, "📈", function(v) CFG.AdaptiveGainEnabled = v end)
CreateSliderCard(TunePage, "Adaptive Min", "Множитель gain при Max Speed", 0.1, 1.0,
    CFG.AdaptiveGainMin, "🔽", function(v) CFG.AdaptiveGainMin = v end, 2)
CreateSliderCard(TunePage, "Adaptive Max", "Множитель gain при нулевой скорости", 1.0, 2.5,
    CFG.AdaptiveGainMax, "🔼", function(v) CFG.AdaptiveGainMax = v end, 2)
CreateSection(TunePage, "Control")
CreateSliderCard(TunePage, "Vertical Cap", "Лимит по оси Y", 40, 100,
    CFG.VertCap, "📈", function(v) CFG.VertCap = v end)
CreateSliderCard(TunePage, "Max Turn Angle", "Угол сброса буста", 15, 180,
    CFG.MaxTurnAngle, "📐", function(v) CFG.MaxTurnAngle = v end)
CreateSliderCard(TunePage, "Brake Rate", "Скорость торможения (Shift)", 20, 200,
    CFG.BrakeRate, "🛑", function(v) CFG.BrakeRate = v end)
CreateSection(TunePage, "Fall & Landing")
CreateSliderCard(TunePage, "Fast Fall Force", "Сила падения (X)", 30, 300,
    CFG.FastFallForce, "⬇", function(v) CFG.FastFallForce = v end)
CreateSliderCard(TunePage, "Land Boost %", "Прибавка при посадке", 0, 20,
    CFG.LandingBoostPercent, "📊", function(v) CFG.LandingBoostPercent = v end)
CreateSliderCard(TunePage, "Land Soft VY", "Порог мягкой посадки", 10, 60,
    CFG.LandingSoftVY, "📉", function(v) CFG.LandingSoftVY = v end)

-- === Visual page ===
CreateSection(VisPage, "Effects")
CreateToggleCard(VisPage, "Landing Prediction", "Круговой таймер до приземления",
    State.LandPredEnabled, "🎯", function(v)
        State.LandPredEnabled = v
        if not v then
            PredState.FadeState = "hidden"; PredState.FadeProgress = 0
            PredState.IdleTime = 0; DestroyPred()
        end
    end)
CreateSection(VisPage, "Markers")
CreateToggleCard(VisPage, "Show Markers", "Отображает сохранённые маршруты в мире",
    State.MarkersEnabled, "📍", function(v) SetMarkersVisible(v) end)
CreateSliderCard(VisPage, "Marker Range", "Максимальная дистанция видимости маркеров", 20, 500,
    CFG.MarkerMaxDist, "📏", function(v) CFG.MarkerMaxDist = v end)
CreateSection(VisPage, "Interface")
CreateToggleCard(VisPage, "Status Window", "Монитор скорости, FPS и пинга",
    State.WatermarkEnabled, "📊", function(v) State.WatermarkEnabled = v; UI.WatermarkFrame.Visible = v end)
CreateToggleCard(VisPage, "Recorder Status", "Movement recorder monitor window",
    State.RecorderStatusEnabled, "🎬", function(v) State.RecorderStatusEnabled = v; UI.RecorderStatusFrame.Visible = v end)
CreateToggleCard(VisPage, "Compact Mode", "Компактные инфо-окна",
    CFG.CompactMode, "🗜", function(v) ApplyCompactMode(v) end)

-- === Shaders page ===
CreateSection(ShaderPage, "Lighting")
CreateToggleCard(ShaderPage, "Lighting Boost", "Улучшает освещение в игре",
    State.LightingBoostEnabled, "💡", function(v)
        State.LightingBoostEnabled = v
        if v then ApplyLighting() else RestoreLighting() end
    end)
CreateSliderCard(ShaderPage, "Brightness", "Яркость", 1, 8,
    CFG.LightBrightness, "☀", function(v)
        CFG.LightBrightness = v
        if State.LightingBoostEnabled then pcall(function() Lighting.Brightness = v end) end
    end, 1)
CreateSliderCard(ShaderPage, "Ambient", "Фоновое освещение", 0, 255,
    CFG.LightAmbientVal, "🌤", function(v)
        CFG.LightAmbientVal = v
        if State.LightingBoostEnabled then
            local c = Color3.fromRGB(v, v, v)
            pcall(function() Lighting.Ambient = c; Lighting.OutdoorAmbient = c end)
        end
    end)
CreateSliderCard(ShaderPage, "Exposure", "Экспозиция камеры", -1, 2,
    CFG.LightExposure, "👁", function(v)
        CFG.LightExposure = v
        if State.LightingBoostEnabled then pcall(function() Lighting.ExposureCompensation = v end) end
    end, 2)

CreateSection(ShaderPage, "Bloom")
CreateToggleCard(ShaderPage, "Bloom", "Свечение от ярких поверхностей",
    CFG.BloomEnabled, "🌟", function(v) CFG.BloomEnabled = v; Shaders.ApplyBloom() end)
CreateSliderCard(ShaderPage, "Bloom Intensity", "Сила свечения", 0.1, 2.0,
    CFG.BloomIntensity, "✦", function(v)
        CFG.BloomIntensity = v
        if CFG.BloomEnabled and Shaders.PostEffects.Bloom then
            Shaders.PostEffects.Bloom.Intensity = v
        end
    end, 2)
CreateSliderCard(ShaderPage, "Bloom Size", "Радиус размытия", 4, 64,
    CFG.BloomSize, "◯", function(v)
        CFG.BloomSize = v
        if CFG.BloomEnabled and Shaders.PostEffects.Bloom then
            Shaders.PostEffects.Bloom.Size = v
        end
    end, 0)
CreateSliderCard(ShaderPage, "Bloom Threshold", "Порог яркости", 0.5, 2.0,
    CFG.BloomThreshold, "▽", function(v)
        CFG.BloomThreshold = v
        if CFG.BloomEnabled and Shaders.PostEffects.Bloom then
            Shaders.PostEffects.Bloom.Threshold = v
        end
    end, 2)

CreateSection(ShaderPage, "Color Correction")
CreateToggleCard(ShaderPage, "Color Correction", "Коррекция цвета и насыщенности",
    CFG.ColorCorrectionEnabled, "🎨", function(v)
        CFG.ColorCorrectionEnabled = v; Shaders.ApplyColorCorrection()
    end)
CreateSliderCard(ShaderPage, "CC Brightness", "Яркость цвета", -0.5, 0.5,
    CFG.CC_Brightness, "☀", function(v)
        CFG.CC_Brightness = v
        if CFG.ColorCorrectionEnabled and Shaders.PostEffects.ColorCorrection then
            Shaders.PostEffects.ColorCorrection.Brightness = v
        end
    end, 2)
CreateSliderCard(ShaderPage, "CC Contrast", "Контраст", -0.5, 0.5,
    CFG.CC_Contrast, "◐", function(v)
        CFG.CC_Contrast = v
        if CFG.ColorCorrectionEnabled and Shaders.PostEffects.ColorCorrection then
            Shaders.PostEffects.ColorCorrection.Contrast = v
        end
    end, 2)
CreateSliderCard(ShaderPage, "CC Saturation", "Насыщенность", -1.0, 1.0,
    CFG.CC_Saturation, "◈", function(v)
        CFG.CC_Saturation = v
        if CFG.ColorCorrectionEnabled and Shaders.PostEffects.ColorCorrection then
            Shaders.PostEffects.ColorCorrection.Saturation = v
        end
    end, 2)

CreateSection(ShaderPage, "Fog")
CreateToggleCard(ShaderPage, "Fog", "Туман в мире",
    CFG.FogEnabled, "🌫", function(v) CFG.FogEnabled = v; Shaders.ApplyFog() end)
CreateSliderCard(ShaderPage, "Fog Start", "Начало тумана (studs)", 5, 500,
    CFG.FogStart, "▶", function(v)
        CFG.FogStart = v
        if CFG.FogEnabled then pcall(function() Lighting.FogStart = v end) end
    end, 0)
CreateSliderCard(ShaderPage, "Fog End", "Конец тумана (studs)", 100, 5000,
    CFG.FogEnd, "◀", function(v)
        CFG.FogEnd = v
        if CFG.FogEnabled then pcall(function() Lighting.FogEnd = v end) end
    end, 0)

CreateSection(ShaderPage, "Atmosphere")
CreateToggleCard(ShaderPage, "Atmosphere", "Атмосферная дымка",
    CFG.AtmosphereEnabled, "🌁", function(v) CFG.AtmosphereEnabled = v; Shaders.ApplyAtmosphere() end)
CreateSliderCard(ShaderPage, "Atmos Density", "Плотность атмосферы", 0, 1.0,
    CFG.AtmosDensity, "◆", function(v)
        CFG.AtmosDensity = v
        if CFG.AtmosphereEnabled and Shaders.PostEffects.Atmosphere then
            Shaders.PostEffects.Atmosphere.Density = v
        end
    end, 2)
CreateSliderCard(ShaderPage, "Atmos Haze", "Дымка", 0, 5,
    CFG.AtmosHaze, "▽", function(v)
        CFG.AtmosHaze = v
        if CFG.AtmosphereEnabled and Shaders.PostEffects.Atmosphere then
            Shaders.PostEffects.Atmosphere.Haze = v
        end
    end, 1)

CreateSection(ShaderPage, "Extra")
CreateToggleCard(ShaderPage, "Sun Rays", "Лучи от солнца",
    CFG.SunRaysEnabled, "🌅", function(v) CFG.SunRaysEnabled = v; Shaders.ApplySunRays() end)
CreateToggleCard(ShaderPage, "Depth of Field", "Размытие фона",
    CFG.DOFEnabled, "🔍", function(v) CFG.DOFEnabled = v; Shaders.ApplyDepthOfField() end)

CreateSection(ShaderPage, "Weather")
CreateToggleCard(ShaderPage, "Snow", "Снег вокруг игрока",
    CFG.WeatherSnow, "❄", function(v)
        if SuppressWeatherToggle then return end
        CFG.WeatherSnow = v
        if v then
            SuppressWeatherToggle = true
            CFG.WeatherRain = false; CFG.WeatherSakura = false
            if ToggleRefs["Rain"] then ToggleRefs["Rain"](false) end
            if ToggleRefs["Sakura"] then ToggleRefs["Sakura"](false) end
            SuppressWeatherToggle = false
            Shaders.SetWeather("snow")
        elseif Shaders.GetActiveWeather() == "none" then Shaders.SetWeather("none") end
    end)
CreateToggleCard(ShaderPage, "Rain", "Дождь вокруг игрока",
    CFG.WeatherRain, "🌧", function(v)
        if SuppressWeatherToggle then return end
        CFG.WeatherRain = v
        if v then
            SuppressWeatherToggle = true
            CFG.WeatherSnow = false; CFG.WeatherSakura = false
            if ToggleRefs["Snow"] then ToggleRefs["Snow"](false) end
            if ToggleRefs["Sakura"] then ToggleRefs["Sakura"](false) end
            SuppressWeatherToggle = false
            Shaders.SetWeather("rain")
        elseif Shaders.GetActiveWeather() == "none" then Shaders.SetWeather("none") end
    end)
CreateToggleCard(ShaderPage, "Sakura", "Лепестки сакуры",
    CFG.WeatherSakura, "🌸", function(v)
        if SuppressWeatherToggle then return end
        CFG.WeatherSakura = v
        if v then
            SuppressWeatherToggle = true
            CFG.WeatherSnow = false; CFG.WeatherRain = false
            if ToggleRefs["Snow"] then ToggleRefs["Snow"](false) end
            if ToggleRefs["Rain"] then ToggleRefs["Rain"](false) end
            SuppressWeatherToggle = false
            Shaders.SetWeather("sakura")
        elseif Shaders.GetActiveWeather() == "none" then Shaders.SetWeather("none") end
    end)
CreateSliderCard(ShaderPage, "Weather Intensity", "Плотность частиц", 0.1, 2.0,
    CFG.WeatherIntensity, "✺", function(v)
        CFG.WeatherIntensity = v; Shaders.UpdateWeatherRate()
    end, 2)

-- === Hotkeys page ===
CreateSection(HotkeysPage, "Keybinds")
MakeLabel(HotkeysPage, {
    Size=UDim2.new(1, 0, 0, 22),
    Text="ЛКМ — назначить клавишу, ПКМ — сбросить",
    TextColor3=Theme.TextDim, TextSize=11, Font=Enum.Font.Gotham, TextWrapped=true,
})
for _, item in ipairs(HotkeysList) do CreateHotkeyCard(HotkeysPage, item.title, item.id, Hotkeys[item.id]) end

-- === REC page ===
CreateSection(RecPage, "Info")
UI.RecHelpLabel = MakeLabel(RecPage, {
    Size=UDim2.new(1, 0, 0, 34),
    Text=string.format("%s: record · %s: play nearby",
        (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—",
        (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—"),
    TextColor3=Theme.TextDim, TextSize=11, Font=Enum.Font.Gotham, TextWrapped=true,
})
CreateSection(RecPage, "Playback")
CreateSliderCard(RecPage, "Playback Speed", "Скорость воспроизведения", 0.5, 3.0,
    CFG.PlaybackSpeed, "⏩", function(v) CFG.PlaybackSpeed = v; SetPlaybackSpeed(v) end, 2)
CreateSection(RecPage, "Trim")
CreateToggleCard(RecPage, "Trim Start", "Обрезать статичное начало",
    CFG.TrimStartOnStop, "✂", function(v) CFG.TrimStartOnStop = v end)
CreateToggleCard(RecPage, "Trim End", "Обрезать статичный конец",
    CFG.TrimEndOnStop, "✂", function(v) CFG.TrimEndOnStop = v end)
CreateSliderCard(RecPage, "Trim Threshold", "Порог движения в studs", 0.2, 5.0,
    CFG.TrimThreshold, "📐", function(v) CFG.TrimThreshold = v end, 2)
CreateSection(RecPage, "Status")
local statusCard = CreateCardShell(RecPage, { height = 58, padding = {14, 16, 14, 16} })
UI.RecStatusLabel = MakeLabel(statusCard, {
    Size=UDim2.new(1, 0, 0, 16), Text="Idle", TextColor3=Theme.TextMuted,
    TextSize=12, Font=Enum.Font.GothamBold,
})
MakeLabel(statusCard, {
    Size=UDim2.new(1, 0, 0, 12), Position=UDim2.new(0, 0, 0, 20),
    Text="Captures pos & vel at 30 Hz", TextColor3=Theme.TextMuted,
    TextSize=9, Font=Enum.Font.Gotham,
})
CreateSection(RecPage, "Save")
UI.RecNameBox = New("TextBox", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = Theme.BgDarkest, BackgroundTransparency = 0.4,
    BorderSizePixel = 0, Text = "", PlaceholderText = "Recording name...",
    PlaceholderColor3 = Theme.TextMuted, TextColor3 = Theme.TextMuted,
    TextSize = 12, Font = Enum.Font.Gotham, TextEditable = false,
    ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = RecPage,
})
Corner(UI.RecNameBox, 8); Stroke(UI.RecNameBox, Theme.Border, 1, 0.6)
Pad(UI.RecNameBox, 0, 12, 0, 12)
local btnRow = MakeFrame(RecPage, { Size=UDim2.new(1, 0, 0, 40), BackgroundTransparency=1 })
New("UIListLayout", {
    FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0, 8),
    SortOrder=Enum.SortOrder.LayoutOrder, Parent=btnRow,
})
UI.RecSaveBtn = New("TextButton", {
    Size=UDim2.new(0.5, -4, 1, 0), BackgroundColor3=Theme.Accent,
    BackgroundTransparency=0.75, BorderSizePixel=0, Text="",
    AutoButtonColor=false, LayoutOrder=1, Parent=btnRow,
})
Corner(UI.RecSaveBtn, 8); Gradient(UI.RecSaveBtn, { Theme.Accent, Theme.AccentDark }, 45)
Stroke(UI.RecSaveBtn, Theme.AccentSoft, 1, 0.4)
UI.RecSaveLbl = MakeLabel(UI.RecSaveBtn, {
    Text="SAVE", TextColor3=Theme.TextMuted, TextSize=11,
    Font=Enum.Font.GothamBold, TextTransparency=0.4,
    TextXAlignment=Enum.TextXAlignment.Center,
})
UI.RecCancelBtn = New("TextButton", {
    Size=UDim2.new(0.5, -4, 1, 0), BackgroundColor3=Theme.SurfaceBase,
    BackgroundTransparency=0.75, BorderSizePixel=0, Text="",
    AutoButtonColor=false, LayoutOrder=2, Parent=btnRow,
})
Corner(UI.RecCancelBtn, 8); Stroke(UI.RecCancelBtn, Theme.Border, 1, 0.7)
UI.RecCancelLbl = MakeLabel(UI.RecCancelBtn, {
    Text="CANCEL", TextColor3=Theme.TextMuted, TextSize=11,
    Font=Enum.Font.GothamBold, TextTransparency=0.4,
    TextXAlignment=Enum.TextXAlignment.Center,
})
local saveBtnStroke = UI.RecSaveBtn:FindFirstChildOfClass("UIStroke")
ApplyHover(UI.RecSaveBtn, { scale=1.02, stroke=saveBtnStroke, hoverStrokeColor=Theme.AccentSoft, hoverStrokeTransp=0.1 })
ApplyPress(UI.RecSaveBtn, { pressScale=0.97, hoverScale=1.02 })
local cancelBtnStroke = UI.RecCancelBtn:FindFirstChildOfClass("UIStroke")
ApplyHover(UI.RecCancelBtn, { scale=1.02, stroke=cancelBtnStroke, hoverStrokeColor=Theme.Accent, hoverStrokeTransp=0.4 })
ApplyPress(UI.RecCancelBtn, { pressScale=0.97, hoverScale=1.02 })
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
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = "Saved: " .. name
            UI.RecStatusLabel.TextColor3 = Theme.Success
        end
        RecorderState.Saved = RecLoadAll()
        if RefreshMarkers then RefreshMarkers() end
        if RefreshRecorderList then RefreshRecorderList() end
    else
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = "Save failed"
            UI.RecStatusLabel.TextColor3 = Theme.Danger
        end
    end
end)
UI.RecCancelBtn.MouseButton1Click:Connect(function()
    if not RecorderState.InputEnabled then return end
    RecorderState.Cache = nil; DestroyUnsavedMarker()
    UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
    RecSetInputEnabled(false)
    if UI.RecStatusLabel then
        UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = Theme.TextMuted
    end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
end)
CreateSection(RecPage, "Recordings")
UI.RecListContainer = MakeFrame(RecPage, { Size=UDim2.new(1, 0, 0, 0), BackgroundTransparency=1 })
UI.RecListContainer.AutomaticSize = Enum.AutomaticSize.Y
New("UIListLayout", {
    Padding=UDim.new(0, 8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=UI.RecListContainer,
})
RecSetInputEnabled(false)
local function CreateRecordingCard(parent, rec)
    local card = MakeFrame(parent, { Size=UDim2.new(1, 0, 0, 64), BackgroundTransparency=0, Active=true })
    StyleCard(card, { radius = 10 }); Pad(card, 10, 14, 10, 14)
    local iconBox = MakeFrame(card, {
        Size=UDim2.new(0, 34, 0, 34), Position=UDim2.new(0, 0, 0.5, -17),
        BackgroundColor3=Theme.SurfaceLight, BackgroundTransparency=0.2,
    })
    Corner(iconBox, 8); Stroke(iconBox, Theme.Border, 1, 0.6)
    Gradient(iconBox, { Theme.SurfaceHover, Theme.SurfaceBase }, 45)
    MakeLabel(iconBox, {
        Text="🎬", TextColor3=Theme.TextDim, TextSize=15,
        TextXAlignment=Enum.TextXAlignment.Center, TextYAlignment=Enum.TextYAlignment.Center,
    })
    MakeLabel(card, {
        Size=UDim2.new(1, -130, 0, 16), Position=UDim2.new(0, 42, 0, 4),
        Text=rec.name, TextSize=12, Font=Enum.Font.GothamBold,
        TextTruncate=Enum.TextTruncate.AtEnd,
    })
    MakeLabel(card, {
        Size=UDim2.new(1, -130, 0, 12), Position=UDim2.new(0, 42, 0, 22),
        Text=string.format("%.1fs · %d frames", rec.duration, rec.frameCount),
        TextColor3=Theme.TextDim, TextSize=9, Font=Enum.Font.Code,
        TextTruncate=Enum.TextTruncate.AtEnd,
    })
    local metaStr = rec.mapName or ""
    if rec.createdAt then
        local ok, dateStr = pcall(function() return os.date("%d.%m.%Y", rec.createdAt) end)
        if ok and dateStr then
            metaStr = (metaStr ~= "" and (metaStr .. " · " .. dateStr)) or dateStr
        end
    end
    if metaStr ~= "" then
        MakeLabel(card, {
            Size=UDim2.new(1, -130, 0, 10), Position=UDim2.new(0, 42, 0, 38),
            Text=metaStr, TextColor3=Theme.TextMuted, TextSize=8, Font=Enum.Font.Gotham,
            TextTruncate=Enum.TextTruncate.AtEnd,
        })
    end
    local playBtn = New("TextButton", {
        Size=UDim2.new(0, 30, 0, 30), Position=UDim2.new(1, -70, 0.5, -15),
        BackgroundColor3=Theme.Accent, BackgroundTransparency=0.4,
        BorderSizePixel=0, Text="", AutoButtonColor=false, Parent=card,
    })
    Corner(playBtn, 8); local playStroke = Stroke(playBtn, Theme.Accent, 1, 0.4)
    MakeLabel(playBtn, { Text="▶", TextColor3=Theme.BgDarkest, TextSize=13,
        TextXAlignment=Enum.TextXAlignment.Center })
    ApplyHover(playBtn, { scale=1.1, stroke=playStroke, hoverStrokeColor=Theme.AccentSoft, hoverStrokeTransp=0.1 })
    ApplyPress(playBtn, { pressScale=0.92, hoverScale=1.1 })
    playBtn.MouseButton1Click:Connect(function()
        if RecorderState.IsRecording then
            if UI.RecStatusLabel then
                UI.RecStatusLabel.Text = "Сначала остановите запись"
                UI.RecStatusLabel.TextColor3 = Theme.Warning
            end
            return
        end
        local _, decoded = RecReadFirstFrame(rec.path)
        if decoded then StartPlayback(rec.name, decoded.frames, decoded.duration) end
    end)
    local delBtn = New("TextButton", {
        Size=UDim2.new(0, 30, 0, 30), Position=UDim2.new(1, -32, 0.5, -15),
        BackgroundColor3=Theme.SurfaceLight, BackgroundTransparency=0.2,
        BorderSizePixel=0, Text="", AutoButtonColor=false, Parent=card,
    })
    Corner(delBtn, 8); local delStroke = Stroke(delBtn, Theme.Border, 1, 0.6)
    MakeLabel(delBtn, { Text="🗑", TextColor3=Theme.TextDim, TextSize=13,
        TextXAlignment=Enum.TextXAlignment.Center })
    ApplyHover(delBtn, { scale=1.1, stroke=delStroke, hoverStrokeColor=Theme.Danger, hoverStrokeTransp=0.3 })
    ApplyPress(delBtn, { pressScale=0.92, hoverScale=1.1 })
    delBtn.MouseButton1Click:Connect(function()
        if RecorderState.IsRecording then
            if UI.RecStatusLabel then
                UI.RecStatusLabel.Text = "Сначала остановите запись"
                UI.RecStatusLabel.TextColor3 = Theme.Warning
            end
            return
        end
        RecDeleteFile(rec.path); DestroyMarker(rec.name)
        task.defer(function() RecorderState.Saved = RecLoadAll(); RefreshRecorderList() end)
    end)
end
RefreshRecorderList = function()
    if not UI.RecListContainer then return end
    for _, child in ipairs(UI.RecListContainer:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    if #RecorderState.Saved == 0 then
        local emptyCard = MakeFrame(UI.RecListContainer, {
            Size=UDim2.new(1, 0, 0, 44), BackgroundTransparency=0.4,
        })
        Corner(emptyCard, 10); Stroke(emptyCard, Theme.Border, 1, 0.8)
        MakeLabel(emptyCard, {
            Text="No recordings yet", TextColor3=Theme.TextMuted,
            TextSize=11, Font=Enum.Font.Gotham,
            TextXAlignment=Enum.TextXAlignment.Center,
        })
    else
        for _, rec in ipairs(RecorderState.Saved) do CreateRecordingCard(UI.RecListContainer, rec) end
    end
    if State.MarkersEnabled then RefreshMarkers() end
    task.delay(0.05, UpdateContentScroll)
end
if Tabs[1] then
    Tabs[1].Page.Visible = true
    Tabs[1].Label.TextColor3 = Theme.Text
    Tabs[1].IconLabel.TextColor3 = Theme.Accent
    Tabs[1].Bg.BackgroundTransparency = 0.75
    ActiveTab = Tabs[1]
end
task.defer(function()
    RecorderState.Saved = RecLoadAll()
    if RefreshRecorderList then RefreshRecorderList() end
end)
MakeDraggable(UI.MainFrame, UI.Header,
    function(input)
        return not (input.Position.X - UI.Header.AbsolutePosition.X >= UI.Header.AbsoluteSize.X - 70)
    end,
    function() if SaveConfig then SaveConfig() end end)

-- ================= SAVE / LOAD =================
local ToggleMap = {
    BhopEnabled="Auto BunnyHop", JumpAccelEnabled="Jump Acceleration",
    SlopeBoostEnabled="Slope Boost", LandingBoostEnabled="Landing Boost",
    LandPredEnabled="Landing Prediction", LightingBoostEnabled="Lighting Boost",
    WatermarkEnabled="Status Window", MarkersEnabled="Show Markers",
    RecorderStatusEnabled="Recorder Status",
    AdaptiveGainEnabled="Enable Adaptive Gain",
    TrimStartOnStop="Trim Start", TrimEndOnStop="Trim End",
    CompactMode="Compact Mode", AntiAfkEnabled="Anti-AFK",
    BloomEnabled="Bloom", ColorCorrectionEnabled="Color Correction",
    FogEnabled="Fog", AtmosphereEnabled="Atmosphere",
    SunRaysEnabled="Sun Rays", DOFEnabled="Depth of Field",
    WeatherSnow="Snow", WeatherRain="Rain", WeatherSakura="Sakura",
}
local SliderMap = {
    GainPercent="Gain Percent", MaxSpeed="Max Speed", VertCap="Vertical Cap",
    MaxTurnAngle="Max Turn Angle", BrakeRate="Brake Rate", MinSpeed="Min Speed",
    FastFallForce="Fast Fall Force", LandingBoostPercent="Land Boost %",
    LandingSoftVY="Land Soft VY", LightBrightness="Brightness",
    LightAmbientVal="Ambient", LightExposure="Exposure", MarkerMaxDist="Marker Range",
    AdaptiveGainMin="Adaptive Min", AdaptiveGainMax="Adaptive Max",
    PlaybackSpeed="Playback Speed", TrimThreshold="Trim Threshold",
    BloomIntensity="Bloom Intensity", BloomSize="Bloom Size", BloomThreshold="Bloom Threshold",
    CC_Brightness="CC Brightness", CC_Contrast="CC Contrast", CC_Saturation="CC Saturation",
    FogStart="Fog Start", FogEnd="Fog End",
    AtmosDensity="Atmos Density", AtmosHaze="Atmos Haze",
    WeatherIntensity="Weather Intensity",
}
local function UDim2ToTable(u)
    return { XScale=u.X.Scale, XOffset=u.X.Offset, YScale=u.Y.Scale, YOffset=u.Y.Offset }
end
local function TableToUDim2(t)
    if type(t) ~= "table" then return nil end
    return UDim2.new(tonumber(t.XScale) or 0, tonumber(t.XOffset) or 0,
                     tonumber(t.YScale) or 0, tonumber(t.YOffset) or 0)
end
local function Log(msg) pcall(function() warn("[Noclipov] " .. tostring(msg)) end) end
local writeInFlight = false; local writeQueued = false
local configLoading = false
local function BuildSaveData()
    local data = {
        version=SCRIPT_VERSION, IsVisible=IsVisible,
        MainFramePos=UDim2ToTable(UI.MainFrame.Position),
        LauncherPos=UDim2ToTable(UI.LauncherIcon.Position),
        WatermarkPos=UDim2ToTable(UI.WatermarkFrame.Position),
        RecorderStatusPos=UDim2ToTable(UI.RecorderStatusFrame.Position),
        Hotkeys={}, Toggles={}, Sliders={},
    }
    for _, item in ipairs(HotkeysList) do
        data.Hotkeys[item.id] = Hotkeys[item.id] and Hotkeys[item.id].Name or "None"
    end
    for k, v in pairs(State) do if type(v) == "boolean" then data.Toggles[k] = v end end
    for k, v in pairs(CFG) do
        if type(v) == "boolean" then data.Toggles[k] = v
        elseif type(v) == "number" then data.Sliders[k] = v end
    end
    return data
end
local function DoSaveConfigNow()
    EnsureBaseFolders()
    local data = BuildSaveData()
    local encOk, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not encOk or type(encoded) ~= "string" then Log("SAVE FAIL: JSONEncode"); return false end
    local writeOk, writeErr = pcall(writefile, CONFIG_PATH, encoded)
    if not writeOk then Log("SAVE FAIL: " .. tostring(writeErr)); return false end
    return true
end
SaveConfig = function()
    if configLoading then return end
    writeQueued = true
    if writeInFlight then return end
    writeInFlight = true
    task.spawn(function()
        while writeQueued do writeQueued = false; pcall(DoSaveConfigNow) end
        writeInFlight = false
    end)
end
LoadConfig = function()
    EnsureBaseFolders()
    configLoading = true
    local content = nil; local source = "none"
    pcall(function()
        if isfile and isfile(CONFIG_PATH) then content = readfile(CONFIG_PATH); source = "isfile+readfile" end
    end)
    if not content or #tostring(content) == 0 then
        pcall(function() content = readfile(CONFIG_PATH); source = "direct readfile" end)
    end
    if not content or #tostring(content) == 0 then
        configLoading = false; Log("LOAD: no content"); return
    end
    local jsonOk, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not jsonOk or type(data) ~= "table" then
        configLoading = false; Log("LOAD FAIL: invalid JSON"); return
    end
    if data.IsVisible ~= nil then IsVisible = data.IsVisible == true end
    local p = TableToUDim2(data.MainFramePos); if p then UI.MainFrame.Position = p end
    p = TableToUDim2(data.LauncherPos); if p then UI.LauncherIcon.Position = p end
    p = TableToUDim2(data.WatermarkPos); if p then UI.WatermarkFrame.Position = p end
    p = TableToUDim2(data.RecorderStatusPos); if p then UI.RecorderStatusFrame.Position = p end
    if type(data.Hotkeys) == "table" then
        for id, keyName in pairs(data.Hotkeys) do
            if keyName == "None" then
                Hotkeys[id] = nil
                if HotkeyButtons[id] then
                    HotkeyButtons[id].Text = "None"; HotkeyButtons[id].TextColor3 = Theme.TextMuted
                end
            elseif type(keyName) == "string" and Enum.KeyCode[keyName] then
                Hotkeys[id] = Enum.KeyCode[keyName]
                if HotkeyButtons[id] then
                    HotkeyButtons[id].Text = keyName; HotkeyButtons[id].TextColor3 = Theme.Text
                end
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
    pcall(function() SetAntiAfkEnabled(CFG.AntiAfkEnabled == true) end)
    pcall(function() ApplyCompactMode(CFG.CompactMode == true) end)
    pcall(function() SetPlaybackSpeed(CFG.PlaybackSpeed or 1.0) end)
    pcall(Shaders.ApplyAll)
    configLoading = false
    Log("LOAD OK from " .. source)
end

-- ================= WINDOW CONTROLS =================
local function showWindow()
    IsVisible = true; UI.MainFrame.Visible = true
    local targetPos = UI.MainFrame.Position
    UI.MainFrame.Size = UDim2.new(0, WIN_W * 0.95, 0, WIN_H * 0.95)
    UI.MainFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset,
        targetPos.Y.Scale, targetPos.Y.Offset + 24)
    Tween(UI.MainFrame, {
        Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = targetPos,
    }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    task.delay(0.4, UpdateContentScroll)
    if SaveConfig then SaveConfig() end
end
local function hideWindow()
    IsVisible = false; UI.MainFrame.Visible = false
    if SaveConfig then SaveConfig() end
end
UI.LauncherIcon.MouseButton1Click:Connect(function()
    if os.clock() - launcherDragEndTime < 0.15 then return end
    if IsVisible then hideWindow() else showWindow() end
end)
local function ResetCharacterState()
    DestroyPred()
    PredState.FadeState = "hidden"; PredState.FadeProgress = 0
    PredState.IdleTime = 0; PredState.LastSuccess = 0
    StopPlayback()
end
TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
    ResetCharacterState()
    if RecorderState.IsRecording then
        RecorderState.IsRecording = false; RecorderState.Frames = {}
        RecorderState.FrameAccum = 0; RecorderState.Cache = nil
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = "Interrupted"; UI.RecStatusLabel.TextColor3 = Theme.Warning
        end
        RecSetInputEnabled(false)
        if RefreshMarkers then RefreshMarkers() end
    end
end))
TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
    ResetCharacterState()
    task.delay(0.5, SweepLegacyWorkspace)
    task.delay(1, function()
        RecorderState.Saved = RecLoadAll()
        if RefreshRecorderList then RefreshRecorderList() end
    end)
    task.defer(function()
        Shaders.SetWeather(Shaders.GetActiveWeather())
    end)
end))

-- ================= INPUT =================
TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if awaitingBind then
        local key = input.KeyCode
        if key ~= Enum.KeyCode.Unknown and key ~= Enum.KeyCode.Space then
            Hotkeys[awaitingBind] = key
            if HotkeyButtons[awaitingBind] then
                HotkeyButtons[awaitingBind].Text = key.Name
                HotkeyButtons[awaitingBind].TextColor3 = Theme.Text
                Tween(HotkeyButtons[awaitingBind], { BackgroundColor3 = Theme.SurfaceBase }, 0.15)
            end
            awaitingBind = nil
            if SaveConfig then SaveConfig() end
        end
        return
    end
    if UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local k = input.KeyCode
        local bindMap = {
            Bhop="Auto BunnyHop", Accel="Jump Acceleration",
            Slope="Slope Boost", Land="Landing Boost",
            Pred="Landing Prediction", Light="Lighting Boost",
        }
        for bindId, uiName in pairs(bindMap) do
            if Hotkeys[bindId] and k == Hotkeys[bindId] and ToggleRefs[uiName] then
                local stateKey = nil
                for sk, un in pairs(ToggleMap) do if un == uiName then stateKey = sk; break end end
                if stateKey then ToggleRefs[uiName](not State[stateKey]) end
                return
            end
        end
        if Hotkeys["Record"] and k == Hotkeys["Record"] then
            if RecorderState.IsRecording then RecStop(true) else RecStart() end
            return
        end
        if Hotkeys["Playback"] and k == Hotkeys["Playback"] then
            TryStartNearbyPlayback(); return
        end
        if Hotkeys["UI"] and k == Hotkeys["UI"] then
            if IsVisible then hideWindow() else showWindow() end
        end
    end
end))
TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = true end
end))
TrackConnection(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = false end
end))
TrackConnection(UserInputService.InputChanged:Connect(function(input)
    if not ActiveInteraction then return end
    if not (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then return end
    ActiveInteraction.onMove(input)
end))
TrackConnection(UserInputService.InputEnded:Connect(function(input)
    if not ActiveInteraction then return end
    if not (input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch) then return end
    local handler = ActiveInteraction.onEnd
    ActiveInteraction = nil
    handler()
end))

-- ================= LOOPS =================
TrackConnection(RunService.Stepped:Connect(function(_, dt)
    if PlaybackState.Active then return end
    if State.BhopEnabled then TryBhop(dt) end
    if State.SlopeBoostEnabled then TrySlopeBoost() end
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then ClampVelocity(hrp) end
    end
end))
local lastOrphanSweep      = 0
local lastUIUpdate         = 0
local lastTelemetryUpdate  = 0
local lastRecStatusUpdate  = 0
local lastRecHelpUpdate    = 0
local lastMarkerPulse      = 0
local fpsFrames, fpsAccum  = 0, 0
local cachedPing           = 0

TrackConnection(RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    if RecorderState.IsRecording then
        RecorderState.FrameAccum = RecorderState.FrameAccum + dt
        if RecorderState.FrameAccum >= RECORD_HZ then
            RecorderState.FrameAccum = RecorderState.FrameAccum - RECORD_HZ
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local t = os.clock() - RecorderState.StartTime
                local cf = hrp.CFrame; local v = hrp.AssemblyLinearVelocity
                table.insert(RecorderState.Frames, {
                    t=t, px=cf.X, py=cf.Y, pz=cf.Z,
                    vx=v.X, vy=v.Y, vz=v.Z,
                    lx=cf.LookVector.X, ly=cf.LookVector.Y, lz=cf.LookVector.Z,
                })
                if UI.RecStatusLabel then
                    UI.RecStatusLabel.Text = string.format("● REC  %.1fs · %d", t, #RecorderState.Frames)
                end
            end
        end
    end
    if PlaybackState.Active then UpdatePlayback() end
    if State.LandPredEnabled or PredState.FadeState ~= "hidden" or PredState.Data then
        local ok, err = pcall(UpdatePrediction, dt)
        if not ok and not PredState.__errLogged then
            PredState.__errLogged = true
            warn("[Noclipov] Prediction error: " .. tostring(err))
        end
    end
    if now - lastRecStatusUpdate > 0.05 then
        lastRecStatusUpdate = now
        UpdateRecorderStatus()
    end
    if now - lastRecHelpUpdate > 0.5 then
        lastRecHelpUpdate = now
        if UI.RecHelpLabel then
            local newText = string.format("%s: record · %s: play nearby",
                (Hotkeys["Record"] and Hotkeys["Record"].Name) or "—",
                (Hotkeys["Playback"] and Hotkeys["Playback"].Name) or "—")
            if UI.RecHelpLabel.Text ~= newText then UI.RecHelpLabel.Text = newText end
        end
    end
    if now - lastOrphanSweep > 3.0 then
        lastOrphanSweep = now
        SweepOrphanPredParts()
    end
    if now - lastUIUpdate > 0.05 then
        lastUIUpdate = now
        if UI.WatermarkFrame.Visible then
            fpsFrames = fpsFrames + 1; fpsAccum = fpsAccum + dt
            if now - lastTelemetryUpdate > 0.5 then
                lastTelemetryUpdate = now
                if fpsAccum > 0 then
                    UI.WmFpsVal.Text = tostring(math.floor(fpsFrames / fpsAccum + 0.5))
                end
                fpsFrames, fpsAccum = 0, 0
                pcall(function()
                    cachedPing = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                end)
                UI.WmPingVal.Text = tostring(cachedPing)
                UI.WmPingVal.TextColor3 = cachedPing < 80 and Theme.Success
                    or cachedPing < 150 and Theme.Warning or Theme.Danger
            end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local spd = Vector3.new(hrp.AssemblyLinearVelocity.X, 0,
                    hrp.AssemblyLinearVelocity.Z).Magnitude
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
                if st == "GAIN" then
                    local g = CFG.GainPercent
                    if CFG.AdaptiveGainEnabled and displaySpeed > 1 then
                        local norm = math.clamp(displaySpeed / math.max(CFG.MaxSpeed, 1), 0, 1)
                        g = g * (CFG.AdaptiveGainMax - norm * (CFG.AdaptiveGainMax - CFG.AdaptiveGainMin))
                    end
                    sText = string.format("+%.0f", g); sColor = Theme.Success
                elseif st == "BRAKE" then sText, sColor = "BRAKE", Theme.Danger
                elseif st == "AIR" then sText, sColor = "AIR", Theme.Accent
                elseif st == "NO CHAR" then sText, sColor = "N/A", Theme.Warning
                elseif st == "DISABLED" then sText, sColor = "OFF", Theme.TextMuted
                elseif st == "IDLE" then sText, sColor = "IDLE", Theme.TextMuted
                else sText, sColor = st or "—", Theme.TextMuted end
                UI.WmLiveLabel.Text = sText
                UI.WmLiveLabel.TextColor3 = sColor
                UI.WmLiveDot.BackgroundColor3 = sColor
                if PlaybackState.Active then
                    UI.WmSpeedBadge.Visible = true
                    UI.WmSpeedBadgeLbl.Text = string.format("×%.2f", PlaybackState.Speed or 1)
                    UI.WmSubSpeedLbl.Text = "SPEED · PLAYBACK"
                    UI.WmSubSpeedLbl.TextColor3 = Theme.Accent
                else
                    UI.WmSpeedBadge.Visible = false
                    UI.WmSubSpeedLbl.Text = "CURRENT SPEED"
                    UI.WmSubSpeedLbl.TextColor3 = Theme.TextMuted
                end
            else
                UI.WmSpeedVal.Text = "-"
                UI.WmLiveLabel.Text = "—"
                UI.WmLiveLabel.TextColor3 = Theme.TextMuted
                UI.WmLiveDot.BackgroundColor3 = Theme.TextMuted
                UI.WmSpeedBarFill.Size = UDim2.new(0, 0, 1, 0)
            end
            local isActive = (BhopState.CurrentStatus == "GAIN"
                or BhopState.CurrentStatus == "BRAKE"
                or BhopState.CurrentStatus == "AIR")
            UI.WmLivePill.BackgroundTransparency =
                isActive and (0.2 + math.sin(now * math.pi * 2.5) * 0.12) or 0.3
        end
        if logoGlow and logoGlow.Parent then
            logoGlow.BackgroundTransparency =
                0.75 + (0.5 + 0.5 * math.sin(now * math.pi * 1.4)) * 0.15
        end
    end
    if now - lastMarkerPulse > 0.033 then
        lastMarkerPulse = now
        if State.MarkersEnabled or UnsavedMarker or PlaybackState.StartMarker then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local hrpPos = hrp.Position
                local maxDist = CFG.MarkerMaxDist or 150
                local function updateVisualGroup(m)
                    if not m.startPos then return end
                    local dist = (hrpPos - m.startPos).Magnitude
                    local far = dist > maxDist
                    if far ~= m.isFar then
                        m.isFar = far
                        if m.ring then m.ring.Transparency = far and 1 or 0.55 end
                        if m.ringGlow then m.ringGlow.Enabled = not far end
                        if m.ringOuter then m.ringOuter.Transparency = far and 1 or 0.78 end
                        if m.crystal then m.crystal.Transparency = far and 1 or 0.25 end
                        if m.cap then m.cap.Transparency = far and 1 or 0.1 end
                        if m.glow then m.glow.Transparency = far and 1 or 0.85 end
                        if m.pillar then m.pillar.Enabled = not far end
                        if m.light then m.light.Enabled = not far end
                        if m.billboard then m.billboard.Enabled = not far end
                    end
                    if not far then
                        local phase = m.pulsePhase or 0
                        local nowSpin = now * 0.8 + phase
                        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2 + phase)
                        local bob = math.sin(now * 1.5 + phase) * 0.08
                        if m.root then m.root.Position = m.startPos end
                        if m.cap then
                            m.cap.CFrame = CFrame.new(m.startPos + Vector3.new(0, 2.55 + bob, 0))
                            m.cap.Transparency = 0.1 + pulse * 0.08
                        end
                        if m.crystal then
                            m.crystal.CFrame = CFrame.new(m.startPos + Vector3.new(0, 1.8 + bob * 0.6, 0))
                                * CFrame.Angles(0, nowSpin, 0)
                            m.crystal.Transparency = 0.25 + pulse * 0.1
                        end
                        if m.ring then
                            m.ring.CFrame = CFrame.new(m.startPos + Vector3.new(0, 0.03, 0))
                                * CFrame.Angles(0, -nowSpin * 0.6, math.rad(90))
                            m.ring.Transparency = 0.55 + pulse * 0.08
                        end
                        if m.ringOuter then
                            m.ringOuter.CFrame = CFrame.new(m.startPos + Vector3.new(0, 0.02, 0))
                                * CFrame.Angles(0, nowSpin * 1.2, math.rad(90))
                            m.ringOuter.Transparency = 0.78 + pulse * 0.05
                        end
                        if m.glow and m.cap then m.glow.Position = m.cap.Position end
                        if m.ringGlow then m.ringGlow.Brightness = 0.25 + pulse * 0.15 end
                        if m.light then m.light.Brightness = 0.5 + pulse * 0.3 end
                    end
                end
                for _, m in pairs(MarkerParts) do updateVisualGroup(m) end
                if UnsavedMarker then updateVisualGroup(UnsavedMarker) end
                if PlaybackState.StartMarker then updateVisualGroup(PlaybackState.StartMarker) end
            end
        end
    end
    -- shader module owns weather tracking
    pcall(Shaders.UpdatePosition)
end))

-- ================= MAP WATCH =================
local MapWatch = { LastMapName = GetMapName(), AttrConn = nil, ReloadDebounce = nil }
local function HandleMapChange()
    if MapWatch.ReloadDebounce then return end
    MapWatch.ReloadDebounce = true
    task.delay(0.2, function()
        MapWatch.ReloadDebounce = nil
        MapWatch.LastMapName = GetMapName()
        if RecorderState.IsRecording or RecorderState.Cache then
            RecorderState.IsRecording = false
            RecorderState.Frames = {}
            RecorderState.FrameAccum = 0
            RecorderState.Cache = nil
            RecSetInputEnabled(false)
            DestroyUnsavedMarker()
            if UI.RecNameBox then
                UI.RecNameBox.Text = ""
                UI.RecNameBox.PlaceholderText = "Recording name..."
            end
            if UI.RecStatusLabel then
                UI.RecStatusLabel.Text = "Interrupted (map changed)"
                UI.RecStatusLabel.TextColor3 = Theme.Warning
            end
        end
        if PlaybackState.Active then StopPlayback() end
        RecorderState.Saved = RecLoadAll()
        if RefreshRecorderList then RefreshRecorderList() end
        if State.MarkersEnabled then RefreshMarkers() end
    end)
end
local function BindMapAttribute(map)
    if MapWatch.AttrConn then
        pcall(function() MapWatch.AttrConn:Disconnect() end)
        MapWatch.AttrConn = nil
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
TrackConnection(workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then BindMapAttribute(child); HandleMapChange() end
end))
TrackConnection(workspace.ChildRemoved:Connect(function(child)
    if child.Name == "Map" then MapWatch.LastMapName = "Unknown"; HandleMapChange() end
end))
TryBindMapFromWorkspace()
task.spawn(function()
    local lastSafety = GetMapName()
    while UI.ScreenGui and UI.ScreenGui.Parent and not Disposer.disposed do
        task.wait(5)
        local now = GetMapName()
        if now ~= lastSafety then
            lastSafety = now
            if now ~= MapWatch.LastMapName then
                MapWatch.LastMapName = now; HandleMapChange()
            end
        end
        local map = workspace:FindFirstChild("Map")
        if map and not MapWatch.AttrConn then BindMapAttribute(map) end
    end
end)
task.spawn(function()
    while UI.ScreenGui and UI.ScreenGui.Parent and not Disposer.disposed do
        task.wait(0.3)
        if IsVisible and ActiveTab then UpdateContentScroll() end
    end
end)

-- ================= INIT =================
UI.MainFrame.Visible = false
LoadConfig()
if IsVisible then showWindow() else UI.MainFrame.Visible = false end
task.defer(function() SweepOrphanPredParts(true) end)

-- ================= CLEANUP =================
Cleanup = function()
    if Disposer.disposed then return end
    pcall(function() DoSaveConfigNow() end)
    for k in pairs(State) do
        if type(State[k]) == "boolean" then State[k] = false end
    end
    pcall(function() SetAntiAfkEnabled(false) end)
    pcall(function() if AntiAfk.conn then AntiAfk.conn:Disconnect(); AntiAfk.conn = nil end end)
    pcall(function() ResetBhopState() end)
    pcall(function() StopPlayback(true) end)
    pcall(function() ClearPlaybackPath() end)
    pcall(function() DestroyPlaybackStartMarker() end)
    pcall(function() DestroyUnsavedMarker() end)
    for name in pairs(MarkerParts) do pcall(function() DestroyMarker(name) end) end
    pcall(DestroyPred); pcall(RestoreLighting)
    pcall(Shaders.Cleanup)
    Disposer:dispose()
    if MapWatch.AttrConn then
        pcall(function() MapWatch.AttrConn:Disconnect() end); MapWatch.AttrConn = nil
    end
    if UI.ScreenGui then pcall(function() UI.ScreenGui:Destroy() end); UI.ScreenGui = nil end
    SweepLegacyWorkspace()
    if ENV[ENV_CLEANUP_KEY] == Cleanup then ENV[ENV_CLEANUP_KEY] = nil end
    if ENV[ENV_VERSION_KEY] == SCRIPT_VERSION then ENV[ENV_VERSION_KEY] = nil end
end
ENV[ENV_CLEANUP_KEY] = Cleanup