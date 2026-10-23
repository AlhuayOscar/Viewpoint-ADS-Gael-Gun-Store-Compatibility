require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISInventoryPaneContextMenu"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "PVADS/PVADS_Calibrator"
require "PVADS/PVADS_Locale"
require "PVADS_GaelWeaponCatalog"
require "PVADS_GaelVisualChoices"
local L = PVADS.L

local LABEL_ES = {
    ["Sight X"] = "Mira X", ["Sight Y"] = "Mira Y", ["Sight Z"] = "Mira Z",
    ["Relief"] = "Distancia ocular", ["Optic height"] = "Altura de la óptica",
    ["Lens size"] = "Tamaño del lente", ["ADS time"] = "Tiempo de ADS",
    ["PiP lens X"] = "Lente PiP X", ["PiP lens Y"] = "Lente PiP Y", ["PiP lens Z"] = "Lente PiP Z",
    ["PiP lens size"] = "Tamaño del lente PiP", ["PiP zoom"] = "Zoom PiP",
    ["Lens speed"] = "Velocidad del lente", ["Lens movement"] = "Movimiento del lente",
    ["PiP reticle X"] = "Retícula PiP X", ["PiP reticle Y"] = "Retícula PiP Y",
    ["PiP depth"] = "Profundidad PiP", ["Anchor X (m)"] = "Anclaje X (m)",
    ["Anchor Y (m)"] = "Anclaje Y (m)", ["Anchor Z (m)"] = "Anclaje Z (m)",
    ["Glass crop size"] = "Tamaño del recorte",
    ["Crop frame X"] = "Marco de recorte X",
    ["Crop frame Y"] = "Marco de recorte Y",
    ["Reticle roll"] = "Rotación de la retícula",
    ["ADS FOV"] = "FOV al apuntar", ["Pitch"] = "Pitch", ["Yaw"] = "Yaw", ["Roll"] = "Roll",
}
local function fieldLabel(field) return L(field[2], LABEL_ES[field[2]] or field[2]) end
local function realTimeDotLabel()
    return L(PVADS.GaelRealTimeDot and "RealTimeDot: ON" or "RealTimeDot: OFF",
        PVADS.GaelRealTimeDot and "Punto en tiempo real: ACTIVADO" or "Punto en tiempo real: DESACTIVADO")
end

-- Companion to the stock calibrator. Both windows write to the same user profile.
PVADS.GaelRealTimeDot = true
local Cal = PVADS.Calibrator
local FIELDS = {
    {"adjX", "Sight X", 0.0002}, {"adjY", "Sight Y", 0.0005},
    {"adjZ", "Sight Z", 0.0002}, {"adjPitch", "Pitch", 0.025},
    {"adjYaw", "Yaw", 0.025}, {"adjRoll", "Roll", 0.1},
    {"relief", "Relief", 0.001}, {"fovMul", "ADS FOV", 0.005},
    {"opticHeight", "Optic height", 0.0002}, {"lensScale", "Lens size", 0.01, 1},
    {"adsTime", "ADS time", 0.005},
    {"pipX", "PiP lens X", 0.005}, {"pipY", "PiP lens Y", 0.005},
    {"pipZ", "PiP lens Z", 0.002}, {"pipScale", "PiP lens size", 0.005, 1},
    {"pipZoom", "PiP zoom", 0.01, 1}, {"pipSpeed", "Lens speed", 0.1, 14, 0.5, 120}, {"pipMove", "Lens movement", 1, 0, 0, 100}, {"pipRetX", "PiP reticle X", 0.005},
    {"pipRetY", "PiP reticle Y", 0.005}, {"pipDepth", "PiP depth", 0.002},
    {"pipAnchorX", "Anchor X (m)", 0.001},
    {"pipAnchorY", "Anchor Y (m)", 0.001},
    {"pipAnchorZ", "Anchor Z (m)", 0.001},
    {"pipAnchorScale", "Glass crop size", 0.01, 1},
    {"pipCropX", "Crop frame X", 0.01, 0},
    {"pipCropY", "Crop frame Y", 0.01, 0},
}
-- The range selector widens only spatial placement and physical sizing controls.
-- Angles, FOV, ADS timing and zoom keep their original fine calibration span.
local WIDE_RANGE_FIELDS = {
    adjX = true, adjY = true, adjZ = true, relief = true, opticHeight = true,
    lensScale = true, pipX = true, pipY = true, pipZ = true, pipScale = true,
    pipRetX = true, pipRetY = true, pipDepth = true,
    pipAnchorX = true, pipAnchorY = true, pipAnchorZ = true, pipAnchorScale = true, pipCropX = true, pipCropY = true,
}
local PAGE_OF_FIELD = {
    adjX = 1, adjY = 1, adjZ = 1,
    adjPitch = 2, adjYaw = 2, adjRoll = 2, relief = 2, fovMul = 2,
    opticHeight = 2, lensScale = 2, adsTime = 2,
    pipX = 3, pipY = 3, pipZ = 3, pipScale = 3, pipZoom = 3,
    pipRetX = 3, pipRetY = 3, pipDepth = 3,
    pipSpeed = 4, pipMove = 4, pipAnchorX = 4, pipAnchorY = 4, pipAnchorZ = 4, pipAnchorScale = 4, pipCropX = 4, pipCropY = 4,
}
local PAGES = {
    { title = "1 - Posición del arma", titleEN = "1 - Weapon position", tab = "1 Arma", tabEN = "1 Weapon" },
    { title = "2 - Orientación y ajustes de mira", titleEN = "2 - Sight angles and settings", tab = "2 Alineación", tabEN = "2 Alignment" },
    { title = "3 - PiP y retícula", titleEN = "3 - PiP and reticle", tab = "3 PiP / Mira", tabEN = "3 PiP / Sight" },
    { title = "4 - Vidrio: anclaje y movimiento", titleEN = "4 - Glass anchor and movement", tab = "4 Vidrio", tabEN = "4 Glass" },
    { title = "5 - Posibles desalineadas", titleEN = "5 - Possible not aligned", tab = "5 Revisar", tabEN = "5 Check" },
}
local PAGE_FILE = "PVADS_GaelCalibratorPage.txt"
local function loadPagePreference()
    if not getFileReader then return 3 end
    local ok, reader = pcall(getFileReader, PAGE_FILE, false)
    if not ok or not reader then return 3 end
    local line = reader:readLine()
    reader:close()
    local value = tonumber(line and string.match(line, "page=(%d+)"))
    return math.max(1, math.min(#PAGES, math.floor(value or 3)))
end
local function savePagePreference(page)
    if not getFileWriter then return end
    local ok, writer = pcall(getFileWriter, PAGE_FILE, true, false)
    if not ok or not writer then return end
    writer:write("page=" .. tostring(page) .. "\r\n")
    writer:close()
end
PVADS.GaelCalibratorPage = PVADS.GaelCalibratorPage or loadPagePreference()
-- Copy every saved optic profile from one weapon to compatible weapons.
local RANGES = { 1, 10, 50, 200 }
local WEAPONS = PVADS_GaelWeaponCatalog or {}
local function profileDisplayName(fullType)
    if not fullType or fullType == "" then return L("No optic", "Sin mira") end
    local ok, item = pcall(function() return ScriptManager.instance:getItem(fullType) end)
    if ok and item and item.getDisplayName then
        local good, name = pcall(item.getDisplayName, item)
        if good and name and name ~= "" then return tostring(name) end
    end
    return tostring(fullType):match("[^%.]+$") or tostring(fullType)
end

local function detectPossibleMisalignment()
    local candidates, weaponNames = {}, {}
    for _, entry in ipairs(WEAPONS) do weaponNames[entry[2]] = entry[3] end
    for key, values in pairs(PVADS.User or {}) do
        if type(key) == "string" and type(values) == "table" and key ~= "__GaelGlobalOffsets__|" then
            local weaponId, opticId = string.match(key, "^([^|]+)|([^|]*)$")
            if weaponId and opticId and opticId ~= "" then
                local reasons, explicitGeometry, zeroGeometry = {}, 0, 0
                local function countZero(field)
                    local n = tonumber(values[field])
                    if n ~= nil then
                        explicitGeometry = explicitGeometry + 1
                        if math.abs(n) < 0.000001 then zeroGeometry = zeroGeometry + 1 end
                    end
                    return n
                end
                local sx, sy, sz = countZero("adjX"), countZero("adjY"), countZero("adjZ")
                local ax, ay, az = countZero("pipAnchorX"), countZero("pipAnchorY"), countZero("pipAnchorZ")
                local px, py, pz = countZero("pipX"), countZero("pipY"), countZero("pipZ")
                if explicitGeometry >= 6 and zeroGeometry >= 5 then
                    reasons[#reasons + 1] = L("many saved position values are zero", "muchos valores de posición guardados están en cero")
                end
                if sx and sy and sz and math.sqrt(sx*sx + sy*sy + sz*sz) > 0.20 then
                    reasons[#reasons + 1] = L("large sight offset", "desplazamiento grande de la mira")
                end
                if ax and ay and az and math.sqrt(ax*ax + ay*ay + az*az) > 0.50 then
                    reasons[#reasons + 1] = L("large glass anchor offset", "desplazamiento grande del anclaje del vidrio")
                end
                local pipScale = tonumber(values.pipScale)
                local anchorScale = tonumber(values.pipAnchorScale)
                if (pipScale and (pipScale < 0.15 or pipScale > 6))
                    or (anchorScale and (anchorScale < 0.15 or anchorScale > 6)) then
                    reasons[#reasons + 1] = L("unusual lens or crop scale", "tamaño de lente o recorte inusual")
                end
                local optic = PVADS.Optics and PVADS.Optics[opticId]
                local mode = tostring(values.mode or (optic and optic.mode) or ""):lower()
                local hasPipData = values.pipScale ~= nil or values.pipX ~= nil or values.pipY ~= nil
                    or values.pipZ ~= nil or values.pipAnchorX ~= nil or values.pipAnchorY ~= nil
                    or values.pipAnchorZ ~= nil
                if (mode == "scope" or mode == "scopeg36" or mode == "scopereddotalt") and not hasPipData then
                    reasons[#reasons + 1] = L("scope profile has no saved glass/ PiP values", "el perfil telescópico no tiene valores guardados de vidrio/PiP")
                end
                if #reasons > 0 then
                    local weaponName = weaponNames[weaponId] or profileDisplayName(weaponId)
                    local opticName = profileDisplayName(opticId)
                    candidates[#candidates + 1] = {
                        key = key, weaponId = weaponId, opticId = opticId,
                        label = weaponName .. "  |  " .. opticName .. "  —  " .. table.concat(reasons, "; "),
                        tooltip = table.concat(reasons, "\n"),
                    }
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
    return candidates
end
local PREVIEW_SCOPE_ITEMS
local PREVIEW_MOUNT_ITEMS
local RETICLES = {
    {"Auto (optic default)", "auto"}, {"None", "none"},
    {"Dot", "dot"}, {"Holo circle", "holo"},
    {"OKP-7 arrow + bars", "okp7"}, {"OKP-7 ring + dot", "okp7_ring"},
    {"OKP-7 double rings", "okp7_rings"},
    {"Kobra T (solid)", "kobra_open"}, {"Kobra T (LED dots)", "kobra_dotted"},
    {"Kobra dot + chevron", "kobra_combo"}, {"Kobra chevron", "kobra_chevron"},
    {"Chevron", "chevron"}, {"Cross + dot", "crossdot"},
    {"Duplex", "duplex"}, {"Mil-dot", "mildot"},
    {"Post", "post"}, {"Eastern / PSO", "eastern"},
}
local RETICLE_ES = {
    ["Auto (optic default)"] = "Auto (predeterminado de la mira)", ["None"] = "Ninguna",
    ["Dot"] = "Punto", ["Holo circle"] = "Círculo holográfico",
    ["OKP-7 arrow + bars"] = "OKP-7: flecha y barras", ["OKP-7 ring + dot"] = "OKP-7: anillo y punto",
    ["OKP-7 double rings"] = "OKP-7: anillos dobles", ["Kobra T (solid)"] = "Kobra T (sólida)",
    ["Kobra T (LED dots)"] = "Kobra T (puntos LED)", ["Kobra dot + chevron"] = "Kobra: punto y chevrón",
    ["Kobra chevron"] = "Kobra: chevrón", ["Chevron"] = "Chevrón", ["Cross + dot"] = "Cruz y punto",
    ["Duplex"] = "Dúplex", ["Mil-dot"] = "Mil-dot", ["Post"] = "Poste", ["Eastern / PSO"] = "Oriental / PSO",
}
local MODES = {
    {"Auto (optic default)", "auto"}, {"Iron", "iron"},
    {"Reflex", "reflex"}, {"Scope / PiP", "scope"},
    {"Scope G36 (ADS)", "scopeg36"},
    {"ScopeRedDotALT (ADS)", "scopereddotalt"},
}
local MODE_ES = {
    ["Auto (optic default)"] = "Auto (predeterminado de la mira)", ["Iron"] = "Mira abierta",
    ["Reflex"] = "Réflex", ["Scope / PiP"] = "Telescópica / PiP",
    ["Scope G36 (ADS)"] = "Telescópica G36 (ADS)", ["ScopeRedDotALT (ADS)"] = "ScopeRedDotALT (ADS)",
}
local function visualChoiceLabel(options, spanishLabels, value)
    for _, option in ipairs(options) do
        if option[2] == value then return L(option[1], spanishLabels[option[1]]) end
    end
    return tostring(value or "")
end

local function findOwned(container, itemId)
    if not container then return nil end
    local items = container:getItems()
    if not items then return nil end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == itemId then return item end
        if instanceof(item, "InventoryContainer") then
            local found = findOwned(item:getInventory(), itemId)
            if found then return found end
        end
    end
    return nil
end

local function previewPartDefinitions()
    if PREVIEW_SCOPE_ITEMS then return PREVIEW_SCOPE_ITEMS, PREVIEW_MOUNT_ITEMS end
    PREVIEW_SCOPE_ITEMS, PREVIEW_MOUNT_ITEMS = {}, {}
    local ok, all = pcall(getAllItems)
    if not ok or not all then return PREVIEW_SCOPE_ITEMS, PREVIEW_MOUNT_ITEMS end
    for i = 0, all:size() - 1 do
        local scriptItem = all:get(i)
        local valid, category, fullType, displayName, hidden, obsolete = pcall(function()
            return scriptItem:getDisplayCategory(), scriptItem:getFullName(),
                scriptItem:getDisplayName(), scriptItem:isHidden(), scriptItem:getObsolete()
        end)
        if valid and category == "WeaponPart" and fullType and not hidden and not obsolete then
            local part = instanceItem(fullType)
            if part then
                local partType = tostring(part:getPartType() or "")
                local entry = { id = fullType, name = displayName or fullType, partType = partType }
                if partType == "Scope" then
                    PREVIEW_SCOPE_ITEMS[#PREVIEW_SCOPE_ITEMS + 1] = entry
                elseif string.find(string.lower(partType), "mount", 1, true)
                    or string.find(string.lower(partType), "rail", 1, true) then
                    PREVIEW_MOUNT_ITEMS[#PREVIEW_MOUNT_ITEMS + 1] = entry
                end
            end
        end
    end
    table.sort(PREVIEW_SCOPE_ITEMS, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    table.sort(PREVIEW_MOUNT_ITEMS, function(a, b) return a.id < b.id end)
    return PREVIEW_SCOPE_ITEMS, PREVIEW_MOUNT_ITEMS
end

local function ensureInventoryPart(player, fullType)
    local item = findOwned(player:getInventory(), fullType)
    if item then return item end
    if not ScriptManager.instance:getItem(fullType) then return nil end
    return player:getInventory():AddItem(fullType)
end

local function replaceWeaponPart(player, weapon, fullType, partType)
    if not player or not weapon or not fullType then return false end
    local currentPart = weapon:getWeaponPart(partType)
    if currentPart and currentPart:getFullType() == fullType then return true end
    if currentPart then
        weapon:detachWeaponPart(player, currentPart)
        player:getInventory():AddItem(currentPart)
    end
    local part = ensureInventoryPart(player, fullType)
    if not part then return false end
    local attached = pcall(function() weapon:attachWeaponPart(player, part) end)
    local installed = weapon:getWeaponPart(partType)
    if not attached or not installed or installed:getFullType() ~= fullType then
        player:getInventory():Remove(part)
        return false
    end
    player:getInventory():Remove(part)
    if syncHandWeaponFields then pcall(syncHandWeaponFields, player, weapon) end
    if player.resetEquippedHandsModels then pcall(player.resetEquippedHandsModels, player) end
    if player.resetModelNextFrame then pcall(player.resetModelNextFrame, player) end
    return true
end

local function selected()
    local pl = getSpecificPlayer(0)
    local weapon = PVADS.Controller.weapon(pl)
    return weapon and PVADS.userKey(weapon) or nil
end

local function hasOpticProfile(key)
    local opticId = key and string.match(key, "^[^|]+|([^|]+)$")
    return opticId ~= nil and opticId ~= ""
end

local function pip2DBackupEnabled(key, profile)
    if profile and profile.pip2DBackup ~= nil then
        return (tonumber(profile.pip2DBackup) or 0) > 0.5
    end
    return hasOpticProfile(key)
end

local function selectedWeaponIsAutomatic()
    local pl = getSpecificPlayer(0)
    local weapon = PVADS.Controller.weapon(pl)
    if not weapon then return false end
    local fireMode = weapon.getFireMode and weapon:getFireMode()
    return fireMode and string.lower(tostring(fireMode)) == "auto"
        or (fireMode == nil and weapon.isAutomatic and weapon:isAutomatic()) or false
end

local function recoilReverseEnabled(values)
    local setting = values and tonumber(values.recoilPitchReverse)
    if setting ~= nil then return setting == 1 end
    return selectedWeaponIsAutomatic()
end

-- Keep explicit resets distinguishable from profiles that went missing in
-- memory, so the guarded writer can preserve the latter without undoing Reset.
if PVADSCalibWindow and PVADSCalibWindow.onReset and not PVADS.gaelStockResetWrapped then
    PVADS.gaelStockResetWrapped = true
    local stockOnReset = PVADSCalibWindow.onReset
    PVADSCalibWindow.onReset = function(self, ...)
        local key = selected()
        local result = stockOnReset(self, ...)
        if key and PVADS.User[key] == nil then
            PVADS.GaelDeletedProfileKeys = PVADS.GaelDeletedProfileKeys or {}
            PVADS.GaelDeletedProfileKeys[key] = true
        end
        return result
    end
end

local function current(field, global)
    if global then return PVADS.GaelGlobalValue(field[1]) end
    local p = PVADS.Controller.profile
    local n = p and p[field[1]]
    if p and p.userWeapon and p.userWeapon[field[1]] ~= nil then
        n = p.userWeapon[field[1]]
    end
    local value = n == nil and (field[4] or 0) or n
    return PVADS.GaelGlobalOnlyAvailable() and value
        or value - PVADS.GaelEffectiveGlobalValue(p, field[1])
end

local function clampField(field, amount, global)
    if field[1] == "pipSpeed" then
        local low, high = global and -13.5 or (field[5] or 0.5), global and 106 or (field[6] or 120)
        return math.max(low, math.min(high, tonumber(amount) or (field[4] or 14)))
    elseif field[1] == "pipMove" then
        return math.max(-100, math.min(100, tonumber(amount) or 0))
    elseif field[1] == "pipAnchorScale" then
        return math.max(0.05, math.min(8, tonumber(amount) or 1))
    elseif field[1] == "pipCropX" or field[1] == "pipCropY" then
        return math.max(-2, math.min(2, tonumber(amount) or 0))
    elseif field[1] == "lensScale" or field[1] == "pipScale" then
        return math.max(0.001, math.min(10, tonumber(amount) or (field[4] or 1)))
    end
    return amount
end

local function apply(field, amount, global)
    local key = global and PVADS.GaelGlobalKey or selected()
    if not key then return false end
    amount = clampField(field, amount, global)
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    PVADS.User[key][field[1]] = amount
    PVADS.Controller.refresh(true)
    return true, amount
end

local function markerScale()
    local settings = PVADS.User and PVADS.User[PVADS.GaelGlobalKey]
    local value = settings and tonumber(settings.markerScale) or 1
    return math.max(0, math.min(3, value))
end

local function shotProjectionVersion(aim)
    if not aim or not aim.shotMirrorVersion then return 0 end
    local ok, version = pcall(aim.shotMirrorVersion)
    return ok and (tonumber(version) or 0) or 0
end

local function loadedShotMirror(aim)
    return shotProjectionVersion(aim) >= 1
end

local function pushMarkerScale()
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    if loadedShotMirror(aim) and aim.setShotSeparationScale then
        pcall(aim.setShotSeparationScale, markerScale())
    end
end

PVADSGaelSliderWindow = ISCollapsableWindow:derive("PVADSGaelSliderWindow")

function PVADSGaelSliderWindow:new(x, y)
    local o = ISCollapsableWindow.new(self, x, y, 610, 520)
    o.title = L("Project Viewpoint - slider calibrator", "Project Viewpoint - calibrador de perfiles")
    o.resizable = false
    o.rangeLevel = 3
    o.page = PVADS.GaelCalibratorPage or 3
    o.editGlobal = false
    o.globalDirty = false
    o.rows = {}
    return o
end

function PVADSGaelSliderWindow:rangeFor(row, centre)
    row.centre = centre
    local rangeMultiplier = WIDE_RANGE_FIELDS[row.field[1]] and RANGES[self.rangeLevel] or 1
    local span = row.field[3] * 200 * rangeMultiplier
    local minimum = centre - span
    local maximum = centre + span
    if row.field[1] == "pipAnchorScale" then
        minimum = math.max(0.05, minimum)
        maximum = math.min(8, maximum)
    elseif row.field[1] == "pipCropX" or row.field[1] == "pipCropY" then
        minimum = math.max(-2, minimum)
        maximum = math.min(2, maximum)
    elseif row.field[1] == "lensScale" or row.field[1] == "pipScale" or row.field[1] == "pipZoom" then
        minimum = math.max(0.001, minimum)
        if row.field[1] ~= "pipZoom" then maximum = math.min(10, maximum) end
    elseif row.field[1] == "pipSpeed" then
        local low, high = self.editGlobal and -13.5 or (row.field[5] or 0.5), self.editGlobal and 106 or (row.field[6] or 120)
        minimum = math.max(low, minimum)
        maximum = math.min(high, maximum)
    elseif row.field[1] == "pipMove" then
        minimum = math.max(-100, minimum)
        maximum = math.min(100, maximum)
    end
    row.slider:setValues(minimum, maximum, row.field[3], row.field[3], true)
    row.slider:setCurrentValue(centre, true)
end

function PVADSGaelSliderWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:titleBarHeight() + 7
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7

    self.availableButton = ISButton:new(8, y, 220, bh, L("Only available: NO", "Solo disponibles: NO"), self,
        PVADSGaelSliderWindow.onAvailable)
    self.availableButton:initialise(); self:addChild(self.availableButton)
    self.availableButton:setVisible(false)
    self.rangeButton = ISButton:new(122, y, 112, bh, L("Pos range x50", "Rango pos. x50"), self,
        PVADSGaelSliderWindow.onRange)
    self.rangeButton:initialise(); self:addChild(self.rangeButton)
    self.localButton = ISButton:new(306, y, 143, bh, L("[Edit Local]", "[Modificar local]"), self, PVADSGaelSliderWindow.onLocal)
    self.localButton:initialise(); self:addChild(self.localButton)
    self.globalButton = ISButton:new(454, y, 143, bh, L("Edit Global", "Modificar global"), self, PVADSGaelSliderWindow.onGlobal)
    self.globalButton:initialise(); self:addChild(self.globalButton)
    self.scopeY = y + 3
    y = y + bh + 8
    local prev = ISButton:new(82, y, 30, bh, "<", self, PVADSGaelSliderWindow.onPrevWeapon)
    prev:initialise(); self:addChild(prev)
    self.weaponCombo = ISComboBox:new(116, y, 446, bh, self, PVADSGaelSliderWindow.onWeaponChosen)
    self.weaponCombo:initialise(); self.weaponCombo:instantiate()
    self.weaponCombo:setEditable(true)
    for _, weapon in ipairs(WEAPONS) do
        self.weaponCombo:addOptionWithData(string.format("#%d %s [%s]", weapon[1], weapon[3], weapon[2]), weapon[2])
    end
    self:addChild(self.weaponCombo)
    local next = ISButton:new(566, y, 30, bh, ">", self, PVADSGaelSliderWindow.onNextWeapon)
    next:initialise(); self:addChild(next)
    self.weaponY = y + 3
    y = y + bh + 8
    self.attachmentY = y
    self.attachmentPrevButton = ISButton:new(120, y, 30, bh, "<", self, PVADSGaelSliderWindow.onPrevAttachment)
    self.attachmentPrevButton:initialise(); self:addChild(self.attachmentPrevButton)
    self.attachmentNextButton = ISButton:new(566, y, 30, bh, ">", self, PVADSGaelSliderWindow.onNextAttachment)
    self.attachmentNextButton:initialise(); self:addChild(self.attachmentNextButton)
    y = y + bh + 7
    self.pageTabs = {}
    local tabX, tabGap = 8, 6
    local tabWidth = math.floor((self.width - 16 - (#PAGES - 1) * tabGap) / #PAGES)
    for page = 1, #PAGES do
        local tab = ISButton:new(tabX + (page - 1) * (tabWidth + tabGap), y, tabWidth, bh,
            L(PAGES[page].tabEN, PAGES[page].tab), self, PVADSGaelSliderWindow["onPage" .. page])
        tab:initialise(); self:addChild(tab)
        self.pageTabs[page] = tab
    end
    self.pageTitleY = y + bh + 5
    y = y + 2 * bh + 23
    self.choiceY = y + 3
    self.reticleCombo = ISComboBox:new(75, y, 220, bh, self, PVADSGaelSliderWindow.onReticleChosen)
    self.reticleCombo:initialise(); self.reticleCombo:instantiate()
    for _, option in ipairs(RETICLES) do
        self.reticleCombo:addOptionWithData(L(option[1], RETICLE_ES[option[1]]), option[2])
    end
    self:addChild(self.reticleCombo)
    self.modeCombo = ISComboBox:new(375, y, 220, bh, self, PVADSGaelSliderWindow.onModeChosen)
    self.modeCombo:initialise(); self.modeCombo:instantiate()
    for _, option in ipairs(MODES) do
        self.modeCombo:addOptionWithData(L(option[1], MODE_ES[option[1]]), option[2])
    end
    self:addChild(self.modeCombo)
    self.recoilPitchReverseButton = ISButton:new(8, y, 220, bh,
        L("Reverse recoil Pitch/Yaw?: NO", "¿Invertir Pitch/Yaw del retroceso?: NO"), self, PVADSGaelSliderWindow.onRecoilPitchReverse)
    self.recoilPitchReverseButton:initialise(); self:addChild(self.recoilPitchReverseButton)
    self.rowsY = y + bh + 8
    self.pageRowCount = { 0, 0, 0, 0 }
    for i, field in ipairs(FIELDS) do
        local page = PAGE_OF_FIELD[field[1]] or 1
        self.pageRowCount[page] = self.pageRowCount[page] + 1
        local rowY = self.rowsY + (self.pageRowCount[page] - 1) * (bh + 3)
        local entry = ISTextEntryBox:new(string.format("%.5f", current(field, self.editGlobal)), 117, rowY, 83, bh)
        entry.font = UIFont.Small
        entry:initialise(); entry:instantiate()
        entry.pvRow = i; entry.pvOwner = self
        entry.onCommandEntered = function(box) box.pvOwner:applyTyped(box) end
        entry.onLostFocus = function(box) box.pvOwner:applyTyped(box) end
        self:addChild(entry)
        local slider = ISSliderPanel:new(210, rowY, 388, bh, self, PVADSGaelSliderWindow.onSlide)
        slider:initialise(); slider:instantiate()
        slider:setDoButtons(false)
        slider.pvRow = i
        self:addChild(slider)
        local row = { field = field, entry = entry, slider = slider, y = rowY, page = page }
        self.rows[i] = row
        self:rangeFor(row, current(field, self.editGlobal))
    end
    local function button(x, label, callback, width)
        local b = ISButton:new(x, 0, width or 92, bh, label, self, callback)
        b:initialise(); self:addChild(b)
        return b
    end
    local centerButton = button(8, L("Center", "Centrar"), PVADSGaelSliderWindow.onCenter)
    self.holdButton = button(106, L("Hold ADS", "Mantener ADS"), PVADSGaelSliderWindow.onHold)
    local resetButton = button(204, L("Reset", "Restablecer"), PVADSGaelSliderWindow.onReset)
    local copyButton = button(302, L("Copy", "Copiar"), PVADSGaelSliderWindow.onCopy)
    self.saveButton = button(400, L("Save", "Guardar"), PVADSGaelSliderWindow.onSave)
    self.centerCropButton = button(498, L("Center in circle", "Centrar en círculo"), PVADSGaelSliderWindow.onCenterCrop, 100)
    local probeButton = button(8, L("Probe", "Analizar"), PVADSGaelSliderWindow.onProbe)
    local validateButton = button(106, L("Validate", "Validar"), PVADSGaelSliderWindow.onValidate)
    self.realTimeDotButton = button(204, realTimeDotLabel(), PVADSGaelSliderWindow.onRealTimeDot, 140)
    self.copyLensButton = button(350, L("Copy profiles", "Copiar perfiles"), PVADSGaelSliderWindow.onCopyLens, 96)
    self.glassAnchorButton = button(350, L("Anchor: OFF", "Anclaje: NO"), PVADSGaelSliderWindow.onUseGlassAnchor, 96)
    self.pipAltButton = button(450, "PiP ALT", PVADSGaelSliderWindow.onPipAlt, 76)
    self.fixedWeaponButton = button(450, L("Fixed: OFF", "Fijo: NO"), PVADSGaelSliderWindow.onFixedWeapon, 76)
    self.pip2DBackupButton = button(350, L("Reactivate PiP 2D Backup", "Reactivar respaldo PiP 2D"),
        PVADSGaelSliderWindow.onPip2DBackup, 178)
    local closeButton = button(530, L("Close", "Cerrar"), PVADSGaelSliderWindow.close, 76)
    self.closeButton = closeButton
    self.scanButton = button(8, L("Scan profiles", "Buscar perfiles"), PVADSGaelSliderWindow.onScanProfiles, 132)
    self.scanList = ISScrollingListBox:new(8, 0, self.width - 16, 280)
    self.scanList:initialise(); self.scanList:instantiate()
    self.scanList.itemheight = bh + 8
    self.scanList:setOnMouseDownFunction(self, PVADSGaelSliderWindow.onDismissScanItem)
    self:addChild(self.scanList)
    self.scanButton:setVisible(false); self.scanList:setVisible(false)
    self.footerRows = {
        { centerButton, self.holdButton, resetButton, copyButton, self.saveButton, self.centerCropButton },
        { probeButton, validateButton, self.realTimeDotButton, self.copyLensButton, self.pipAltButton, self.fixedWeaponButton, closeButton },
        { self.pip2DBackupButton },
    }
    self:addMarkerScaleControl()
    self:layoutPage()
end

function PVADSGaelSliderWindow:keepOnScreen()
    local core = getCore and getCore()
    if not core then return end
    local margin = 10
    local maxX = math.max(margin, core:getScreenWidth() - self:getWidth() - margin)
    local maxY = math.max(margin, core:getScreenHeight() - self:getHeight() - margin)
    local x = math.max(margin, math.min(maxX, self:getX()))
    local y = math.max(margin, math.min(maxY, self:getY()))
    if x ~= self:getX() then self:setX(x) end
    if y ~= self:getY() then self:setY(y) end
end

function PVADSGaelSliderWindow:layoutPage()
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7
    local gap = bh + 3
    local rowIndex = 0
    for _, row in ipairs(self.rows or {}) do
        local visible = row.page == self.page
        row.entry:setVisible(visible)
        row.slider:setVisible(visible)
        if visible then
            rowIndex = rowIndex + 1
            row.y = self.rowsY + (rowIndex - 1) * gap
            row.entry:setY(row.y)
            row.slider:setY(row.y)
        end
    end
    if self.reticleCombo then self.reticleCombo:setVisible(self.page == 3) end
    if self.modeCombo then self.modeCombo:setVisible(self.page == 3) end
    if self.recoilPitchReverseButton then self.recoilPitchReverseButton:setVisible(self.page == 2) end
    if self.copyLensButton then self.copyLensButton:setVisible(self.page ~= 3 and self.page ~= 4) end
    if self.glassAnchorButton then self.glassAnchorButton:setVisible(self.page == 4 and not self.editGlobal) end
    if self.centerCropButton then self.centerCropButton:setVisible(self.page == 4 and not self.editGlobal) end
    if self.fixedWeaponButton then self.fixedWeaponButton:setVisible(self.page == 4 and not self.editGlobal) end
    if self.pipAltButton then self.pipAltButton:setVisible(self.page ~= 4) end
    if self.pip2DBackupButton then self.pip2DBackupButton:setVisible(self.page == 3 and not self.editGlobal) end
    if self.scanButton then self.scanButton:setVisible(self.page == 5) end
    if self.scanList then self.scanList:setVisible(self.page == 5) end
    if self.page == 5 then
        for _, buttons in ipairs(self.footerRows or {}) do
            for _, button in ipairs(buttons) do button:setVisible(button == self.closeButton) end
        end
        if self.markerScaleSlider then self.markerScaleSlider:setVisible(false) end
        local scanY = self.pageTitleY + 36
        self.scanButton:setY(scanY)
        self.scanList:setY(scanY + bh + 5)
        self.scanList:setHeight(250)
        self.closeButton:setVisible(true)
        self.closeButton:setY(scanY + bh + 261)
        self.markerScaleY = self.closeButton:getY()
        self.infoY = self.closeButton:getY() + bh + 4
        self:setHeight(self.infoY + 35)
        for page, tab in ipairs(self.pageTabs or {}) do
            local pageTab = L(PAGES[page].tabEN, PAGES[page].tab)
            tab:setTitle((page == self.page and "[" or "") .. pageTab .. (page == self.page and "]" or ""))
        end
        self:keepOnScreen()
        return
    else
        if self.markerScaleSlider then self.markerScaleSlider:setVisible(true) end
        for _, buttons in ipairs(self.footerRows or {}) do
            for _, button in ipairs(buttons) do button:setVisible(true) end
        end
        if self.copyLensButton then self.copyLensButton:setVisible(self.page ~= 3 and self.page ~= 4) end
        if self.glassAnchorButton then self.glassAnchorButton:setVisible(self.page == 4 and not self.editGlobal) end
        if self.centerCropButton then self.centerCropButton:setVisible(self.page == 4 and not self.editGlobal) end
        if self.fixedWeaponButton then self.fixedWeaponButton:setVisible(self.page == 4 and not self.editGlobal) end
        if self.pipAltButton then self.pipAltButton:setVisible(self.page ~= 4) end
        if self.pip2DBackupButton then self.pip2DBackupButton:setVisible(self.page == 3 and not self.editGlobal) end
    end
    self:updateGlassAnchorButton()
    self:updateFixedWeaponButton()
    for page, tab in ipairs(self.pageTabs or {}) do
        local pageTab = L(PAGES[page].tabEN, PAGES[page].tab)
        tab:setTitle((page == self.page and "[" or "") .. pageTab .. (page == self.page and "]" or ""))
    end
    local footerY = self.rowsY + rowIndex * gap + 6
    for line, buttons in ipairs(self.footerRows or {}) do
        for _, b in ipairs(buttons) do b:setY(footerY + (line - 1) * (bh + 4)) end
    end
    local footerLines = self.page == 3 and 3 or 2
    self.markerScaleY = footerY + footerLines * (bh + 4) + 3
    if self.markerScaleSlider then self.markerScaleSlider:setY(self.markerScaleY - 3) end
    self.infoY = self.markerScaleY + bh + 8
    self:setHeight(self.infoY + 42)
    self:keepOnScreen()
end

function PVADSGaelSliderWindow:setPage(page)
    page = math.max(1, math.min(#PAGES, math.floor(tonumber(page) or 1)))
    self.page = page
    PVADS.GaelCalibratorPage = page
    savePagePreference(page)
    self:layoutPage()
    self:onCenter()
end

function PVADSGaelSliderWindow:onPage1() self:setPage(1) end
function PVADSGaelSliderWindow:onPage2() self:setPage(2) end
function PVADSGaelSliderWindow:onPage3() self:setPage(3) end
function PVADSGaelSliderWindow:onPage4() self:setPage(4) end
function PVADSGaelSliderWindow:onPage5() self:setPage(5) end

function PVADSGaelSliderWindow:onScanProfiles()
    self.scanList:clear()
    local candidates = detectPossibleMisalignment()
    for _, candidate in ipairs(candidates) do
        self.scanList:addItem(candidate.label, candidate, candidate.tooltip)
    end
    self.scanStatus = #candidates == 0
        and L("No likely issues found in saved optic profiles.", "No se encontraron señales probables en los perfiles guardados.")
        or string.format(L("%d possible profile(s). Click an entry to dismiss it for this scan.", "%d perfil(es) posible(s). Haz clic en una fila para quitarla de esta búsqueda."), #candidates)
end

function PVADSGaelSliderWindow:onDismissScanItem(candidate)
    if not candidate or not self.scanList then return end
    self.scanList:removeItemByIndex(self.scanList.selected)
    local count = #self.scanList.items
    self.scanStatus = string.format(L("%d remaining. Dismissed only until the next scan.", "%d restantes. Se quita solo hasta la próxima búsqueda."), count)
end

function PVADSGaelSliderWindow:addMarkerScaleControl()
    if self.markerScaleSlider then return end
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7
    local slider = ISSliderPanel:new(165, 0, 388, bh,
        self, PVADSGaelSliderWindow.onMarkerScale)
    slider:initialise(); slider:instantiate()
    slider:setDoButtons(false)
    slider:setValues(0, 3, 0.05, 0.05, true)
    slider:setCurrentValue(markerScale(), true)
    self:addChild(slider)
    self.markerScaleSlider = slider
end

function PVADSGaelSliderWindow:syncRecoilPitchReverse()
    local key = selected()
    local values = key and PVADS.User[key]
    local reverse = recoilReverseEnabled(values)
    if self.recoilPitchReverseButton then
        self.recoilPitchReverseButton:setTitle(L("Reverse recoil Pitch/Yaw?: ", "¿Invertir Pitch/Yaw del retroceso?: ") .. (reverse and L("YES", "SÍ") or L("NO", "NO")))
        self.recoilPitchReverseButton:setVisible(self.page == 2 and not self.editGlobal)
    end
end

function PVADSGaelSliderWindow:onRecoilPitchReverse()
    if self.editGlobal then return end
    local key = selected()
    if not key then
        self.message = L("Equip a weapon to change its recoil profile", "Equipa un arma para cambiar su perfil de retroceso")
        return
    end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    local enabled = not recoilReverseEnabled(PVADS.User[key])
    PVADS.User[key].recoilPitchReverse = enabled and 1 or 0
    PVADS.Controller.refresh(true)
    self:syncRecoilPitchReverse()
    self.message = enabled
        and L("Recoil Pitch/Yaw reversed for this profile (press Save)", "Pitch/Yaw del retroceso invertidos para este perfil (pulsa Guardar)")
        or L("Recoil Pitch/Yaw normal for this profile (press Save)", "Pitch/Yaw del retroceso normales para este perfil (pulsa Guardar)")
    self.saveButton:setTitle(L("Save", "Guardar"))
end

function PVADSGaelSliderWindow:onMarkerScale(value)
    value = math.floor(math.max(0, math.min(3, tonumber(value) or 1)) * 20 + 0.5) / 20
    local key = PVADS.GaelGlobalKey
    PVADS.User[key] = PVADS.User[key] or {}
    PVADS.User[key].markerScale = value
    self.markerDirty = true
    self.message = string.format(L("Global marker spacing x%.2f (Save to keep)", "Separación global x%.2f (Guardar para conservar)"), value)
    pushMarkerScale()
end

function PVADSGaelSliderWindow:equipSelected()
    if not PVADS.Settings.developer then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local itemId = self.weaponCombo:getSelectedData()
    if not itemId then return end
    local item = findOwned(pl:getInventory(), itemId)
    if not item then
        if not ScriptManager.instance:getItem(itemId) then
            self.message = L("Item unavailable: ", "Objeto no disponible: ") .. itemId
            return
        end
        item = pl:getInventory():AddItem(itemId)
    end
    if not item or not instanceof(item, "HandWeapon") or not item:isAimedFirearm() then
        self.message = L("ADS firearm unavailable: ", "Arma de fuego ADS no disponible: ") .. itemId
        return
    end
    PVADS.Controller.forceADS = true
    if pl:getPrimaryHandItem() ~= item then
        ISInventoryPaneContextMenu.equipWeapon(item, true, item:isTwoHandWeapon(), pl:getPlayerNum())
        self.message = L("Equipping ", "Equipando ") .. itemId .. L("; hold Ctrl to aim", "; mantén Ctrl para apuntar")
    else
        PVADS.Controller.refresh(true)
        self.message = L("Ready: ", "Listo: ") .. itemId .. L("; hold Ctrl to aim", "; mantén Ctrl para apuntar")
    end
    return item
end

function PVADSGaelSliderWindow:onWeaponChosen()
    local weapon = self:equipSelected()
    self:syncAttachmentOptions(weapon)
    self:updateGlassAnchorButton()
    self:updateFixedWeaponButton()
end

function PVADSGaelSliderWindow:stepWeapon(delta)
    local count = #WEAPONS
    if count == 0 then return end
    local index = self.weaponCombo:getSelected()
    if not index or index < 1 then index = 1 end
    self.weaponCombo:setSelected((index - 1 + delta + count) % count + 1)
    self:onWeaponChosen()
end

function PVADSGaelSliderWindow:onPrevWeapon() self:stepWeapon(-1) end
function PVADSGaelSliderWindow:onNextWeapon() self:stepWeapon(1) end

function PVADSGaelSliderWindow:syncAttachmentOptions(weapon)
    local itemId = self.weaponCombo and self.weaponCombo:getSelectedData()
    if not itemId then
        self.attachments, self.attachmentIndex = {}, 1
        return
    end
    if self.attachmentWeaponId == itemId and self.attachments then return end
    self.attachmentWeaponId = itemId
    self.attachments = { { id = false, name = L("No sight", "Sin mira") } }
    self.attachmentIndex = 1
    local player = getSpecificPlayer(0)
    weapon = weapon or (player and findOwned(player:getInventory(), itemId))
    if not player or not weapon or not weapon.getWeaponPart then return end

    local scopes, mounts = previewPartDefinitions()
    local inventory = player:getInventory()
    local screwdriver = findOwned(inventory, "Base.Screwdriver")
    local temporaryScrewdriver = not screwdriver
    if temporaryScrewdriver then screwdriver = inventory:AddItem("Base.Screwdriver") end
    local seen = {}
    for _, optic in ipairs(scopes) do
        if optic.id ~= itemId then
            local testWeapon = instanceItem(itemId)
            local part = instanceItem(optic.id)
            local compatible = testWeapon and part and pcall(function()
                return part:canAttach(player, testWeapon)
            end)
            if compatible then
                local ok, canAttach = pcall(function() return part:canAttach(player, testWeapon) end)
                compatible = ok and canAttach
            end
            local mountId
            if not compatible and testWeapon and part then
                for _, mount in ipairs(mounts) do
                    local testMount = instanceItem(mount.id)
                    if testMount then
                        local okMount, canMount = pcall(function() return testMount:canAttach(player, testWeapon) end)
                        if okMount and canMount then
                            local attachedMount = pcall(function() testWeapon:attachWeaponPart(player, testMount) end)
                            if attachedMount then
                                local okOptic, canAttach = pcall(function() return part:canAttach(player, testWeapon) end)
                                if okOptic and canAttach then mountId = mount.id; break end
                            end
                        end
                    end
                end
            end
            if (compatible or mountId) and not seen[optic.id] then
                seen[optic.id] = true
                self.attachments[#self.attachments + 1] = {
                    id = optic.id, name = optic.name, mountId = mountId,
                }
            end
        end
    end
    if temporaryScrewdriver and screwdriver then inventory:Remove(screwdriver) end
    table.sort(self.attachments, function(a, b)
        if a.id == false then return true end
        if b.id == false then return false end
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    local currentPart = weapon:getWeaponPart("Scope")
    if currentPart then
        for i, attachment in ipairs(self.attachments) do
            if attachment.id == currentPart:getFullType() then self.attachmentIndex = i; break end
        end
    end
end

function PVADSGaelSliderWindow:applyAttachmentSelection()
    local options = self.attachments or {}
    local attachment = options[self.attachmentIndex]
    local itemId = self.weaponCombo and self.weaponCombo:getSelectedData()
    local player = getSpecificPlayer(0)
    local held = player and PVADS.Controller.weapon(player)
    -- Never change a copy in the inventory: Controller.refresh() resolves the
    -- firearm in hand, so that would change profile values without changing its optic.
    local weapon = held and itemId and held:getFullType() == itemId and held or nil
    if not attachment or not player or not weapon then
        self.message = L("Wait for the selected weapon to equip before changing its sight", "Espera a que se equipe el arma seleccionada antes de cambiar su mira")
        return false
    end
    if attachment.mountId then
        local mount = instanceItem(attachment.mountId)
        local partType = mount and mount:getPartType()
        if partType and not replaceWeaponPart(player, weapon, attachment.mountId, partType) then
            self.message = L("Could not install mount: ", "No se pudo instalar la montura: ") .. attachment.mountId
            return false
        end
    end
    if attachment.id then
        if not replaceWeaponPart(player, weapon, attachment.id, "Scope") then
            self.message = L("Could not install sight: ", "No se pudo instalar la mira: ") .. attachment.id
            return false
        end
    else
        local currentPart = weapon:getWeaponPart("Scope")
        if currentPart then
            weapon:detachWeaponPart(player, currentPart)
            player:getInventory():AddItem(currentPart)
            if syncHandWeaponFields then pcall(syncHandWeaponFields, player, weapon) end
            if player.resetEquippedHandsModels then pcall(player.resetEquippedHandsModels, player) end
            if player.resetModelNextFrame then pcall(player.resetModelNextFrame, player) end
        end
    end
    local installed = weapon:getWeaponPart("Scope")
    if attachment.id and (not installed or installed:getFullType() ~= attachment.id) then
        self.message = L("The game did not install the sight: ", "El juego no instaló la mira: ") .. attachment.id
        return false
    elseif not attachment.id and installed then
        self.message = L("Could not remove the current sight", "No se pudo retirar la mira actual")
        return false
    end
    PVADS.Controller.refresh(true)
    self.message = attachment.id and (L("Test sight: ", "Mira de prueba: ") .. attachment.id)
        or L("Sight removed for iron-sight testing", "Mira retirada para probar las miras abiertas")
    return true
end

function PVADSGaelSliderWindow:stepAttachment(delta)
    local options = self.attachments or {}
    if #options == 0 then return end
    local previousIndex = self.attachmentIndex
    self.attachmentIndex = (self.attachmentIndex - 1 + delta + #options) % #options + 1
    if not self:applyAttachmentSelection() then self.attachmentIndex = previousIndex end
end

function PVADSGaelSliderWindow:onPrevAttachment() self:stepAttachment(-1) end
function PVADSGaelSliderWindow:onNextAttachment() self:stepAttachment(1) end

function PVADSGaelSliderWindow:setEditGlobal(global)
    if self.editGlobal == global then return end
    self.editGlobal = global
    self.localButton:setTitle(global and L("Edit Local", "Modificar local") or "[" .. L("Edit Local", "Modificar local") .. "]")
    self.globalButton:setTitle(global and "[" .. L("Edit Global", "Modificar global") .. "]" or L("Edit Global", "Modificar global"))
    self.saveButton:setTitle((global or self.globalDirty) and L("Confirm?", "¿Confirmar?") or L("Save", "Guardar"))
    self.availableButton:setVisible(global)
    self.availableButton:setTitle(PVADS.GaelGlobalOnlyAvailable()
        and "[" .. L("Available only: YES", "Solo disponibles: SÍ") .. "]" or L("Available only: NO", "Solo disponibles: NO"))
    self.reticleCombo:setVisible(not global)
    self.modeCombo:setVisible(not global)
    if self.pipAltButton then self.pipAltButton:setVisible(not global) end
    self.attachmentPrevButton:setVisible(not global)
    self.attachmentNextButton:setVisible(not global)
    if self.glassAnchorButton then self.glassAnchorButton:setVisible(self.page == 4 and not global) end
    self:updateGlassAnchorButton()
    self:syncRecoilPitchReverse()
    self:onCenter()
    self.message = global and L("Global: 0 = unchanged; values are ADDED to all weapons and sights", "Global: 0 = sin cambios; los valores se SUMAN a todas las armas y miras")
        or L("Local: editing only the equipped weapon and sight", "Local: editando solo el arma y la mira equipadas")
end

function PVADSGaelSliderWindow:onLocal() self:setEditGlobal(false) end
function PVADSGaelSliderWindow:onGlobal() self:setEditGlobal(true) end

function PVADSGaelSliderWindow:onAvailable()
    local key = PVADS.GaelGlobalKey
    PVADS.User[key] = PVADS.User[key] or {}
    PVADS.User[key].onlyAvailable = PVADS.GaelGlobalOnlyAvailable() and nil or 1
    self.globalDirty = true
    self.availableButton:setTitle(PVADS.GaelGlobalOnlyAvailable()
        and "[" .. L("Available only: YES", "Solo disponibles: SÍ") .. "]" or L("Available only: NO", "Solo disponibles: NO"))
    PVADS.Controller.refresh(true)
    self.message = PVADS.GaelGlobalOnlyAvailable()
        and L("Available only: skips every explicitly calibrated value, including 0", "Solo disponibles: omite cada valor calibrado explícitamente, incluso 0")
        or L("Global: applies to all, including calibrated profiles", "Global: se aplica a todos, incluidos los perfiles calibrados")
end

function PVADSGaelSliderWindow:onRealTimeDot()
    PVADS.GaelRealTimeDot = not PVADS.GaelRealTimeDot
    if self.realTimeDotButton then
        self.realTimeDotButton:setTitle(realTimeDotLabel())
    end
    self.message = PVADS.GaelRealTimeDot
        and L("RealTimeDot: ON - Recoil and sway active during calibration", "RealTimeDot: ON - retroceso y balanceo activos durante la calibración")
        or L("RealTimeDot: OFF - Static view for calibration", "RealTimeDot: OFF - vista estática para calibrar")
    PVADS.Controller.refresh(true)
end

function PVADSGaelSliderWindow:syncChoices()
    local key = selected()
    local profile = key and PVADS.User[key]
    self.updatingChoices = true
    self.reticleCombo:setSelectedData(profile and profile.reticle or "auto")
    self.modeCombo:setSelectedData(profile and profile.mode or "auto")
    self.updatingChoices = false
end

function PVADSGaelSliderWindow:applyChoice(field, choice)
    if self.updatingChoices or self.editGlobal then return end
    local key = selected()
    if not key then return end
    if field == "mode" and choice == "scopeg36" and not string.match(key, "^Base%.G36|") then
        self.message = L("Scope G36 (ADS) only applies to the G36", "Scope G36 (ADS) solo se aplica al G36")
        self:syncChoices()
        return
    end
    local allowed = field == "mode" and PVADS.GaelVisualModes or PVADS.GaelVisualReticles
    if choice ~= "auto" and not allowed[choice] then return end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    if choice == "auto" then
        PVADS.User[key][field] = nil
    else
        PVADS.User[key][field] = choice
    end
    PVADS.Controller.refresh(true)
    if field == "mode" and choice == "scopereddotalt" then
        local saved = PVADS.saveUserProfiles()
        self.message = saved and L("ScopeRedDotALT saved for this weapon and sight", "ScopeRedDotALT guardado para esta arma y mira")
            or L("ScopeRedDotALT applied; could not save", "ScopeRedDotALT aplicado; no se pudo guardar")
    else
        local options, spanishLabels = field == "mode" and MODES or RETICLES, field == "mode" and MODE_ES or RETICLE_ES
        self.message = L(field == "mode" and "ADS mode" or "Reticle", field == "mode" and "Modo ADS" or "Retícula")
            .. " = " .. visualChoiceLabel(options, spanishLabels, choice)
    end
end

function PVADSGaelSliderWindow:onReticleChosen()
    self:applyChoice("reticle", self.reticleCombo:getSelectedData())
end

function PVADSGaelSliderWindow:onModeChosen()
    self:applyChoice("mode", self.modeCombo:getSelectedData())
end

-- Fallback for integrated scopes that have no measurable eyepiece: draw a
-- collimated dot on the weapon's projected sight axis instead of the PiP pass.
function PVADSGaelSliderWindow:onPipAlt()
    if self.editGlobal then return end
    local key = selected()
    if not key then
        self.message = L("Equip a weapon with a scope to apply PiP ALT", "Equipa un arma con mira telescópica para aplicar PiP ALT")
        return
    end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    local profile = PVADS.User[key]
    profile.mode = "reflex"
    profile.reticle = "none"
    profile.pipAlt = 1
    profile.pipZ = -0.08000
    profile.pipRetX = 0
    profile.pipRetY = 0
    PVADS.Controller.refresh(true)
    self:syncChoices()
    print("[PVADSGAEL2][PiP ALT] applied key=" .. tostring(key) .. " overlayDot=red mode=reflex")
    self.message = L("PiP ALT: custom red dot on the weapon axis; press Save", "PiP ALT: punto rojo propio sobre el eje del arma; pulsa Guardar")
    if self.saveButton then self.saveButton:setTitle(L("Save", "Guardar")) end
end

function PVADSGaelSliderWindow:onPip2DBackup()
    if self.editGlobal then return end
    local key = selected()
    if not key then
        self.message = L("Select a weapon with an optic first", "Primero selecciona un arma con mira")
        return
    end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    local profile = PVADS.User[key]
    local enabled = not pip2DBackupEnabled(key, profile)
    profile.pip2DBackup = enabled and 1 or 0
    if enabled then
        -- Restore the screen-space PiP path instead of the experimental glass anchor.
        profile.pipFixed = 0
        profile.pipAnchorClip = 0
    end
    PVADS.Controller.refresh(true)
    self:updatePip2DBackupButton()
    self.message = enabled
        and L("PiP 2D backup enabled; press Save to keep it", "Respaldo PiP 2D activado; pulsa Guardar para conservarlo")
        or L("PiP 2D backup disabled; press Save to keep it", "Respaldo PiP 2D desactivado; pulsa Guardar para conservarlo")
    if self.saveButton then self.saveButton:setTitle(L("Save", "Guardar")) end
end

function PVADSGaelSliderWindow:updatePip2DBackupButton()
    if not self.pip2DBackupButton then return end
    local key = selected()
    local profile = key and PVADS.User[key]
    local enabled = pip2DBackupEnabled(key, profile)
    self.pip2DBackupButton:setTitle(enabled
        and L("PiP 2D Backup: ON", "Respaldo PiP 2D: SÍ")
        or L("Reactivate PiP 2D Backup", "Reactivar respaldo PiP 2D"))
end

function PVADSGaelSliderWindow:onSlide(amount, slider)
    local row = self.rows[slider.pvRow]
    if not row then return end
    local appliedOK, applied = apply(row.field, amount, self.editGlobal)
    if appliedOK then
        if self.editGlobal then
            self.globalDirty = true
            self.saveButton:setTitle(L("Confirm?", "¿Confirmar?"))
        end
        row.entry:setText(string.format("%.5f", applied))
        self.message = (self.editGlobal and L("Global +/- ", "Global +/- ") or L("Local ", "Local "))
            .. fieldLabel(row.field) .. " = " .. string.format("%.5f", applied)
    end
end

function PVADSGaelSliderWindow:applyTyped(box)
    local row = self.rows[box.pvRow]
    local amount = tonumber(box:getText())
    if not amount then
        box:setText(string.format("%.5f", current(row.field, self.editGlobal)))
        self.message = L("Enter a number", "Introduce un número")
        return
    end
    amount = clampField(row.field, amount, self.editGlobal)
    if math.abs(amount - current(row.field, self.editGlobal)) > 0.0000001 then
        local appliedOK, applied = apply(row.field, amount, self.editGlobal)
        if appliedOK then
            if self.editGlobal then
                self.globalDirty = true
                self.saveButton:setTitle(L("Confirm?", "¿Confirmar?"))
            end
            box:setText(string.format("%.5f", applied))
            self:rangeFor(row, applied)
        end
    end
end

function PVADSGaelSliderWindow:onSightArrowKey(key, stepMultiplier)
    if not self:isVisible() or self.isCollapsed then return end
    for _, row in ipairs(self.rows) do
        if row.entry:isFocused() then return end
    end

    local row, direction
    if key == Keyboard.KEY_LEFT then
        row, direction = self.rows[1], -1 -- Sight X: left decreases.
    elseif key == Keyboard.KEY_RIGHT then
        row, direction = self.rows[1], 1 -- Sight X: right increases.
    elseif key == Keyboard.KEY_UP then
        row, direction = self.rows[3], -1 -- Sight Z: up decreases.
    elseif key == Keyboard.KEY_DOWN then
        row, direction = self.rows[3], 1 -- Sight Z: down increases.
    else
        return
    end

    if not row then return end
    stepMultiplier = math.max(1, math.min(8, tonumber(stepMultiplier) or 1))
    local value = clampField(row.field, current(row.field, self.editGlobal) + direction * row.field[3] * stepMultiplier, self.editGlobal)
    if apply(row.field, value, self.editGlobal) then
        self:rangeFor(row, value)
        row.slider:setCurrentValue(value, true)
        row.entry:setText(string.format("%.5f", value))
        if self.editGlobal then
            self.globalDirty = true
            self.saveButton:setTitle(L("Confirm?", "¿Confirmar?"))
        end
        self.message = (self.editGlobal and L("Global +/- ", "Global +/- ") or L("Local ", "Local "))
            .. fieldLabel(row.field) .. " = " .. string.format("%.5f", value)
    end
end

function PVADSGaelSliderWindow:onRange()
    self.rangeLevel = self.rangeLevel % #RANGES + 1
    self.rangeButton:setTitle(L("Pos range x", "Rango pos. x") .. RANGES[self.rangeLevel])
    self:onCenter()
end

function PVADSGaelSliderWindow:onCenter()
    for _, row in ipairs(self.rows) do
        local value = current(row.field, self.editGlobal)
        if self.editGlobal then
            self:rangeFor(row, 0)
            if value < row.slider.minValue or value > row.slider.maxValue then
                self:rangeFor(row, value)
            else
                row.slider:setCurrentValue(value, true)
            end
        else
            self:rangeFor(row, value)
        end
    end
end

-- Recover the projected glass to the generated optic-mount anchor, then
-- center the crop frame. The existing Center button only recenters ranges.
function PVADSGaelSliderWindow:onCenterCrop()
    if self.editGlobal then return end
    local key = selected()
    if not key then return end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    -- Removing the local offsets lets ResolveProfile restore its generated
    -- mount reference (or the profile's zero defaults) instead of preserving
    -- an anchor that may have moved the glass off screen.
    PVADS.User[key].pipAnchorX = nil
    PVADS.User[key].pipAnchorY = nil
    PVADS.User[key].pipAnchorZ = nil
    PVADS.User[key].pipCropX = 0
    PVADS.User[key].pipCropY = 0
    PVADS.Controller.refresh(true)
    self:onCenter()
    self.message = L("Glass returned to the optic mount and crop frame centered; press Save to keep it", "Vidrio devuelto al montaje de la mira y marco centrado; pulsa Guardar para conservarlo")
end

function PVADSGaelSliderWindow:onHold()
    PVADS.Controller.forceADS = not PVADS.Controller.forceADS
    self.holdButton:setTitle(PVADS.Controller.forceADS and L("Release", "Soltar") or L("Hold ADS", "Mantener ADS"))
    if Cal.window and Cal.window.btnHold then
        Cal.window.btnHold:setTitle(PVADS.Controller.forceADS and L("Release", "Soltar") or L("Hold ADS", "Mantener ADS"))
    end
end

function PVADSGaelSliderWindow:onUseGlassAnchor()
    local key = selected()
    if not key then return end
    PVADS.User[key] = PVADS.User[key] or {}
    local enabled = tonumber(PVADS.User[key].pipAnchorClip) or 0
    PVADS.User[key].pipAnchorClip = enabled > 0.5 and 0 or 1
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    PVADS.Controller.refresh(true)
    self:updateGlassAnchorButton()
    self.message = PVADS.User[key].pipAnchorClip > 0.5
        and L("Glass crop now follows the calibrated anchor", "El recorte del vidrio ahora sigue el anclaje calibrado")
        or L("Automatic glass crop restored", "Se restableció el recorte automático del vidrio")
end

function PVADSGaelSliderWindow:updateGlassAnchorButton()
    if not self.glassAnchorButton then return end
    local key = selected()
    local profile = key and PVADS.User and PVADS.User[key]
    local enabled = profile and (tonumber(profile.pipAnchorClip) or 0) > 0.5
    self.glassAnchorButton:setTitle(enabled
        and L("Anchor: ON", "Anclaje: SÍ")
        or L("Anchor: OFF", "Anclaje: NO"))
end

function PVADSGaelSliderWindow:onFixedWeapon()
    if self.editGlobal then return end
    local key = selected()
    if not key then
        self.message = L("Select a weapon profile first", "Selecciona primero un perfil de arma")
        return
    end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    local enabled = (tonumber(PVADS.User[key].pipFixed) or 0) <= 0.5
    -- For GaelGunStore's M4 + x2Scope, Fixed also needs to place and size the
    -- projected glass at the model's Scope attachment. The old saved anchor
    -- could leave the small PiP circle floating beside the physical lens.
    if enabled and key == "Base.M4|Base.x2Scope" then
        PVADS.User[key].pipAnchorClip = 1
        PVADS.User[key].pipAnchorX = 0.0000
        PVADS.User[key].pipAnchorY = -0.2828 -- Scope Y - muzzle Y
        PVADS.User[key].pipAnchorZ = 0.0172 -- Scope Z - muzzle Z
        PVADS.User[key].pipAnchorScale = 4.0000
    end
    PVADS.User[key].pipFixed = enabled and 1 or 0
    PVADS.Controller.refresh(true)
    self:updateFixedWeaponButton()
    self.message = enabled
        and (key == "Base.M4|Base.x2Scope"
            and L("Glass snapped to the M4 scope mount; adjust if needed, then Save", "Vidrio colocado en el montaje de la mira M4; ajusta si hace falta y pulsa Guardar")
            or L("Glass follows the weapon directly; press Save to keep it", "El vidrio sigue directamente al arma; pulsa Guardar para conservarlo"))
        or L("Normal glass movement restored; press Save to keep it", "Se restauró el movimiento normal del vidrio; pulsa Guardar para conservarlo")
    if self.saveButton then self.saveButton:setTitle(L("Save", "Guardar")) end
end

function PVADSGaelSliderWindow:updateFixedWeaponButton()
    if not self.fixedWeaponButton then return end
    local key = selected()
    local profile = key and PVADS.User and PVADS.User[key]
    local enabled = profile and (tonumber(profile.pipFixed) or 0) > 0.5
    self.fixedWeaponButton:setTitle(enabled
        and L("Fixed: ON", "Fijo: SÍ")
        or L("Fixed: OFF", "Fijo: NO"))
end

function PVADSGaelSliderWindow:onReset()
    local key = self.editGlobal and PVADS.GaelGlobalKey or selected()
    if not key then return end
    local savedScale = self.editGlobal and markerScale() or nil
    PVADS.User[key] = nil
    PVADS.GaelDeletedProfileKeys = PVADS.GaelDeletedProfileKeys or {}
    PVADS.GaelDeletedProfileKeys[key] = true
    if savedScale then PVADS.User[key] = { markerScale = savedScale } end
    if self.editGlobal then self.globalDirty = true end
    PVADS.Controller.refresh(true)
    self:onCenter()
    self:syncChoices()
    self.message = L("Reset ", "Restablecido: ") .. key
end

function PVADSGaelSliderWindow:onCopy()
    if self.editGlobal then
        self.message = L("Global offsets are saved with Confirm?; Copy is local only", "Los valores globales se guardan con ¿Confirmar?; Copiar solo afecta al perfil local")
        return
    end
    local snippet = Cal.snippet()
    Clipboard.setClipboard(snippet)
    self.message = L("Copied current profile", "Perfil actual copiado")
end

local function canOpticFitWeapon(player, weaponId, opticId, mounts)
    local testWeapon = instanceItem(weaponId)
    local optic = instanceItem(opticId)
    if not testWeapon or not optic then return false end
    local ok, canAttach = pcall(function() return optic:canAttach(player, testWeapon) end)
    if ok and canAttach then return true end

    -- Mounts are tested on temporary script items only; the real gun need not have one installed.
    for _, mountDef in ipairs(mounts or {}) do
        local mount = instanceItem(mountDef.id)
        local mountedWeapon = instanceItem(weaponId)
        if mount and mountedWeapon then
            local mountOK, mountAllowed = pcall(function() return mount:canAttach(player, mountedWeapon) end)
            if mountOK and mountAllowed then
                local attachOK = pcall(function() mountedWeapon:attachWeaponPart(player, mount) end)
                if attachOK then
                    local opticOK, opticAllowed = pcall(function() return optic:canAttach(player, mountedWeapon) end)
                    if opticOK and opticAllowed then return true end
                end
            end
        end
    end
    return false
end

local function copyProfileTable(source)
    local out = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then out[key] = copyProfileTable(value)
        else out[key] = value end
    end
    return out
end

function PVADSGaelSliderWindow:onCopyLens()
    local sourceKey = selected()
    local profile = PVADS.Controller and PVADS.Controller.profile
    if not sourceKey or not profile then
        self.message = L("Equip the weapon you want to use as the source", "Equipa el arma que quieras usar como origen")
        return
    end
    if self.editGlobal then
        self.message = L("Switch to the weapon profile; copying uses individual profiles, not Global", "Cambia al perfil del arma; la copia usa perfiles individuales, no el modo global")
        return
    end
    local player = getSpecificPlayer(0)
    if not player then self.message = L("Player unavailable", "Jugador no disponible"); return end

    local sourceWeaponId = string.match(sourceKey, "^([^|]*)|")
    if not sourceWeaponId then
        self.message = L("Could not identify the source weapon", "No se pudo identificar el arma de origen")
        return
    end

    -- Snapshot every saved optic profile for this weapon. An empty optic suffix is the no-sight profile.
    local sourceProfiles, sourcePrefix = {}, sourceWeaponId .. "|"
    for key, saved in pairs(PVADS.User or {}) do
        if type(key) == "string" and string.sub(key, 1, #sourcePrefix) == sourcePrefix then
            local opticId = string.sub(key, #sourcePrefix + 1)
            if opticId ~= "" and type(saved) == "table" then
                sourceProfiles[opticId] = copyProfileTable(saved)
            end
        end
    end

    -- Include live edits for the equipped optic, even before Save is pressed.
    local liveOpticId = tostring(profile.opticId or "")
    if liveOpticId ~= "" then
        local liveProfile = sourceProfiles[liveOpticId] or {}
        sourceProfiles[liveOpticId] = liveProfile
        for _, field in ipairs(FIELDS) do liveProfile[field[1]] = current(field, false) end
        for _, name in ipairs({ "mode", "reticle", "pipAlt", "pip2DBackup", "recoilPitchReverse" }) do
            local value = profile[name]
            if value == nil and profile.userWeapon then value = profile.userWeapon[name] end
            if value ~= nil then liveProfile[name] = value end
        end
    end

    local opticIds = {}
    for opticId in pairs(sourceProfiles) do opticIds[#opticIds + 1] = opticId end
    table.sort(opticIds)
    if #opticIds == 0 then
        self.message = L("The source weapon has no saved sight profiles", "El arma de origen no tiene perfiles guardados de miras")
        return
    end

    local _, mounts = previewPartDefinitions()
    local entries, seen, targetWeapons = {}, {}, {}
    for _, weapon in ipairs(WEAPONS) do
        local targetWeaponId = weapon[2]
        if targetWeaponId and targetWeaponId ~= sourceWeaponId
            and ScriptManager.instance:getItem(targetWeaponId) then
            for _, opticId in ipairs(opticIds) do
                if canOpticFitWeapon(player, targetWeaponId, opticId, mounts) then
                    local key = targetWeaponId .. "|" .. opticId
                    if not seen[key] then
                        seen[key] = true
                        entries[#entries + 1] = { key = key, values = copyProfileTable(sourceProfiles[opticId]) }
                        targetWeapons[targetWeaponId] = true
                    end
                end
            end
        end
    end

    local weaponCount = 0
    for _ in pairs(targetWeapons) do weaponCount = weaponCount + 1 end
    if #entries == 0 then
        self.message = L("No target weapons have compatible profiles for these sights", "No hay armas destino con perfiles compatibles para estas miras")
        return
    end
    self.pendingLensCopy = {
        sourceWeaponId = sourceWeaponId, sourceProfileCount = #opticIds,
        entries = entries, targetWeaponCount = weaponCount,
    }
    local modal = ISModalDialog:new(0, 0, 540, 150,
        string.format(L("Copy %d sight profiles from %s to %d weapons (%d profiles)?", "¿Copiar %d perfiles de mira de %s a %d armas (%d perfiles)?"),
            #opticIds, sourceWeaponId, weaponCount, #entries), true,
        self, PVADSGaelSliderWindow.onConfirmCopyLens)
    modal.gaelInfo = L("All values from each compatible sight are copied; the no-sight profile is skipped.", "Se copian todos los valores de cada mira compatible; se omite el perfil sin mira.")
    modal.prerender = function(dialog)
        ISModalDialog.prerender(dialog)
        dialog:drawText(dialog.gaelInfo, 18, 48, 0.9, 0.85, 0.55, 1, UIFont.Small)
        dialog:drawText(L("A mount does not need to be installed. Existing target profiles will be fully replaced.", "No hace falta tener una montura instalada. Los perfiles existentes de destino se reemplazarán por completo."),
            18, 68, 0.9, 0.9, 0.9, 1, UIFont.Small)
    end
    modal:initialise(); modal:addToUIManager()
end

function PVADSGaelSliderWindow:onConfirmCopyLens(button)
    local pending = self.pendingLensCopy
    self.pendingLensCopy = nil
    if not pending then return end
    if button.internal ~= "YES" then
        self.message = L("Profile copy cancelled", "Copia de perfiles cancelada")
        return
    end
    for _, entry in ipairs(pending.entries) do
        PVADS.User[entry.key] = entry.values
        if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[entry.key] = nil end
    end
    local saved = PVADS.saveUserProfiles()
    PVADS.Controller.refresh(true)
    print(string.format("[PVADSGAEL2][copy-profiles] source=%s sourceProfiles=%d targetWeapons=%d targetProfiles=%d saved=%s",
        pending.sourceWeaponId, pending.sourceProfileCount, pending.targetWeaponCount,
        #pending.entries, tostring(saved)))
    self.message = saved
        and string.format(L("Copied %d profiles to %d weapons (%d profiles)%s", "Se copiaron %d perfiles a %d armas (%d perfiles)%s"),
            pending.sourceProfileCount, pending.targetWeaponCount, #pending.entries,
            L(" from ", " desde ") .. pending.sourceWeaponId)
        or L("Copy applied, but could not be saved", "Copia aplicada, pero no se pudo guardar")
end

function PVADSGaelSliderWindow:onSave()
    if self.editGlobal or self.globalDirty then
        local lines = { string.format(L("Global purple marker x%.2f", "Punto morado global x%.2f"), markerScale()) }
        for _, field in ipairs(FIELDS) do
            local value = PVADS.GaelGlobalValue(field[1])
            if value ~= 0 then
                lines[#lines + 1] = string.format("%s %+0.5f", field[2], value)
            end
        end
        local message = PVADS.GaelGlobalOnlyAvailable()
            and L("Confirm Available only for all weapons and sights?", "¿Confirmar Solo disponibles para todas las armas y miras?")
            or L("Confirm for ALL weapons and sights?", "¿Confirmar para TODAS las armas y miras?")
        local height = 130 + math.min(#lines, 10) * 18
        local modal = ISModalDialog:new(0, 0, 520, height, message, true,
            self, PVADSGaelSliderWindow.onConfirmGlobalSave)
        modal.gaelLines = lines
        modal.prerender = function(dialog)
            ISModalDialog.prerender(dialog)
            if #dialog.gaelLines == 0 then
                dialog:drawText(L("All offsets are 0", "Todos los valores están en 0"), 18, 49, 1, 0.85, 0.5, 1, UIFont.Small)
            else
                for i, line in ipairs(dialog.gaelLines) do
                    local col = math.floor((i - 1) / 10)
                    local row = (i - 1) % 10
                    dialog:drawText(line, 18 + col * 250, 49 + row * 18,
                        1, 0.85, 0.5, 1, UIFont.Small)
                end
            end
            dialog:drawText(L("If you choose No, the preview stays active but is not saved.", "Si eliges No, la vista previa seguirá activa, pero no se guardará."),
                18, dialog:getHeight() - 62, 0.75, 0.8, 0.9, 1, UIFont.Small)
        end
        modal:initialise(); modal:addToUIManager()
        return
    end
    local saved = PVADS.saveUserProfiles()
    if saved then self.markerDirty = false end
    self.message = saved and L("Saved to PVADS_UserProfiles.txt", "Guardado en PVADS_UserProfiles.txt") or L("Save failed", "No se pudo guardar")
end

function PVADSGaelSliderWindow:onConfirmGlobalSave(button)
    if button.internal ~= "YES" then
        self.message = L("Global changes not saved; keep adjusting or use Reset", "Cambios globales sin guardar; puedes seguir ajustando o restablecer")
        return
    end
    if PVADS.saveUserProfiles() then
        self.globalDirty = false
        self.markerDirty = false
        self.saveButton:setTitle(self.editGlobal and L("Confirm?", "¿Confirmar?") or L("Save", "Guardar"))
        self.message = L("Global offsets saved to PVADS_UserProfiles.txt", "Valores globales guardados en PVADS_UserProfiles.txt")
    else
        self.message = L("Save failed", "No se pudo guardar")
    end
end

function PVADSGaelSliderWindow:onProbe()
    self.message = PVADS_probe and tostring(PVADS_probe()) or L("Probe unavailable", "Análisis no disponible")
end

function PVADSGaelSliderWindow:onValidate()
    if PVADS.Validate then
        self.message = L("Validation: ", "Validación: ") .. tostring(PVADS.Validate()) .. L(" finding(s); see console", " resultado(s); consulta la consola")
    end
end

function PVADSGaelSliderWindow:close()
    self:setVisible(false)
    if Cal.window and Cal.window:isVisible() then Cal.window:close() end
    PVADS.Controller.forceADS = false
end

function PVADSGaelSliderWindow:render()
    ISCollapsableWindow.render(self)
    self:keepOnScreen()
    if self.isCollapsed then return end
    local key = selected()
    if key ~= self.lastKey then
        self.lastKey = key
        self:onCenter()
        self:syncChoices()
        self:syncRecoilPitchReverse()
        local itemId = key and string.match(key, "^[^|]+")
        if itemId then self.weaponCombo:setSelectedData(itemId) end
        self.attachmentWeaponId = nil
        self:syncAttachmentOptions()
    end
    local choices = key and PVADS.User[key]
    self:syncRecoilPitchReverse()
    self:updatePip2DBackupButton()
    if self.reticleCombo:getSelectedData() ~= (choices and choices.reticle or "auto")
        or self.modeCombo:getSelectedData() ~= (choices and choices.mode or "auto") then
        self:syncChoices()
    end
    if not self.editGlobal then
        self:drawText(L("Edit values:", "Editar valores:"), 8, self.scopeY, 1, 1, 1, 1, UIFont.Small)
    end
    self:drawText(L("Weapon", "Arma"), 8, self.weaponY, 1, 1, 1, 1, UIFont.Small)
    self:drawText(L("Hold Ctrl to aim; V toggles ADS. Selecting a weapon enables Hold ADS.", "Mantén Ctrl para apuntar; V activa o desactiva ADS. Elegir un arma habilita Mantener ADS."), 8, self.weaponY + 22, 0.7, 0.85, 1, 1, UIFont.Small)
    self:drawText(L("Sight / attachment", "Mira / accesorio"), 8, self.attachmentY + 3, 1, 1, 1, 1, UIFont.Small)
    local attachment = self.attachments and self.attachments[self.attachmentIndex]
    self:drawText(attachment and attachment.name or L("Select a weapon", "Selecciona un arma"), 158, self.attachmentY + 3,
        0.8, 0.9, 1, 1, UIFont.Small)
    local pageInfo = PAGES[self.page] or PAGES[1]
    self:drawText(L(pageInfo.titleEN, pageInfo.title), 8, self.pageTitleY, 1, 0.85, 0.45, 1, UIFont.Small)
    if self.page == 5 then
        self:drawText(L("Heuristic only: zeroes and extreme offsets/scales are review clues, not proof of misalignment.", "Es una heurística: ceros y valores extremos son pistas para revisar, no una prueba de desalineación."),
            8, self.pageTitleY + 17, 0.8, 0.85, 0.95, 1, UIFont.Small)
        if self.scanStatus then self:drawText(self.scanStatus, 150, self.pageTitleY + 42, 1, 0.9, 0.4, 1, UIFont.Small) end
    elseif self.page == 3 then
        self:drawText(L("Reticle", "Retícula"), 8, self.choiceY, 1, 1, 1, 1, UIFont.Small)
        self:drawText(L("ADS mode", "Modo ADS"), 306, self.choiceY, 1, 1, 1, 1, UIFont.Small)
        local backupOn = pip2DBackupEnabled(key, choices)
        self:drawText(backupOn
                and L("PiP 2D backup ON - screen-space fallback", "Respaldo PiP 2D ACTIVADO - proyección en pantalla")
                or L("PiP 2D backup OFF - anchor test", "Respaldo PiP 2D DESACTIVADO - prueba de anclaje"),
            8, self.pageTitleY + 18, 1, 0.55, 0.3, 1, UIFont.Small)
    elseif self.page == 2 and self.editGlobal then
        self:drawText(L("Global +/-: values are deltas from 0", "Global +/-: los valores son ajustes relativos desde 0"),
            8, self.pageTitleY + 18, 1, 0.8, 0.4, 1, UIFont.Small)
    end
    for _, row in ipairs(self.rows) do
        if row.page == self.page then
            self:drawText(fieldLabel(row.field), 8, row.y + 3, 1, 1, 1, 1, UIFont.Small)
            local n = current(row.field, self.editGlobal)
            if not row.slider.dragInside then
                if n < row.slider.minValue or n > row.slider.maxValue then self:rangeFor(row, n)
                else row.slider:setCurrentValue(n, true) end
            end
            if not row.entry:isFocused() then
                local displayed = string.format("%.5f", n)
                if row.entry:getText() ~= displayed then row.entry:setText(displayed) end
            end
        end
    end
    if self.markerScaleSlider and self.page ~= 5 then
        local scale = markerScale()
        if not self.markerScaleSlider.dragInside then
            self.markerScaleSlider:setCurrentValue(scale, true)
        end
        self:drawText(L("Purple marker x", "Punto morado x"), 8, self.markerScaleY + 3, 1, 0.8, 0.4, 1, UIFont.Small)
        self:drawText(string.format("x%.2f", scale), 556, self.markerScaleY + 3,
            1, 0.8, 0.4, 1, UIFont.Small)
    end
    self:drawText(key or L("No firearm equipped", "No hay un arma de fuego equipada"), 8, self.infoY, 0.85, 0.85, 0.85, 1, UIFont.Small)
    if self.holdButton then
        self.holdButton:setTitle(PVADS.Controller.forceADS and L("Release", "Soltar") or L("Hold ADS", "Mantener ADS"))
    end
    if self.message then self:drawText(self.message, 8, self.infoY + 18, 1, 0.9, 0.4, 1, UIFont.Small) end
end

local function install()
    if not Cal then return end
    if Cal.gaelSliderWindow then
        if Cal.gaelSliderWindow.addMarkerScaleControl then
            Cal.gaelSliderWindow:addMarkerScaleControl()
        else
            local old = Cal.gaelSliderWindow
            local visible = old:isVisible()
            local x, y = old:getX(), old:getY()
            old:setVisible(false)
            old:removeFromUIManager()
            Cal.gaelSliderWindow = PVADSGaelSliderWindow:new(x, y)
            Cal.gaelSliderWindow:initialise()
            Cal.gaelSliderWindow:addToUIManager()
            Cal.gaelSliderWindow:setVisible(visible)
        end
    end
    pushMarkerScale()
    if not Cal.gaelSightArrowKeysInstalled then
        Cal.gaelSightArrowKeysInstalled = true
        Cal.gaelSightArrowRepeatCount = {}
        Events.OnKeyPressed.Add(function(key)
            Cal.gaelSightArrowRepeatCount[key] = 0
            local window = Cal.gaelSliderWindow
            if window and window.onSightArrowKey then window:onSightArrowKey(key) end
        end)
        Events.OnKeyKeepPressed.Add(function(key)
            if key ~= Keyboard.KEY_LEFT and key ~= Keyboard.KEY_RIGHT
                and key ~= Keyboard.KEY_UP and key ~= Keyboard.KEY_DOWN then return end
            local window = Cal.gaelSliderWindow
            if not window or not window.onSightArrowKey or not window:isVisible() then return end
            local counts = Cal.gaelSightArrowRepeatCount
            counts[key] = (counts[key] or 0) + 1
            local multiplier = math.min(8, 1 + math.floor(counts[key] / 4))
            window:onSightArrowKey(key, multiplier)
        end)
    end
    if not Cal.gaelSliderInstalled then
    Cal.gaelSliderInstalled = true
    local originalToggle = Cal.toggle
    Cal.toggle = function(...)
        originalToggle(...)
        local main = Cal.window
        if not main then return end
        if not Cal.gaelSliderWindow then
            local sw = getCore():getScreenWidth()
            Cal.gaelSliderWindow = PVADSGaelSliderWindow:new(math.max(370, sw - 630), 80)
            Cal.gaelSliderWindow:initialise()
            Cal.gaelSliderWindow:addToUIManager()
        else
            Cal.gaelSliderWindow:setVisible(main:isVisible())
            if main:isVisible() then Cal.gaelSliderWindow:onCenter() end
        end
    end
    local originalClose = PVADSCalibWindow.close
    PVADSCalibWindow.close = function(win, ...)
        originalClose(win, ...)
        if Cal.gaelSliderWindow then Cal.gaelSliderWindow:setVisible(false) end
    end
    local originalSave = PVADSCalibWindow.onSave
    PVADSCalibWindow.onSave = function(win, ...)
        local slider = Cal.gaelSliderWindow
        if slider and (slider.editGlobal or slider.globalDirty) then
            slider:onSave()
        else
            originalSave(win, ...)
        end
    end

    end
    -- Rebind on Lua reload: the old render closure cannot see newly loaded
    -- code. Keep its base draw, but hide the calibrator while it runs so its
    -- obsolete marker is suppressed.
    if PVADSOverlay then
        PVADSOverlay.gaelHooked = true
        PVADSOverlay.gaelBaseForReload = PVADSOverlay.gaelBaseForReload or PVADSOverlay.render
        local origOverlayRender = PVADSOverlay.gaelBaseForReload
        local sightState = {}
        PVADSOverlay.render = function(self)
            local calWin = PVADS.Calibrator and PVADS.Calibrator.window
            local wasVisible = calWin and calWin:isVisible()
            if wasVisible then calWin:setVisible(false) end
            origOverlayRender(self)
            if wasVisible then
                calWin:setVisible(true)
                local cx, cy = self.width / 2, self.height / 2
                self:drawRect(cx - 8, cy, 17, 1, 0.9, 0, 1, 1)
                self:drawRect(cx, cy - 8, 1, 17, 0.9, 0, 1, 1)

                -- The line begins at PVADS' visible sight window. Its end
                -- shows the barrel's angular miss accumulated over range.
                if PVADS_getState then
                    PVADS_getState(sightState)
                    local angleX = tonumber(sightState.dotX)
                    local angleY = tonumber(sightState.dotY)
                    local startX = tonumber(sightState.winX)
                    local startY = tonumber(sightState.winY)
                    local root = rawget(_G, "ViewpointGael")
                    local aim = root and root.Aim
                    local projectionVersion = shotProjectionVersion(aim)
                    local liveMirror = projectionVersion >= 1
                    if liveMirror and aim.sightMarkerX and aim.sightMarkerY then
                        local okX, projectedX = pcall(aim.sightMarkerX)
                        local okY, projectedY = pcall(aim.sightMarkerY)
                        projectedX, projectedY = tonumber(projectedX), tonumber(projectedY)
                        if okX and okY and projectedX and projectedY
                            and projectedX == projectedX and projectedY == projectedY
                            and math.abs(projectedX) < 100000 and math.abs(projectedY) < 100000 then
                            angleX, angleY = projectedX, projectedY
                        end
                    end
                    if sightState.visible and angleX and angleY
                        and angleX > -9000 and angleY > -9000 then
                        pushMarkerScale()
                        local scale = markerScale()
                        -- Version 1 reflected the muzzle a second time and
                        -- left the marker on the front post. Lua reload can
                        -- correct its HUD preview until version 2 is loaded.
                        if projectionVersion < 2 then
                            local dx, dy = angleX - cx, angleY - cy
                            angleX, angleY = cx - dx * scale, cy - dy * scale
                        end
                        local dotX, dotY = angleX, angleY
                        if not startX or not startY or startX < -9000 or startY < -9000 then
                            startX, startY = cx, cy
                        end
                        if startX ~= dotX or startY ~= dotY then
                            self:drawLine2(startX, startY, dotX, dotY, 0.72, 1, 0.18, 0.85)
                        end
                        self:drawRect(dotX - 3, dotY - 3, 7, 7, 0.9, 1, 0, 1)
                    end
                end
            end
            local profile = PVADS.Controller and PVADS.Controller.profile
            if profile and tonumber(profile.pipAlt) == 1 and profile.mode == "reflex" and PVADS_getState then
                PVADS_getState(sightState)
                local dotX, dotY = tonumber(sightState.dotX), tonumber(sightState.dotY)
                if sightState.visible and dotX and dotY and dotX > -9000 and dotY > -9000
                    and dotX < self.width + 9000 and dotY < self.height + 9000 then
                    -- Our own HUD dot, independent from the addon's PiP reticle render pass.
                    self:drawRect(dotX - 5, dotY - 5, 11, 11, 0.95, 0.02, 0.02, 0.02)
                    self:drawRect(dotX - 2, dotY - 2, 5, 5, 1.0, 1.0, 0.08, 0.06)
                end
            end
        end
    end
end

Events.OnGameStart.Add(install)
Events.OnGameBoot.Add(install)
install()
