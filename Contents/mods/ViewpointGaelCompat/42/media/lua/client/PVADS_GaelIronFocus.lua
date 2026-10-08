-- Experimental iron focus and GOL sway; dynamic values never enter the saved profile.
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFov = nil
local wheelFocused = nil
local NO_REFERENCE_IRONS = { ["Base.GOL"] = true }
local SWAY_LIMIT = 25.0 -- Temporary diagnostic amplitude for live PVADS profile motion.
local SWAY_SPEED_INTERVAL = 0.25
local SWAY_STEP_MIN = 0.5
local SWAY_STEP_MAX = 2.0
local swayKey = nil
local swayApplied = false
local swayAt = nil
local swayYaw, swayPitch = 0, 0
local targetYaw, targetPitch = 0, 0
local speedYaw, speedPitch = 0, 0
local swayReachedLogged = false
local lastSwayPushAt = nil
local SWAY_PUSH_INTERVAL_MS = 50

local function settings()
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = not vars or vars.CrouchIronFocus ~= false
    local wheelEnabled = not vars or vars.WheelIronFocus ~= false
    local multiplier = tonumber(vars and vars.CrouchIronFocusMultiplier) or 0.70
    return enabled, wheelEnabled, math.max(0.30, math.min(1.00, multiplier))
end

local function randomTarget(current, limit)
    for _ = 1, 8 do
        local side = ZombRand(2) == 0 and -1 or 1
        local target = side * limit * (0.6 + ZombRand(401) / 1000)
        if math.abs(target - current) >= limit * 0.5 then return target end
    end
    return current >= 0 and -limit or limit
end

local function randomSpeed()
    return (SWAY_STEP_MIN + (SWAY_STEP_MAX - SWAY_STEP_MIN) * ZombRand(1001) / 1000) / SWAY_SPEED_INTERVAL
end

local function approach(value, target, step)
    if math.abs(target - value) <= step then return target end
    return value + (target > value and step or -step)
end

local function updateNoReferenceSway(controller, profile, iron)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local calibrator = PVADS.Calibrator
    local calibrating = calibrator and calibrator.window and calibrator.window:isVisible()
    local eligible = (not vars or vars.NoReferenceHoldSway ~= false)
        and not calibrating
        and controller.ready and controller.lastWant
        and iron
        and NO_REFERENCE_IRONS[profile.weaponId]
    if not eligible then
        if swayApplied then print("[ViewpointGael] Lua ADS sway stopped; restoring base profile") end
        swayKey, swayApplied, swayAt = nil, false, nil
        swayYaw, swayPitch = 0, 0
        swayReachedLogged = false
        return false, nil
    end

    local now = getTimestampMs()
    if controller.sig ~= swayKey then
        swayKey, swayAt = controller.sig, now
        swayYaw, swayPitch = 0, 0
        targetYaw = randomTarget(0, SWAY_LIMIT)
        targetPitch = randomTarget(0, SWAY_LIMIT)
        speedYaw, speedPitch = randomSpeed(), randomSpeed()
        swayReachedLogged = false
        print("[ViewpointGael] Lua ADS sway active for " .. profile.weaponId
            .. "; iron source=" .. tostring(profile.ironSource))
    end
    local dt = math.max(0, math.min(0.25, (now - swayAt) / 1000))
    swayAt = now
    swayYaw = approach(swayYaw, targetYaw, speedYaw * dt)
    swayPitch = approach(swayPitch, targetPitch, speedPitch * dt)
    if swayYaw == targetYaw then
        targetYaw, speedYaw = randomTarget(swayYaw, SWAY_LIMIT), randomSpeed()
    end
    if swayPitch == targetPitch then
        targetPitch, speedPitch = randomTarget(swayPitch, SWAY_LIMIT), randomSpeed()
    end
    swayApplied = true
    if not swayReachedLogged and (math.abs(swayYaw) >= 15 or math.abs(swayPitch) >= 15) then
        swayReachedLogged = true
        print("[ViewpointGael] Lua ADS sway reached 15 degrees for " .. profile.weaponId)
    end
    return true, now
end

local function updateIronFocus(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not controller or not controller.ready or not profile or not PVADS_setProfile then
        lastProfile, lastFov, wheelFocused = nil, nil, nil
        swayKey, swayApplied, swayAt, lastSwayPushAt = nil, false, nil, nil
        swayYaw, swayPitch = 0, 0
        return
    end

    local crouchEnabled, wheelEnabled, multiplier = settings()
    if not controller.lastWant or not wheelEnabled then wheelFocused = nil end
    local iron = profile.mode == "iron" and not profile.opticId and not profile.noIrons
    local baseFov = tonumber(profile.fovMul) or 0.93
    local focusFov = nil
    if iron then
        if wheelFocused == true then
            focusFov = math.max(MIN_FOV_MULTIPLIER, baseFov - 0.30)
        elseif wheelFocused == nil and crouchEnabled and player:isSneaking() then
            focusFov = math.max(MIN_FOV_MULTIPLIER, baseFov * multiplier)
        end
    end
    local swayActive, now = updateNoReferenceSway(controller, profile, iron)
    if profile == lastProfile and focusFov == lastFov then
        if not swayActive and not lastSwayPushAt then return end
        if swayActive and lastSwayPushAt and now - lastSwayPushAt < SWAY_PUSH_INTERVAL_MS then return end
    end
    local hadDynamicProfile = lastFov ~= nil or lastSwayPushAt ~= nil
    lastProfile, lastFov = profile, focusFov

    if focusFov or swayActive then
        local view = {}
        for key, value in pairs(profile) do view[key] = value end
        if focusFov then view.fovMul = focusFov end
        if swayActive then
            view.adjYaw = (tonumber(profile.adjYaw) or 0) + swayYaw
            view.adjPitch = (tonumber(profile.adjPitch) or 0) + swayPitch
        end
        PVADS_setProfile(view)
    elseif hadDynamicProfile then
        PVADS_setProfile(profile)
    end
    lastSwayPushAt = swayActive and now or nil
end

local function onWheel(wheel)
    wheel = tonumber(wheel) or 0
    if wheel == 0 then return end
    local _, enabled = settings()
    if not enabled then return end
    local player = getSpecificPlayer(0)
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not player or not controller or not controller.ready or not controller.lastWant
        or not player:isAiming() or not profile
        or profile.mode ~= "iron" or profile.opticId or profile.noIrons then return end
    wheelFocused = wheel > 0
    updateIronFocus(player)
end

Events.OnPlayerUpdate.Add(updateIronFocus)
Events.OnMouseWheel.Add(onWheel)
