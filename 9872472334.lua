repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334] = true, [10662098230] = true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!")
    return
end

-- Services ---------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

local Connections = {}
local State = {
    BhopEnabled        = false,
    IsHoldingJump      = false,
    SlopeBoostEnabled  = false,
    StrafeEnabled      = false,
    SpeedBoostEnabled  = false,
    AutoReviveEnabled  = false,
    AutoReviveOthers   = false,
}
local ScriptActive = true

-- Helpers ----------------------------------------------------------------
local function SafeParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    if syn and syn.protect_gui then
        local sg = Instance.new("ScreenGui")
        syn.protect_gui(sg)
        return sg
    end
    return CoreGui
end

local function CleanupPrevious()
    if type(ENV.__ZettaCleanup) == "function" then
        pcall(ENV.__ZettaCleanup)
    end
    ENV.__ZettaCleanup = nil
    ENV.__ZettaSession = nil

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
    return New("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        Parent = parent,
    })
end

local function Tween(inst, props, t)
    TweenService:Create(inst, TweenInfo.new(t or 0.2), props):Play()
end

local function GetEvents()
    return ReplicatedStorage:FindFirstChild("Events")
end

CleanupPrevious()

-- Theme ------------------------v----------------------------------------
local Accent     = Color3.fromRGB(110, 50, 190)
local AccentDark = Color3.fromRGB(70, 30, 130)
local AccentText = Color3.fromRGB(240, 230, 255)
local IdleBg     = Color3.fromRGB(35, 22, 55)
local IdleText   = Color3.fromRGB(180, 165, 210)
local FieldBg    = Color3.fromRGB(28, 18, 44)
local FieldText  = Color3.fromRGB(225, 215, 245)
local TrackBg    = Color3.fromRGB(50, 40, 70)

-- UI Root --------------------------------------------------------------
local ScreenGui = New("ScreenGui", {
    Name = "ZettaPulseSuiteUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = SafeParent(),
})

local LAUNCHER_SIZE = 42

local LauncherIcon = New("TextButton", {
    Name = "LauncherIcon",
    Size = UDim2.new(0, LAUNCHER_SIZE, 0, LAUNCHER_SIZE),
    Position = UDim2.new(0.03, 0, 0.25, 0),
    BackgroundColor3 = Color3.fromRGB(20, 15, 30),
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Text = "ZP",
    TextColor3 = Accent,
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    Active = true,
    AutoButtonColor = false,
    Parent = ScreenGui,
})
Corner(LauncherIcon, 12)
do
    local dragging, dragStart, startPos
    local DRAG_THRESHOLD = 6

    local function beginDrag(input)
        dragging = true
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        startPos = LauncherIcon.Position
    end

    local function moveDrag(input)
        if not dragging then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        -- Порог, чтобы обычный тап не превращался в микро-перетаскивание
        if math.abs(delta.X) < DRAG_THRESHOLD and math.abs(delta.Y) < DRAG_THRESHOLD then
            return
        end
        local parentSize = ScreenGui.AbsoluteSize
        local newX = startPos.X.Offset + delta.X
        local newY = startPos.Y.Offset + delta.Y
        -- Не позволяем утащить иконку за пределы экрана
        newX = math.clamp(newX, 0, parentSize.X - LAUNCHER_SIZE)
        newY = math.clamp(newY, 0, parentSize.Y - LAUNCHER_SIZE)
        LauncherIcon.Position = UDim2.new(0, newX, 0, newY)
    end

    local function endDrag()
        dragging = false
    end

    LauncherIcon.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag(input)
        end
    end)

    Connections.LauncherDragMove = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            moveDrag(input)
        end
    end)

    Connections.LauncherDragEnd = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            endDrag()
        end
    end)
end


local MainFrame = New("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0.88, 0, 0.72, 0),
    Position = UDim2.new(0.06, 0, 0.14, 0),
    BackgroundColor3 = Color3.fromRGB(15, 10, 25),
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
    Draggable = true,
    Parent = ScreenGui,
})
New("UISizeConstraint", {
    MaxSize = Vector2.new(520, 360),
    MinSize = Vector2.new(280, 220),
    Parent = MainFrame,
})
Corner(MainFrame, 12)
Stroke(MainFrame, AccentDark, 1.5, 0.35)

local TopBar = New("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = Color3.fromRGB(25, 15, 40),
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    Parent = MainFrame,
})

New("TextLabel", {
    Size = UDim2.new(0.6, 0, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "Noclipov UI",
    TextColor3 = AccentText,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TopBar,
})

local function TopButton(text, color, textColor, transparency, xOffset)
    local b = New("TextButton", {
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(1, xOffset, 0, 4),
        BackgroundColor3 = color,
        BackgroundTransparency = transparency,
        Text = text,
        TextColor3 = textColor,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        Parent = TopBar,
    })
    Corner(b, 8)
    return b
end

local CloseButton = TopButton("X", Color3.fromRGB(200, 50, 50), Color3.fromRGB(255, 100, 100), 0.8, -42)
local HideButton  = TopButton("-", AccentDark, AccentText, 0.6, -84)
HideButton.TextSize = 20

local SideBar = New("ScrollingFrame", {
    Size = UDim2.new(0.28, 0, 1, -44),
    Position = UDim2.new(0, 0, 0, 44),
    BackgroundColor3 = Color3.fromRGB(20, 12, 32),
    BackgroundTransparency = 0.4,
    BorderSizePixel = 0,
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = Accent,
    Parent = MainFrame,
})
New("UIListLayout", {
    Padding = UDim.new(0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = SideBar,
})
New("UIPadding", { PaddingTop = UDim.new(0, 8), Parent = SideBar })

local Container = New("Frame", {
    Size = UDim2.new(0.72, -10, 1, -52),
    Position = UDim2.new(0.28, 5, 0, 48),
    BackgroundTransparency = 1,
    Parent = MainFrame,
})

-- Components -----------------------------------------------------------
local Tabs = {}
local FirstTab = true

local function CreateTab(name)
    local Button = New("TextButton", {
        Name = name .. "Tab",
        Size = UDim2.new(0.9, 0, 0, 40),
        BackgroundColor3 = IdleBg,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = IdleText,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        Parent = SideBar,
    })
    Corner(Button, 8)

    local Page = New("ScrollingFrame", {
        Name = name .. "Page",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Accent,
        Visible = false,
        Parent = Container,
    })
    New("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = Page,
    })
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
            Tween(t.Button, {
                BackgroundColor3 = IdleBg,
                BackgroundTransparency = 0.25,
                TextColor3 = IdleText,
            })
        end
        Page.Visible = true
        Tween(Button, {
            BackgroundColor3 = Accent,
            BackgroundTransparency = 0.1,
            TextColor3 = AccentText,
        })
    end)

    table.insert(Tabs, { Button = Button, Page = Page })
    return Page
end

local function CreateToggle(page, text, default, callback)
    local Frame = New("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = FieldBg,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Parent = page,
    })
    Corner(Frame, 8)

    New("TextLabel", {
        Size = UDim2.new(0.65, 0, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = FieldText,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = Frame,
    })

    local toggled = default
    local Switch = New("TextButton", {
        Size = UDim2.new(0, 48, 0, 26),
        Position = UDim2.new(1, -54, 0.5, -13),
        BackgroundColor3 = toggled and Accent or TrackBg,
        BackgroundTransparency = toggled and 0.1 or 0,
        Text = "",
        Parent = Frame,
    })
    Corner(Switch, UDim.new(1, 0))

    local Knob = New("Frame", {
        Size = UDim2.new(0, 20, 0, 20),
        Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = Switch,
    })
    Corner(Knob, UDim.new(1, 0))

    Switch.MouseButton1Click:Connect(function()
        toggled = not toggled
        Tween(Switch, {
            BackgroundColor3 = toggled and Accent or TrackBg,
            BackgroundTransparency = toggled and 0.1 or 0,
        })
        Tween(Knob, {
            Position = toggled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        })
        callback(toggled)
    end)
end

local function CreateSlider(page, text, min, max, default, callback)
    local Frame = New("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = FieldBg,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Parent = page,
    })
    Corner(Frame, 8)

    New("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 20),
        Position = UDim2.new(0, 10, 0, 4),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = FieldText,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Frame,
    })
    local ValueLabel = New("TextLabel", {
        Size = UDim2.new(0.3, 0, 0, 20),
        Position = UDim2.new(0.7, -10, 0, 4),
        BackgroundTransparency = 1,
        Text = tostring(default),
        TextColor3 = Accent,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = Frame,
    })
    local Track = New("TextButton", {
        Size = UDim2.new(1, -20, 0, 12),
        Position = UDim2.new(0, 10, 0, 30),
        BackgroundColor3 = TrackBg,
        Text = "",
        Parent = Frame,
    })
    Corner(Track, UDim.new(1, 0))

    local Fill = New("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Accent,
        BorderSizePixel = 0,
        Parent = Track,
    })
    Corner(Fill, UDim.new(1, 0))

    local dragging = false
    local function update(input)
        local posX = math.clamp(input.Position.X - Track.AbsolutePosition.X, 0, Track.AbsoluteSize.X)
        local pct = posX / Track.AbsoluteSize.X
        local value = math.floor(min + (max - min) * pct)
        Fill.Size = UDim2.new(pct, 0, 1, 0)
        ValueLabel.Text = tostring(value)
        callback(value)
    end

    Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end)
    Connections["SliderMove_" .. text] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    Connections["SliderEnd_" .. text] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function CreateButton(page, text, callback)
    local Button = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Color3.fromRGB(45, 28, 70),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = FieldText,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        Parent = page,
    })
    Corner(Button, 8)

    Button.MouseButton1Click:Connect(function()
        Tween(Button, {
            BackgroundColor3 = Accent,
            BackgroundTransparency = 0.1,
            TextColor3 = AccentText,
        }, 0.1)
        task.wait(0.1)
        Tween(Button, {
            BackgroundColor3 = Color3.fromRGB(45, 28, 70),
            BackgroundTransparency = 0.15,
            TextColor3 = FieldText,
        })
        callback()
    end)
end

-- Tabs -----------------------------------------------------------------
local PlayerTab   = CreateTab("Main")

local function TriggerSelfRevive()
    local events = GetEvents()
    if not events then return end
    local revive = events:FindFirstChild("Revive")
    if revive then revive:FireServer() end
    local setMode = events:FindFirstChild("SetPlayerMode")
    if setMode then setMode:FireServer(true) end
    local charEvents = events:FindFirstChild("Character")
    if charEvents and charEvents:FindFirstChild("Revive") then
        charEvents.Revive:FireServer()
    end
end

CreateButton(PlayerTab, "Instant Revive Self", TriggerSelfRevive)
-- Bhop -----------------------------------------------------------------
CreateToggle(PlayerTab, "Auto BunnyHop (Hold Jump)", State.BhopEnabled, function(v)
    State.BhopEnabled = v
end)

-- Slope Boost ----------------------------------------------------------
local SLOPE = {
    Cooldown        = 0.25,
    MinSpeed        = 20,
    Gain            = 1.4,    -- базовый множитель импульса
    GainPerSpeed    = 0.025,  -- прибавка к Gain за каждую stud/s скорости
    MaxGain         = 3.5,    -- верхняя граница Gain (чтобы не улетать в космос)
    SpeedRef        = 50,     -- скорость, от которой считаем "быстрый" игрок
    UpComponent     = 2,
    MinRise         = 1.13,
    NormalMin       = 0.60,
    NormalMax       = 0.98,
    AirRay          = 18,
    GroundRay       = 8,
}
local LastSlopeBoost = 0
local DOWN_AIR    = Vector3.new(0, -SLOPE.AirRay, 0)
local DOWN_GROUND = Vector3.new(0, -SLOPE.GroundRay, 0)

local SlopeRayParams = RaycastParams.new()
SlopeRayParams.FilterType = Enum.RaycastFilterType.Exclude
SlopeRayParams.IgnoreWater = true
SlopeRayParams.RespectCanCollide = true  -- игнорировать парты с CanCollide = false
SlopeRayParams.FilterDescendantsInstances = { LocalPlayer.Character, workspace.Map.Parts.ImmovableProps }

local function RefreshSlopeFilter()
    local filter = {}
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    SlopeRayParams.FilterDescendantsInstances = filter
end

local function SampleGroundY(origin, rayVec)
    local r = Workspace:Raycast(origin, rayVec, SlopeRayParams)
    if not r then return nil, nil end
    -- Двойная защита: даже если RespectCanCollide не сработал по какой-то причине,
    -- не считаем поверхностью неколлизионные объекты
    if not r.Instance or not r.Instance.CanCollide then return nil, nil end
    return r.Position.Y, r
end

local function IsAirborne(hum)
    if not hum then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
        return true
    end
    return hum.FloorMaterial == Enum.Material.Air
end

local function SampleGroundY(origin, rayVec)
    local r = Workspace:Raycast(origin, rayVec, nil)
    return r and r.Position.Y or nil, r
end

local MIN_UPWARD_VELOCITY = 1.5   -- минимальная вертикальная скорость вверх (stud/s)

local function TrySlopeBoost()
    if not State.SlopeBoostEnabled then return end

    -- Буст работает только пока игрок удерживает пробел
    if not State.IsHoldingJump then return end

    local now = os.clock()
    if now - LastSlopeBoost < SLOPE.Cooldown then return end

    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not IsAirborne(hum) then return end

    RefreshSlopeFilter()

    local vel = hrp.AssemblyLinearVelocity
    if vel.Y < MIN_UPWARD_VELOCITY then return end

    local flatVel = Vector3.new(vel.X, 0, vel.Z)
    local speed = flatVel.Magnitude
    if speed < 0.1 then return end
    local fw = flatVel.Unit
    local base = hrp.Position

    local hBehind, hAhead1, hAhead2, hAhead3, frontRay
    for _, rayVec in ipairs({ DOWN_AIR, DOWN_GROUND }) do
        hBehind = SampleGroundY(base - fw * 2.0, rayVec)
        hAhead1, frontRay = SampleGroundY(base + fw * 1.0, rayVec)
        hAhead2 = SampleGroundY(base + fw * 2.5, rayVec)
        hAhead3 = SampleGroundY(base + fw * 4.0, rayVec)
        if hBehind and hAhead1 and hAhead2 then break end
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

    -- Чем быстрее игрок — тем сильнее импульс.
    local speedOverRef = math.max(0, speed - SLOPE.SpeedRef)
    local effectiveGain = SLOPE.Gain + speedOverRef * SLOPE.GainPerSpeed
    effectiveGain = math.min(effectiveGain, SLOPE.MaxGain)

    task.spawn(function()
        task.wait(0.03)
        if not State.SlopeBoostEnabled then return end
        if not State.IsHoldingJump then return end
        if not hrp.Parent then return end
        local v2 = hrp.AssemblyLinearVelocity
        if v2.Y < 0 then return end

        -- Скорость могла измениться за 0.03 сек — пересчитываем усилитель
        local currentSpeed = Vector3.new(v2.X, 0, v2.Z).Magnitude
        local curOverRef = math.max(0, currentSpeed - SLOPE.SpeedRef)
        local curGain = math.min(
            SLOPE.Gain + curOverRef * SLOPE.GainPerSpeed,
            SLOPE.MaxGain
        )

        hrp.AssemblyLinearVelocity =
            (fw + Vector3.new(0, SLOPE.UpComponent, 0)).Unit
            * math.max(currentSpeed, SLOPE.MinSpeed)
            * curGain
    end)
end

CreateToggle(PlayerTab, "Slope / Stair Boost (Air)", State.SlopeBoostEnabled, function(v)
    State.SlopeBoostEnabled = v
    if not v then LastSlopeBoost = 0 end
end)

Connections.SlopeBoostLoop = RunService.Heartbeat:Connect(TrySlopeBoost)

-- Character / Jump hooks ----------------------------------------------
local function HookBhop(character)
    if not character then return end
    local hum = character:WaitForChild("Humanoid", 5)
    if not hum then return end

    if Connections.BhopStateChanged then
        Connections.BhopStateChanged:Disconnect()
    end
    Connections.BhopStateChanged = hum.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Landed
            and State.IsHoldingJump
            and State.BhopEnabled then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

if LocalPlayer.Character then HookBhop(LocalPlayer.Character) end
Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function(char)
    HookBhop(char)
    if State.AutoReviveOthers then HookTouchRevive(char) end
end)

Connections.JumpInputBegan = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then
        State.IsHoldingJump = true
    end
end)

Connections.JumpInputEnded = UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        State.IsHoldingJump = false
    end
end)

-- Cleanup --------------------------------------------------------------
local function Cleanup()
    ScriptActive = false

    for k in pairs(State) do
        if type(State[k]) == "boolean" then State[k] = false end
    end

    for _, conn in pairs(Connections) do
        if typeof(conn) == "RBXScriptConnection" and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(Connections)
	RestoreAllLV()
    if ScreenGui then pcall(function() ScreenGui:Destroy() end) end

    if ENV.__ZettaCleanup == Cleanup then
        ENV.__ZettaCleanup = nil
    end
end

ENV.__ZettaCleanup = Cleanup

LauncherIcon.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)
HideButton.MouseButton1Click:Connect(function() MainFrame.Visible = false end)
CloseButton.MouseButton1Click:Connect(Cleanup)