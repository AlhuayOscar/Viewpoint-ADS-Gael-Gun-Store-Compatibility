-- String-valued visual choices for the Gael calibrator. PVADS 1.6's stock
-- profile file only reads/writes numbers; keep both kinds in the same file.
require "PVADS/PVADS_Calibrator"

if not PVADS.gaelVisualChoicesInstalled then
    PVADS.gaelVisualChoicesInstalled = true

    local FILE = "PVADS_UserProfiles.txt"
    local modes = { iron = true, reflex = true, scope = true }
    local reticles = {
        none = true, dot = true, holo = true, okp7 = true,
        okp7_ring = true, okp7_rings = true,
        kobra_combo = true, kobra_open = true,
        kobra_dotted = true, kobra_chevron = true,
        chevron = true, crossdot = true,
        duplex = true, mildot = true, post = true, eastern = true,
    }
    PVADS.GaelVisualModes = modes
    PVADS.GaelVisualReticles = reticles

    -- Global numeric deltas are applied after the personal weapon/optic override.
    -- Keep them in the same profile file under a reserved, non-weapon key.
    local globalKey = "__GaelGlobalOffsets__|"
    local globalFields = {
        adjX = true, adjY = true, adjZ = true,
        adjPitch = true, adjYaw = true, adjRoll = true,
        relief = true, fovMul = true, opticHeight = true,
        lensScale = true, adsTime = true,
        pipX = true, pipY = true, pipZ = true,
        pipScale = true, pipZoom = true,
        pipRetX = true, pipRetY = true, pipDepth = true,
    }
    local unitDefaults = { lensScale = true, pipScale = true, pipZoom = true }
    PVADS.GaelGlobalKey = globalKey
    PVADS.GaelGlobalFields = globalFields
    function PVADS.GaelGlobalValue(name)
        local offsets = PVADS.User and PVADS.User[globalKey]
        local value = offsets and offsets[name]
        return globalFields[name] and type(value) == "number" and value or 0
    end

    function PVADS.GaelGlobalOnlyAvailable()
        local offsets = PVADS.User and PVADS.User[globalKey]
        return offsets and offsets.onlyAvailable == 1 or false
    end

    local function explicitlyCalibrated(profile, name)
        local id, opticId = profile.weaponId, profile.opticId or ""
        local user = PVADS.User and PVADS.User[id .. "|" .. opticId]
        local weaponOptics = PVADS.WeaponOptic and PVADS.WeaponOptic[id]
        local specific = weaponOptics and weaponOptics[opticId]
        local weapon = PVADS.Weapons and PVADS.Weapons[id]
        return (user and user[name] ~= nil)
            or (specific and specific[name] ~= nil)
            or (weapon and weapon[name] ~= nil)
    end

    function PVADS.GaelEffectiveGlobalValue(profile, name)
        if not profile then return 0 end
        if PVADS.GaelGlobalOnlyAvailable() and explicitlyCalibrated(profile, name) then return 0 end
        return PVADS.GaelGlobalValue(name)
    end

    local originalResolveProfile = PVADS.ResolveProfile
    local lastResolvedProfileDiagnostic = {}
    local function diagnosticValues(values)
        if not values then return "none" end
        local fields = { "adjX", "adjY", "adjZ", "adjPitch", "adjYaw", "adjRoll", "fovMul", "relief", "adsTime", "mode", "reticle", "recoilPitchReverse" }
        local out = {}
        for _, name in ipairs(fields) do
            local value = values[name]
            if value ~= nil then out[#out + 1] = name .. "=" .. tostring(value) end
        end
        return #out > 0 and table.concat(out, ",") or "empty"
    end
    PVADS.ResolveProfile = function(weapon)
        local profile = originalResolveProfile(weapon)
        for name in pairs(globalFields) do
            local delta = PVADS.GaelEffectiveGlobalValue(profile, name)
            if delta ~= 0 then
                profile[name] = (tonumber(profile[name]) or (unitDefaults[name] and 1 or 0)) + delta
            end
        end
        local key = tostring(profile.weaponId) .. "|" .. tostring(profile.opticId or "")
        local user = PVADS.User and PVADS.User[key]
        local diagnostic = string.format("[ViewpointGaelCompat][profiles][resolve] key=%s user={%s} opticFields={%s} final={%s}",
            key, diagnosticValues(user), diagnosticValues(profile.userWeapon), diagnosticValues(profile))
        if lastResolvedProfileDiagnostic[key] ~= diagnostic then
            lastResolvedProfileDiagnostic[key] = diagnostic
            print(diagnostic)
        end
        return profile
    end

    function PVADS.loadUserProfiles()
        PVADS.User = {}
        PVADS.GaelDeletedProfileKeys = {}
        local loaded = 0
        local reader = getFileReader(FILE, false)
        if not reader then
            print("[ViewpointGaelCompat][profiles] load: file not found; starting empty")
            return
        end
        while true do
            local line = reader:readLine()
            if not line then break end
            local key, fields = string.match(line, "^([^=]+)=>(.*)$")
            if key then
                local profile = {}
                for name, value in string.gmatch(fields, "([%w_]+)=([^;]+)") do
                    local number = tonumber(value)
                    if number then
                        profile[name] = number
                    elseif name == "mode" and modes[value] then
                        profile.mode = value
                    elseif name == "reticle" and reticles[value] then
                        profile.reticle = value
                    end
                end
                PVADS.User[key] = profile
                loaded = loaded + 1
            end
        end
        reader:close()
        print(string.format("[ViewpointGaelCompat][profiles] loaded %d user profiles from %s", loaded, FILE))
    end

    function PVADS.saveUserProfiles()
        -- The stock writer truncates the file. Keep disk entries missing from
        -- the live table unless the player explicitly reset that profile.
        local preserved = 0
        local reader = getFileReader(FILE, false)
        if reader then
            while true do
                local line = reader:readLine()
                if not line then break end
                local key, fields = string.match(line, "^([^=]+)=>(.*)$")
                if key and PVADS.User[key] == nil
                    and not (PVADS.GaelDeletedProfileKeys and PVADS.GaelDeletedProfileKeys[key]) then
                    local profile = {}
                    for name, value in string.gmatch(fields, "([%w_]+)=([^;]+)") do
                        local number = tonumber(value)
                        if number then
                            profile[name] = number
                        elseif name == "mode" and modes[value] then
                            profile.mode = value
                        elseif name == "reticle" and reticles[value] then
                            profile.reticle = value
                        end
                    end
                    if next(profile) then
                        PVADS.User[key] = profile
                        preserved = preserved + 1
                    end
                end
            end
            reader:close()
        end
        local writer = getFileWriter(FILE, true, false)
        if not writer then return false end
        writer:write("# Project Viewpoint ADS - personal calibration. Format: weapon|optic=>key=value;...\r\n")
        for key, profile in pairs(PVADS.User) do
            local fields = {}
            for name, value in pairs(profile) do
                if type(value) == "number" then
                    fields[#fields + 1] = name .. "=" .. string.format("%.5f", value)
                elseif name == "mode" and modes[value] then
                    fields[#fields + 1] = "mode=" .. value
                elseif name == "reticle" and reticles[value] then
                    fields[#fields + 1] = "reticle=" .. value
                end
            end
            table.sort(fields)
            writer:write(key .. "=>" .. table.concat(fields, ";") .. ";\r\n")
        end
        writer:close()
        local saved = 0
        for _ in pairs(PVADS.User) do saved = saved + 1 end
        PVADS.GaelDeletedProfileKeys = {}
        print(string.format("[ViewpointGaelCompat][profiles] saved %d user profiles to %s (restored %d missing in-memory entries)", saved, FILE, preserved))
        return true
    end

    function PVADS.Calibrator.snippet()
        local playerObj = getSpecificPlayer(0)
        local weapon = PVADS.Controller.weapon(playerObj)
        if not weapon then return "-- no firearm equipped" end
        local key = PVADS.userKey(weapon)
        local profile = PVADS.User[key] or {}
        local fields = {}
        for name, value in pairs(profile) do
            if type(value) == "number" then
                fields[#fields + 1] = name .. " = " .. string.format("%.4f", value)
            elseif name == "mode" and modes[value] then
                fields[#fields + 1] = "mode = " .. string.format("%q", value)
            elseif name == "reticle" and reticles[value] then
                fields[#fields + 1] = "reticle = " .. string.format("%q", value)
            end
        end
        table.sort(fields)
        local weaponId, opticId = string.match(key, "^([^|]*)|(.*)$")
        return string.format('PVADS.RegisterWeaponOpticOverride("%s", "%s", { %s })',
            weaponId, opticId or "", table.concat(fields, ", "))
    end
end
