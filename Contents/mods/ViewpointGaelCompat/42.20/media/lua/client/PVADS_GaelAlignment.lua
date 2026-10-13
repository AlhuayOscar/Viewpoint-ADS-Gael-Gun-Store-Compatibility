-- Generic ADS alignment response around the weapon's saved sight calibration.
-- The calibrated front/rear sight line is zero. Small hold errors are easier to
-- control; large errors move the gun and its shot line progressively farther.
PVADS_GaelAlignment = PVADS_GaelAlignment or {}

local function smoothstep(low, high, value)
    local t = math.max(0, math.min(1, (value - low) / (high - low)))
    return t * t * (3 - 2 * t)
end

function PVADS_GaelAlignment.response(yaw, pitch)
    yaw, pitch = tonumber(yaw) or 0, tonumber(pitch) or 0
    local error = math.sqrt(yaw * yaw + pitch * pitch)
    if error < 0.00001 then return 0, 0 end

    local fine = 0.38 + 0.62 * smoothstep(0.20, 1.50, error)
    local large = 1 + 0.60 * smoothstep(1.20, 4.00, error)
    local corrected = math.min(20, error * fine * large)
    local factor = corrected / error
    return yaw * factor, pitch * factor
end
