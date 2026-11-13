-- ============================================================
-- NOCLIPOV v2.10 — Integrated UI (Clean)
-- ============================================================
repeat task.wait() until game:IsLoaded()

local ALLOWED_PLACE_IDS = { [9872472334]=true, [10662098230]=true, [10808838353]=true }
if not ALLOWED_PLACE_IDS[game.PlaceId] then
    game:GetService("Players").LocalPlayer:Kick("Unsupported game!"); return
end

local SCRIPT_VERSION  = "2.10"
local ENV_CLEANUP_KEY = "__NoclipovCleanup"
local BASE_FOLDER     = "Noclipov/evade"
local CONFIG_PATH     = BASE_FOLDER .. "/Config.json"
local CONFIG_BAK_PATH = BASE_FOLDER .. "/Config.bak.json"
local MOVEMENT_BASE   = BASE_FOLDER .. "/movement"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local VirtualUser       = game:GetService("VirtualUser")
local Stats             = game:GetService("Stats")
local LocalPlayer       = Players.LocalPlayer
local ENV               = (getgenv and getgenv()) or _G

do
    local oldCleanup = ENV[ENV_CLEANUP_KEY] or ENV.__ZettaCleanup
    if type(oldCleanup) == "function" then pcall(oldCleanup); task.wait() end
    ENV[ENV_CLEANUP_KEY] = nil; ENV.__ZettaCleanup = nil
end

-- ================= MODULE LOAD =================
local UI = dofile("Noclipov/modules/ui.lua")
local NotificationSystem = { Push = function(text, type, dur) UI:Notify(text, type, dur) end }
local BindSystem = UI.Bindings

-- ================= CONFIG / STATE =================
local CFG = {
    GainPercent=8, MaxSpeed=120, VertCap=55, BrakeRate=60, FastFallForce=90,
    MinSpeed=15, LandingBoostPercent=5, LandingSoftVY=30, MaxTurnAngle=45,
    AdaptiveGainEnabled=false, AdaptiveGainMin=0.4, AdaptiveGainMax=1.6,
    PredMinVisibleDist=15, PredFadeInSpeed=10, PredFadeOutSpeed=14,
    PredToleranceTime=0.4, PredTerminalVel=200, PredMaxSteps=120, PredNormalMin=0.3,
    MarkerMaxDist=500, PlaybackSpeed=1.0, TrimThreshold=1.0,
    CompactMode=false, AntiAfkEnabled=false, NotifyEnabled=true,
    UIScale=1.0, AutoReviveDelay=0.5, SmartJumpBuffer=0.1, LandingMomentum=true,
    Theme="Amethyst",
    SlopeVertBoost=1.0, SlopeCooldown=0.55, SlopeMinSpeed=25,
    SlopeBaseGain=1.15, SlopeMaxGain=2.2, SlopeGainPerSpeed=0.01,
}
local State = {
    BhopEnabled=false, JumpAccelEnabled=false, IsHoldingJump=false,
    SlopeBoostEnabled=false, LandPredEnabled=false, LandingBoostEnabled=false,
    WatermarkEnabled=false, MarkersEnabled=false, RecorderStatusEnabled=false, AutoReviveEnabled=false,
}

local SaveConfig, LoadConfig, RefreshRecorderList, RefreshMarkers
local IsVisible = true
local Cleanup = function() end

-- ================= DISPOSER =================
local Disposer = { items = {}, disposed = false, cleaning = false }
function Disposer:track(kind, obj)
    if not obj then return obj end
    if self.disposed then
        pcall(function()
            if kind == "connection" then if obj.Connected then obj:Disconnect() end
            elseif kind == "instance" then if obj.Parent then obj:Destroy() end end
        end)
        return obj
    end
    table.insert(self.items, {kind = kind, obj = obj}); return obj
end
function Disposer:dispose()
    if self.disposed or self.cleaning then return end
    self.cleaning, self.disposed = true, true
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        pcall(function()
            if item.kind == "connection" then if item.obj.Connected then item.obj:Disconnect() end
            elseif item.kind == "instance" then if item.obj.Parent then item.obj:Destroy() end end
        end)
        self.items[i] = nil
    end
    table.clear(self.items); self.cleaning = false
end
local function TrackConnection(conn) return Disposer:track("connection", conn) end

-- ================= ANTI-AFK =================
local AntiAfk = {enabled=false, conn=nil}
local function SetAntiAfkEnabled(enabled)
    AntiAfk.enabled = enabled
    if enabled and not AntiAfk.conn then
        AntiAfk.conn = TrackConnection(LocalPlayer.Idled:Connect(function()
            if not AntiAfk.enabled then return end
            pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
        end))
    end
end

-- ================= AUTO-REVIVE =================
local function TriggerSelfRevive()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then return end
    if events:FindFirstChild("Revive") then pcall(function() events.Revive:FireServer() end) end
    if events:FindFirstChild("SetPlayerMode") then pcall(function() events.SetPlayerMode:FireServer(true) end) end
    local ch = events:FindFirstChild("Character")
    if ch and ch:FindFirstChild("Revive") then pcall(function() ch.Revive:FireServer() end) end
end
local AutoRevive = {enabled=false, diedConn=nil, healthConn=nil}
local function DoReviveTrigger() if AutoRevive.enabled then pcall(TriggerSelfRevive) end end
function AutoRevive.Attach(char)
    if AutoRevive.diedConn then pcall(function() AutoRevive.diedConn:Disconnect() end); AutoRevive.diedConn = nil end
    if AutoRevive.healthConn then pcall(function() AutoRevive.healthConn:Disconnect() end); AutoRevive.healthConn = nil end
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then task.delay(0.25, function() if AutoRevive.enabled and char.Parent then AutoRevive.Attach(char) end end); return end
    local fired = false
    AutoRevive.diedConn = hum.Died:Connect(function()
        if not AutoRevive.enabled or fired then return end
        fired = true; task.delay(CFG.AutoReviveDelay or 0.5, DoReviveTrigger)
    end)
    AutoRevive.healthConn = hum.HealthChanged:Connect(function(hp)
        if hp <= 0 and AutoRevive.enabled and not fired then fired = true; task.delay(CFG.AutoReviveDelay or 0.5, DoReviveTrigger) end
    end)
end
function AutoRevive.SetEnabled(enabled)
    AutoRevive.enabled = enabled
    if enabled then AutoRevive.Attach(LocalPlayer.Character)
    else
        if AutoRevive.diedConn then pcall(function() AutoRevive.diedConn:Disconnect() end); AutoRevive.diedConn = nil end
        if AutoRevive.healthConn then pcall(function() AutoRevive.healthConn:Disconnect() end); AutoRevive.healthConn = nil end
    end
end
TrackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    if AutoRevive.enabled then task.wait(0.5); AutoRevive.Attach(char) end
end))

-- ================= CHARACTER CACHE =================
local CharCache = {char=nil, hum=nil, hrp=nil}
local function RefreshCharCache()
    local c = LocalPlayer.Character
    CharCache.char = c; CharCache.hum = c and c:FindFirstChildOfClass("Humanoid")
    CharCache.hrp = c and c:FindFirstChild("HumanoidRootPart")
end
local function GetChar()
    if not CharCache.char or not CharCache.char.Parent then RefreshCharCache() end
    return CharCache.char
end
local function GetHum()
    local c = GetChar()
    if c and (not CharCache.hum or not CharCache.hum.Parent) then CharCache.hum = c:FindFirstChildOfClass("Humanoid") end
    return CharCache.hum
end
local function GetHrp()
    local c = GetChar()
    if c and (not CharCache.hrp or not CharCache.hrp.Parent) then CharCache.hrp = c:FindFirstChild("HumanoidRootPart") end
    return CharCache.hrp
end

-- ================= MOVEMENT =================
local CHAR_RAY = RaycastParams.new()
CHAR_RAY.FilterType = Enum.RaycastFilterType.Exclude; CHAR_RAY.IgnoreWater = true
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
            if m == Enum.VelocityConstraintMode.Plane then
                if d.Enabled then return d end
                planeBest = planeBest or d
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

local BhopState = {
    TargetSpeed=0, WasAirborne=false, TrackedHrp=nil, TrackedLV=nil,
    LastGameDir=nil, LastLandingBoosted=false, LastSlopeBoost=0, CurrentStatus="IDLE",
    _lastLvCheck=0, LastJumpRelease=0, LastJumpStateTime=0, LastBoostTime=0, HumStateConn=nil,
}
local function ResetBhopState()
    BhopState.TargetSpeed = 0; BhopState.LastGameDir = nil; BhopState.WasAirborne = false
    BhopState.LastLandingBoosted = false; BhopState.TrackedHrp = nil; BhopState.TrackedLV = nil
    BhopState.CurrentStatus = "IDLE"; BhopState._lastLvCheck = 0
end
local DestroyPred, StopPlayback
local function FullCharacterReset()
    if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end); BhopState.HumStateConn = nil end
    ResetBhopState()
    if DestroyPred then DestroyPred() end
    PredState.FadeState = "hidden"; PredState.FadeProgress = 0
    PredState.IdleTime = 0; PredState.LastSuccess = 0
    if StopPlayback then StopPlayback(true) end
    SessionStats.MaxSpeed = 0; displaySpeed = 0
    BhopState.LastJumpRelease = 0; BhopState.LastJumpStateTime = 0; BhopState.LastBoostTime = 0
    if BindSystem.Capture then BindSystem.CaptureCancel() end
    RefreshCharCache()
end

local function TryBhop(dt)
    if LocalPlayer.Character then
        local hum0 = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum0 and hum0.Health <= 0 then BhopState.TargetSpeed = 0; return end
    end
    local char = GetChar()
    if not char then ResetBhopState(); BhopState.CurrentStatus = "NO CHAR"; return end
    local hum = GetHum(); local hrp = GetHrp()
    if not hum or not hrp then ResetBhopState(); BhopState.CurrentStatus = "IDLE"; return end
    if BhopState.TrackedHrp ~= hrp then
        BhopState.TrackedHrp = hrp; BhopState.TrackedLV = FindGameLV(char); ResetBhopState(); BhopState.TrackedHrp = hrp
        if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end) end
        BhopState.HumStateConn = hum.StateChanged:Connect(function(_, newState)
            if newState == Enum.HumanoidStateType.Jumping then BhopState.LastJumpStateTime = os.clock() end
        end)
    else
        local t = os.clock()
        if not BhopState.TrackedLV or not BhopState.TrackedLV.Parent or (t - (BhopState._lastLvCheck or 0) > 0.5) then
            BhopState.TrackedLV = FindGameLV(char); BhopState._lastLvCheck = t
        end
    end
    if not State.BhopEnabled then ResetBhopState(); BhopState.WasAirborne = IsAirborne(hum, hrp); BhopState.CurrentStatus = "DISABLED"; return end

    local now = os.clock()
    local isBraking = BindSystem.IsHeld("Brake")
    local airborne = IsAirborne(hum, hrp)
    local justJumped = airborne and not BhopState.WasAirborne
    local gameSpeed, gameDir = 0, nil
    if BhopState.TrackedLV and BhopState.TrackedLV.Parent then
        local pv = BhopState.TrackedLV.PlaneVelocity
        local mag = math.sqrt(pv.X*pv.X + pv.Y*pv.Y); gameSpeed = mag
        if mag > 0.5 then gameDir = Vector3.new(pv.X/mag, 0, pv.Y/mag) end
    end
    if not airborne and not gameDir then
        local md = hum.MoveDirection; local flat = Vector3.new(md.X, 0, md.Z)
        if flat.Magnitude > 0.01 then gameDir = flat.Unit end
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
    if not airborne and BhopState.WasAirborne and State.LandingBoostEnabled and BhopState.TargetSpeed > 0 and not BhopState.LastLandingBoosted and not isBraking then
        local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
        if vy <= CFG.LandingSoftVY then
            local headroom = math.max(0, CFG.MaxSpeed - BhopState.TargetSpeed)
            BhopState.TargetSpeed = BhopState.TargetSpeed + math.min(BhopState.TargetSpeed * (CFG.LandingBoostPercent / 100), headroom)
            BhopState.LastLandingBoosted = true
        end
    end
    if not airborne then BhopState.LastLandingBoosted = false end
    if not airborne and not State.IsHoldingJump and (now - (BhopState.LastJumpRelease or 0)) > 0.15 then BhopState.TargetSpeed = 0 end
    local shouldJump = State.IsHoldingJump or ((now - (BhopState.LastJumpRelease or 0)) < (CFG.SmartJumpBuffer or 0.1))
    if not airborne and shouldJump and hum.FloorMaterial ~= Enum.Material.Air and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true); hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    if airborne and BindSystem.IsHeld("Fall") then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y - CFG.FastFallForce * dt, -CFG.VertCap), v.Z)
    end
    if not skipApply and BhopState.TrackedLV and BhopState.TrackedLV.Parent and BhopState.TargetSpeed >= 1 and gameDir then
        EnsureLVBoostable(BhopState.TrackedLV)
        local speed = math.min(BhopState.TargetSpeed, CFG.MaxSpeed)
        BhopState.TrackedLV.PlaneVelocity = Vector2.new(gameDir.X * speed, gameDir.Z * speed)
    end
    BhopState.CurrentStatus = isBraking and "BRAKE" or (airborne and BhopState.TargetSpeed > 1 and "GAIN" or (airborne and "AIR" or "IDLE"))
    BhopState.WasAirborne = airborne
end

-- ================= SLOPE =================
local SLOPE = {NormalMin=math.cos(math.rad(70)), NormalMax=math.cos(math.rad(30)), AirRay=20, GroundRay=12, VertFrac=0.7}
local DOWN_AIR = Vector3.new(0, -SLOPE.AirRay, 0)
local DOWN_GROUND = Vector3.new(0, -SLOPE.GroundRay, 0)
local SlopeRay = RaycastParams.new(); SlopeRay.FilterType = Enum.RaycastFilterType.Exclude; SlopeRay.IgnoreWater = true

local function TrySlopeBoost()
    if BindSystem.IsHeld("Brake") or not State.SlopeBoostEnabled or not State.IsHoldingJump then return end
    local now = os.clock()
    if now - BhopState.LastSlopeBoost < CFG.SlopeCooldown then return end
    local char = GetChar(); if not char then return end
    local hrp = GetHrp(); local hum = GetHum()
    if not hrp or not hum or not IsAirborne(hum, hrp) then return end
    SlopeRay.FilterDescendantsInstances = {char}
    local vel = hrp.AssemblyLinearVelocity
    if vel.Y < 2 then return end
    local flat = Vector3.new(vel.X, 0, vel.Z)
    if flat.Magnitude < 0.1 then return end
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
        local targetY = math.min(v2.Y + boosted * vertFrac, CFG.VertCap or 55)
        if targetY < v2.Y then targetY = v2.Y end
        local hvx, hvz = fw.X * boosted, fw.Z * boosted
        hrp.AssemblyLinearVelocity = Vector3.new(hvx, targetY, hvz)
        local lv = BhopState.TrackedLV
        if lv and lv.Parent then EnsureLVBoostable(lv); lv.PlaneVelocity = Vector2.new(hvx, hvz) end
        BhopState.TargetSpeed = math.max(BhopState.TargetSpeed, boosted)
    end)
end

-- ================= PREDICTION =================
local PRED_RAY = RaycastParams.new()
PRED_RAY.FilterType = Enum.RaycastFilterType.Exclude; PRED_RAY.IgnoreWater = true
pcall(function() PRED_RAY.RespectCanCollide = true end)

local PredState = {
    Data=nil, SmoothCFrame=nil, FadeState="hidden", FadeProgress=0,
    LastSuccess=0, LastUpdate=0, ArcParts={}, IdleTime=0,
    CachedImpact=nil, CachedImpactTime=nil, CachedImpactVel=nil,
    CachedImpactAt=0, LastPath=nil, __errLogged=false, __errLoggedAt=0,
}
local function PredictLanding(hrp, hum, maxTime)
    local hipHeight = math.max(hum.HipHeight or 0, hrp.Size.Y * 0.5 + 1)
    local pos = hrp.Position - Vector3.new(0, hipHeight, 0)
    local vel = hrp.AssemblyLinearVelocity
    local g = Workspace.Gravity; local terminal = CFG.PredTerminalVel or 200; local dt = 0.025
    local maxSteps = math.min(math.floor(maxTime / dt), CFG.PredMaxSteps or 120)
    local normalMin = CFG.PredNormalMin or 0.3
    PRED_RAY.FilterDescendantsInstances = {LocalPlayer.Character}
    local path = {pos}
    if vel.Y >= -5 then
        local groundRay = Workspace:Raycast(pos, Vector3.new(0, -hipHeight - 1, 0), PRED_RAY)
        if groundRay and groundRay.Normal.Y > normalMin then return groundRay.Position, path, 0.01, vel end
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
                    return hit.Position, path, math.max((i - 1 + alpha) * dt, 0.01), nextVel
                elseif hit.Normal.Y <= 0.2 and nextVel.Y <= 0 then return nil, nil end
            end
        end
        pos = nextPos; vel = nextVel
    end
    return nil, nil
end

function DestroyPred()
    if PredState.Data then
        for _, key in ipairs({"root","ring","ringOuter","innerRing","dot","dotGlow","beam","ringLight"}) do
            local p = PredState.Data[key]; if p then pcall(function() p:Destroy() end) end
        end
        PredState.Data = nil
    end
    for _, p in ipairs(PredState.ArcParts) do pcall(function() p:Destroy() end) end
    table.clear(PredState.ArcParts)
    PredState.SmoothCFrame = nil; PredState.CachedImpact = nil; PredState.CachedImpactTime = nil
    PredState.CachedImpactVel = nil; PredState.LastPath = nil; PredState.__errLogged = false
end

local function EnsurePred()
    if PredState.Data and PredState.Data.root and PredState.Data.root.Parent then return PredState.Data end
    DestroyPred()
    local accent = UI:GetTheme().Accent
    local root = Instance.new("Part"); root.Name="Noclipov_LandPred_Root"; root.Size=Vector3.new(0.1,0.1,0.1)
    root.Transparency=1; root.Anchored=true; root.CanCollide=false; root.CanQuery=false; root.CanTouch=false; root.Parent=Workspace
    local ring = Instance.new("Part"); ring.Name="Noclipov_LandPred_Ring"; ring.Shape=Enum.PartType.Cylinder
    ring.Size=Vector3.new(0.06,4.5,4.5); ring.Anchored=true; ring.CanCollide=false; ring.CanQuery=false; ring.CanTouch=false
    ring.Material=Enum.Material.Neon; ring.Color=accent; ring.Transparency=0.15; ring.Parent=Workspace
    local ringLight = Instance.new("PointLight"); ringLight.Color=accent; ringLight.Range=4; ringLight.Brightness=0.15; ringLight.Shadows=false; ringLight.Parent=ring
    local ringOuter = Instance.new("Part"); ringOuter.Name="Noclipov_LandPred_RingOuter"; ringOuter.Shape=Enum.PartType.Cylinder
    ringOuter.Size=Vector3.new(0.02,5.8,5.8); ringOuter.Anchored=true; ringOuter.CanCollide=false; ringOuter.CanQuery=false; ringOuter.CanTouch=false
    ringOuter.Material=Enum.Material.ForceField; ringOuter.Color=accent; ringOuter.Transparency=0.7; ringOuter.Parent=Workspace
    local innerRing = Instance.new("Part"); innerRing.Name="Noclipov_LandPred_InnerRing"; innerRing.Shape=Enum.PartType.Cylinder
    innerRing.Size=Vector3.new(0.04,3.2,3.2); innerRing.Anchored=true; innerRing.CanCollide=false; innerRing.CanQuery=false; innerRing.CanTouch=false
    innerRing.Material=Enum.Material.Neon; innerRing.Color=UI:GetTheme().TextBright; innerRing.Transparency=0.1; innerRing.Parent=Workspace
    local dot = Instance.new("Part"); dot.Name="Noclipov_LandPred_Dot"; dot.Shape=Enum.PartType.Ball
    dot.Size=Vector3.new(0.55,0.55,0.55); dot.Anchored=true; dot.CanCollide=false; dot.CanQuery=false; dot.CanTouch=false
    dot.Material=Enum.Material.Neon; dot.Color=UI:GetTheme().TextBright; dot.Transparency=0.05; dot.Parent=Workspace
    local dotGlow = Instance.new("Part"); dotGlow.Name="Noclipov_LandPred_DotGlow"; dotGlow.Shape=Enum.PartType.Ball
    dotGlow.Size=Vector3.new(1.4,1.4,1.4); dotGlow.Anchored=true; dotGlow.CanCollide=false; dotGlow.CanQuery=false; dotGlow.CanTouch=false
    dotGlow.Material=Enum.Material.ForceField; dotGlow.Color=accent; dotGlow.Transparency=0.8; dotGlow.Parent=Workspace
    local att0=Instance.new("Attachment"); att0.Position=Vector3.zero; att0.Parent=root
    local att1=Instance.new("Attachment"); att1.Position=Vector3.new(0,15,0); att1.Parent=root
    local beam=Instance.new("Beam"); beam.Attachment0=att0; beam.Attachment1=att1
    beam.Width0=0.25; beam.Width1=0.06; beam.Color=ColorSequence.new(accent)
    beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.65), NumberSequenceKeypoint.new(0.5,0.85), NumberSequenceKeypoint.new(1,0.95)})
    beam.FaceCamera=true; beam.LightEmission=0.5; beam.LightInfluence=0; beam.Parent=root
    for _ = 1, 24 do
        local p = Instance.new("Part"); p.Name="Noclipov_LandPred_Arc"; p.Shape=Enum.PartType.Block
        p.Size=Vector3.new(0.06,0.06,1); p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
        p.Material=Enum.Material.Neon; p.Color=accent; p.Transparency=1; p.Parent=Workspace
        table.insert(PredState.ArcParts, p)
    end
    PredState.Data = {root=root, ring=ring, ringLight=ringLight, ringOuter=ringOuter, innerRing=innerRing, dot=dot, dotGlow=dotGlow, beam=beam}
    return PredState.Data
end
UI.GUI.ThemeSystem.Subscribe(function(nt)
    if PredState.Data then
        local col = nt.Accent
        if PredState.Data.ring then PredState.Data.ring.Color = col end
        if PredState.Data.ringOuter then PredState.Data.ringOuter.Color = col end
        if PredState.Data.dotGlow then PredState.Data.dotGlow.Color = col end
        if PredState.Data.beam then PredState.Data.beam.Color = ColorSequence.new(col) end
        if PredState.Data.ringLight then PredState.Data.ringLight.Color = col end
    end
    for _, p in ipairs(PredState.ArcParts) do if p.Parent then p.Color = nt.Accent end end
end)

local function fadeAlpha(base)
    if PredState.FadeProgress <= 0 then return 1 end
    if PredState.FadeProgress >= 1 then return base end
    return 1 - PredState.FadeProgress * (1 - base)
end

local function UpdatePrediction(dt)
    if not State.LandPredEnabled and PredState.FadeState == "hidden" and not PredState.Data then return end
    if PlaybackState and PlaybackState.Active then
        if PredState.FadeState ~= "hidden" then PredState.FadeState = "hidden"; PredState.FadeProgress = 0; DestroyPred() end
        return
    end
    local now = os.clock()
    if now - PredState.LastUpdate < 0.033 then return end
    local frameDt = now - PredState.LastUpdate; PredState.LastUpdate = now
    local predPos, path, predTime, impactVel
    local hrp = GetHrp(); local hum = GetHum()
    if State.LandPredEnabled and hrp and hum and IsAirborne(hum, hrp) then
        local ok, c, p, t, v = pcall(PredictLanding, hrp, hum, 3.0)
        if ok and c and p and t then
            local dist = (hrp.Position - c).Magnitude
            if dist >= (CFG.PredMinVisibleDist or 15) then
                predPos, path, predTime, impactVel = c, p, t, v
                PredState.CachedImpact = c; PredState.CachedImpactTime = t
                PredState.CachedImpactVel = v; PredState.CachedImpactAt = now; PredState.LastPath = p
            end
        elseif not ok and now - (PredState.__errLoggedAt or 0) > 30 then
            PredState.__errLoggedAt = now; warn("[Noclipov] Prediction error:", tostring(c))
        end
    end
    if predPos then
        PredState.LastSuccess = now; PredState.IdleTime = 0
        if PredState.FadeState == "hidden" then PredState.FadeState = "showing"; PredState.FadeProgress = 0
        elseif PredState.FadeState == "hiding" then PredState.FadeState = "showing" end
    else
        if State.LandPredEnabled and PredState.CachedImpact and (now - (PredState.CachedImpactAt or 0) < 0.25) then
            local cacheDist = (hrp and (hrp.Position - PredState.CachedImpact).Magnitude) or math.huge
            if cacheDist >= (CFG.PredMinVisibleDist or 15) then
                predPos = PredState.CachedImpact; predTime = PredState.CachedImpactTime
                impactVel = PredState.CachedImpactVel; path = PredState.LastPath; PredState.LastSuccess = now
            elseif PredState.FadeState ~= "hidden" then PredState.FadeState = "hiding" end
        else
            if (PredState.FadeState == "showing" or PredState.FadeState == "visible") and (now - PredState.LastSuccess > (CFG.PredToleranceTime or 0.4)) then
                PredState.FadeState = "hiding"
            end
        end
    end
    if PredState.FadeState == "showing" then
        PredState.FadeProgress = math.min(1, PredState.FadeProgress + frameDt * CFG.PredFadeInSpeed)
        if PredState.FadeProgress >= 1 then PredState.FadeState = "visible" end
    elseif PredState.FadeState == "hiding" then
        PredState.FadeProgress = math.max(0, PredState.FadeProgress - frameDt * CFG.PredFadeOutSpeed)
        if PredState.FadeProgress <= 0 then PredState.FadeState = "hidden"; DestroyPred(); return end
    end
    if PredState.FadeState == "hidden" then
        PredState.IdleTime = PredState.IdleTime + frameDt
        if PredState.IdleTime > 2 and PredState.Data then DestroyPred() end
        return
    end
    if not hrp then return end
    local data = EnsurePred()
    local theme = UI:GetTheme()
    if predPos then
        local targetCF = CFrame.new(predPos + Vector3.new(0, 0.05, 0))
        if not PredState.SmoothCFrame then PredState.SmoothCFrame = targetCF end
        PredState.SmoothCFrame = PredState.SmoothCFrame:Lerp(targetCF, math.clamp(frameDt * 15, 0, 1))
        local urgency = math.clamp(1 - (predTime or 2) / 2.0, 0, 1)
        local pulseSpeed = 2.0 + urgency * 3.5
        local pulse = 0.5 + 0.5 * math.sin(now * math.pi * pulseSpeed)
        local spinSpeed = 1.2 + urgency * 2.0
        local spin = now * spinSpeed
        data.root.Position = PredState.SmoothCFrame.Position
        local timeColor = theme.Accent
        local ringScale = 4.5 + pulse * (0.15 + urgency * 0.5)
        data.ring.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90))
        data.ring.Transparency = fadeAlpha(0.15 + pulse*0.08 + urgency*0.08)
        data.ring.Size = Vector3.new(0.06, ringScale, ringScale)
        data.ring.Color = timeColor
        if data.ringOuter then
            local outerScale = 5.8 + pulse * (0.2 + urgency * 0.6)
            data.ringOuter.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.01, 0) * CFrame.Angles(0, now*0.6, math.rad(90))
            data.ringOuter.Transparency = fadeAlpha(0.7 - pulse*0.1 - urgency*0.15)
            data.ringOuter.Size = Vector3.new(0.02, outerScale, outerScale)
            data.ringOuter.Color = timeColor
        end
        local innerSize = 3.2 - urgency * 0.8
        data.innerRing.CFrame = PredState.SmoothCFrame * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, -spin*1.5, math.rad(90))
        data.innerRing.Transparency = fadeAlpha(0.1 + pulse*0.15 + urgency*0.05)
        data.innerRing.Size = Vector3.new(0.04, innerSize, innerSize)
        local dotSize = 0.55 + urgency * 0.35
        data.dot.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.3, 0))
        data.dot.Size = Vector3.new(dotSize, dotSize, dotSize)
        data.dot.Transparency = fadeAlpha(0.05 + urgency * 0.05)
        data.dot.Color = timeColor
        if data.dotGlow then
            local auraSize = 1.4 + pulse * (0.2 + urgency * 0.5)
            data.dotGlow.CFrame = CFrame.new(PredState.SmoothCFrame.Position + Vector3.new(0, 0.25, 0))
            data.dotGlow.Size = Vector3.new(auraSize, auraSize, auraSize)
            data.dotGlow.Transparency = fadeAlpha(0.8 - pulse * 0.15)
            data.dotGlow.Color = timeColor
        end
        if data.beam then data.beam.Color = ColorSequence.new(timeColor) end
        if data.ringLight then data.ringLight.Color = timeColor; data.ringLight.Brightness = 0.08 + pulse * 0.05 end
        if path and #path > 2 then
            local N = #path; local numSeg = #PredState.ArcParts
            for i, seg in ipairs(PredState.ArcParts) do
                local idx1 = math.clamp(math.floor((i - 1) / numSeg * (N - 1)) + 1, 1, N - 1)
                local idx2 = math.clamp(math.floor(i / numSeg * (N - 1)) + 1, idx1 + 1, N)
                local A = path[idx1]; local B = path[idx2]; local len = (B - A).Magnitude
                if len > 0.05 then
                    local t = (i - 1) / (numSeg - 1); local midT = 1 - math.abs(t * 2 - 1)
                    local thick = 0.03 + midT * (0.08 + urgency * 0.05)
                    seg.Size = Vector3.new(thick, thick, len); seg.CFrame = CFrame.new((A + B) / 2, B)
                    seg.Color = timeColor:Lerp(theme.Accent, t * 0.5)
                    seg.Transparency = fadeAlpha(math.max(0.05, (0.55 - t*0.25) - urgency*0.1))
                else seg.Transparency = 1 end
            end
        else for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end end
    else
        for _, p in ipairs(PredState.ArcParts) do p.Transparency = 1 end
        data.ring.Transparency = 1; data.innerRing.Transparency = 1; data.dot.Transparency = 1
        data.ringOuter.Transparency = 1; data.dotGlow.Transparency = 1
        if data.ringLight then data.ringLight.Enabled = false end
    end
end
local function SweepOrphanPredParts(force)
    if not force and (State.LandPredEnabled or PredState.FadeState ~= "hidden" or PredState.Data or #PredState.ArcParts > 0) then return end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("BasePart") and (obj.Name:match("^Noclipov_Pred_") or obj.Name:match("^Noclipov_LandPred_")) then
            pcall(function() obj:Destroy() end)
        end
    end
end
local RecorderState, PlaybackState

-- ================= FILES =================
local RECORD_HZ = 1 / 30
RecorderState = {IsRecording=false, StartTime=0, Frames={}, FrameAccum=0, Cache=nil, Saved={}, InputEnabled=false}
PlaybackState = {Active=false, Frames=nil, Duration=0, StartTime=nil, RecName=nil, WasBhopEnabled=false, WasPredEnabled=false, WasPredToggleState=false, StartMarker=nil, Speed=1.0, OriginalAutoRotate=nil, OriginalHrpCollide=nil, OriginalWalkSpeed=nil, OriginalJumpPower=nil, OriginalJumpHeight=nil, OriginalLVEnabled=nil, TrackedLVDuringPlayback=nil}
local PLAY_RADIUS = 10
local PlaybackPath = {parts={}, active=false}
local MarkerParts = {}
local UnsavedMarker = nil
local CreateUnsavedMarker, RefreshMarkers, SetMarkersVisible, DestroyMarker, CreateMarker, DestroyUnsavedMarker
local DestroyPlaybackStartMarker, CreatePlaybackStartMarker, ClearPlaybackPath, CreatePlaybackPath, UpdatePlaybackPath
local RecStart, RecStop

local function GetMapName()
    local ok, name = pcall(function()
        local map = workspace:FindFirstChild("Map"); if not map then return nil end
        return map:GetAttribute("MapName")
    end)
    if ok and type(name) == "string" and name ~= "" then return (name:gsub("[^%w_%-]", "_")) end
    return "Unknown"
end
RecorderState.GetMapName = GetMapName

local BASE_FOLDERS_READY = false
local function EnsureBaseFolders()
    if BASE_FOLDERS_READY then return end; BASE_FOLDERS_READY = true
    pcall(function() if isfolder and not isfolder("Noclipov") then makefolder("Noclipov") end end)
    pcall(function() if isfolder and not isfolder(BASE_FOLDER) then makefolder(BASE_FOLDER) end end)
    pcall(function() if isfolder and not isfolder(MOVEMENT_BASE) then makefolder(MOVEMENT_BASE) end end)
end
local function RecEnsureFolder()
    EnsureBaseFolders()
    local mapName = GetMapName()
    pcall(function()
        if isfolder and makefolder then
            local folder = MOVEMENT_BASE .. "/" .. mapName
            if not isfolder(folder) then makefolder(folder) end
        end
    end)
end
local function RecSaveToFile(name, frames, duration)
    RecEnsureFolder()
    local data = {version=1, name=name, mapName=GetMapName(), createdAt=os.time(), duration=duration, frameCount=#frames, frames=frames}
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok or not encoded then return false end
    return pcall(writefile, MOVEMENT_BASE .. "/" .. GetMapName() .. "/" .. name .. ".json", encoded)
end
RecorderState.RecSaveToFile = RecSaveToFile
local function RecListFiles()
    RecEnsureFolder()
    local folder = MOVEMENT_BASE .. "/" .. GetMapName(); local files = {}
    pcall(function() if listfiles and isfolder and isfolder(folder) then files = listfiles(folder) end end)
    return files
end
local function RecLoadAll()
    local list = {}
    for _, path in ipairs(RecListFiles()) do
        if type(path) == "string" and path:match("%.json$") then
            local content; pcall(function() content = readfile(path) end)
            if content then
                local decoded; pcall(function() decoded = HttpService:JSONDecode(content) end)
                if decoded then
                    local fname = path:match("([^/\\]+)%.json$") or "unknown"
                    table.insert(list, {name=fname, path=path, duration=decoded.duration or 0, frameCount=decoded.frameCount or #(decoded.frames or {}), mapName=decoded.mapName or "", createdAt=decoded.createdAt})
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return list
end
RecorderState.RecLoadAll = RecLoadAll
local function RecDeleteFile(path) pcall(delfile, path) end
RecorderState.RecDeleteFile = RecDeleteFile
local function RecReadFirstFrame(path)
    local content; pcall(function() content = readfile(path) end); if not content then return nil end
    local decoded; pcall(function() decoded = HttpService:JSONDecode(content) end)
    if not decoded or not decoded.frames or not decoded.frames[1] then return nil end
    local f = decoded.frames[1]
    if not (f.px and f.py and f.pz) then return nil end
    return Vector3.new(f.px, f.py, f.pz), decoded
end
RecorderState.RecReadFirstFrame = RecReadFirstFrame
local function RecSetInputEnabled(enabled)
    RecorderState.InputEnabled = enabled
    if not UI.RecNameBox then return end
    UI.RecNameBox.TextEditable = enabled
    UI.RecNameBox.TextColor3 = enabled and UI:GetTheme().Text or UI:GetTheme().TextMuted
    UI.RecNameBox.BackgroundTransparency = enabled and 0.3 or 0.7
    if UI.RecSaveLbl then UI.RecSaveLbl.TextColor3 = enabled and UI:GetTheme().BgDarkest or UI:GetTheme().TextMuted; UI.RecSaveLbl.TextTransparency = enabled and 0 or 0.4 end
    if UI.RecSaveBtn then UI.RecSaveBtn.BackgroundTransparency = enabled and 0.05 or 0.75 end
    if UI.RecCancelLbl then UI.RecCancelLbl.TextColor3 = enabled and UI:GetTheme().Text or UI:GetTheme().TextMuted; UI.RecCancelLbl.TextTransparency = enabled and 0 or 0.4 end
    if UI.RecCancelBtn then UI.RecCancelBtn.BackgroundTransparency = enabled and 0.1 or 0.75 end
end
RecorderState.RecSetInputEnabled = RecSetInputEnabled

local function TrimLeadingStatic(frames, threshold)
    threshold = threshold or 1.0; if #frames < 3 then return frames end
    local p0 = Vector3.new(frames[1].px, frames[1].py, frames[1].pz)
    local lastStaticIdx = 1; local anyMoved = false
    for i = 2, #frames do
        local p = Vector3.new(frames[i].px, frames[i].py, frames[i].pz)
        if (p - p0).Magnitude > threshold then anyMoved = true; break end
        lastStaticIdx = i
    end
    if not anyMoved then return {} end
    if lastStaticIdx == 1 then return frames end
    local trimmed = {}; local offsetT = frames[lastStaticIdx].t
    for i = lastStaticIdx, #frames do
        local f = frames[i]
        table.insert(trimmed, {t=f.t - offsetT, px=f.px, py=f.py, pz=f.pz, vx=f.vx, vy=f.vy, vz=f.vz, lx=f.lx, ly=f.ly, lz=f.lz})
    end
    return trimmed
end
local function TrimTrailingStatic(frames, threshold)
    threshold = threshold or 1.0; if #frames < 3 then return frames end
    local pEnd = Vector3.new(frames[#frames].px, frames[#frames].py, frames[#frames].pz)
    local firstStaticIdx = #frames
    for i = #frames - 1, 1, -1 do
        local p = Vector3.new(frames[i].px, frames[i].py, frames[i].pz)
        if (p - pEnd).Magnitude > threshold then break end
        firstStaticIdx = i
    end
    if firstStaticIdx == #frames or firstStaticIdx <= 2 then return frames end
    local trimmed = {}
    for i = 1, firstStaticIdx do table.insert(trimmed, frames[i]) end
    return trimmed
end
local function CanStartRecording()
    local char = LocalPlayer.Character; if not char then return false, "No character" end
    local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false, "No humanoid" end
    if hum.FloorMaterial == Enum.Material.Air or IsAirborne(hum, hrp) then return false, "Player in air" end
    if hrp.AssemblyLinearVelocity.Magnitude > 2 then return false, "Player is moving" end
    return true
end
RecStart = function()
    if RecorderState.IsRecording or PlaybackState.Active then return end
    local ok, reason = CanStartRecording()
    if not ok then
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = reason; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
        return
    end
    RecorderState.IsRecording = true; RecorderState.StartTime = os.clock()
    RecorderState.Frames = {}; RecorderState.FrameAccum = 0; RecorderState.Cache = nil
    RecSetInputEnabled(false)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "● REC"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Danger end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
    NotificationSystem.Push("Recording started", "info", 2)
end
RecorderState.RecStart = RecStart
RecStop = function(cache)
    if not RecorderState.IsRecording then return end
    RecorderState.IsRecording = false
    local frames = RecorderState.Frames; RecorderState.Frames = {}; RecorderState.FrameAccum = 0
    if cache and #frames >= 2 then
        local trimmed = TrimLeadingStatic(frames, CFG.TrimThreshold or 1.0)
        if #trimmed > 0 then trimmed = TrimTrailingStatic(trimmed, CFG.TrimThreshold or 1.0) end
        if #trimmed < 2 then
            RecorderState.Cache = nil
            if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Too short"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
            RecSetInputEnabled(false); if RefreshMarkers then RefreshMarkers() end
            if RefreshRecorderList then task.defer(RefreshRecorderList) end; return
        end
        local newDuration = trimmed[#trimmed].t
        RecorderState.Cache = {frames=trimmed, duration=newDuration, frameCount=#trimmed}
        local trimmedCount = #frames - #trimmed
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = trimmedCount > 0 and string.format("Ready: %.1fs · %d (trimmed %d)", newDuration, #trimmed, trimmedCount) or string.format("Ready: %.1fs · %d frames", newDuration, #trimmed)
            UI.RecStatusLabel.TextColor3 = UI:GetTheme().Success
        end
        RecSetInputEnabled(true); if CreateUnsavedMarker then CreateUnsavedMarker(trimmed) end
        NotificationSystem.Push(string.format("Recorded %.1fs", newDuration), "success", 3)
    else
        RecorderState.Cache = nil
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().TextMuted end
        RecSetInputEnabled(false)
    end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
end
RecorderState.RecStop = RecStop

-- ================= MARKERS =================
local function UpdateMarkerTheme(m, nt)
    if not m then return end
    local col = nt.Accent
    if m.isUnsaved then col = nt.Warning end
    if m.isStart then col = nt.Success end
    if m.halo then m.halo.Color = col end
    if m.ringInner then m.ringInner.Color = col end
    if m.ring then m.ring.Color = col end
    if m.ringOuter then m.ringOuter.Color = col end
    if m.crystal then m.crystal.Color = col end
    if m.cap then m.cap.Color = col end
    if m.glow then m.glow.Color = col end
    if m.pillar then m.pillar.Color = ColorSequence.new(col) end
    if m.particles then m.particles.Color = ColorSequence.new(col) end
    if m.ringGlow then m.ringGlow.Color = col end
    if m.light then m.light.Color = col end
end
UI.GUI.ThemeSystem.Subscribe(function(nt)
    for _, m in pairs(MarkerParts) do UpdateMarkerTheme(m, nt) end
    if UnsavedMarker then UpdateMarkerTheme(UnsavedMarker, nt) end
    if PlaybackState.StartMarker then UpdateMarkerTheme(PlaybackState.StartMarker, nt) end
end)
local function CreateMarkerVisual(pos, colorKey, isUnsaved, isStart)
    local col = UI:GetTheme()[colorKey]
    local function part(shape, size, cframe, material, transparency, name)
        local p = Instance.new("Part"); p.Name = "Noclipov_Marker_" .. name
        if shape then p.Shape = shape end
        p.Size = size; p.CFrame = cframe; p.Anchored = true
        p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Material = material; p.Color = col; p.Transparency = transparency
        p.Parent = Workspace; return p
    end
    local root = part(nil, Vector3.new(0.1,0.1,0.1), CFrame.new(pos), Enum.Material.Plastic, 1, "Root")
    local halo = part(Enum.PartType.Cylinder, Vector3.new(0.05,5.5,5.5), CFrame.new(pos+Vector3.new(0,0.05,0))*CFrame.Angles(0,0,math.rad(90)), Enum.Material.Neon, 0.92, "Halo")
    local ringInner = part(Enum.PartType.Cylinder, Vector3.new(0.04,3.2,3.2), CFrame.new(pos+Vector3.new(0,0.06,0))*CFrame.Angles(0,0,math.rad(90)), Enum.Material.Neon, 0.4, "RingInner")
    local ring = part(Enum.PartType.Cylinder, Vector3.new(0.04,4.2,4.2), CFrame.new(pos+Vector3.new(0,0.04,0))*CFrame.Angles(0,0,math.rad(90)), Enum.Material.Neon, 0.25, "Ring")
    local ringGlow = Instance.new("PointLight"); ringGlow.Color = col; ringGlow.Range = 5; ringGlow.Brightness = 0.4; ringGlow.Shadows = false; ringGlow.Parent = ring
    local ringOuter = part(Enum.PartType.Cylinder, Vector3.new(0.02,5.0,5.0), CFrame.new(pos+Vector3.new(0,0.03,0))*CFrame.Angles(0,0,math.rad(90)), Enum.Material.ForceField, 0.85, "RingOuter")
    local crystal = part(Enum.PartType.Block, Vector3.new(0.08,1.6,0.08), CFrame.new(pos+Vector3.new(0,2.0,0)), Enum.Material.Neon, 0.15, "Crystal")
    local cap = part(Enum.PartType.Ball, Vector3.new(0.42,0.42,0.42), CFrame.new(pos+Vector3.new(0,2.85,0)), Enum.Material.Neon, 0, "Cap")
    local glow = part(Enum.PartType.Ball, Vector3.new(1.6,1.6,1.6), cap.CFrame, Enum.Material.ForceField, 0.7, "Glow")
    local att0 = Instance.new("Attachment"); att0.Position = Vector3.zero; att0.Parent = root
    local att1 = Instance.new("Attachment"); att1.Position = Vector3.new(0,15,0); att1.Parent = root
    local pillar = Instance.new("Beam"); pillar.Attachment0 = att0; pillar.Attachment1 = att1
    pillar.Width0 = 0.15; pillar.Width1 = 0.02; pillar.Color = ColorSequence.new(col)
    pillar.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.7), NumberSequenceKeypoint.new(0.5,0.9), NumberSequenceKeypoint.new(1,1)})
    pillar.FaceCamera = true; pillar.LightEmission = 0.6; pillar.LightInfluence = 0; pillar.Parent = root
    local particles = Instance.new("ParticleEmitter"); particles.Name = "Noclipov_Marker_Particles"
    particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particles.Rate = 4; particles.Lifetime = NumberRange.new(1.5,2.5); particles.Speed = NumberRange.new(1,2.5)
    particles.SpreadAngle = Vector2.new(180,180)
    particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(0.3,0.25), NumberSequenceKeypoint.new(1,0)})
    particles.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)})
    particles.Color = ColorSequence.new(col)
    particles.LightEmission = 1; particles.Acceleration = Vector3.new(0,2,0); particles.EmissionDirection = Enum.NormalId.Top; particles.Parent = cap
    local light = Instance.new("PointLight"); light.Color = col; light.Range = 8; light.Brightness = 0.8; light.Shadows = false; light.Parent = cap

    return {root=root, halo=halo, ring=ring, ringGlow=ringGlow, ringOuter=ringOuter, ringInner=ringInner, crystal=crystal, cap=cap, glow=glow, pillar=pillar, particles=particles, light=light, pos=pos, isUnsaved=isUnsaved, isStart=isStart}
end
local function DestroyMarkerVisual(m)
    if not m then return end
    for _, key in ipairs({"root","halo","ring","ringInner","ringOuter","crystal","cap","glow"}) do
        if m[key] then pcall(function() m[key]:Destroy() end) end
    end
    if m.billboard then pcall(function() m.billboard:Destroy() end) end
end
local function BuildMarkerBillboard(crystalPart, title, subtitle, meta, colorKey, isUnsaved)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 190, 0, 56); bb.StudsOffset = Vector3.new(0, 3.4, 0)
    bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.Parent = crystalPart
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1); bg.BackgroundColor3 = UI:GetTheme().BgDarkest
    bg.BackgroundTransparency = 0.15; bg.BorderSizePixel = 0; bg.Parent = bb
    UI.GUI.ThemeSystem.Bind(bg, {BackgroundColor3 = "BgDarkest"}); UI.GUI.Corner(bg, 10); UI.GUI.Stroke(bg, colorKey, 1, 0.7)
    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 2, 0, 22); accentBar.Position = UDim2.new(0, 0, 0.5, -11)
    accentBar.BackgroundColor3 = UI:GetTheme()[colorKey]; accentBar.BackgroundTransparency = 0.35
    accentBar.BorderSizePixel = 0; accentBar.Parent = bg
    UI.GUI.ThemeSystem.Bind(accentBar, {BackgroundColor3 = colorKey}); UI.GUI.Corner(accentBar, 1)
    UI.GUI.MakeLabel(bg, {Size=UDim2.new(1,-60,0,16), Position=UDim2.fromOffset(10,6), Text=title, TextSize=12, TextTheme="Text", Font=Enum.Font.GothamBold, TextTruncate=Enum.TextTruncate.AtEnd})
    if isUnsaved then
        local badge = Instance.new("Frame")
        badge.Size = UDim2.new(0, 50, 0, 14); badge.Position = UDim2.new(1, -58, 0, 7)
        badge.BackgroundColor3 = UI:GetTheme()[colorKey]; badge.BackgroundTransparency = 0.82; badge.BorderSizePixel = 0; badge.Parent = bg
        UI.GUI.ThemeSystem.Bind(badge, {BackgroundColor3 = colorKey}); UI.GUI.Corner(badge, 4); UI.GUI.Stroke(badge, colorKey, 1, 0.4)
        UI.GUI.MakeLabel(badge, {Text="UNSAVED", TextTheme=colorKey, TextSize=7, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center})
    end
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -20, 0, 1); div.Position = UDim2.fromOffset(10, 26)
    div.BorderSizePixel = 0; div.BackgroundTransparency = 0.75; div.Parent = bg; UI.GUI.ThemeSystem.Bind(div, {BackgroundColor3 = "Border"})
    UI.GUI.MakeLabel(bg, {Size=UDim2.new(1,-20,0,12), Position=UDim2.fromOffset(10,31), Text=subtitle, TextTheme="TextDim", TextSize=9, Font=Enum.Font.Code, TextTruncate=Enum.TextTruncate.AtEnd})
    if meta and meta ~= "" then
        UI.GUI.MakeLabel(bg, {Size=UDim2.new(1,-20,0,10), Position=UDim2.fromOffset(10,43), Text=meta, TextTheme="TextMuted", TextSize=8, TextTruncate=Enum.TextTruncate.AtEnd})
    end
    return bb
end
DestroyMarker = function(name)
    local m = MarkerParts[name]; if not m then return end
    DestroyMarkerVisual(m); MarkerParts[name] = nil
end
CreateMarker = function(rec)
    local startPos, decoded = RecReadFirstFrame(rec.path); if not startPos or not decoded then return end
    local visual = CreateMarkerVisual(startPos, "Accent", false, false)
    local meta = ""
    if decoded.createdAt then
        local ok, dateStr = pcall(function() return os.date("%d %b %Y · %H:%M", decoded.createdAt) end)
        if ok then meta = dateStr end
    end
    visual.billboard = BuildMarkerBillboard(visual.crystal, rec.name, string.format("%.1fs · %d frames", rec.duration, rec.frameCount), meta, "Accent", false)
    visual.rec = rec; visual.startPos = startPos; visual.isFar = false; visual.pulsePhase = math.random() * 2; visual.pulseBaseSize = 3.0
    MarkerParts[rec.name] = visual
end
RefreshMarkers = function()
    for name in pairs(MarkerParts) do DestroyMarker(name) end
    if not State.MarkersEnabled or AreMarkersBlocked() then return end
    for _, rec in ipairs(RecorderState.Saved) do CreateMarker(rec) end
end
SetMarkersVisible = function(v)
    State.MarkersEnabled = v
    if v then RefreshMarkers() else for name in pairs(MarkerParts) do DestroyMarker(name) end end
end
DestroyUnsavedMarker = function()
    if not UnsavedMarker then return end
    pcall(function() if UnsavedMarker.pillar then UnsavedMarker.pillar:Destroy() end end)
    pcall(function() if UnsavedMarker.light then UnsavedMarker.light:Destroy() end end)
    DestroyMarkerVisual(UnsavedMarker); UnsavedMarker = nil
end
CreateUnsavedMarker = function(frames)
    DestroyUnsavedMarker(); if not frames or #frames < 1 then return end
    local f = frames[1]; local pos = Vector3.new(f.px, f.py, f.pz)
    local visual = CreateMarkerVisual(pos, "Warning", true, false)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "Unsaved Recording", string.format("%.1fs · %d frames", frames[#frames].t, #frames), "Save from REC tab to keep", "Warning", true)
    visual.startPos = pos; visual.isFar = false; visual.pulsePhase = 0; visual.pulseBaseSize = 3.0; UnsavedMarker = visual
end
DestroyPlaybackStartMarker = function()
    if not PlaybackState.StartMarker then return end
    DestroyMarkerVisual(PlaybackState.StartMarker); PlaybackState.StartMarker = nil
end
CreatePlaybackStartMarker = function(pos)
    DestroyPlaybackStartMarker()
    local visual = CreateMarkerVisual(pos, "Success", false, true)
    visual.billboard = BuildMarkerBillboard(visual.crystal, "START POINT", PlaybackState.RecName or "?", "Playback origin", "Success", false)
    visual.isFar = false; visual.pulsePhase = 0; visual.pulseBaseSize = 3.0; visual.startPos = pos
    PlaybackState.StartMarker = visual
end

-- ================= PLAYBACK =================
ClearPlaybackPath = function()
    for _, p in ipairs(PlaybackPath.parts) do pcall(function() p:Destroy() end) end
    table.clear(PlaybackPath.parts); PlaybackPath.active = false
end
CreatePlaybackPath = function(frames, count)
    ClearPlaybackPath(); if not frames or #frames < 2 then return end
    count = count or 50; local total = #frames
    for i = 1, count do
        local idx = math.clamp(math.floor((i - 1) / (count - 1) * (total - 1)) + 1, 1, total)
        local f = frames[idx]; local p = Instance.new("Part")
        p.Name = "Noclipov_PlaybackPath_" .. i; p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.22, 0.22, 0.22); p.Position = Vector3.new(f.px, f.py, f.pz)
        p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Material = Enum.Material.Neon; p.Color = UI:GetTheme().Accent; p.Transparency = 0.7; p.Parent = Workspace
        p:SetAttribute("t", f.t); table.insert(PlaybackPath.parts, p)
    end
    PlaybackPath.active = true
end
UpdatePlaybackPath = function(elapsed)
    if not PlaybackPath.active then return end
    local now = os.clock()
    for _, p in ipairs(PlaybackPath.parts) do
        if p.Parent then
            local t = p:GetAttribute("t") or 0
            if elapsed > t then
                local alpha = math.clamp((elapsed - t) / 1.2, 0, 1)
                p.Transparency = 0.7 + alpha * 0.3
                local s = 0.22 - alpha * 0.12; p.Size = Vector3.new(s, s, s)
            else
                p.Transparency = 0.55 + (0.5 + 0.5 * math.sin(now * math.pi * 3 + t * 2)) * 0.15
            end
        end
    end
end
UI.GUI.ThemeSystem.Subscribe(function(nt) for _, p in ipairs(PlaybackPath.parts) do if p.Parent then p.Color = nt.Accent end end end)

function SetPlaybackSpeed(speed)
    speed = math.clamp(tonumber(speed) or 1, 0.5, 3.0)
    if PlaybackState.Active then
        local now = os.clock()
        local curElapsed = (now - (PlaybackState.StartTime or now)) * (PlaybackState.Speed or 1)
        PlaybackState.Speed = speed; PlaybackState.StartTime = now - curElapsed / speed
    else PlaybackState.Speed = speed end
    CFG.PlaybackSpeed = speed
end
function StopPlayback(silent)
    if not PlaybackState.Active then return end
    local wasBhop = PlaybackState.WasBhopEnabled; local wasPred = PlaybackState.WasPredEnabled; local wasPredToggle = PlaybackState.WasPredToggleState
    PlaybackState.Active = false
    local hum = GetHum(); local hrp = GetHrp()
    if hum then
        if PlaybackState.OriginalAutoRotate ~= nil then pcall(function() hum.AutoRotate = PlaybackState.OriginalAutoRotate end) end
        if PlaybackState.OriginalWalkSpeed ~= nil then pcall(function() hum.WalkSpeed = PlaybackState.OriginalWalkSpeed end) end
        if PlaybackState.OriginalJumpPower ~= nil then pcall(function() hum.JumpPower = PlaybackState.OriginalJumpPower end) end
        if PlaybackState.OriginalJumpHeight ~= nil then pcall(function() hum.JumpHeight = PlaybackState.OriginalJumpHeight end) end
    end
    if hrp and PlaybackState.OriginalHrpCollide ~= nil then pcall(function() hrp.CanCollide = PlaybackState.OriginalHrpCollide end) end
    if PlaybackState.TrackedLVDuringPlayback and PlaybackState.TrackedLVDuringPlayback.Parent then
        if PlaybackState.OriginalLVEnabled ~= nil then pcall(function() PlaybackState.TrackedLVDuringPlayback.Enabled = PlaybackState.OriginalLVEnabled end) end
    end
    PlaybackState.OriginalAutoRotate = nil; PlaybackState.OriginalHrpCollide = nil
    PlaybackState.OriginalWalkSpeed = nil; PlaybackState.OriginalJumpPower = nil; PlaybackState.OriginalJumpHeight = nil
    PlaybackState.OriginalLVEnabled = nil; PlaybackState.TrackedLVDuringPlayback = nil; PlaybackState.StartTime = nil
    PlaybackState.Frames = nil; PlaybackState.RecName = nil
    PlaybackState.WasBhopEnabled = false; PlaybackState.WasPredEnabled = false; PlaybackState.WasPredToggleState = false
    ClearPlaybackPath(); DestroyPlaybackStartMarker()
    if wasBhop then
        if not silent and UI.Refs.Toggle["Auto BunnyHop"] then UI.Refs.Toggle["Auto BunnyHop"](true)
        else State.BhopEnabled = true end
    end
    if wasPred then
        State.LandPredEnabled = true
        if not silent and UI.Refs.Toggle["Landing Prediction"] and wasPredToggle then pcall(function() UI.Refs.Toggle["Landing Prediction"](true) end) end
    end
    if UI.RecStatusLabel and not silent then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().TextMuted end
end
local function StartPlayback(recName, frames, duration)
    if PlaybackState.Active then StopPlayback() end
    if not frames or #frames < 2 or RecorderState.IsRecording then return end
    local hum = GetHum(); local hrp = GetHrp()
    if not hrp or not hum then return end
    if hum.Health <= 0 then NotificationSystem.Push("Cannot play: dead", "warning", 2); return end

    PlaybackState.WasBhopEnabled = State.BhopEnabled
    if State.BhopEnabled then State.BhopEnabled = false; if UI.Refs.Toggle["Auto BunnyHop"] then UI.Refs.Toggle["Auto BunnyHop"](false) end end
    PlaybackState.WasPredEnabled = State.LandPredEnabled; PlaybackState.WasPredToggleState = State.LandPredEnabled
    State.LandPredEnabled = false
    if UI.Refs.Toggle["Landing Prediction"] then pcall(function() UI.Refs.Toggle["Landing Prediction"](false) end) end
    pcall(DestroyPred); PredState.FadeState = "hidden"; PredState.FadeProgress = 0

    PlaybackState.RecName = recName
    PlaybackState.OriginalAutoRotate = hum.AutoRotate; PlaybackState.OriginalHrpCollide = hrp.CanCollide
    PlaybackState.OriginalWalkSpeed = hum.WalkSpeed; PlaybackState.OriginalJumpPower = hum.JumpPower; PlaybackState.OriginalJumpHeight = hum.JumpHeight
    hum.AutoRotate = false; hum.WalkSpeed = 0
    pcall(function() hum.JumpPower = 0 end); pcall(function() hum.JumpHeight = 0 end)
    hrp.CanCollide = false
    local lv = BhopState.TrackedLV or FindGameLV(LocalPlayer.Character)
    if lv then PlaybackState.OriginalLVEnabled = lv.Enabled; PlaybackState.TrackedLVDuringPlayback = lv; pcall(function() lv.Enabled = false end) end
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end)
    local f1 = frames[1]; local p1 = Vector3.new(f1.px, f1.py, f1.pz)
    local look1 = Vector3.new(f1.lx, f1.ly, f1.lz); if look1.Magnitude < 0.01 then look1 = Vector3.new(0, 0, -1) end
    pcall(function() hrp.CFrame = CFrame.lookAt(p1, p1 + look1.Unit) end)

    PlaybackState.Active = true; PlaybackState.Frames = frames
    PlaybackState.Duration = math.max(duration or frames[#frames].t, 0.01)
    PlaybackState.Speed = CFG.PlaybackSpeed or 1.0; PlaybackState.StartTime = nil
    pcall(function() CreatePlaybackStartMarker(p1) end); pcall(function() CreatePlaybackPath(frames, 50) end)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "▶ Playing: " .. recName; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Accent end
    NotificationSystem.Push("▶ " .. tostring(recName), "info", 2)
end
local function TryStartNearbyPlayback()
    if PlaybackState.Active then StopPlayback(); return end
    if RecorderState.Cache then StartPlayback("Unsaved", RecorderState.Cache.frames, RecorderState.Cache.duration); return end
    if RecorderState.IsRecording then
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Cannot play while recording"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
        return
    end
    local hrp = GetHrp(); if not hrp then return end
    local nearestRec, nearestDecoded, nearestDist = nil, nil, math.huge
    for _, rec in ipairs(RecorderState.Saved) do
        local pos, decoded = RecReadFirstFrame(rec.path)
        if pos and decoded then local d = (hrp.Position - pos).Magnitude; if d < nearestDist then nearestDist = d; nearestRec = rec; nearestDecoded = decoded end end
    end
    if not nearestRec or nearestDist > PLAY_RADIUS then
        local msg = string.format("No marker within %d studs", PLAY_RADIUS)
        if UI.RecStatusLabel then
            UI.RecStatusLabel.Text = msg; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning
            task.delay(2, function() if UI.RecStatusLabel and not PlaybackState.Active and not RecorderState.IsRecording then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().TextMuted end end)
        end
        NotificationSystem.Push(msg, "warning", 2); return
    end
    StartPlayback(nearestRec.name, nearestDecoded.frames, nearestDecoded.duration)
end
local function UpdatePlayback()
    if not PlaybackState.Active then return end
    local hrp = GetHrp(); local hum = GetHum()
    if not hrp or not hum or hum.Health <= 0 then StopPlayback(); return end
    local frames = PlaybackState.Frames; if not frames or #frames < 2 then StopPlayback(); return end
    if not PlaybackState.StartTime then PlaybackState.StartTime = os.clock() end
    local elapsed = (os.clock() - PlaybackState.StartTime) * (PlaybackState.Speed or 1)
    if elapsed >= PlaybackState.Duration then StopPlayback(); return end

    local lo, hi = 1, #frames
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if frames[mid].t <= elapsed then lo = mid else hi = mid end
    end
    local A = frames[lo]; local B = frames[hi]; local dtAB = B.t - A.t
    local alpha = dtAB > 0 and math.clamp((elapsed - A.t) / dtAB, 0, 1) or 0
    local targetPos = Vector3.new(A.px + (B.px - A.px) * alpha, A.py + (B.py - A.py) * alpha, A.pz + (B.pz - A.pz) * alpha)
    local lookVec = Vector3.new(A.lx + (B.lx - A.lx) * alpha, A.ly + (B.ly - A.ly) * alpha, A.lz + (B.lz - A.lz) * alpha)
    if lookVec.Magnitude < 0.01 then lookVec = Vector3.new(0, 0, -1) end
    pcall(function() hrp.CFrame = CFrame.lookAt(targetPos, targetPos + lookVec.Unit) end)
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end)
    local lv = PlaybackState.TrackedLVDuringPlayback
    if lv and lv.Parent and lv.Enabled then pcall(function() lv.Enabled = false end) end
    UpdatePlaybackPath(elapsed)
end
UI._StartPlayback = StartPlayback
UI._TryStartNearbyPlayback = TryStartNearbyPlayback
UI._UpdatePlayback = UpdatePlayback


-- ================= UI SHELL (INTEGRATION) =================
local Window = UI:CreateWindow({
    Title = "NOCLIPOV",
    Version = SCRIPT_VERSION,
    Theme = CFG.Theme,
    ConfigPath = CONFIG_PATH,
    OnClose = function() Cleanup() end
})
UI.ScreenGui = Window.ScreenGui

-- Pre-built Watermark & Recorder Status
UI.Watermark = Window:CreateWatermark()
UI.RecorderStatus = Window:CreateRecorderStatus()

function UI.ApplyCompactMode(enabled)
    CFG.CompactMode = enabled
    local wm = UI.Watermark
    if wm then
        if enabled then
            wm.Instance.Size = UDim2.fromOffset(280, 96)
            if wm.LivePill then wm.LivePill.Visible = false end
            if wm.SubSpeedLbl then wm.SubSpeedLbl.Visible = false end
            if wm.SpeedVal then wm.SpeedVal.Size = UDim2.new(1, -50, 0, 42); wm.SpeedVal.TextSize = 34 end
        else
            wm.Instance.Size = UDim2.fromOffset(280, 148)
            if wm.LivePill then wm.LivePill.Visible = true end
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
    local now = os.clock(); local pillText, pillColor
    if RecorderState.IsRecording then
        local dur = now - RecorderState.StartTime; pillText, pillColor = "REC", UI:GetTheme().Danger
        rs.DurVal.Text = string.format("%.1fs", dur); rs.DurVal.TextColor3 = UI:GetTheme().Danger
        rs.FramesVal.Text = tostring(#RecorderState.Frames); rs.FramesVal.TextColor3 = UI:GetTheme().Text
        rs.InfoLbl.Text = "Recording..."; rs.InfoLbl.TextColor3 = UI:GetTheme().Danger
        rs.SubLbl.Text = string.format("Press %s to stop", BindSystem.GetDisplay("Record")); rs.SubLbl.TextColor3 = UI:GetTheme().TextDim
        rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.75 + math.sin(now * math.pi * 3) * 0.15
    elseif PlaybackState.Active then
        rs.FramesVal.Text = tostring(#(PlaybackState.Frames or {})); rs.FramesVal.TextColor3 = UI:GetTheme().Text
        local elapsed = (now - (PlaybackState.StartTime or now)) * (PlaybackState.Speed or 1)
        local pct = math.clamp(elapsed / math.max(0.01, PlaybackState.Duration or 1), 0, 1)
        pillText, pillColor = "PLAY", UI:GetTheme().Accent
        rs.DurVal.Text = string.format("%.1fs", elapsed); rs.DurVal.TextColor3 = UI:GetTheme().Accent
        rs.InfoLbl.Text = PlaybackState.RecName or "?"; rs.InfoLbl.TextColor3 = UI:GetTheme().Text
        rs.SubLbl.Text = string.format("%.1f/%.1fs · %.0f%% · ×%.2f", elapsed, PlaybackState.Duration or 0, pct * 100, PlaybackState.Speed or 1)
        rs.SubLbl.TextColor3 = UI:GetTheme().TextDim; rs.ProgBg.Visible = true; rs.ProgFill.Size = UDim2.new(pct, 0, 1, 0)
        rs.Pill.BackgroundTransparency = 0.3
    elseif RecorderState.Cache then
        pillText, pillColor = "READY", UI:GetTheme().Success
        rs.DurVal.Text = string.format("%.1fs", RecorderState.Cache.duration); rs.DurVal.TextColor3 = UI:GetTheme().Success
        rs.FramesVal.Text = tostring(RecorderState.Cache.frameCount); rs.FramesVal.TextColor3 = UI:GetTheme().Text
        rs.InfoLbl.Text = "Ready to save"; rs.InfoLbl.TextColor3 = UI:GetTheme().Success
        rs.SubLbl.Text = string.format("Save in REC tab · %s to play", BindSystem.GetDisplay("Playback")); rs.SubLbl.TextColor3 = UI:GetTheme().TextDim
        rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.3
    else
        pillText, pillColor = "IDLE", UI:GetTheme().TextMuted
        rs.DurVal.Text = "--"; rs.DurVal.TextColor3 = UI:GetTheme().TextMuted
        rs.FramesVal.Text = "--"; rs.FramesVal.TextColor3 = UI:GetTheme().TextMuted
        rs.InfoLbl.Text = "Idle"; rs.InfoLbl.TextColor3 = UI:GetTheme().TextDim
        rs.SubLbl.Text = string.format("%s rec · %s play · %d saved", BindSystem.GetDisplay("Record"), BindSystem.GetDisplay("Playback"), #RecorderState.Saved)
        rs.SubLbl.TextColor3 = UI:GetTheme().TextMuted; rs.ProgBg.Visible = false; rs.Pill.BackgroundTransparency = 0.3
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

-- PLAY
PlayPage:Section("Movement")
PlayPage:Toggle({ Name = "Auto BunnyHop", Description = "Автоматический прыжок при удержании Space", Default = State.BhopEnabled, Icon = "🐇", Callback = function(v) State.BhopEnabled = v; if not v then ResetBhopState() end end })
PlayPage:Toggle({ Name = "Jump Acceleration", Description = "Увеличивает скорость при каждом прыжке", Default = State.JumpAccelEnabled, Icon = "⚡", Callback = function(v) State.JumpAccelEnabled = v end })
PlayPage:Section("Boosts")
PlayPage:Toggle({ Name = "Slope Boost", Description = "Ускорение при столкновении со склоном", Default = State.SlopeBoostEnabled, Icon = "⛷", Callback = function(v) State.SlopeBoostEnabled = v end })
PlayPage:Toggle({ Name = "Landing Boost", Description = "Добавляет скорость при мягком приземлении", Default = State.LandingBoostEnabled, Icon = "🪂", Callback = function(v) State.LandingBoostEnabled = v end })
PlayPage:Toggle({ Name = "Landing Momentum", Description = "Сохранять импульс при посадке", Default = CFG.LandingMomentum, Icon = "💨", Callback = function(v) CFG.LandingMomentum = v end })
PlayPage:Section("Utility")
PlayPage:Button({ Name = "INSTANT REVIVE", Description = "Мгновенное восстановление персонажа", Callback = TriggerSelfRevive })
PlayPage:Toggle({ Name = "Auto Revive", Description = "Автоматическое возрождение через 0.5с после смерти", Default = State.AutoReviveEnabled, Icon = "💫", Callback = function(v) State.AutoReviveEnabled = v; AutoRevive.SetEnabled(v) end })
PlayPage:Slider({ Name = "Revive Delay", Description = "Задержка перед автовозрождением (сек)", Min = 0.1, Max = 3.0, Default = CFG.AutoReviveDelay, Icon = "⏱", Decimals = 2, Callback = function(v) CFG.AutoReviveDelay = v end })
PlayPage:Toggle({ Name = "Anti-AFK", Description = "Предотвращает кик за неактивность", Default = CFG.AntiAfkEnabled, Icon = "🛡", Callback = function(v) CFG.AntiAfkEnabled = v; SetAntiAfkEnabled(v) end })

-- TUNE
TunePage:Section("Speed")
TunePage:Slider({ Name = "Gain Percent", Description = "Процент прибавки за прыжок", Min = 1, Max = 20, Default = CFG.GainPercent, Icon = "⚡", Snaps = {5, 8, 10, 12, 15, 20}, Callback = function(v) CFG.GainPercent = v end })
TunePage:Slider({ Name = "Max Speed", Description = "Максимальная скорость", Min = 50, Max = 250, Default = CFG.MaxSpeed, Icon = "🚀", Snaps = {80, 100, 120, 150, 200, 250}, Callback = function(v) CFG.MaxSpeed = v end })
TunePage:Slider({ Name = "Min Speed", Description = "Минимальная скорость", Min = 5, Max = 50, Default = CFG.MinSpeed, Icon = "🐢", Snaps = {10, 15, 20, 25, 30, 50}, Callback = function(v) CFG.MinSpeed = v end })
TunePage:Section("Adaptive Gain")
TunePage:Toggle({ Name = "Enable Adaptive Gain", Description = "Масштабирует gain по скорости", Default = CFG.AdaptiveGainEnabled, Icon = "📈", Callback = function(v) CFG.AdaptiveGainEnabled = v end })
TunePage:Slider({ Name = "Adaptive Min", Description = "Множитель gain при Max Speed", Min = 0.1, Max = 1.0, Default = CFG.AdaptiveGainMin, Icon = "🔽", Decimals = 2, Callback = function(v) CFG.AdaptiveGainMin = v end })
TunePage:Slider({ Name = "Adaptive Max", Description = "Множитель gain при нулевой скорости", Min = 1.0, Max = 2.5, Default = CFG.AdaptiveGainMax, Icon = "🔼", Decimals = 2, Callback = function(v) CFG.AdaptiveGainMax = v end })
TunePage:Section("Control")
TunePage:Slider({ Name = "Max Turn Angle", Description = "Угол сброса буста", Min = 15, Max = 180, Default = CFG.MaxTurnAngle, Icon = "📐", Snaps = {45, 60, 90, 120, 180}, Callback = function(v) CFG.MaxTurnAngle = v end })
TunePage:Slider({ Name = "Vertical Cap", Description = "Лимит по оси Y", Min = 40, Max = 100, Default = CFG.VertCap, Icon = "📈", Callback = function(v) CFG.VertCap = v end })
TunePage:Slider({ Name = "Brake Rate", Description = "Скорость торможения (Shift)", Min = 20, Max = 200, Default = CFG.BrakeRate, Icon = "🛑", Callback = function(v) CFG.BrakeRate = v end })
TunePage:Slider({ Name = "Jump Buffer", Description = "Буфер отпускания Space (сек)", Min = 0.05, Max = 0.2, Default = CFG.SmartJumpBuffer, Icon = "⏱", Decimals = 2, Callback = function(v) CFG.SmartJumpBuffer = v end })
TunePage:Section("Fall & Landing")
TunePage:Slider({ Name = "Fast Fall Force", Description = "Сила падения (X)", Min = 30, Max = 300, Default = CFG.FastFallForce, Icon = "⬇", Callback = function(v) CFG.FastFallForce = v end })
TunePage:Slider({ Name = "Land Boost %", Description = "Прибавка при посадке", Min = 0, Max = 20, Default = CFG.LandingBoostPercent, Icon = "📊", Callback = function(v) CFG.LandingBoostPercent = v end })
TunePage:Slider({ Name = "Land Soft VY", Description = "Порог мягкой посадки", Min = 10, Max = 60, Default = CFG.LandingSoftVY, Icon = "📉", Callback = function(v) CFG.LandingSoftVY = v end })
TunePage:Section("Slope Boost")
TunePage:Slider({ Name = "Slope Cooldown", Description = "Кулдаун буста (сек)", Min = 0.1, Max = 2.0, Default = CFG.SlopeCooldown, Icon = "⏱", Decimals = 2, Snaps = {0.3, 0.5, 0.75, 1.0}, Callback = function(v) CFG.SlopeCooldown = v end })
TunePage:Slider({ Name = "Slope Min Speed", Description = "Мин. скорость для буста", Min = 10, Max = 100, Default = CFG.SlopeMinSpeed, Icon = "🐢", Snaps = {15, 25, 35, 50}, Callback = function(v) CFG.SlopeMinSpeed = v end })
TunePage:Slider({ Name = "Slope Base Gain", Description = "Базовый множитель буста", Min = 1.0, Max = 2.0, Default = CFG.SlopeBaseGain, Icon = "⚡", Decimals = 2, Snaps = {1.1, 1.2, 1.35, 1.5}, Callback = function(v) CFG.SlopeBaseGain = v end })
TunePage:Slider({ Name = "Slope Max Gain", Description = "Макс. множитель буста", Min = 1.5, Max = 4.0, Default = CFG.SlopeMaxGain, Icon = "🚀", Decimals = 2, Snaps = {1.8, 2.2, 2.8, 3.5}, Callback = function(v) CFG.SlopeMaxGain = v end })
TunePage:Slider({ Name = "Slope Vert Boost", Description = "Множитель вертикали (0 = только горизонталь)", Min = 0.0, Max = 2.0, Default = CFG.SlopeVertBoost, Icon = "⛷", Decimals = 2, Callback = function(v) CFG.SlopeVertBoost = v end })

-- VIS
VisPage:Section("Effects")
VisPage:Toggle({ Name = "Landing Prediction", Description = "Визуальный таймер до приземления", Default = State.LandPredEnabled, Icon = "🎯", Callback = function(v)
    State.LandPredEnabled = v
    if not v then PredState.FadeState = "hidden"; PredState.FadeProgress = 0; PredState.IdleTime = 0; DestroyPred() end
end })
VisPage:Section("Markers")
VisPage:Toggle({ Name = "Show Markers", Description = "Отображает маршруты в мире", Default = State.MarkersEnabled, Icon = "📍", Callback = function(v) SetMarkersVisible(v) end })
VisPage:Slider({ Name = "Marker Range", Description = "Дистанция видимости", Min = 20, Max = 1000, Default = CFG.MarkerMaxDist, Icon = "📏", Callback = function(v) CFG.MarkerMaxDist = v end })
VisPage:Section("Interface")
VisPage:Toggle({ Name = "Status Window", Description = "Монитор скорости и FPS", Default = State.WatermarkEnabled, Icon = "📊", Callback = function(v) State.WatermarkEnabled = v; UI.Watermark.Instance.Visible = v end })
VisPage:Toggle({ Name = "Recorder Status", Description = "Монитор записи", Default = State.RecorderStatusEnabled, Icon = "🎬", Callback = function(v) State.RecorderStatusEnabled = v; UI.RecorderStatus.Instance.Visible = v end })
VisPage:Toggle({ Name = "Compact Mode", Description = "Компактные окна", Default = CFG.CompactMode, Icon = "🗜", Callback = function(v) UI.ApplyCompactMode(v) end })

-- KEYS
HotkeysPage:Section("Keybinds")
HotkeysPage:Label("ЛКМ — назначить, ПКМ — сбросить, Backspace — очистить")
local HotkeysList = {
    {id="Bhop", title="Toggle Bhop", default=Enum.KeyCode.B},
    {id="Accel", title="Toggle Jump Accel", default=Enum.KeyCode.J},
    {id="Slope", title="Toggle Slope Boost", default=Enum.KeyCode.V},
    {id="Land", title="Toggle Landing Boost", default=Enum.KeyCode.N},
    {id="Pred", title="Toggle Prediction", default=Enum.KeyCode.M},
    {id="Record", title="Toggle Record", default=Enum.KeyCode.F},
    {id="Playback", title="Play Nearby", default=Enum.KeyCode.P},
    {id="CycleSpeed", title="Cycle Playback Speed", default=Enum.KeyCode.O},
    {id="Brake", title="Brake (Hold)", default=Enum.KeyCode.LeftShift},
    {id="Fall", title="Fast Fall (Hold)", default=Enum.KeyCode.X},
    {id="UI", title="Toggle UI", default=Enum.KeyCode.RightShift},
}
for _, item in ipairs(HotkeysList) do
    HotkeysPage:Keybind({ Name = item.title, ActionId = item.id, Default = item.default })
end

-- REC
RecPage:Section("Info")
UI.RecHelpLabel = RecPage:Label("", { height = 34 })
RecPage:Section("Playback")
RecPage:Slider({ Name = "Playback Speed", Description = "Скорость воспроизведения", Min = 0.5, Max = 3.0, Default = CFG.PlaybackSpeed, Icon = "⏩", Decimals = 2, Snaps = {0.5, 1.0, 1.5, 2.0, 2.5, 3.0}, Callback = function(v) CFG.PlaybackSpeed = v; SetPlaybackSpeed(v) end })
RecPage:Section("Trim")
RecPage:Slider({ Name = "Trim Threshold", Description = "Порог движения", Min = 0.2, Max = 5.0, Default = CFG.TrimThreshold, Icon = "📐", Decimals = 2, Callback = function(v) CFG.TrimThreshold = v end })

RecPage:Section("Status")
UI.RecStatusLabel = RecPage:Label("Idle", { height = 40, size = 12, theme = "TextMuted" })

RecPage:Section("Save")
UI.RecNameBox = RecPage:TextBox({ Name = "Recording Name", Placeholder = "Enter name...", Callback = function(v) end }).TextBox
local btnRow = RecPage:Custom({ Size = UDim2.new(1, 0, 0, 40) })
UI.GUI.CreateInstance("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0, 8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=btnRow })

local function MakeRecBtn(parent, text, themeKey, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, -4, 1, 0); btn.BackgroundColor3 = UI:GetTheme()[themeKey]
    btn.BackgroundTransparency = 0.75; btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false
    btn.LayoutOrder = order; btn.Parent = parent
    UI.GUI.ThemeSystem.Bind(btn, {BackgroundColor3 = themeKey}); UI.GUI.Corner(btn, 8); UI.GUI.Gradient(btn, themeKey, "BgDarkest", 45)
    local st = UI.GUI.Stroke(btn, themeKey, 1, 0.4)
    UI.GUI.ApplyHover(btn, {scale=1.02, stroke=st, hoverStrokeColor=themeKey, hoverStrokeTransp=0.1, baseStrokeColor=themeKey})
    UI.GUI.ApplyPress(btn, {pressScale=0.97, hoverScale=1.02})
    local lbl = UI.GUI.MakeLabel(btn, { Text=text, TextTheme="TextMuted", TextSize=11, Font=Enum.Font.GothamBold, TextTransparency=0.4, TextXAlignment=Enum.TextXAlignment.Center })
    return btn, lbl
end
UI.RecSaveBtn, UI.RecSaveLbl = MakeRecBtn(btnRow, "SAVE", "Accent", 1)
UI.RecCancelBtn, UI.RecCancelLbl = MakeRecBtn(btnRow, "CANCEL", "SurfaceBase", 2)

TrackConnection(UI.RecSaveBtn.MouseButton1Click:Connect(function()
    if not RecorderState.InputEnabled or not RecorderState.Cache then return end
    local name = (UI.RecNameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[^%w_%-%(%) ]", "")
    if name == "" then UI.RecNameBox.PlaceholderText = "Enter a valid name"; return end
    for _, rec in ipairs(RecorderState.Saved) do
        if rec.name == name then UI.RecNameBox.PlaceholderText = "Name already in use"; return end
    end
    if RecorderState.RecSaveToFile(name, RecorderState.Cache.frames, RecorderState.Cache.duration) then
        RecorderState.Cache = nil; DestroyUnsavedMarker()
        UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
        RecorderState.RecSetInputEnabled(false)
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Saved: " .. name; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Success end
        RecorderState.Saved = RecorderState.RecLoadAll()
        if RefreshMarkers then RefreshMarkers() end
        if RefreshRecorderList then RefreshRecorderList() end
        NotificationSystem.Push("Saved: " .. name, "success", 2)
    else
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Save failed"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Danger end
        NotificationSystem.Push("Save failed", "error", 3)
    end
end))

TrackConnection(UI.RecCancelBtn.MouseButton1Click:Connect(function()
    if not RecorderState.InputEnabled then return end
    RecorderState.Cache = nil; DestroyUnsavedMarker()
    UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..."
    RecorderState.RecSetInputEnabled(false)
    if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Idle"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().TextMuted end
    if RefreshMarkers then RefreshMarkers() end
    if RefreshRecorderList then task.defer(RefreshRecorderList) end
end))

RecPage:Section("Recordings")
local recList = RecPage:List({ Size = UDim2.new(1, 0, 0, 200) })

local clearAllBtn = RecPage:Button({ Name = "🗑 CLEAR ALL RECORDINGS", Description = "Удалить все записи", Callback = function()
    if RecorderState.IsRecording then NotificationSystem.Push("Остановите запись", "warning", 2); return end
    local count = 0
    for _, rec in ipairs(RecorderState.Saved) do
        if RecorderState.RecDeleteFile(rec.path) then count = count + 1 end
        DestroyMarker(rec.name)
    end
    RecorderState.Saved = {}; RecorderState.Cache = nil; DestroyUnsavedMarker()
    if RefreshRecorderList then RefreshRecorderList() end
    if RefreshMarkers then RefreshMarkers() end
    NotificationSystem.Push(string.format("Deleted %d recordings", count), "warning", 3)
end })
local clearSt = clearAllBtn.Instance:FindFirstChildOfClass("UIStroke")
if clearSt then UI.GUI.ApplyHover(clearAllBtn.Instance, {scale=1.01, stroke=clearSt, hoverStrokeColor="Danger", hoverStrokeTransp=0.3, baseStrokeColor="AccentSoft"}) end

RefreshRecorderList = function()
    recList:Clear()
    if #RecorderState.Saved == 0 then
        recList:AddItem({ Icon = "ℹ", Title = "No recordings", Subtitle = "Record a path first", OnPlay = nil, OnDelete = nil })
    else
        for _, rec in ipairs(RecorderState.Saved) do
            local metaStr = rec.mapName or ""
            if rec.createdAt then
                local ok, dateStr = pcall(function() return os.date("%d.%m.%Y", rec.createdAt) end)
                if ok and dateStr then metaStr = (metaStr ~= "" and (metaStr .. " · " .. dateStr)) or dateStr end
            end
            recList:AddItem({
                Icon = "🎬",
                Title = rec.name,
                Subtitle = string.format("%.1fs · %d frames · %s", rec.duration, rec.frameCount, metaStr),
                OnPlay = function()
                    if RecorderState.IsRecording then
                        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Сначала остановите запись"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
                        return
                    end
                    local isPlaying = PlaybackState.Active and PlaybackState.RecName == rec.name
                    if isPlaying then StopPlayback()
                    else
                        local _, decoded = RecorderState.RecReadFirstFrame(rec.path)
                        if decoded then StartPlayback(rec.name, decoded.frames, decoded.duration) end
                    end
                end,
                OnDelete = function()
                    if RecorderState.IsRecording then
                        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Сначала остановите запись"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
                        return
                    end
                    RecorderState.RecDeleteFile(rec.path); DestroyMarker(rec.name)
                    task.defer(function() RecorderState.Saved = RecorderState.RecLoadAll(); RefreshRecorderList() end)
                    NotificationSystem.Push("Deleted: " .. rec.name, "warning", 2)
                end
            })
        end
    end
end

task.defer(function()
    RecorderState.Saved = RecorderState.RecLoadAll()
    if RefreshRecorderList then RefreshRecorderList() end
end)


-- ================= CONFIG LOAD / SAVE =================
do
    local ToggleMap = {
        BhopEnabled="Auto BunnyHop", JumpAccelEnabled="Jump Acceleration",
        SlopeBoostEnabled="Slope Boost", LandingBoostEnabled="Landing Boost",
        LandPredEnabled="Landing Prediction",
        WatermarkEnabled="Status Window", MarkersEnabled="Show Markers",
        RecorderStatusEnabled="Recorder Status", AutoReviveEnabled="Auto Revive",
        AdaptiveGainEnabled="Enable Adaptive Gain", CompactMode="Compact Mode",
        AntiAfkEnabled="Anti-AFK", NotifyEnabled="Notifications",
        LandingMomentum="Landing Momentum",
    }
    local SliderMap = {
        GainPercent="Gain Percent", MaxSpeed="Max Speed", VertCap="Vertical Cap",
        MaxTurnAngle="Max Turn Angle", BrakeRate="Brake Rate", MinSpeed="Min Speed",
        FastFallForce="Fast Fall Force", LandingBoostPercent="Land Boost %",
        LandingSoftVY="Land Soft VY", MarkerMaxDist="Marker Range",
        AdaptiveGainMin="Adaptive Min", AdaptiveGainMax="Adaptive Max",
        PlaybackSpeed="Playback Speed", TrimThreshold="Trim Threshold", UIScale="UI Scale",
        SmartJumpBuffer="Jump Buffer", AutoReviveDelay="Revive Delay",
        SlopeVertBoost="Slope Vert Boost", SlopeCooldown="Slope Cooldown",
        SlopeMinSpeed="Slope Min Speed", SlopeBaseGain="Slope Base Gain", SlopeMaxGain="Slope Max Gain",
    }

    local function UDim2ToTable(u)
        return {XScale = u.X.Scale, XOffset = u.X.Offset, YScale = u.Y.Scale, YOffset = u.Y.Offset}
    end
    local function TableToUDim2(t)
        if type(t) ~= "table" then return nil end
        return UDim2.new(tonumber(t.XScale) or 0, tonumber(t.XOffset) or 0, tonumber(t.YScale) or 0, tonumber(t.YOffset) or 0)
    end
    local function Log(msg) pcall(function() warn("[Noclipov] " .. tostring(msg)) end) end

    local writeInFlight, writeQueued = false, false
    local configLoading = false

    local function BuildSaveData()
        local data = {
            version = SCRIPT_VERSION, IsVisible = Window.IsVisible, Theme = UI:GetThemeName(),
            MainFramePos = UDim2ToTable(Window.MainFrame.Position),
            LauncherPos = UDim2ToTable(Window.LauncherIcon.Position),
            WatermarkPos = UDim2ToTable(UI.Watermark.Instance.Position),
            RecorderStatusPos = UDim2ToTable(UI.RecorderStatus.Instance.Position),
            Hotkeys = {}, Toggles = {}, Sliders = {},
        }
        for _, item in ipairs(HotkeysList) do data.Hotkeys[item.id] = BindSystem.Serialize(item.id) end
        for k, v in pairs(State) do if type(v) == "boolean" then data.Toggles[k] = v end end
        for k, v in pairs(CFG) do
            if type(v) == "boolean" then data.Toggles[k] = v
            elseif type(v) == "number" then data.Sliders[k] = v end
        end
        return data
    end

    local function DoSaveConfigNow()
        local data = BuildSaveData()
        local encOk, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if not encOk or type(encoded) ~= "string" then Log("SAVE FAIL: JSONEncode"); return false end
        local writeOk, writeErr = pcall(writefile, CONFIG_PATH, encoded)
        if not writeOk then Log("SAVE FAIL: " .. tostring(writeErr)); return false end
        pcall(writefile, CONFIG_BAK_PATH, encoded)
        return true
    end

    SaveConfig = function()
        if configLoading then return end
        writeQueued = true
        if writeInFlight then return end
        writeInFlight = true
        task.spawn(function()
            while writeQueued do
                writeQueued = false
                pcall(DoSaveConfigNow)
            end
            writeInFlight = false
        end)
    end

    LoadConfig = function()
        configLoading = true
        local content, source = nil, "none"
        pcall(function() if isfile and isfile(CONFIG_PATH) then content = readfile(CONFIG_PATH); source = "primary" end end)
        if not content or #tostring(content) == 0 then pcall(function() content = readfile(CONFIG_BAK_PATH); source = "backup" end) end
        if not content or #tostring(content) == 0 then configLoading = false; Log("LOAD: no content"); return end
        local jsonOk, data = pcall(function() return HttpService:JSONDecode(content) end)
        if not jsonOk or type(data) ~= "table" then configLoading = false; Log("LOAD FAIL: invalid JSON"); return end
        
        if data.IsVisible ~= nil then Window.IsVisible = data.IsVisible == true end
        if type(data.Theme) == "string" and UI.Themes[data.Theme] then UI:SetTheme(data.Theme) else UI:SetTheme("Amethyst") end

        local p = TableToUDim2(data.MainFramePos); if p then Window.MainFrame.Position = p end
        p = TableToUDim2(data.LauncherPos); if p then Window.LauncherIcon.Position = p end
        p = TableToUDim2(data.WatermarkPos); if p then UI.Watermark.Instance.Position = p end
        p = TableToUDim2(data.RecorderStatusPos); if p then UI.RecorderStatus.Instance.Position = p end

        if type(data.Hotkeys) == "table" then
            for _, item in ipairs(HotkeysList) do
                local val = data.Hotkeys[item.id]
                BindSystem.Bindings[item.id] = nil
                if type(val) == "table" then BindSystem.Bindings[item.id] = BindSystem.Deserialize(val)
                elseif type(val) == "string" and val ~= "None" then
                    local kc = Enum.KeyCode[val]
                    if kc then BindSystem.Bindings[item.id] = {type = "key", value = kc} end
                end
                BindSystem.UpdateButton(item.id)
            end
            BindSystem.Held = {}
        end

        if type(data.Toggles) == "table" then
            for stateKey, uiName in pairs(ToggleMap) do
                local v = data.Toggles[stateKey]
                if v ~= nil and UI.Refs.Toggle[uiName] then UI.Refs.Toggle[uiName](v == true) end
            end
        end
        if type(data.Sliders) == "table" then
            for cfgKey, uiName in pairs(SliderMap) do
                local v = data.Sliders[cfgKey]
                if v ~= nil and type(v) == "number" and v == v then
                    CFG[cfgKey] = v
                    if UI.Refs.Slider[uiName] then UI.Refs.Slider[uiName](v) end
                end
            end
        end

        local sc = math.clamp(CFG.UIScale or 1.0, 0.7, 1.5)
        Window:SetScale(sc)

        pcall(function() SetAntiAfkEnabled(CFG.AntiAfkEnabled == true) end)
        pcall(function() AutoRevive.SetEnabled(State.AutoReviveEnabled == true) end)
        pcall(function() UI.ApplyCompactMode(CFG.CompactMode == true) end)
        pcall(function() SetPlaybackSpeed(CFG.PlaybackSpeed or 1.0) end)
        configLoading = false
        Log("LOAD OK from " .. source .. " (v" .. (data.version or "?") .. ")")
    end
end

-- ================= CHARACTER EVENTS =================
TrackConnection(LocalPlayer.CharacterRemoving:Connect(function()
    FullCharacterReset()
    if RecorderState.IsRecording then
        RecorderState.IsRecording = false
        RecorderState.Frames = {}; RecorderState.FrameAccum = 0; RecorderState.Cache = nil
        if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Interrupted"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
        RecorderState.RecSetInputEnabled(false)
        if RefreshMarkers then RefreshMarkers() end
    end
end))
TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
    FullCharacterReset()
    task.delay(0.5, SweepLegacyWorkspace)
    task.delay(1, function() RecorderState.Saved = RecorderState.RecLoadAll(); if RefreshRecorderList then RefreshRecorderList() end end)
end))

-- ================= INPUT =================
do
    local TOGGLE_STATE_MAP = {
        Bhop  = {uiName = "Auto BunnyHop",      stateKey = "BhopEnabled"},
        Accel = {uiName = "Jump Acceleration",  stateKey = "JumpAccelEnabled"},
        Slope = {uiName = "Slope Boost",        stateKey = "SlopeBoostEnabled"},
        Land  = {uiName = "Landing Boost",      stateKey = "LandingBoostEnabled"},
        Pred  = {uiName = "Landing Prediction", stateKey = "LandPredEnabled"},
    }

    local function DispatchAction(actionId)
        local toggle = TOGGLE_STATE_MAP[actionId]
        if toggle and UI.Refs.Toggle[toggle.uiName] then UI.Refs.Toggle[toggle.uiName](not State[toggle.stateKey]); return end
        if actionId == "Record" then
            if RecorderState.IsRecording then RecorderState.RecStop(true) else RecorderState.RecStart() end
            return
        end
        if actionId == "Playback" then UI._TryStartNearbyPlayback(); return end
        if actionId == "CycleSpeed" then
            local speeds = {0.5, 1.0, 1.5, 2.0, 2.5, 3.0}
            local cur = CFG.PlaybackSpeed or 1.0
            local bestIdx, bestDiff = 1, math.huge
            for i, s in ipairs(speeds) do
                local d = math.abs(s - cur)
                if d < bestDiff then bestDiff = d; bestIdx = i end
            end
            local nextIdx = (bestIdx % #speeds) + 1
            SetPlaybackSpeed(speeds[nextIdx])
            if UI.Refs.Slider["Playback Speed"] then UI.Refs.Slider["Playback Speed"](speeds[nextIdx]) end
            NotificationSystem.Push(string.format("Playback ×%.1f", speeds[nextIdx]), "info", 1.5)
            return
        end
        if actionId == "UI" then
            if Window.IsVisible then Window:Hide() else Window:Show() end
            return
        end
    end

    TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
        if BindSystem.Capture then
            local cap = BindSystem.Capture
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then BindSystem.CaptureCancel(); NotificationSystem.Push("Bind cancelled", "info", 1.5); return end
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Backspace then local id = cap.actionId; BindSystem.CaptureCancel(); BindSystem.Clear(id); NotificationSystem.Push("Bind cleared", "info", 1.5); return end
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then NotificationSystem.Push("Space is reserved", "warning", 1.5); return end
            if UserInputService:GetFocusedTextBox() then BindSystem.CaptureCancel(); return end
            local binding = BindSystem.InputToBinding(input)
            if binding then BindSystem.CaptureComplete(binding) end
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
        for actionId, binding in pairs(BindSystem.Bindings) do
            if BindSystem.MatchBinding(binding, input) then BindSystem.Held[actionId] = nil end
        end
    end))

    TrackConnection(UserInputService.TextBoxFocused:Connect(function() State.IsHoldingJump = false end))
end

-- ================= STEPPED =================
TrackConnection(RunService.Stepped:Connect(function(_, dt)
    if PlaybackState.Active then return end
    if State.BhopEnabled then TryBhop(dt) end
    if State.SlopeBoostEnabled then TrySlopeBoost() end
end))

-- ================= HEARTBEAT =================
do
    local lastOrphanSweep, lastUIUpdate, lastTelemetryUpdate = 0, 0, 0
    local lastRecStatus, lastRecHelp, lastMarkerPulse = 0, 0, 0
    local fpsFrames, fpsAccum, cachedPing = 0, 0, 0

    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        if BindSystem.Capture then BindSystem.CaptureTick() end

        if RecorderState.IsRecording then
            RecorderState.FrameAccum = RecorderState.FrameAccum + dt
            if RecorderState.FrameAccum >= RECORD_HZ then
                RecorderState.FrameAccum = RecorderState.FrameAccum - RECORD_HZ
                local hrp = GetHrp()
                if hrp then
                    local t = os.clock() - RecorderState.StartTime
                    local cf = hrp.CFrame
                    local v = hrp.AssemblyLinearVelocity
                    table.insert(RecorderState.Frames, {
                        t=t, px=cf.X, py=cf.Y, pz=cf.Z, vx=v.X, vy=v.Y, vz=v.Z,
                        lx=cf.LookVector.X, ly=cf.LookVector.Y, lz=cf.LookVector.Z,
                    })
                    if UI.RecStatusLabel then UI.RecStatusLabel.Text = string.format("● REC  %.1fs · %d", t, #RecorderState.Frames) end
                end
            end
        end

        if PlaybackState.Active then UI._UpdatePlayback() end

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

        -- Watermark
        if now - lastUIUpdate > 0.05 then
            lastUIUpdate = now
            local wm = UI.Watermark
            if wm and wm.Instance.Visible then
                fpsFrames = fpsFrames + 1; fpsAccum = fpsAccum + dt
                if now - lastTelemetryUpdate > 0.5 then
                    lastTelemetryUpdate = now
                    if fpsAccum > 0 then wm.FpsVal.Text = tostring(math.floor(fpsFrames / fpsAccum + 0.5)) end
                    fpsFrames, fpsAccum = 0, 0
                    pcall(function() cachedPing = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                    wm.PingVal.Text = tostring(cachedPing)
                    wm.PingVal.TextColor3 = cachedPing < 80 and UI:GetTheme().Success or cachedPing < 150 and UI:GetTheme().Warning or UI:GetTheme().Danger
                end
                local hrp = GetHrp()
                if hrp then
                    local spd = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
                    if spd > SessionStats.MaxSpeed then SessionStats.MaxSpeed = spd end
                    displaySpeed = displaySpeed + (spd - displaySpeed) * math.min(1, dt * 15)
                    wm.SpeedVal.Text = string.format("%.1f", displaySpeed)
                    wm.MaxVal.Text = string.format("%.0f", CFG.MaxSpeed)
                    wm.TimeVal.Text = FormatTime(now - SessionStats.StartTime)
                    local pct = math.clamp(displaySpeed / math.max(1, CFG.MaxSpeed), 0, 1)
                    wm.SpeedBarFill.Size = UDim2.new(pct, 0, 1, 0)
                    wm.SpeedBarFill.BackgroundColor3 = pct >= 0.9 and UI:GetTheme().Success or UI:GetTheme().Accent

                    local st = BhopState.CurrentStatus
                    local sText, sColor
                    if st == "GAIN" then
                        local g = CFG.GainPercent
                        if CFG.AdaptiveGainEnabled and displaySpeed > 1 then
                            local norm = math.clamp(displaySpeed / math.max(CFG.MaxSpeed, 1), 0, 1)
                            g = g * (CFG.AdaptiveGainMax - norm * (CFG.AdaptiveGainMax - CFG.AdaptiveGainMin))
                        end
                        sText = string.format("+%.0f", g); sColor = UI:GetTheme().Success
                    elseif st == "BRAKE" then sText, sColor = "BRAKE", UI:GetTheme().Danger
                    elseif st == "AIR" then sText, sColor = "AIR", UI:GetTheme().Accent
                    elseif st == "NO CHAR" then sText, sColor = "N/A", UI:GetTheme().Warning
                    elseif st == "DISABLED" then sText, sColor = "OFF", UI:GetTheme().TextMuted
                    elseif st == "IDLE" then sText, sColor = "IDLE", UI:GetTheme().TextMuted
                    else sText, sColor = st or "—", UI:GetTheme().TextMuted end

                    wm.LiveLbl.Text = sText; wm.LiveLbl.TextColor3 = sColor
                    wm.LiveDot.BackgroundColor3 = sColor

                    if PlaybackState.Active then
                        wm.SpeedBadge.Visible = true
                        wm.SpeedBadgeLbl.Text = string.format("×%.2f", PlaybackState.Speed or 1)
                        wm.SubSpeedLbl.Text = "SPEED · PLAYBACK"; wm.SubSpeedLbl.TextColor3 = UI:GetTheme().Accent
                    else
                        wm.SpeedBadge.Visible = false
                        wm.SubSpeedLbl.Text = "CURRENT SPEED"; wm.SubSpeedLbl.TextColor3 = UI:GetTheme().TextMuted
                    end
                else
                    wm.SpeedVal.Text = "-"; wm.LiveLbl.Text = "—"; wm.LiveLbl.TextColor3 = UI:GetTheme().TextMuted
                    wm.LiveDot.BackgroundColor3 = UI:GetTheme().TextMuted; wm.SpeedBarFill.Size = UDim2.new(0, 0, 1, 0)
                end

                local isActive = (BhopState.CurrentStatus == "GAIN" or BhopState.CurrentStatus == "BRAKE" or BhopState.CurrentStatus == "AIR")
                local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 3)
                wm.LivePill.BackgroundTransparency = isActive and (0.15 + pulse * 0.15) or 0.3
                if BhopState.CurrentStatus == "GAIN" then wm.LivePill.BackgroundColor3 = UI:GetTheme().Success:Lerp(UI:GetTheme().SurfaceBase, pulse * 0.3) end
            end
        end

        -- Marker Pulse
        if now - lastMarkerPulse > 0.05 then
            lastMarkerPulse = now
            if State.MarkersEnabled or UnsavedMarker or PlaybackState.StartMarker then
                local hrp = GetHrp()
                if hrp then
                    local hrpPos = hrp.Position; local maxDist = CFG.MarkerMaxDist or 500
                    local function tickMarker(m)
                        if not m or not m.cap or not m.cap.Parent then return end
                        local dist = (hrpPos - m.startPos).Magnitude; local far = dist > maxDist
                        if far ~= m.isFar then
                            m.isFar = far
                            if m.halo then m.halo.Transparency = far and 1 or 0.92 end
                            if m.ringInner then m.ringInner.Transparency = far and 1 or 0.4 end
                            if m.ring then m.ring.Transparency = far and 1 or 0.25 end
                            if m.ringGlow then m.ringGlow.Enabled = not far end
                            if m.ringOuter then m.ringOuter.Transparency = far and 1 or 0.85 end
                            if m.crystal then m.crystal.Transparency = far and 1 or 0.15 end
                            if m.cap then m.cap.Transparency = far and 1 or 0 end
                            if m.glow then m.glow.Transparency = far and 1 or 0.7 end
                            if m.pillar then m.pillar.Enabled = not far end
                            if m.particles then m.particles.Enabled = not far end
                            if m.light then m.light.Enabled = not far end
                            if m.billboard then m.billboard.Enabled = not far end
                        end
                        if not far then
                            local phase = m.pulsePhase or 0; local nowSpin = now * 0.8 + phase
                            local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2 + phase)
                            local bob = math.sin(now * 1.5 + phase) * 0.08
                            if m.root then m.root.Position = m.startPos end
                            if m.cap then m.cap.CFrame = CFrame.new(m.startPos + Vector3.new(0, 2.85 + bob, 0)); m.cap.Transparency = pulse * 0.08 end
                            if m.crystal then m.crystal.CFrame = CFrame.new(m.startPos + Vector3.new(0, 2.0 + bob * 0.6, 0)) * CFrame.Angles(0, nowSpin * 1.4, 0); m.crystal.Transparency = 0.15 + pulse * 0.1 end
                            if m.ring then m.ring.CFrame = CFrame.new(m.startPos + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, -nowSpin * 0.6, math.rad(90)); m.ring.Transparency = 0.25 + pulse * 0.08 end
                            if m.ringInner then m.ringInner.CFrame = CFrame.new(m.startPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, nowSpin * 1.2, math.rad(90)); m.ringInner.Transparency = 0.4 + pulse * 0.1 end
                            if m.ringOuter then m.ringOuter.CFrame = CFrame.new(m.startPos + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, nowSpin * 1.8, math.rad(90)); m.ringOuter.Transparency = 0.85 + pulse * 0.05 end
                            if m.halo then m.halo.Transparency = 0.92 + pulse * 0.03; m.halo.Size = Vector3.new(0.05, 5.5 + pulse * 0.3, 5.5 + pulse * 0.3) end
                            if m.glow and m.cap then m.glow.Position = m.cap.Position end
                            if m.ringGlow then m.ringGlow.Brightness = 0.25 + pulse * 0.2 end
                            if m.light then m.light.Brightness = 0.6 + pulse * 0.4 end
                        end
                    end
                    for _, m in pairs(MarkerParts) do tickMarker(m) end
                    if UnsavedMarker then tickMarker(UnsavedMarker) end
                    if PlaybackState.StartMarker then tickMarker(PlaybackState.StartMarker) end
                end
            end
        end
    end))
end

-- ================= MAP WATCH =================
do
    local MapSystem = { LastMapName = RecorderState.GetMapName(), AttrConn = nil, ReloadDebounce = nil }
    local function HandleChange()
        if MapSystem.ReloadDebounce then return end
        MapSystem.ReloadDebounce = true
        task.delay(0.2, function()
            MapSystem.ReloadDebounce = nil; MapSystem.LastMapName = RecorderState.GetMapName()
            if RecorderState.IsRecording or RecorderState.Cache then
                RecorderState.IsRecording = false; RecorderState.Frames = {}; RecorderState.FrameAccum = 0; RecorderState.Cache = nil
                RecorderState.RecSetInputEnabled(false); DestroyUnsavedMarker()
                if UI.RecNameBox then UI.RecNameBox.Text = ""; UI.RecNameBox.PlaceholderText = "Recording name..." end
                if UI.RecStatusLabel then UI.RecStatusLabel.Text = "Interrupted (map changed)"; UI.RecStatusLabel.TextColor3 = UI:GetTheme().Warning end
            end
            if PlaybackState.Active then StopPlayback() end
            RecorderState.Saved = RecorderState.RecLoadAll()
            if RefreshRecorderList then task.defer(function() RefreshRecorderList(); if State.MarkersEnabled then RefreshMarkers() end end) end
        end)
    end
    local function Bind(map)
        if MapSystem.AttrConn then pcall(function() MapSystem.AttrConn:Disconnect() end); MapSystem.AttrConn = nil end
        if not map then return end
        MapSystem.AttrConn = TrackConnection(map:GetAttributeChangedSignal("MapName"):Connect(function()
            local newName = RecorderState.GetMapName()
            if newName ~= MapSystem.LastMapName then MapSystem.LastMapName = newName; HandleChange() end
        end))
    end
    TrackConnection(workspace.ChildAdded:Connect(function(child) if child.Name == "Map" then Bind(child); HandleChange() end end))
    TrackConnection(workspace.ChildRemoved:Connect(function(child) if child.Name == "Map" then MapSystem.LastMapName = "Unknown"; HandleChange() end end))
    local map = workspace:FindFirstChild("Map"); if map then Bind(map) end
    task.spawn(function()
        local lastSafety = RecorderState.GetMapName()
        while UI.ScreenGui and UI.ScreenGui.Parent and not Disposer.disposed do
            task.wait(5)
            local now = RecorderState.GetMapName()
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
    if not BindSystem.Bindings[item.id] then BindSystem.Bindings[item.id] = {type = "key", value = item.default} end
    BindSystem.UpdateButton(item.id)
end

if not Window.IsVisible then Window.MainFrame.Visible = false end
task.defer(function() SweepOrphanPredParts(true) end)
task.delay(0.5, function() NotificationSystem.Push("Noclipov v" .. SCRIPT_VERSION .. " loaded", "success", 3) end)

-- ================= CLEANUP =================
Cleanup = function()
    if Disposer.disposed then return end
    pcall(function()
        local data = { version = SCRIPT_VERSION, IsVisible = Window.IsVisible, Theme = UI:GetThemeName(), Hotkeys = {}, Toggles = {}, Sliders = {} }
        for _, item in ipairs(HotkeysList) do data.Hotkeys[item.id] = BindSystem.Serialize(item.id) end
        for k, v in pairs(State) do if type(v) == "boolean" then data.Toggles[k] = v end end
        for k, v in pairs(CFG) do if type(v) == "boolean" then data.Toggles[k] = v elseif type(v) == "number" then data.Sliders[k] = v end end
        local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if ok and encoded then pcall(writefile, CONFIG_PATH, encoded) end
    end)

    for k in pairs(State) do if type(State[k]) == "boolean" then State[k] = false end end
    pcall(function() SetAntiAfkEnabled(false) end)
    pcall(function() AutoRevive.SetEnabled(false) end)
    pcall(function() if AntiAfk.conn then AntiAfk.conn:Disconnect(); AntiAfk.conn = nil end end)
    pcall(function() ResetBhopState() end)
    pcall(function() StopPlayback(true) end)
    pcall(function() ClearPlaybackPath() end)
    pcall(function() DestroyPlaybackStartMarker() end)
    pcall(function() DestroyUnsavedMarker() end)
    for name in pairs(MarkerParts) do pcall(function() DestroyMarker(name) end) end
    if BhopState.HumStateConn then pcall(function() BhopState.HumStateConn:Disconnect() end); BhopState.HumStateConn = nil end
    pcall(DestroyPred)
    Disposer:dispose()
    if Window then pcall(function() Window:Destroy() end) end
    SweepLegacyWorkspace()
    if ENV[ENV_CLEANUP_KEY] == Cleanup then ENV[ENV_CLEANUP_KEY] = nil end
end
ENV[ENV_CLEANUP_KEY] = Cleanup