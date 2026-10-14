-- String-valued visual choices for the Gael calibrator. PVADS 1.6's stock
-- profile file only reads/writes numbers; keep both kinds in the same file.
require "PVADS/PVADS_Calibrator"

if not PVADS.gaelVisualChoicesInstalled then
    PVADS.gaelVisualChoicesInstalled = true

    local FILE = "PVADS_UserProfiles.txt"
    local modes = { iron = true, reflex = true, scope = true, scopeg36 = true, scopereddotalt = true }
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
    local okp7DefaultProfile = {
        pipX = 0.00000, pipY = 0.00000, pipZ = 0.00000,
        pipScale = 0.46000, pipZoom = 1.00000,
        pipRetX = 0.00000, pipRetY = -0.16500, pipDepth = 0.00000,
    }
    -- Add new bolt-action sniper IDs here so Carcano lens copying and the
    -- calibrator's sniper-only copy button include them automatically.
    PVADS.GaelSniperCopyWeaponIds = {
        "Base.M24", "Base.Springfield_sniper", "Base.Enfield", "Base.SR338", "Base.CS5",
        "Base.GOL", "Base.JNG90", "Base.L115A", "Base.L96", "Base.M200",
        "Base.M40", "Base.M98B", "Base.Scout_elite", "Base.SV98", "Base.AWS",
    }
    -- Bolt-action sniper and historical rifle IDs that should default these
    -- four small optics to the scope/PiP ADS renderer.
    local boltActionScopeWeapons = {
        ["Base.Carcano"] = true, ["Base.CarcanoCarbine1891"] = true,
        ["Base.Enfield"] = true, ["Base.Enfield1917"] = true,
        ["Base.Kark98"] = true, ["Base.MannlicherM1895"] = true,
        ["Base.MannlicherM1895_long"] = true, ["Base.MartiniHenry"] = true,
        ["Base.MAS36"] = true, ["Base.Mauser98"] = true,
        ["Base.Mosin"] = true, ["Base.MosinNagant1891"] = true,
        ["Base.RossMK3"] = true, ["Base.Springfield1903"] = true,
        ["Base.TankgewehrM1918"] = true, ["Base.VarmintRifle"] = true,
        ["Base.HuntingRifle"] = true, ["Base.DeLisle"] = true,
        ["Base.M24"] = true, ["Base.Springfield_sniper"] = true,
        ["Base.SR338"] = true, ["Base.CS5"] = true, ["Base.GOL"] = true,
        ["Base.JNG90"] = true, ["Base.L115A"] = true, ["Base.L96"] = true,
        ["Base.M200"] = true, ["Base.M40"] = true, ["Base.M98B"] = true,
        ["Base.Scout_elite"] = true, ["Base.SV98"] = true, ["Base.AWS"] = true,
    }
    local scopeADSOptics = {
        ["Base.SLDG"] = true, ["Base.PKA"] = true,
        ["Base.CP1"] = true, ["Base.MicroT1"] = true,
    }
    local redDotAltDefaults = {
        ["Base.AK74"] = true,
        ["Base.AUG_A2"] = true,
    }
    local rdsLensSizeDefaults = {
        ["Base.AK47"] = true,
    }
    -- Completed one-time profile migrations are archived in docs/archive/PVADS_GaelVisualChoices.pre-checkpoint.lua.txt.
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
        local fields = { "adjX", "adjY", "adjZ", "adjPitch", "adjYaw", "adjRoll", "fovMul", "relief", "lensScale", "pipScale", "pipZoom", "adsTime", "mode", "reticle", "pipAlt", "recoilPitchReverse" }
        local out = {}
        for _, name in ipairs(fields) do
            local value = values[name]
            if value ~= nil then out[#out + 1] = name .. "=" .. tostring(value) end
        end
        return #out > 0 and table.concat(out, ",") or "empty"
    end
    PVADS.ResolveProfile = function(weapon)
        local profile = originalResolveProfile(weapon)
        -- Default OKP-7 presentation for any weapon, including combinations
        -- without a user profile. Personal values remain intact once saved.
        if profile.opticId == "Base.OKP7" then
            local key = tostring(profile.weaponId) .. "|" .. tostring(profile.opticId)
            local user = PVADS.User and PVADS.User[key]
            if not user then
                profile.mode = "scopereddotalt"
                for name, value in pairs(okp7DefaultProfile) do
                    profile[name] = value
                    if profile.userWeapon then profile.userWeapon[name] = value end
                end
            end
        end
        -- MiniRedDot is a small reflex optic that needs the alternate scope
        -- window. Use it for every weapon carrying this optic unless the user
        -- explicitly selected a different ADS mode for that weapon/optic.
        if profile.opticId == "Base.MiniRedDot" then
            local key = tostring(profile.weaponId) .. "|" .. tostring(profile.opticId)
            local user = PVADS.User and PVADS.User[key]
            if not user or user.mode == nil then
                profile.mode = "scopereddotalt"
            end
            -- 0.095 is the old accidentally shrunken PiP value. Migrate it
            -- in memory and use the intended shared size; leave other manual
            -- per-weapon sizes untouched.
            if user and tonumber(user.pipScale) == 0.095 then
                user.pipScale = 1.94000
                profile.pipScale = 1.94000
                if profile.userWeapon then profile.userWeapon.pipScale = 1.94000 end
            elseif not user or user.pipScale == nil then
                if profile.userWeapon then profile.userWeapon.pipScale = 1.94000 end
                profile.pipScale = 1.94000
            end
        end
        -- The G36 carry-handle optic needs the stock scope renderer and reticle.
        -- Keep a named choice in the calibrator, but pass native values to ADS.
        if profile.weaponId == "Base.G36" and profile.mode == "scopeg36" then
            profile.mode = "scope"
            profile.reticle = "eastern"
        end
        if profile.weaponId and profile.opticId
            and boltActionScopeWeapons[profile.weaponId] and scopeADSOptics[profile.opticId] then
            local key = tostring(profile.weaponId) .. "|" .. tostring(profile.opticId)
            local user = PVADS.User and PVADS.User[key]
            if not user or user.mode == nil then profile.mode = "scope" end
        end
        -- RedDot defaults for the AK-74 and AUG A3, with the same low sight
        -- height and alternate scope-style ADS. Preserve explicit user tuning.
        if profile.weaponId and profile.opticId == "Base.RedDot"
            and redDotAltDefaults[profile.weaponId] then
            local key = tostring(profile.weaponId) .. "|Base.RedDot"
            local user = PVADS.User and PVADS.User[key]
            if not user or user.mode == nil then profile.mode = "scopereddotalt" end
            if not user or user.adjZ == nil then profile.adjZ = -0.01700 end
        end
        if profile.weaponId and profile.opticId == "Base.RDS"
            and rdsLensSizeDefaults[profile.weaponId] then
            local key = tostring(profile.weaponId) .. "|Base.RDS"
            local user = PVADS.User and PVADS.User[key]
            local lensScale = user and tonumber(user.lensScale) or 2.00000
            profile.lensScale = lensScale
            if profile.userWeapon then profile.userWeapon.lensScale = lensScale end
        end
        -- Small scope-style lens for x1 reflex optics that need a separate
        -- sight window. Keep the selected reticle and user lens-size tuning.
        if profile.mode == "scopereddotalt" then
            local key = tostring(profile.weaponId) .. "|" .. tostring(profile.opticId or "")
            local user = PVADS.User and PVADS.User[key]
            profile.mode = "scope"
            -- PVADS routes optic fields into userWeapon, so p.lensScale can
            -- still be the optic default (often 1.0) after ResolveProfile.
            -- Promote the saved calibration for this renderer explicitly.
            profile.lensScale = user and tonumber(user.lensScale) or 0.20
        end
        -- Since PVADS 1.8, optic calibrations are moved to userWeapon so the
        -- Java optic renderer can apply them. Its PiP lens-size path still
        -- reads the resolved top-level value in some update states, briefly
        -- falling back to the optic default (1.0). Keep the resolved value
        -- stable for both render paths.
        local opticUser = profile.userWeapon
        if opticUser then
            for _, name in ipairs({ "pipScale", "pipZoom", "pipX", "pipY", "pipZ", "pipRetX", "pipRetY", "pipDepth" }) do
                if opticUser[name] ~= nil then profile[name] = tonumber(opticUser[name]) or profile[name] end
            end
            if opticUser.lensScale ~= nil and (profile.mode == "scope"
                or (profile.opticId == "Base.RDS" and profile.weaponId
                    and rdsLensSizeDefaults[profile.weaponId])) then
                profile.lensScale = tonumber(opticUser.lensScale) or profile.lensScale
            end
        end
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
        local migratedMiniRedDotPipSizes = 0
        local migratedOKP7Profiles = 0
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
                if string.match(key, "|Base%.MiniRedDot$") and tonumber(profile.pipScale) == 0.095 then
                    profile.pipScale = 1.94000
                    migratedMiniRedDotPipSizes = migratedMiniRedDotPipSizes + 1
                end
                if string.match(key, "|Base%.OKP7$") and tonumber(profile.okp7DefaultVersion) ~= 2 then
                    profile.mode = "scopereddotalt"
                    for name, value in pairs(okp7DefaultProfile) do profile[name] = value end
                    profile.okp7DefaultVersion = 2
                    migratedOKP7Profiles = migratedOKP7Profiles + 1
                end
                PVADS.User[key] = profile
                loaded = loaded + 1
            end
        end
        reader:close()
        -- Completed batch copies are deliberately inactive now; see the archived migration source.
        print(string.format("[ViewpointGaelCompat][profiles] loaded %d user profiles from %s", loaded, FILE))
        if migratedMiniRedDotPipSizes > 0 and PVADS.saveUserProfiles then
            local saved = PVADS.saveUserProfiles()
            print(string.format("[ViewpointGaelCompat][profiles] migrated %d MiniRedDot PiP sizes from 0.095 to 1.94 (saved=%s)",
                migratedMiniRedDotPipSizes, tostring(saved)))
        end
        if migratedOKP7Profiles > 0 and PVADS.saveUserProfiles then
            local saved = PVADS.saveUserProfiles()
            print(string.format("[ViewpointGaelCompat][profiles] applied OKP-7 defaults to %d saved profiles (saved=%s)",
                migratedOKP7Profiles, tostring(saved)))
        end
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
            if string.match(key, "|Base%.OKP7$") and profile.okp7DefaultVersion == nil then
                profile.okp7DefaultVersion = 2
            end
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
