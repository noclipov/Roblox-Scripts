local int = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Character"):WaitForChild("Interact")
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/additional.lua"))()
add.KeyBinds({
	F1 = function() 
		for i,v in pairs(game.Players:GetChildren()) do
			if not v.Character or v == game.Players.LocalPlayer then continue end
			if v.Character:GetAttribute("Downed") and not v.Character:GetAttribute("Carried") then
				local lastpos = add.tp(v.Character.PrimaryPart.CFrame);task.wait(0.2)
				int:FireServer("Revive", nil, v.Name);task.wait(0.2)
				int:FireServer("Revive", true, v.Name);task.wait(0.1)
				add.tp(lastpos, 0);task.wait(0.2)
			end
		end
	end,
	F2 = function()
		for i,v in pairs(game.Players:GetChildren()) do
			if not v.Character or v == game.Players.LocalPlayer then continue end
			if v.Character:GetAttribute("Downed") and not v.Character:GetAttribute("Carried") then
				local lastpos = add.tp(v.Character.PrimaryPart.CFrame);task.wait(0.2)
				int:FireServer("Carry", nil, v.Name);task.wait(0.2)
				add.tp(lastpos, 0);task.wait(0.3)
				int:FireServer("EndCarry")
				break
			end
		end
	end,
	F3 = function()
		local zones = workspace.Game.Map.SafeZones:GetChildren()
		game.Players.LocalPlayer.Character.PrimaryPart.CFrame = zones[math.random(#zones)].CFrame
	end,
})