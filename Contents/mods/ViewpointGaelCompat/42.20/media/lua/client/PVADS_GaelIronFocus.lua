-- Experimental: crouching narrows the ADS view for unmounted iron sights.
-- Only fovMul changes; the calibrated sight position and saved profile stay intact.
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFov = nil
local wheelFocused = nil
local NO_REFERENCE_IRONS = { ["Base.GOL"] = true }
local SWAY_DEGREES_PER_SECOND = 0.0425
local SWAY_YAW_LIMIT = 0.7
local SWAY_PITCH_LIMIT = 0.4
local swayProfile = nil
local swayApplied = false
local swayAt = nil
local swayYaw, swayPitch = 0, 0
local yawDirection, pitchDirection = 1, -1

local function settings()
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = not vars or vars.CrouchIronFocus ~= false
    local wheelEnabled = not vars or vars.WheelIronFocus ~= false
    local multiplier = tonumber(vars and vars.CrouchIronFocusMultiplier) or 0.70
    return enabled, wheelEnabled, math.max(0.30, math.min(1.00, multiplier))
end

local function advance(value, direction, limit, step)
    value = value + direction * step
    if value > limit then
        value, direction = limit - (value - limit), -1
    elseif value < -limit then
        value, direction = -limit + (-limit - value), 1
    end
    return value, direction
end

local function updateNoReferenceSway(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    local aim = ViewpointGael and ViewpointGael.Aim
    if not (profile and aim and aim.setHoldSway) then return end
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local calibrator = PVADS.Calibrator
    local calibrating = calibrator and calibrator.window and calibrator.window:isVisible()
    local eligible = (not vars or vars.NoReferenceHoldSway ~= false)
        and not calibrating
        and controller.ready and controller.lastWant and player:isAiming()
        and profile.mode == "iron" and not profile.opticId and not profile.noIrons
        and profile.ironSource == "family default"
        and NO_REFERENCE_IRONS[profile.weaponId]
    if not eligible then
        if swayApplied and profile == swayProfile then
            aim.setHoldSway(profile.weaponId,
                tonumber(profile.adjYaw) or 0, tonumber(profile.adjPitch) or 0)
        end
        swayProfile, swayApplied, swayAt = nil, false, nil
        swayYaw, swayPitch = 0, 0
        return
    end

    local now = getTimestampMs()
    if profile ~= swayProfile then
        swayProfile, swayAt = profile, now
        swayYaw, swayPitch = 0, 0
        yawDirection = ZombRand(2) == 0 and -1 or 1
        pitchDirection = ZombRand(2) == 0 and -1 or 1
    end
    local dt = math.max(0, math.min(0.25, (now - swayAt) / 1000))
    swayAt = now
    local step = SWAY_DEGREES_PER_SECOND * dt
    swayYaw, yawDirection = advance(swayYaw, yawDirection, SWAY_YAW_LIMIT, step)
    swayPitch, pitchDirection = advance(swayPitch, pitchDirection, SWAY_PITCH_LIMIT, step)
    swayApplied = aim.setHoldSway(profile.weaponId,
        (tonumber(profile.adjYaw) or 0) + swayYaw,
        (tonumber(profile.adjPitch) or 0) + swayPitch) == true
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
