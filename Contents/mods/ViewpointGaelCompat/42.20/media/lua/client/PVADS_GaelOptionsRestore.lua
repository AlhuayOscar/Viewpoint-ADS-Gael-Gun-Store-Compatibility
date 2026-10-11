require "PVADS/PVADS_Options"

-- Restores and guarantees that Project Viewpoint ADS settings appear under
-- Main Options -> (Mods) even when running with Viewpoint's Java integration.
-- Also exposes Viewpoint Gael Gun Store Compatibility settings.

local ID = "ProjectViewpointADS"
local GAEL_ID = "ViewpointGaelCompat"

local optsPVADS
local optsGael
local applyTrueBallisticsOptions

local FIELD = { adsControl = "mode", speed = "speedMul", ironDist = "ironDistance", pipScopes = "pip" }

local function val(optionsObj, id, default)
    local o = optionsObj and optionsObj:getOption(id)
    if not o then return default end
    local v = o:getValue()
    if v == nil then return default end
    return v
end

local function applyPVADSOptions()
    if not optsPVADS then return end
    local s = PVADS and PVADS.Settings
    if not s then return end

    s.mode = val(optsPVADS, "adsControl", s.mode)
    s.key = val(optsPVADS, "key", s.key)
    s.speedMul = val(optsPVADS, "speed", s.speedMul)
    s.adsSens = val(optsPVADS, "adsSens", s.adsSens)
    s.scopeSens = val(optsPVADS, "scopeSens", s.scopeSens)
    s.hideCrosshair = val(optsPVADS, "hideCrosshair", s.hideCrosshair)
    s.adsSharp = val(optsPVADS, "adsSharp", s.adsSharp)
    s.thirdAds = val(optsPVADS, "thirdAds", s.thirdAds)
    s.closeClip = val(optsPVADS, "closeClip", s.closeClip)
    s.sway = val(optsPVADS, "sway", s.sway)
    s.swayAmount = val(optsPVADS, "swayAmount", s.swayAmount)
    s.cameraRecoil = val(optsPVADS, "cameraRecoil", s.cameraRecoil)
    s.recoilAmount = val(optsPVADS, "recoilAmount", s.recoilAmount)
    s.eyeBox = val(optsPVADS, "eyeBox", s.eyeBox)
    s.inertia = val(optsPVADS, "inertia", s.inertia)
    s.brightness = val(optsPVADS, "brightness", s.brightness)
    s.color = val(optsPVADS, "color", s.color)
    s.lensSize = val(optsPVADS, "lensSize", s.lensSize)
    s.ironDistance = val(optsPVADS, "ironDist", s.ironDistance)
    s.scopeZoom = val(optsPVADS, "scopeZoom", s.scopeZoom)
    s.pip = val(optsPVADS, "pipScopes", s.pip)
    s.hipSpread = val(optsPVADS, "hipSpread", s.hipSpread)
    s.pipQuality = val(optsPVADS, "pipQuality", s.pipQuality)
    s.aimPriority = val(optsPVADS, "aimPriority", s.aimPriority)
    s.presence = val(optsPVADS, "presence", s.presence)
    s.presenceStart = val(optsPVADS, "presenceStart", s.presenceStart)
    s.presenceStrength = val(optsPVADS, "presenceStrength", s.presenceStrength)
    s.presenceSmoothing = val(optsPVADS, "presenceSmoothing", s.presenceSmoothing)
    s.lowReady = val(optsPVADS, "lowReady", s.lowReady)
    s.lowReadyAmount = val(optsPVADS, "lowReadyAmount", s.lowReadyAmount)
    s.presenceDebug = val(optsPVADS, "presenceDebug", s.presenceDebug)
    s.presenceOthers = val(optsPVADS, "presenceOthers", s.presenceOthers)
    s.developer = val(optsPVADS, "developer", true)
    s.calibKey = val(optsPVADS, "calibKey", Keyboard.KEY_SEMICOLON)
    s.variableZoom = val(optsPVADS, "variableZoom", s.variableZoom)
    s.wheelZoom = val(optsPVADS, "wheelZoom", s.wheelZoom)
    s.zoomInKey = val(optsPVADS, "zoomInKey", s.zoomInKey)
    s.zoomOutKey = val(optsPVADS, "zoomOutKey", s.zoomOutKey)
    s.zeroUpKey = val(optsPVADS, "zeroUpKey", s.zeroUpKey)
    s.zeroDownKey = val(optsPVADS, "zeroDownKey", s.zeroDownKey)
    s.scopeHud = val(optsPVADS, "scopeHud", s.scopeHud)

    PVADS.developer = s.developer
    if PVADS_setSettings then
        PVADS_setSettings({
            enabled = true,
            hideCrosshair = s.hideCrosshair,
            adsSharp = s.adsSharp,
            thirdAds = s.thirdAds,
            closeClip = s.closeClip,
            sway = s.sway,
            cameraRecoil = s.cameraRecoil,
            eyeBox = s.eyeBox,
            inertia = s.inertia,
            speedMul = s.speedMul,
            adsSens = s.adsSens,
            scopeSens = s.scopeSens,
            swayAmount = s.swayAmount,
            recoilAmount = s.recoilAmount,
            lensSize = s.lensSize,
            ironDistance = s.ironDistance,
            scopeZoom = s.scopeZoom,
            pip = s.pip and true or false,
            hipSpread = s.hipSpread and true or false,
            pipQuality = 3 - (tonumber(s.pipQuality) or 2),
            presence = s.presence and true or false,
            presenceStart = (tonumber(s.presenceStart) or 8) / 100,
            presenceStrength = tonumber(s.presenceStrength) or 1.0,
            presenceSmoothing = tonumber(s.presenceSmoothing) or 1.0,
            lowReady = s.lowReady and true or false,
            lowReadyAmount = tonumber(s.lowReadyAmount) or 0.5,
            presenceDebug = (s.presenceDebug and s.developer) and true or false,
            presenceOthers = s.presenceOthers and true or false,
        })
    end
    if PVADS_setDeveloper then PVADS_setDeveloper(s.developer and true or false) end
    if PVADS_setClickAim then PVADS_setClickAim(s.mode == 4) end
end

local function buildPVADSModOptions()
    if not (PZAPI and PZAPI.ModOptions) or optsPVADS then return end
    optsPVADS = PZAPI.ModOptions:create(ID, "Project Viewpoint ADS")
    local s = PVADS and PVADS.Settings or {}

    optsPVADS:addTitle("Aim down sights")
    local m = optsPVADS:addComboBox("adsControl", "ADS control", "How sights are raised with a firearm. DayZ style: click the aim button (right mouse) to bring the sights up and keep them there, click again to lower them; hold it for ordinary hip aiming.")
    m:addItem("Aim (right mouse) raises the sights", (s.mode or 4) == 1)
    m:addItem("Hold the ADS key while aiming", (s.mode or 4) == 2)
    m:addItem("Hip fire; ADS key toggles sights (remembered)", (s.mode or 4) == 3)
    m:addItem("DayZ: click right mouse = sights, hold = hip fire", (s.mode or 4) == 4)
    optsPVADS:addKeyBind("key", "ADS key", s.key or Keyboard.KEY_V, "Used by the hold and toggle modes.")
    optsPVADS:addTickBox("aimPriority", "Aiming takes priority over menus", s.aimPriority ~= false)
    optsPVADS:addTickBox("thirdAds", "ADS from third person switches to first person", s.thirdAds ~= false)
    optsPVADS:addSlider("speed", "ADS transition speed", 0.5, 2.0, 0.05, s.speedMul or 1.0)
    optsPVADS:addSlider("adsSens", "ADS mouse sensitivity", 0.3, 1.5, 0.05, s.adsSens or 0.85)
    optsPVADS:addSlider("scopeSens", "Magnified scope sensitivity", 0.3, 2.0, 0.05, s.scopeSens or 1.0)
    optsPVADS:addTickBox("hideCrosshair", "Hide Viewpoint's crosshair while aiming down sights", s.hideCrosshair ~= false)
    optsPVADS:addTickBox("closeClip", "Stop the gun clipping open near the camera while aiming", s.closeClip == true)
    optsPVADS:addTickBox("adsSharp", "No depth-of-field blur while aiming down sights", s.adsSharp ~= false)
    optsPVADS:addSlider("ironDist", "Iron sight / red dot distance (long guns)", 0.8, 1.6, 0.05, s.ironDistance or 1.0)

    optsPVADS:addTitle("Weapon handling feel (visual)")
    optsPVADS:addTickBox("sway", "Weapon sway", s.sway ~= false)
    optsPVADS:addSlider("swayAmount", "Sway amount", 0.0, 2.0, 0.05, s.swayAmount or 1.0)
    optsPVADS:addTickBox("cameraRecoil", "Camera recoil", s.cameraRecoil ~= false, "Camera climb and weapon recoil feedback.")
    optsPVADS:addSlider("recoilAmount", "Recoil amount", 0.0, 2.0, 0.05, s.recoilAmount or 1.0, "Scales the view climb and visible gun kick.")
    optsPVADS:addTickBox("hipSpread", "Hip-fire spread", s.hipSpread ~= false)
    optsPVADS:addTickBox("inertia", "Weapon inertia when turning", s.inertia ~= false)

    optsPVADS:addTitle("Physical weapon presence")
    optsPVADS:addTickBox("presence", "Physical weapon collision", s.presence ~= false)
    optsPVADS:addTickBox("presenceOthers", "Other players' guns collide too", s.presenceOthers ~= false)
    optsPVADS:addSlider("presenceStart", "Collision start distance (cm)", 0, 20, 1, s.presenceStart or 8)
    optsPVADS:addSlider("presenceStrength", "Compressed pose strength", 0.5, 1.5, 0.05, s.presenceStrength or 1.0)
    optsPVADS:addSlider("presenceSmoothing", "Collision smoothing", 0.5, 2.0, 0.05, s.presenceSmoothing or 1.0)
    optsPVADS:addTickBox("lowReady", "Low ready when not aiming (first person)", s.lowReady == true)
    optsPVADS:addSlider("lowReadyAmount", "Low ready amount", 0.1, 1.0, 0.05, s.lowReadyAmount or 0.5)

    optsPVADS:addTitle("Optics")
    optsPVADS:addTickBox("eyeBox", "Scope eye box", s.eyeBox ~= false)
    optsPVADS:addSlider("lensSize", "Scope lens size on screen", 0.5, 1.1, 0.02, s.lensSize or 0.84)
    optsPVADS:addSlider("scopeZoom", "Scope zoom", 1.0, 2.5, 0.05, s.scopeZoom or 1.5)
    optsPVADS:addSlider("brightness", "Reticle brightness", 0.2, 1.5, 0.05, s.brightness or 1.0)
    local c = optsPVADS:addComboBox("color", "Illuminated reticle colour")
    c:addItem("Red", (s.color or 1) == 1)
    c:addItem("Green", (s.color or 1) == 2)
    c:addItem("Amber", (s.color or 1) == 3)
    c:addItem("Black", (s.color or 1) == 4)
    optsPVADS:addTickBox("pipScopes", "Picture-in-picture scopes and sights", s.pip ~= false)
    local pq = optsPVADS:addComboBox("pipQuality", "Picture-in-picture quality")
    pq:addItem("High", (s.pipQuality or 2) == 1)
    pq:addItem("Mid (default)", (s.pipQuality or 2) == 2)
    pq:addItem("Low", (s.pipQuality or 2) == 3)

    optsPVADS:addTitle("Scope zoom and zeroing")
    optsPVADS:addTickBox("variableZoom", "Variable zoom on high-power scopes", s.variableZoom ~= false)
    optsPVADS:addTickBox("wheelZoom", "Mouse wheel changes scope zoom", s.wheelZoom ~= false)
    optsPVADS:addKeyBind("zoomInKey", "Scope zoom in (key)", s.zoomInKey or 0)
    optsPVADS:addKeyBind("zoomOutKey", "Scope zoom out (key)", s.zoomOutKey or 0)
    optsPVADS:addKeyBind("zeroUpKey", "Zeroing up", s.zeroUpKey or Keyboard.KEY_PRIOR)
    optsPVADS:addKeyBind("zeroDownKey", "Zeroing down", s.zeroDownKey or Keyboard.KEY_NEXT)
    optsPVADS:addTickBox("scopeHud", "Show zoom and zero when changed", s.scopeHud ~= false)

    optsPVADS:addTitle("Developer & Calibration")
    optsPVADS:addTickBox("developer", "Developer / calibration mode", true, "Enables calibration window and debug features.")
    optsPVADS:addKeyBind("calibKey", "Open calibrator", Keyboard.KEY_SEMICOLON, "Default key: Ñ on Spanish keyboard layouts.")
    optsPVADS:addTickBox("presenceDebug", "Debug weapon collision", s.presenceDebug == true)

    optsPVADS.apply = function()
        applyPVADSOptions()
    end
end

local function buildGaelModOptions()
    if not (PZAPI and PZAPI.ModOptions) or optsGael then return end
    optsGael = PZAPI.ModOptions:create(GAEL_ID, "Viewpoint GGS ADS Patch")

    optsGael:addTitle("Calibración y Control de Miras")
    optsGael:addKeyBind("gaelCalibKey", "Abrir HUD Calibrador (Ñ por defecto)", Keyboard.KEY_SEMICOLON, "Abre el calibrador PVGADS; puedes cambiar la tecla aquí.")
    optsGael:addTickBox("forceDeveloper", "Activar herramientas de desarrollo y calibración", true, "Deja disponible el calibrador durante el desarrollo del parche.")

    optsGael:addTitle("Retroceso y Comportamiento Balístico")
    optsGael:addTickBox("shotPitchRecoil", "Retroceso vertical por disparo", true, "Simula el retroceso del cañón y la elevación al disparar.")
    optsGael:addTickBox("shotRecoilAffectsAim", "El retroceso afecta el punto de impacto", true, "Desplaza la línea de disparo junto con el movimiento del cañón.")
    optsGael:addTickBox("boltPitchMotion", "Movimiento mecánico del cerrojo", true, "Simula la oscilación al ciclar el arma de cerrojo o corredera.")
    optsGael:addTickBox("holdSway", "Balanceo al apuntar (Hold Sway)", true, "Balanceo natural afectado por fatiga, fuerza y resistencia.")
    optsGael:addTickBox("sightMotion", "Movimiento de mira al caminar", true, "Desplaza la mira suavemente según el paso y el cansancio.")
    optsGael:addTickBox("focusSearchBlur", "Desenfoque al buscar foco de mira", true, "Efecto de desenfoque de profundidad al apuntar con miras de hierro.")

    optsGael:addTitle("Diagnóstico de True Ballistics")
    optsGael:addTickBox("vtbTracerEveryShot", "Mostrar trazadora en cada proyectil", true, "Activa la trazadora visual de True Ballistics para depurar el recorrido de cada disparo.")
    optsGael:addTickBox("vtbDrawTrajectory", "Dibujar trayectoria del proyectil", true, "Activa el dibujo de trayectoria de True Ballistics mientras los proyectiles vuelan.")
    optsGael:addTickBox("vtbDrawImpacts", "Dibujar impactos y colisiones", true, "Muestra marcadores de impacto de True Ballistics.")

    local function applyGaelOptions()
        if not optsGael then return end
        SandboxVars = SandboxVars or {}
        SandboxVars.ViewpointGaelCompat = SandboxVars.ViewpointGaelCompat or {}
        local v = SandboxVars.ViewpointGaelCompat
        v.ShotPitchRecoil = val(optsGael, "shotPitchRecoil", true)
        v.ShotRecoilAffectsAim = val(optsGael, "shotRecoilAffectsAim", true)
        v.BoltPitchMotion = val(optsGael, "boltPitchMotion", true)
        v.NoReferenceHoldSway = val(optsGael, "holdSway", true)
        v.SightMotion = val(optsGael, "sightMotion", true)
        v.FocusSearchBlur = val(optsGael, "focusSearchBlur", true)
        applyTrueBallisticsOptions()
        if PVADS and PVADS.Settings then
            PVADS.Settings.developer = true
            local k = val(optsGael, "gaelCalibKey", Keyboard.KEY_SEMICOLON)
            if k and k ~= 0 then PVADS.Settings.calibKey = k end
        end
    end

    optsGael.apply = function()
        applyGaelOptions()
    end
end

applyTrueBallisticsOptions = function()
    if not optsGael then return false end
    local tracerFn = rawget(_G, "VTB_tracers")
    local debugFn = rawget(_G, "VTB_debug")
    if type(tracerFn) ~= "function" or type(debugFn) ~= "function" then return false end
    local tracerOk = pcall(tracerFn, val(optsGael, "vtbTracerEveryShot", true) and 1 or 0)
    local trajectoryOk = pcall(debugFn, "trajectories", val(optsGael, "vtbDrawTrajectory", true))
    local impactOk = pcall(debugFn, "impacts", val(optsGael, "vtbDrawImpacts", true))
    return tracerOk and trajectoryOk and impactOk
end

local function retryTrueBallisticsOptions()
    if applyTrueBallisticsOptions and applyTrueBallisticsOptions() then
        Events.OnTick.Remove(retryTrueBallisticsOptions)
    end
end

local function initOptions()
    buildPVADSModOptions()
    buildGaelModOptions()
end

Events.OnGameBoot.Add(initOptions)
Events.OnGameStart.Add(function()
    initOptions()
    if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.load then
        PZAPI.ModOptions:load()
    end
    applyPVADSOptions()
    if optsGael and optsGael.apply then
        optsGael.apply()
    end
    if not applyTrueBallisticsOptions() then Events.OnTick.Add(retryTrueBallisticsOptions) end
end)

initOptions()
