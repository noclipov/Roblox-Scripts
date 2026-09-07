local UserInputService = game:GetService("UserInputService")
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/additional.lua"))()
local msg = add.module("notify.lua")
msg.Mini("Purple", "Loading script...", 3)
local function detected_anomaly(npc_name)
    msg.Mini("Crimson", ("%s is an ANOMALY!"):format(npc_name), 10)
    fireproximityprompt(workspace.Misc.ShutterButton.PP)
end
local function base_check_in(window_number)
	window_number = window_number or 1
    fireproximityprompt(workspace.Misc["CheckIn"..(window_number==1 and "" or window_number)]:WaitForChild("Form").PP)
    fireproximityprompt(workspace.Misc["CheckIn"..(window_number==1 and "" or window_number)].Camera.PP)
end
local function check_in(window_number)
    window_number = window_number or 1
    if window_number == 1 then base_check_in(window_number) else base_check_in(window_number) end
    task.wait(0.5)
    fireproximityprompt(workspace.Misc.CheckIn.Computer.PP)
    task.wait(0.1)
    fireproximityprompt(workspace.Misc.CheckIn.Printer.PP)
    task.wait(0.6)
    local badge = workspace.Misc["CheckIn"..(window_number == 2 and window_number or "")]:WaitForChild("PrintedBadge")
    repeat task.wait() until badge.PP.Enabled
    local name = workspace.Misc["CheckIn"..(window_number == 2 and window_number or "")].PrintedBadge.Tag.UI.Label.Text
    if workspace.NPCs[name]:GetAttribute("Skinwalker") then
        detected_anomaly(name)
        return
    end
    fireproximityprompt(workspace.Misc.CheckIn:WaitForChild("PrintedBadge"):WaitForChild("PP"))
    task.wait(0.1)
    fireproximityprompt(workspace.NPCs[name].PP)
end
add.KeyBinds({
	Z = function()
        check_in(1)
	end,
	X = function()
        check_in(2)
	end,
})
