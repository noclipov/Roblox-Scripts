-- local int = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Character"):WaitForChild("Interact")
-- local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/additional.lua"))()
-- add.KeyBinds({
-- 	F1 = function()
-- 		for i,v in pairs(game.Players:GetChildren()) do
-- 			if not v.Character or v == game.Players.LocalPlayer then continue end
-- 			if v.Character:GetAttribute("Downed") and not v.Character:GetAttribute("Carried") then
-- 				local lastpos = add.tp(v.Character.PrimaryPart.CFrame);task.wait(0.2)
-- 				int:FireServer("Revive", true, v.Name);task.wait(0.2)
-- 				add.tp(lastpos);task.wait(0.2)
-- 			end
-- 		end
-- 	end,
-- 	F2 = function()
-- 		for i,v in pairs(game.Players:GetChildren()) do
-- 			if not v.Character or v == game.Players.LocalPlayer then continue end
-- 			if v.Character:GetAttribute("Downed") and not v.Character:GetAttribute("Carried") then
-- 				local lastpos = add.tp(v.Character.PrimaryPart.CFrame);task.wait(0.2)
-- 				int:FireServer("Carry", nil, v.Name);task.wait(0.1)
-- 				add.tp(lastpos)
-- 				break
-- 			end
-- 		end
-- 	end,
-- 	F3 = function()
-- 		local zones = workspace.Game.Map.SafeZones:GetChildren()
-- 		add.tp(zones[math.random(#zones)].CFrame)
-- 	end,
-- })
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/additional.lua"))()
local msg = add.module("notify.lua")
local UserInputService = game:GetService("UserInputService")
local lp = game.Players.LocalPlayer
local hum = lp.Character and lp.Character.Humanoid or lp.CharacterAdded:Wait() and lp.Character.Humanoid
local IsHoldingJump = false
local function setup_bhop(humanoid)
    humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Landed and IsHoldingJump then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
    msg.New("Purple", "Noclipov scripts","AutoBHOP has been successfully enabled!", 5)
end
setup_bhop(hum)
lp.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid")
    setup_bhop(hum)
end)
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then
        IsHoldingJump = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        IsHoldingJump = false
    end
end)