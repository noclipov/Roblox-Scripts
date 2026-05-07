-- https://www.roblox.com/games/72167803024670
local UIS = game:GetService("UserInputService")
local events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
local binds; binds = UIS.InputBegan:Connect(function(a,b)
    if a.KeyCode == Enum.KeyCode.F1 then
        events:WaitForChild("Hit"):FireServer(1)
    elseif a.KeyCode == Enum.KeyCode.F2 then
        events:WaitForChild("Hit"):FireServer(0.9)
    elseif a.KeyCode == Enum.KeyCode.F3 then
        events:WaitForChild("Hit"):FireServer(0.2)
    elseif a.KeyCode == Enum.KeyCode.F4 then
        events:WaitForChild("Hit"):FireServer(0.05)
    elseif a.KeyCode == Enum.KeyCode.F5 then
        binds:Disconnect()
    end
end)
while game.Players.LocalPlayer.Character do task.wait()
    local dodge = game:GetService("Players").LocalPlayer.PlayerGui.Frames.InGame.Dodge
    if dodge.Visible then
        task.wait(0.15)
        events:WaitForChild("Dodge"):FireServer(dodge.TextLabel.Text)
        dodge.Visible = false
    end
end