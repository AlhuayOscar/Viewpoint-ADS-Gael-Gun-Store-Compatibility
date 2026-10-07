require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "PVADS/PVADS_Calibrator"

-- Companion to the stock calibrator. Both windows write to the same user profile.
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
local RANGES = { 1, 5, 20 }

local function selected()
    local pl = getSpecificPlayer(0)
    local weapon = PVADS.Controller.weapon(pl)
    return weapon and PVADS.userKey(weapon) or nil
end

local function current(field)
    local p = PVADS.Controller.profile
    local n = p and p[field[1]]
    return n == nil and (field[4] or 0) or n
end

local function apply(field, amount)
    local key = selected()
    if not key then return false end
    PVADS.User[key] = PVADS.User[key] or {}
    PVADS.User[key][field[1]] = amount
    PVADS.Controller.refresh(true)
    return true
end

PVADSGaelSliderWindow = ISCollapsableWindow:derive("PVADSGaelSliderWindow")

function PVADSGaelSliderWindow:new(x, y)
    local o = ISCollapsableWindow.new(self, x, y, 610, 690)
    o.title = "Project Viewpoint - slider calibrator"
    o.resizable = false
    o.rangeLevel = 1
    o.rows = {}
    return o
end

function PVADSGaelSliderWindow:rangeFor(row, centre)
    row.centre = centre
    local span = row.field[3] * 200 * RANGES[self.rangeLevel]
    row.slider:setValues(centre - span, centre + span, row.field[3], row.field[3], true)
    row.slider:setCurrentValue(centre, true)
end

function PVADSGaelSliderWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:titleBarHeight() + 7
    local bh = getTextManager():getFontHeight(UIFont.Small) + 7
    for i, field in ipairs(FIELDS) do
        if i == 12 then y = y + 16; self.pipY = y - 13 end
        local entry = ISTextEntryBox:new(string.format("%.5f", current(field)), 117, y, 83, bh)
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
        self:rangeFor(row, current(field))
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
    button(498, "Save", PVADSGaelSliderWindow.onSave)
    y = y + bh + 4
    button(8, "Probe", PVADSGaelSliderWindow.onProbe)
    button(106, "Validate", PVADSGaelSliderWindow.onValidate)
    button(498, "Close", PVADSGaelSliderWindow.close)
    self.infoY = y + bh + 10
    self:setHeight(self.infoY + 48)
end

function PVADSGaelSliderWindow:onSlide(amount, slider)
    local row = self.rows[slider.pvRow]
    if not row then return end
    if apply(row.field, amount) then
        row.entry:setText(string.format("%.5f", amount))
        self.message = row.field[2] .. " = " .. string.format("%.5f", amount)
    end
end

function PVADSGaelSliderWindow:applyTyped(box)
    local row = self.rows[box.pvRow]
    local amount = tonumber(box:getText())
    if not amount then
        box:setText(string.format("%.5f", current(row.field)))
        self.message = "Enter a number"
        return
    end
    if math.abs(amount - current(row.field)) > 0.0000001 and apply(row.field, amount) then
        self:rangeFor(row, amount)
    end
end

function PVADSGaelSliderWindow:onRange()
    self.rangeLevel = self.rangeLevel % #RANGES + 1
    self.rangeButton:setTitle("Range x" .. RANGES[self.rangeLevel])
    self:onCenter()
end

function PVADSGaelSliderWindow:onCenter()
    for _, row in ipairs(self.rows) do self:rangeFor(row, current(row.field)) end
end

function PVADSGaelSliderWindow:onHold()
    PVADS.Controller.forceADS = not PVADS.Controller.forceADS
    self.holdButton:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
    if Cal.window and Cal.window.btnHold then
        Cal.window.btnHold:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
    end
end

function PVADSGaelSliderWindow:onReset()
    local key = selected()
    if not key then return end
    PVADS.User[key] = nil
    PVADS.Controller.refresh(true)
    self:onCenter()
    self.message = "Reset " .. key
end

function PVADSGaelSliderWindow:onCopy()
    local snippet = Cal.snippet()
    Clipboard.setClipboard(snippet)
    self.message = "Copied current profile"
end

function PVADSGaelSliderWindow:onSave()
    self.message = PVADS.saveUserProfiles() and "Saved to PVADS_UserProfiles.txt" or "Save failed"
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
    if key ~= self.lastKey then self.lastKey = key; self:onCenter() end
    if self.pipY then self:drawText("Picture-in-picture (scopes / red dots)", 8, self.pipY, 0.55, 0.85, 1, 1, UIFont.Small) end
    for _, row in ipairs(self.rows) do
        self:drawText(row.field[2], 8, row.y + 3, 1, 1, 1, 1, UIFont.Small)
        local n = current(row.field)
        if not row.slider.dragInside then
            if n < row.slider.minValue or n > row.slider.maxValue then self:rangeFor(row, n)
            else row.slider:setCurrentValue(n, true) end
        end
        if not row.entry:isFocused() then
            local displayed = string.format("%.5f", n)
            if row.entry:getText() ~= displayed then row.entry:setText(displayed) end
        end
    end
    self:drawText(key or "No firearm equipped", 8, self.infoY, 0.85, 0.85, 0.85, 1, UIFont.Small)
    if self.holdButton then
        self.holdButton:setTitle(PVADS.Controller.forceADS and "Release" or "Hold ADS")
    end
    if self.message then self:drawText(self.message, 8, self.infoY + 18, 1, 0.9, 0.4, 1, UIFont.Small) end
end

local function install()
    if not Cal or Cal.gaelSliderInstalled then return end
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
end

Events.OnGameStart.Add(install)
