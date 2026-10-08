-- Experimental: crouching narrows the ADS view for unmounted iron sights.
-- Only fovMul changes; the calibrated sight position and saved profile stay intact.
local FOCUS_MULTIPLIER = 0.70
local MIN_FOV_MULTIPLIER = 0.30 -- PVADS Java clamps fovMul to this value.

local lastProfile = nil
local lastFocused = false

local function updateIronFocus(player)
    if player ~= getSpecificPlayer(0) then return end
    local controller = PVADS and PVADS.Controller
    local profile = controller and controller.profile
    if not controller or not controller.ready or not profile or not PVADS_setProfile then
        lastProfile, lastFocused = nil, false
        return
    end

    local focused = profile.mode == "iron"
        and not profile.opticId
        and not profile.noIrons
        and player:isSneaking()
    if profile == lastProfile and focused == lastFocused then return end
    lastProfile, lastFocused = profile, focused

    if focused then
        local view = {}
        for key, value in pairs(profile) do view[key] = value end
        view.fovMul = math.max(MIN_FOV_MULTIPLIER,
            (tonumber(profile.fovMul) or 0.93) * FOCUS_MULTIPLIER)
        PVADS_setProfile(view)
    elseif profile.mode == "iron" and not profile.opticId then
        PVADS_setProfile(profile)
    end
end

Events.OnPlayerUpdate.Add(updateIronFocus)
