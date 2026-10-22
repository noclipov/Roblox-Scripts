repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334] = true, [10662098230] = true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!")
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

local CFG = {
    GainPercent         = 8,
    MaxSpeed            = 120,
    VertCap             = 55,
    SoftRate            = 120,
    BrakeRate           = 60,
    FastFallForce       = 90,
    MinSpeed            = 15,
    LandingBoostPercent = 5,
    LandingSoftVY       = 30,
    AbsCap              = 200,
}

local Connections = {}
local State = {
    BhopEnabled         = false,
    IsHoldingJump       = false,
    SlopeBoostEnabled   = false,
    LandPredEnabled     = false,
    LandingBoostEnabled = false,
    SnapRequested       = false,
}

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
        local existing = parent and parent:FindFirstChild("ZettaPulseSuiteUI")
        if existing then pcall(function() existing:Destroy() end) end
    end
end

local function New(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    return inst
end
local function Corner(parent, radius)
    local r = (typeof(radius) == "UDim") and radius or UDim.new(0, radius or 8)
    return New("UICorner", { CornerRadius = r, Parent = parent })
end
local function Stroke(parent, color, thickness, transparency)
    return New("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, Parent = parent })
end
local function Tween(inst, props, t)
    TweenService:Create(inst, TweenInfo.new(t or 0.2), props):Play()
end
local function GetEvents() return ReplicatedStorage:FindFirstChild("Events") end

CleanupPrevious()

local Accent     = Color3.fromRGB(110, 50, 190)
local AccentDark = Color3.fromRGB(70, 30, 130)
local AccentText = Color3.fromRGB(240, 230, 255)
local IdleBg     = Color3.fromRGB(35, 22, 55)
local IdleText   = Color3.fromRGB(180, 165, 210)
local FieldBg    = Color3.fromRGB(28, 18, 44)
local FieldText  = Color3.fromRGB(225, 215, 245)
local TrackBg    = Color3.fromRGB(50, 40, 70)

local ScreenGui = New("ScreenGui", {
    Name = "ZettaPulseSuiteUI", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = SafeParent(),
})
local LAUNCHER_SIZE = 42
local LauncherIcon = New("TextButton", {
    Name = "LauncherIcon", Size = UDim2.new(0, LAUNCHER_SIZE, 0, LAUNCHER_SIZE),
    Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Color3.fromRGB(20, 15, 30), BackgroundTransparency = 0.15,
    BorderSizePixel = 0, Text = "ZP", TextColor3 = Accent, TextSize = 16,
    Font = Enum.Font.GothamBold, Active = true, AutoButtonColor = false, Parent = ScreenGui,
})
Corner(LauncherIcon, 12)
do
    local dragging, dragStart, startPos
    LauncherIcon.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPos = LauncherIcon.Position
        end
    end)
    Connections.LauncherDragMove = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if math.abs(delta.X) < 6 and math.abs(delta.Y) < 6 then return end
        local ps = ScreenGui.AbsoluteSize
        LauncherIcon.Position = UDim2.new(0,
            math.clamp(startPos.X.Offset + delta.X, 0, ps.X - LAUNCHER_SIZE), 0,
            math.clamp(startPos.Y.Offset + delta.Y, 0, ps.Y - LAUNCHER_SIZE))
    end)
    Connections.LauncherDragEnd = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local MainFrame = New("Frame", {
    Name = "MainFrame", Size = UDim2.new(0.88, 0, 0.72, 0),
    Position = UDim2.new(0.06, 0, 0.14, 0),
    BackgroundColor3 = Color3.fromRGB(15, 10, 25), BackgroundTransparency = 0.35,
    BorderSizePixel = 0, ClipsDescendants = true, Active = true, Draggable = true, Parent = ScreenGui,
})
New("UISizeConstraint", { MaxSize = Vector2.new(520, 460), MinSize = Vector2.new(280, 220), Parent = MainFrame })
Corner(MainFrame, 12)
Stroke(MainFrame, AccentDark, 1.5, 0.35)

local TopBar = New("Frame", {
    Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(25, 15, 40),
    BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = MainFrame,
})
New("TextLabel", {
    Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1, Text = "Noclipov UI", TextColor3 = AccentText,
    TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = TopBar,
})

local function TopButton(text, color, textColor, transp, xOff)
    local b = New("TextButton", {
        Size = UDim2.new(0, 36, 0, 36), Position = UDim2.new(1, xOff, 0, 4),
        BackgroundColor3 = color, BackgroundTransparency = transp,
        Text = text, TextColor3 = textColor, TextSize = 16, Font = Enum.Font.GothamBold, Parent = TopBar,
    })
    Corner(b, 8)
    return b
end

local CloseButton = TopButton("X", Color3.fromRGB(200, 50, 50), Color3.fromRGB(255, 100, 100), 0.8, -42)
local HideButton  = TopButton("-", AccentDark, AccentText, 0.6, -84)
HideButton.TextSize = 20

local SideBar = New("ScrollingFrame", {
    Size = UDim2.new(0.28, 0, 1, -44), Position = UDim2.new(0, 0, 0, 44),
    BackgroundColor3 = Color3.fromRGB(20, 12, 32), BackgroundTransparency = 0.4,
    BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Accent, Parent = MainFrame,
})
New("UIListLayout", {
    Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder, Parent = SideBar,
})
New("UIPadding", { PaddingTop = UDim.new(0, 8), Parent = SideBar })

local Container = New("Frame", {
    Size = UDim2.new(0.72, -10, 1, -52), Position = UDim2.new(0.28, 5, 0, 48),
    BackgroundTransparency = 1, Parent = MainFrame,
})

local Tabs = {}
local FirstTab = true

local function CreateTab(name)
    local Button = New("TextButton", {
        Name = name .. "Tab", Size = UDim2.new(0.9, 0, 0, 40),
        BackgroundColor3 = IdleBg, BackgroundTransparency = 0.25,
        BorderSizePixel = 0, Text = name, TextColor3 = IdleText, TextSize = 11,
        Font = Enum.Font.GothamMedium, Parent = SideBar,
    })
    Corner(Button, 8)
    local Page = New("ScrollingFrame", {
        Name = name .. "Page", Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 4, ScrollBarImageColor3 = Accent, Visible = false, Parent = Container,
    })
    New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Page })
    New("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = Page })
    if FirstTab then
        FirstTab = false
        Page.Visible = true
        Button.BackgroundColor3 = Accent
        Button.BackgroundTransparency = 0.1
        Button.TextColor3 = AccentText
    end
    Button.MouseButton1Click:Connect(function()
        for _, t in ipairs(Tabs) do
            t.Page.Visible = false
            Tween(t.Button, { BackgroundColor3 = IdleBg, BackgroundTransparency = 0.25, TextColor3 = IdleText })
        end
        Page.Visible = true
        Tween(Button, { BackgroundColor3 = Accent, BackgroundTransparency = 0.1, TextColor3 = AccentText })
    end)
    table.insert(Tabs, { Button = Button, Page = Page })
    return Page
end

local function CreateToggle(page, text, default, cb)
    local Frame = New("Frame", {
        Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = FieldBg,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = page,
    })
    Corner(Frame, 8)
    New("TextLabel", {
        Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1, Text = text, TextColor3 = FieldText, TextSize = 11,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = Frame,
    })
    local toggled = default
    local Switch = New("TextButton", {
        Size = UDim2.new(0, 48, 0, 26), Position = UDim2.new(1, -54, 0.5, -13),
        BackgroundColor3 = toggled and Accent or TrackBg,
        BackgroundTransparency = toggled and 0.1 or 0, Text = "", Parent = Frame,
    })
    Corner(Switch, UDim.new(1, 0))
    local Knob = New("Frame", {
        Size = UDim2.new(0, 20, 0, 20),
        Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Parent = Switch,
    })
    Corner(Knob, UDim.new(1, 0))
    Switch.MouseButton1Click:Connect(function()
        toggled = not toggled
        Tween(Switch, { BackgroundColor3 = toggled and Accent or TrackBg, BackgroundTransparency = toggled and 0.1 or 0 })
        Tween(Knob, { Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10) })
        cb(toggled)
    end)
end

local function CreateSlider(page, text, min, max, default, cb, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    local Frame = New("Frame", {
        Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = FieldBg,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = page,
    })
    Corner(Frame, 8)
    New("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0, 10, 0, 3),
        BackgroundTransparency = 1, Text = text, TextColor3 = FieldText, TextSize = 11,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = Frame,
    })
    local ValueLabel = New("TextLabel", {
        Size = UDim2.new(0.35, 0, 0, 18), Position = UDim2.new(0.6, -10, 0, 3),
        BackgroundTransparency = 1,
        Text = string.format("%." .. decimals .. "f", default),
        TextColor3 = Accent, TextSize = 11, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = Frame,
    })
    local Track = New("TextButton", {
        Size = UDim2.new(1, -20, 0, 10), Position = UDim2.new(0, 10, 0, 26),
        BackgroundColor3 = TrackBg, Text = "", Parent = Frame,
    })
    Corner(Track, UDim.new(1, 0))
    local Fill = New("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Accent, BorderSizePixel = 0, Parent = Track,
    })
    Corner(Fill, UDim.new(1, 0))
    local dragging = false
    local function update(input)
        local posX = math.clamp(input.Position.X - Track.AbsolutePosition.X, 0, Track.AbsoluteSize.X)
        local pct = posX / Track.AbsoluteSize.X
        local value = min + (max - min) * pct
        value = math.floor(value * mult + 0.5) / mult
        Fill.Size = UDim2.new(pct, 0, 1, 0)
        ValueLabel.Text = string.format("%." .. decimals .. "f", value)
        cb(value)
    end
    Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(input)
        end
    end)
    Connections["SliderMove_" .. text] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then update(input) end
    end)
    Connections["SliderEnd_" .. text] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function CreateButton(page, text, cb)
    local Button = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(45, 28, 70),
        BackgroundTransparency = 0.15, BorderSizePixel = 0, Text = text,
        TextColor3 = FieldText, TextSize = 11, Font = Enum.Font.GothamMedium, Parent = page,
    })
    Corner(Button, 8)
    Button.MouseButton1Click:Connect(function()
        Tween(Button, { BackgroundColor3 = Accent, BackgroundTransparency = 0.1, TextColor3 = AccentText }, 0.1)
        task.wait(0.1)
        Tween(Button, { BackgroundColor3 = Color3.fromRGB(45, 28, 70), BackgroundTransparency = 0.15, TextColor3 = FieldText })
        cb()
    end)
end

local CHAR_RAY_PARAMS = RaycastParams.new()
CHAR_RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
CHAR_RAY_PARAMS.IgnoreWater = true

local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    if hum.Health <= 0 then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping
        or st == Enum.HumanoidStateType.Freefall
        or st == Enum.HumanoidStateType.FallingDown then return true end
    if hum.FloorMaterial == Enum.Material.Air then
        local f = {}
        if LocalPlayer.Character then table.insert(f, LocalPlayer.Character) end
        CHAR_RAY_PARAMS.FilterDescendantsInstances = f
        local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -3.0, 0), CHAR_RAY_PARAMS)
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
    local charEvents = events:FindFirstChild("Character")
    if charEvents and charEvents:FindFirstChild("Revive") then
        pcall(function() charEvents.Revive:FireServer() end)
    end
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

local function WritePlane(lv, hrp, horiz)
    if lv and lv.Parent then
        if lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane then
            lv.PlaneVelocity = Vector2.new(horiz.X, horiz.Z)
        elseif lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Vector then
            local v = lv.VectorVelocity
            lv.VectorVelocity = Vector3.new(horiz.X, v.Y, horiz.Z)
        end
    end
    local v = hrp.AssemblyLinearVelocity
    hrp.AssemblyLinearVelocity = Vector3.new(horiz.X, v.Y, horiz.Z)
end

local function ClampVelocity(hrp)
    local av = hrp.AssemblyLinearVelocity
    local horiz = Vector3.new(av.X, 0, av.Z)
    local y = av.Y
    local clamped = false
    if horiz.Magnitude > CFG.MaxSpeed then
        horiz = horiz.Unit * CFG.MaxSpeed
        clamped = true
    end
    if math.abs(y) > CFG.VertCap then
        y = (y > 0) and CFG.VertCap or -CFG.VertCap
        clamped = true
    end
    local newV = Vector3.new(horiz.X, y, horiz.Z)
    if newV.Magnitude > CFG.AbsCap then
        newV = newV.Unit * CFG.AbsCap
        clamped = true
    end
    if clamped then hrp.AssemblyLinearVelocity = newV end
    return clamped
end

local function RotateTowardsXZ(fromDir, toDir, maxAngleRad)
    if fromDir.Magnitude < 0.001 then return toDir end
    if toDir.Magnitude < 0.001 then return fromDir end
    local from = Vector3.new(fromDir.X, 0, fromDir.Z).Unit
    local to   = Vector3.new(toDir.X, 0, toDir.Z).Unit
    local dot = math.clamp(from:Dot(to), -1, 1)
    local angle = math.acos(dot)
    if angle <= maxAngleRad then return to end
    local cross = from:Cross(to)
    if math.abs(cross.Y) < 0.0001 and math.abs(cross.X) < 0.0001 and math.abs(cross.Z) < 0.0001 then
        if dot > 0 then return to end
        return Vector3.new(-from.Z, 0, from.X)
    end
    local rot = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), (cross.Y > 0) and maxAngleRad or -maxAngleRad)
    return (rot * from).Unit
end

local function GetCameraForwardXZ()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local f = cam.CFrame.LookVector
    local flat = Vector3.new(f.X, 0, f.Z)
    if flat.Magnitude < 0.01 then return nil end
    return flat.Unit
end

local function GetMoveDir(hum)
    local md = hum.MoveDirection
    if md.Magnitude > 0.01 then
        local flat = Vector3.new(md.X, 0, md.Z)
        if flat.Magnitude > 0.01 then return flat.Unit end
    end
    return nil
end

local function GetPhysicsDir(hrp)
    local av = hrp.AssemblyLinearVelocity
    local horiz = Vector3.new(av.X, 0, av.Z)
    local spd = horiz.Magnitude
    if spd < 0.5 then return nil, spd end
    return horiz.Unit, spd
end

local function PredictLanding(hrp, hum, maxTime)
    if not hrp then return nil end
    maxTime = maxTime or 2.5

    local feetOffset = 2.5
    if hum and hum:IsA("Humanoid") then
        local ok, hh = pcall(function() return hum.HipHeight end)
        if ok and typeof(hh) == "number" and hh > 0 then feetOffset = hh end
    end

    local pos = hrp.Position - Vector3.new(0, feetOffset, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity
    local dt = 0.04
    local maxSteps = math.ceil(maxTime / dt)

    local filter = {}
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    CHAR_RAY_PARAMS.FilterDescendantsInstances = filter

    for _ = 1, maxSteps do
        local newPos = pos + vel * dt + Vector3.new(0, -0.5 * g * dt * dt, 0)
        local newVel = Vector3.new(vel.X, vel.Y - g * dt, vel.Z)

        local delta = newPos - pos
        if delta.Magnitude > 0.01 then
            local hit = Workspace:Raycast(pos, delta, CHAR_RAY_PARAMS)
            if hit then
                if hit.Normal.Y > 0.4 then
                    return hit.Position
                end
                return nil
            end
        end
        pos = newPos
        vel = newVel
    end
    return nil
end

local PredData = nil
local lastPredSuccess = 0
local lastPredUpdate = 0

local function DestroyPredPart()
    if not PredData then return end
    if PredData.ring then pcall(function() PredData.ring:Destroy() end) end
    if PredData.dot then pcall(function() PredData.dot:Destroy() end) end
    PredData = nil
end

local function EnsurePredPart()
    if PredData and PredData.ring and PredData.ring.Parent then return PredData end
    DestroyPredPart()

    local ring = Instance.new("Part")
    ring.Name = "ZP_Pred_Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.12, 5.5, 5.5)
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(170, 100, 255)
    ring.Transparency = 0.5
    ring.TopSurface = Enum.SurfaceType.Smooth
    ring.BottomSurface = Enum.SurfaceType.Smooth

    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(190, 120, 255)
    hl.FillTransparency = 0.7
    hl.OutlineColor = Color3.fromRGB(230, 180, 255)
    hl.OutlineTransparency = 0.3
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.Adornee = ring
    hl.Parent = ring

    local dot = Instance.new("Part")
    dot.Name = "ZP_Pred_Dot"
    dot.Shape = Enum.PartType.Ball
    dot.Size = Vector3.new(1.1, 1.1, 1.1)
    dot.Anchored = true
    dot.CanCollide = false
    dot.CanQuery = false
    dot.CanTouch = false
    dot.Material = Enum.Material.Neon
    dot.Color = Color3.fromRGB(235, 170, 255)
    dot.Transparency = 0.2

    ring.Parent = Workspace
    dot.Parent = Workspace

    PredData = { ring = ring, dot = dot, hl = hl }
    return PredData
end

local function UpdateLandingPrediction()
    if not State.LandPredEnabled then
        DestroyPredPart(); lastPredSuccess = 0
        return
    end
    local now = os.clock()
    if now - lastPredUpdate < 0.033 then return end
    lastPredUpdate = now

    local char = LocalPlayer.Character
    if not char then DestroyPredPart(); lastPredSuccess = 0; return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum or not IsAirborne(hum, hrp) then
        DestroyPredPart(); lastPredSuccess = 0; return
    end

    local pos = PredictLanding(hrp, hum, 2.5)
    if not pos then
        if now - lastPredSuccess > 0.15 then DestroyPredPart() end
        return
    end
    lastPredSuccess = now

    local data = EnsurePredPart()
    local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 3)
    local size = 5.0 + pulse * 1.6
    data.ring.Size = Vector3.new(0.12, size, size)
    data.ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    data.ring.Transparency = 0.35 + pulse * 0.30
    data.dot.CFrame = CFrame.new(pos + Vector3.new(0, 0.35, 0))
    data.dot.Transparency = 0.15 + pulse * 0.20
    data.hl.FillTransparency = 0.60 + pulse * 0.25
    data.hl.OutlineTransparency = 0.30 + pulse * 0.30
end

local TargetSpeed  = 0
local LastDir      = Vector3.new(0, 0, 0)
local WasAirborne  = false
local TrackedHrp   = nil
local TrackedLV    = nil
local LastLandingBoosted = false

local function ResetBhopState()
    TargetSpeed = 0
    LastDir = Vector3.new(0, 0, 0)
end

local function TryBhop(dt)
    local char = LocalPlayer.Character
    if not char then
        ResetBhopState(); WasAirborne = false; TrackedHrp = nil; TrackedLV = nil
        return
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then ResetBhopState(); WasAirborne = false; return end

    if TrackedHrp ~= hrp then
        TrackedHrp = hrp
        TrackedLV = FindGameLV(char)
        ResetBhopState()
        WasAirborne = false
    elseif not TrackedLV or TrackedLV.Parent ~= hrp then
        TrackedLV = FindGameLV(char)
    end

    if not State.BhopEnabled then
        ResetBhopState()
        WasAirborne = IsAirborne(hum, hrp)
        ClampVelocity(hrp)
        return
    end

    local airborne = IsAirborne(hum, hrp)
    local humState = hum:GetState()
    local physDir, physSpeed = GetPhysicsDir(hrp)

    if airborne and not WasAirborne then
        local isRealJump = (humState == Enum.HumanoidStateType.Jumping) and State.IsHoldingJump
        if isRealJump then
            local baseSpeed = math.max(TargetSpeed, physSpeed)
            if baseSpeed > 3 then
                local gainMult = CFG.GainPercent / 100
                local headroom = CFG.MaxSpeed - baseSpeed
                local wanted   = baseSpeed * gainMult
                local actual   = math.min(wanted, math.max(0, headroom))
                TargetSpeed = baseSpeed + actual
                -- Seed direction from current momentum (airplane vector)
                if physDir then
                    LastDir = physDir
                elseif GetMoveDir(hum) then
                    LastDir = GetMoveDir(hum)
                end
            end
        end
    end

    local braking = airborne and TargetSpeed > 0
        and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
    if braking then
        TargetSpeed = math.max(CFG.MinSpeed, TargetSpeed - CFG.BrakeRate * dt)
    end

    local locked = airborne and UserInputService:IsKeyDown(Enum.KeyCode.Q)

    if airborne and TargetSpeed >= 1 then
        -- Snap (R key)
        if State.SnapRequested then
            local camDir = GetCameraForwardXZ()
            if camDir then LastDir = camDir end
            State.SnapRequested = false
        end

        if not locked then
            -- Seed if empty
            if LastDir.Magnitude < 0.01 then
                LastDir = physDir or Vector3.new(0, 0, 1)
            end

            -- Airplane correction: if physics speed matches our target,
            -- direction is our true momentum. Use it (fixes drift).
            if physDir and physSpeed > TargetSpeed * 0.7 then
                local align = LastDir:Dot(physDir)
                if align > 0.5 then
                    LastDir = physDir
                end
            end

            -- WASD soft steering (no snap, no hard threshold)
            local inputDir = GetMoveDir(hum)
            if inputDir then
                LastDir = RotateTowardsXZ(LastDir, inputDir, math.rad(CFG.SoftRate) * dt)
            end
        end

        if LastDir.Magnitude < 0.01 then LastDir = Vector3.new(0, 0, 1) end
        local writeSpeed = math.min(TargetSpeed, CFG.MaxSpeed)
        WritePlane(TrackedLV, hrp, LastDir * writeSpeed)

        if UserInputService:IsKeyDown(Enum.KeyCode.X) then
            local v = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(
                v.X,
                math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap),
                v.Z
            )
        end
    end

    if not airborne and TargetSpeed >= 1 and State.IsHoldingJump then
        if LastDir.Magnitude > 0.01 then
            local writeSpeed = math.min(TargetSpeed, CFG.MaxSpeed)
            WritePlane(TrackedLV, hrp, LastDir * writeSpeed)
        end
        if hum.FloorMaterial ~= Enum.Material.Air
            and humState ~= Enum.HumanoidStateType.Jumping then
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    if not airborne and WasAirborne then
        if State.LandingBoostEnabled and TargetSpeed > 0 and not LastLandingBoosted then
            local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
            if vy <= CFG.LandingSoftVY then
                local bonus = TargetSpeed * (CFG.LandingBoostPercent / 100)
                local headroom = CFG.MaxSpeed - TargetSpeed
                TargetSpeed = TargetSpeed + math.min(bonus, math.max(0, headroom))
                LastLandingBoosted = true
            end
        end
    end
    if not airborne then LastLandingBoosted = false end

    if not airborne and not State.IsHoldingJump then
        ResetBhopState()
    end

    WasAirborne = airborne
    ClampVelocity(hrp)
end

local SLOPE = {
    Cooldown = 0.55, MinSpeed = 25,
    Gain = 1.15, GainPerSpeed = 0.01, MaxGain = 2.2,
    SpeedRef = 40, UpComponent = 1.0, MinRise = 1.5,
    NormalMin = 0.30, NormalMax = 0.98, AirRay = 20, GroundRay = 12,
}
local LastSlopeBoost = 0
local DOWN_AIR    = Vector3.new(0, -SLOPE.AirRay, 0)
local DOWN_GROUND = Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRayParams = RaycastParams.new()
SlopeRayParams.FilterType = Enum.RaycastFilterType.Exclude
SlopeRayParams.IgnoreWater = true
SlopeRayParams.FilterDescendantsInstances = {}
pcall(function() SlopeRayParams.RespectCanCollide = true end)

local function RefreshSlopeFilter()
    local filter = {}
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    local map = Workspace:FindFirstChild("Map")
    if map then
        local parts = map:FindFirstChild("Parts")
        if parts then
            local props = parts:FindFirstChild("ImmovableProps")
            if props then table.insert(filter, props) end
        end
    end
    SlopeRayParams.FilterDescendantsInstances = filter
end

local function SampleGroundY(origin, rayVec)
    local r = Workspace:Raycast(origin, rayVec, SlopeRayParams)
    if not r or not r.Instance then return nil, nil end
    return r.Position.Y, r
end

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock()
    if now - LastSlopeBoost < SLOPE.Cooldown then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    RefreshSlopeFilter()
    local vel = hrp.AssemblyLinearVelocity
    if vel.Y < 2 then return end
    local flatVel = Vector3.new(vel.X, 0, vel.Z)
    local speed = flatVel.Magnitude
    if speed < 0.1 then return end
    local fw = flatVel.Unit
    local base = hrp.Position
    local hBehind = SampleGroundY(base - fw * 2.0, DOWN_AIR)
    local hAhead1, frontRay = SampleGroundY(base + fw * 1.0, DOWN_AIR)
    local hAhead2 = SampleGroundY(base + fw * 2.5, DOWN_AIR)
    local hAhead3 = SampleGroundY(base + fw * 4.0, DOWN_AIR)
    if not (hBehind and hAhead1 and hAhead2 and frontRay) then
        hBehind = SampleGroundY(base - fw * 2.0, DOWN_GROUND)
        hAhead1, frontRay = SampleGroundY(base + fw * 1.0, DOWN_GROUND)
        hAhead2 = SampleGroundY(base + fw * 2.5, DOWN_GROUND)
        hAhead3 = SampleGroundY(base + fw * 4.0, DOWN_GROUND)
    end
    if not (hBehind and hAhead1 and hAhead2 and frontRay) then return end
    local rise1 = hAhead1 - hBehind
    local rise2 = hAhead2 - hBehind
    local rise3 = hAhead3 and (hAhead3 - hBehind) or rise2
    if rise1 <= 0 or rise2 <= 0 then return end
    if rise1 < SLOPE.MinRise then return end
    if rise2 < SLOPE.MinRise * 0.7 then return end
    if rise1 > rise2 * 2.0 then return end
    if rise3 < SLOPE.MinRise * 0.5 and rise2 < SLOPE.MinRise then return end
    local upDot = frontRay.Normal:Dot(Vector3.new(0, 1, 0))
    if upDot >= SLOPE.NormalMax or upDot <= SLOPE.NormalMin then return end
    LastSlopeBoost = now
    local fwCapture = fw
    task.spawn(function()
        task.wait(0.03)
        if not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
        if not hrp.Parent then return end
        local v2 = hrp.AssemblyLinearVelocity
        if v2.Y < 0 then return end
        local currentSpeed = Vector3.new(v2.X, 0, v2.Z).Magnitude
        local curOverRef = math.max(0, currentSpeed - SLOPE.SpeedRef)
        local curGain = math.min(SLOPE.Gain + curOverRef * SLOPE.GainPerSpeed, SLOPE.MaxGain)
        hrp.AssemblyLinearVelocity =
            (fwCapture + Vector3.new(0, SLOPE.UpComponent, 0)).Unit
            * math.max(currentSpeed, SLOPE.MinSpeed) * curGain
    end)
end

Connections.JumpInputBegan = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = true end
    if input.KeyCode == Enum.KeyCode.R then State.SnapRequested = true end
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

local PlayerTab = CreateTab("Main")

CreateButton(PlayerTab, "Instant Revive Self", TriggerSelfRevive)

CreateToggle(PlayerTab, "Auto BunnyHop", State.BhopEnabled, function(v)
    State.BhopEnabled = v
    if not v then ResetBhopState() end
end)

CreateToggle(PlayerTab, "Slope Boost", State.SlopeBoostEnabled, function(v)
    State.SlopeBoostEnabled = v
    if not v then LastSlopeBoost = 0 end
end)

CreateToggle(PlayerTab, "Landing Prediction", State.LandPredEnabled, function(v)
    State.LandPredEnabled = v
    if not v then DestroyPredPart() end
end)

CreateToggle(PlayerTab, "Landing Boost", State.LandingBoostEnabled, function(v)
    State.LandingBoostEnabled = v
end)

CreateSlider(PlayerTab, "Gain Percent", 1, 20, CFG.GainPercent, function(v)
    CFG.GainPercent = v
end)

CreateSlider(PlayerTab, "Max Speed", 50, 250, CFG.MaxSpeed, function(v)
    CFG.MaxSpeed = v
end)

CreateSlider(PlayerTab, "Vertical Cap", 40, 100, CFG.VertCap, function(v)
    CFG.VertCap = v
end)

CreateSlider(PlayerTab, "Soft Rate", 20, 360, CFG.SoftRate, function(v)
    CFG.SoftRate = v
end)

CreateSlider(PlayerTab, "Brake Rate", 20, 200, CFG.BrakeRate, function(v)
    CFG.BrakeRate = v
end)

CreateSlider(PlayerTab, "Fast Fall Force", 30, 300, CFG.FastFallForce, function(v)
    CFG.FastFallForce = v
end)

CreateSlider(PlayerTab, "Min Speed", 5, 50, CFG.MinSpeed, function(v)
    CFG.MinSpeed = v
end)

CreateSlider(PlayerTab, "Land Boost Percent", 0, 20, CFG.LandingBoostPercent, function(v)
    CFG.LandingBoostPercent = v
end)

CreateSlider(PlayerTab, "Land Soft VY", 10, 60, CFG.LandingSoftVY, function(v)
    CFG.LandingSoftVY = v
end)

local function Cleanup()
    for k in pairs(State) do
        if type(State[k]) == "boolean" then State[k] = false end
    end
    for _, conn in pairs(Connections) do
        if typeof(conn) == "RBXScriptConnection" and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(Connections)
    ResetBhopState()
    WasAirborne = false
    TrackedHrp = nil
    TrackedLV = nil
    DestroyPredPart()
    if ScreenGui then pcall(function() ScreenGui:Destroy() end) end
    if ENV.__ZettaCleanup == Cleanup then ENV.__ZettaCleanup = nil end
end
ENV.__ZettaCleanup = Cleanup

LauncherIcon.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
HideButton.MouseButton1Click:Connect(function() MainFrame.Visible = false end)
CloseButton.MouseButton1Click:Connect(Cleanup)