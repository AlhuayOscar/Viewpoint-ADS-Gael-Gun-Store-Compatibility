-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "ISUI/ISUIElement"
require "PVADS/PVADS_Locale"
local L = PVADS.L
require "PVADS/PVADS_Controller"

--[[
Optic overlay. Draws only what the 3D view cannot: the collimated reticle inside a reflex window and
the lens of a magnified scope (mask, reticle, eye-box shadow). Positions come from the Java side,
which projects the real sight axis and optic window of the aligned weapon model every frame, so the
reticle moves with the gun (recoil, inertia) instead of sitting on the screen centre.
Click-through: the element never consumes mouse input.
]]

PVADSOverlay = ISUIElement:derive("PVADSOverlay")

local TEX = {}
-- reticle textures by reticle name (no string building per frame)
local RET, GLOW = {}, {}
local function tex(name)
    local t = TEX[name]
    if t == nil then
        t = getTexture("media/textures/PVADS/" .. name .. ".png") or false
        TEX[name] = t
    end
    return t or nil
end
PVADS.texture = tex
local function retTex(name)
    local t = RET[name]
    if t == nil then t = tex("ret_" .. name) or false; RET[name] = t end
    return t or nil
end
local function glowTex(name)
    local t = GLOW[name]
    if t == nil then t = tex("ret_" .. name .. "_glow") or false; GLOW[name] = t end
    return t or nil
end

local state = {}

function PVADSOverlay:new()
    local o = ISUIElement.new(self, 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    o.anchorRight = true; o.anchorBottom = true
    return o
end

function PVADSOverlay:initialise()
    ISUIElement.initialise(self)
end

function PVADSOverlay:instantiate()
    ISUIElement.instantiate(self)
    self.javaObject:setConsumeMouseEvents(false)
end

function PVADSOverlay:onMouseDown() return false end
function PVADSOverlay:onMouseUp() return false end
function PVADSOverlay:onRightMouseDown() return false end
function PVADSOverlay:onRightMouseUp() return false end
function PVADSOverlay:onMouseWheel() return false end

local function color()
    local p = PVADS.Controller.profile
    if p and p.color then return p.color end
    return PVADS.ReticleColors[PVADS.Settings.color or 1] or PVADS.ReticleColors[1]
end

function PVADSOverlay:prerender()
    local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= w or self.height ~= h then self:setWidth(w); self:setHeight(h) end
end

function PVADSOverlay:drawScope(p, k)
    local cx, cy, R = state.lensX, state.lensY, state.lensR
    local eb = state.eyeBox or 1
    local r = R * (0.72 + 0.28 * eb)                 -- the visible exit pupil shrinks when misaligned
    local w, h = self.width, self.height
    local a = k
    -- black outside the lens. Whole pixels, and each rect reaches 3 px under the lens ring: the ring
    -- texture's outermost texels filter to transparent, which left see-through seams when the lens moved.
    local x0, y0 = math.floor(cx - r), math.floor(cy - r)
    local x1, y1 = math.ceil(cx + r), math.ceil(cy + r)
    local o = 3
    self:drawRect(0, 0, w, math.max(0, y0 + o), a, 0, 0, 0)
    self:drawRect(0, y1 - o, w, math.max(0, h - y1 + o), a, 0, 0, 0)
    self:drawRect(0, y0 + o, math.max(0, x0 + o), y1 - y0 - 2 * o, a, 0, 0, 0)
    self:drawRect(x1 - o, y0 + o, math.max(0, w - x1 + o), y1 - y0 - 2 * o, a, 0, 0, 0)
    -- lens edge vignette (soft round mask) and reticle
    local ring = tex("lens_mask")
    if ring then self:drawTextureScaled(ring, x0, y0, x1 - x0, y1 - y0, a, 1, 1, 1) end
    local ret = p.reticle and p.reticle ~= "none" and retTex(p.reticle)
    if ret and p.reticle == "dot" then
        -- 1x red dot: a small illuminated dot in the middle of the lens, same size as on a reflex sight
        local c = color(); local br = PVADS.Settings.brightness or 1
        local size = math.max(7, self.height * 0.0105) * (p.reticleScale or 1)
        self:drawTextureScaled(ret, cx - size / 2, cy - size / 2, size, size, math.min(1, a * br), c.r, c.g, c.b)
        ret = nil
    end
    if ret then
        -- second-focal-plane reticle: centred on the optic axis, constant size on screen
        local rr = R * 0.98
        local b = math.min(1, a * (0.35 + 0.65 * eb))
        self:drawTextureScaled(ret, cx - rr, cy - rr, 2 * rr, 2 * rr, b, 0.03, 0.03, 0.03)
        local glow = glowTex(p.reticle)
        if glow then
            local c = color(); local br = PVADS.Settings.brightness or 1
            self:drawTextureScaled(glow, cx - rr, cy - rr, 2 * rr, 2 * rr, math.min(1, b * br * 0.9), c.r, c.g, c.b)
        end
    end
    -- eye box: crescent shadow grows as the eye leaves the optic axis
    if eb < 0.999 then
        local sh = tex("eyebox_shadow")
        if sh then self:drawTextureScaled(sh, x0, y0, x1 - x0, y1 - y0, a * (1 - eb), 1, 1, 1) end
    end
end

-- picture-in-picture: the zoomed picture is drawn into the lens by the Java side; only the ring and the
-- reticle are added here, and nothing outside the lens is blacked out
function PVADSOverlay:drawPip(p, k)
    -- the lens and its reticle are drawn by the Java pass in the same frame as the world (so they never trail
    -- the eyepiece while turning); this only hands over which reticle and colour to use
    if not PVADS_setPipReticle then return end
    local c = color(); local br = PVADS.Settings.brightness or 1
    local name = p.reticle
    if not name or name == "none" then PVADS_setPipReticle(nil, nil, 0, 0, 0, 0, 0, 0); return end
    local ret = retTex(name)
    local mode = name == "dot" and 2 or 1
    local size = math.max(7, self.height * 0.0105) * (p.reticleScale or 1)
    PVADS_setPipReticle(ret, mode == 1 and glowTex(name) or nil, mode, c.r, c.g, c.b, br, size)
end

function PVADSOverlay:drawReflex(p, k)
    if not p.reticle or p.reticle == "none" then return end
    local dx, dy = state.dotX, state.dotY
    local wx, wy, wr = state.winX, state.winY, state.winR
    if wr and wr > 1 then
        local d = math.sqrt((dx - wx) ^ 2 + (dy - wy) ^ 2)
        local edge = wr * 0.92
        if d > edge then
            k = k * math.max(0, 1 - (d - edge) / (wr * 0.15))   -- the dot only exists inside the glass
        end
    end
    if k <= 0.01 then return end
    local t = retTex(p.reticle) or retTex("dot")
    if not t then return end
    local c = color()
    local br = PVADS.Settings.brightness or 1
    local size = math.max(7, self.height * 0.0105) * (p.reticleScale or 1)
    if p.reticle ~= "dot" then size = size * 4 end
    self:drawTextureScaled(t, dx - size / 2, dy - size / 2, size, size, math.min(1, k * br), c.r, c.g, c.b)
end

local pres = {}
local function dotLine(self, x0, y0, x1, y1, r, g, b)
    local dx, dy = x1 - x0, y1 - y0
    local n = math.min(60, math.floor(math.sqrt(dx * dx + dy * dy) / 6))
    for i = 0, n do
        local k = n > 0 and i / n or 0
        self:drawRect(x0 + dx * k - 1, y0 + dy * k - 1, 3, 3, 0.9, r, g, b)
    end
end
local function onScreen(x) return x and x > -9000 end

--- Developer view of the physical weapon presence (Options > Developer > Debug weapon collision).
function PVADSOverlay:drawPresenceDebug()
    if not PVADS_getPresence then return end
    PVADS_getPresence(pres)
    if not pres.debug or not pres.valid then return end
    local a = pres.amount or 0
    if onScreen(pres.rx) and onScreen(pres.mx) then dotLine(self, pres.rx, pres.ry, pres.mx, pres.my, 0.2, 1, 0.2) end
    if onScreen(pres.px) then self:drawRect(pres.px - 4, pres.py - 4, 9, 9, 0.9, 1, 1, 0) end
    if onScreen(pres.mx) then self:drawRect(pres.mx - 4, pres.my - 4, 9, 9, 0.9, 0, 0.6, 1) end
    if onScreen(pres.hx) then self:drawRect(pres.hx - 6, pres.hy - 6, 13, 13, 0.9, 1, 0.1, 0.1) end
    local x, y, fh = 20, self.height * 0.25, 18
    local lines = {
        string.format(L("Weapon presence: amount %.2f  view block %.2f  sight %s", "Presencia del arma: nivel %.2f  bloqueo de vista %.2f  mira %s"), a, pres.viewBlock or 0, pres.adsBlocked and L("BLOCKED", "BLOQUEADA") or L("free", "libre")),
        string.format(L("probe: %s  need %.2f m  hit at %.2f m", "sondeo: %s  requiere %.2f m  impacto a %.2f m"), tostring(pres.type), pres.need or 0, pres.hitDist or 0),
        string.format(L("gun: %.2f m (%s, %s)  pose pitch %.1f  yaw %.1f deg", "arma: %.2f m (%s, %s)  inclinación %.1f  giro %.1f grados"), pres.length or 0, tostring(pres.source), tostring(pres.family), pres.pitch or 0, pres.yaw or 0),
    }
    self:drawRect(x - 6, y - 4, 520, #lines * fh + 8, 0.55, 0, 0, 0)
    for i, l in ipairs(lines) do self:drawText(l, x, y + (i - 1) * fh, 1, 1, 1, 1, UIFont.Small) end
    self:drawRect(x, y + #lines * fh + 2, 200 * math.min(1, a), 4, 0.9, 1, 0.3 + 0.7 * (1 - a), 0.2)
end

-- 1.6.0: zoom / zero readout, lower right, for a moment after either changes (PVADS_Scope)
function PVADSOverlay:drawScopeHud()
    local hud = PVADS.Scope and PVADS.Scope.hud()
    if not hud then return end
    local parts = {}
    if hud.zoom then parts[#parts + 1] = hud.zoom end
    if hud.zero then parts[#parts + 1] = L("Zero ", "Cero: ") .. hud.zero end
    local text = table.concat(parts, "   ")
    local font = UIFont.Medium
    local tm = getTextManager()
    local tw, th = tm:MeasureStringX(font, text), tm:getFontHeight(font)
    local pad = 8
    local x = self.width - tw - pad * 2 - math.floor(self.width * 0.03)
    local y = self.height - th - pad * 2 - math.floor(self.height * 0.12)
    self:drawRect(x, y, tw + pad * 2, th + pad * 2, 0.45 * hud.alpha, 0, 0, 0)
    self:drawText(text, x + pad, y + pad, 0.92, 0.95, 0.9, hud.alpha, font)
end

--- 1.8.7 steady aim: a thin breath bar low in the middle of the screen while the breath is used or comes back.
local steadyState = {}
function PVADSOverlay:drawBreath()
    if not PVADS_getSteady or not PVADS.Settings.steady then return end
    PVADS_getSteady(steadyState)
    local breath, steady = steadyState.breath or 1, steadyState.steady or 0
    local now = getTimestampMs()
    if breath < 0.995 or steady > 0.02 then self.breathSeen = now end
    local since = self.breathSeen and (now - self.breathSeen) or 1e9
    local a = since < 600 and 1 or math.max(0, 1 - (since - 600) / 400)
    if a <= 0 then return end
    local bw, bh = math.floor(math.max(120, self.width * 0.07)), 3
    local x, y = math.floor((self.width - bw) / 2), math.floor(self.height * 0.86)
    self:drawRect(x - 1, y - 1, bw + 2, bh + 2, 0.35 * a, 0, 0, 0)
    local r, g, b = 0.92, 0.95, 0.9
    if breath < 0.2 then r, g, b = 1, 0.35, 0.3 end
    self:drawRect(x, y, math.floor(bw * math.max(0, math.min(1, breath)) + 0.5), bh, (0.45 + 0.4 * steady) * a, r, g, b)
end

--- 1.9.0 weapon rest: a small word next to the breath bar while the gun rests (sights up)
local restState = {}
local REST_WORDS = { [1] = L("PRONE", "TENDIDO"), [2] = L("RESTED", "APOYADO"), [3] = L("BIPOD", "BÍPODE") }
function PVADSOverlay:drawRest()
    if not PVADS_getRest or not PVADS.Settings.rest then return end
    PVADS_getRest(restState)
    local word = REST_WORDS[math.floor(tonumber(restState.used) or 0)]
    if not word then return end
    local font = UIFont.Small
    local tm = getTextManager()
    local tw = tm:MeasureStringX(font, word)
    local x, y = math.floor((self.width - tw) / 2), math.floor(self.height * 0.86) + 8
    self:drawText(word, x, y, 0.92, 0.95, 0.9, 0.75, font)
end

function PVADSOverlay:render()
    if not PVADS_getState or not PVADS.Controller.ready then return end
    if PVADS.Settings.presenceDebug and PVADS.Settings.developer then self:drawPresenceDebug() end
    self:drawScopeHud()
    PVADS_getState(state)
    if (state.t or 0) > 0 then self:drawBreath(); self:drawRest() end
    if not state.visible then return end
    local p = PVADS.Controller.profile
    if not p then return end
    local t = state.t or 0
    if state.mode == 2 then
        -- the lens exists only while the scope is fully up: quick fade in, instant hide when lowering
        if state.lensUp then
            local now = getTimestampMs()
            self.lensSince = self.lensSince or now
            local k = math.min(1, (now - self.lensSince) / 120)
            if state.pipMode then if state.pip then self:drawPip(p, k) end; return end
            -- Use the actual projected optic position. Do not pin the lens
            -- mask to screen centre: it must move with the weapon and recoil.
            self:drawScope(p, k)
        else
            self.lensSince = nil
        end
    elseif state.mode == 1 then
        local k = math.min(1, math.max(0, (t - 0.6) / 0.4))
        if k > 0 then self:drawReflex(p, k) end
    end
    if PVADS.Settings.developer and PVADS.Calibrator and PVADS.Calibrator.window and PVADS.Calibrator.window:isVisible() then
        -- calibration aid: true screen centre (Viewpoint's aim ray) and the gun's sight axis
        local cx, cy = self.width / 2, self.height / 2
        self:drawRect(cx - 8, cy, 17, 1, 0.9, 0, 1, 1)
        self:drawRect(cx, cy - 8, 1, 17, 0.9, 0, 1, 1)
        self:drawRect(state.dotX - 3, state.dotY - 3, 7, 7, 0.9, 1, 0, 1)
    end
end

local function create()
    if PVADS.overlay then return end
    local o = PVADSOverlay:new()
    o:initialise()
    o:instantiate()
    o:addToUIManager()
    o:setAlwaysOnTop(false)
    o:backMost()
    o:setVisible(false)
    PVADS.overlay = o
end

--[[
1.5.7: the overlay is a full-screen element. The game decides "is the mouse over this window" by checking whether any
top-level element ABOVE it covers that point (zombie.ui.UIElement.isPointOver), whatever that element does with clicks.
Whenever the overlay ended up above the inventory windows, they stopped scrolling and accepting dropped items.
Invisible elements are skipped by that test, so the overlay is only visible while it has something to draw (sights up,
the calibrator aid or the presence debug view), and it is pushed to the back of the UI each time it is shown.
]]
local probe = {}
local function overlayWanted()
    if not PVADS.Controller.ready or not PVADS_getState then return false end
    local s = PVADS.Settings
    if s.presenceDebug and s.developer then return true end
    if s.developer and PVADS.Calibrator and PVADS.Calibrator.window and PVADS.Calibrator.window:isVisible() then return true end
    if PVADS.Scope and PVADS.Scope.hud() then return true end
    PVADS_getState(probe)
    return probe.visible == true or probe.lensUp == true or (probe.t or 0) > 0
end

local backTick = 0
local function updateVisibility()
    local o = PVADS.overlay
    if not o then return end
    local want = overlayWanted()
    if want ~= o:isVisible() then
        o:setVisible(want)
        if want then o:backMost(); backTick = 0 end
    elseif want then
        backTick = backTick + 1
        if backTick >= 60 then backTick = 0; o:backMost() end   -- stay behind windows opened meanwhile
    end
end

Events.OnGameStart.Add(create)
Events.OnTick.Add(updateVisibility)
Events.OnResolutionChange.Add(function()
    if PVADS.overlay then PVADS.overlay:setWidth(getCore():getScreenWidth()); PVADS.overlay:setHeight(getCore():getScreenHeight()) end
end)
