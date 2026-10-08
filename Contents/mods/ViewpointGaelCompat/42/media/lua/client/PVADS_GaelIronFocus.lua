-- Experimental: crouching narrows the ADS view for unmounted iron sights.
-- Only fovMul changes; the calibrated sight position and saved profile stay intact.
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFov = nil
local wheelFocused = nil
local NO_REFERENCE_IRONS = { ["Base.GOL"] = true }
local SWAY_LIMIT = 2.0 -- Temporary diagnostic amplitude for visible post-alignment motion.
local SWAY_SPEED_INTERVAL = 0.25
local SWAY_STEP_MIN = 0.05
local SWAY_STEP_MAX = 0.20
local swayKey = nil
local swayApplied = false
local swayAt = nil
local swayYaw, swayPitch = 0, 0
local targetYaw, targetPitch = 0, 0
local speedYaw, speedPitch = 0, 0
local swayRequestedLogged = false

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
        local target = side * limit * (0.5 + ZombRand(501) / 1000)
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

local function updateNoReferenceSway(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    local aim = ViewpointGael and ViewpointGael.Aim
    if not (profile and aim and aim.setHoldSway) then
        if swayApplied and aim and aim.setHoldSway and swayKey then
            print("[ViewpointGael] hold sway reset: ADS profile unavailable")
            aim.setHoldSway(string.match(swayKey, "^[^|]+"), 0, 0)
        end
        swayKey, swayApplied, swayAt = nil, false, nil
        swayYaw, swayPitch = 0, 0
        return
    end
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local calibrator = PVADS.Calibrator
    local calibrating = calibrator and calibrator.window and calibrator.window:isVisible()
    local eligible = (not vars or vars.NoReferenceHoldSway ~= false)
        and not calibrating
        and controller.ready and controller.lastWant
        and profile.mode == "iron" and not profile.opticId and not profile.noIrons
        and profile.ironSource == "family default"
        and NO_REFERENCE_IRONS[profile.weaponId]
    if not eligible then
        if swayApplied and swayKey then
            print("[ViewpointGael] hold sway reset: want=" .. tostring(controller.lastWant)
                .. " calibrating=" .. tostring(calibrating) .. " iron=" .. tostring(profile.mode == "iron"))
            aim.setHoldSway(string.match(swayKey, "^[^|]+"), 0, 0)
        end
        swayKey, swayApplied, swayAt = nil, false, nil
        swayYaw, swayPitch = 0, 0
        return
    end

    local now = getTimestampMs()
    if controller.sig ~= swayKey then
        swayKey, swayAt = controller.sig, now
        swayYaw, swayPitch = 0, 0
        targetYaw = randomTarget(0, SWAY_LIMIT)
        targetPitch = randomTarget(0, SWAY_LIMIT)
        speedYaw, speedPitch = randomSpeed(), randomSpeed()
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
    swayApplied = aim.setHoldSway(profile.weaponId, swayYaw, swayPitch) == true
    if swayApplied and not swayRequestedLogged and (math.abs(swayYaw) > 0.05 or math.abs(swayPitch) > 0.05) then
        swayRequestedLogged = true
        print("[ViewpointGael] requesting post-alignment hold sway for " .. profile.weaponId)
    end
end

local function updateIronFocus(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not controller or not controller.ready or not profile or not PVADS_setProfile then
        lastProfile, lastFov, wheelFocused = nil, nil, nil
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
    if profile == lastProfile and focusFov == lastFov then return end
    lastProfile, lastFov = profile, focusFov

    if focusFov then
        local view = {}
        for key, value in pairs(profile) do view[key] = value end
        view.fovMul = focusFov
        PVADS_setProfile(view)
    elseif iron then
        PVADS_setProfile(profile)
    end
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
Events.OnPlayerUpdate.Add(updateNoReferenceSway)
Events.OnMouseWheel.Add(onWheel)
