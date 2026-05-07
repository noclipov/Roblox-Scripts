loadstring(game:HttpGet("https://raw.githubusercontent.com/dimanoclip/Roblox-Luas/main/Anti-AFK.lua"))()
local msg = loadstring(readfile("noclipov/NotifyModule.lua"))()
local pls = game.Players
local lp = pls.LocalPlayer
local character = lp.Character or lp.CharacterAdded:Wait()
local states = {phychiczone = false}
local RS = game:GetService("ReplicatedStorage")
local events = RS:WaitForChild("RemoteEvents")
events:WaitForChild("ChangeRank"):FireServer(9)
RS:WaitForChild("EquipSavedRaceRF"):InvokeServer()
local function equip_tool(name)
	if name and lp.Backpack:FindFirstChild(name) then
		lp.Character:WaitForChild("Humanoid"):EquipTool(lp.Backpack[name])
	elseif not name then
		lp.Character:WaitForChild("Humanoid"):UnequipTools()
	end
end
local function teleport(position, spread)
    position = position or character.PrimaryPart.Position
    spread = spread or 20
    events:WaitForChild("UseSkill"):FireServer("Teleport", Vector3.new(position.X+math.random(-spread, spread), position.Y, position.Z+math.random(-spread, spread)))
end
local function collect_crate(crate, equip_psychic)
    local lastpos = character.PrimaryPart.Position
    local last_status = character.PrimaryPart.Anchored
	local crate_primary = crate:WaitForChild("Meshes/CRATEFORSPTS_Cube")
    local crate_position = crate_primary.Position or lastpos
    character.PrimaryPart.Anchored = false
    teleport(crate_position, 2)
    equip_tool()
    task.wait(0.25)
    fireclickdetector(crate_primary:WaitForChild("ClickDetector"), 10)
    task.wait(1)
    teleport(lastpos, 3)
    character.PrimaryPart.Anchored = last_status
    if equip_psychic then equip_tool("PsychicPower") end
end
local function setup_character(char)
	if not char then return end
    char:WaitForChild("Humanoid").Died:Connect(function()
        task.wait(2)
        respawn()
    end)
	char:WaitForChild("Humanoid").Changed:Connect(function(property)
		if property == "MoveDirection" and char.Humanoid[property].Magnitude > 0 then
			if char:FindFirstChild("PsychicPower") then
				equip_tool()
			end
		elseif property == "MoveDirection" and char.Humanoid[property].Magnitude == 0 then
			if states.phychiczone then
				equip_tool("PsychicPower")
			end
		end
	end)
	char.ChildAdded:Connect(function(child)
		if child.Name == "KillingIntentAura" then
			child.Size = Vector3.new(60,60,60)
			child.Material = Enum.Material.ForceField
			child.Color = Color3.fromRGB(90,0,0)
			child.Transparency = 0
			child:WaitForChild("KillingIntentAuraSFX"):Destroy()
			child:WaitForChild("KillingIntentAura"):Destroy()
			child:WaitForChild("KillingIntentAura"):Destroy()
		end
	end)
    events:WaitForChild("UseSkill"):FireServer("ConcealAura")
end
setup_character(character)
local function collect_crates(name)
	while workspace:FindFirstChild("SecretCrate") do
		collect_crate(workspace.SecretCrate, character:FindFirstChild("PsychicPower") and true or false)
		task.wait(2)
	end
end
-- collect_crates()
-- Auto Crates
workspace.ChildAdded:Connect(function(child)
    if child.Name:find("Secret") then
        msg.Mini("Success", ("%s spawned"):format(child.Name), 10)
		-- collect_crates()
    end
end)
local function respawn()
    local lastpos = character.PrimaryPart.CFrame
    msg.Mini("Error", "You have died", 2)
    local btn = lp.PlayerGui.IntroGui.PlayButton
    firesignal(btn.MouseButton1Click)
    -- msg.Mini("Warning", "Teleporting to last pos", 2)
    -- teleport(lastpos, 5)
end
-- Auto Respawn
lp.CharacterAdded:Connect(function(char)
	character = char
	setup_character(character)
    task.wait(2)
    workspace.CurrentCamera.CameraSubject = character.Humanoid
    workspace.CurrentCamera.CameraType = Enum.CameraType.Follow
    lp.PlayerGui.MainGui.Enabled = true
    lp.PlayerGui.IntroGui.Enabled = false
    game:GetService("Lighting").Blur.Enabled = false
end)
-- Auto Grind Stats
task.spawn(function()
    while true do task.wait()
        events:WaitForChild("FS_Train"):FireServer()
        events:WaitForChild("BT_Train"):FireServer()
    end
end)
-- Auto Timed Quests
task.spawn(function()
    while true do task.wait(1)
        for _, type in pairs({"Daily", "Weekly"}) do
            for _1, stat in pairs({"FistStrength", "BodyToughness", "MovementSpeed", "JumpForce", "PsychicPower"}) do
                for i=1,12 do task.wait()
                    events:WaitForChild("TimerQuestClaim"):FireServer(i, stat, type)
                end
            end
        end
    end
end)
for i,v in pairs(workspace.Main.TrainingAreasHitBoxes.PS:GetChildren()) do
	v.CanTouch = true
	v.Touched:Connect(function(part)
		if character and part == character.PrimaryPart then
			states.phychiczone = true
		end
	end)
	v.TouchEnded:Connect(function(part)
		if character and part == character.PrimaryPart then
			states.phychiczone = false
		end
	end)
end
msg.New("Success", "Auth", "Вы успешно вошли в систему", 5)

-- task.wait(2)
-- events:WaitForChild("UseSkill"):FireServer("KillingIntentAura")
-- local function get_multi() return lp:GetAttribute("RaceTPMMultiplier") end
-- local maxm = get_multi()
-- while true do task.wait()
-- 	if not lp.Character then continue end
--     if get_multi() > maxm then break end
--     RS:WaitForChild("RollRaceRF"):InvokeServer()
-- end
-- RS:WaitForChild("SaveRaceRF"):InvokeServer()
