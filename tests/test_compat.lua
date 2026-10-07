local pvadsRoot = assert(os.getenv("PVADS_LUA_SHARED"), "Set PVADS_LUA_SHARED to ProjectViewpointADS/42/media/lua/shared")
package.path = "Contents/mods/PVADSGaelOptics/42/media/lua/client/?.lua;" .. pvadsRoot .. "/?.lua;" .. package.path
local init
Events = { OnGameStart = { Add = function(fn) init = fn end } }
local shapes = {}
PVADS_setOpticShape = function(name) shapes[name] = true end

require "VP_GaelCompat"
assert(init)
init()
assert(not shapes.ACOGx4 and shapes.EKP_kobra)

local function gun(partType, partName)
    local part = { getFullType = function() return "Base." .. partName end,
        getPartType = function() return partType end }
    local parts = { size = function() return 1 end, get = function() return part end }
    return { getFullType = function() return "Base.UMP45" end,
        getDisplayName = function() return "UMP-45" end,
        getAllWeaponParts = function() return parts end }
end

local acog = PVADS.ResolveProfile(gun("Scope", "ACOGx4"))
assert(acog.family == "smg" and acog.mode == "scope" and acog.mag == 4)
assert(acog.reticle == "chevron" and acog.opticId == "Base.ACOGx4")
assert(acog.relief == 0.22)

local kobra = PVADS.ResolveProfile(gun("L_Scope", "EKP_kobra"))
assert(kobra.mode == "reflex" and kobra.mag == 1 and kobra.opticId == "Base.EKP_kobra")

local redDot = PVADS.ResolveProfile(gun("Scope", "RedDot"))
assert(redDot.mode == "reflex" and redDot.mag == 1)
assert(redDot.relief ~= acog.relief)
assert(PVADS.Generated.weapons["Base.AK74"] == nil)
local ak74 = { getFullType = function() return "Base.AK74" end,
    getWeight = function() return 2.8 end, getMaxDamage = function() return 7 end,
    getAllWeaponParts = function() return { size = function() return 0 end } end }
local akProfile = PVADS.ResolveProfile(ak74)
assert(akProfile.ironSource == "rear+front" and akProfile.sy == 0.083)
print("Viewpoint/Gael optic registration checks passed")


