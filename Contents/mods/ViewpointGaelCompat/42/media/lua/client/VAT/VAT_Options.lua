require "VAT/VAT_Config"

--[[
Personal settings: Settings > Mods > Viewpoint - Advanced Throwables.
Controls are real key bindings here (rebindable); the primary throw uses the game's own Attack
binding, so mouse users keep their mouse button and remapped keyboards keep their key.
Gameplay values (speeds, damage, validation...) are sandbox options controlled by the server.
]]

local ID = "ViewpointAdvancedThrowables"
local opts

local function val(id, default)
    local o = opts and opts:getOption(id)
    if not o then return default end
    local v = o:getValue()
    if v == nil then return default end
    return v
end

function VAT.applyClientOptions()
    local c = VAT.Config.client
    if opts then
        c.previewMode = val("previewMode", c.previewMode)
        c.chargeIndicator = val("chargeIndicator", c.chargeIndicator)
        c.attackThrows = val("attackThrows", c.attackThrows)
        c.crouchRolls = val("crouchRolls", c.crouchRolls)
        c.autoArc = val("autoArc", c.autoArc)
        c.autoEquipNext = val("autoEquipNext", c.autoEquipNext)
        c.keyThrow = val("keyThrow", c.keyThrow)
        c.keyCancel = val("keyCancel", c.keyCancel)
        c.keyUnderhand = val("keyUnderhand", c.keyUnderhand)
        c.keyRoll = val("keyRoll", c.keyRoll)
        c.keyCook = val("keyCook", c.keyCook)
        c.debugDraw = val("debugDraw", c.debugDraw)
        c.effects = val("effects", c.effects)
        c.fireEffects = val("fireEffects", c.fireEffects)
        c.effectLights = val("effectLights", c.effectLights)
        c.effectQuality = val("effectQuality", c.effectQuality)
    end
    VAT.Config.invalidate()
    if VAT_setDebug then VAT_setDebug(c.debugDraw and true or false) end
    if VAT.FxClient and VAT.FxClient.applySettings then VAT.FxClient.applySettings() end
end

local function build()
    if not (PZAPI and PZAPI.ModOptions) or opts then return end
    opts = PZAPI.ModOptions:create(ID, "Viewpoint - Advanced Throwables")
    local c = VAT.Config.client
    opts:addTitle("Throwing")
    opts:addTickBox("attackThrows", "Attack button throws grenades and other throwables", c.attackThrows,
        "Uses the game's Attack binding while Viewpoint drives the view. Hold to charge, release to throw.")
    opts:addKeyBind("keyThrow", "Throw held item (hold to charge)", c.keyThrow,
        "Throws any throwable object in your hand, including bottles, cans, rocks and tools.")
    opts:addKeyBind("keyUnderhand", "Underhand toss (hold while releasing)", c.keyUnderhand)
    opts:addKeyBind("keyRoll", "Roll along the ground (hold while releasing)", c.keyRoll)
    opts:addTickBox("crouchRolls", "Crouching rolls the throw along the ground", c.crouchRolls)
    opts:addKeyBind("keyCancel", "Cancel a prepared throw", c.keyCancel)
    opts:addKeyBind("keyCook", "Start the fuse while holding (cookable items only)", c.keyCook)
    opts:addTickBox("autoEquipNext", "Equip the next one of the same item after a throw", c.autoEquipNext)
    opts:addTitle("Aiming")
    local p = opts:addComboBox("previewMode", "Trajectory preview while preparing",
        "Simple shows where it will land; Full adds a faint arc. The server may limit this.")
    p:addItem("Off", c.previewMode == 1)
    p:addItem("Simple", c.previewMode == 2)
    p:addItem("Full", c.previewMode == 3)
    opts:addTickBox("chargeIndicator", "Thin charge bar under the crosshair", c.chargeIndicator)
    opts:addTickBox("autoArc", "Aim assist: arc onto the point under the crosshair when in reach", c.autoArc)
    opts:addTitle("Effects")
    opts:addTickBox("effects", "3D effects for explosions, smoke grenades and flashbangs", c.effects,
        "Fireballs, sparks, debris, smoke and dust drawn inside Viewpoint's first and third person view.")
    opts:addTickBox("fireEffects", "3D flames and smoke for every fire", c.fireEffects,
        "In Viewpoint the game's own fire and smoke sprites are not shown; this draws them in 3D.")
    opts:addTickBox("effectLights", "Explosions and fires light up their surroundings", c.effectLights)
    local q = opts:addComboBox("effectQuality", "Effect detail",
        "How many particles each effect uses. Lower it if big fires or smoke clouds cost too much.")
    q:addItem("Low", c.effectQuality == 1)
    q:addItem("Normal", c.effectQuality == 2)
    q:addItem("High", c.effectQuality == 3)
    opts:addTitle("Developer")
    opts:addTickBox("debugDraw", "Debug trajectory drawing and logging", c.debugDraw,
        "Release point, camera ray, velocity, predicted and actual paths, collisions, ownership. "
            .. "On servers only when the admin allows it.")
    opts.apply = function() VAT.applyClientOptions() end
end

build()
Events.OnGameBoot.Add(build)
Events.OnGameStart.Add(function()
    if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.load then PZAPI.ModOptions:load() end
    VAT.applyClientOptions()
end)
