-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Calibrator"

--[[
Development validator: enumerates every firearm script that is actually loaded (vanilla + any packs)
and reports what Project Viewpoint knows about it. Run it from the calibrator ("Validate") or the
debug console: PVADS.Validate(). Output goes to the console and Zomboid/Lua/PVADS_validation.txt.
]]

local RETICLES = { "dot", "crossdot", "duplex", "mildot", "post", "chevron", "eastern", "holo" }

function PVADS.Validate()
    local out, findings = {}, 0
    local function add(kind, msg) findings = findings + 1; table.insert(out, kind .. ": " .. msg) end

    if not PVADS_available or not PVADS_available() then add("FATAL", "Java part / Viewpoint not available") end

    local items = getScriptManager():getAllItems()
    local guns, known = 0, 0
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it:isRanged() then
            local sprite = it:getWeaponSprite()
            local id = it:getFullName()
            if sprite and sprite ~= "" then
                guns = guns + 1
                local g = PVADS.Generated.weapons[id]
                if not g then
                    add("Missing weapon profile", id .. " (generic fallback will be used)")
                else
                    known = known + 1
                    if g.iron == "default" then add("Needs calibration", id .. " - iron sights from family default: " .. tostring(g.note)) end
                    for _, pt in ipairs({ "front", "rear" }) do
                        local v = g[pt]
                        if v and (math.abs(v[1]) > 0.2 or math.abs(v[3]) > 0.3 or v[2] ~= v[2]) then add("Invalid transform", id .. " " .. pt) end
                    end
                    if g.opticModels then
                        for part, model in pairs(g.opticModels) do
                            if not getScriptManager():getModelScript(model) then add("Missing model", id .. " optic " .. part .. " -> " .. model) end
                        end
                    end
                end
                if not getScriptManager():getModelScript(sprite) then add("Missing model", id .. " weapon model " .. sprite) end
            end
        end
    end

    for id, o in pairs(PVADS.Generated.optics) do
        if not getScriptManager():getItem(id) then add("Unknown attachment", id .. " (not loaded)") end
        local def = PVADS.Optics[id]
        if not def then add("Missing optic profile", id .. " (kind from generator: " .. tostring(o.kind) .. ")") end
    end
    for _, r in ipairs(RETICLES) do
        if not PVADS.texture("ret_" .. r) then add("Missing texture", "ret_" .. r) end
    end
    for _, n in ipairs({ "lens_mask", "eyebox_shadow" }) do
        if not PVADS.texture(n) then add("Missing texture", n) end
    end
    for _, d in ipairs(PVADS.Registry.duplicates or {}) do add("Duplicate registration", d) end

    local pl = getSpecificPlayer(0)
    if pl and PVADS_probe then
        local probe = PVADS_probe()
        table.insert(out, "equipped: " .. probe)
        if string.find(probe, "issue=") then add("Unsupported weapon state", probe) end
    end

    table.insert(out, 1, string.format("Project Viewpoint ADS %s validation: %d firearms loaded, %d with generated profiles, %d finding(s)",
        PVADS.VERSION, guns, known, findings))
    local w = getFileWriter("PVADS_validation.txt", true, false)
    for _, l in ipairs(out) do
        print("[ProjectViewpoint] " .. l)
        if w then w:write(l .. "\r\n") end
    end
    if w then w:close() end
    return findings
end
