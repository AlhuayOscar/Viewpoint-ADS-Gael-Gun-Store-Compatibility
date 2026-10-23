-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Weapons"

--[[
Client options. Everything here is a personal visual/control preference; nothing is server controlled because
nothing here changes gameplay for other players.

1.7.4: the options live in Viewpoint's own settings window (Viewpoint 0.1.6, key Delete) on the "Recoil & ADS"
page (declared by the Java part, see Options.java). Viewpoint saves them.
1.7.8: the keys are in the game's own Options > Keybinds ("Project Viewpoint ADS" section, PVADS_Keys.lua).
Only if that window is not available (older Viewpoint, Java part not loaded) the old Settings > Mods page is built.
]]

PVADS.Settings = {
    mode = 1,               -- 1 aim = ADS, 2 hold key, 3 toggle key
    key = Keyboard.KEY_V,
    speedMul = 1.0, adsSens = 0.85, scopeSens = 1.0,
    hideCrosshair = true, adsSharp = true, thirdAds = true, closeClip = true, sway = true, swayAmount = 1.0, cameraRecoil = true, recoilAmount = 1.0,
    eyeBox = true, inertia = true, brightness = 1.0, color = 1, lensSize = 0.84, ironDistance = 1.0, scopeZoom = 1.5, pip = true, pipQuality = 2, hipSpread = true, aimPriority = true,
    presence = true, presenceStart = 8, presenceStrength = 1.0, presenceSmoothing = 1.0, lowReady = false, lowReadyAmount = 0.5, presenceDebug = false, presenceOthers = true,
    developer = false, calibKey = Keyboard.KEY_F9,
    variableZoom = true, wheelZoom = true, zoomInKey = 0, zoomOutKey = 0,
    zeroUpKey = Keyboard.KEY_PRIOR, zeroDownKey = Keyboard.KEY_NEXT, scopeHud = true,
    steady = true, steadyZoom = 1.2, steadyKey = Keyboard.KEY_LSHIFT,   -- 1.8.7 steady aim (hold breath)
    rest = true, bipodAuto = true, bipodKey = 0,                       -- 1.9.0 weapon rest and bipods
}

PVADS.ReticleColors = {
    { r = 1.00, g = 0.12, b = 0.10 },   -- red
    { r = 0.25, g = 1.00, b = 0.30 },   -- green
    { r = 1.00, g = 0.70, b = 0.15 },   -- amber
    { r = 0.05, g = 0.05, b = 0.05 },   -- black (non-illuminated)
}

local ID = "PVADSGAEL2"
local opts
local inViewpoint = false        -- options are in Viewpoint's settings window
local vpValues = {}

-- option id (as declared) -> PVADS.Settings field
local FIELD = { adsControl = "mode", speed = "speedMul", ironDist = "ironDistance", pipScopes = "pip" }

local function val(id, default)
    local o = opts and opts:getOption(id)
    if not o then return default end
    local v = o:getValue()
    if v == nil then return default end
    return v
end

function PVADS.applySettings()
    local s = PVADS.Settings
    if PVADS.refreshKeys then PVADS.refreshKeys() end         -- 1.7.8: keys are the game's own (Options > Keybinds)
    if inViewpoint and PVADS_getOptions then
        vpValues = PVADS_getOptions({}) or vpValues
        for id, v in pairs(vpValues) do
            local f = FIELD[id] or id
            if s[f] ~= nil and type(s[f]) == type(v) then s[f] = v end
        end
    elseif opts then
        s.mode = val("adsControl", s.mode)
        s.speedMul = val("speed", s.speedMul)
        s.adsSens = val("adsSens", s.adsSens)
        s.scopeSens = val("scopeSens", s.scopeSens)
        s.hideCrosshair = val("hideCrosshair", s.hideCrosshair)
        s.adsSharp = val("adsSharp", s.adsSharp)
        s.thirdAds = val("thirdAds", s.thirdAds)
        s.closeClip = val("closeClip", s.closeClip)
        s.sway = val("sway", s.sway)
        s.swayAmount = val("swayAmount", s.swayAmount)
        s.cameraRecoil = val("cameraRecoil", s.cameraRecoil)
        s.recoilAmount = val("recoilAmount", s.recoilAmount)
        s.eyeBox = val("eyeBox", s.eyeBox)
        s.inertia = val("inertia", s.inertia)
        s.steady = val("steady", s.steady)
        s.steadyZoom = val("steadyZoom", s.steadyZoom)
        s.rest = val("rest", s.rest)
        s.bipodAuto = val("bipodAuto", s.bipodAuto)
        s.brightness = val("brightness", s.brightness)
        s.color = val("color", s.color)
        s.lensSize = val("lensSize", s.lensSize)
        s.ironDistance = val("ironDist", s.ironDistance)
        s.scopeZoom = val("scopeZoom", s.scopeZoom)
        s.pip = val("pipScopes", s.pip)          -- new id in 1.4.0: on by default, old saved "off" does not carry over
        s.hipSpread = val("hipSpread", s.hipSpread)
        s.pipQuality = val("pipQuality", s.pipQuality)
        s.aimPriority = val("aimPriority", s.aimPriority)
        s.presence = val("presence", s.presence)
        s.presenceStart = val("presenceStart", s.presenceStart)
        s.presenceStrength = val("presenceStrength", s.presenceStrength)
        s.presenceSmoothing = val("presenceSmoothing", s.presenceSmoothing)
        s.lowReady = val("lowReady", s.lowReady)
        s.lowReadyAmount = val("lowReadyAmount", s.lowReadyAmount)
        s.presenceDebug = val("presenceDebug", s.presenceDebug)
        s.presenceOthers = val("presenceOthers", s.presenceOthers)
        s.developer = val("developer", s.developer)
        s.variableZoom = val("variableZoom", s.variableZoom)
        s.wheelZoom = val("wheelZoom", s.wheelZoom)
        s.scopeHud = val("scopeHud", s.scopeHud)
    end
    PVADS.developer = s.developer
    if PVADS_setSettings then
        PVADS_setSettings({
            enabled = true, hideCrosshair = s.hideCrosshair, adsSharp = s.adsSharp, thirdAds = s.thirdAds, closeClip = s.closeClip, sway = s.sway, cameraRecoil = s.cameraRecoil,
            eyeBox = s.eyeBox, inertia = s.inertia, speedMul = s.speedMul, adsSens = s.adsSens,
            steady = s.steady and true or false, steadyZoom = tonumber(s.steadyZoom) or 1.2,
            rest = s.rest and true or false,
            scopeSens = s.scopeSens, swayAmount = s.swayAmount, recoilAmount = s.recoilAmount, lensSize = s.lensSize, ironDistance = s.ironDistance, scopeZoom = s.scopeZoom,
            pip = s.pip and true or false, hipSpread = s.hipSpread and true or false,
            pipQuality = 3 - (tonumber(s.pipQuality) or 2),   -- combo 1 High, 2 Mid, 3 Low -> Java 2, 1, 0
            presence = s.presence and true or false,
            presenceStart = (tonumber(s.presenceStart) or 8) / 100,   -- option in cm, Java in metres
            presenceStrength = tonumber(s.presenceStrength) or 1.0,
            presenceSmoothing = tonumber(s.presenceSmoothing) or 1.0,
            lowReady = s.lowReady and true or false,
            lowReadyAmount = tonumber(s.lowReadyAmount) or 0.5,
            presenceDebug = (s.presenceDebug and s.developer) and true or false,
            presenceOthers = s.presenceOthers and true or false,
        })
        PVADS_setDeveloper(s.developer and true or false)
        -- Mode 4 used an experimental click-to-lock input that did not work reliably.
        if tonumber(s.mode) == 4 or tonumber(s.mode) == nil then s.mode = 1 end
        if PVADS_setClickAim then PVADS_setClickAim(false) end
        if PVADS._loggedMode ~= s.mode then
            PVADS._loggedMode = s.mode
            local names = { "aim (right mouse) raises the sights", "hold the ADS key while aiming",
                            "ADS key toggles the sights" }
            PVADS.log("ADS control: " .. tostring(s.mode) .. " = " .. tostring(names[s.mode] or "unknown"))
        end
        if PVADS.Controller then PVADS.Controller.aimAllowed = nil end
    end
end

--- Options in Viewpoint's settings window when it can take them. final = last chance (game boot): build the
--- Settings > Mods page instead.
local function useViewpoint()
    if inViewpoint then return true end
    if PVADS.bindJava and PVADS.bindJava() and PVADS_optionsReady and PVADS_optionsReady() then
        inViewpoint = true
        PVADS.log("options: in Viewpoint's settings window (Delete) > Recoil & ADS; keys in Options > Keybinds > Project Viewpoint ADS")
    end
    return inViewpoint
end

local function build(final)
    if useViewpoint() then return end
    if not final then return end
    if not (PZAPI and PZAPI.ModOptions) or opts then return end
    opts = PZAPI.ModOptions:create(ID, "PVADSGAEL2 - ADS & Recoil")
    local s = PVADS.Settings
    opts:addTitle("Aim down sights")
    local m = opts:addComboBox("adsControl", "ADS control", "Choose how the sights are raised.")
    m:addItem("Aim (right mouse) raises the sights", s.mode == 1)
    m:addItem("Hold the ADS key while aiming", s.mode == 2)
    m:addItem("Hip fire; ADS key toggles sights (remembered)", s.mode == 3)
    opts:addTickBox("aimPriority", "Aiming takes priority over menus", s.aimPriority, "While you hold a firearm, the ADS key does not open the vehicle / animal radial menu that shares it (V), and Viewpoint Interface's interaction prompt and action menu step aside while you aim. Lower the gun or holster it to use them.")
    opts:addTickBox("thirdAds", "ADS from third person switches to first person", s.thirdAds, "In third person, raising the sights switches to first person and lowering them switches back. Hip fire stays in third person.")
    opts:addSlider("speed", "ADS transition speed", 0.5, 2.0, 0.05, s.speedMul, "Multiplies every weapon's raise time (higher = faster).")
    opts:addSlider("adsSens", "ADS mouse sensitivity", 0.3, 1.5, 0.05, s.adsSens)
    opts:addSlider("scopeSens", "Magnified scope sensitivity", 0.3, 2.0, 0.05, s.scopeSens, "1.0 keeps the same feel per degree of view at every magnification.")
    opts:addTickBox("hideCrosshair", "Hide Viewpoint's crosshair while aiming down sights", s.hideCrosshair)
    opts:addTickBox("closeClip", "Stop the gun clipping open near the camera while aiming", s.closeClip, "Moves the camera's near clip plane from 5 cm to about 1 cm while sights are up, so the receiver and stock right under your eye are drawn instead of being cut open.")
    opts:addTickBox("adsSharp", "No depth-of-field blur while aiming down sights", s.adsSharp, "Viewpoint shader packs with depth of field focus on the screen centre, which is your sights when ADS, so the world blurs. This keeps the view sharp while sights are up.")
    opts:addSlider("ironDist", "Iron sight / red dot distance (long guns)", 0.8, 1.6, 0.05, s.ironDistance, "How far in front of your eye the gun sits when aiming down sights. Higher = smaller front sight, more of the target visible and less of your hands near the camera, but past about 1.3 the arms stretch to reach. Pistols are not affected. Does not change where you hit.")
    opts:addTitle("Weapon handling feel (visual)")
    opts:addTickBox("sway", "Weapon sway", s.sway, "Breathing sway, affected by aiming skill, endurance, fatigue, panic, movement and weapon weight.")
    opts:addSlider("swayAmount", "Sway amount", 0.0, 2.0, 0.05, s.swayAmount)
    opts:addTickBox("cameraRecoil", "Camera recoil", s.cameraRecoil, "Each shot climbs the view and pushes it a little sideways. Part of it settles back, the rest stays: hold the gun down on full auto. Every weapon kicks its own way (pistols snap, rifles push, snipers and shotguns punch).")
    opts:addSlider("recoilAmount", "Recoil amount", 0.0, 2.0, 0.05, s.recoilAmount, "Scales the view climb and the visible gun kick.")
    opts:addTickBox("hipSpread", "Hip-fire spread", s.hipSpread, "Shots from the hip go somewhere inside a cone that depends on the weapon (wide for snipers and machine guns, tight for pistols), grows while moving or running and shrinks with Aiming skill. Aim down the sights to hit at range. Works with Viewpoint True Ballistics. Not added while Viewpoint's own 'Gunplay Rework (0.1.6)' setting is on: its aim ring already spreads hip fire.")
    opts:addTickBox("inertia", "Weapon inertia when turning", s.inertia)
    opts:addTickBox("steady", "Steady aim (hold breath)", s.steady, "With the sights fully up, hold the Steady aim key (Left Shift by default, in Options > Keybinds) to hold your breath: the sway almost stops for up to 5 seconds. Magnified scopes are only steadied; iron sights, red dots and holo sights also zoom in a little.")
    opts:addTickBox("rest", "Weapon rest and bipods", s.rest, "Rest the handguard on a table, counter, low wall, fence or window sill with the sights up, or go prone (Advanced Movement), and the sway settles; with a deployed bipod it all but stops and the recoil is halved.")
    opts:addTickBox("bipodAuto", "Deploy bipods automatically", s.bipodAuto, "Bipods go down by the gun pack's own action when you go prone or rest the gun, and fold when you walk off.")
    opts:addSlider("steadyZoom", "Iron sight / red dot zoom while steadying", 1.0, 1.5, 0.05, s.steadyZoom, "Iron sights, red dots, holo sights and other unmagnified sights. 1.0 = no zoom.")
    opts:addTitle("Physical weapon presence")
    opts:addTickBox("presence", "Physical weapon collision", s.presence, "Your gun occupies real space: near walls, closed doors and windows, tall furniture and vehicles it slides back and rises into a compressed ready instead of passing through, and returns exactly to your sights when there is room again. Long rifles need more room than pistols. First and third person, hip and ADS. Visual and handling only (client side); shots still leave along your aim. Untick to switch the whole system off.")
    opts:addTickBox("presenceOthers", "Other players' guns collide too", s.presenceOthers, "Other players' guns also give way at walls, doors and furniture on your screen. Worked out on your own game from what it already knows about them (no network traffic, nothing needed on the server); players who run this mod see yours the same way. Up to 12 nearest aiming players within 40 tiles.")
    opts:addSlider("presenceStart", "Collision start distance (cm)", 0, 20, 1, s.presenceStart, "How far in front of an obstacle the muzzle starts giving way.")
    opts:addSlider("presenceStrength", "Compressed pose strength", 0.5, 1.5, 0.05, s.presenceStrength, "How far the gun pulls back and rises when it meets something.")
    opts:addSlider("presenceSmoothing", "Collision smoothing", 0.5, 2.0, 0.05, s.presenceSmoothing, "Lower = snappier, higher = softer movement into and out of the compressed pose.")
    opts:addTickBox("lowReady", "Low ready when not aiming (first person)", s.lowReady, "Lowers the muzzle a little while you hold a firearm without aiming. Off by default.")
    opts:addSlider("lowReadyAmount", "Low ready amount", 0.1, 1.0, 0.05, s.lowReadyAmount)
    opts:addTitle("Optics")
    opts:addTickBox("eyeBox", "Scope eye box (lens shadow when misaligned)", s.eyeBox)
    opts:addSlider("lensSize", "Scope lens size on screen", 0.5, 1.1, 0.02, s.lensSize)
    opts:addSlider("scopeZoom", "Scope zoom", 1.0, 2.5, 0.05, s.scopeZoom, "Multiplies the zoom of 2x/4x/8x scopes. 1.0 = the scope's own number against Viewpoint's wide view; 1.5 = a 4x scope zooms 6x.")
    opts:addSlider("brightness", "Reticle brightness", 0.2, 1.5, 0.05, s.brightness)
    local c = opts:addComboBox("color", "Illuminated reticle colour")
    c:addItem("Red", s.color == 1); c:addItem("Green", s.color == 2); c:addItem("Amber", s.color == 3); c:addItem("Black", s.color == 4)
    opts:addTickBox("pipScopes", "Picture-in-picture scopes and sights", s.pip, "Scopes show their magnified view inside the scope's glass, and red dots / holo sights show the world clearly through their window with the lit reticle, while the rest of the screen, the gun and your hands stay normal. Renders the world a second time while aiming through an optic, so it costs some frame rate. Untick for the classic full-screen scope view. If it ever fails it switches itself off and the classic view is used.")
    local pq = opts:addComboBox("pipQuality", "Picture-in-picture quality", "How much work the view inside scopes and sights costs. All levels only draw the part of the world the lens shows. High: everything, every frame (rain and object outlines in the lens too). Mid: no rain particles or outlines inside the lens. Low: like Mid, but the lens picture is redrawn every other frame (can lag a little when turning fast).")
    pq:addItem("High", s.pipQuality == 1); pq:addItem("Mid (default)", s.pipQuality == 2); pq:addItem("Low", s.pipQuality == 3)
    opts:addDescription("Without picture-in-picture, magnified scopes magnify the whole first-person view behind a lens mask.")
    opts:addTitle("Scope zoom and zeroing")
    opts:addTickBox("variableZoom", "Variable zoom on high-power scopes", s.variableZoom, "Scopes of 4x and up zoom in steps: an 8x goes 2x / 4x / 8x, a 6x 1.5x / 3x / 6x, a 4x 2x / 4x. Optics registered with their own zoom levels always use them.")
    opts:addTickBox("wheelZoom", "Mouse wheel changes scope zoom", s.wheelZoom, "While looking through a variable scope: wheel up zooms in, wheel down zooms out.")
    opts:addTickBox("scopeHud", "Show zoom and zero when changed", s.scopeHud, "A small readout in the lower right corner for a moment after you change the zoom or the zero.")
    opts:addTitle("Developer")
    opts:addTickBox("developer", "Developer / calibration mode", s.developer, "Enables the calibration window, extra logging and the validator.")
    opts:addTickBox("presenceDebug", "Debug weapon collision (needs developer mode)", s.presenceDebug, "Shows the weapon's measured length, its rear, pivot and muzzle, the probe hit, the obstruction amount and the pose on screen, and logs state changes.")
    opts.apply = function() PVADS.applySettings() end
end

build(false)
Events.OnGameBoot.Add(function() build(true) end)
Events.OnGameStart.Add(function()
    if not inViewpoint and PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.load then PZAPI.ModOptions:load() end
    PVADS.applySettings()
end)

-- Viewpoint's window changes values live: re-apply when any of ours changed (checked twice a second)
local lastSig, tick = nil, 0
Events.OnTick.Add(function()
    if not inViewpoint or not PVADS_optionsSignature then return end
    tick = tick + 1
    if tick < 30 then return end
    tick = 0
    local sig = PVADS_optionsSignature()
    if sig ~= lastSig then
        local first = lastSig == nil
        lastSig = sig
        if not first then PVADS.applySettings() end
    end
end)
