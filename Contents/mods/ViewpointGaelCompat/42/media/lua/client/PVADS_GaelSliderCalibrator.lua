require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
require "ISUI/ISTextEntryBox"
require "ISUI/ISInventoryPaneContextMenu"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "PVADS/PVADS_Calibrator"
require "PVADS_GaelWeaponCatalog"
require "PVADS_GaelVisualChoices"

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
    {"pipZoom", "PiP zoom", 0.01, 1}, {"pipRetX", "PiP reticle X", 0.005},
    {"pipRetY", "PiP reticle Y", 0.005}, {"pipDepth", "PiP depth", 0.002},
}
-- Shared lens presentation and sight XYZ values copied between sniper rifles.
-- Pitch/yaw, relief and optic height stay specific to each weapon.
local SHARED_LENS_FIELDS = {
    "adjX", "adjY", "adjZ", "lensScale", "pipX", "pipY", "pipZ",
    "pipScale", "pipZoom", "pipRetX", "pipRetY", "pipDepth",
}
local RANGES = { 1, 5, 20 }
local WEAPONS = PVADS_GaelWeaponCatalog or {}
-- Bulk lens copy is temporarily restricted to bolt-action sniper rifles.
-- Add newly released Gael sniper IDs here to include them in future copies.
local SNIPER_COPY_WEAPON_IDS = PVADS.GaelSniperCopyWeaponIds or {}
local SNIPER_COPY_SOURCE_WEAPON_SET = { ["Base.Carcano"] = true }
for _, weaponId in ipairs(SNIPER_COPY_WEAPON_IDS) do SNIPER_COPY_SOURCE_WEAPON_SET[weaponId] = true end
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
local MODES = {
    {"Auto (optic default)", "auto"}, {"Iron", "iron"},
    {"Reflex", "reflex"}, {"Scope / PiP", "scope"},
    {"Scope G36 (ADS)", "scopeg36"},
    {"ScopeRedDotALT (ADS)", "scopereddotalt"},
}

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
    return true
end

local function selected()
    local pl = getSpecificPlayer(0)
    local weapon = PVADS.Controller.weapon(pl)
    return weapon and PVADS.userKey(weapon) or nil
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

local function apply(field, amount, global)
    local key = global and PVADS.GaelGlobalKey or selected()
    if not key then return false end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    PVADS.User[key][field[1]] = amount
    PVADS.Controller.refresh(true)
    return true
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
    local o = ISCollapsableWindow.new(self, x, y, 610, 690)
    o.title = "Project Viewpoint - slider calibrator"
    o.resizable = false
    o.rangeLevel = 1
    o.editGlobal = false
    o.globalDirty = false
    o.rows = {}
    return o
end

function PVADSGaelSliderWindow:rangeFor(row, centre)
    row.centre = centre
    local span = row.field[3] * 200 * RANGES[self.rangeLevel]
    local minimum = centre - span
    if row.field[1] == "lensScale" or row.field[1] == "pipScale" or row.field[1] == "pipZoom" then
        minimum = math.max(0.001, minimum)
    end
    row.slider:setValues(minimum, centre + span, row.field[3], row.field[3], true)
    row.slider:setCurrentValue(centre, true)
end

function PVADSGaelSliderWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:titleBarHeight() + 7
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7

    self.availableButton = ISButton:new(8, y, 220, bh, "Solo disponibles: NO", self,
        PVADSGaelSliderWindow.onAvailable)
    self.availableButton:initialise(); self:addChild(self.availableButton)
    self.availableButton:setVisible(false)
    self.localButton = ISButton:new(306, y, 143, bh, "[Modificar Local]", self, PVADSGaelSliderWindow.onLocal)
    self.localButton:initialise(); self:addChild(self.localButton)
    self.globalButton = ISButton:new(454, y, 143, bh, "Modificar Global", self, PVADSGaelSliderWindow.onGlobal)
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
    y = y + bh + 23
    self.choiceY = y + 3
    self.reticleCombo = ISComboBox:new(75, y, 220, bh, self, PVADSGaelSliderWindow.onReticleChosen)
    self.reticleCombo:initialise(); self.reticleCombo:instantiate()
    for _, option in ipairs(RETICLES) do
        self.reticleCombo:addOptionWithData(option[1], option[2])
    end
    self:addChild(self.reticleCombo)
    self.modeCombo = ISComboBox:new(375, y, 220, bh, self, PVADSGaelSliderWindow.onModeChosen)
    self.modeCombo:initialise(); self.modeCombo:instantiate()
    for _, option in ipairs(MODES) do
        self.modeCombo:addOptionWithData(option[1], option[2])
    end
    self:addChild(self.modeCombo)
    y = y + bh + 6
    self.attachmentY = y
    self.attachmentPrevButton = ISButton:new(120, y, 30, bh, "<", self,
        PVADSGaelSliderWindow.onPrevAttachment)
    self.attachmentPrevButton:initialise(); self:addChild(self.attachmentPrevButton)
    self.attachmentNextButton = ISButton:new(566, y, 30, bh, ">", self,
        PVADSGaelSliderWindow.onNextAttachment)
    self.attachmentNextButton:initialise(); self:addChild(self.attachmentNextButton)
    self.choiceInfoY = y + bh + 4
    y = y + bh + 23
    self.recoilPitchReverseButton = ISButton:new(8, y, 220, bh,
        "RecoilPitchYawReverse?: NO", self, PVADSGaelSliderWindow.onRecoilPitchReverse)
    self.recoilPitchReverseButton:initialise(); self:addChild(self.recoilPitchReverseButton)
    y = y + bh + 6
    for i, field in ipairs(FIELDS) do
        if i == 12 then y = y + 16; self.pipY = y - 13 end
        local entry = ISTextEntryBox:new(string.format("%.5f", current(field, self.editGlobal)), 117, y, 83, bh)
        entry.font = UIFont.Small
        entry:initialise(); entry:instantiate()
        entry.pvRow = i; entry.pvOwner = self
        entry.onCommandEntered = function(box) box.pvOwner:applyTyped(box) end
        entry.onLostFocus = function(box) box.pvOwner:applyTyped(box) end
        self:addChild(entry)
        local slider = ISSliderPanel:new(210, y, 388, bh, self, PVADSGaelSliderWindow.onSlide)
        slider:initialise(); slider:instantiate()
        slider:setDoButtons(false)
        slider.pvRow = i
        self:addChild(slider)
        local row = { field = field, entry = entry, slider = slider, y = y }
        self.rows[i] = row
        self:rangeFor(row, current(field, self.editGlobal))
        y = y + bh + 3
    end
    y = y + 8
    local function button(x, label, callback, width)
        local b = ISButton:new(x, y, width or 92, bh, label, self, callback)
        b:initialise(); self:addChild(b)
        return b
    end
    self.rangeButton = button(8, "Range x1", PVADSGaelSliderWindow.onRange)
    button(106, "Center", PVADSGaelSliderWindow.onCenter)
    self.holdButton = button(204, "Hold ADS", PVADSGaelSliderWindow.onHold)
    button(302, "Reset", PVADSGaelSliderWindow.onReset)
    button(400, "Copy", PVADSGaelSliderWindow.onCopy)
    self.saveButton = button(498, "Save", PVADSGaelSliderWindow.onSave)
    y = y + bh + 4
    button(8, "Probe", PVADSGaelSliderWindow.onProbe)
    button(106, "Validate", PVADSGaelSliderWindow.onValidate)
    self.realTimeDotButton = button(204, PVADS.GaelRealTimeDot and "RealTimeDot: ON" or "RealTimeDot: OFF", PVADSGaelSliderWindow.onRealTimeDot, 140)
    self.copyLensButton = button(350, "Copiar lente", PVADSGaelSliderWindow.onCopyLens, 96)
    self.pipAltButton = button(450, "PiP ALT", PVADSGaelSliderWindow.onPipAlt, 76)
    button(530, "Close", PVADSGaelSliderWindow.close, 76)
    self.infoY = y + bh + 10
    self:addMarkerScaleControl()
end

function PVADSGaelSliderWindow:addMarkerScaleControl()
    if self.markerScaleSlider then return end
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7
    self.markerScaleY = self.infoY
    local slider = ISSliderPanel:new(165, self.markerScaleY - 3, 388, bh,
        self, PVADSGaelSliderWindow.onMarkerScale)
    slider:initialise(); slider:instantiate()
    slider:setDoButtons(false)
    slider:setValues(0, 3, 0.05, 0.05, true)
    slider:setCurrentValue(markerScale(), true)
    self:addChild(slider)
    self.markerScaleSlider = slider
    self.infoY = self.infoY + bh + 8
    self:setHeight(self.infoY + 48)
end

function PVADSGaelSliderWindow:syncRecoilPitchReverse()
    local key = selected()
    local values = key and PVADS.User[key]
    local reverse = recoilReverseEnabled(values)
    if self.recoilPitchReverseButton then
        self.recoilPitchReverseButton:setTitle("RecoilPitchYawReverse?: " .. (reverse and "SI" or "NO"))
        self.recoilPitchReverseButton:setVisible(not self.editGlobal)
    end
end

function PVADSGaelSliderWindow:onRecoilPitchReverse()
    if self.editGlobal then return end
    local key = selected()
    if not key then
        self.message = "Equipa un arma para cambiar su perfil de recoil"
        return
    end
    PVADS.User[key] = PVADS.User[key] or {}
    if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
    local enabled = not recoilReverseEnabled(PVADS.User[key])
    PVADS.User[key].recoilPitchReverse = enabled and 1 or 0
    PVADS.Controller.refresh(true)
    self:syncRecoilPitchReverse()
    self.message = enabled
        and "Pitch y yaw del recoil invertidos para este perfil (pulsa Save para guardar)"
        or "Pitch y yaw del recoil normales para este perfil (pulsa Save para guardar)"
    self.saveButton:setTitle("Save")
end

function PVADSGaelSliderWindow:onMarkerScale(value)
    value = math.floor(math.max(0, math.min(3, tonumber(value) or 1)) * 20 + 0.5) / 20
    local key = PVADS.GaelGlobalKey
    PVADS.User[key] = PVADS.User[key] or {}
    PVADS.User[key].markerScale = value
    self.markerDirty = true
    self.message = string.format("Separacion global x%.2f (Save para conservar)", value)
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
            self.message = "Item unavailable: " .. itemId
            return
        end
        item = pl:getInventory():AddItem(itemId)
    end
    if not item or not instanceof(item, "HandWeapon") or not item:isAimedFirearm() then
        self.message = "ADS firearm unavailable: " .. itemId
        return
    end
    PVADS.Controller.forceADS = true
    if pl:getPrimaryHandItem() ~= item then
        ISInventoryPaneContextMenu.equipWeapon(item, true, item:isTwoHandWeapon(), pl:getPlayerNum())
        self.message = "Equipping " .. itemId .. "; hold Ctrl to aim"
    else
        PVADS.Controller.refresh(true)
        self.message = "Ready: " .. itemId .. "; hold Ctrl to aim"
    end
    return item
end

function PVADSGaelSliderWindow:onWeaponChosen()
    local weapon = self:equipSelected()
    self:syncAttachmentOptions(weapon)
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
    self.attachments = { { id = false, name = "Sin mira" } }
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
    local weapon = player and itemId and findOwned(player:getInventory(), itemId)
    if not attachment or not player or not weapon then
        self.message = "Equipa el arma seleccionada antes de cambiar su mira"
        return
    end
    if attachment.mountId then
        local mount = instanceItem(attachment.mountId)
        local partType = mount and mount:getPartType()
        if partType and not replaceWeaponPart(player, weapon, attachment.mountId, partType) then
            self.message = "No se pudo instalar la montura " .. attachment.mountId
            return
        end
    end
    if attachment.id then
        if not replaceWeaponPart(player, weapon, attachment.id, "Scope") then
            self.message = "No se pudo instalar la mira " .. attachment.id
            return
        end
    else
        local currentPart = weapon:getWeaponPart("Scope")
        if currentPart then
            weapon:detachWeaponPart(player, currentPart)
            player:getInventory():AddItem(currentPart)
            if syncHandWeaponFields then pcall(syncHandWeaponFields, player, weapon) end
        end
    end
    PVADS.Controller.refresh(true)
    self.message = attachment.id and ("Mira de prueba: " .. attachment.id)
        or "Mira retirada para probar los hierros"
end

function PVADSGaelSliderWindow:stepAttachment(delta)
    local options = self.attachments or {}
    if #options == 0 then return end
    self.attachmentIndex = (self.attachmentIndex - 1 + delta + #options) % #options + 1
    self:applyAttachmentSelection()
end

function PVADSGaelSliderWindow:onPrevAttachment() self:stepAttachment(-1) end
function PVADSGaelSliderWindow:onNextAttachment() self:stepAttachment(1) end

function PVADSGaelSliderWindow:setEditGlobal(global)
    if self.editGlobal == global then return end
    self.editGlobal = global
    self.localButton:setTitle(global and "Modificar Local" or "[Modificar Local]")
    self.globalButton:setTitle(global and "[Modificar Global]" or "Modificar Global")
    self.saveButton:setTitle((global or self.globalDirty) and "Confirmar?" or "Save")
    self.availableButton:setVisible(global)
    self.availableButton:setTitle(PVADS.GaelGlobalOnlyAvailable()
        and "[Solo disponibles: SI]" or "Solo disponibles: NO")
    self.reticleCombo:setVisible(not global)
    self.modeCombo:setVisible(not global)
    if self.pipAltButton then self.pipAltButton:setVisible(not global) end
    self.attachmentPrevButton:setVisible(not global)
    self.attachmentNextButton:setVisible(not global)
    self:syncRecoilPitchReverse()
    self:onCenter()
    self.message = global and "Global: 0 = sin cambio; los valores se SUMAN a todas las armas y miras"
        or "Local: editando solo el arma y mira equipadas"
end

function PVADSGaelSliderWindow:onLocal() self:setEditGlobal(false) end
function PVADSGaelSliderWindow:onGlobal() self:setEditGlobal(true) end

function PVADSGaelSliderWindow:onAvailable()
    local key = PVADS.GaelGlobalKey
    PVADS.User[key] = PVADS.User[key] or {}
    PVADS.User[key].onlyAvailable = PVADS.GaelGlobalOnlyAvailable() and nil or 1
    self.globalDirty = true
    self.availableButton:setTitle(PVADS.GaelGlobalOnlyAvailable()
        and "[Solo disponibles: SI]" or "Solo disponibles: NO")
    PVADS.Controller.refresh(true)
    self.message = PVADS.GaelGlobalOnlyAvailable()
        and "Solo disponibles: excluye cada valor calibrado explicitamente, incluso 0"
        or "Global: aplica a todos, incluidos los perfiles calibrados"
end

function PVADSGaelSliderWindow:onRealTimeDot()
    PVADS.GaelRealTimeDot = not PVADS.GaelRealTimeDot
    if self.realTimeDotButton then
        self.realTimeDotButton:setTitle(PVADS.GaelRealTimeDot and "RealTimeDot: ON" or "RealTimeDot: OFF")
    end
    self.message = PVADS.GaelRealTimeDot
        and "RealTimeDot: ON - Recoil y Sway activos durante la calibracion"
        or "RealTimeDot: OFF - Vista estatica para calibrar"
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
        self.message = "Scope G36 (ADS) solo se aplica al G36"
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
        self.message = saved and "ScopeRedDotALT guardado para esta arma y mira"
            or "ScopeRedDotALT aplicado; no se pudo guardar"
    else
        self.message = field .. " = " .. (choice == "auto" and "optic default" or choice)
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
        self.message = "Equipa un arma con scope para aplicar PiP ALT"
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
    print("[ViewpointGaelCompat][PiP ALT] applied key=" .. tostring(key) .. " overlayDot=red mode=reflex")
    self.message = "PiP ALT: punto rojo propio sobre el eje del arma; pulsa Save"
    if self.saveButton then self.saveButton:setTitle("Save") end
end

function PVADSGaelSliderWindow:onSlide(amount, slider)
    local row = self.rows[slider.pvRow]
    if not row then return end
    if apply(row.field, amount, self.editGlobal) then
        if self.editGlobal then
            self.globalDirty = true
            self.saveButton:setTitle("Confirmar?")
        end
        row.entry:setText(string.format("%.5f", amount))
        self.message = (self.editGlobal and "Global +/- " or "Local ")
            .. row.field[2] .. " = " .. string.format("%.5f", amount)
    end
end

function PVADSGaelSliderWindow:applyTyped(box)
    local row = self.rows[box.pvRow]
    local amount = tonumber(box:getText())
    if not amount then
        box:setText(string.format("%.5f", current(row.field, self.editGlobal)))
        self.message = "Enter a number"
        return
    end
    if math.abs(amount - current(row.field, self.editGlobal)) > 0.0000001
        and apply(row.field, amount, self.editGlobal) then
        if self.editGlobal then
            self.globalDirty = true
            self.saveButton:setTitle("Confirmar?")
        end
        self:rangeFor(row, amount)
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
    local value = current(row.field, self.editGlobal) + direction * row.field[3] * stepMultiplier
    if apply(row.field, value, self.editGlobal) then
        self:rangeFor(row, value)
        row.slider:setCurrentValue(value, true)
        row.entry:setText(string.format("%.5f", value))
        if self.editGlobal then
            self.globalDirty = true
            self.saveButton:setTitle("Confirmar?")
        end
        self.message = (self.editGlobal and "Global +/- " or "Local ")
            .. row.field[2] .. " = " .. string.format("%.5f", value)
    end
end

function PVADSGaelSliderWindow:onRange()
    self.rangeLevel = self.rangeLevel % #RANGES + 1
    self.rangeButton:setTitle("Range x" .. RANGES[self.rangeLevel])
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

function PVADSGaelSliderWindow:onHold()
    PVADS.Controller.forceADS = not PVADS.Controller.forceADS
    self.holdButton:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
    if Cal.window and Cal.window.btnHold then
        Cal.window.btnHold:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
    end
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
    self.message = "Reset " .. key
end

function PVADSGaelSliderWindow:onCopy()
    if self.editGlobal then
        self.message = "Los offsets globales se guardan con Confirmar?; Copy es solo local"
        return
    end
    local snippet = Cal.snippet()
    Clipboard.setClipboard(snippet)
    self.message = "Copied current profile"
end

local function canOpticFitWeapon(player, weaponId, opticId, mounts)
    local testWeapon = instanceItem(weaponId)
    local optic = instanceItem(opticId)
    if not testWeapon or not optic then return false end
    local ok, canAttach = pcall(function() return optic:canAttach(player, testWeapon) end)
    if ok and canAttach then return true end

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

function PVADSGaelSliderWindow:onCopyLens()
    local sourceKey = selected()
    local profile = PVADS.Controller and PVADS.Controller.profile
    if not sourceKey or not profile or not profile.opticId then
        self.message = "Equipa el arma y la mira que usaras como origen"
        return
    end
    local player = getSpecificPlayer(0)
    if not player then self.message = "Jugador no disponible"; return end

    local sourceWeaponId, opticId = string.match(sourceKey, "^([^|]*)|(.*)$")
    if not sourceWeaponId or opticId == "" or opticId ~= tostring(profile.opticId) then
        self.message = "No se pudo identificar la mira del perfil actual"
        return
    end
    if not SNIPER_COPY_SOURCE_WEAPON_SET[sourceWeaponId] then
        self.message = "Para copiar, equipa un rifle francotirador de cerrojo"
        return
    end

    local values = {}
    for _, name in ipairs(SHARED_LENS_FIELDS) do
        local field
        for _, candidate in ipairs(FIELDS) do
            if candidate[1] == name then field = candidate; break end
        end
        if field then
            if self.editGlobal then
                local value = tonumber(profile[name])
                if value == nil and profile.userWeapon then value = tonumber(profile.userWeapon[name]) end
                if value == nil then value = field[4] or 0 end
                -- Unrestricted offsets still apply after saving the copied
                -- local values, so subtract them. In only-available mode the
                -- copied explicit field blocks the global offset and needs the
                -- full currently previewed value.
                if not PVADS.GaelGlobalOnlyAvailable() then
                    value = value - PVADS.GaelEffectiveGlobalValue(profile, name)
                end
                values[name] = value
            else
                values[name] = current(field, false)
            end
        end
    end

    local _, mounts = previewPartDefinitions()
    local targetKeys, seen = {}, {}
    local function addTarget(weaponId)
        local key = tostring(weaponId) .. "|" .. opticId
        if not seen[key] then seen[key] = true; targetKeys[#targetKeys + 1] = key end
    end
    for _, weaponId in ipairs(SNIPER_COPY_WEAPON_IDS) do
        if weaponId ~= sourceWeaponId and canOpticFitWeapon(player, weaponId, opticId, mounts) then
            addTarget(weaponId)
        end
    end

    local globalCopy = self.editGlobal
    self.pendingLensCopy = { sourceKey = sourceKey, opticId = opticId, keys = targetKeys, values = values, global = globalCopy }
    local modal = ISModalDialog:new(0, 0, 540, 150,
        string.format("Copiar ajustes a %d francotiradores compatibles con %s%s?",
            #targetKeys, tostring(profile.opticId), globalCopy and " (incluye monturas)" or ""), true,
        self, PVADSGaelSliderWindow.onConfirmCopyLens)
    modal.gaelInfo = string.format("Mira: %s. Se copian Sight XYZ y ajustes de lente/PiP; Pitch/Yaw, Relief y altura quedan propios.", opticId)
    modal.prerender = function(dialog)
        ISModalDialog.prerender(dialog)
        dialog:drawText(dialog.gaelInfo, 18, 48, 0.9, 0.85, 0.55, 1, UIFont.Small)
        dialog:drawText("Sight XYZ, Lens size, PiP X/Y/Z, PiP size/zoom, reticle offsets y depth se sobrescribiran.",
            18, 68, 0.9, 0.9, 0.9, 1, UIFont.Small)
    end
    modal:initialise(); modal:addToUIManager()
end

function PVADSGaelSliderWindow:onConfirmCopyLens(button)
    local pending = self.pendingLensCopy
    self.pendingLensCopy = nil
    if not pending then return end
    if button.internal ~= "YES" then
        self.message = "Copia de lente cancelada"
        return
    end
    for _, key in ipairs(pending.keys) do
        PVADS.User[key] = PVADS.User[key] or {}
        if PVADS.GaelDeletedProfileKeys then PVADS.GaelDeletedProfileKeys[key] = nil end
        for name, value in pairs(pending.values) do
            PVADS.User[key][name] = value
        end
    end
    local saved = PVADS.saveUserProfiles()
    PVADS.Controller.refresh(true)
    print(string.format("[ViewpointGaelCompat][copy-lens] source=%s optic=%s targets=%d saved=%s fields=%s",
        pending.sourceKey, pending.opticId, #pending.keys, tostring(saved), table.concat(SHARED_LENS_FIELDS, ",")))
    self.message = saved
        and string.format("Ajustes de %s copiados a %d combinaciones compatibles%s", pending.opticId, #pending.keys,
            pending.global and " (desde Global)" or "")
        or "Copia aplicada pero no se pudo guardar"
end

function PVADSGaelSliderWindow:onSave()
    if self.editGlobal or self.globalDirty then
        local lines = { string.format("Punto morado global x%.2f", markerScale()) }
        for _, field in ipairs(FIELDS) do
            local value = PVADS.GaelGlobalValue(field[1])
            if value ~= 0 then
                lines[#lines + 1] = string.format("%s %+0.5f", field[2], value)
            end
        end
        local message = PVADS.GaelGlobalOnlyAvailable()
            and "Confirmar Solo disponibles para todas las armas y miras?"
            or "Confirmar para TODAS las armas y miras?"
        local height = 130 + math.min(#lines, 10) * 18
        local modal = ISModalDialog:new(0, 0, 520, height, message, true,
            self, PVADSGaelSliderWindow.onConfirmGlobalSave)
        modal.gaelLines = lines
        modal.prerender = function(dialog)
            ISModalDialog.prerender(dialog)
            if #dialog.gaelLines == 0 then
                dialog:drawText("Todos los offsets estan en 0", 18, 49, 1, 0.85, 0.5, 1, UIFont.Small)
            else
                for i, line in ipairs(dialog.gaelLines) do
                    local col = math.floor((i - 1) / 10)
                    local row = (i - 1) % 10
                    dialog:drawText(line, 18 + col * 250, 49 + row * 18,
                        1, 0.85, 0.5, 1, UIFont.Small)
                end
            end
            dialog:drawText("Si eliges No, la vista previa sigue activa pero sin guardar.",
                18, dialog:getHeight() - 62, 0.75, 0.8, 0.9, 1, UIFont.Small)
        end
        modal:initialise(); modal:addToUIManager()
        return
    end
    local saved = PVADS.saveUserProfiles()
    if saved then self.markerDirty = false end
    self.message = saved and "Saved to PVADS_UserProfiles.txt" or "Save failed"
end

function PVADSGaelSliderWindow:onConfirmGlobalSave(button)
    if button.internal ~= "YES" then
        self.message = "Global sin guardar; puedes seguir ajustando o usar Reset"
        return
    end
    if PVADS.saveUserProfiles() then
        self.globalDirty = false
        self.markerDirty = false
        self.saveButton:setTitle(self.editGlobal and "Confirmar?" or "Save")
        self.message = "Offsets globales guardados en PVADS_UserProfiles.txt"
    else
        self.message = "Save failed"
    end
end

function PVADSGaelSliderWindow:onProbe()
    self.message = PVADS_probe and tostring(PVADS_probe()) or "Probe unavailable"
end

function PVADSGaelSliderWindow:onValidate()
    if PVADS.Validate then
        self.message = "Validation: " .. tostring(PVADS.Validate()) .. " finding(s); see console"
    end
end

function PVADSGaelSliderWindow:close()
    self:setVisible(false)
    if Cal.window and Cal.window:isVisible() then Cal.window:close() end
    PVADS.Controller.forceADS = false
end

function PVADSGaelSliderWindow:render()
    ISCollapsableWindow.render(self)
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
    if self.reticleCombo:getSelectedData() ~= (choices and choices.reticle or "auto")
        or self.modeCombo:getSelectedData() ~= (choices and choices.mode or "auto") then
        self:syncChoices()
    end
    if not self.editGlobal then
        self:drawText("Editar valores:", 8, self.scopeY, 1, 1, 1, 1, UIFont.Small)
    end
    self:drawText("Weapon", 8, self.weaponY, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Hold Ctrl to aim; V toggles ADS. Selecting a weapon enables Hold ADS.", 8, self.weaponY + 22, 0.7, 0.85, 1, 1, UIFont.Small)
    if self.editGlobal then
        self:drawText("Global +/- : las barras parten de 0; Solo disponibles protege valores ya editados", 8, self.choiceY,
            1, 0.8, 0.4, 1, UIFont.Small)
    else
        self:drawText("Retícula", 8, self.choiceY, 1, 1, 1, 1, UIFont.Small)
        self:drawText("Modo ADS", 306, self.choiceY, 1, 1, 1, 1, UIFont.Small)
        self:drawText("Mira / attachment", 8, self.attachmentY + 3, 1, 1, 1, 1, UIFont.Small)
        local attachment = self.attachments and self.attachments[self.attachmentIndex]
        self:drawText(attachment and attachment.name or "Selecciona un arma", 158, self.attachmentY + 3,
            0.8, 0.9, 1, 1, UIFont.Small)
    end
    local profile = PVADS.Controller.profile
    if profile then
        self:drawText((self.editGlobal and "Vista previa: " or "Actual: ")
            .. tostring(profile.reticle) .. " / " .. tostring(profile.mode),
            8, self.choiceInfoY, 0.65, 0.85, 1, 1, UIFont.Small)
    end
    if self.pipY then self:drawText("Picture-in-picture (scopes / red dots)", 8, self.pipY, 0.55, 0.85, 1, 1, UIFont.Small) end
    for _, row in ipairs(self.rows) do
        self:drawText(row.field[2], 8, row.y + 3, 1, 1, 1, 1, UIFont.Small)
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
    if self.markerScaleSlider then
        local scale = markerScale()
        if not self.markerScaleSlider.dragInside then
            self.markerScaleSlider:setCurrentValue(scale, true)
        end
        self:drawText("Punto morado x", 8, self.markerScaleY + 3, 1, 0.8, 0.4, 1, UIFont.Small)
        self:drawText(string.format("x%.2f", scale), 556, self.markerScaleY + 3,
            1, 0.8, 0.4, 1, UIFont.Small)
    end
    self:drawText(key or "No firearm equipped", 8, self.infoY, 0.85, 0.85, 0.85, 1, UIFont.Small)
    if self.holdButton then
        self.holdButton:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
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
