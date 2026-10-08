-- Experimental: crouching narrows the ADS view for unmounted iron sights.
-- Only fovMul changes; the calibrated sight position and saved profile stay intact.
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFov = nil
local wheelFocused = nil

local function settings()
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = not vars or vars.CrouchIronFocus ~= false
    local wheelEnabled = not vars or vars.WheelIronFocus ~= false
    local multiplier = tonumber(vars and vars.CrouchIronFocusMultiplier) or 0.70
    return enabled, wheelEnabled, math.max(0.30, math.min(1.00, multiplier))
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
Events.OnMouseWheel.Add(onWheel)
