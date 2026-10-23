-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Weapons"

--[[
GaelGunStore 1.6 - Firearms pack (Workshop 3616176188, mod id GaelGunStore_B42) compatibility.

Read from the pack's own files (media/scripts/Firearms/*.txt, scripts/GunPartItem/Scope.txt and L_Scope.txt,
lua/shared/GGS_AimingSystem.lua):
- Its 351 firearms are in module Base and replace the vanilla guns. Families follow the pack's own file
  categories (Pistolas, Revolvers, SMG, SMG_twohands, Rifles_automaticos, Rifles_semi, Rifles_bolt_nomag, LMG,
  Escopeta*), split by calibre / role where a category mixes them. Launchers (Explosives.txt) and bows are left
  to the automatic profile.
- Optics are ordinary weapon parts (PartType Scope, and L_Scope for the side-mounted Russian optics) whose models
  attach at the gun's scope point (mounts under them are drawn as usual), so the runtime systems (iron sights
  measured on the loaded mesh, scope tube measurement, picture-in-picture) apply as they are.
- Magnifications follow the pack's own scope marks (GGS_AimingSystem: SCOPE_MARKS x3 / x4 / x6 / x7 / x8 / x20 /
  x40) and its list of reflex sights (1x). Our scopes stop at 25x, so its 40x BallisticScope is 25x here.
  Optics the pack gives no mark (Accupoint, ATN Thor, IRNV) are set from its own vision class
  (long-range = 8x, ACOG class = 4x).
- Its own scope overlay (client/UI/GGS_ScopeCrosshair.lua: full-screen lens border, black mask, peripheral
  vision, and a mouse-cursor warp before each shot to line the round up with its reticle) is made for the
  top-down view. While Viewpoint draws the view it is kept off (PVADS_Compat_GaelGunStore client part).

Everything here only applies while GaelGunStore is active: its ids (Base.AK47, Base.AA12, ...) are the same as
the Vanilla Firearms Expansion packs' ones, whose measured profiles must stay untouched without it.
]]

PVADS.GaelGunStore = PVADS.GaelGunStore or { active = false }
local G = PVADS.GaelGunStore

--- GaelGunStore loaded: its shared aiming module defines the global GGS_AimingSystem (lua/shared/GGS_AimingSystem.lua).
function G.detect()
    if G.active then return true end
    G.active = rawget(_G, "GGS_AimingSystem") ~= nil
    return G.active
end

local function fam(family, ids, extra)
    for _, id in ipairs(ids) do
        local ft = "Base." .. id
        if not (PVADS.Weapons[ft] and PVADS.Weapons[ft].family) then    -- hand-set vanilla data wins
            local def = { family = family }
            if extra then for k, v in pairs(extra) do def[k] = v end end
            PVADS.RegisterWeaponProfile(ft, def)
        end
    end
end

local function reflex(ids, reticle)
    for _, id in ipairs(ids) do
        if not PVADS.Optics["Base." .. id] then
            PVADS.RegisterOpticProfile("Base." .. id, { kind = "scope", mag = 1.3, reticle = reticle or "dot", lensScale = 0.95, swayMul = 0.87, zero = 50 })
        end
    end
end

local function scope(id, mag, reticle, zero)
    if PVADS.Optics["Base." .. id] then return end                    -- vanilla x2 / x4 / x8 keep their profiles
    PVADS.RegisterOpticProfile("Base." .. id, { kind = "scope", mag = mag, reticle = reticle, zero = zero or (mag >= 8 and 150 or 100) })
end

function G.register()
    if G.registered or not G.detect() then return end
    G.registered = true
    -- ------------------------------------------------------------ weapons (351; launchers and bows excluded)
    fam("assault", { "A91", "ACE21", "ACE23", "ACR", "ADS", "AEK", "AK101", "AK103" })
    fam("assault", { "AK12", "AK19", "AK47", "AK5C", "AK74", "AK74u", "AK74u_long", "AK9" })
    fam("assault", { "AKM", "AKU12", "AK_minidrako", "AMD65", "AN94", "AR15", "AR160", "ASH_12" })
    fam("assault", { "AUG_A1", "AUG_A2", "AssaultRifle", "CZ805", "DDM4", "FAL", "FAL_CQB", "FAMAS" })
    fam("assault", { "FN2000", "G36", "G36C", "Groza", "HK416", "HoneyBadger", "IA2", "K2" })
    fam("assault", { "KAC_PDW", "L85", "LR300", "LVOA", "M4", "MTAR", "QBZ951", "R5" })
    fam("assault", { "SAR21", "SIG516", "SIG_553", "SR3M", "SR47", "SS2V5", "ScarL", "Type81" })
    fam("assault", { "VSK", "VSS", "VSS_Tactical", "VZ58", "Wieger940", "XM8" })
    fam("battlerifle", { "ACE52_CQB", "ACE53", "AR10", "AssaultRifle2", "BAR", "CeiRigotti", "FarquharHill", "FedorovAvtomat" })
    fam("battlerifle", { "FedorovAvtomatMaxim", "G27", "G3A3", "G43", "Galil", "HuotAutomaticRifle", "IA2_308", "M1" })
    fam("battlerifle", { "M1A1", "MK18", "MauserSelbstladerM1916", "Mondragon", "RSC1917", "SA58", "SVT_40", "ScarH" })
    fam("battlerifle", { "Selbstlader1906", "V_M87" })
    fam("carbine", { "CarcanoCarbine1891", "CircuitJudgeRifle", "DeLisle", "M16A2", "MatebaGrifone", "Mini_14", "PieperM1893", "Remington121" })
    fam("carbine", { "RemingtonModel8", "Ruger10_22", "RugerLC", "SKS", "SKS_carbine", "SKS_carbine_short", "SWM1854", "SWM1894" })
    fam("carbine", { "VEPR", "ValmetM82", "Winchester1886", "Winchester1895" })
    fam("machinegun", { "AWS", "CETME", "HK_121", "L86", "LSAT", "Lewis", "M240B", "M249" })
    fam("machinegun", { "M60E4", "MG131", "MG4", "MG42", "MG710", "Minimi", "Negev", "PKM" })
    fam("machinegun", { "PKP", "QBB95", "RPD", "RPK", "RPK12", "RPK16", "Type88" })
    fam("pistol", { "Anaconda", "Automag357", "Automag44", "Automag50AE", "Beretta_PX4", "BrowningHP", "CZ75", "ColtNavy1851" })
    fam("pistol", { "ColtNavyExorcist", "ColtPeacemaker1873", "Coonan357", "Deagle357_gold", "Deagle50AE", "DeagleCar14", "FN502_22LR", "FNX45" })
    fam("pistol", { "FiveSeven", "G17", "G18", "G2", "GSH18", "Glock23", "Glock43", "Glock_tactical" })
    fam("pistol", { "Grizzly50AE", "HKMK23", "Jericho941", "Kimber1911", "M93R", "M9A3", "M9_Samurai", "MP1911" })
    fam("pistol", { "MP_R8", "Nagant_M1895", "OTS_33", "P220", "P220_Elite", "P228", "P99", "PB6P9" })
    fam("pistol", { "Pistol", "Pistol2", "Pistol3", "Python357", "RSH12", "Revolver", "Revolver38", "Revolver666" })
    fam("pistol", { "Revolver_long", "Revolver_short", "Rhino20DS", "Rhino60DS", "Ruger357", "SR1M", "SW1905", "SW1917" })
    fam("pistol", { "SW500", "SW629", "SWM3", "SWM327", "SWM629_Deluxe", "Samurai_aw", "Samurai_kendo", "Schofield1875" })
    fam("pistol", { "ScrapRevolver", "Snub22LR", "Taurus606", "Taurus_RT85", "Taurus_raging_bull", "Taurus_raging_bull460", "USP45", "VP70" })
    fam("pistol", { "VictorySW22", "Walther_P38", "Webley_MK_snub", "Webley_Revolver", "Wildey", "XD", "pistol_shotgun" })
    fam("shotgun", { "AA12", "Becker_Shotgun", "Becker_Shotgun_Short", "BenelliM3", "BenelliM4", "Beretta_A400", "Beretta_A400_Short", "Browning_Auto" })
    fam("shotgun", { "Browning_Auto_Short", "DVB15", "ENARM_Pentagun", "Jackhammer", "KS23", "KSG", "M1887", "M1887_Short" })
    fam("shotgun", { "M620", "MTS_255", "MTS_255_Short", "Mossber500", "Mossber590", "QBA", "QBS09", "QBS09_Short" })
    fam("shotgun", { "RMB93", "Remington1100", "Remington1100_Short", "Remington870", "Remington870_Short", "SPAS12", "SPAS15", "SWMP_12" })
    fam("shotgun", { "Saiga12", "Shorty", "Shotgun", "ShotgunSawnoff", "Sjorgen", "Sjorgen_Short", "Striker", "USAS12" })
    fam("shotgun", { "VR80", "Winchester1897" })
    fam("shotgun", { "DB_Condor", "DB_Condor_sawn", "DoubleBarrelShotgun", "DoubleBarrelShotgunSawnoff" }, { bead = true })
    fam("smg", { "A2000", "AEK919", "APC9K", "AR6951", "AUG_9mm", "CBJ", "CZScorpion", "Colt9mm" })
    fam("smg", { "K7", "Kriss9mm", "KrissVector45", "LanchesterMK1", "MAB38A", "MAT49", "MP18", "MP40" })
    fam("smg", { "MP5", "MP5K", "MP5SD", "MP7", "MP9", "MPX", "MSST", "MX4" })
    fam("smg", { "P90", "P99_Kilin", "PP2000", "PP93", "PPSH41", "PP_Bizon", "Saiga9mm", "Silenced_Sten" })
    fam("smg", { "Sten_MK5", "TMP", "Thompson", "UMP45", "UMP45_long", "UMP9", "UZI", "Veresk" })
    fam("smg", { "X86" })
    fam("smg", { "MAC10", "Micro_UZI", "TEC9", "VZ61" }, { relief = 0.16 })
    fam("sniper", { "CS5", "Carcano", "Enfield", "Enfield1917", "GOL", "HKG28", "HuntingRifle", "JNG90" })
    fam("sniper", { "Kark98", "L115A", "L96", "M110", "M200", "M21", "M24", "M39" })
    fam("sniper", { "M40", "M82A3", "M98B", "MAS36", "MannlicherM1895", "MannlicherM1895_long", "MartiniHenry", "Mauser98" })
    fam("sniper", { "Mosin", "MosinNagant1891", "RossMK3", "SR338", "SV98", "SVD", "SVD12", "SVDK" })
    fam("sniper", { "SVDK_short", "SVD_short", "SVU", "Scout_elite", "Springfield1903", "Springfield_sniper", "TankgewehrM1918", "VSSK" })
    fam("sniper", { "VarmintRifle", "WA2000" })

    -- ------------------------------------------------------------ optics
    -- 1x red dots / holographic sights (the pack's reflex vision class, plus PK-A and the AK Kobra)
    reflex({ "Comp_M4", "Coyote", "CP1", "CrimsonRedDot", "Deltapoint", "Kobra", "MicroT1", "MiniRedDot", "OKP7",
             "RDS", "Romeo3", "RX01", "SigSauerRomeo3", "SLDG", "TruBrite", "VenomRDS", "VortexRedDot", "ZaMiniRDS",
             "PKA", "EKP_kobra" })
    reflex({ "Eotech", "Eotech_XPS3" }, "holo")

    -- SLDG's rear glass is a small round window in the actual FBX mesh.
    -- glassY is stored as a magnitude because glassWindow tests -Y first;
    -- the rear lens plane itself is at Y=-0.055 in the mesh.
    -- The measured bounds and perimeter let PiP follow the moving optic.
    PVADS.RegisterOpticProfile("Base.SLDG", {
        glass = { -0.0085, 0.0085, -0.0345, -0.0175, 0.0550, true },
        glassPoly = {
            0.00846,-0.02601, 0.00818,-0.02386, 0.00735,-0.02185,
            0.00602,-0.02013, 0.00430,-0.01880, 0.00229,-0.01797,
            0.00014,-0.01769, -0.00201,-0.01797, -0.00402,-0.01880,
            -0.00574,-0.02013, -0.00707,-0.02185, -0.00790,-0.02386,
            -0.00818,-0.02601, -0.00790,-0.02816, -0.00707,-0.03017,
            -0.00574,-0.03189, -0.00402,-0.03322, -0.00201,-0.03405,
            0.00014,-0.03433, 0.00229,-0.03405, 0.00430,-0.03322,
            0.00602,-0.03189, 0.00735,-0.03017, 0.00818,-0.02816
        },
    })
    -- magnified, by the pack's scope mark
    scope("EKP_kobra_2x", 2, "dot", 50)                -- 2x by name; no mark
    scope("Elcan_M145", 3, "crossdot")                 -- x3
    scope("Leapers_UTG3", 3, "mildot")                 -- x3
    scope("1P78", 3, "eastern")                        -- x3
    scope("ACOGx4", 4, "chevron")                      -- x4 (ACOG)
    scope("Acog_ecos", 4, "chevron")                   -- x4 (ACOG)
    scope("Bravo4", 4, "chevron")                      -- x4
    scope("Compact4x", 4, "duplex")                    -- x4
    scope("HAMR", 4, "crossdot")                       -- x4
    scope("Spectre", 4, "crossdot")                    -- x4
    scope("SUSAT", 4, "post")                          -- x4
    scope("Zeiss4x25", 4, "post")                      -- x4
    scope("1PN93_4", 4, "eastern")                     -- x4
    scope("POSP", 4, "eastern")                        -- x4 (PSO-1 mark)
    scope("POSP4x24", 4, "eastern")                    -- x4 (PSO-1 mark)
    scope("Acog_TA648", 6, "chevron")                  -- x6
    scope("Eotech_vudu", 6, "crossdot")                -- x6
    scope("PistolScope", 7, "duplex")                  -- x7
    scope("PM_IILP", 20, "mildot", 200)                -- x20
    scope("Springfield_longrange_scope", 20, "duplex", 200)   -- x20
    scope("BallisticScope", 25, "mildot", 200)         -- x40 in the pack; 25x is this mod's top
    -- no mark: from the pack's vision class
    scope("Accupoint", 8, "duplex")                    -- long-range class
    scope("IRNV", 8, "duplex")                         -- long-range class
    scope("ATN_Thor", 4, "crossdot")                   -- ACOG class
    PVADS.log("GaelGunStore: weapon and optic profiles registered; SLDG glass aperture uses 24-point mesh profile")
end

-- at load when GaelGunStore's Lua came first, otherwise once everything is loaded (before any profile is resolved)
G.register()
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(G.register) end
