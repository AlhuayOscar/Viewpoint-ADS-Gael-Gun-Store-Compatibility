-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Options"

--[[
1.7.8: this mod's keys are in the game's own Options > Keybinds, in a "Project Viewpoint ADS" section.

Done the way vanilla adds its own sections (client/Foraging/ISSearchManager.lua: on OnGameBoot,
table.insert(keyBinding, { value = "[Search Mode]" }) and { value = id, key = code }). MainOptions then lists them,
saves them in keysB42.ini with the rest and registers them with getCore():addKeyBinding(name, ...); this mod reads
them with getCore():getKey(name) (Core.getKey(String)). Labels: UI_optionscreen_binding_<name> in
Translate/EN/UI.json. Ids are namespaced "PVADSGAEL2:<name>" as Better Car Physics (42.21) does.

Keys set on the old Settings > Mods page (saved in Lua/ModOptions.ini as "keybind|PVADSGAEL2|<id>|<code>")
become the defaults here, so nobody loses a key they had changed.
]]

PVADS.Keys = PVADS.Keys or {}
local K = PVADS.Keys

-- PVADS.Settings field, keybind name, default, old Settings > Mods option id
K.LIST = {
    { field = "key",         name = "PVADSGAEL2:ADS",        default = Keyboard.KEY_V,     old = "key" },
    { field = "zoomInKey",   name = "PVADSGAEL2:ZoomIn",     default = 0,                  old = "zoomInKey" },
    { field = "zoomOutKey",  name = "PVADSGAEL2:ZoomOut",    default = 0,                  old = "zoomOutKey" },
    { field = "zeroUpKey",   name = "PVADSGAEL2:ZeroUp",     default = Keyboard.KEY_PRIOR, old = "zeroUpKey" },
    { field = "zeroDownKey", name = "PVADSGAEL2:ZeroDown",   default = Keyboard.KEY_NEXT,  old = "zeroDownKey" },
    { field = "calibKey",    name = "PVADSGAEL2:Calibrator", default = Keyboard.KEY_F9,    old = "calibKey" },
    -- 1.8.7: hold to steady the sights (hold breath) once they are fully up
    { field = "steadyKey",   name = "PVADSGAEL2:Steady",     default = Keyboard.KEY_LSHIFT, old = "steadyKey" },
    -- 1.9.0: deploy / fold the held gun's bipod by hand (unbound: bipods deploy on their own when prone or rested)
    { field = "bipodKey",    name = "PVADSGAEL2:Bipod",      default = 0,                  old = "bipodKey" },
}

--- Keys changed on the old Settings > Mods page: { optionId = code }.
local function oldModOptionKeys()
    local found = {}
    local ok, reader = pcall(getFileReader, "ModOptions.ini", false)
    if not ok or not reader then return found end
    while true do
        local line = reader:readLine()
        if line == nil then break end
        for id, code in string.gmatch(line, "keybind|PVADSGAEL2|([%w_]+)|(%d+)") do
            found[id] = tonumber(code)
        end
        for id, code in string.gmatch(line, "keybind|ProjectViewpointADS|([%w_]+)|(%d+)") do
            found[id] = tonumber(code)
        end
    end
    reader:close()
    return found
end

local added = false
function K.addBindings()
    if added or type(keyBinding) ~= "table" then return end
    added = true
    local old = oldModOptionKeys()
    table.insert(keyBinding, { value = "[PVADSGAEL2]" })
    for _, k in ipairs(K.LIST) do
        local code = old[k.old]
        if code == nil then code = k.default end
        k.start = code
        table.insert(keyBinding, { value = k.name, key = code })
    end
end

--- MainOptions.loadKeys has registered our binds (it puts every bind it registers in MainOptions.keys).
local registered = false
local function isRegistered()
    if registered then return true end
    if type(MainOptions) ~= "table" or type(MainOptions.keys) ~= "table" then return false end
    for _, b in ipairs(MainOptions.keys) do
        if b.value == K.LIST[1].name then registered = true; return true end
    end
    return false
end

--- Current keys from the game's key bindings into PVADS.Settings (cheap: a lookup per key). Until the game has
--- registered them (it does when its options screen is built at start-up), the starting keys are used.
function K.refresh()
    local core = getCore and getCore()
    if not core then return end
    local s = PVADS.Settings
    local live = isRegistered()
    for _, k in ipairs(K.LIST) do
        if live then
            local ok, code = pcall(core.getKey, core, k.name)
            if ok and type(code) == "number" then s[k.field] = code end
        elseif k.start ~= nil then
            s[k.field] = k.start
        end
    end
end
PVADS.refreshKeys = K.refresh

Events.OnGameBoot.Add(K.addBindings)
Events.OnGameStart.Add(K.refresh)
