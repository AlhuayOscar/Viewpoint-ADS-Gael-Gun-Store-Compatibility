-- Presentation weights: rotational barrel recoil 70%, positional push 30%.
-- Degrees and metres are separate effects, weighted against their own baseline.
require "PVADS_GaelWeaponCatalog"
require "PVADS_GaelAlignment"
PVADS_GaelRecoilBalance = PVADS_GaelRecoilBalance or {}
local balance = PVADS_GaelRecoilBalance
balance.angularWeight, balance.offsetWeight = 0.70, 0.30

function balance.armPenalty(stiffness, pain)
    local muscle = stiffness >= 20 and 3 or (stiffness >= 5 and 1.5 or 0)
    return math.max(muscle, math.max(0, math.min(100, pain)) * 0.03)
end

function balance.movementFactor(exertion, fatigue)
    return 1 + math.max(0, math.min(4, exertion)) * 0.25
        + math.max(0, math.min(3, fatigue)) * 0.5
end

-- Keep the first five impulses and the existing long-burst/regrip policy.
-- Later rapid automatic shots accumulate actual angular error, not HUD offset.
function balance.burstPeak(target, previous, shots, automatic, longBurst, limit)
    if not automatic or shots <= 5 or longBurst then return target end
    local direction = previous ~= 0 and (previous > 0 and 1 or -1)
        or (target >= 0 and 1 or -1)
    return direction * math.min(limit, math.abs(previous) + math.abs(target) * 0.8)
end

function balance.longBurstAnchor(target, previous, scale)
    return scale > 0 and math.max(target, math.abs(previous) / scale) or target
end

local weapons = {}
for _, entry in ipairs(PVADS_GaelWeaponCatalog or {}) do weapons[entry[2]] = true end

function balance.profile(profile)
    if not profile or not weapons[profile.weaponId] or profile._gaelRecoilBalanced then
        return profile
    end
    local view = {}
    for key, value in pairs(profile) do view[key] = value end
    view.gunKick = (tonumber(profile.gunKick) or 3) * balance.angularWeight
    view.gunBack = (tonumber(profile.gunBack) or 0.02) * balance.offsetWeight
    view._gaelRecoilBalanced = true
    return view
end

function balance.angular(yaw, pitch, recoilYaw, recoilPitch)
    recoilYaw, recoilPitch = recoilYaw or 0, recoilPitch or 0
    -- Only breathing/hold motion uses the fine alignment response. Shot recoil
    -- must rotate the barrel directly, including the existing burst/regrip curve.
    local holdYaw, holdPitch = PVADS_GaelAlignment.response(
        yaw - recoilYaw, pitch - recoilPitch)
    return holdYaw + recoilYaw * balance.angularWeight,
        holdPitch + recoilPitch * balance.angularWeight
end

function balance.install()
    if not PVADS_setProfile or PVADS_setProfile == balance.wrapper then return end
    local original = PVADS_setProfile
    balance.wrapper = function(profile, ...)
        return original(balance.profile(profile), ...)
    end
    PVADS_setProfile = balance.wrapper
    local controller = PVADS and PVADS.Controller
    if controller and controller.ready and controller.profile then
        balance.wrapper(controller.profile)
    end
end

Events.OnGameBoot.Add(balance.install)
Events.OnGameStart.Add(balance.install)
balance.install()
