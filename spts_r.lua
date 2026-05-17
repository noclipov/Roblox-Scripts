-- ==========================================
-- [1. ЗАГРУЗКА БИБЛИОТЕК И МОДУЛЕЙ]
-- ==========================================
local conv = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/convs.lua"))()
local msg = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/notify.lua"))()
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/additional.lua"))()
local wsm = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/wsm.lua"))()
local plm = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/playerlist.lua"))()
local scanner = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/scanner.lua"))()

local ws = wsm.new("ws://localhost:1337/luau", 15)
ws:Start()
add.afk()
msg.Mini("Magma", "Enable fps control", 15, function()
	add.fpsc()
end)

-- ==========================================
-- [2. СЕРВИСЫ И КОНСТАНТЫ ROBLOX]
-- ==========================================
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
local Events = ReplicatedStorage:WaitForChild("RemoteEvents")

-- ==========================================
-- [3. СОСТОЯНИЕ И ПОТОКИ СКРИПТА]
-- ==========================================
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local states = {phychiczone = false, farming = nil, crates = {"Secret"}}
local farmThread, wsDataThread

-- ==========================================
-- [4. СЛУЖЕБНЫЕ И УТИЛИТАРНЫЕ ФУНКЦИИ]
-- ==========================================
local function copyToClipboard(text)
	local setC = setclipboard or toclipboard or (Clipboard and Clipboard.set)
	if setC then pcall(function() setC(tostring(text)) end) end
end

local function useskill(name, arg)
	if not name or not character then return end
	local args = {name}
	if arg then args[2] = arg end
	Events:WaitForChild("UseSkill"):FireServer(unpack(args))
end

local function teleport(position, spread)
	if not character or not character.PrimaryPart then return end
	position = position or character.PrimaryPart.Position
	spread = (spread and spread > -1) and spread or 5
	
	local had_kia = false
	if character:FindFirstChild("KillingIntentAura") then
		useskill("KillingIntentAura")
		had_kia = true
		task.wait(0.1)
	end

	if spread > 0 then
		useskill("Teleport", Vector3.new(position.X + math.random(-spread, spread), position.Y, position.Z + math.random(-spread, spread)))
	else
		character.PrimaryPart.CFrame = CFrame.new(position)
	end

	if had_kia then 
		task.spawn(function() 
			task.wait(0.5) 
			if character and not character:FindFirstChild("KillingIntentAura") then useskill("KillingIntentAura") end
		end) 
	end
	return character.PrimaryPart.Position
end

local function equipitem(name)
	if not name then return end
	local success, inventory = pcall(function() return Events:WaitForChild("InventoryRF"):InvokeServer() end)
	if not success or not inventory then return end
	
	for _, item in ipairs(inventory.Equipped) do
		Events:WaitForChild("UnequipItem"):FireServer(item)
		task.wait(0.05)
		Events:WaitForChild("EquipItem"):FireServer(name)
	end
end

-- ==========================================
-- [5. ЛОГИКА СУНДУКОВ И ТРЕНИРОВОЧНЫХ ЗОН]
-- ==========================================
local function setup_zone(data)
	states.farming = data
	if data == nil or next(data) == nil then return end
	if not character or not character.PrimaryPart then return end
	
	if add.distTo(data.pos) > 15 then teleport(data.pos, data.spread) end
	add.equipTool(data.tool)
	equipitem(data.item)
	
	repeat task.wait(0.1) until not character:FindFirstChild("ForceField")
	
	if data.skill and (not data.skill_condition or data.skill_condition()) then 
		useskill(data.skill) 
	end
end

local function collect_crate(crate, equip_psychic)
	local crate_primary = crate:WaitForChild("Meshes/CRATEFORSPTS_Cube", 5)
	if not crate_primary then return end
	
	add.equipTool()
	local lastpos = teleport(crate_primary.Position, 2)
	task.wait(0.2)
	
	if crate_primary:FindFirstChild("ClickDetector") then fireclickdetector(crate_primary.ClickDetector, 10) end
	task.wait(0.8)
	if states.farming~=nil then setup_zone(states.farming)
	else teleport(lastpos, 3) end
	
	if equip_psychic then add.equipTool("PsychicPower") end
end

local function collect_crates(name)
	while workspace:FindFirstChild(name) do
		local crate = workspace:FindFirstChild(name)
		if crate then collect_crate(crate, character:FindFirstChild("PsychicPower") and true or false) end
		task.wait(1)
	end
end

-- ==========================================
-- [6. ИНИЦИАЛИЗАЦИЯ ИНТЕРФЕЙСОВ (UI)]
-- ==========================================
scanner.Init({
	Style = {
		Accent = Color3.fromRGB(140, 100, 255), Highlight = Color3.fromRGB(180, 160, 255),
		Bg = Color3.fromRGB(15, 15, 20), Text = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(100, 255, 100), Distance = 40, MaxUiVisibleDistance = 60,
	},
	LocalSetup = {
		MaxUiVisibleDistance = 30,
		Offsets = {
			["RightUpperArm"] = Vector3.new(1.4, 0, 0),
			["UpperTorso"] = Vector3.new(-1.4, 0.2, 0),
			["Head"] = Vector3.new(1.3, 1.0, 0),
		}
	},
	StatsConfig = {
		["RightUpperArm"] = {Attr = "FistStrength", Name = "Fist Strength", Emoji = "🦾", Color = Color3.fromRGB(255, 80, 80), Offset = Vector3.new(3.5, 0, 0)},
		["UpperTorso"] = {Attr = "BodyToughness", Name = "Body Toughness", Emoji = "🛡️", Color = Color3.fromRGB(80, 255, 150), Offset = Vector3.new(-3.5, 0.5, 0)},
		["Head"] = {Attr = "PsychicPower", Name = "Psychic Power", Emoji = "🧠", Color = Color3.fromRGB(200, 100, 255), Offset = Vector3.new(3, 2, 0)},
	},
	Interactions = {
		{Name = "Nick", Emoji = "👤", 
			Callback = function(targetPlayer) copyToClipboard(targetPlayer.Name) end
		},
		{Name = "Squad", Emoji = "👥", 
			Condition = function(targetPlayer)
				local myGang = LocalPlayer:GetAttribute("Gang")
				local targetGang = targetPlayer:GetAttribute("Gang")
				return (myGang ~= "Not In A Clan") and myGang ~= targetGang
			end,
			Callback = function(targetPlayer) Events.GangRemotes.Invite:FireServer(targetPlayer.UserId) end
		},
	},
})

plm.Init({
	{
		Emoji = "👥",
		Condition = function() local g = LocalPlayer:GetAttribute("Gang") return g and g ~= "" end,
		Callback = function(targetPlayer)
			Events.GangRemotes.Invite:FireServer(targetPlayer.UserId)
			msg.Mini("Sky", "Приглашение отправлено игроку " .. targetPlayer.Name, 3)
		end
	},
	{
		Emoji = "💢",
		Condition = function(targetPlayer)
			return targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") 
				and targetPlayer.Character.Humanoid.Health > 0 
				and (targetPlayer:GetAttribute("PsychicPower") or 0) * 100 <= (LocalPlayer:GetAttribute("PsychicPower") or 0)
		end,
		Callback = function(targetPlayer)
			local char = targetPlayer.Character
			if char and char:FindFirstChild("HumanoidRootPart") and not char:FindFirstChildOfClass("ForceField") then
				Events.UseSkill:FireServer("HellFire", char)
				msg.Mini("Wine", "Пытаемся сжечь " .. targetPlayer.Name, 3)
			end
		end
	},
}, "Left", Enum.KeyCode.Delete)

-- ==========================================
-- [7. УПРАВЛЕНИЕ ЖИЗНЕННЫМ ЦИКЛОМ ПЕРСОНАЖА]
-- ==========================================
local function setupCharacter(char)
	if not char then return end
	
	char:WaitForChild("Humanoid").Died:Connect(function()
		msg.Mini("Coral", "You have died", 2)
		task.wait(2)
		add.toggleCoreGui(Enum.CoreGuiType.PlayerList, true)
		add.toggleCoreGui(Enum.CoreGuiType.Chat, true)
		add.toggleCoreGui(Enum.CoreGuiType.Backpack, true)
		camera.CameraType = Enum.CameraType.Custom
		
		if PlayerGui:FindFirstChild("IntroGui") then PlayerGui.IntroGui.Enabled = false end
		if LocalPlayer:GetAttribute("CharacterLoaded") then
			for _, gName in ipairs({ "MainGui", "QuestsGui" }) do
				if PlayerGui:FindFirstChild(gName) then PlayerGui[gName].Enabled = true end
			end
		end
		Events.RefreshCharacter:FireServer()
	end)
	
	char.Humanoid.Changed:Connect(function(property)
		if property == "MoveDirection" then
			if char.Humanoid.MoveDirection.Magnitude > 0 then
				if char:FindFirstChild("PsychicPower") then add.EquipTool() end
			elseif char.Humanoid.MoveDirection.Magnitude == 0 then
				if states.phychiczone then add.EquipTool("PsychicPower") end
			end
			setup_zone(states.farming)
		end
	end)
	
	char.ChildAdded:Connect(function(child)
		if child.Name == "KillingIntentAura" then
			child.Size = Vector3.new(55, 25, 55)
			child.Material = Enum.Material.ForceField
			child.Color = Color3.fromRGB(110, 50, 220)
			child.Transparency = 0.75
			
			local sfx = child:WaitForChild("KillingIntentAuraSFX", 2) if sfx then sfx:Destroy() end
			for _, auraPart in ipairs(child:GetChildren()) do
				if auraPart.Name == "KillingIntentAura" then auraPart:Destroy() end
			end
		end
	end)
	
	useskill("ConcealAura")
	Events:WaitForChild("ChangeRank"):FireServer(9)
	task.wait(0.3)
	add.removeTool("GhostBike")
	setup_zone(states.farming)
	
	camera.CameraSubject = char.Humanoid
	camera.CameraType = Enum.CameraType.Custom
	PlayerGui.MainGui.Enabled = true
	if PlayerGui:FindFirstChild("IntroGui") then PlayerGui.IntroGui.Enabled = false end
	Lighting.Blur.Enabled = false
end

setupCharacter(character)
LocalPlayer.CharacterAdded:Connect(function(char)
	character = char
	setupCharacter(character)
end)

-- ==========================================
-- [8. ПЕРЕХВАТ УВЕДОМЛЕНИЙ И СОБЫТИЙ МИРА]
-- ==========================================
local notificationFrame = CoreGui:WaitForChild("RobloxGui"):WaitForChild("NotificationFrame")
notificationFrame.Visible = false

notificationFrame.ChildAdded:Connect(function(child)
	local titleLabel = child:WaitForChild("NotificationTitle", 2)
	local textLabel = child:WaitForChild("NotificationText", 2)
	
	if titleLabel and textLabel then
		local title, text = titleLabel.Text, textLabel.Text
		child:Destroy() 
		msg.New("Vanilla", title, text, 5)
	end
end)

workspace.ChildAdded:Connect(function(child)
	if child.Name:find("Crate") then 
		task.wait(0.3)
		local rarity = child:GetAttribute("Rarity")
		if not states.crates or not table.find(states.crates, rarity) then return end
		
		if Players.numPlayers > 1 then
			msg.Mini("Peach", ("%s Crate has spawned"):format(rarity), 10, function() collect_crates(child.Name) end)
		else 
			collect_crates(child.Name) 
		end
	end
end)

-- ==========================================
-- [9. ПОТОКИ АВТОМАТИЗАЦИИ И СЕТЕВАЯ ДАТА]
-- ==========================================
task.spawn(function()
	while true do 
		task.wait(5)
		for _, qType in ipairs({"Daily", "Weekly"}) do
			for _, stat in ipairs({"FistStrength", "BodyToughness", "MovementSpeed", "JumpForce", "PsychicPower"}) do
				for i = 1, 12 do Events:WaitForChild("TimerQuestClaim"):FireServer(i, stat, qType) end
			end
		end
	end
end)

task.spawn(function()
	while true do 
		Events:WaitForChild("FS_Train"):FireServer()
		Events:WaitForChild("BT_Train"):FireServer()
		task.wait(0.1)
	end
end)

local zones = {
	{
		stat = "FinalTPM",
		pos = Vector3.new(193, 248.42, 845),
		spread = 0,
		item = nil,
		tool = nil,
		skill = "KillingIntentAura",
		skill_condition = function() return character and not character:FindFirstChild("KillingIntentAura") end,
		time=3600*2
	},
	{
		stat = "PsychicPower",
		pos = Vector3.new(-2312, 244.56, -363),
		spread = 10,
		item = "ZeusStrike",
		tool = "PsychicPower",
		skill = "KillingIntentAura",
		skill_condition = function() return character and character:FindFirstChild("KillingIntentAura") end,
		time=3600
	},
	{
		stat = "BodyToughness",
		pos = Vector3.new(-1206, 356.79, -3027),
		spread = 10,
		item = "ChampionsTrophy",
		tool = nil,
		skill = nil,
		time=3600
	},
}

local function datatows(delay)
	if wsDataThread then task.cancel(wsDataThread) end
	wsDataThread = task.spawn(function()
		while true do
			pcall(function()
				ws:Send({
					TPM = conv.ToLetters(LocalPlayer:GetAttribute("FinalTPM") or 0),
					PsychicPower = conv.ToLetters(LocalPlayer:GetAttribute("PsychicPower") or 0),
					BodyToughness = conv.ToLetters(LocalPlayer:GetAttribute("BodyToughness") or 0),
				})
			end)
			task.wait(delay)
		end
	end)
end

local function changeActivity()
	if farmThread then task.cancel(farmThread) end
	datatows(1)
	
	farmThread = task.spawn(function()
		while true do
			for _, data in ipairs(zones) do
				setup_zone(data)
				msg.Mini("Wine", "Auto-farm: Working", data.time, function() 
					if farmThread then task.cancel(farmThread) end
					if wsDataThread then task.cancel(wsDataThread) end
					if data.skill then useskill(data.skill) end
					setup_zone(nil)
					msg.Mini("Wine", "Auto-farm: Disabled", 0, function() changeActivity() end) 
				end)
				task.wait(data.time)
			end
		end
	end)
end

for _, box in pairs(workspace.Main.TrainingAreasHitBoxes.PS:GetChildren()) do
	box.CanTouch = true
	box.Touched:Connect(function(part) if character and part == character.PrimaryPart then states.phychiczone = true end end)
	box.TouchEnded:Connect(function(part) if character and part == character.PrimaryPart then states.phychiczone = false end end)
end

add.chatFilter(function(msg, src)
    local text = msg.Text
    if src.UserId == LocalPlayer.UserId and (text:find("Tokens") or text:find("TPM") or text:find("VIP")) then return false 
	elseif src.UserId == LocalPlayer.UserId and text:find("just unboxed a") then return false
	end
    return true
end, false)

-- ==========================================
-- [10. СТАРТОВАЯ ИНИЦИАЛИЗАЦИЯ РАНГА]
-- ==========================================

msg.New("Mint", "Auth", "You have successfully logged in", 5)
msg.Mini("Sakura", "Auto-farm: Disabled", 0, function() changeActivity() end)