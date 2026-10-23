-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Controller"

--[[
Mod detection at game start (client):
- weapon packs in use (logged, so a console shows which calibrations apply). Calibrations are already chosen per
  gun: the profile comes from the item, and the sights are measured on the model the game actually loaded, so a
  pack that replaces vanilla models (VFE) is handled by what it loads.
- other aiming mods that also move the arms and gun after this one. Two mods posing the same arms fight each
  other and the sights end up off to the side; the player is told once, in the console and on screen.
Mod list read with getActivatedMods() / getModInfoByID() as client/ISUI/ISPauseModListUI.lua does.
]]

local D = {}
PVADS.Detect = D

D.PACKS = {
    VFExpansion1 = "Vanilla Firearms Expansion",
    VFExpansion2 = "VFE STALKER Pack",
    VFExpansion3 = "VFE Post '93",
    GunsOfMarz = "Guns of Marz",
    MarzGuns = "Guns of Marz",
}

-- mods that pose the first-person arms / gun themselves (mod id -> name shown to the player)
D.CONFLICTS = {
    ViewpointADSTest = "Viewpoint ADS Test (Native body aim)",
}

local function clean(id)
    id = tostring(id or "")
    return (string.gsub(id, "^\\+", ""))
end

function D.scan()
    local packs, conflicts = {}, {}
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return packs, conflicts end
    for i = 0, mods:size() - 1 do
        local id = clean(mods:get(i))
        if D.PACKS[id] then packs[D.PACKS[id]] = true end
        if D.CONFLICTS[id] then table.insert(conflicts, D.CONFLICTS[id] .. " [" .. id .. "]") end
    end
    return packs, conflicts
end

local function report()
    local packs, conflicts = D.scan()
    local names = {}
    for name in pairs(packs) do table.insert(names, name) end
    table.sort(names)
    PVADS.log("weapon packs detected: " .. (#names > 0 and table.concat(names, ", ") or "none (vanilla guns)"))
    D.conflicts = conflicts
    if #conflicts > 0 then
        local msg = "Another aiming mod is enabled: " .. table.concat(conflicts, ", ")
            .. ". It moves the arms and gun after Project Viewpoint ADS, so the sights will not line up. Disable one of them."
        PVADS.log("WARNING: " .. msg)
        D.warnPending = msg
    end
end

-- on-screen notice once the player exists (HaloTextHelper.addText(character, text) as client/Foraging/forageClient.lua)
local function tick()
    if not D.warnPending then Events.OnPlayerUpdate.Remove(tick) return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local msg = D.warnPending
    D.warnPending = nil
    if HaloTextHelper and HaloTextHelper.addText then
        pcall(HaloTextHelper.addText, pl, "Project Viewpoint ADS: another aiming mod is enabled (see console). Sights may not line up.")
    end
    Events.OnPlayerUpdate.Remove(tick)
end

Events.OnGameStart.Add(function()
    pcall(report)
    Events.OnPlayerUpdate.Add(tick)
end)
