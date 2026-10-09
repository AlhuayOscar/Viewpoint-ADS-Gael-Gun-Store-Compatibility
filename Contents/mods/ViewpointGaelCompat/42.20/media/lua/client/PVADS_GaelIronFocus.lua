-- Iron focus and per-weapon ADS sway; dynamic values never enter the saved profile.
require "PVADS_GaelSwayCatalog"
require "PVADS_GaelGrip"
require "PVADS_GaelAlignment"
require "TimedActions/ISTimedActionQueue"
require "ISUI/ISUIElement"
require "Foraging/ISSearchManager"
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFov = nil
local focusFovTarget, focusFovFrom, focusFovCurrent, focusFovTransitionAt = nil, nil, nil, nil
local FOCUS_ZOOM_TRANSITION_MS = 400
local wheelFocused = nil
local focusChargeMs, focusCapacityMs, focusLastUpdatedAt = nil, nil, nil
local focusCooldownUntil = 0
local FOCUS_COOLDOWN_MS = 400
local FOCUS_RESTART_FRACTION = 0.25
local FOCUS_DENIED_MESSAGE_MS = 1200
local FOCUS_SPRINT_DRAIN_RATE = 1.00
local FOCUS_RUN_DRAIN_RATE = 0.50
local FOCUS_BAR_COLORS = {
    { 1.00, 0.15, 0.12 }, -- unavailable: red
    { 1.00, 0.45, 0.12 }, -- orange
    { 0.95, 0.82, 0.20 }, -- yellow
    { 0.60, 0.88, 0.18 }, -- yellow-green
    { 0.18, 0.80, 0.25 }, -- full: green
}
local focusBar = nil
local focusDeniedUntil = nil
local focusBlurManager = nil
local focusBlurPreviousEffect = false
local focusSwayScale = 1.00
local SWAY_BASE_LIMIT = 0.4 -- Reference amplitude for the original motion speed.
local SWAY_SPEED_INTERVAL = 0.25
local SWAY_STEP_MIN = 0.008
local SWAY_STEP_MAX = 0.032
local swayKey = nil
local swayLimit = nil
local swayApplied = false
local swayAt = nil
local swayYaw, swayPitch = 0, 0
local armJitterYaw, armJitterPitch = 0, 0
local armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
local targetYaw, targetPitch = 0, 0
local speedYaw, speedPitch = 0, 0
local lastSwayPushAt = nil
local SWAY_PUSH_INTERVAL_MS = 50
local SWAY_CENTER_MIN_MS = 3000
local SWAY_CENTER_RANDOM_MS = 2001
local SWAY_CENTER_DURATION = 0.65
local lastCenterAt = nil
local nextCenterDelayMs = nil
local returningToCenter = false
local shotResetPending = false
local sightOffsetX, sightOffsetY, sightOffsetZ = 0, 0, 0
local sightTargetX, sightTargetY, sightTargetZ = 0, 0, 0
local sightLastStepAt = nil
local SIGHT_STEP_INTERVAL_MS = 250
local SIGHT_X_STEP, SIGHT_Y_STEP, SIGHT_Z_STEP = 0.0002, 0.0005, 0.0002
local SIGHT_X_MAX, SIGHT_Y_MAX, SIGHT_Z_MAX = 0.0020, 0.0030, 0.0026
local ARM_DROP_Z = -0.0060
local armDropZ, armDropPhase, armDropUntil = 0, nil, nil
local nextArmDropAt = nil
local walkRoll, walkY = 0, 0
local walkTargetRoll, walkTargetY = 0, 0
local nextWalkTargetAt = nil
local walkRollDirection, walkRollAccumulator = 0, 0
local WALK_ROLL_STEP = 0.01
local WALK_ROLL_STEP_SECONDS = 1 / 120
local HEAVY_RECOIL_WEIGHT = 2.2 -- Heaviest pistol in the Gael weight catalog.
local HEAVY_RECOIL_BONUS = 5.0
local SHOT_RECOIL_SCALE = 0.40
local AUTO_RECOIL_MIN_DIVISOR = 8
local AUTO_RECOIL_MAX_DIVISOR = 24
local STRENGTH_RECOIL_EFFECT = 1.30
local BURST_RESET_MS = 1000
local LONG_BURST_RECOIL_SHOTS = 20
local LONG_BURST_RECOIL_BONUS = 3.0
local LONG_BURST_RISE_MS = 140
local LONG_BURST_HOLD_MS = 700
local LONG_BURST_DURATION_MS = 1150
local LATE_BURST_HOLD_MS = LONG_BURST_HOLD_MS - 150
local LATE_BURST_DURATION_MS = LONG_BURST_DURATION_MS - 150
local LONG_BURST_ANCHOR_STEP = 0.35
local LONG_BURST_PITCH_IMPULSE = 1.25
local LONG_BURST_YAW_IMPULSE = 1.00
local RELEASE_REGRIP_SHOTS = 26
local RELEASE_REGRIP_MS = 400
local RELEASE_REGRIP_HOLD_MS = 600
local RELEASE_REGRIP_RETURN_MS = 400
local releaseRegripDurationMs = RELEASE_REGRIP_MS
local longBurstPitchDirection, longBurstYawDirection = nil, nil
local longBurstPitchAnchor, longBurstYawAnchor = nil, nil
local longBurstPitchFrom, longBurstYawFrom = nil, nil
local longBurstLegShots, longBurstLegStep = nil, 0
local recoilLongBurst = false
local burstWeapon, burstLastShotAt, burstShotCount = nil, nil, 0
local burstAutomatic = nil
local releaseRegripArmed, releaseTriggerSeen = false, false
local releaseRegripAt, releaseRegripPhase, releaseRegripDirection = nil, 0, 1
local releaseRegripYawRadius, releaseRegripPitchRadius = 0, 0
local releaseRegripYaw, releaseRegripPitch = 0, 0
-- Gael pistols use their configured ammunition, not the caliber suggested by a model name.
local PISTOL_RECOIL_BONUS = {
    ["Base.Automag44"] = 3, ["Base.Automag50AE"] = 3,
    ["Base.Deagle50AE"] = 3, ["Base.FNX45"] = 3,
    ["Base.Glock23"] = 3, ["Base.Glock43"] = 3,
    ["Base.Glock_tactical"] = 3, ["Base.HKMK23"] = 3,
    ["Base.Jericho941"] = 3, ["Base.Kimber1911"] = 3,
    ["Base.MP1911"] = 3, ["Base.P220_Elite"] = 3,
    ["Base.Pistol2"] = 3, ["Base.Pistol3"] = 3,
    ["Base.USP45"] = 3, ["Base.Wildey"] = 3,
    ["Base.FN502_22LR"] = 1, ["Base.OTS_33"] = 1,
    ["Base.VictorySW22"] = 1,
}
local RECOIL_RISE_MS = 110
local RECOIL_HOLD_MS = 250
local recoilRiseMs, recoilHoldMs = RECOIL_RISE_MS, RECOIL_HOLD_MS
local recoilDurationMs = 750
local recoilStartedAt, recoilStartPitch, recoilPitch, recoilPeakPitch = nil, 0, 0, 0
local recoilStartYaw, recoilYaw, recoilPeakYaw = 0, 0, 0
local boltAction, boltPitch, boltTarget, boltLastAt = nil, 0, 0, nil
local boltYaw, boltYawTarget = 0, 0
local boltSpeedScale = 1.0
local boltStartedAt, boltMotionDurationMs, boltRiseFraction = nil, nil, nil

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

local function randomSpeed(limit)
    return (SWAY_STEP_MIN + (SWAY_STEP_MAX - SWAY_STEP_MIN) * ZombRand(1001) / 1000)
        / SWAY_SPEED_INTERVAL * (limit / SWAY_BASE_LIMIT)
end

local function approach(value, target, step)
    if math.abs(target - value) <= step then return target end
    return value + (target > value and step or -step)
end

local function strengthMultiplier(player)
    local strength = tonumber(player and player:getPerkLevel(Perks.Strength)) or 5
    strength = math.max(0, math.min(10, strength))
    return 1 + (5 - strength) * 0.10
end

local function enduranceMultiplier(player)
    local moodles = player and player:getMoodles()
    local level = moodles and tonumber(moodles:getMoodleLevel(MoodleType.ENDURANCE)) or 0
    level = math.max(0, math.min(3, level))
    return 1 + (level > 0 and (level + 1) * 0.50 or 0)
end

local function enduranceLevel(player)
    local moodles = player and player:getMoodles()
    local level = moodles and tonumber(moodles:getMoodleLevel(MoodleType.ENDURANCE)) or 0
    return math.max(0, math.min(4, level))
end

local function applyFocusBlur(manager)
    local overlay = manager and manager.searchModeOverlay
    if not overlay then return end
    overlay:getBlur():setTargets(0.5, 0.5) -- Same blur strength as vanilla search mode.
    overlay:getDesat():setTargets(0, 0)
    overlay:getRadius():setTargets(3, 3)
    overlay:getDarkness():setTargets(0.1, 0.1)
    overlay:getGradientWidth():setTargets(2, 2)
end

-- Search mode refreshes its overlay every frame; reapply only while this focus owns it.
local originalSearchOverlayUpdate = ISSearchManager.updateOverlay
ISSearchManager.updateOverlay = function(manager, ...)
    originalSearchOverlayUpdate(manager, ...)
    if manager == focusBlurManager and not manager.isSearchMode then
        applyFocusBlur(manager)
    end
end

local function updateFocusBlur(player, active)
    local manager = ISSearchManager.players and ISSearchManager.players[player]
    if focusBlurManager and (not active or manager ~= focusBlurManager
        or focusBlurManager.isSearchMode) then
        local previous = focusBlurManager
        previous.isEffectOverlay = focusBlurPreviousEffect
        focusBlurManager = nil
        if manager == previous then previous:updateOverlay() end
    end
    if active and manager and not focusBlurManager
        and not manager.isSearchMode and not manager.isEffectOverlay then
        focusBlurPreviousEffect = manager.isEffectOverlay
        focusBlurManager = manager
        manager.isEffectOverlay = true
        manager:updateOverlay()
    end
end

local ARM_PARTS = {
    BodyPartType.Hand_L, BodyPartType.Hand_R,
    BodyPartType.ForeArm_L, BodyPartType.ForeArm_R,
    BodyPartType.UpperArm_L, BodyPartType.UpperArm_R,
}

local function armMuscleFatigue(player)
    local damage = player and player:getBodyDamage()
    if not damage then return 0 end
    local stiffness = 0
    for _, partType in ipairs(ARM_PARTS) do
        local part = damage:getBodyPart(partType)
        if part then stiffness = math.max(stiffness, tonumber(part:getStiffness()) or 0) end
    end
    -- The health panel shows muscle stiffness from 5 and marks 20+ as more than minor.
    if stiffness >= 20 then return 3 end
    if stiffness >= 5 then return 1.5 end
    return 0
end

local function fitnessLevel(player)
    return math.max(0, math.min(10,
        tonumber(player and player:getPerkLevel(Perks.Fitness)) or 0))
end

local function recoilFitnessLevels(player)
    return math.max(0, fitnessLevel(player) - 4)
end

local function focusTimeMs(player)
    local fitness = fitnessLevel(player)
    local exertion = enduranceLevel(player)
    return math.max(1000, 5000 + fitness * 1000
        - math.min(4000, exertion * 1500))
end

local function focusRechargeRate(player)
    return 0.25 * (1 + fitnessLevel(player) * 0.10)
end

local function stopManualFocus(now)
    if wheelFocused == true then focusCooldownUntil = now + FOCUS_COOLDOWN_MS end
    wheelFocused = false
end

local function updateFocusCharge(player, now)
    local capacity = focusTimeMs(player)
    if focusChargeMs == nil then focusChargeMs = capacity end
    focusChargeMs = math.min(focusChargeMs, capacity)
    local last = focusLastUpdatedAt or now
    local movementDrain = player:isSprinting() and FOCUS_SPRINT_DRAIN_RATE
        or (player:isRunning() and FOCUS_RUN_DRAIN_RATE or 0)
    if wheelFocused == true or movementDrain > 0 then
        local drainRate = (wheelFocused == true and 1 or 0) + movementDrain
        focusChargeMs = math.max(0, focusChargeMs
            - math.max(0, now - last) * drainRate)
        if focusChargeMs == 0 then stopManualFocus(now) end
    else
        local recoveryStart = math.max(last, focusCooldownUntil)
        focusChargeMs = math.min(capacity, focusChargeMs
            + math.max(0, now - recoveryStart) * focusRechargeRate(player))
    end
    focusCapacityMs, focusLastUpdatedAt = capacity, now
end

PVADSGaelFocusBar = ISUIElement:derive("PVADSGaelFocusBar")

function PVADSGaelFocusBar:new()
    local core = getCore()
    return ISUIElement.new(self, math.floor(core:getScreenWidth() / 2) + 42,
        math.floor(core:getScreenHeight() / 2) - 35, 110, 70)
end

function PVADSGaelFocusBar:instantiate()
    ISUIElement.instantiate(self)
    self.javaObject:setConsumeMouseEvents(false)
end

function PVADSGaelFocusBar:render()
    local core = getCore()
    self:setX(math.floor(core:getScreenWidth() / 2) + 42)
    self:setY(math.floor(core:getScreenHeight() / 2) - 35)
    local now = getTimestampMs()
    if wheelFocused ~= true then
        if focusDeniedUntil and now < focusDeniedUntil then
            self:drawText("X", 0, 21, 1, 0.15, 0.15, 0.9, UIFont.Medium)
            self:drawText("Espera...", 20, 24, 1, 0.35, 0.35, 0.85, UIFont.Small)
        end
        return
    end
    if not focusChargeMs or not focusCapacityMs then return end
    local remaining = math.max(0, math.min(1, focusChargeMs / focusCapacityMs))
    local targetColor = remaining < FOCUS_RESTART_FRACTION
        and 0.5 * remaining / FOCUS_RESTART_FRACTION
        or 0.5 + 0.5 * (remaining - FOCUS_RESTART_FRACTION)
            / (1 - FOCUS_RESTART_FRACTION)
    local last = self.lastColorAt or now
    self.colorLevel = approach(self.colorLevel or 0.5, targetColor,
        math.max(0, now - last) / 400)
    self.lastColorAt = now
    local position = self.colorLevel * 4
    local index = math.min(4, math.floor(position) + 1)
    local blend = position - (index - 1)
    local red = FOCUS_BAR_COLORS[index][1]
        + (FOCUS_BAR_COLORS[index + 1][1] - FOCUS_BAR_COLORS[index][1]) * blend
    local green = FOCUS_BAR_COLORS[index][2]
        + (FOCUS_BAR_COLORS[index + 1][2] - FOCUS_BAR_COLORS[index][2]) * blend
    local blue = FOCUS_BAR_COLORS[index][3]
        + (FOCUS_BAR_COLORS[index + 1][3] - FOCUS_BAR_COLORS[index][3]) * blend
    self:drawRect(0, 0, 8, 70, 0.27, red, green, blue)
    self:drawRect(1, 1 + math.floor(68 * (1 - remaining)), 6,
        math.ceil(68 * remaining), 0.60, red, green, blue)
end

local function createFocusBar()
    if focusBar then return end
    focusBar = PVADSGaelFocusBar:new()
    focusBar:initialise()
    focusBar:instantiate()
    focusBar:addToUIManager()
    focusBar:setVisible(false)
end

local function randomSightTarget(step, maximum, level)
    if level == 0 then return 0 end
    local steps = math.floor((maximum * level / 4) / step + 0.000001)
    if steps < 1 then return 0 end
    local sign = ZombRand(2) == 0 and -1 or 1
    return sign * ZombRand(steps + 1) * step
end

local function resetSightSway(now)
    sightOffsetX, sightOffsetY, sightOffsetZ = 0, 0, 0
    sightTargetX, sightTargetY, sightTargetZ = 0, 0, 0
    sightLastStepAt = now
end

local function updateSightSway(player, now, dt)
    local level = enduranceLevel(player)
    if level == 0 then
        resetSightSway(now)
        return
    end
    if not sightLastStepAt or now - sightLastStepAt >= SIGHT_STEP_INTERVAL_MS then
        sightLastStepAt = now
        sightTargetX = randomSightTarget(SIGHT_X_STEP, SIGHT_X_MAX, level)
        sightTargetY = randomSightTarget(SIGHT_Y_STEP, SIGHT_Y_MAX, level)
        sightTargetZ = randomSightTarget(SIGHT_Z_STEP, SIGHT_Z_MAX, level)
    end
    local factor = math.min(1, dt * 4)
    sightOffsetX = sightOffsetX + (sightTargetX - sightOffsetX) * factor
    sightOffsetY = sightOffsetY + (sightTargetY - sightOffsetY) * factor
    sightOffsetZ = sightOffsetZ + (sightTargetZ - sightOffsetZ) * factor
end

local function resetMotionSway()
    armDropZ, armDropPhase, armDropUntil, nextArmDropAt = 0, nil, nil, nil
    walkRoll, walkY, walkTargetRoll, walkTargetY, nextWalkTargetAt = 0, 0, 0, 0, nil
    walkRollDirection, walkRollAccumulator = 0, 0
end

local function updateMotionSway(player, now, dt)
    if enduranceLevel(player) >= 3 then
        if not armDropPhase and not nextArmDropAt then
            nextArmDropAt = now + 2000 + ZombRand(2001)
        end
        if not armDropPhase and now >= nextArmDropAt then
            armDropPhase = "fall"
            nextArmDropAt = nil
        end
        if armDropPhase == "fall" then
            armDropZ = approach(armDropZ, ARM_DROP_Z, 0.0060 / 0.40 * dt)
            if armDropZ == ARM_DROP_Z then
                armDropPhase, armDropUntil = "hold", now + 200
            end
        elseif armDropPhase == "hold" and now >= armDropUntil then
            armDropPhase = "recover"
        end
    else
        armDropPhase, armDropUntil, nextArmDropAt = nil, nil, nil
    end
    if armDropPhase == "recover" or enduranceLevel(player) < 3 then
        armDropZ = approach(armDropZ, 0, 0.0060 / 1.0 * dt)
        if armDropZ == 0 then armDropPhase = nil end
    end

    local walking = player:isPlayerMoving() and not player:isRunning() and not player:isSprinting()
    if walking then
        if not nextWalkTargetAt or now >= nextWalkTargetAt then
            walkTargetY = 0.020 + ZombRand(5) * 0.005
            nextWalkTargetAt = now + 450 + ZombRand(201)
        end
        if walkRollDirection == 0 then
            walkRollDirection = ZombRand(2) == 0 and -1 or 1
            walkTargetRoll = walkRollDirection * 3
        elseif walkRoll == walkTargetRoll then
            walkRollDirection = -walkRollDirection
            walkTargetRoll = walkRollDirection * 3
        end
    else
        walkTargetY, walkTargetRoll, nextWalkTargetAt = 0, 0, nil
        walkRollDirection = 0
    end
    walkY = approach(walkY, walkTargetY, 0.040 / 0.70 * dt)
    walkRollAccumulator = walkRollAccumulator + dt
    while walkRollAccumulator >= WALK_ROLL_STEP_SECONDS do
        walkRoll = approach(walkRoll, walkTargetRoll, WALK_ROLL_STEP)
        walkRollAccumulator = walkRollAccumulator - WALK_ROLL_STEP_SECONDS
    end
end

PVADS.GaelRealTimeDot = true

local function isCalibratingBlocked()
    local calibrator = PVADS.Calibrator
    local calibrating = (calibrator and calibrator.window and calibrator.window:isVisible())
        or (PVADSGaelSliderWindow and PVADSGaelSliderWindow.instance and PVADSGaelSliderWindow.instance:isVisible())
    if not calibrating then return false end
    return PVADS.GaelRealTimeDot == false
end

local function updateWeaponSway(player, controller, profile)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local baseLimit = PVADS_GaelSwayCatalog and PVADS_GaelSwayCatalog[profile.weaponId]
    local muscleFatigue = armMuscleFatigue(player)
    local limit = (baseLimit or 0.50) * strengthMultiplier(player) * enduranceMultiplier(player)
        * (1 + muscleFatigue)
    local calibrating = isCalibratingBlocked()
    local angularEnabled = not vars or vars.NoReferenceHoldSway ~= false
    local sightMotionEnabled = not vars or vars.SightMotion ~= false
    local eligible = (angularEnabled or sightMotionEnabled)
        and not calibrating
        and controller.ready and controller.lastWant
        and limit
    if not eligible then
        if swayApplied then print("[ViewpointGael] Lua ADS sway stopped; restoring base profile") end
        swayKey, swayApplied, swayAt, swayLimit = nil, false, nil, nil
        swayYaw, swayPitch = 0, 0
        armJitterYaw, armJitterPitch = 0, 0
        armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
        lastCenterAt, nextCenterDelayMs, returningToCenter, shotResetPending = nil, nil, false, false
        resetSightSway(nil)
        resetMotionSway()
        focusSwayScale = 1.00
        return false, nil
    end

    local now = getTimestampMs()
    if controller.sig ~= swayKey then
        swayKey, swayAt, swayLimit = controller.sig, now, limit
        lastCenterAt, nextCenterDelayMs, returningToCenter = now, SWAY_CENTER_MIN_MS + ZombRand(SWAY_CENTER_RANDOM_MS), false
        swayYaw, swayPitch = 0, 0
        armJitterYaw, armJitterPitch = 0, 0
        armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
        resetSightSway(now)
        resetMotionSway()
        targetYaw = randomTarget(0, limit)
        targetPitch = randomTarget(0, limit)
        speedYaw, speedPitch = randomSpeed(limit), randomSpeed(limit)
        print("[ViewpointGael] Lua ADS sway active for " .. profile.weaponId
            .. "; iron source=" .. tostring(profile.ironSource))
    elseif swayLimit and swayLimit ~= limit then
        local ratio = limit / swayLimit
        swayYaw, swayPitch = swayYaw * ratio, swayPitch * ratio
        targetYaw, targetPitch = targetYaw * ratio, targetPitch * ratio
        speedYaw, speedPitch = speedYaw * ratio, speedPitch * ratio
        swayLimit = limit
    end
    if shotResetPending then
        shotResetPending = false
        swayAt = now
        lastCenterAt, nextCenterDelayMs, returningToCenter = now, SWAY_CENTER_MIN_MS + ZombRand(SWAY_CENTER_RANDOM_MS), false
        swayYaw, swayPitch = 0, 0
        armJitterYaw, armJitterPitch = 0, 0
        armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
        resetSightSway(now)
        resetMotionSway()
        targetYaw, targetPitch = randomTarget(0, limit), randomTarget(0, limit)
        speedYaw, speedPitch = randomSpeed(limit), randomSpeed(limit)
    elseif not returningToCenter and lastCenterAt and now - lastCenterAt >= nextCenterDelayMs then
        returningToCenter = true
        targetYaw, targetPitch = 0, 0
        speedYaw, speedPitch = math.abs(swayYaw) / SWAY_CENTER_DURATION,
            math.abs(swayPitch) / SWAY_CENTER_DURATION
    end
    local dt = math.max(0, math.min(0.25, (now - swayAt) / 1000))
    swayAt = now
    local focusedStill = wheelFocused == true and profile.mode == "iron"
        and not profile.opticId and not profile.noIrons and not player:isPlayerMoving()
    focusSwayScale = approach(focusSwayScale, focusedStill and 0.30 or 1.00, dt * 2.80)
    if sightMotionEnabled then
        updateSightSway(player, now, dt)
        updateMotionSway(player, now, dt)
    else
        resetSightSway(nil)
        resetMotionSway()
    end
    swayYaw = approach(swayYaw, targetYaw, speedYaw * dt)
    swayPitch = approach(swayPitch, targetPitch, speedPitch * dt)
    if muscleFatigue > 0 and (not nextArmJitterAt or now >= nextArmJitterAt) then
        local amplitude = 0.18 * muscleFatigue
        armJitterTargetYaw = amplitude * (ZombRand(2001) / 1000 - 1)
        armJitterTargetPitch = amplitude * (ZombRand(2001) / 1000 - 1)
        nextArmJitterAt = now + 230 + ZombRand(271)
    elseif muscleFatigue <= 0 then
        armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
    end
    armJitterYaw = approach(armJitterYaw, armJitterTargetYaw, 0.7 * dt)
    armJitterPitch = approach(armJitterPitch, armJitterTargetPitch, 0.7 * dt)
    if returningToCenter then
        if swayYaw == 0 and swayPitch == 0 then
            returningToCenter, lastCenterAt = false, now
            nextCenterDelayMs = SWAY_CENTER_MIN_MS + ZombRand(SWAY_CENTER_RANDOM_MS)
            targetYaw, targetPitch = randomTarget(0, limit), randomTarget(0, limit)
            speedYaw, speedPitch = randomSpeed(limit), randomSpeed(limit)
        end
    else
        if swayYaw == targetYaw then
            targetYaw, speedYaw = randomTarget(swayYaw, limit), randomSpeed(limit)
        end
        if swayPitch == targetPitch then
            targetPitch, speedPitch = randomTarget(swayPitch, limit), randomSpeed(limit)
        end
    end
    swayApplied = true
    return true, now
end

local function smoothstep(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function longBurstDirectionFactor(from, direction)
    local progress = smoothstep(longBurstLegStep / longBurstLegShots)
    return from + (direction - from) * progress
end

local function updateReleaseRegrip(player, controller, now)
    if releaseRegripArmed then
        local down = player.isAttackButtonDown and player:isAttackButtonDown()
        if down then releaseTriggerSeen = true end
        local sinceShot = burstLastShotAt and now - burstLastShotAt or 0
        if controller.lastWant and not down
            and (releaseTriggerSeen and sinceShot >= 30 or sinceShot >= 250) then
            releaseRegripArmed, releaseTriggerSeen = false, false
            releaseRegripAt = now
            releaseRegripDurationMs = RELEASE_REGRIP_MS
            releaseRegripPhase = ZombRand(6284) / 1000
            releaseRegripDirection = ZombRand(2) == 0 and -1 or 1
            local gripScale = PVADS_GaelGrip.recoilMultiplier(burstWeapon)
            releaseRegripYawRadius = (0.55 + ZombRand(401) / 1000)
                * SHOT_RECOIL_SCALE * gripScale
            releaseRegripPitchRadius = (0.40 + ZombRand(351) / 1000)
                * SHOT_RECOIL_SCALE * gripScale
            -- Keep the last long-burst offset while the regrip rotates, then recenter.
            recoilLongBurst = false
            recoilStartedAt = now
            recoilStartPitch, recoilPeakPitch = recoilPitch, recoilPitch
            recoilStartYaw, recoilPeakYaw = recoilYaw, recoilYaw
            recoilRiseMs = 1
            recoilHoldMs = RELEASE_REGRIP_HOLD_MS
            recoilDurationMs = recoilHoldMs + RELEASE_REGRIP_RETURN_MS
                / (1 + recoilFitnessLevels(player) * 0.15)
        elseif not controller.lastWant then
            releaseRegripArmed, releaseTriggerSeen = false, false
        end
    end
    if not releaseRegripAt then return false end
    local progress = (now - releaseRegripAt) / releaseRegripDurationMs
    if progress >= 1 or not controller.lastWant then
        releaseRegripAt, releaseRegripYaw, releaseRegripPitch = nil, 0, 0
        return false
    end
    local phase = releaseRegripPhase
    local angle = phase + releaseRegripDirection * 2 * math.pi * progress
    local envelope = 1 - smoothstep(progress)
    releaseRegripYaw = releaseRegripYawRadius
        * (math.cos(angle) - math.cos(phase)) * envelope
    releaseRegripPitch = releaseRegripPitchRadius
        * (math.sin(angle) - math.sin(phase)) * envelope
    return true
end

local function nextLongBurstCorner(pitch, yaw)
    -- The visual profile subtracts recoilPitch, so positive recoilPitch
    -- produces the usual negative pitch. Keep that direction 80% of the time.
    local nextPitch = ZombRand(5) == 0 and -1 or 1
    local nextYaw = ZombRand(2) == 0 and -1 or 1
    if nextPitch == pitch and nextYaw == yaw then nextYaw = -nextYaw end
    return nextPitch, nextYaw
end

local function updateShotRecoil(controller, profile, now)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = (not vars or vars.ShotPitchRecoil ~= false)
        and controller.lastWant
    if not enabled or isCalibratingBlocked() then
        recoilStartedAt, recoilStartPitch, recoilPitch, recoilPeakPitch = nil, 0, 0, 0
        recoilStartYaw, recoilYaw, recoilPeakYaw = 0, 0, 0
        releaseRegripArmed, releaseTriggerSeen, releaseRegripAt = false, false, nil
        releaseRegripYaw, releaseRegripPitch = 0, 0
        return false
    end
    if not recoilStartedAt then return false end
    local age = math.max(0, now - recoilStartedAt)
    if age >= recoilDurationMs then
        recoilStartedAt, recoilStartPitch, recoilPitch, recoilPeakPitch = nil, 0, 0, 0
        recoilStartYaw, recoilYaw, recoilPeakYaw = 0, 0, 0
        return false
    end
    local peakPitch, peakYaw = recoilPeakPitch, recoilPeakYaw
    if recoilLongBurst then
        peakPitch = math.abs(recoilPeakPitch) * longBurstDirectionFactor(
            longBurstPitchFrom, longBurstPitchDirection)
        peakYaw = math.abs(recoilPeakYaw) * longBurstDirectionFactor(
            longBurstYawFrom, longBurstYawDirection)
    end
    if age <= recoilRiseMs then
        local rise = smoothstep(age / recoilRiseMs)
        recoilPitch = recoilStartPitch + (peakPitch - recoilStartPitch) * rise
        recoilYaw = recoilStartYaw + (peakYaw - recoilStartYaw) * rise
    elseif age <= recoilHoldMs then
        recoilPitch, recoilYaw = peakPitch, peakYaw
    else
        local remaining = 1 - smoothstep((age - recoilHoldMs) / (recoilDurationMs - recoilHoldMs))
        recoilPitch = peakPitch * remaining
        recoilYaw = peakYaw * remaining
    end
    return true
end

local function updateBoltPitch(player, controller, profile, now)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    if (vars and vars.BoltPitchMotion == false) then
        boltAction, boltPitch, boltTarget, boltLastAt = nil, 0, 0, nil
        boltYaw, boltYawTarget = 0, 0
        boltSpeedScale = 1.0
        boltStartedAt, boltMotionDurationMs, boltRiseFraction = nil, nil, nil
        return false
    end
    if isCalibratingBlocked() then
        boltAction, boltPitch, boltTarget, boltLastAt = nil, 0, 0, nil
        boltYaw, boltYawTarget = 0, 0
        boltSpeedScale = 1.0
        boltStartedAt, boltMotionDurationMs, boltRiseFraction = nil, nil, nil
        return false
    end
    local queue = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(player)
    local action = queue and queue.current
    local racking = action and action.Type == "ISRackFirearm" and action:isStarted()
        and action.gun and action.gun:getFullType() == profile.weaponId
        and (controller.lastWant or player:isAiming())
    if racking then
        if action ~= boltAction then
            boltAction = action
            boltTarget = (ZombRand(2) == 0 and -1 or 1) * (2.0 + ZombRand(21) / 10)
            boltYawTarget = (ZombRand(2) == 0 and -1 or 1) * (0.3 + ZombRand(51) / 100)
            boltSpeedScale = 0.65 + ZombRand(71) / 100
            local baseDuration = action.gun:getWeaponReloadType() == WeaponReloadType.SHOTGUN
                and 600 or 1200
            local rackDuration = ISReloadWeaponAction.getReloadTime(player, baseDuration)
            boltStartedAt = now
            boltMotionDurationMs = math.max(150, rackDuration * (0.70 + ZombRand(21) / 100))
            boltRiseFraction = math.max(0.30, math.min(0.62, 0.42 / boltSpeedScale))
        end
    else
        boltAction, boltTarget = nil, 0
        boltYawTarget = 0
    end
    local dt = boltLastAt and math.max(0, math.min(0.25, (now - boltLastAt) / 1000)) or 0
    boltLastAt = now
    if racking then
        local progress = math.min(1, math.max(0, (now - boltStartedAt) / boltMotionDurationMs))
        local motion = progress < boltRiseFraction
            and smoothstep(progress / boltRiseFraction)
            or 1 - smoothstep((progress - boltRiseFraction) / (1 - boltRiseFraction))
        boltPitch, boltYaw = boltTarget * motion, boltYawTarget * motion
    else
        boltPitch = approach(boltPitch, 0, 13.125 * boltSpeedScale * dt)
        boltYaw = approach(boltYaw, 0, 2.35 * boltSpeedScale * dt)
    end
    if not racking and boltPitch == 0 and boltYaw == 0 then
        boltLastAt = nil
        boltSpeedScale = 1.0
        boltStartedAt, boltMotionDurationMs, boltRiseFraction = nil, nil, nil
        return false
    end
    return true
end

local lastMotionWeaponId
local function publishRecoilAim(profile, view, dynamicActive)
    local root = rawget(_G, "ViewpointGael")
    local publish = root and root.Aim and root.Aim.setRecoilAim
    local moveSight = root and root.Aim and root.Aim.setHoldSway

    if not profile or not view or not dynamicActive or isCalibratingBlocked() then
        PVADS.GaelDeltaYaw, PVADS.GaelDeltaPitch, PVADS.GaelDeltaRoll = 0, 0, 0
        PVADS.GaelDeltaX, PVADS.GaelDeltaY, PVADS.GaelDeltaZ = 0, 0, 0
        if publish then pcall(publish, profile and profile.weaponId or "", 0, 0, false) end
        if moveSight and (profile or lastMotionWeaponId) then
            pcall(moveSight, (profile and profile.weaponId) or lastMotionWeaponId, 0, 0)
        end
        lastMotionWeaponId = nil
        return
    end

    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = not vars or vars.ShotRecoilAffectsAim ~= false
    if not enabled then
        PVADS.GaelDeltaYaw, PVADS.GaelDeltaPitch, PVADS.GaelDeltaRoll = 0, 0, 0
        PVADS.GaelDeltaX, PVADS.GaelDeltaY, PVADS.GaelDeltaZ = 0, 0, 0
        if publish then pcall(publish, profile.weaponId or "", 0, 0, false) end
        if moveSight then pcall(moveSight, profile.weaponId or "", 0, 0) end
        lastMotionWeaponId = nil
        return
    end

    local baseYaw = tonumber(profile.adjYaw) or 0
    local basePitch = tonumber(profile.adjPitch) or 0
    local baseRoll = tonumber(profile.adjRoll) or 0
    local baseX = tonumber(profile.adjX) or 0
    local baseY = tonumber(profile.adjY) or 0
    local baseZ = tonumber(profile.adjZ) or 0

    local curYaw = tonumber(view.adjYaw) or baseYaw
    local curPitch = tonumber(view.adjPitch) or basePitch
    local curRoll = tonumber(view.adjRoll) or baseRoll
    local curX = tonumber(view.adjX) or baseX
    local curY = tonumber(view.adjY) or baseY
    local curZ = tonumber(view.adjZ) or baseZ

    local dYaw = curYaw - baseYaw
    local dPitch = curPitch - basePitch
    local dRoll = curRoll - baseRoll
    local dX = curX - baseX
    local dY = curY - baseY
    local dZ = curZ - baseZ

    PVADS.GaelDeltaYaw = dYaw
    PVADS.GaelDeltaPitch = dPitch
    PVADS.GaelDeltaRoll = dRoll
    PVADS.GaelDeltaX = dX
    PVADS.GaelDeltaY = dY
    PVADS.GaelDeltaZ = dZ

    local core = getCore()
    local screenH = core and core.getScreenHeight and core:getScreenHeight() or 1080
    local scale = math.max(0.65, math.min(1.50, screenH / 1080))
    local pxPerDeg = 20.0 * scale

    -- The angular alignment is yaw/pitch only. Position and roll still animate
    -- the weapon, but must not be converted into extra degrees of aim error.
    local totalYaw, totalPitch = dYaw, dPitch
    totalYaw, totalPitch = PVADS_GaelAlignment.response(totalYaw, totalPitch)

    PVADS.GaelDynamicScreenX = totalYaw * pxPerDeg
    PVADS.GaelDynamicScreenY = totalPitch * pxPerDeg

    if publish then
        -- The shot leaves opposite the visible barrel deviation. The HUD
        -- marker reads the same shot ray, so it must use this sign as well.
        pcall(publish, profile.weaponId or "", -totalYaw, -totalPitch, true)
    end
    -- Apply the same angular deviation after PVADS aligns the gun. Its sight
    -- projection and the sight ray used by True Ballistics then move together.
    if moveSight then
        pcall(moveSight, profile.weaponId or "", totalYaw, totalPitch)
    end
    lastMotionWeaponId = profile.weaponId
end

local function resetIronFocusState(player, now)
    PVADS.GaelDynamicScreenX = 0
    PVADS.GaelDynamicScreenY = 0
    publishRecoilAim(nil, nil, false)
    stopManualFocus(now)
    wheelFocused, focusDeniedUntil = nil, nil
    updateFocusCharge(player, now)
    updateFocusBlur(player, false)
    lastProfile, lastFov = nil, nil
    focusFovTarget, focusFovFrom, focusFovCurrent, focusFovTransitionAt = nil, nil, nil, nil
    if focusBar then focusBar:setVisible(false) end
    swayKey, swayApplied, swayAt, swayLimit, lastSwayPushAt = nil, false, nil, nil, nil
    swayYaw, swayPitch = 0, 0
    armJitterYaw, armJitterPitch = 0, 0
    armJitterTargetYaw, armJitterTargetPitch, nextArmJitterAt = 0, 0, nil
    lastCenterAt, nextCenterDelayMs, returningToCenter, shotResetPending = nil, nil, false, false
    resetSightSway(nil)
    resetMotionSway()
    focusSwayScale = 1.00
    recoilStartedAt, recoilStartPitch, recoilPitch, recoilPeakPitch = nil, 0, 0, 0
    recoilStartYaw, recoilYaw, recoilPeakYaw = 0, 0, 0
    boltAction, boltPitch, boltTarget, boltLastAt = nil, 0, 0, nil
    boltYaw, boltYawTarget = 0, 0
    boltSpeedScale = 1.0
    boltStartedAt, boltMotionDurationMs, boltRiseFraction = nil, nil, nil
end

local function pushDynamicProfile(view, profile)
    local root = rawget(_G, "ViewpointGael")
    local apply = root and root.Aim and root.Aim.setDynamicProfile
    if apply then
        pcall(apply, profile.weaponId,
            tonumber(view.adjX) or 0, tonumber(view.adjY) or 0, tonumber(view.adjZ) or 0,
            tonumber(view.adjPitch) or 0, tonumber(view.adjYaw) or 0,
            tonumber(view.adjRoll) or 0, tonumber(view.fovMul) or 0.9)
    end
    if PVADS_setProfile then
        pcall(PVADS_setProfile, view)
    end
end

local function updateIronFocus(player)
    if player ~= getSpecificPlayer(0) then return end
    local focusNow = getTimestampMs()
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not controller or not controller.ready or not profile or not PVADS_setProfile then
        resetIronFocusState(player, focusNow)
        return
    end

    local crouchEnabled, wheelEnabled, multiplier = settings()
    local iron = profile.mode == "iron" and not profile.opticId and not profile.noIrons
    if not controller.lastWant or not wheelEnabled or not iron then
        stopManualFocus(focusNow)
        wheelFocused = nil
        focusDeniedUntil = nil
    end
    updateFocusCharge(player, focusNow)
    if focusDeniedUntil and focusNow >= focusCooldownUntil
        and focusChargeMs >= focusCapacityMs * FOCUS_RESTART_FRACTION then
        focusDeniedUntil = nil
    end
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    updateFocusBlur(player, wheelFocused == true and iron and wheelEnabled
        and controller.lastWant and (not vars or vars.FocusSearchBlur ~= false))
    if focusBar then
        focusBar:setVisible(not not (iron and controller.lastWant and wheelEnabled
            and (wheelFocused == true or focusDeniedUntil and focusNow < focusDeniedUntil)))
    end
    local baseFov = tonumber(profile.fovMul) or 0.93
    local desiredFocusFov = nil
    if iron then
        if wheelFocused == true then
            desiredFocusFov = math.max(MIN_FOV_MULTIPLIER, baseFov - 0.30)
        elseif wheelFocused == nil and crouchEnabled and player:isSneaking() then
            desiredFocusFov = math.max(MIN_FOV_MULTIPLIER, baseFov * multiplier)
        end
    end
    local targetFov = desiredFocusFov or baseFov
    if profile ~= lastProfile then
        focusFovTarget, focusFovFrom, focusFovCurrent, focusFovTransitionAt =
            baseFov, baseFov, baseFov, focusNow
    end
    if targetFov ~= focusFovTarget then
        focusFovFrom = focusFovCurrent or baseFov
        focusFovTarget, focusFovTransitionAt = targetFov, focusNow
    end
    local focusProgress = math.min(1, math.max(0,
        (focusNow - focusFovTransitionAt) / FOCUS_ZOOM_TRANSITION_MS))
    focusFovCurrent = focusFovFrom + (focusFovTarget - focusFovFrom) * smoothstep(focusProgress)
    local focusFov = (desiredFocusFov or focusProgress < 1) and focusFovCurrent or nil
    local swayActive, now = updateWeaponSway(player, controller, profile)
    now = now or getTimestampMs()
    local regripActive = updateReleaseRegrip(player, controller, now)
    local recoilActive = updateShotRecoil(controller, profile, now)
    local boltActive = updateBoltPitch(player, controller, profile, now)
    local dynamicActive = swayActive or recoilActive or boltActive or regripActive
    local hadDynamicProfile = lastFov ~= nil or lastSwayPushAt ~= nil
    lastProfile, lastFov = profile, focusFov

    if focusFov or dynamicActive then
        local view = {}
        for key, value in pairs(profile) do view[key] = value end
        if focusFov then view.fovMul = focusFov end
        if swayActive then
            local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
            local focusScale = focusSwayScale
            if not vars or vars.NoReferenceHoldSway ~= false then
                view.adjYaw = (tonumber(profile.adjYaw) or 0)
                    + (swayYaw + armJitterYaw) * focusScale
                view.adjPitch = (tonumber(profile.adjPitch) or 0)
                    + (swayPitch + armJitterPitch) * focusScale
            end
            if not vars or vars.SightMotion ~= false then
                view.adjX = (tonumber(profile.adjX) or 0) + sightOffsetX * focusScale
                view.adjY = (tonumber(profile.adjY) or 0) + (sightOffsetY + walkY) * focusScale
                view.adjZ = (tonumber(profile.adjZ) or 0)
                    + math.max(ARM_DROP_Z, math.min(SIGHT_Z_MAX, sightOffsetZ + armDropZ)) * focusScale
                view.adjRoll = (tonumber(profile.adjRoll) or 0) + walkRoll * focusScale
            end
        end
        if recoilActive then
            view.adjYaw = (tonumber(view.adjYaw) or tonumber(profile.adjYaw) or 0) + recoilYaw
        end
        if boltActive then
            view.adjYaw = (tonumber(view.adjYaw) or tonumber(profile.adjYaw) or 0) + boltYaw
        end
        if regripActive then
            view.adjYaw = (tonumber(view.adjYaw) or tonumber(profile.adjYaw) or 0)
                + releaseRegripYaw
        end
        if recoilActive or boltActive then
            view.adjPitch = (tonumber(view.adjPitch) or tonumber(profile.adjPitch) or 0)
                - (recoilActive and recoilPitch or 0) - (boltActive and boltPitch or 0)
        end
        if regripActive then
            view.adjPitch = (tonumber(view.adjPitch) or tonumber(profile.adjPitch) or 0)
                + releaseRegripPitch
        end
        pushDynamicProfile(view, profile)
        publishRecoilAim(profile, view, dynamicActive)
    elseif hadDynamicProfile then
        PVADS_setProfile(profile)
        publishRecoilAim(profile, nil, false)
    end
    lastSwayPushAt = dynamicActive and now or nil
end

local function setManualFocus(focused)
    local _, enabled = settings()
    if not enabled then return end
    local player = getSpecificPlayer(0)
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not player or not controller or not controller.ready or not controller.lastWant
        or not player:isAiming() or not profile
        or profile.mode ~= "iron" or profile.opticId or profile.noIrons then return end
    local now = getTimestampMs()
    updateFocusCharge(player, now)
    if focused then
        if wheelFocused == true then return end
        if now < focusCooldownUntil
            or focusChargeMs < focusCapacityMs * FOCUS_RESTART_FRACTION then
            focusDeniedUntil = now + FOCUS_DENIED_MESSAGE_MS
            updateIronFocus(player)
            return
        end
        focusDeniedUntil = nil
        wheelFocused = true
        if focusBar then
            focusBar.colorLevel, focusBar.lastColorAt = 0.5, now
        end
    else
        focusDeniedUntil = nil
        stopManualFocus(now)
    end
    updateIronFocus(player)
end

local function onWheel(wheel)
    wheel = tonumber(wheel) or 0
    if wheel ~= 0 then setManualFocus(wheel > 0) end
end

local function onFocusKey(key)
    key = tonumber(key) or 0
    if key == 0 then return end
    local controls = PVADS and PVADS.Settings
    if not controls then return end
    local zoomIn = tonumber(controls.zoomInKey) or 0
    local zoomOut = tonumber(controls.zoomOutKey) or 0
    if zoomIn ~= 0 and key == zoomIn then
        setManualFocus(true)
    elseif zoomOut ~= 0 and key == zoomOut then
        setManualFocus(false)
    end
end

local function onWeaponFired(player, weapon)
    if player ~= getSpecificPlayer(0) or not weapon or not weapon:isRanged() then return end
    local controller = PVADS and PVADS.Controller
    if controller and controller.ready and controller.lastWant then
        shotResetPending = true
        focusDeniedUntil = nil
        stopManualFocus(getTimestampMs()) -- Firing cancels manual focus and starts its cooldown.
        if focusBar then focusBar:setVisible(false) end
        focusSwayScale = 1.00
        local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
        if not vars or vars.ShotPitchRecoil ~= false then
            local shotAt = getTimestampMs()
            local fireMode = weapon.getFireMode and weapon:getFireMode()
            local automatic = fireMode and string.lower(tostring(fireMode)) == "auto"
                or (fireMode == nil and weapon.isAutomatic and weapon:isAutomatic())
            if weapon ~= burstWeapon or not burstLastShotAt
                or shotAt - burstLastShotAt > BURST_RESET_MS
                or automatic ~= burstAutomatic then
                burstShotCount = 0
                longBurstPitchDirection, longBurstYawDirection = nil, nil
                longBurstPitchAnchor, longBurstYawAnchor = nil, nil
                longBurstPitchFrom, longBurstYawFrom = nil, nil
                longBurstLegShots, longBurstLegStep = nil, 0
                releaseRegripArmed, releaseTriggerSeen, releaseRegripAt = false, false, nil
                releaseRegripYaw, releaseRegripPitch = 0, 0
            end
            burstWeapon, burstLastShotAt, burstAutomatic = weapon, shotAt, automatic
            burstShotCount = burstShotCount + 1
            if automatic and burstShotCount >= RELEASE_REGRIP_SHOTS then
                releaseRegripArmed = true
                if player.isAttackButtonDown and player:isAttackButtonDown() then
                    releaseTriggerSeen = true
                end
            end
            releaseRegripAt, releaseRegripYaw, releaseRegripPitch = nil, 0, 0
            local burstScale = burstShotCount <= 3 and 0.50
                or (burstShotCount <= 5 and 0.75 or 1.00)
            local longBurstBonus = automatic and burstShotCount > LONG_BURST_RECOIL_SHOTS
                and LONG_BURST_RECOIL_BONUS or 0
            recoilLongBurst = longBurstBonus > 0
            recoilStartedAt = shotAt
            recoilStartPitch = recoilPitch
            recoilStartYaw = recoilYaw
            local exertion = enduranceLevel(player)
            local minPitch, maxPitch = 5.0, 12.0
            if exertion == 1 then
                minPitch, maxPitch = 6.0, 14.0
            elseif exertion == 2 then
                minPitch, maxPitch = 8.0, 16.0
            elseif exertion >= 3 then
                minPitch, maxPitch = 10.0, 20.0
            end
            local weaponWeight = tonumber(weapon:getWeight()) or 0
            recoilDurationMs = weaponWeight > HEAVY_RECOIL_WEIGHT
                and (750 + ZombRand(401)) or (650 + ZombRand(301))
            recoilRiseMs, recoilHoldMs = RECOIL_RISE_MS, RECOIL_HOLD_MS
            if longBurstBonus > 0 then
                recoilRiseMs = LONG_BURST_RISE_MS
                recoilHoldMs = burstShotCount > RELEASE_REGRIP_SHOTS
                    and LATE_BURST_HOLD_MS or LONG_BURST_HOLD_MS
                recoilDurationMs = burstShotCount > RELEASE_REGRIP_SHOTS
                    and LATE_BURST_DURATION_MS or LONG_BURST_DURATION_MS
            end
            if burstShotCount > 5 then
                local recoveryBonusPerLevel = burstShotCount >= RELEASE_REGRIP_SHOTS
                    and 0.15 or 0.10
                local recoverySpeed = 1 + recoilFitnessLevels(player) * recoveryBonusPerLevel
                recoilDurationMs = recoilHoldMs
                    + (recoilDurationMs - recoilHoldMs) / recoverySpeed
            end
            local bonus = weaponWeight > HEAVY_RECOIL_WEIGHT and HEAVY_RECOIL_BONUS
                or (PISTOL_RECOIL_BONUS[weapon:getFullType()] or 0)
            minPitch = minPitch + bonus
            maxPitch = maxPitch + bonus
            local strength = math.max(0, math.min(10, tonumber(player:getPerkLevel(Perks.Strength)) or 5))
            local recoilScale = automatic
                and (1 / (AUTO_RECOIL_MIN_DIVISOR
                    + (AUTO_RECOIL_MAX_DIVISOR - AUTO_RECOIL_MIN_DIVISOR) * STRENGTH_RECOIL_EFFECT * strength / 10)) or 1
            recoilScale = recoilScale * burstScale
            local steps = math.floor((maxPitch - minPitch) * 10)
            local direction = ZombRand(5) == 0 and -1 or 1
            local amount = (minPitch + ZombRand(steps + 1) / 10) * recoilScale
                + longBurstBonus
            local minYaw, maxYaw = 4.0, 10.0
            local yawSteps = math.floor((maxYaw - minYaw) * 10)
            local yawDirection = ZombRand(2) == 0 and -1 or 1
            local yawAmount = (minYaw + ZombRand(yawSteps + 1) / 10) * recoilScale
                + longBurstBonus
            local muscleFatigue = armMuscleFatigue(player)
            amount = amount * (1 + muscleFatigue)
            yawAmount = yawAmount * (1 + muscleFatigue)
            if longBurstBonus > 0 then
                longBurstPitchDirection = longBurstPitchDirection
                    or (recoilPitch ~= 0 and (recoilPitch > 0 and 1 or -1) or direction)
                longBurstYawDirection = longBurstYawDirection
                    or (recoilYaw ~= 0 and (recoilYaw > 0 and 1 or -1) or yawDirection)
                if not longBurstLegShots then
                    longBurstPitchFrom, longBurstYawFrom =
                        longBurstPitchDirection, longBurstYawDirection
                    longBurstPitchDirection, longBurstYawDirection = nextLongBurstCorner(
                        longBurstPitchFrom, longBurstYawFrom)
                    longBurstLegShots, longBurstLegStep = 4 + ZombRand(2), 0
                elseif longBurstLegStep >= longBurstLegShots then
                    local nextPitch, nextYaw = nextLongBurstCorner(
                        longBurstPitchDirection, longBurstYawDirection)
                    longBurstPitchFrom, longBurstYawFrom =
                        longBurstPitchDirection, longBurstYawDirection
                    longBurstPitchDirection, longBurstYawDirection = nextPitch, nextYaw
                    longBurstLegShots, longBurstLegStep = 4 + ZombRand(2), 0
                end
                longBurstLegStep = longBurstLegStep + 1
                direction, yawDirection = longBurstPitchDirection, longBurstYawDirection
                longBurstPitchAnchor = longBurstPitchAnchor
                    and approach(longBurstPitchAnchor, amount, LONG_BURST_ANCHOR_STEP) or amount
                longBurstYawAnchor = longBurstYawAnchor
                    and approach(longBurstYawAnchor, yawAmount, LONG_BURST_ANCHOR_STEP) or yawAmount
                amount = math.max(0.25, longBurstPitchAnchor
                    + (ZombRand(2001) / 1000 - 1) * LONG_BURST_PITCH_IMPULSE)
                yawAmount = math.max(0.25, longBurstYawAnchor
                    + (ZombRand(2001) / 1000 - 1) * LONG_BURST_YAW_IMPULSE)
            end
            local gripScale = PVADS_GaelGrip.recoilMultiplier(weapon)
            local pitchTarget = amount * SHOT_RECOIL_SCALE * gripScale
            local yawTarget = yawAmount * SHOT_RECOIL_SCALE * gripScale
            recoilPeakPitch = direction * (longBurstBonus > 0 and pitchTarget
                or math.max(pitchTarget, direction * recoilPitch))
            recoilPeakYaw = yawDirection * (longBurstBonus > 0 and yawTarget
                or math.max(yawTarget, yawDirection * recoilYaw))
        end
    end
end

Events.OnPlayerUpdate.Add(updateIronFocus)
Events.OnGameStart.Add(createFocusBar)
Events.OnMouseWheel.Add(onWheel)
Events.OnKeyPressed.Add(onFocusKey)
Events.OnWeaponSwingHitPoint.Add(onWeaponFired)
