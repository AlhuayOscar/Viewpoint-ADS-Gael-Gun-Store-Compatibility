-- Apply optic FOV after PVADS has combined the weapon, mount, optic and user calibration.
require "PVADS/PVADS_Core"

if not PVADS._gaelOpticFovWrapped then
    local resolveProfile = PVADS.ResolveProfile

    PVADS.ResolveProfile = function(weapon)
        local profile = resolveProfile(weapon)
        local fov = profile and tonumber(profile.fovMul)
        if profile and profile.opticId and fov then
            local mag = tonumber(profile.mag) or 1
            local onePower = profile.mode == "reflex" or mag <= 1.01
            -- Keep a little more view for 1x sights and give magnified optics
            -- stronger ADS zoom. Scale every calibrated FOV so low saved
            -- values still receive the same optic treatment as iron sights.
            profile.fovMul = math.max(0.3, fov * (onePower and 0.8 or 0.7))
        end
        return profile
    end

    PVADS._gaelOpticFovWrapped = true
end
