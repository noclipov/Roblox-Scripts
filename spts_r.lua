-- [[ ЗАГРУЗКА БИБЛИОТЕК ]]
local conv = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/convs.lua"))()
loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Anti-AFK.lua"))()

local msg = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/NotifyModule.lua"))()
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/additional.lua"))()

-- [[ СЕРВИСЫ ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Mouse = LocalPlayer:GetMouse()
local Events = ReplicatedStorage:WaitForChild("RemoteEvents")

-- [[ НАСТРОЙКИ ]]
local STYLE = {
    Accent = Color3.fromRGB(140, 100, 255),
    Highlight = Color3.fromRGB(180, 160, 255),
    Bg = Color3.fromRGB(15, 15, 20),
    Text = Color3.fromRGB(255, 255, 255),
    Success = Color3.fromRGB(100, 255, 100),
    Distance = 60,
    MaxUiVisibleDistance = 80,
}

local STATS_CONFIG = {
    ["Head"] = {Attr = "PsychicPower", Name = "Psychic Power", Emoji = "🧠", Color = Color3.fromRGB(200, 100, 255), Offset = Vector3.new(3, 2, 0)},
    ["UpperTorso"] = {Attr = "BodyToughness", Name = "Body Toughness", Emoji = "🛡️", Color = Color3.fromRGB(80, 255, 150), Offset = Vector3.new(-3.5, 0.5, 0)},
    ["RightUpperArm"] = {Attr = "FistStrength", Name = "Fist Strength", Emoji = "🦾", Color = Color3.fromRGB(255, 80, 80), Offset = Vector3.new(3.5, 0, 0)},
    ["LeftUpperLeg"] = {Attr = "MovementSpeed", Name = "Movement Speed", Emoji = "⚡", Color = Color3.fromRGB(80, 200, 255), Offset = Vector3.new(-3, -2, 0)},
    ["RightUpperLeg"] = {Attr = "JumpForce", Name = "Jump Force", Emoji = "🚀", Color = Color3.fromRGB(255, 200, 80), Offset = Vector3.new(3, -2, 0)},
}

local INTERACTIONS = {
    {
        Name = "Nick", 
        Emoji = "👤", 
        Callback = function(targetPlayer)
            setclipboard(targetPlayer.Name)
        end
    },
    {
        Name = "Invite", 
        Emoji = "👥", 
        Callback = function(targetPlayer)
            Events.GangRemotes.Invite:FireServer(targetPlayer.UserId)
        end
    },
}

-- [[ ПЕРЕМЕННЫЕ СОСТОЯНИЯ ]]
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local states = {phychiczone = false, autofarm = false, farmingpos = nil}
local activeScanner = nil

-- [[ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ]]
local function copyToClipboard(text)
    local setC = setclipboard or toclipboard or (Clipboard and Clipboard.set)
    if setC then
        setC(tostring(text))
    else
        warn("Твой эксплоит не поддерживает копирование в буфер обмена!")
    end
end

local function useskill(name, arg)
	if not name then return end
	local args = {[1]=name} 
	if arg then args[2] = arg end
	Events:WaitForChild("UseSkill"):FireServer(unpack(args))
end

local function teleport(position, spread)
    position = position or character.PrimaryPart.Position
    spread = (spread and spread > -1) and spread or 5
    if spread > 0 then
        useskill("Teleport", Vector3.new(position.X + math.random(-spread, spread), position.Y, position.Z + math.random(-spread, spread)))
    else
        if character then character.PrimaryPart.CFrame = CFrame.new(position) end
    end
end

local function equipitem(name)
	if not name then return end
	local equipped = Events:WaitForChild("InventoryRF"):InvokeServer().Equipped
	for i=1,#equipped do
		Events:WaitForChild("UnequipItem"):FireServer(equipped[i])
		task.wait(0.1)
		Events:WaitForChild("EquipItem"):FireServer(name)
	end
end

-- local function setup_bodyparts(character, callback)
-- 	if not character or BODY_PARTS.Head == true then return end
-- 	for part in BODY_PARTS do
-- 		part.ChildAdded:Connect(callback)
-- 	end
-- end

-- [[ ПОДСВЕТКА ЦЕЛИ ]]
local Highlight = Instance.new("Highlight")
	Highlight.FillTransparency = 0.85
	Highlight.FillColor = Color3.fromRGB(148, 63, 209)
	Highlight.OutlineColor = STYLE.Highlight
	Highlight.Parent = CoreGui

RunService.RenderStepped:Connect(function()
    if activeScanner then
        Highlight.Enabled = false
        return
    end

    local target = nil
    if Mouse.Target and Mouse.Target.Parent then
        local char = Mouse.Target.Parent:FindFirstChild("Humanoid") and Mouse.Target.Parent or Mouse.Target.Parent.Parent
        if char and Players:FindFirstChild(char.Name) and char:FindFirstChild("Humanoid") and char ~= character then
            target = char
        end
    end
    Highlight.Adornee = target
    Highlight.Enabled = (target ~= nil)
end)

-- [[ КЛАСС СИСТЕМЫ ИНТЕРФЕЙСА (СКАHEР) ]]
local Interaction = {}
Interaction.__index = Interaction

function Interaction.new(targetPlayer)
    if activeScanner then
        activeScanner:Destroy()
    end

    local oldGui = PlayerGui:FindFirstChild("NumericScanner")
    if oldGui then oldGui:Destroy() end

	local self = setmetatable({}, Interaction)
    self.Target = targetPlayer
    self.Gui = Instance.new("ScreenGui", PlayerGui)
    self.Gui.Name = "NumericScanner"
    self.Connections = {}
    
    local targetChar = targetPlayer.Character
    if not targetChar then return end

    activeScanner = self

    -- 1. Создание выносок со статистикой
    for partName, data in pairs(STATS_CONFIG) do
        local part = targetChar:FindFirstChild(partName)
        if part then
            self:CreateNumericCallout(part, data, targetPlayer)
        end
    end

    -- 2. Создание панели действий над головой
    local head = targetChar:FindFirstChild("Head")
    if head and #INTERACTIONS>0 then
        self:CreateActionDock(head, targetPlayer)
    end

    -- Отслеживание дистанции до цели
    local distConn = RunService.Heartbeat:Connect(function()
        if not targetChar or not character or not character.PrimaryPart then 
            self:Destroy() 
            return 
        end
        local dist = (targetChar.PrimaryPart.Position - character.PrimaryPart.Position).Magnitude
        if dist > STYLE.Distance then 
            self:Destroy() 
        end
    end)
    table.insert(self.Connections, distConn)

    return self
end

function Interaction:CreateNumericCallout(part, data, targetPlayer)
    local bgu = Instance.new("BillboardGui", self.Gui)
    bgu.Adornee = part
    bgu.StudsOffset = data.Offset
    bgu.AlwaysOnTop = true
    bgu.Active = true
    bgu.Size = UDim2.fromOffset(100, 45)

    local f = Instance.new("Frame", bgu)
    f.Size = UDim2.fromScale(1, 1)
    f.BackgroundColor3 = STYLE.Bg
    f.BackgroundTransparency = 0.2
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke", f)
    stroke.Color = data.Color
    stroke.Thickness = 1.5

    local title = Instance.new("TextLabel", f)
    title.Size = UDim2.new(1, 0, 0, 18)
    title.Position = UDim2.fromOffset(0, 4)
    title.Text = data.Emoji .. " " .. data.Name
    title.TextColor3 = Color3.fromRGB(200, 200, 200)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 10
    title.BackgroundTransparency = 1
    title.ZIndex = 2

    local valueLabel = Instance.new("TextLabel", f)
    valueLabel.Size = UDim2.new(1, 0, 0, 20)
    valueLabel.Position = UDim2.fromOffset(0, 18)
    valueLabel.Text = "0"
    valueLabel.TextColor3 = data.Color
    valueLabel.Font = Enum.Font.GothamBlack
    valueLabel.TextSize = 14
    valueLabel.BackgroundTransparency = 1
    valueLabel.ZIndex = 2

    local clickBtn = Instance.new("TextButton", f)
    clickBtn.Size = UDim2.fromScale(1, 1)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.ZIndex = 5

    local rawValue = 0
    local function updateValue()
        rawValue = targetPlayer:GetAttribute(data.Attr) or 0
        valueLabel.Text = conv.ToLetters(rawValue, 1)
        valueLabel.TextSize = 18
        TweenService:Create(valueLabel, TweenInfo.new(0.3), {TextSize = 14}):Play()
    end

    -- Эффекты наведения (Ховеры)
    local hoverIn = clickBtn.MouseEnter:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.15), {
            Thickness = 2.5,
            Color = data.Color:Lerp(Color3.new(1, 1, 1), 0.25)
        }):Play()
        TweenService:Create(f, TweenInfo.new(0.15), {BackgroundTransparency = 0.05}):Play()
    end)

    local hoverOut = clickBtn.MouseLeave:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.15), {
            Thickness = 1.5,
            Color = data.Color
        }):Play()
        TweenService:Create(f, TweenInfo.new(0.15), {BackgroundTransparency = 0.2}):Play()
    end)

    table.insert(self.Connections, hoverIn)
    table.insert(self.Connections, hoverOut)

    -- Расчет прозрачности от расстояния камеры
    local camConn = RunService.RenderStepped:Connect(function()
        if not bgu.Parent or not workspace.CurrentCamera then return end
        local camDist = (part.Position - workspace.CurrentCamera.CFrame.Position).Magnitude

        if camDist > STYLE.MaxUiVisibleDistance then
            f.BackgroundTransparency = 1
            title.TextTransparency = 1
            valueLabel.TextTransparency = 1
            stroke.Transparency = 1
        elseif camDist > (STYLE.MaxUiVisibleDistance - 15) then
            local alpha = math.clamp((STYLE.MaxUiVisibleDistance - camDist) / 15, 0, 1)
            f.BackgroundTransparency = 1 - (alpha * 0.8)
            title.TextTransparency = 1 - alpha
            valueLabel.TextTransparency = 1 - alpha
            stroke.Transparency = 1 - alpha
        else
            f.BackgroundTransparency = 0.2
            title.TextTransparency = 0
            valueLabel.TextTransparency = 0
            stroke.Transparency = 0
        end
    end)
    table.insert(self.Connections, camConn)

    -- Копирование при клике
    local clickConn = clickBtn.MouseButton1Click:Connect(function()
        copyToClipboard(valueLabel.Text)
        local originalColor = stroke.Color
        TweenService:Create(stroke, TweenInfo.new(0.08), {Color = STYLE.Success, Thickness = 3}):Play()
        task.delay(0.2, function()
            if stroke.Parent then
                TweenService:Create(stroke, TweenInfo.new(0.3), {Color = originalColor, Thickness = 1.5}):Play()
            end
        end)
    end)
    table.insert(self.Connections, clickConn)

    local attrConn = targetPlayer:GetAttributeChangedSignal(data.Attr):Connect(updateValue)
    table.insert(self.Connections, attrConn)
    
    updateValue()
end

function Interaction:CreateActionDock(head, targetPlayer)
    local bgu = Instance.new("BillboardGui", self.Gui)
    bgu.Adornee = head
    bgu.StudsOffset = Vector3.new(0, 5.0, 0)
    bgu.AlwaysOnTop = true
    bgu.Active = true

    local buttonWidth = 85
    local spacing = 6
    local totalWidth = (#INTERACTIONS * buttonWidth) + ((#INTERACTIONS - 1) * spacing) + 16
    local totalHeight = 40
    bgu.Size = UDim2.fromOffset(totalWidth, totalHeight)

    local mainFrame = Instance.new("Frame", bgu)
    mainFrame.Size = UDim2.fromScale(1, 1)
    mainFrame.BackgroundColor3 = STYLE.Bg
    mainFrame.BackgroundTransparency = 0.25
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
    
    local stroke = Instance.new("UIStroke", mainFrame)
    stroke.Color = STYLE.Accent
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4

    local list = Instance.new("UIListLayout", mainFrame)
    list.FillDirection = Enum.FillDirection.Horizontal
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.Padding = UDim.new(0, spacing)

    local createdButtons = {}

    for _, action in ipairs(INTERACTIONS) do
        local btn = Instance.new("TextButton", mainFrame)
        btn.Size = UDim2.fromOffset(buttonWidth, 28)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        btn.BackgroundTransparency = 0.3
        btn.Text = action.Emoji .. " " .. action.Name
        btn.TextColor3 = STYLE.Text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.AutoButtonColor = false
        
        local btnCorner = Instance.new("UICorner", btn)
        btnCorner.CornerRadius = UDim.new(0, 6)
        
        local btnStroke = Instance.new("UIStroke", btn)
        btnStroke.Color = STYLE.Text
        btnStroke.Thickness = 1
        btnStroke.Transparency = 0.85

        local btnHoverIn = btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = STYLE.Accent, BackgroundTransparency = 0.1}):Play()
            TweenService:Create(btnStroke, TweenInfo.new(0.2), {Transparency = 0.4}):Play()
        end)

        local btnHoverOut = btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(30, 30, 40), BackgroundTransparency = 0.3}):Play()
            TweenService:Create(btnStroke, TweenInfo.new(0.2), {Transparency = 0.85}):Play()
        end)

        local btnClick = btn.MouseButton1Click:Connect(function()
            action.Callback(targetPlayer)
            self:Destroy()
        end)

        table.insert(self.Connections, btnHoverIn)
        table.insert(self.Connections, btnHoverOut)
        table.insert(self.Connections, btnClick)
        table.insert(createdButtons, {btn = btn, stroke = btnStroke})
    end

    local camConn = RunService.RenderStepped:Connect(function()
        if not bgu.Parent or not workspace.CurrentCamera then return end
        local camDist = (head.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
        
        if camDist > STYLE.MaxUiVisibleDistance then
            mainFrame.BackgroundTransparency = 1
            stroke.Transparency = 1
            for _, item in ipairs(createdButtons) do
                item.btn.BackgroundTransparency = 1
                item.btn.TextTransparency = 1
                item.stroke.Transparency = 1
            end
        elseif camDist > (STYLE.MaxUiVisibleDistance - 15) then
            local alpha = math.clamp((STYLE.MaxUiVisibleDistance - camDist) / 15, 0, 1)
            mainFrame.BackgroundTransparency = 1 - (alpha * 0.75)
            stroke.Transparency = 1 - (alpha * 0.6)
            for _, item in ipairs(createdButtons) do
                item.btn.BackgroundTransparency = 1 - (alpha * 0.7)
                item.btn.TextTransparency = 1 - alpha
                item.stroke.Transparency = 1 - (alpha * 0.15)
            end
        else
            mainFrame.BackgroundTransparency = 0.25
            stroke.Transparency = 0.4
            for _, item in ipairs(createdButtons) do
                local isHovering = (UserInputService:GetMouseLocation() - item.btn.AbsolutePosition).Magnitude < 30
                if not isHovering then
                    item.btn.BackgroundTransparency = 0.3
                    item.btn.TextTransparency = 0
                    item.stroke.Transparency = 0.85
                end
            end
        end
    end)
    table.insert(self.Connections, camConn)
end

function Interaction:Destroy()
    for _, conn in ipairs(self.Connections) do
        if conn then conn:Disconnect() end
    end
    self.Gui:Destroy()
    if activeScanner == self then
        activeScanner = nil
    end
end

-- [[ КЛИК-ДЕТЕКТОР ИГРОКОВ ]]
UserInputService.InputBegan:Connect(function(input, proc)
    if proc then return end 

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local targetChar = nil
        if Mouse.Target and Mouse.Target.Parent then
            local c = Mouse.Target.Parent:FindFirstChild("Humanoid") and Mouse.Target.Parent or Mouse.Target.Parent.Parent
            if c and c:FindFirstChild("Humanoid") then
                targetChar = c
            end
        end

        if targetChar then
            local p = Players:GetPlayerFromCharacter(targetChar)
            if p and p ~= LocalPlayer then
                Interaction.new(p)
            end
        else
            if activeScanner then
                activeScanner:Destroy()
            end
        end
    end
end)


-- [[ АВТОМАТИЗАЦИЯ ИГРЫ (ОСНОВНОЙ ФУНКЦИОНАЛ) ]]
local function setupCharacter(char)
	LocalPlayer:SetAttribute("BodyAura", 12)
	LocalPlayer:SetAttribute("FistAura", 1)
    if not char then return end
    char:WaitForChild("Humanoid").Died:Connect(function()
        task.wait(2)
        local btn = LocalPlayer.PlayerGui.IntroGui.PlayButton
        firesignal(btn.MouseButton1Click)
        msg.Mini("Coral", "You have died", 2)
    end)
    char:WaitForChild("Humanoid").Changed:Connect(function(property)
        if property == "MoveDirection" then
			if char.Humanoid[property].Magnitude > 0 then
				if char:FindFirstChild("PsychicPower") then
					add.EquipTool()
				end
			elseif char.Humanoid[property].Magnitude == 0 then
				if states.phychiczone then
					add.EquipTool("PsychicPower")
				end
			end
			if states.farmingpos and add.distTo(states.farmingpos) > 15 then teleport(states.farmingpos, 0) end
        end
    end)
	char:WaitForChild("HumanoidRootPart").Changed:Connect(function(property)
		if property == "Position" or property == "CFrame" then
			if states.farmingpos and add.distTo(states.farmingpos) > 15 then teleport(states.farmingpos, 0) end
		end
	end)
    char.ChildAdded:Connect(function(child)
        if child.Name == "KillingIntentAura" then
            child.Size = Vector3.new(50, 30, 50)
			child.Material = Enum.Material.ForceField
			child.Color = Color3.fromRGB(110, 50, 220)
			child.Transparency = 0.75
            child:WaitForChild("KillingIntentAuraSFX"):Destroy()
            child:WaitForChild("KillingIntentAura"):Destroy()
            child:WaitForChild("KillingIntentAura"):Destroy()
		end
    end)
    Events:WaitForChild("UseSkill"):FireServer("ConcealAura")
	if LocalPlayer.Backpack:FindFirstChild("GhostBike") then LocalPlayer.Backpack.GhostBike:Destroy() end
end
setupCharacter(character)

LocalPlayer.CharacterAdded:Connect(function(char)
    character = char
    setupCharacter(character)
    task.wait(1.5)
    workspace.CurrentCamera.CameraSubject = character.Humanoid
    workspace.CurrentCamera.CameraType = Enum.CameraType.Follow
    LocalPlayer.PlayerGui.MainGui.Enabled = true
    LocalPlayer.PlayerGui.IntroGui.Enabled = false
    Lighting.Blur.Enabled = false
end)

-- Авто-фарм квестов по времени
task.spawn(function()
    while true do task.wait(1)
        for _, qType in pairs({"Daily", "Weekly"}) do
            for _, stat in pairs({"FistStrength", "BodyToughness", "MovementSpeed", "JumpForce", "PsychicPower"}) do
                for i = 1, 12 do task.wait()
                    Events:WaitForChild("TimerQuestClaim"):FireServer(i, stat, qType)
                end
            end
        end
    end
end)

-- Авто-тренировки
task.spawn(function()
    while true do task.wait()
        Events:WaitForChild("FS_Train"):FireServer()
        Events:WaitForChild("BT_Train"):FireServer()
    end
end)

-- Авто-ротация зон
local zones = {
	{
		stat="TPM",
		pos=Vector3.new(193, 248.42, 845),
		item=nil,
		tool=nil,
		skill="KillingIntentAura"
	},
	{
		stat="PsychicPower",
		pos=Vector3.new(-2312, 244.56, -363),
		item="ZeusStrike",
		tool="PsychicPower",
		skill="KillingIntentAura"
	},
	{
		stat="BodyToughness",
		pos=Vector3.new(-1206, 356.79, -3027),
		item="ChampionsTrophy",
		tool=nil,
		skill=nil
	},
	{
		stat="FistStrength",
		pos=Vector3.new(272, 1158.24, -3025),
		item="OrangePlasma",
		tool=nil,
		skill=nil
	},
}
local function changeActivity()
	states.autofarm = true
	while states.autofarm do task.wait()
		if not character then break end
		for _,data in zones do
			local startstat = LocalPlayer:GetAttribute(data.stat)
			states.farmingpos = data.pos; task.wait(0.2)
			if add.distTo(data.pos) > 15 then teleport(data.pos, 5) end
			add.equipTool(data.tool)
			equipitem(data.item)
			repeat task.wait() until not character:FindFirstChild("ForceField")
			task.wait(0.5); useskill(data.skill)
			msg.Mini("Sky", "Activity Changed", 1200, function() states.autofarm = false; states.farmingpos = nil; msg.Mini("Pink", "Click on me to restart", 0, function() changeActivity() end) end); task.wait(1200)
			print(("Farmed %s of %s"):format(conv.ToLetters(LocalPlayer:GetAttribute(data.stat)-startstat), data.stat))
		end
	end
end

-- Players.PlayerAdded:Connect(changeActivity)
-- Players.PlayerRemoving:Connect(changeActivity)

-- Зоны тренировок
for _, box in pairs(workspace.Main.TrainingAreasHitBoxes.PS:GetChildren()) do
    box.CanTouch = true
    box.Touched:Connect(function(part)
        if character and part == character.PrimaryPart then
            states.phychiczone = true
        end
    end)
    box.TouchEnded:Connect(function(part)
        if character and part == character.PrimaryPart then
            states.phychiczone = false
        end
    end)
end

add.chatFilter(function(msg, src)
    local text = msg.Text
	local self = src.UserId == LocalPlayer.UserId
    if self and (text:find("Tokens") or text:find("TPM") or text:find("VIP")) then return false end
    return true
end)

Events:WaitForChild("ChangeRank"):FireServer(9)
ReplicatedStorage:WaitForChild("EquipSavedRaceRF"):InvokeServer()
msg.New("Mint", "Auth", "You have successfully logged in", 10, function()
	changeActivity()
end, "Авто-фарм")
