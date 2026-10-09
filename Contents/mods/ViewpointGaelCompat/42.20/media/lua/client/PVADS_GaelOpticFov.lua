-- Apply optic FOV after PVADS has combined the weapon, mount, optic and user calibration.
require "PVADS/PVADS_Core"

if not PVADS._gaelOpticFovWrapped then
    local resolveProfile = PVADS.ResolveProfile

    PVADS.ResolveProfile = function(weapon)
        local profile = resolveProfile(weapon)
        local fov = profile and tonumber(profile.fovMul)
        if profile and profile.opticId and fov and fov >= 0.8 then
            local mag = tonumber(profile.mag) or 1
            local onePower = profile.mode == "reflex" or mag <= 1.01
            profile.fovMul = math.max(0.3, fov - (onePower and 0.2 or 0.3))
        end
        return profile
    end

    PVADS._gaelOpticFovWrapped = true
end
