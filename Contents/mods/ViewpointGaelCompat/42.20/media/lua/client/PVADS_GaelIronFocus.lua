-- Experimental: crouching narrows the ADS view for unmounted iron sights.
-- Only fovMul changes; the calibrated sight position and saved profile stay intact.
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFocused = false
local lastMultiplier = nil

local function settings()
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    local enabled = not vars or vars.CrouchIronFocus ~= false
    local multiplier = tonumber(vars and vars.CrouchIronFocusMultiplier) or 0.70
    return enabled, math.max(0.30, math.min(1.00, multiplier))
end

local function updateIronFocus(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not controller or not controller.ready or not profile or not PVADS_setProfile then
        lastProfile, lastFocused, lastMultiplier = nil, false, nil
        return
    end

    local enabled, multiplier = settings()
    local focused = enabled
        and profile.mode == "iron"
        and not profile.opticId
        and not profile.noIrons
        and player:isSneaking()
    if profile == lastProfile and focused == lastFocused
        and (not focused or multiplier == lastMultiplier) then return end
    lastProfile, lastFocused, lastMultiplier = profile, focused, multiplier

    if focused then
        local view = {}
        for key, value in pairs(profile) do view[key] = value end
        view.fovMul = math.max(MIN_FOV_MULTIPLIER,
            (tonumber(profile.fovMul) or 0.93) * multiplier)
        PVADS_setProfile(view)
    elseif profile.mode == "iron" and not profile.opticId then
        PVADS_setProfile(profile)
    end
end

Events.OnPlayerUpdate.Add(updateIronFocus)
