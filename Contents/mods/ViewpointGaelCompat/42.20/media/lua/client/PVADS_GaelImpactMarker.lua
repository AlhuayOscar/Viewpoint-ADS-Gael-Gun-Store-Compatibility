require "ISUI/ISPanel"

local ImpactMarker = ISPanel:derive("PVADSGaelImpactMarker")

function ImpactMarker:new()
    local core = getCore()
    local o = ISPanel.new(self, 0, 0, core:getScreenWidth(), core:getScreenHeight())
    o.background = false
    o.border = false
    o:noBackground()
    return o
end

function ImpactMarker:isMouseOver()
    return false
end

function ImpactMarker:instantiate()
    ISPanel.instantiate(self)
    self.javaObject:setConsumeMouseEvents(false)
end

function ImpactMarker:onMouseDown()
    return false
end

function ImpactMarker:onMouseUp()
    return false
end

function ImpactMarker:render()
    local core = getCore()
    if self.width ~= core:getScreenWidth() then self:setWidth(core:getScreenWidth()) end
    if self.height ~= core:getScreenHeight() then self:setHeight(core:getScreenHeight()) end
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    if not aim or not aim.impactVisible then return end
    local ok, visible = pcall(aim.impactVisible)
    if not ok or visible ~= true then return end
    local okX, x = pcall(aim.impactScreenX)
    local okY, y = pcall(aim.impactScreenY)
    if not okX or not okY then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x ~= x or y ~= y then return end

    -- Black outline keeps the real impact marker legible over bright surfaces.
    self:drawRect(x - 7, y - 7, 15, 15, 0.95, 0.02, 0.05, 0.02)
    self:drawRect(x - 4, y - 4, 9, 9, 1.00, 0.10, 1.00, 0.20)
    local label = ""
    local okLabel, value = pcall(aim.impactLabel)
    if okLabel and value then label = tostring(value) end
    if label ~= "" then
        local width = getTextManager():MeasureStringX(UIFont.Small, label)
        local left = math.min(getCore():getScreenWidth() - width - 12, x + 11)
        self:drawText(label, left, y + 8, 0.10, 1.00, 0.20, 1.00, UIFont.Small)
    end
end

local function installImpactMarker()
    if PVADS and PVADS.gaelImpactMarker then return end
    local marker = ImpactMarker:new()
    marker:initialise()
    marker:instantiate()
    -- Keep this full-screen drawing panel behind real UI windows. Click-through
    -- alone is insufficient because the UI hover test also considers z-order.
    marker:setAlwaysOnTop(false)
    marker:addToUIManager()
    marker:backMost()
    marker:setVisible(false)
    PVADS = PVADS or {}
    PVADS.gaelImpactMarker = marker
end

local function updateImpactMarkerVisibility()
    local marker = PVADS and PVADS.gaelImpactMarker
    if not marker then return end
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    local shouldShow = false
    if aim and aim.impactVisible then
        local ok, visible = pcall(aim.impactVisible)
        shouldShow = ok and visible == true
    end
    if marker:isVisible() ~= shouldShow then
        marker:setVisible(shouldShow)
        if shouldShow then marker:backMost() end
    end
end

Events.OnGameStart.Add(installImpactMarker)
Events.OnTick.Add(updateImpactMarkerVisibility)
