-- [[ ЗАГРУЗКА БИБЛИОТЕК ]]
local conv = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/convs.lua"))()
local msg = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/notify.lua"))()
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/additional.lua"))()
local wsm = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/wsm.lua"))()
local plm = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/playerlist.lua"))()
local scanner = loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Libs/scanner.lua"))()

local ws = wsm.new("ws://localhost:1337/luau", 15)
ws:Start()

add.aa()
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

-- [[ ПЕРЕМЕННЫЕ СОСТОЯНИЯ ]]
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local states = {phychiczone = false, farming = nil, crates = {"Secret"}}
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
	if not name or not character then return end
	local args = {[1]=name} 
	if arg then args[2] = arg end
	Events:WaitForChild("UseSkill"):FireServer(unpack(args))
end

local function teleport(position, spread)
	if not character then return end
    position = position or character.PrimaryPart.Position
    spread = (spread and spread > -1) and spread or 5
	local had_kia
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
	if had_kia then task.spawn(function() task.wait(1); useskill("KillingIntentAura") end) end
	return character.PrimaryPart.Position
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

local function collect_crate(crate, equip_psychic)
	local crate_primary = crate:WaitForChild("Meshes/CRATEFORSPTS_Cube")
    local crate_position = crate_primary.Position
    add.equipTool(); local lastpos=teleport(crate_position, 2)
    task.wait(0.25)
    fireclickdetector(crate_primary:WaitForChild("ClickDetector"), 10)
    task.wait(1); teleport(lastpos, 3)
    if equip_psychic then add.equipTool("PsychicPower") end
end

local function collect_crates(name)
	while workspace:FindFirstChild(name) do
		collect_crate(workspace:FindFirstChild(name), character:FindFirstChild("PsychicPower") and true or false)
		task.wait(2)
	end
end

local function setup_zone(data)
	states.farming = data; task.wait(0.2)
	if data == nil or data == {} then return end
	if add.distTo(data.pos) > 15 then teleport(data.pos, data.spread) end
	add.equipTool(data.tool)
	equipitem(data.item)
	repeat task.wait() until not character:FindFirstChild("ForceField")
	task.wait(0.5); if data.skill_condition and data.skill_condition() or not data.skill_condition then useskill(data.skill) end
end

local function calculateNextPosition(currentPosition, velocity, extra)
    return currentPosition + velocity.Unit*extra
end

scanner.Init({
    Style = {
		Accent = Color3.fromRGB(140, 100, 255),
		Highlight = Color3.fromRGB(180, 160, 255),
		Bg = Color3.fromRGB(15, 15, 20),
		Text = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(100, 255, 100),
		Distance = 60,
		MaxUiVisibleDistance = 80,
	},
	LocalSetup = {
        MaxUiVisibleDistance = 20, -- Твои статы начнут плавно исчезать уже на расстоянии 40 стадс
        Offsets = {
			["Head"] = Vector3.new(1.3, 1.0, 0),
			["UpperTorso"] = Vector3.new(-1.4, 0.2, 0),
			["RightUpperArm"] = Vector3.new(1.4, 0, 0),
        }
    },
    StatsConfig = {
		["Head"] = {Attr = "PsychicPower", Name = "Psychic Power", Emoji = "🧠", Color = Color3.fromRGB(200, 100, 255), Offset = Vector3.new(3, 2, 0)},
		["UpperTorso"] = {Attr = "BodyToughness", Name = "Body Toughness", Emoji = "🛡️", Color = Color3.fromRGB(80, 255, 150), Offset = Vector3.new(-3.5, 0.5, 0)},
		["RightUpperArm"] = {Attr = "FistStrength", Name = "Fist Strength", Emoji = "🦾", Color = Color3.fromRGB(255, 80, 80), Offset = Vector3.new(3.5, 0, 0)},
	},
    Interactions = {
		{
			Name = "Nick", 
			Emoji = "👤", 
			Callback = function(targetPlayer)
				setclipboard(targetPlayer.Name)
			end
		},
		{
			Name = "Squad", 
			Emoji = "👥", 
			Condition = function(targetPlayer)
				local myGang = LocalPlayer:GetAttribute("Gang")
				local targetGang = targetPlayer:GetAttribute("Gang")
				return (myGang ~= nil and myGang ~= "") and myGang ~= targetGang
			end,
			Callback = function(targetPlayer)
				Events.GangRemotes.Invite:FireServer(targetPlayer.UserId)
			end
		},
	},
})

plm.Init({
    {
        Emoji = "👥",
        Condition = function(targetPlayer)
            local myGang = game.Players.LocalPlayer:GetAttribute("Gang")
            return (myGang ~= nil and myGang ~= "")
        end,
        Callback = function(targetPlayer)
            Events.GangRemotes.Invite:FireServer(targetPlayer.UserId)
            msg.Mini("Sky", "Приглашение отправлено игроку " .. targetPlayer.Name, 3)
        end
    },
    {
        Emoji = "💢",
        Condition = function(targetPlayer)
            return targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") and targetPlayer.Character.Humanoid.Health > 0 and targetPlayer:GetAttribute("PsychicPower")*100<=game.Players.LocalPlayer:GetAttribute("PsychicPower")
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

-- [[ АВТОМАТИЗАЦИЯ ИГРЫ (ОСНОВНОЙ ФУНКЦИОНАЛ) ]]
local function setupCharacter(char)
    if not char then return end
    char:WaitForChild("Humanoid").Died:Connect(function()
        msg.Mini("Coral", "You have died", 2); task.wait(2)
        add.toggleCoreGui(Enum.CoreGuiType.PlayerList, true)
        add.toggleCoreGui(Enum.CoreGuiType.Chat, true)
        add.toggleCoreGui(Enum.CoreGuiType.Backpack, true)
        camera.CameraType = Enum.CameraType.Custom
		repeat PlayerGui.IntroGui.Enabled = false
		until not PlayerGui.IntroGui.Enabled
        if LocalPlayer:GetAttribute("CharacterLoaded") then
            for _, gui in pairs({ "MainGui", "QuestsGui" }) do
                PlayerGui[gui].Enabled = true
            end
        end
        Events.RefreshCharacter:FireServer()
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
			setup_zone(states.farming)
        end
    end)
    char.ChildAdded:Connect(function(child)
        if child.Name == "KillingIntentAura" then
            child.Size = Vector3.new(55, 25, 55)
			child.Material = Enum.Material.ForceField
			child.Color = Color3.fromRGB(110, 50, 220)
			child.Transparency = 0.75
            child:WaitForChild("KillingIntentAuraSFX"):Destroy()
            child:WaitForChild("KillingIntentAura"):Destroy()
            child:WaitForChild("KillingIntentAura"):Destroy()
		end
    end)
    useskill("ConcealAura"); task.wait(0.5); add.removeTool("GhostBike"); setup_zone(states.farming)
	camera.CameraSubject = char.Humanoid; camera.CameraType = Enum.CameraType.Custom
    PlayerGui.MainGui.Enabled = true; PlayerGui.IntroGui.Enabled = false; Lighting.Blur.Enabled = false
end
setupCharacter(character)

-- Отслеживание спавна сундуков
workspace.ChildAdded:Connect(function(child)
    if child.Name:find("Crate") then task.wait(0.5)
		local rarity = child:GetAttribute("Rarity")
		if not states.crates or not table.find(states.crates, rarity) then return end
		if Players.numPlayers > 1 then
			msg.Mini("Peach", ("%s Crate has spawned"):format(rarity), 10, function()
				collect_crates(child.Name)
			end)
		else collect_crates(child.Name) end
    end
end)

game:GetService("CoreGui").RobloxGui.NotificationFrame.ChildAdded:Connect(function(child)
    game:GetService("CoreGui").RobloxGui.NotificationFrame.Visible = false
	if not child or #(child:GetChildren()) == 0 then return end
    local title = child.NotificationTitle.Text
    local text = child.NotificationText.Text
	task.wait(0.1)
	child:Destroy()
	msg.New("Vanilla", title, text, 5)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    character = char
    setupCharacter(character)
end)

local spheres = {}
for i,v in pairs(game:GetService("ReplicatedStorage").Visuals.Skills.EnergySpheres:GetChildren()) do table.insert(spheres, v.Name) end

workspace.ChildAdded:Connect(function(child)
    if table.find(spheres, child.Name) then
        local whileloop
        child.Destroying:Connect(function() task.cancel(whileloop) end)
        whileloop = task.spawn(function()
			local mindist =child.Size.X*2.5
            while true do
                local nextpos = calculateNextPosition(child.Position, child.Velocity, 50)
                if add.distTo(nextpos) <= (mindist) or add.distTo(child.Position) <= (mindist) then
					local lastpos 
					repeat lastpos = teleport(Vector3.new(nextpos.X, character.PrimaryPart.Position.Y, nextpos.Z), child.Size.X*3.1)
					until add.distTo(nextpos) > (mindist) and add.distTo(child.Position) > (mindist)
					task.wait(1)
                    teleport(lastpos, 7)
                end
                task.wait()
            end
        end)
    end
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
		stat="FinalTPM",
		pos=Vector3.new(193, 248.42, 845),
		spread=0,
		item=nil,
		tool=nil,
		skill="KillingIntentAura",
		skill_condition = function() return not character:FindFirstChild("KillingIntentAura") end
	},
	{
		stat="PsychicPower",
		pos=Vector3.new(-2312, 244.56, -363),
		spread=10,
		item="ZeusStrike",
		tool="PsychicPower",
		skill="KillingIntentAura",
		skill_condition = function() return character:FindFirstChild("KillingIntentAura") end
	},
	{
		stat="BodyToughness",
		pos=Vector3.new(-1206, 356.79, -3027),
		spread=10,
		item="ChampionsTrophy",
		tool=nil,
		skill=nil
	},
}

local function datatows(delay: number)
	return task.spawn(function()
		while true do
			ws:Send({
				TPM = conv.ToLetters(LocalPlayer:GetAttribute("FinalTPM")),
				PsychicPower = conv.ToLetters(LocalPlayer:GetAttribute("PsychicPower")),
				BodyToughness = conv.ToLetters(LocalPlayer:GetAttribute("BodyToughness")),
			})
			task.wait(delay)
		end
	end)
end

local function changeActivity()
	local farm;
	local upd = datatows(1)
	farm = task.spawn(function()
		states.farming = zones[1]
		while states.farming ~= nil do task.wait()
			if not character then break end
			for _,data in zones do
				setup_zone(data)
				msg.Mini("Wine", "Auto-farm: Working", 3600, function() 
					task.cancel(farm)
					task.cancel(upd)
					if data.skill then useskill(data.skill) end
					setup_zone(nil)
					msg.Mini("Wine", "Auto-farm: Disabled", 0, function() 
						changeActivity() 
					end) 
				end)
				task.wait(3600)
			end
		end
	end)
end

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
msg.New("Mint", "Auth", "You have successfully logged in", 5)
msg.Mini("Sakura", "Auto-farm: Disabled", 0, function()
	changeActivity()
end)