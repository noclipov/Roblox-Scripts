while not game.IsLoaded do task.wait() end
local pls = game.Players
local lp = pls.LocalPlayer
while not lp do task.wait() lp = game.Players.LocalPlayer end
local char = lp.Character or lp.CharacterAdded:Wait() and lp.Character
local mypp = char.PrimaryPart
lp.CharacterAdded:Connect(function(character)
    char = character
    mypp = character.PrimaryPart
end)
local function getping() return lp:GetNetworkPing()*2000 end
local CurCam = workspace.CurrentCamera
task.wait(1)
local add = loadstring(game:HttpGet("https://raw.githubusercontent.com/Dimanoname/Roblox-Luas/main/Libs/additional.lua"))()
local msg = loadstring(game:HttpGet("https://raw.githubusercontent.com/Dimanoname/Roblox-Luas/main/Libs/msgs.lua"))()
local vinp = loadstring(game:HttpGet("https://raw.githubusercontent.com/Dimanoname/Roblox-Luas/main/Libs/vinp.lua"))()
local PlayerModule = lp.PlayerScripts:WaitForChild("PlayerModule")
local cameras, MouseLockController
if hookmetamethod then
    Cameras = require(PlayerModule):GetCameras()
    MouseLockController = Cameras.activeMouseLockController
end
local UIS = game:GetService("UserInputService")
local pgui = lp:WaitForChild("PlayerGui")
local RP = game:GetService("ReplicatedStorage")
local function teamcheck(player)
    return player.Team ~= lp.Team
end
local volleyball_ids = {
    ["74691681039273"] = true,
    ["73956553001240"] = true,
    ["103521881639626"] = true,
    ["109684591839194"] = true,
    ["134314141048307"] = true,
    ["96802054849934"] = true,
}
-- setclipboard(string.format("game:GetService('TeleportService'):TeleportToPlaceInstance(%s, '%s', game.Players.LocalPlayer)", tostring(game.PlaceId), game.JobId))
if volleyball_ids[tostring(game.PlaceId)] then
    while not lp:GetAttribute("User_Level") do task.wait() end
    task.wait(0.5)
    game.StarterGui:SetCore("ChatActive", false)
    -- Variables
    local Styles = RP.Content.Style
    local Abilities = RP.Content.Ability
    local Rarities = require(RP.Content.Rarity)
    local closest = {nil, 1e99}
    local lastserver, antishiftlock, superhitbox, targethl, setter_mode, spike_hack, ball, autoset, autospike
    local services = RP:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_knit@1.7.0"):WaitForChild("knit"):WaitForChild("Services")
    -- Misc
    local toggle_advs = services.GameService.RF.ToggleAdvancedMoves
    local jersey = services.JerseyService.RF.RequestJerseyUpdate
    local settings = services.SettingsService.RF.ChangeSetting
    local keybind = services.SettingsService.RF.UpdateKeybind
    -- Hooks
    local serve = services.GameService.RF.Serve
    local interact = services.BallService.RF.Interact
    local ping = services.EngineSchedulerService.RF.Ping
    local hitbox = services.BallService.RF.CreateHitbox
    local spawnball = services.BallService.RF.SpawnBall
    -- Binds
    local claim_rewards = services.LevelService.RF.ClaimLevelRewards
    local request_teleport = services.PartyService.RF.RequestTeleport
    local return_to_lobby = services.GameService.RF.ReturnPartyToLobby
    local high_ping = services.RankedService.RF.RetryServerVote
    -- Chat Commands
    local callbacks = {
        ["2v2"] = function() request_teleport:InvokeServer("Twos") end,
        ["requeue"] = function() return_to_lobby:InvokeServer(true) end,
        ["return"] = function() return_to_lobby:InvokeServer(false) end,
        ["setter mode"] = function() setter_mode = not setter_mode; if targethl then targethl:Destroy() end end
    }
    local commands = {
        ["!2s"] = callbacks["2v2"],
        ["!2"] = callbacks["2v2"],
        ["!req"] = callbacks["requeue"],
        ["req?"] = callbacks["requeue"],
        ["again?"] = callbacks["requeue"],
        ["!re"] = callbacks["requeue"],
        ["!back"] = callbacks["return"],
        ["gg"] = callbacks["return"],
        ["wp"] = callbacks["return"],
        ["!lobby"] = callbacks["return"],
        ["!hub"] = callbacks["return"],
        ["i set"] = callbacks["setter mode"],
        ["you set"] = callbacks["setter mode"],
        ["are you a setter?"] = callbacks["setter mode"],
    }
    -- Functions
    local function getlvl() return tonumber(lp:GetAttribute("User_Level")) end
    local function ingame() return lp:GetAttribute("Gameplay_InGame") end
    local function enableadvmoves() local text = pgui:WaitForChild("Interface"):WaitForChild("TeamSelection"):WaitForChild("Options"):WaitForChild("AdvancedMoves"):WaitForChild("Text"); if text.Text:find("OFF") then toggle_advs:InvokeServer() end end
    local function getball()
        for i,v in pairs(workspace:GetChildren()) do
            if v.Name:find("CLIENT_BALL") then return v end
        end
        return nil
    end
    local function activeballid()
        return getball():GetAttribute("Id")
    end
    local function rotate_to_cam()
        local hum = lp.Character.Humanoid
        local prim = lp.Character.PrimaryPart
        local c1 = prim.CFrame
        local c2 = CurCam.CFrame
        prim.CFrame = CFrame.lookAlong(c1.Position, Vector3.new(c2.LookVector.x,c1.LookVector.y,c2.LookVector.z))
    end
    local function is_midair(ply)
        ply = ply or lp
        return ply.Character.Humanoid.FloorMaterial == Enum.Material.Air
    end
    local function get_style(ply)
        ply = ply or lp
        return ply:GetAttribute("Gameplay_Style")
    end
    local function get_actual_style(ply)
        ply = ply or lp
        local style = get_style(ply)
        local style_module = Styles:FindFirstChild(style)
        if not style_module then return end
        style_module = require(style_module)
        return {style_module.DisplayName, Rarities.Data[style_module.Rarity].Name}
    end
    local function get_ability(ply)
        ply = ply or lp
        return ply:GetAttribute("Gameplay_Ability")
    end
    local function get_ability_state(ply)
        ply = ply or lp
        local ability = get_ability(ply)
        local charge = ply:GetAttribute("Ability_Charge")
        local module_ability = Abilities:FindFirstChild(ability)
        if not charge or not module_ability then return end
        local max = require(module_ability).Conditions.Charge
        return charge >= max
    end
    local function update_hitbox(size, color)
        local hitbox
        color = color or Color3.fromRGB(180, 0, 255)
        ball = getball()
        if ball then
            hitbox = ball:FindFirstChild("HitBox")
            if hitbox then 
                hitbox.Size = Vector3.new(ball.PrimaryPart.Size.X*size, ball.PrimaryPart.Size.Y*size, ball.PrimaryPart.Size.Z*size)
                hitbox.Color = color
            else
                hitbox = Instance.new("Part", ball)
                hitbox.Name = "HitBox"
                hitbox.Material = Enum.Material.ForceField
                hitbox.Color = color
                hitbox.CFrame = ball.PrimaryPart.CFrame
                hitbox.Anchored = true
                hitbox.CanCollide = false
                hitbox.CanTouch = true
                hitbox.Transparency = 1
                hitbox.Shape = Enum.PartType.Ball
                hitbox.Size = Vector3.new(ball.PrimaryPart.Size.X*size, ball.PrimaryPart.Size.Y*size, ball.PrimaryPart.Size.Z*size)
            end
            return hitbox
        end
        return nil
    end
    if getlvl() < 5 then waitinglvl5 = true else enableadvmoves() end
    -- Main code
    local recieves = {["Dive"] = true, ["Bump"] = true, ["Set"] = true, ["JumpSet"] = false}
    local attack = {["Spike"] = true,  ["JumpSet"] = true, ["Block"] = true}
    -- Events
    pls.PlayerAdded:Connect(function(ply)
        ply:SetAttribute("LineColor", Color3.fromRGB(255,255,255))
    end)
    pls.PlayerRemoving:Connect(function(ply)
        if workspace:FindFirstChild("lines") then
            if workspace.lines:FindFirstChild(ply.Name) then
                workspace.lines[ply.Name]:Destroy()
            end
        end
    end)
    RP.AttributeChanged:Connect(function(attr)
        if attr == "IsBallInPlay" then
            antishiftlock = RP:GetAttribute("IsBallInPlay")
            superhitbox = true
        end
        if attr == "ServedByPlayer" then
            local serveguy = RP:GetAttribute("ServedByPlayer")
            if lastserver and lastserver ~= serveguy and pls:FindFirstChild(lastserver) then pls[lastserver]:SetAttribute("LineColor", Color3.fromRGB(255,255,255)) end
            if serveguy ~= "" and serveguy ~= nil then
                pls[serveguy]:SetAttribute("LineColor", Color3.fromRGB(70, 0, 255))
            end
            lastserver = serveguy
        end
        if attr == "LastHitter" then
            if recieves[RP:GetAttribute("LastHitType")] and RP:GetAttribute("TeamHitStreak") >= 1 and RP:GetAttribute("LastHitTeam") == tostring(lp.Team) then
                antishiftlock = true
                superhitbox = false
            elseif RP:GetAttribute("LastHitType") == "Spike" or RP:GetAttribute("LastHitTeam") ~= tostring(lp.Team) then
                antishiftlock = false
                superhitbox = true
            end
        end
    end)
    workspace.ChildAdded:Connect(function(child)
        if child == getball() then
            ball = child
            child:WaitForChild("HitBox").Touched:Connect(function(part)
                if part.Parent == lp.Character then
                    if RP:GetAttribute("LastHitTeam") ~= tostring(lp.Team) and attack[RP:GetAttribute("LastHitType")] then
                        if child.PrimaryPart.CFrame.Position.Y >= lp.Character.PrimaryPart.CFrame.Position.Y then
                            if not setter_mode and is_midair() or not is_midair() then
                                vinp.CenterMouseClick()
                            end
                        else
                            if is_midair() then
                                autoset = true
                                vinp.PressKey(Enum.KeyCode.Q)
                            end
                        end
                    elseif not setter_mode and is_midair() and RP:GetAttribute("LastHitter") ~= lp.Name and RP:GetAttribute("LastHitTeam") == tostring(lp.Team) and (attack[RP:GetAttribute("LastHitType")] or recieves[RP:GetAttribute("LastHitType")] or RP:GetAttribute("LastHitType") == "Block") then
                        vinp.CenterMouseClick()
                    end
                end
            end)
        end
    end)
    -- Binds
    UIS.InputBegan:Connect(function(a,b)
        if a.KeyCode == Enum.KeyCode.Space and not b then
            pcall(function()
                if lp.Character.Humanoid.FloorMaterial ~= Enum.Material.Air and MouseLockController:GetIsMouseLocked()  then
                    local c1 = lp.Character.PrimaryPart.CFrame
                    local last_height = c1.Position.Y
                    rotate_to_cam()
                    antishiftlock = false
                    repeat task.wait() until c1.Position.Y < last_height
                end
            end)
        elseif a.KeyCode == Enum.KeyCode.LeftControl and not b then
            superhitbox = false
            antishiftlock = false
        end
        if a.KeyCode == Enum.KeyCode.F1 and not b then
            setter_mode = false
            spike_hack = false
            msg.Notify("Special modes", "Disabled", 0.3)
            if targethl then targethl:Destroy() end
        elseif a.KeyCode == Enum.KeyCode.F2 and not b then
            if not ingame() then request_teleport:InvokeServer("Twos") end
        elseif a.KeyCode == Enum.KeyCode.F3 and not b then
            if not ingame() then return_to_lobby:InvokeServer(true)
            elseif pgui.Interface.Game.RetryServerVote.Visible == true then high_ping:InvokeServer(true)
            else setter_mode = not setter_mode; if targethl then targethl:Destroy() end; msg.Notify("Setter mode", setter_mode and "Enabled" or "Disabled", 0.3) end
        elseif a.KeyCode == Enum.KeyCode.F4 and not b then
            if not ingame() then return_to_lobby:InvokeServer(false)
            elseif pgui.Interface.Game.RetryServerVote.Visible == true then high_ping:InvokeServer(false)
            else spike_hack = not spike_hack; msg.Notify("Adv. spike mode", spike_hack and "Enabled" or "Disabled", 0.3) end
        end
        if a.KeyCode == Enum.KeyCode.One and not b then
            powerpreset = 0.3
            msg.Notify("Power Preset", "0.3", 0.3)
        elseif a.KeyCode == Enum.KeyCode.Two and not b then
            powerpreset = 0.5
            msg.Notify("Power Preset", "0.5", 0.3)
        elseif a.KeyCode == Enum.KeyCode.Three and not b then
            powerpreset = 0.8
            msg.Notify("Power Preset", "0.8", 0.3)
        elseif a.KeyCode == Enum.KeyCode.Four and not b then
            powerpreset = nil
            msg.Notify("Power Preset", "Disabled", 0.3)
        end
    end)
    -- Chat Commands
    lp.Chatted:Connect(function(message, target)
        if target then return end
        if commands[message] then commands[message]()
        else game.StarterGui:SetCore("ChatActive", false)
        end
    end)
    -- Game Settings
    settings:InvokeServer("Music", false)
    settings:InvokeServer("Haptics", false)
    settings:InvokeServer("RarityCutscene", false)
    settings:InvokeServer("NightMode", true)
    settings:InvokeServer("BubbleChat", false)
    keybind:InvokeServer("E", true, "Block")
    keybind:InvokeServer("Q", true, "JumpSet")
    -- hookmetamethod
    task.spawn(function()
        if hookmetamethod then
            task.wait(2)
            local hook_handler
            hook_handler = hookmetamethod(game, "__namecall", function(self, ...)
                local args = {...}
                if self == interact and (args[1]["Move"] == "Bump" or args[1]["Move"] == "Set") then
                    superhitbox = false
                    local move = args[1]["Move"]
                    return hook_handler(self, {
                            ["Charge"] = move == "Bump" and 0 or 1,
                            ["Move"] = move,
                            ["SpecialCharge"] = 0,
                            ["TiltDirection"] = Vector3.yAxis,
                            ["BallId"] = args[1]["BallId"],
                            ["MoveDirection"] = Vector3.zero,
                            ["Key"] = args[1]["Key"],
                            ["From"] = "Client",
                            ["LookVector"] = CurCam.CFrame.LookVector,
                            ["ClientCanRunSpecial"] = false
                        })
                elseif self == hitbox and (args[1]["Move"] == "Bump" or args[1]["Move"] == "Set") then
                    superhitbox = false
                    local move = args[1]["Move"]
                    return hook_handler(self, {
                        ["BallId"] = args[1]["BallId"],
                        ["Charge"] = move == "Bump" and 0 or 1,
                        ["Key"] = args[1]["Key"],
                        ["ClientTimestamp"] = args[1]["ClientTimestamp"],
                        ["Move"] = move
                    })
                elseif self == interact and (args[1]["Move"] == "Spike") then
                    return hook_handler(self, {
                        ["Charge"] = powerpreset or args[1]["Charge"],
                        ["Move"] = args[1]["Move"],
                        ["SpecialCharge"] = args[1]["SpecialCharge"],
                        ["TiltDirection"] = args[1]["TiltDirection"],
                        ["BallId"] = args[1]["BallId"],
                        ["MoveDirection"] = args[1]["MoveDirection"],
                        ["ClientCanRunSpecial"] = true,
                        ["From"] = args[1]["From"],
                        ["LookVector"] = (spike_hack) and CurCam.CFrame.LookVector or args[1]["LookVector"]
                    })
                elseif self == interact and (args[1]["Move"] == "JumpSet") then
                    local tilt = args[1]["TiltDirection"]
                    local set_assist = true
                    if tilt ~= Vector3.yAxis then set_assist = false end
                    local final
                    local max_dist = 64
                    if closest[1] and setter_mode then
                        local target = closest[1]
                        local part = target
                        local vel,rot = part.Velocity,part.CFrame.Rotation
                        if vel ~= Vector3.zero then
                            local speed,dir = vel.Magnitude,vel.Unit
                            local dist = 2 +(speed*0.7)
                            local offset = dir*dist
                            final = part.CFrame.Position+offset
                            local min = math.floor(part.Position.Z) < 0 and -4 or 4
                            local fz = math.clamp(final.Z, min<4 and -math.huge or min, min<4 and min or math.huge)
                            final = Vector3.new(final.X, part.Position.Y, fz < 0 and math.min(fz, min) or math.max(fz, min))
                            final = CFrame.new(final + target.CFrame.LookVector, final)
                            final = final.Position
                            tilt = tilt == Vector3.yAxis and (final-ball.PrimaryPart.Position).Unit or tilt
                        else
                            local actpos = Vector3.new(target.Position.x, target.Position.y, target.Position.z)
                            final = CFrame.new(actpos + target.CFrame.LookVector, actpos)
                            final = final.Position
                            tilt = tilt == Vector3.yAxis and (final-ball.PrimaryPart.Position).Unit or tilt
                        end
                        closest = {nil, 1e99}
                    elseif not setter_mode and autoset then
                        tilt = Vector3.yAxis
                        autoset = false
                    end
                    local dist = final and add.dist_to(final) or max_dist
                    return hook_handler(self, {
                        ["Charge"] = set_assist and (dist < max_dist and dist/max_dist or 1) or args[1]["Charge"],
                        ["Move"] = args[1]["Move"],
                        ["SpecialCharge"] = args[1]["SpecialCharge"],
                        ["TiltDirection"] = tilt,
                        ["BallId"] = args[1]["BallId"],
                        ["MoveDirection"] = args[1]["MoveDirection"],
                        ["ClientCanRunSpecial"] = true,
                        ["From"] = args[1]["From"],
                        ["LookVector"] = args[1]["LookVector"]
                    })
                elseif self == ping then 
                    return hook_handler(self, args[1], {})
                elseif self == serve then 
                    return hook_handler(self, args[1]*1.4, powerpreset or 1)
                elseif self == spawnball then
                    if args[1] then
                        return hook_handler(self, args[1]*1.4)
                    else
                        return hook_handler(self, ...)
                    end
                end
                return hook_handler(self, ...)
            end)
        end
    end)
    -- Loop #1 (Ball Hitbox)
    task.spawn(function()
        while game:GetService("RunService").RenderStepped:Wait() do
            if lp.Character:FindFirstChild("Humanoid") then
                update_hitbox((superhitbox and 5 or is_midair() and 2 or 1.7)+(math.floor((getping()-50)/50)))
            end
            if hookmetamethod and antishiftlock then UserSettings():GetService("UserGameSettings").RotationType = Enum.RotationType.MovementRelative end
            if closest[1] and setter_mode then
                local target = closest[1]
                local camera_lv = CurCam.CFrame.LookVector
                local hit_dist = math.floor((target.Position-(mypp.Position+Vector3.new(camera_lv.X, mypp.CFrame.LookVector.Y, camera_lv.Z)*50)).magnitude)
                closest[2] = hit_dist
            end
        end
    end)
    -- Loop #2 (Players' lines)
    task.spawn(function()
        while game:GetService("RunService").RenderStepped:Wait() do
            for i,v in pairs(pls:GetChildren()) do
                if not setter_mode or teamcheck(v) or v == lp or not v.Character  then continue end
                local pp = v.Character.PrimaryPart
                local camera_lv = CurCam.CFrame.LookVector
                local hit_dist = math.floor((pp.Position-(mypp.Position+Vector3.new(camera_lv.X, mypp.CFrame.LookVector.Y, camera_lv.Z)*50)).magnitude)
                if hit_dist < closest[2] then
                    closest = {pp, hit_dist}
                    if targethl then targethl:Destroy() end
                    targethl = add.hlplayer(v, Color3.fromRGB(100,40,255), nil, 0.5)
                end
            end
        end
    end)
    -- Loop #3 (Color corrections, etc.)
    task.spawn(function()
        while true do task.wait(0.5)
            if waitinglvl5 then
                if getlvl()>=5 then
                    local str = pgui:FindFirstChild("Interface").TeamSelection.Options.AdvancedMoves.Text.Text
                    if str:find("OFF") then services.GameService.RF.ToggleAdvancedMoves:InvokeServer() end
                    request_teleport:InvokeServer("Default")
                    waitinglvl5=false
                end
            end
            game:GetService("Lighting").ColorCorrection.Brightness = -0.2
            game:GetService("Lighting").ColorCorrection.Contrast = 0.3
            if not pgui:FindFirstChild("Interface").Lobby.Styles.Visible then jersey:InvokeServer() end
            pgui:FindFirstChild("Interface").Stats.BundleContainer.Visible = false
        end
    end)
end
msg.Notify("Useless", "Loaded", 0.1)
if _G.ReExec then return end
_G.ReExec = true; queue_on_teleport("loadstring(readfile('misc.lua'))(); _G.ReExec = false")