-- ============================================================
-- NOCLIPOV v2.18 — Refactored & Optimized Main Code (Updated)
-- ============================================================
repeat task.wait() until game:IsLoaded()
local ALLOWED_PLACE_IDS = { [9872472334]=true, [10662098230]=true, [10808838353]=true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return end

local SCRIPT_VERSION  = "2.18"
local ENV_CLEANUP_KEY = "__NoclipovCleanup"
local CONFIG_PATH     = "Noclipov/evade/Config.json"
local CONFIG_BAK_PATH = "Noclipov/evade/Config.bak.json"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local VirtualUser       = game:GetService("VirtualUser")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

-- Cleanup previous
do
    local oldCleanup = ENV[ENV_CLEANUP_KEY] or ENV.__ZettaCleanup
    if type(oldCleanup) == "function" then pcall(oldCleanup); task.wait() end
    ENV[ENV_CLEANUP_KEY] = nil; ENV.__ZettaCleanup = nil
end

-- ================= MODULE LOADING =================
local additional = isfile("Noclipov/modules/additional.lua") and dofile("Noclipov/modules/additional.lua") or loadstring(game:HttpGet("https://raw.githubusercontent.com/noclipov/Roblox-Luas/refs/heads/main/Libs/additional.lua"))()
local UI = additional.module("ui.lua", true, false)
local movementLib = additional.module("movement.lua", true, false)

local Movement = movementLib
if type(movementLib.new) == "function" then
    Movement = movementLib.new(UI)
end

local NotificationSystem = { 
    Push = function(text, nType, dur) 
        UI.Notify.Push("NOCLIPOV", text, nType, dur) 
    end 
}

local BindSystem = UI.Bindings
if not BindSystem then warn("[Noclipov] Failed to load BindSystem"); return end
BindSystem.Held = BindSystem.Held or {}

local SessionStats = { StartTime = os.clock() }
local displaySpeed = 0
local function FormatTime(sec) sec = math.floor(sec); return string.format("%02d:%02d", math.floor(sec/60), sec%60) end

-- ================= CONFIG / STATE =================
local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, MaxTurnAngle=45,
    AdaptiveGainEnabled=false, AdaptiveGainMin=0.4, AdaptiveGainMax=1.6,
    MarkerMaxDist=500, PlaybackSpeed=1.0, TrimThreshold=1.0,
    CompactMode=false, AntiAfkEnabled=false,
    UIScale=1.0,
    Theme="Amethyst",
    SlopeVertBoost=1.0, SlopeCooldown=0.55, SlopeMinSpeed=25,
    SlopeBaseGain=1.15, SlopeMaxGain=2.2, SlopeGainPerSpeed=0.01,
}
local PRED_CONST = { MinVisibleDist=15, FadeInSpeed=10, FadeOutSpeed=14, ToleranceTime=0.4, TerminalVel=200, MaxSteps=120, NormalMin=0.3 }
local State = {
    BhopEnabled=false, JumpAccelEnabled=false, IsHoldingJump=false,
    SlopeBoostEnabled=false, LandPredEnabled=false,
    MarkersEnabled=true,
}

local LoadConfig, RefreshRecorderList
local DestroyPred, PredState
local Cleanup = function() end

-- ================= DISPOSER =================
local Disposer = { items = {}, disposed = false, cleaning = false }
function Disposer:track(kind, obj)
    if not obj then return obj end
    if self.disposed then pcall(function() if kind == "connection" then if obj.Connected then obj:Disconnect() end elseif kind == "instance" then if obj.Parent then obj:Destroy() end end end); return obj end
    table.insert(self.items, {kind = kind, obj = obj}); return obj
end
function Disposer:dispose()
    if self.disposed or self.cleaning then return end
    self.cleaning, self.disposed = true, true
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        pcall(function() if item.kind == "connection" then if item.obj.Connected then item.obj:Disconnect() end elseif item.kind == "instance" then if item.obj.Parent then item.obj:Destroy() end end end)
        self.items[i] = nil
    end
    table.clear(self.items); self.cleaning = false
end
local function TrackConnection(conn) return Disposer:track("connection", conn) end

-- ================= ANTI-AFK =================
local AntiAfk = {enabled=false, conn=nil}
local function SetAntiAfkEnabled(enabled)
    AntiAfk.enabled = enabled
    if enabled then
        if not AntiAfk.conn then
            AntiAfk.conn = TrackConnection(LocalPlayer.Idled:Connect(function()
                if not AntiAfk.enabled then return end
                pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
            end))
        end
    else
        if AntiAfk.conn then pcall(function() AntiAfk.conn:Disconnect() end); AntiAfk.conn = nil end
    end
end

-- ================= CHARACTER CACHE =================
local CharCache = {char=nil, hum=nil, hrp=nil}
local function RefreshCharCache()
    local c = LocalPlayer.Character
    CharCache.char = c; CharCache.hum = c and c:FindFirstChildOfClass("Humanoid"); CharCache.hrp = c and c:FindFirstChild("HumanoidRootPart")
end
local function GetChar() if not CharCache.char or not CharCache.char.Parent then RefreshCharCache() end; return CharCache.char end
local function GetHum() local c = GetChar(); if c and (not CharCache.hum or not CharCache.hum.Parent) then CharCache.hum = c:FindFirstChildOfClass("Humanoid") end; return CharCache.hum end
local function GetHrp() local c = GetChar(); if c and (not CharCache.hrp or not CharCache.hrp.Parent) then CharCache.hrp = c:FindFirstChild("HumanoidRootPart") end; return CharCache.hrp end

-- ================= MOVEMENT (Bhop / Slope) =================
local CHAR_RAY = RaycastParams.new(); CHAR_RAY.FilterType = Enum.RaycastFilterType.Exclude; CHAR_RAY.IgnoreWater = true
pcall(function() CHAR_RAY.RespectCanCollide = true end)
local function IsAirborne(hum, hrp)
    if not hum or not hrp then return false end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.FallingDown then return true end
    if st ~= Enum.HumanoidStateType.Running and st ~= Enum.HumanoidStateType.Landed and st ~= Enum.HumanoidStateType.RunningNoPhysics then return false end
    if hum.FloorMaterial == Enum.Material.Air then
        CHAR_RAY.FilterDescendantsInstances = {LocalPlayer.Character}
        return Workspace:Raycast(hrp.Position, Vector3.new(0, -3, 0), CHAR_RAY) == nil
    end
    return false
end
local function FindGameLV(char)
    if not char then return nil end
    local planeBest, anyFallback
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("LinearVelocity") and d.Attachment0 and d.RelativeTo == Enum.ActuatorRelativeTo.World then
            local m = d.VelocityConstraintMode
            if m == Enum.VelocityConstraintMode.Plane then if d.Enabled then return d end; planeBest = planeBest or d
            elseif m == Enum.VelocityConstraintMode.Vector then anyFallback = anyFallback or d end
        end
    end
    return planeBest or anyFallback
end
local function EnsureLVBoostable(lv)
    if not lv then return end
    if not lv.Enabled then pcall(function() lv.Enabled = true end) end
    if lv.MaxForce < 1e6 then pcall(function() lv.MaxForce = math.huge end) end
end
local BhopState = { TargetSpeed=0, WasAirborne=false, TrackedHrp=nil, TrackedLV=nil, LastGameDir=nil, LastSlopeBoost=0, _lastLvCheck=0, LastJumpRelease=0, LastJumpStateTime=0, LastBoostTime=0, HumStateConn=nil }
local function ResetBhopState()
    BhopState.TargetSpeed = 0; BhopState.LastGameDir = nil; BhopState.WasAirborne = false
    BhopState.TrackedHrp = nil; BhopState.TrackedLV = nil
    BhopState._lastLvCheck = 0
    BhopState.LastSlopeBoost = 0
    BhopState.LastJumpRelease = 0
    BhopState.LastJumpStateTime = 0
    BhopState.LastBoostTime = 0
end

local function FullCharacterReset()
    if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end); BhopState.HumStateConn = nil end
    ResetBhopState()
    if DestroyPred then DestroyPred() end
    if PredState then
        PredState.FadeState = "hidden"; PredState.FadeProgress = 0; PredState.IdleTime = 0; PredState.LastSuccess = 0
    end
    if Movement and Movement.StopPlayback then pcall(function() Movement:StopPlayback(true) end) end
    displaySpeed = 0
    if BindSystem.Capture then pcall(function() BindSystem.CaptureCancel() end) end
    RefreshCharCache()
end

local function TryBhop(dt)
    if LocalPlayer.Character then
        local hum0 = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum0 and hum0.Health <= 0 then BhopState.TargetSpeed = 0; return end
    end
    local char = GetChar(); if not char then ResetBhopState(); return end
    local hum = GetHum(); local hrp = GetHrp()
    if not hum or not hrp then ResetBhopState(); return end
    if BhopState.TrackedHrp ~= hrp then
        ResetBhopState()
        BhopState.TrackedHrp = hrp
        BhopState.TrackedLV = FindGameLV(char)
        if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end) end
        BhopState.HumStateConn = hum.StateChanged:Connect(function(_, newState) if newState == Enum.HumanoidStateType.Jumping then BhopState.LastJumpStateTime = os.clock() end end)
    else
        local t = os.clock()
        if not BhopState.TrackedLV or not BhopState.TrackedLV.Parent or (t - (BhopState._lastLvCheck or 0) > 0.5) then
            BhopState.TrackedLV = FindGameLV(char); BhopState._lastLvCheck = t
        end
    end

    local now = os.clock()
    local isBraking = BindSystem.Held["Brake"] == true
    local airborne = IsAirborne(hum, hrp)
    local justJumped = airborne and not BhopState.WasAirborne
    local gameSpeed, gameDir = 0, nil
    if BhopState.TrackedLV and BhopState.TrackedLV.Parent then
        local pv = BhopState.TrackedLV.PlaneVelocity; local mag = math.sqrt(pv.X*pv.X + pv.Y*pv.Y); gameSpeed = mag
        if mag > 0.5 then gameDir = Vector3.new(pv.X/mag, 0, pv.Y/mag) end
    end
    if not airborne and not gameDir then
        local md = hum.MoveDirection; local flat = Vector3.new(md.X, 0, md.Z); if flat.Magnitude > 0.01 then gameDir = flat.Unit end
    end
    local recentJump = (now - (BhopState.LastJumpStateTime or 0)) < 0.15
    local jumpIntent = State.IsHoldingJump or ((now - (BhopState.LastJumpRelease or 0)) < 0.15)
    local canBoost = (justJumped or recentJump) and jumpIntent and not isBraking
    local boostCooldownOk = (now - (BhopState.LastBoostTime or 0)) > 0.2
    if canBoost and boostCooldownOk then
        BhopState.LastBoostTime = now
        local base = math.max(BhopState.TargetSpeed, gameSpeed, CFG.MinSpeed)
        if State.JumpAccelEnabled then
            local gainPct = CFG.GainPercent
            if CFG.AdaptiveGainEnabled then
                local norm = math.clamp(base / math.max(CFG.MaxSpeed, 1), 0, 1)
                gainPct = gainPct * (CFG.AdaptiveGainMax - norm * (CFG.AdaptiveGainMax - CFG.AdaptiveGainMin))
            end
            BhopState.TargetSpeed = math.min(CFG.MaxSpeed, base + (CFG.MaxSpeed - base) * (gainPct / 100))
        else BhopState.TargetSpeed = math.min(CFG.MaxSpeed, base) end
    end
    local skipApply = false
    if airborne and gameDir then
        if BhopState.LastGameDir then
            local align = math.clamp(BhopState.LastGameDir:Dot(gameDir), -1, 1)
            if math.deg(math.acos(align)) > CFG.MaxTurnAngle then BhopState.TargetSpeed = CFG.MinSpeed; skipApply = true end
        end
        if not skipApply then
            local physVel = hrp.AssemblyLinearVelocity; local flatVel = Vector3.new(physVel.X, 0, physVel.Z)
            if flatVel.Magnitude > 0.5 then
                local physDir = flatVel.Unit; local alignPhys = math.clamp(physDir:Dot(gameDir), -1, 1)
                if math.deg(math.acos(alignPhys)) > CFG.MaxTurnAngle then BhopState.TargetSpeed = CFG.MinSpeed; skipApply = true end
            end
        end
    end
    if gameDir then BhopState.LastGameDir = gameDir end
    if isBraking then BhopState.TargetSpeed = math.max(CFG.MinSpeed, BhopState.TargetSpeed - CFG.BrakeRate * dt) end
    if not airborne and not State.IsHoldingJump and (now - (BhopState.LastJumpRelease or 0)) > 0.15 then BhopState.TargetSpeed = 0 end
    local shouldJump = State.IsHoldingJump or ((now - (BhopState.LastJumpRelease or 0)) < 0.1)
    if not airborne and shouldJump and hum.FloorMaterial ~= Enum.Material.Air and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true); hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if airborne and BindSystem.Held["Fall"] == true then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    if not skipApply and BhopState.TrackedLV and BhopState.TrackedLV.Parent and BhopState.TargetSpeed >= 1 and gameDir then
        EnsureLVBoostable(BhopState.TrackedLV)
        local speed = math.min(BhopState.TargetSpeed, CFG.MaxSpeed)
        BhopState.TrackedLV.PlaneVelocity = Vector2.new(gameDir.X * speed, gameDir.Z * speed)
    end
    BhopState.WasAirborne = airborne
end

-- ================= SLOPE =================
local SLOPE = {NormalMin=math.cos(math.rad(70)), NormalMax=math.cos(math.rad(30)), AirRay=20, GroundRay=12, VertFrac=0.7}
local DOWN_AIR = Vector3.new(0, -SLOPE.AirRay, 0)
local DOWN_GROUND = Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new(); SlopeRay.FilterType = Enum.RaycastFilterType.Exclude; SlopeRay.IgnoreWater = true
local function TrySlopeBoost()
    if BindSystem.Held["Brake"] == true or not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock(); if now - BhopState.LastSlopeBoost < CFG.SlopeCooldown then return end
    local char = GetChar(); if not char then return end
    local hrp = GetHrp(); local hum = GetHum()
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    SlopeRay.FilterDescendantsInstances = {char}
    local vel = hrp.AssemblyLinearVelocity; if vel.Y < 2 then return end
    local flat = Vector3.new(vel.X, 0, vel.Z); if flat.Magnitude < 0.1 then return end
    local fw = flat.Unit; local base = hrp.Position
    local hB  = Workspace:Raycast(base - fw*2.0, DOWN_AIR, SlopeRay)
    local hA1 = Workspace:Raycast(base + fw*1.0, DOWN_AIR, SlopeRay)
    local hA2 = Workspace:Raycast(base + fw*2.5, DOWN_AIR, SlopeRay)
    if not (hB and hA1 and hA2) then
        hB  = Workspace:Raycast(base - fw*2.0, DOWN_GROUND, SlopeRay)
        hA1 = Workspace:Raycast(base + fw*1.0, DOWN_GROUND, SlopeRay)
        hA2 = Workspace:Raycast(base + fw*2.5, DOWN_GROUND, SlopeRay)
    end
    if not (hB and hA1 and hA2) then return end
    local r1 = hA1.Position.Y - hB.Position.Y; local r2 = hA2.Position.Y - hB.Position.Y
    if r1 <= 0 or r2 <= 0 or r1 < 1.5 or r2 < 1.05 or r1 > r2 * 2.0 then return end
    local upDot = hA1.Normal.Y
    if upDot >= SLOPE.NormalMax or upDot <= SLOPE.NormalMin then return end
    BhopState.LastSlopeBoost = now
    task.spawn(function()
        task.wait(0.03)
        if not State.SlopeBoostEnabled or not State.IsHoldingJump or not hrp.Parent then return end
        local v2 = hrp.AssemblyLinearVelocity; if v2.Y < 0 then return end
        local sp = Vector3.new(v2.X, 0, v2.Z).Magnitude
        local over = math.max(0, sp - CFG.SlopeMinSpeed)
        local g = math.min(CFG.SlopeBaseGain + over * CFG.SlopeGainPerSpeed, CFG.SlopeMaxGain)
        local boosted = math.max(sp, CFG.SlopeMinSpeed) * g
        local vertFrac = SLOPE.VertFrac * (CFG.SlopeVertBoost or 1.0)
        local targetY = math.min(v2.Y + boosted * vertFrac, CFG.VertCap or 55); if targetY < v2.Y then targetY = v2.Y end
        local hvx, hvz = fw.X * boosted, fw.Z * boosted
        hrp.AssemblyLinearVelocity = Vector3.new(hvx, targetY, hvz)
        local lv = BhopState.TrackedLV; if lv and lv.Parent then EnsureLVBoostable(lv); lv.PlaneVelocity = Vector2.new(hvx, hvz) end
        BhopState.TargetSpeed = math.max(BhopState.TargetSpeed, boosted)
    end)
end

-- ================= PREDICTION =================
local PRED_RAY = RaycastParams.new(); PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude; PRED_RAY.IgnoreWater = true
pcall(function() PRED_RAY.RespectCanCollide = true end)
PredState = { Data=nil, SmoothCFrame=nil, FadeState="hidden", FadeProgress=0, LastSuccess=0, LastUpdate=0, ArcParts={}, IdleTime=0, CachedImpact=nil, CachedImpactTime=nil, CachedImpactAt=0, LastPath=nil, __errLogged=false, __errLoggedAt=0 }

local function PredictLanding(hrp, hum, maxTime)
    local hipHeight = math.max(hum.HipHeight or 0, hrp.Size.Y * 0.5 + 1)
    local pos = hrp.Position - Vector3.new(0, hipHeight, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity; local terminal = PRED_CONST.TerminalVel; local dt = 0.025
    local maxSteps = math.min(math.floor(maxTime / dt), PRED_CONST.MaxSteps); local normalMin = PRED_CONST.NormalMin
    PRED_RAY.FilterDescendantsInstances = {LocalPlayer.Character}
    local path = {pos}
    if vel.Y >= -5 then
        local groundRay = Workspace:Raycast(pos, Vector3.new(0, -hipHeight - 1, 0), PRED_RAY)
        if groundRay and groundRay.Normal.Y > normalMin then return groundRay.Position, path, 0.01 end
    end
    for i = 1, maxSteps do
        local vY = math.max(vel.Y - g * dt, -terminal)
        local nextVel = Vector3.new(vel.X, vY, vel.Z)
        local nextPos = Vector3.new(pos.X + vel.X*dt, pos.Y + vel.Y*dt - 0.5*g*dt*dt, pos.Z + vel.Z*dt)
        local rayDir = nextPos - pos; local dist = rayDir.Magnitude
        table.insert(path, nextPos)
        if dist > 0.05 then
            local hit = Workspace:Raycast(pos, rayDir, PRED_RAY)
            if hit then
                if hit.Normal.Y > normalMin then
                    local hitDist = (hit.Position - pos).Magnitude
                    local alpha = math.clamp(hitDist / math.max(dist, 0.01), 0, 1)
                    return hit.Position, path, math.max((i - 1 + alpha) * dt, 0.01)
                elseif hit.Normal.Y <= 0.2 and nextVel.Y <= 0 then return nil, nil end
            end
        end
        pos = nextPos; vel = nextVel
    end
    return nil, nil
end
DestroyPred = function()
    if PredState.Data then
        for _, key in ipairs({"root","ring","ringOuter","innerRing","dot","dotGlow","beam","ringLight"}) do local p = PredState.Data[key]; if p then pcall(function() p:Destroy() end) end end
        PredState.Data = nil
    end
    for _, p in ipairs(PredState.ArcParts) do pcall(function() p:Destroy() end) end
    table.clear(PredState.ArcParts)
    PredState.SmoothCFrame = nil; PredState.CachedImpact = nil; PredState.CachedImpactTime = nil; PredState.LastPath = nil; PredState.__errLogged = false
end
local function EnsurePred()
    if PredState.Data and PredState.Data.root and PredState.Data.root.Parent then return PredState.Data end
    DestroyPred()
    local accent = UI:GetTheme().Accent
    
    -- Корневой объект (невидимый якорь)
    local root = Instance.new("Part"); root.Name="Noclipov_LandPred_Root"; root.Size=Vector3.new(0.1,0.1,0.1); root.Transparency=1; root.Anchored=true; root.CanCollide=false; root.CanQuery=false; root.CanTouch=false; root.Parent=Workspace
    
    -- Основное кольцо (плоское, на земле)
    local ring = Instance.new("Part"); ring.Name="Noclipov_LandPred_Ring"; ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(0.05, 4.0, 4.0); ring.Anchored=true; ring.CanCollide=false; ring.CanQuery=false; ring.CanTouch=false; ring.Material=Enum.Material.Neon; ring.Color=accent; ring.Transparency=0.1; ring.CFrame = CFrame.Angles(0, 0, math.rad(90)); ring.Parent=Workspace
    
    -- Внутреннее кольцо
    local innerRing = Instance.new("Part"); innerRing.Name="Noclipov_LandPred_InnerRing"; innerRing.Shape=Enum.PartType.Cylinder; innerRing.Size=Vector3.new(0.05, 2.0, 2.0); innerRing.Anchored=true; innerRing.CanCollide=false; innerRing.CanQuery=false; innerRing.CanTouch=false; innerRing.Material=Enum.Material.Neon; innerRing.Color=UI:GetTheme().TextBright; innerRing.Transparency=0.3; innerRing.CFrame = CFrame.Angles(0, 0, math.rad(90)); innerRing.Parent=Workspace
    
    -- Внешнее тонкое кольцо (радар)
    local ringOuter = Instance.new("Part"); ringOuter.Name="Noclipov_LandPred_RingOuter"; ringOuter.Shape=Enum.PartType.Cylinder; ringOuter.Size=Vector3.new(0.02, 6.0, 6.0); ringOuter.Anchored=true; ringOuter.CanCollide=false; ringOuter.CanQuery=false; ringOuter.CanTouch=false; ringOuter.Material=Enum.Material.ForceField; ringOuter.Color=accent; ringOuter.Transparency=0.6; ringOuter.CFrame = CFrame.Angles(0, 0, math.rad(90)); ringOuter.Parent=Workspace
    
    -- Перекрестие (2 тонкие полоски)
    local cross1 = Instance.new("Part"); cross1.Name="Noclipov_Cross1"; cross1.Size=Vector3.new(0.1, 0.05, 5.5); cross1.Anchored=true; cross1.CanCollide=false; cross1.CanQuery=false; cross1.CanTouch=false; cross1.Material=Enum.Material.Neon; cross1.Color=accent; cross1.Transparency=0.5; cross1.Parent=Workspace
    local cross2 = Instance.new("Part"); cross2.Name="Noclipov_Cross2"; cross2.Size=Vector3.new(5.5, 0.05, 0.1); cross2.Anchored=true; cross2.CanCollide=false; cross2.CanQuery=false; cross2.CanTouch=false; cross2.Material=Enum.Material.Neon; cross2.Color=accent; cross2.Transparency=0.5; cross2.Parent=Workspace

    -- Центральная точка
    local dot = Instance.new("Part"); dot.Name="Noclipov_LandPred_Dot"; dot.Shape=Enum.PartType.Ball; dot.Size=Vector3.new(0.4,0.4,0.4); dot.Anchored=true; dot.CanCollide=false; dot.CanQuery=false; dot.CanTouch=false; dot.Material=Enum.Material.Neon; dot.Color=UI:GetTheme().TextBright; dot.Transparency=0.05; dot.Parent=Workspace
    
    -- Свечение вокруг точки
    local dotGlow = Instance.new("Part"); dotGlow.Name="Noclipov_LandPred_DotGlow"; dotGlow.Shape=Enum.PartType.Ball; dotGlow.Size=Vector3.new(1.0,1.0,1.0); dotGlow.Anchored=true; dotGlow.CanCollide=false; dotGlow.CanQuery=false; dotGlow.CanTouch=false; dotGlow.Material=Enum.Material.ForceField; dotGlow.Color=accent; dotGlow.Transparency=0.8; dotGlow.Parent=Workspace
    
    -- Свет
    local ringLight = Instance.new("PointLight"); ringLight.Color=accent; ringLight.Range=6; ringLight.Brightness=0.5; ringLight.Shadows=false; ringLight.Parent=ring

    -- Вертикальный луч
    local att0=Instance.new("Attachment"); att0.Position=Vector3.zero; att0.Parent=root
    local att1=Instance.new("Attachment"); att1.Position=Vector3.new(0,20,0); att1.Parent=root
    local beam=Instance.new("Beam"); beam.Attachment0=att0; beam.Attachment1=att1; beam.Width0=0.15; beam.Width1=0.0; beam.Color=ColorSequence.new(accent)
    beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.8), NumberSequenceKeypoint.new(0.5,0.4), NumberSequenceKeypoint.new(1,1)})
    beam.FaceCamera=true; beam.LightEmission=1; beam.LightInfluence=0; beam.Parent=root

    -- Траектория (шары вместо кубиков)
    for _ = 1, 20 do
        local p = Instance.new("Part"); p.Name="Noclipov_LandPred_Arc"; p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(0.1,0.1,0.1); p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Material=Enum.Material.Neon; p.Color=accent; p.Transparency=1; p.Parent=Workspace
        table.insert(PredState.ArcParts, p)
    end
    
    PredState.Data = {
        root=root, ring=ring, innerRing=innerRing, ringOuter=ringOuter, 
        cross1=cross1, cross2=cross2, dot=dot, dotGlow=dotGlow, 
        ringLight=ringLight, beam=beam
    }
    return PredState.Data
end
UI.GUI.ThemeSystem.Subscribe(function(nt)
    local col = nt.Accent
    if PredState.Data then
        if PredState.Data.ring then PredState.Data.ring.Color = col end
        if PredState.Data.ringOuter then PredState.Data.ringOuter.Color = col end
        if PredState.Data.dotGlow then PredState.Data.dotGlow.Color = col end
        if PredState.Data.beam then PredState.Data.beam.Color = ColorSequence.new(col) end
        if PredState.Data.ringLight then PredState.Data.ringLight.Color = col end
    end
    for _, p in ipairs(PredState.ArcParts) do if p.Parent then p.Color = col end end
    
    pcall(function()
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("BasePart") and (obj.Name:match("^Noclipov_Marker") or obj.Name:match("^Noclipov_Path") or obj.Name:match("^Noclipov_Playback")) then
                obj.Color = col
            elseif obj:IsA("Model") and (obj.Name:match("^Noclipov_Marker") or obj.Name:match("^Noclipov_Path") or obj.Name:match("^Noclipov_Playback")) then
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("BasePart") then child.Color = col
                    elseif child:IsA("Beam") then child.Color = ColorSequence.new(col)
                    elseif child:IsA("Trail") then child.Color = ColorSequence.new(col)
                    elseif child:IsA("PointLight") then child.Color = col end
                end
            end
        end
    end)

    if Movement and Movement.RefreshMarkers then 
        pcall(function() Movement:RefreshMarkers() end) 
    end
end)
local function fadeAlpha(base)
    if PredState.FadeProgress <= 0 then return 1 end
    if PredState.FadeProgress >= 1 then return base end
    return 1 - PredState.FadeProgress * (1 - base)
end
local function UpdatePrediction(dt)
    if not State.LandPredEnabled and PredState.FadeState == "hidden" and not PredState.Data then return end
    if Movement and Movement.PlayState and Movement.PlayState.Active then
        if PredState.FadeState ~= "hidden" then PredState.FadeState = "hidden"; PredState.FadeProgress = 0; DestroyPred() end; return
    end
    local now = os.clock(); if now - PredState.LastUpdate < 0.033 then return end
    local frameDt = now - PredState.LastUpdate; PredState.LastUpdate = now
    local predPos, path, predTime
    local hrp = GetHrp(); local hum = GetHum()
    if State.LandPredEnabled and hrp and hum and IsAirborne(hum, hrp) then
        local ok, c, p, t = pcall(PredictLanding, hrp, hum, 3.0)
        if ok and c and p and t then
            local dist = (hrp.Position - c).Magnitude
            if dist >= PRED_CONST.MinVisibleDist then
                predPos, path, predTime = c, p, t
                PredState.CachedImpact = c; PredState.CachedImpactTime = t; PredState.CachedImpactAt = now; PredState.LastPath = p
            end
        end
    end
    
    if predPos then
        PredState.LastSuccess = now; PredState.IdleTime = 0
        if PredState.FadeState == "hidden" then PredState.FadeState = "showing"; PredState.FadeProgress = 0
        elseif PredState.FadeState == "hiding" then PredState.FadeState = "showing" end
    else
        if State.LandPredEnabled and PredState.CachedImpact and (now - (PredState.CachedImpactAt or 0) < 0.25) then
            local cacheDist = (hrp and (hrp.Position - PredState.CachedImpact).Magnitude) or math.huge
            if cacheDist >= PRED_CONST.MinVisibleDist then
                predPos = PredState.CachedImpact; predTime = PredState.CachedImpactTime; path = PredState.LastPath; PredState.LastSuccess = now
            elseif PredState.FadeState ~= "hidden" then PredState.FadeState = "hiding" end
        else
            if (PredState.FadeState == "showing" or PredState.FadeState == "visible") and (now - PredState.LastSuccess > PRED_CONST.ToleranceTime) then PredState.FadeState = "hiding" end
        end
    end
    
    if PredState.FadeState == "showing" then
        PredState.FadeProgress = math.min(1, PredState.FadeProgress + frameDt * PRED_CONST.FadeInSpeed)
        if PredState.FadeProgress >= 1 then PredState.FadeState = "visible" end
    elseif PredState.FadeState == "hiding" then
        PredState.FadeProgress = math.max(0, PredState.FadeProgress - frameDt * PRED_CONST.FadeOutSpeed)
        if PredState.FadeProgress <= 0 then PredState.FadeState = "hidden"; DestroyPred(); return end
    end
    if PredState.FadeState == "hidden" then
        PredState.IdleTime = PredState.IdleTime + frameDt
        if PredState.IdleTime > 2 and PredState.Data then DestroyPred() end; return
    end
    if not hrp then return end
    
    local data = EnsurePred(); local theme = UI:GetTheme()
    
    if predPos then
        local targetCF = CFrame.new(predPos + Vector3.new(0, 0.05, 0))
        if not PredState.SmoothCFrame then PredState.SmoothCFrame = targetCF end
        PredState.SmoothCFrame = PredState.SmoothCFrame:Lerp(targetCF, math.clamp(frameDt * 18, 0, 1))
        
        -- Вычисляем "срочность" (0 - высоко, 1 - прямо сейчас приземлимся)
        local urgency = math.clamp(1 - (predTime or 2) / 2.0, 0, 1)
        local pulseSpeed = 2.0 + urgency * 4.0
        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * pulseSpeed)
        
        -- Цвет: плавный переход от акцента к красному при опасном сближении
        local baseColor = theme.Accent:Lerp(theme.Danger, urgency)
        local timeColor = baseColor
        
        data.root.Position = PredState.SmoothCFrame.Position
        
        -- Настройка колец
        local ringScale = 4.0 + pulse * (0.2 + urgency * 0.3)
        data.ring.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90))
        data.ring.Transparency = fadeAlpha(0.1 + pulse*0.1 + urgency*0.1); data.ring.Size = Vector3.new(0.05, ringScale, ringScale); data.ring.Color = timeColor
        
        local innerScale = 2.0 - urgency * 0.5 + pulse * 0.1
        data.innerRing.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90))
        data.innerRing.Transparency = fadeAlpha(0.2 + pulse*0.2); data.innerRing.Size = Vector3.new(0.05, innerScale, innerScale); data.innerRing.Color = theme.TextBright
        
        local outerScale = 6.0 + pulse * (0.3 + urgency * 0.5)
        data.ringOuter.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, now*1.5, 0)
        data.ringOuter.Transparency = fadeAlpha(0.6 - pulse*0.1 - urgency*0.2); data.ringOuter.Size = Vector3.new(0.02, outerScale, outerScale); data.ringOuter.Color = timeColor
        
        -- Перекрестие (вращается)
        local crossSize = 5.5 + pulse * 0.5
        data.cross1.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, now * 2, 0)
        data.cross1.Size = Vector3.new(0.08, 0.04, crossSize); data.cross1.Color = timeColor; data.cross1.Transparency = fadeAlpha(0.4)
        data.cross2.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, now * 2, math.rad(90))
        data.cross2.Size = Vector3.new(crossSize, 0.04, 0.08); data.cross2.Color = timeColor; data.cross2.Transparency = fadeAlpha(0.4)
        
        -- Точка в центре
        local dotSize = 0.4 + urgency * 0.3 + pulse * 0.1
        data.dot.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.15, 0))
        data.dot.Size = Vector3.new(dotSize, dotSize, dotSize); data.dot.Transparency = fadeAlpha(0.05); data.dot.Color = timeColor
        
        local auraSize = 1.0 + pulse * (0.3 + urgency * 0.6)
        data.dotGlow.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.15, 0))
        data.dotGlow.Size = Vector3.new(auraSize, auraSize, auraSize); data.dotGlow.Transparency = fadeAlpha(0.8 - pulse * 0.2); data.dotGlow.Color = timeColor
        
        -- Свет и луч
        if data.ringLight then data.ringLight.Enabled = true; data.ringLight.Color = timeColor; data.ringLight.Brightness = 0.2 + pulse * 0.1 end
        if data.beam then 
            data.beam.Color = ColorSequence.new(timeColor)
            data.beam.Width0 = 0.1 + urgency * 0.1
        end
        
        -- Траектория (плавные шары)
        if path and #path > 2 then
            local N = #path; local numSeg = #PredState.ArcParts
            for i, seg in ipairs(PredState.ArcParts) do
                local idx1 = math.clamp(math.floor((i - 1) / numSeg * (N - 1)) + 1, 1, N - 1)
                local idx2 = math.clamp(math.floor(i / numSeg * (N - 1)) + 1, idx1 + 1, N)
                local A = path[idx1]; local B = path[idx2]; local len = (B - A).Magnitude
                if len > 0.05 then
                    local t = (i - 1) / (numSeg - 1)
                    local pos = A:Lerp(B, 0.5)
                    local size = 0.1 + (1 - t) * 0.1
                    seg.Size = Vector3.new(size, size, size)
                    seg.Position = pos
                    seg.Color = timeColor:Lerp(theme.Accent, t * 0.5)
                    seg.Transparency = fadeAlpha(math.max(0.1, (0.6 - t*0.3) - urgency*0.1))
                else seg.Transparency = 1 end
            end
        else for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end end
    else
        -- Плавное затухание при исчезновении
        for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
        data.ring.Transparency = 1; data.innerRing.Transparency = 1; data.ringOuter.Transparency = 1
        data.cross1.Transparency = 1; data.cross2.Transparency = 1
        data.dot.Transparency = 1; data.dotGlow.Transparency = 1
        if data.ringLight then data.ringLight.Enabled = false end
    end
end
local function SweepOrphanPredParts(force)
    if not force and (State.LandPredEnabled or PredState.FadeState ~= "hidden" or PredState.Data or #PredState.ArcParts > 0) then return end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and (obj.Name:match("^Noclipov_Pred_") or obj.Name:match("^Noclipov_LandPred_")) then pcall(function() obj:Destroy() end) end
    end
end

-- ================= UI SHELL =================
local Window = UI:CreateWindow({
    Title = "NOCLIPOV", Version = SCRIPT_VERSION,
    Theme = CFG.Theme, ConfigPath = CONFIG_PATH,
    OnClose = function() Cleanup() end,
})
UI.ScreenGui = Window.ScreenGui

UI.Watermark = Window:CreateWatermark()
UI.RecorderStatus = Window:CreateRecorderStatus()

function UI.ApplyCompactMode(enabled)
    CFG.CompactMode = enabled
    local wm = UI.Watermark
    if wm then
        if enabled then
            wm.Instance.Size = UDim2.fromOffset(260, 96)
            if wm.SubSpeedLbl then wm.SubSpeedLbl.Visible = false end
            if wm.SpeedVal then wm.SpeedVal.Size = UDim2.new(1, -50, 0, 42); wm.SpeedVal.TextSize = 34 end
        else
            wm.Instance.Size = UDim2.fromOffset(260, 148)
            if wm.SubSpeedLbl then wm.SubSpeedLbl.Visible = true end
            if wm.SpeedVal then wm.SpeedVal.Size = UDim2.new(1, -50, 0, 34); wm.SpeedVal.TextSize = 30 end
        end
    end
    local rs = UI.RecorderStatus
    if rs then
        if enabled then
            rs.Instance.Size = UDim2.fromOffset(280, 100)
            if rs.FramesVal then rs.FramesVal.Parent.Visible = false end
            if rs.InfoLbl then rs.InfoLbl.Visible = false end
            if rs.SubLbl then rs.SubLbl.Visible = false end
            if rs.DurVal then rs.DurVal.Size = UDim2.new(1, 0, 1, 0); rs.DurVal.TextSize = 34 end
        else
            rs.Instance.Size = UDim2.fromOffset(280, 152)
            if rs.FramesVal then rs.FramesVal.Parent.Visible = true end
            if rs.InfoLbl then rs.InfoLbl.Visible = true end
            if rs.SubLbl then rs.SubLbl.Visible = true end
            if rs.DurVal then rs.DurVal.Size = UDim2.new(1, 0, 0, 30); rs.DurVal.TextSize = 26 end
        end
    end
end

function UI.UpdateRecorderStatus()
    local rs = UI.RecorderStatus
    if not rs or not rs.Instance.Visible then return end
    local now = os.clock()
    local theme = UI:GetTheme()
    local pillText, pillColor
    
    local isRec = Movement.RecState and Movement.RecState.IsRecording
    local isPlay = Movement.PlayState and Movement.PlayState.Active
    local cache = Movement.RecState and Movement.RecState.Cache
    local savedCount = #(Movement.GetRecordings and Movement:GetRecordings() or {})

    if isRec then
        local dur = now - Movement.RecState.StartTime
        pillText, pillColor = "REC", theme.Danger
        rs.DurVal.Text = string.format("%.1fs", dur); rs.DurVal.TextColor3 = theme.Danger
        rs.FramesVal.Text = tostring(#Movement.RecState.Frames); rs.FramesVal.TextColor3 = theme.Text
        rs.InfoLbl.Text = "Recording..."; rs.InfoLbl.TextColor3 = theme.Danger
        rs.SubLbl.Text = string.format("Press %s to stop", BindSystem.GetDisplay("Record")); rs.SubLbl.TextColor3 = theme.TextDim
        rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.75 + math.sin(now * math.pi * 3) * 0.15
    elseif isPlay then
        rs.FramesVal.Text = tostring(#(Movement.PlayState.Frames or {})); rs.FramesVal.TextColor3 = theme.Text
        local elapsed = (now - (Movement.PlayState.StartTime or now)) * (Movement.PlayState.Speed or 1)
        local pct = math.clamp(elapsed / math.max(0.01, Movement.PlayState.Duration or 1), 0, 1)
        pillText, pillColor = "PLAY", theme.Accent
        rs.DurVal.Text = string.format("%.1fs", elapsed); rs.DurVal.TextColor3 = theme.Accent
        rs.InfoLbl.Text = Movement.PlayState.RecName or "?"; rs.InfoLbl.TextColor3 = theme.Text
        rs.SubLbl.Text = string.format("%.1f/%.1fs · %.0f%% · ×%.2f", elapsed, Movement.PlayState.Duration or 0, pct * 100, Movement.PlayState.Speed or 1)
        rs.SubLbl.TextColor3 = theme.TextDim; rs.ProgBg.Visible = true; rs.ProgFill.Size = UDim2.new(pct, 0, 1, 0)
        rs.Pill.BackgroundTransparency = 0.3
    elseif cache then
        pillText, pillColor = "READY", theme.Success
        rs.DurVal.Text = string.format("%.1fs", cache.duration); rs.DurVal.TextColor3 = theme.Success
        rs.FramesVal.Text = tostring(cache.frameCount); rs.FramesVal.TextColor3 = theme.Text
        rs.InfoLbl.Text = "Ready to save"; rs.InfoLbl.TextColor3 = theme.Success
        rs.SubLbl.Text = string.format("Save in REC tab · %s to play", BindSystem.GetDisplay("Playback")); rs.SubLbl.TextColor3 = theme.TextDim
        rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.3
    else
        pillText, pillColor = "IDLE", theme.TextMuted
        rs.DurVal.Text = "--"; rs.DurVal.TextColor3 = theme.TextMuted
        rs.FramesVal.Text = "--"; rs.FramesVal.TextColor3 = theme.TextMuted
        rs.InfoLbl.Text = "Idle"; rs.InfoLbl.TextColor3 = theme.TextDim
        rs.SubLbl.Text = string.format("%s rec · %s play · %d saved", BindSystem.GetDisplay("Record"), BindSystem.GetDisplay("Playback"), savedCount)
        rs.SubLbl.TextColor3 = theme.TextMuted; rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.3
    end
    rs.Pill.BackgroundColor3 = pillColor; rs.PillDot.BackgroundColor3 = pillColor
    rs.PillLbl.Text = pillText; rs.PillLbl.TextColor3 = pillColor
end

-- ================= PAGES =================
local PlayPage = Window:Tab("Play", "🏃")
local TunePage = Window:Tab("Tune", "⚙")
local VisPage = Window:Tab("Visual", "✨")
local RecPage = Window:Tab("REC", "🎬")
local HotkeysPage = Window:Tab("Keys", "⌨")

PlayPage:Section("Movement")
PlayPage:Toggle({ Name = "Auto BunnyHop", ConfigKey = "BhopEnabled", Description = "Автоматический прыжок при удержании Space", Default = State.BhopEnabled, Icon = "🐇", Callback = function(v) State.BhopEnabled = v; if not v then ResetBhopState() end end })
PlayPage:Toggle({ Name = "Jump Acceleration", ConfigKey = "JumpAccelEnabled", Description = "Увеличивает скорость при каждом прыжке", Default = State.JumpAccelEnabled, Icon = "⚡", Callback = function(v) State.JumpAccelEnabled = v end })
PlayPage:Section("Boosts")
PlayPage:Toggle({ Name = "Slope Boost", ConfigKey = "SlopeBoostEnabled", Description = "Ускорение при столкновении со склоном", Default = State.SlopeBoostEnabled, Icon = "⛷", Callback = function(v) State.SlopeBoostEnabled = v end })
PlayPage:Section("Utility")
PlayPage:Toggle({ Name = "Anti-AFK", ConfigKey = "AntiAfkEnabled", Description = "Предотвращает кик за неактивность", Default = CFG.AntiAfkEnabled, Icon = "🛡", Callback = function(v) CFG.AntiAfkEnabled = v; SetAntiAfkEnabled(v) end })

TunePage:Section("Speed")
TunePage:Slider({ Name = "Gain Percent", ConfigKey = "GainPercent", Description = "Процент прибавки за прыжок", Min = 1, Max = 20, Default = CFG.GainPercent, Icon = "⚡", Callback = function(v) CFG.GainPercent = v end })
TunePage:Slider({ Name = "Max Speed", ConfigKey = "MaxSpeed", Description = "Максимальная скорость", Min = 50, Max = 250, Default = CFG.MaxSpeed, Icon = "🚀", Callback = function(v) CFG.MaxSpeed = v end })
TunePage:Slider({ Name = "Min Speed", ConfigKey = "MinSpeed", Description = "Минимальная скорость", Min = 5, Max = 50, Default = CFG.MinSpeed, Icon = "🐢", Callback = function(v) CFG.MinSpeed = v end })
TunePage:Section("Adaptive Gain")
TunePage:Toggle({ Name = "Enable Adaptive Gain", ConfigKey = "AdaptiveGainEnabled", Description = "Масштабирует gain по скорости", Default = CFG.AdaptiveGainEnabled, Icon = "📈", Callback = function(v) CFG.AdaptiveGainEnabled = v end })
TunePage:Slider({ Name = "Adaptive Min", ConfigKey = "AdaptiveGainMin", Description = "Множитель gain при Max Speed", Min = 0.1, Max = 1.0, Default = CFG.AdaptiveGainMin, Icon = "🔽", Decimals = 2, Callback = function(v) CFG.AdaptiveGainMin = v end })
TunePage:Slider({ Name = "Adaptive Max", ConfigKey = "AdaptiveGainMax", Description = "Множитель gain при нулевой скорости", Min = 1.0, Max = 2.5, Default = CFG.AdaptiveGainMax, Icon = "🔼", Decimals = 2, Callback = function(v) CFG.AdaptiveGainMax = v end })
TunePage:Section("Control")
TunePage:Slider({ Name = "Max Turn Angle", ConfigKey = "MaxTurnAngle", Description = "Угол сброса буста", Min = 15, Max = 180, Default = CFG.MaxTurnAngle, Icon = "📐", Callback = function(v) CFG.MaxTurnAngle = v end })
TunePage:Slider({ Name = "Vertical Cap", ConfigKey = "VertCap", Description = "Лимит по оси Y", Min = 40, Max = 100, Default = CFG.VertCap, Icon = "📈", Callback = function(v) CFG.VertCap = v end })
TunePage:Slider({ Name = "Brake Rate", ConfigKey = "BrakeRate", Description = "Скорость торможения (Shift)", Min = 20, Max = 200, Default = CFG.BrakeRate, Icon = "🛑", Callback = function(v) CFG.BrakeRate = v end })
TunePage:Section("Fall")
TunePage:Slider({ Name = "Fast Fall Force", ConfigKey = "FastFallForce", Description = "Сила падения (X)", Min = 30, Max = 300, Default = CFG.FastFallForce, Icon = "⬇", Callback = function(v) CFG.FastFallForce = v end })
TunePage:Section("Slope Boost")
TunePage:Slider({ Name = "Slope Cooldown", ConfigKey = "SlopeCooldown", Description = "Кулдаун буста (сек)", Min = 0.1, Max = 2.0, Default = CFG.SlopeCooldown, Icon = "⏱", Decimals = 2, Callback = function(v) CFG.SlopeCooldown = v end })
TunePage:Slider({ Name = "Slope Min Speed", ConfigKey = "SlopeMinSpeed", Description = "Мин. скорость для буста", Min = 10, Max = 100, Default = CFG.SlopeMinSpeed, Icon = "🐢", Callback = function(v) CFG.SlopeMinSpeed = v end })
TunePage:Slider({ Name = "Slope Base Gain", ConfigKey = "SlopeBaseGain", Description = "Базовый множитель буста", Min = 1.0, Max = 2.0, Default = CFG.SlopeBaseGain, Icon = "⚡", Decimals = 2, Callback = function(v) CFG.SlopeBaseGain = v end })
TunePage:Slider({ Name = "Slope Max Gain", ConfigKey = "SlopeMaxGain", Description = "Макс. множитель буста", Min = 1.5, Max = 4.0, Default = CFG.SlopeMaxGain, Icon = "🚀", Decimals = 2, Callback = function(v) CFG.SlopeMaxGain = v end })
TunePage:Slider({ Name = "Slope Vert Boost", ConfigKey = "SlopeVertBoost", Description = "Множитель вертикали", Min = 0.0, Max = 2.0, Default = CFG.SlopeVertBoost, Icon = "⛷", Decimals = 2, Callback = function(v) CFG.SlopeVertBoost = v end })

VisPage:Section("Effects")
VisPage:Toggle({ Name = "Landing Prediction", ConfigKey = "LandPredEnabled", Description = "Визуальный таймер до приземления", Default = State.LandPredEnabled, Icon = "🎯", Callback = function(v)
    State.LandPredEnabled = v
    if not v then PredState.FadeState = "hidden"; PredState.FadeProgress = 0; PredState.IdleTime = 0; DestroyPred() end
end })
VisPage:Section("Markers")
VisPage:Toggle({ 
    Name = "Show Markers", 
    ConfigKey = "MarkersEnabled",
    Description = "Отображает маршруты в мире", 
    Default = State.MarkersEnabled, 
    Icon = "📍", 
    Callback = function(v) 
        State.MarkersEnabled = v
        if Movement and Movement.SetMarkersEnabled then 
            Movement:SetMarkersEnabled(v) 
        end
    end 
})
VisPage:Slider({ Name = "Marker Range", ConfigKey = "MarkerMaxDist", Description = "Дистанция видимости", Min = 20, Max = 1000, Default = CFG.MarkerMaxDist, Icon = "📏", Callback = function(v) CFG.MarkerMaxDist = v end })
VisPage:Section("Interface")
VisPage:Toggle({ Name = "Status Window", ConfigKey = "WatermarkVisible", Description = "Монитор скорости и FPS", Default = UI.Watermark.Instance.Visible, Icon = "📊", Callback = function(v) UI.Watermark.Instance.Visible = v end })
VisPage:Toggle({ Name = "Recorder Status", ConfigKey = "RecorderVisible", Description = "Монитор записи", Default = UI.RecorderStatus.Instance.Visible, Icon = "🎬", Callback = function(v) UI.RecorderStatus.Instance.Visible = v end })
VisPage:Toggle({ Name = "Compact Mode", ConfigKey = "CompactMode", Description = "Компактные окна", Default = CFG.CompactMode, Icon = "🗜", Callback = function(v) UI.ApplyCompactMode(v) end })

HotkeysPage:Section("Keybinds")
HotkeysPage:Label("ЛКМ — назначить, ПКМ — сбросить, Backspace — очистить")
local HotkeysList = {
    {id="Bhop", title="Toggle Bhop"},
    {id="Accel", title="Toggle Jump Accel"},
    {id="Slope", title="Toggle Slope Boost"},
    {id="Pred", title="Toggle Prediction"},
    {id="Record", title="Toggle Record"},
    {id="Playback", title="Play Nearby"},
    {id="CycleSpeed", title="Cycle Playback Speed"},
    {id="Brake", title="Brake (Hold)"},
    {id="Fall", title="Fast Fall (Hold)"},
    {id="UI", title="Toggle UI"},
}
for _, item in ipairs(HotkeysList) do HotkeysPage:Keybind({ Name = item.title, ActionId = item.id }) end

-- REC Page
RecPage:Section("Info")
UI.RecHelpLabel = RecPage:Label("", { height = 34 })
RecPage:Section("Playback")
RecPage:Slider({ Name = "Playback Speed", ConfigKey = "PlaybackSpeed", Description = "Скорость воспроизведения", Min = 0.5, Max = 3.0, Default = CFG.PlaybackSpeed, Icon = "⏩", Decimals = 2, Callback = function(v) 
    CFG.PlaybackSpeed = v
    if Movement and Movement.PlayState then Movement.PlayState.Speed = v end
end })
RecPage:Section("Trim")
RecPage:Slider({ Name = "Trim Threshold", ConfigKey = "TrimThreshold", Description = "Порог движения", Min = 0.2, Max = 5.0, Default = CFG.TrimThreshold, Icon = "📐", Decimals = 2, Callback = function(v) CFG.TrimThreshold = v end })
RecPage:Section("Status")
UI.RecStatusLabel = RecPage:Label("Idle", { height = 40, size = 12, theme = "TextMuted" })
RecPage:Section("Save")

local nameInputObj = RecPage:TextBox({ Name = "Recording Name", Placeholder = "Enter name..." })
UI.RecNameBox = nameInputObj.TextBox

RecPage:ButtonRow({ Buttons = {
	{
		Name = "SAVE",
		Style = "Primary",
		Callback = function()
			if not Movement.RecState.Cache then return end
			local name = (UI.RecNameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[^%w_%-%(%) ]", "")
			if name == "" then UI.RecNameBox.PlaceholderText = "Enter a valid name"; return end
			for _, rec in ipairs(Movement:GetRecordings()) do if rec.name == name then UI.RecNameBox.PlaceholderText = "Name already in use"; return end end
			if Movement:SaveToFile(name, Movement.RecState.Cache.frames, Movement.RecState.Cache.duration) then
				Movement.RecState.Cache = nil
				UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
				if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Saved: " .. name; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Success end
				if Movement.RefreshMarkers then Movement:RefreshMarkers() end
				if RefreshRecorderList then RefreshRecorderList() end
				NotificationSystem.Push("Saved: " .. name, "success", 2)
			else
				if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Save failed"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Danger end
				NotificationSystem.Push("Save failed", "error", 3)
			end
		end
	},
	{
		Name = "CANCEL",
		Style = "Secondary",
		Callback = function()
			if not Movement.RecState.Cache then return end
			Movement.RecState.Cache = nil
			if Movement.ClearMarkers then Movement:ClearMarkers() end
			UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
			if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().TextMuted end
			if Movement.RefreshMarkers then Movement:RefreshMarkers() end
			if RefreshRecorderList then task.defer(RefreshRecorderList) end
		end
	},
}})

RecPage:Section("Recordings")
local recList = RecPage:List({ Size = UDim2.new(1, 0, 0, 200) })
RecPage:Button({ Name = "🗑 CLEAR ALL RECORDINGS", Description = "Удалить все записи", Callback = function()
    if Movement.RecState.IsRecording then NotificationSystem.Push("Остановите запись", "warning", 2); return end
    local count = 0
    for _, rec in ipairs(Movement:GetRecordings()) do 
        if Movement:DeleteFile(rec.path) then count = count + 1 end
    end
    Movement.RecState.Cache = nil
    if Movement.ClearMarkers then Movement:ClearMarkers() end
    if RefreshRecorderList then RefreshRecorderList() end
    if Movement.RefreshMarkers then Movement:RefreshMarkers() end
    NotificationSystem.Push(string.format("Deleted %d recordings", count), "warning", 3)
end })

RefreshRecorderList = function()
    recList:Clear()
    local saved = Movement:GetRecordings()
    if #saved == 0 then
        recList:AddItem({ Icon = "ℹ", Title = "No recordings", Subtitle = "Record a path first", OnPlay = nil, OnDelete = nil })
    else
        for _, rec in ipairs(saved) do
            local metaStr = rec.mapName or ""
            if rec.createdAt then local ok, dateStr = pcall(function() return os.date("%d.%m.%Y", rec.createdAt) end); if ok and dateStr then metaStr = (metaStr ~= "" and (metaStr .. " · " .. dateStr)) or dateStr end end
            recList:AddItem({
                Icon = "🎬", Title = rec.name,
                Subtitle = string.format("%.1fs · %d frames · %s", rec.duration, rec.frameCount, metaStr),
                OnPlay = function()
                    if Movement.RecState.IsRecording then 
                        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Сначала остановите запись"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
                        return 
                    end
                    
                    if Movement.RecState.Cache then
                        NotificationSystem.Push("У вас есть несохраненный кеш! Сохраните или отмените его.", "warning", 3)
                        return
                    end

                    local isPlaying = Movement.PlayState.Active and Movement.PlayState.RecName == rec.name
                    if isPlaying then Movement:StopPlayback()
                    else local _, decoded = Movement:ReadFirstFrame(rec.path); if decoded then Movement:StartPlayback(rec.name, decoded.frames, decoded.duration) end end
                end,
                OnDelete = function()
                    if Movement.RecState.IsRecording then if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Сначала остановите запись"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end; return end
                    Movement:DeleteFile(rec.path)
                    task.defer(function() RefreshRecorderList(); if Movement.RefreshMarkers then Movement:RefreshMarkers() end end)
                    NotificationSystem.Push("Deleted: " .. rec.name, "warning", 2)
                end
            })
        end
    end
end
task.defer(function() if RefreshRecorderList then RefreshRecorderList() end end)

-- ================= CONFIG =================
local function UDim2ToTable(u) return {XScale = u.X.Scale, XOffset = u.X.Offset, YScale = u.Y.Scale, YOffset = u.Y.Offset} end
local function TableToUDim2(t) if type(t) ~= "table" then return nil end; return UDim2.new(tonumber(t.XScale) or 0, tonumber(t.XOffset) or 0, tonumber(t.YScale) or 0, tonumber(t.YOffset) or 0) end
local function BuildSaveData()
    -- ui.lua автоматически соберет Toggles, Sliders и Hotkeys благодаря ConfigKey
    local data = {
        version = SCRIPT_VERSION, 
        IsVisible = Window.IsVisible, 
        Theme = UI:GetThemeName(),
        MainFramePos = UDim2ToTable(Window.MainFrame.Position),
        LauncherPos = UDim2ToTable(Window.LauncherIcon.Position),
        WatermarkPos = UDim2ToTable(UI.Watermark.Instance.Position),
        RecorderStatusPos = UDim2ToTable(UI.RecorderStatus.Instance.Position),
        WatermarkVisible = UI.Watermark.Instance.Visible,
        RecorderVisible = UI.RecorderStatus.Instance.Visible,
    }
    return data
end

do
    local function Log(msg) pcall(function() warn("[Noclipov] " .. tostring(msg)) end) end
    LoadConfig = function()
        local content, source = nil, "none"
        pcall(function() if isfile and isfile(CONFIG_PATH) then content = readfile(CONFIG_PATH); source = "primary" end end)
        if not content or #tostring(content) == 0 then pcall(function() content = readfile(CONFIG_BAK_PATH); source = "backup" end) end
        if not content or #tostring(content) == 0 then Log("LOAD: no content"); return end
        local jsonOk, data = pcall(function() return HttpService:JSONDecode(content) end)
        if not jsonOk or type(data) ~= "table" then Log("LOAD FAIL: invalid JSON"); return end
        
        -- ⚡ Загружаем все UI компоненты (включая тублеры и слайдеры по ConfigKey) через ui.lua
        Window:_LoadConfig()

        -- Восстанавливаем кастомные позиции окон
        local p = TableToUDim2(data.WatermarkPos); if p then UI.Watermark.Instance.Position = p end
        p = TableToUDim2(data.RecorderStatusPos); if p then UI.RecorderStatus.Instance.Position = p end
        
        if data.WatermarkVisible ~= nil then
            local wv = data.WatermarkVisible == true
            UI.Watermark.Instance.Visible = wv
        end
        if data.RecorderVisible ~= nil then
            local rv = data.RecorderVisible == true
            UI.RecorderStatus.Instance.Visible = rv
        end
        
        local sc = math.clamp(CFG.UIScale or 1.0, 0.7, 1.5); Window:SetScale(sc)
        pcall(function() SetAntiAfkEnabled(CFG.AntiAfkEnabled == true) end)
        pcall(function() UI.ApplyCompactMode(CFG.CompactMode == true) end)
        
        -- Принудительно применяем состояние маркеров
        if Movement and Movement.SetMarkersEnabled then
            Movement:SetMarkersEnabled(State.MarkersEnabled)
        end
        
        Log("LOAD OK from " .. source .. " (v" .. (data.version or "?") .. ")")
    end
end

-- ================= CHARACTER EVENTS =================
TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
    FullCharacterReset()
end))
TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
    FullCharacterReset()
    task.delay(0.5, function() pcall(function() SweepOrphanPredParts(true) end) end)
    task.delay(1, function() if RefreshRecorderList then RefreshRecorderList() end end)
end))

-- ================= INPUT =================
do
    local TOGGLE_STATE_MAP = {
        Bhop  = {uiName = "Auto BunnyHop",      stateKey = "BhopEnabled"},
        Accel = {uiName = "Jump Acceleration",  stateKey = "JumpAccelEnabled"},
        Slope = {uiName = "Slope Boost",        stateKey = "SlopeBoostEnabled"},
        Pred  = {uiName = "Landing Prediction", stateKey = "LandPredEnabled"},
    }
    local function DispatchAction(actionId)
        local toggle = TOGGLE_STATE_MAP[actionId]
        if toggle and UI.Refs.Toggle[toggle.uiName] then UI.Refs.Toggle[toggle.uiName](not State[toggle.stateKey]); return end
        if actionId == "Record" then
            if Movement.RecState.IsRecording then
                Movement:StopRecording(true)
            else
                local ok, err = Movement:StartRecording()
                if not ok and UI.RecStatusLabel then UI.RecStatusLabel.Text = err or "Cannot record"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
            end
            return
        end
        if actionId == "Playback" then
            if Movement.PlayState.Active then 
                Movement:StopPlayback()
            else
                if Movement.RecState.Cache then
                    Movement:PlayUnsaved()
                    NotificationSystem.Push("Playing Unsaved Cache", "info", 2)
                else
                    local hrp = GetHrp(); if not hrp then return end
                    local nearest, nearestDecoded, minDist = nil, nil, 10
                    for _, rec in ipairs(Movement:GetRecordings()) do
                        local pos, decoded = Movement:ReadFirstFrame(rec.path)
                        if pos and decoded then 
                            local d = (hrp.Position - pos).Magnitude; 
                            if d < minDist then minDist = d; nearest = rec; nearestDecoded = decoded end 
                        end
                    end
                    if nearest then 
                        Movement:StartPlayback(nearest.name, nearestDecoded.frames, nearestDecoded.duration)
                    else 
                        NotificationSystem.Push("No markers within 10 studs", "warning", 2) 
                    end
                end
            end
            return
        end
        if actionId == "CycleSpeed" then
            local speeds = {0.5, 1.0, 1.5, 2.0, 2.5, 3.0}
            local cur = CFG.PlaybackSpeed or 1.0; local bestIdx, bestDiff = 1, math.huge
            for i, s in ipairs(speeds) do local d = math.abs(s - cur); if d < bestDiff then bestDiff = d; bestIdx = i end end
            local nextIdx = (bestIdx % #speeds) + 1
            CFG.PlaybackSpeed = speeds[nextIdx]
            if Movement then Movement.PlayState.Speed = speeds[nextIdx] end
            if UI.Refs.Slider["Playback Speed"] then UI.Refs.Slider["Playback Speed"](speeds[nextIdx]) end
            NotificationSystem.Push(string.format("Playback ×%.1f", speeds[nextIdx]), "info", 1.5); return
        end
        if actionId == "UI" then if Window.IsVisible then Window:Hide() else Window:Show() end; return end
    end
    TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
        if BindSystem.Capture then
            local cap = BindSystem.Capture
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then BindSystem.CaptureCancel(); NotificationSystem.Push("Bind cancelled", "info", 1.5); return end
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Backspace then local id = cap.actionId; BindSystem.CaptureCancel(); BindSystem.Clear(id); NotificationSystem.Push("Bind cleared", "info", 1.5); return end
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then NotificationSystem.Push("Space is reserved", "warning", 1.5); return end
            if UserInputService:GetFocusedTextBox() then BindSystem.CaptureCancel(); return end
            local binding = BindSystem.InputToBinding(input); if binding then BindSystem.CaptureComplete(binding) end
            return
        end
        if UserInputService:GetFocusedTextBox() then return end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then State.IsHoldingJump = true; return end
        for actionId, binding in pairs(BindSystem.Bindings) do
            if BindSystem.MatchBinding(binding, input) then
                if binding.type ~= "wheel" then BindSystem.Held[actionId] = true end
                if not gpe then DispatchAction(actionId) end
            end
        end
    end))
    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
            State.IsHoldingJump = false; BhopState.LastJumpRelease = os.clock()
        end
        for actionId, binding in pairs(BindSystem.Bindings) do if BindSystem.MatchBinding(binding, input) then BindSystem.Held[actionId] = nil end end
    end))
    TrackConnection(UserInputService.TextBoxFocused:Connect(function() State.IsHoldingJump = false end))
end

-- ================= STEPPED =================
TrackConnection(RunService.Stepped:Connect(function(_, dt)
    if Movement.PlayState and Movement.PlayState.Active then return end
    if State.BhopEnabled then TryBhop(dt) end
    if State.SlopeBoostEnabled then TrySlopeBoost() end
end))

-- ================= HEARTBEAT =================
do
    local lastOrphanSweep, lastUIUpdate, lastTelemetryUpdate = 0, 0, 0
    local lastRecStatus, lastRecHelp = 0, 0
    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        if BindSystem.Capture then BindSystem.CaptureTick() end
        
        if State.LandPredEnabled or PredState.FadeState ~= "hidden" or PredState.Data then
            local ok, err = pcall(UpdatePrediction, dt)
            if not ok and not PredState.__errLogged then PredState.__errLogged = true; PredState.__errLoggedAt = now; warn("[Noclipov] Prediction error: " .. tostring(err)) end
        end
        if now - lastRecStatus > 0.05 then lastRecStatus = now; UI.UpdateRecorderStatus() end
        if now - lastRecHelp > 0.5 then
            lastRecHelp = now
            if UI.RecHelpLabel then
                local txt = string.format("%s: record · %s: play nearby", BindSystem.GetDisplay("Record"), BindSystem.GetDisplay("Playback"))
                if UI.RecHelpLabel.Text ~= txt then UI.RecHelpLabel.Text = txt end
            end
        end
        if now - lastOrphanSweep > 3.0 then lastOrphanSweep = now; SweepOrphanPredParts() end
    end))
end

-- ================= MAP WATCH =================
do
    local MapSystem = { LastMapName = Movement:GetMapName(), AttrConn = nil, ReloadDebounce = nil }
    local function HandleChange()
        if MapSystem.ReloadDebounce then return end
        MapSystem.ReloadDebounce = true
        task.delay(0.2, function()
            MapSystem.ReloadDebounce = nil; MapSystem.LastMapName = Movement:GetMapName()
            if Movement.RecState.IsRecording or Movement.RecState.Cache then
                Movement:StopRecording(false)
            end
            if Movement.PlayState.Active then Movement:StopPlayback() end
            if RefreshRecorderList then task.defer(function() RefreshRecorderList(); if State.MarkersEnabled and Movement.RefreshMarkers then Movement:RefreshMarkers() end end) end
        end)
    end
    local function Bind(map)
        if MapSystem.AttrConn then pcall(function() MapSystem.AttrConn:Disconnect() end); MapSystem.AttrConn = nil end
        if not map then return end
        MapSystem.AttrConn = TrackConnection(map:GetAttributeChangedSignal("MapName"):Connect(function()
            local newName = Movement:GetMapName()
            if newName ~= MapSystem.LastMapName then MapSystem.LastMapName = newName; HandleChange() end
        end))
    end
    TrackConnection(workspace.ChildAdded:Connect(function(child) if child.Name == "Map" then Bind(child); HandleChange() end end))
    TrackConnection(workspace.ChildRemoved:Connect(function(child) if child.Name == "Map" then MapSystem.LastMapName = "Unknown"; HandleChange() end end))
    local map = workspace:FindFirstChild("Map"); if map then Bind(map) end
    task.spawn(function()
        local lastSafety = Movement:GetMapName()
        while UI.ScreenGui and UI.ScreenGui.Parent and not Disposer.disposed do
            task.wait(5)
            local now = Movement:GetMapName()
            if now ~= lastSafety then
                lastSafety = now
                if now ~= MapSystem.LastMapName then MapSystem.LastMapName = now; HandleChange() end
            end
            local m = workspace:FindFirstChild("Map"); if m and not MapSystem.AttrConn then Bind(m) end
        end
    end)
end

-- ================= INIT =================
LoadConfig()
for _, item in ipairs(HotkeysList) do
    if not BindSystem.Bindings[item.id] then BindSystem.Bindings[item.id] = nil end
    BindSystem.UpdateButton(item.id)
end
if not Window.IsVisible then Window.MainFrame.Visible = false end
task.defer(function() SweepOrphanPredParts(true) end)

task.defer(function() 
    if Movement and Movement.RefreshMarkers then 
        pcall(function() Movement:RefreshMarkers() end) 
    end
end)

task.delay(0.5, function() NotificationSystem.Push("Noclipov v" .. SCRIPT_VERSION .. " loaded", "success", 3) end)

-- ================= CLEANUP =================
Cleanup = function()
    if Disposer.disposed then return end
    pcall(function()
        local data = BuildSaveData()
        -- Собираем кастомные позиции
        local customData = {
            WatermarkPos = UDim2ToTable(UI.Watermark.Instance.Position),
            RecorderStatusPos = UDim2ToTable(UI.RecorderStatus.Instance.Position),
            WatermarkVisible = UI.Watermark.Instance.Visible,
            RecorderVisible = UI.RecorderStatus.Instance.Visible,
        }
        -- ui.lua сам сохранит свои Toggles/Sliders/Hotkeys
        Window:SaveConfig() 
        
        -- Дописываем кастомные данные в конфиг (опционально, ui.lua уже сохранил основные)
        -- Проще всего оставить сохранение позиций окон в основном скрипте, а UI - в ui.lua
    end)
    for k in pairs(State) do if type(State[k]) == "boolean" then State[k] = false end end
    pcall(function() SetAntiAfkEnabled(false) end)
    pcall(function() if AntiAfk.conn then AntiAfk.conn:Disconnect(); AntiAfk.conn = nil end end)
    pcall(function() ResetBhopState() end)
    if Movement and Movement.Destroy then pcall(function() Movement:Destroy() end) end
    if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end); BhopState.HumStateConn = nil end
    pcall(DestroyPred)
    Disposer:dispose()
    if Window then pcall(function() Window:Destroy() end) end
    if ENV[ENV_CLEANUP_KEY] == Cleanup then ENV[ENV_CLEANUP_KEY] = nil end
end
ENV[ENV_CLEANUP_KEY] = Cleanup