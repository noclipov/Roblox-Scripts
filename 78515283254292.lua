local UserInputService = game:GetService("UserInputService")
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/main/Libs/additional.lua"))()
local msg = add.module("notify.lua")
local function base_check_in(window_number, return_object)
	window_number = window_number or 1
	return_object = return_object or false
	if not return_object then
		fireproximityprompt(workspace.Misc["CheckIn"..(window_number==1 and "" or window_number)]:WaitForChild("Form").PP)
		fireproximityprompt(workspace.Misc["CheckIn"..(window_number==1 and "" or window_number)].Camera.PP)
		return false
	else
		return workspace.Misc["CheckIn"..(window_number==1 and "" or window_number)]
	end
end
local function check_in(window_number)
    window_number = window_number or 1
    base_check_in(window_number); task.wait(0.5)
    fireproximityprompt(workspace.Misc.CheckIn.Computer.PP); task.wait(0.1)
    fireproximityprompt(workspace.Misc.CheckIn.Printer.PP); task.wait(0.6)
    local badge = base_check_in(window_number, true):WaitForChild("PrintedBadge")
    repeat task.wait() until badge.PP.Enabled
    local name = base_check_in(window_number, true):WaitForChild("PrintedBadge").Tag.UI.Label.Text
    if workspace.NPCs[name]:GetAttribute("Skinwalker") then
		msg.Mini("Crimson", ("%s (#%s) is an ANOMALY!"):format(name, window_number), 10)
        return
    end
    fireproximityprompt(base_check_in(window_number, true).PrintedBadge:WaitForChild("PP"))
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
