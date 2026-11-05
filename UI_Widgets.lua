local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local W = FS.W

local WHITE = "Interface\\Buttons\\WHITE8x8"
W.FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
W.SOFT = { bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
           insets = { left = 3, right = 3, top = 3, bottom = 3 } }

function W.Pal() return FS.UI:GetActivePalette() end
function W.FontPath() return FS.Style.FontPath and FS.Style:FontPath(FS.db.profile.font) or FS.UI:GetActiveFont() end
function W.FontFlags()
    local o = FS.db and FS.db.profile.fontOutline
    return (o and o ~= "none") and o or ""
end
W.texts = setmetatable({}, { __mode = "k" }) -- every text the addon made (follows the chosen font)
function W.TextSize() return tonumber(FS.db.profile.textSize) or 12 end

---------------------------------------------------------------------------
-- Number / text formatting (WoW fonts have no emoji, so labels are words
-- and inline |T icons instead of the blueprint's emoji).
---------------------------------------------------------------------------

function W.Num(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

function W.Short(n)
    n = tonumber(n) or 0
    if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return W.Num(n)
end

function W.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s = math.floor(copper / 10000), math.floor((copper % 10000) / 100)
    if g >= 1000 then return string.format("|cffffd100%sg|r", W.Num(g)) end -- big amounts: gold only, so it fits
    if g > 0 then return string.format("|cffffd100%sg|r |cffc0c0c0%02ds|r", W.Num(g), s) end
    return string.format("|cffc0c0c0%ds|r |cffcd7f32%02dc|r", s, copper % 100)
end

function W.Duration(sec)
    sec = math.floor(tonumber(sec) or 0)
    local d, h, m = math.floor(sec / 86400), math.floor((sec % 86400) / 3600), math.floor((sec % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

-- Distances are stored in metres. Shown as m / km (metric, default) or yd / mi.
local METERS_PER_YARD, YARDS_PER_MILE = 0.9144, 1760
W.METERS_PER_STEP = 1.4 -- a running character's stride; steps are an estimate

function W.Distance(meters)
    meters = tonumber(meters) or 0
    if FS.db and FS.db.profile.distanceUnits == "imperial" then
        local yards = meters / METERS_PER_YARD
        if yards < YARDS_PER_MILE then return W.Num(yards) .. " yd" end
        return string.format("%s mi", W.Decimal(yards / YARDS_PER_MILE))
    end
    if meters < 1000 then return W.Num(meters) .. " m" end
    return string.format("%s km", W.Decimal(meters / 1000))
end

function W.Decimal(n)
    n = tonumber(n) or 0
    local whole = math.floor(n)
    return W.Num(whole) .. string.format(".%d", math.floor((n - whole) * 10))
end

function W.Steps(meters)
    return W.Num((tonumber(meters) or 0) / W.METERS_PER_STEP) .. " steps"
end

function W.ShowSteps() return not FS.db or FS.db.profile.showSteps ~= false end

-- "3m 25s" for short fights.
function W.FightTime(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 60 then return sec .. "s" end
    return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
end

function W.Ago(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return "never" end
    local diff = time() - ts
    if diff < 90 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. " min ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. " h ago" end
    return math.floor(diff / 86400) .. " days ago"
end

function W.Date(ts) return ts and date("%d.%m.%Y %H:%M", ts) or "-" end

function W.FormatStat(key, value)
    local def = FS.STATS[key]
    local fmt = def and def.fmt or "num"
    value = tonumber(value) or 0
    if fmt == "gs" then return W.Num(value) .. " GS" end
    if fmt == "ilvl" then return string.format("%.1f", value) end
    if fmt == "lp" then return W.Num(value) .. " " .. FS.POINTS.short end
    if fmt == "duration" then return W.Duration(value) end
    if fmt == "minutes" then return W.Num(value) .. " min" end
    if fmt == "money" then return W.Money(value) end
    if fmt == "short" then return W.Short(value) end
    if fmt == "distance" then return W.Distance(value) end
    return W.Num(value)
end

W.QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff" }
W.RANK_HEX = { "ffd100", "d8d8d8", "e0884a" }

function W.Color(text, hex) return "|cff" .. hex .. tostring(text) .. "|r" end

function W.ClassHex(cls)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls or ""]
    if c and c.colorStr then return c.colorStr:sub(3) end
    return (FS.UI.CLASS_COLORS and FS.UI.CLASS_COLORS[cls or ""]) or "ffffff"
end

function W.ClassName(cls)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls or ""]) or tostring(cls or "?")
end

function W.GsHex(gs, ilvl)
    -- Colour GearScore like item quality, relative to this game's best item level
    -- (about 66 in Era/Forever, 141 in TBC, 496 in Mists).
    local share = (tonumber(ilvl) or 0) / (FS.GAME_INFO.ilvlTop or 66)
    if share >= 0.9 then return W.QUALITY_HEX[4] end
    if share >= 0.55 then return W.QUALITY_HEX[3] end
    if share >= 0.3 then return W.QUALITY_HEX[2] end
    return "cccccc"
end

-- Faction / ruleset badge, e.g. "H•PvE". Shown on network lists only, like the blueprint.
function W.Badge(rec, force)
    if not rec or not rec.ruleset then return "" end
    if not force then
        local scope = FS.UI.currentScope
        if FS.db.profile.showBadges == false or (scope ~= "network" and scope ~= "netaccs") then return "" end
    end
    local side, kind = tostring(rec.ruleset):match("^(%a)%-(.+)$")
    if not side then return "" end
    local hex = side == "A" and "3399ff" or "ff4444"
    return " |cff" .. hex .. side .. "\226\128\162" .. kind .. "|r"
end

function W.CharName(rec)
    if not rec then return "?" end
    if rec.isAccount then return W.Color(rec.owner or "?", "ffffff") end
    return W.Color(FS.ShortName(rec.fullName), W.ClassHex(rec.cls))
end

-- "Name (Owner) H•PvE"
function W.Label(rec, opts)
    opts = opts or {}
    local out = W.CharName(rec)
    if not rec or rec.isAccount then
        if rec and rec.isAccount then out = out .. W.Color(" (" .. (rec.charCount or 0) .. " chars)", "888888") end
        return out .. W.Badge(rec)
    end
    if opts.owner ~= false and rec.owner then out = out .. W.Color(" (" .. rec.owner .. ")", "888888") end
    return out .. W.Badge(rec)
end

---------------------------------------------------------------------------
-- Theming: every themed frame registers here so a theme change reskins all.
---------------------------------------------------------------------------

W.themed = {}

local function ApplyRole(frame, role)
    local pal = W.Pal()
    local Style = FS.Style
    local edge = Style.BorderColour and Style:BorderColour(pal) or pal.border
    -- Non-flat boxes follow the chosen border style and card style.
    if not frame.flatBox and Style.CardBackdrop and FS.db then
        local bd = Style:CardBackdrop()
        if frame.appliedBackdrop ~= bd then frame:SetBackdrop(bd); frame.appliedBackdrop = bd end
    end
    local bold = FS.db and FS.db.profile.cardStyle == "bold"
    if role == "panel" then
        frame:SetBackdropColor(pal.bg[1] * 0.7, pal.bg[2] * 0.7, pal.bg[3] * 0.7, 0.9)
        frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], 0.9)
    elseif role == "card" then
        frame:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
        local c = bold and pal.accent or edge
        frame:SetBackdropBorderColor(c[1], c[2], c[3], bold and 1 or 0.85)
        if FS.db and FS.db.profile.glowCards then
            W.SetGlow(frame, "glow", pal.accent, 0.35 * math.max(0.3, tonumber(FS.db.profile.glow) or 0), 8, FS.db.profile.glowPulse)
        elseif frame.fsGlow_glow then
            W.SetGlow(frame, "glow", pal.accent, 0)
        end
    elseif role == "header" then
        frame:SetBackdropColor(0.12, 0.12, 0.14, 1)
        frame:SetBackdropBorderColor(edge[1] * 0.6, edge[2] * 0.6, edge[3] * 0.6, 1)
    elseif role == "pill" then
        frame:SetBackdropColor(0, 0, 0, 0.45)
        frame:SetBackdropBorderColor(edge[1] * 0.75, edge[2] * 0.75, edge[3] * 0.75, 1)
    elseif role == "accent" then
        frame:SetBackdropColor(pal.accent[1] * 0.18, pal.accent[2] * 0.18, pal.accent[3] * 0.18, 0.95)
        frame:SetBackdropBorderColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
    end
end

-- Soft glow (or shadow) around a frame: four gradient strips plus faint corners,
-- optionally pulsing. key separates layers ("glow", "shadow").
local function Gradient(tex, orientation, c, a1, a2)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(c[1], c[2], c[3], a1), CreateColor(c[1], c[2], c[3], a2))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
    else
        tex:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2)
    end
end

function W.SetGlow(frame, key, colour, strength, size, pulse)
    local field = "fsGlow_" .. key
    local g = frame[field]
    strength = tonumber(strength) or 0
    if strength <= 0 then
        if g then g:Hide(); if g.anim then g.anim:Stop() end end
        return
    end
    if not g then
        g = CreateFrame("Frame", nil, frame)
        g:SetAllPoints()
        g:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
        g.t = {}
        for _, part in ipairs({ "top", "bottom", "left", "right", "tl", "tr", "bl", "br" }) do
            g.t[part] = g:CreateTexture(nil, "BACKGROUND")
            g.t[part]:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
        frame[field] = g
    end
    size = tonumber(size) or 14
    local t, a = g.t, math.min(1, strength)
    local function Place(tex, p1, rel1, x1, y1, p2, rel2, x2, y2)
        tex:ClearAllPoints()
        tex:SetPoint(p1, frame, rel1, x1, y1)
        tex:SetPoint(p2, frame, rel2, x2, y2)
    end
    Place(t.top, "BOTTOMLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, size)
    Place(t.bottom, "TOPLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -size)
    Place(t.left, "TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", -size, 0)
    Place(t.right, "TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", size, 0)
    Place(t.tl, "BOTTOMRIGHT", "TOPLEFT", 0, 0, "TOPLEFT", "TOPLEFT", -size, size)
    Place(t.tr, "BOTTOMLEFT", "TOPRIGHT", 0, 0, "TOPRIGHT", "TOPRIGHT", size, size)
    Place(t.bl, "TOPRIGHT", "BOTTOMLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", -size, -size)
    Place(t.br, "TOPLEFT", "BOTTOMRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", size, -size)
    Gradient(t.top, "VERTICAL", colour, a, 0)
    Gradient(t.bottom, "VERTICAL", colour, 0, a)
    Gradient(t.left, "HORIZONTAL", colour, 0, a)
    Gradient(t.right, "HORIZONTAL", colour, a, 0)
    for _, c in ipairs({ "tl", "tr" }) do Gradient(t[c], "VERTICAL", colour, a * 0.45, 0) end
    for _, c in ipairs({ "bl", "br" }) do Gradient(t[c], "VERTICAL", colour, 0, a * 0.45) end
    g:Show()
    if pulse then
        if not g.anim and g.CreateAnimationGroup then
            g.anim = g:CreateAnimationGroup()
            local fade = g.anim:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.35)
            fade:SetDuration(1.2)
            if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
            g.anim:SetLooping("BOUNCE")
        end
        if g.anim and not g.anim:IsPlaying() then g.anim:Play() end
    elseif g.anim then
        g.anim:Stop()
        g:SetAlpha(1)
    end
end

function W.Box(parent, role, flat)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(flat and W.FLAT or W.SOFT)
    f.flatBox = flat
    f.themeRole = role or "card"
    table.insert(W.themed, f)
    ApplyRole(f, f.themeRole)
    return f
end

function W.Reskin()
    for _, f in ipairs(W.themed) do
        if f.UpdateLook then f:UpdateLook() elseif f.themeRole then ApplyRole(f, f.themeRole) end
    end
end

function W.Text(parent, template, justify, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    if size then fs:SetFont(W.FontPath(), size, W.FontFlags()) end
    W.texts[fs] = true
    return fs
end

function W.AccentText(fs)
    local pal = W.Pal()
    fs:SetTextColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
end

---------------------------------------------------------------------------
-- Buttons, sub-tabs, checkboxes, search boxes
---------------------------------------------------------------------------

function W.Button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 120, height or 24)
    b:SetBackdrop(W.FLAT)
    b.text = W.Text(b, "GameFontNormalSmall", "CENTER")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetText(label)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    function b:SetActive(active) self.active = active; self:UpdateLook() end
    function b:UpdateLook()
        local pal = W.Pal()
        local pop = FS.db and math.max(0, math.min(1, tonumber(FS.db.profile.pop) or 0.4)) or 0.4
        if self.active then
            local k = 0.2 + 0.2 * pop
            self:SetBackdropColor(pal.accent[1] * k, pal.accent[2] * k, pal.accent[3] * k, 1)
            self:SetBackdropBorderColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
            self.text:SetTextColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
        else
            self:SetBackdropColor(0.10, 0.10, 0.12, 1)
            local e = FS.Style.Mix and FS.Style.Mix({ 0.30, 0.30, 0.30 }, pal.accent, pop * 0.5) or { 0.3, 0.3, 0.3 }
            self:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            self.text:SetTextColor(0.85, 0.85, 0.85, 1)
        end
    end
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    table.insert(W.themed, b)
    b:UpdateLook()
    return b
end

-- items: { {id=, label=}, ... }; width is the full bar width.
-- Sub-tabs sit in a framed tray with an accent line on top, so it is clear they
-- belong to the main tab above (the active main tab has a matching connector).
function W.SubTabs(parent, items, width, onSelect, height)
    height = height or 24
    local bar = W.Box(parent, "header", true)
    bar:SetSize(width, height + 8)
    bar.topLine = bar:CreateTexture(nil, "OVERLAY")
    bar.topLine:SetPoint("TOPLEFT")
    bar.topLine:SetPoint("TOPRIGHT")
    bar.topLine:SetHeight(2)
    local baseLook = bar.UpdateLook
    function bar:UpdateLook()
        local pal = W.Pal()
        self:SetBackdropColor(0.07, 0.07, 0.09, 1)
        self:SetBackdropBorderColor(pal.border[1] * 0.6, pal.border[2] * 0.6, pal.border[3] * 0.6, 1)
        self.topLine:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], 0.9)
    end
    bar:UpdateLook()
    bar.buttons = {}
    local gap = 4
    local inner = width - 8
    local w = (inner - gap * (#items - 1)) / #items
    for i, item in ipairs(items) do
        local btn = W.Button(bar, item.label, w, height, function() bar:Select(item.id) end)
        btn:SetPoint("LEFT", bar, "LEFT", 4 + (i - 1) * (w + gap), -1)
        btn.id = item.id
        bar.buttons[i] = btn
    end
    function bar:Select(id, silent)
        self.current = id
        for _, btn in ipairs(self.buttons) do btn:SetActive(btn.id == id) end
        if not silent and onSelect then onSelect(id) end
    end
    return bar
end

function W.Check(parent, label, onToggle)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.label = W.Text(cb, "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self) if onToggle then onToggle(self:GetChecked() and true or false) end end)
    return cb
end

function W.Search(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 24)
    box:SetBackdrop(W.FLAT)
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    box.hint = W.Text(box, "GameFontDisableSmall")
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetText(placeholder or "Search...")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        if onChange then onChange(text:lower()) end
    end)
    return box
end

-- Case-insensitive "does this character match the search text?"
function W.Matches(rec, query)
    if not query or query == "" then return true end
    local hay = table.concat({ tostring(rec.fullName or ""), tostring(rec.owner or ""), tostring(rec.zone or ""),
                               tostring(rec.gs or ""), tostring(rec.guildName or "") }, " "):lower()
    return hay:find(query, 1, true) ~= nil
end

function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    return scroll, content
end

---------------------------------------------------------------------------
-- Character tooltip
---------------------------------------------------------------------------

function W.CharTooltip(owner, rec)
    if not rec or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if rec.isAccount then
        GameTooltip:AddLine(rec.owner or "?", 1, 1, 1)
        GameTooltip:AddLine((rec.charCount or 0) .. " characters synced", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Last seen: " .. W.Ago(rec.lastUpdate), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(W.CharName(rec) .. W.Badge(rec, true))
        GameTooltip:AddLine(string.format("Level %s %s %s", tostring(rec.level or "?"), rec.race or "", W.ClassName(rec.cls)), 1, 1, 1)
        if rec.owner then GameTooltip:AddLine("Player: " .. rec.owner, 0.8, 0.8, 0.8) end
        if rec.guildName then GameTooltip:AddLine("<" .. rec.guildName .. ">", 0.25, 1, 0.25) end
        if rec.zone then GameTooltip:AddLine("Zone: " .. rec.zone, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(string.format("%s GS  -  %.1f iLvl", W.Num(rec.gs), tonumber(rec.ilvl) or 0), 0.64, 0.21, 0.93)
        for _, award in ipairs(FS.Officer.AwardsFor and FS.Officer:AwardsFor(rec.fullName) or {}) do
            GameTooltip:AddLine("Award: " .. tostring(award.title), 1, 0.82, 0)
        end
        local via = rec.isMyChar and "your account" or ({ bnet = "Battle.net friend", relay = "relayed by a guildmate", guild = "guild" })[rec.via or "guild"]
        GameTooltip:AddLine("Updated " .. W.Ago(rec.lastUpdate) .. "  -  via " .. tostring(via), 0.6, 0.6, 0.6)
        if rec.version then
            local newer = FS.CompareVersions(rec.version, FS.VERSION) > 0
            GameTooltip:AddLine("FellowshipSync " .. rec.version .. (newer and "  (newer than yours)" or ""),
                newer and 1 or 0.6, newer and 0.82 or 0.6, newer and 0 or 0.6)
        end
    end
    GameTooltip:AddLine("Click to inspect", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Ranked list: header + scrolling rows, built lazily from a row pool.
--   columns: { {label=, width=, justify=} ... }
--   rows:    { {cells={...}, rec=record, isSelf=bool} ... }
---------------------------------------------------------------------------

function W.List(parent, columns, opts)
    opts = opts or {}
    local list = { columns = columns, pool = {}, opts = opts, rowHeight = opts.rowHeight or 22 }
    local frame = CreateFrame("Frame", nil, parent)
    list.frame = frame

    local header = W.Box(frame, "header", true)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT", -24, 0)
    header:SetHeight(24)
    local x = 8
    for _, col in ipairs(columns) do
        col.base = col.base or col.width
        col.x = x
        local fs = W.Text(header, "GameFontNormalSmall", col.justify)
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(col.width)
        fs:SetText(col.label)
        col.headerText = fs
        x = x + col.width + 8
    end

    local scroll, content = W.ScrollArea(frame)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 0)
    list.scroll, list.content = scroll, content

    list.empty = W.Text(frame, "GameFontDisable", "CENTER")
    list.empty:SetPoint("TOP", header, "BOTTOM", 0, -40)
    list.empty:SetText(opts.emptyText or "Nothing here yet. Sync with your guild or type /fsync test for sample data.")

    -- Columns grow to fill the available width (never below their design size),
    -- so values are not cut off on a normal-sized window.
    list.fitWidth = 0
    function list:Layout()
        local width = (self.frame:GetWidth() or 0) - 24
        if width <= 0 or math.abs(width - self.fitWidth) < 1 then return end
        self.fitWidth = width
        local base = 0
        for _, col in ipairs(self.columns) do base = base + col.base end
        local scale = math.max(1, (width - 8 * (#self.columns + 1)) / math.max(1, base))
        local cx = 8
        for _, col in ipairs(self.columns) do
            col.x, col.width = cx, math.floor(col.base * scale)
            col.headerText:ClearAllPoints()
            col.headerText:SetPoint("LEFT", col.headerText:GetParent(), "LEFT", cx, 0)
            col.headerText:SetWidth(col.width)
            cx = cx + col.width + 8
        end
        for _, row in ipairs(self.pool) do
            for c, fs in ipairs(row.cells) do
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", self.columns[c].x, 0)
                fs:SetWidth(self.columns[c].width)
            end
        end
    end

    function list:SetColumnLabel(i, text) if self.columns[i] then self.columns[i].headerText:SetText(text) end end

    local function MakeRow(i)
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetHeight(list.rowHeight)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * (list.rowHeight + 2)))
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row:SetBackdrop(W.FLAT)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        row.selfBar = row:CreateTexture(nil, "ARTWORK")
        row.selfBar:SetPoint("TOPLEFT")
        row.selfBar:SetPoint("BOTTOMLEFT")
        row.selfBar:SetWidth(3)
        row.cells = {}
        for c, col in ipairs(columns) do
            local fs = W.Text(row, "GameFontHighlightSmall", col.justify)
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.width)
            row.cells[c] = fs
        end
        row:SetScript("OnClick", function(r) if r.rec and list.opts.onClick then list.opts.onClick(r.rec, r) end end)
        row:SetScript("OnEnter", function(r)
            local shown = false
            if r.rec and r.rec.fullName and not list.opts.noTooltip then W.CharTooltip(r, r.rec); shown = true end
            -- Anything cut off is shown in full in the tooltip.
            for c, fs in ipairs(r.cells) do
                if fs.IsTruncated and fs:IsTruncated() then
                    if not shown then GameTooltip:SetOwner(r, "ANCHOR_RIGHT"); shown = true end
                    GameTooltip:AddDoubleLine(list.columns[c].headerText:GetText() or "", fs:GetText() or "", 0.7, 0.7, 0.7, 1, 1, 1)
                end
            end
            if shown then GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        list.pool[i] = row
        return row
    end

    function list:SetRows(rows)
        self:Layout()
        content:SetWidth(math.max(scroll:GetWidth() or 0, 100))
        local pal, font, size = W.Pal(), W.FontPath(), W.TextSize()
        for i, data in ipairs(rows) do
            local row = self.pool[i] or MakeRow(i)
            row.rec = data.rec
            for c, fs in ipairs(row.cells) do
                fs:SetFont(font, size, W.FontFlags())
                fs:SetText(data.cells[c] or "")
            end
            local shade = (i % 2 == 0) and 0.085 or 0.06
            row:SetBackdropColor(shade, shade, shade + 0.01, 0.8)
            row:SetBackdropBorderColor(0, 0, 0, 0)
            if data.isSelf then
                row.selfBar:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], 0.9)
                row:SetBackdropColor(pal.accent[1] * 0.12, pal.accent[2] * 0.12, pal.accent[3] * 0.12, 0.9)
            else
                row.selfBar:SetColorTexture(0, 0, 0, 0)
            end
            row:Show()
        end
        for i = #rows + 1, #self.pool do self.pool[i]:Hide(); self.pool[i].rec = nil end
        content:SetHeight(math.max(10, #rows * (self.rowHeight + 2)))
        self.empty:SetShown(#rows == 0)
        self:FitColumns(#rows)
    end

    -- Sizes every column to its longest text (header included), gives spare room to the
    -- name column, and only shrinks columns when the list really can't fit everything.
    function list:FitColumns(rowCount)
        local cols = self.columns
        local avail = math.max(200, (scroll:GetWidth() or 960) - 16)
        local gap, widths, total = 8, {}, 0
        for c, col in ipairs(cols) do
            local w = (col.headerText:GetStringWidth() or 0) + 8
            for i = 1, math.min(rowCount, 300) do
                local cell = self.pool[i].cells[c]
                w = math.max(w, (cell:GetStringWidth() or 0) + 8)
            end
            widths[c] = math.max(24, math.ceil(w))
            total = total + widths[c] + gap
        end
        local flex = self.opts.flex or 2
        if not cols[flex] then flex = #cols end
        if total < avail then
            widths[flex] = widths[flex] + (avail - total)
        elseif total > avail then
            local shrinkable = 0
            for c = 1, #cols do shrinkable = shrinkable + math.max(0, widths[c] - 50) end
            local over = total - avail
            for c = 1, #cols do
                local room = math.max(0, widths[c] - 50)
                widths[c] = widths[c] - (shrinkable > 0 and over * room / shrinkable or 0)
            end
        end
        local x = 8
        for c, col in ipairs(cols) do
            col.x, col.width = x, widths[c]
            col.headerText:ClearAllPoints()
            col.headerText:SetPoint("LEFT", header, "LEFT", x, 0)
            col.headerText:SetWidth(widths[c])
            for i = 1, rowCount do
                local cell = self.pool[i].cells[c]
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", self.pool[i], "LEFT", x, 0)
                cell:SetWidth(widths[c])
            end
            x = x + widths[c] + gap
        end
    end

    return list
end

-- Rank text with gold/silver/bronze for the top three.
function W.Rank(i)
    local hex = W.RANK_HEX[i]
    return hex and W.Color(i .. ".", hex) or (i .. ".")
end

function W.RankValue(i, text)
    local hex = W.RANK_HEX[i]
    if hex and not tostring(text):find("|c", 1, true) then return W.Color(text, hex) end
    return text
end

---------------------------------------------------------------------------
-- Event text (news ticker, toasts, legacy feed)
---------------------------------------------------------------------------

local STAT_LABEL = function(key) return (FS.STATS[key] and FS.STATS[key].label) or tostring(key) end

-- Returns tag, sentence, icon for an event.
function W.EventText(ev)
    local rec = FS.db.global.characters[ev.who]
    local who = rec and W.CharName(rec) or W.Color(FS.ShortName(ev.who), "ffffff")
    if ev.kind == "death" then
        return W.Color("BREAKING:", "ff5555"),
            string.format("%s died to %s%s!", who, W.Color(ev.a or "Unknown", "ff7777"), ev.z and ev.z ~= "" and (" in " .. ev.z) or ""),
            "Interface\\Icons\\Ability_Rogue_FeignDeath"
    elseif ev.kind == "gear" then
        return W.Color("GEARSCORE:", "a335ee"),
            string.format("%s equipped %s and reached %s GS!", who, ev.a or "new gear", W.Num(ev.v)),
            "Interface\\Icons\\INV_Chest_Plate06"
    elseif ev.kind == "legacy" then
        return W.Color(FS.IS_FOREVER and "LEGACY:" or "ACHIEVEMENT:", "00e6ff"),
            string.format("%s earned %s%s!", who, W.Color(ev.a or "a challenge", "ffd100"),
                (tonumber(ev.lp) or 0) > 0 and W.Color(" (+" .. ev.lp .. " " .. FS.POINTS.short .. ")", "00e6ff") or ""),
            "Interface\\Icons\\Achievement_General"
    elseif ev.kind == "level" then
        return W.Color("LEVEL UP:", "ffd100"),
            string.format("%s reached level %d!", who, tonumber(ev.v) or 0),
            "Interface\\Icons\\Spell_Holy_SurgeOfLight"
    elseif ev.kind == "prof" then
        return W.Color("PROFESSION:", "1eff00"),
            string.format("%s reached %s %d!", who, ev.a or "?", tonumber(ev.v) or 0),
            "Interface\\Icons\\Trade_BlackSmithing"
    elseif ev.kind == "boss" then
        return W.Color("BOSS DOWN:", "ff8000"),
            string.format("%s defeated %s for the first time!", who, W.Color(ev.a or "?", "ffd100")),
            "Interface\\Icons\\Achievement_Boss_Onyxia"
    elseif ev.kind == "bounty" then
        return W.Color("BOUNTY:", "1eff00"), "The guild completed " .. W.Color(ev.a or "a bounty", "ffd100") .. "!",
            "Interface\\Icons\\INV_Misc_Bag_10"
    elseif ev.kind == "wager" then
        return W.Color("WAGER:", "ffd100"), string.format("%s %s %s Fellowship Marks.", who,
            (tonumber(ev.v) or 0) >= 0 and "won" or "lost", W.Num(math.abs(tonumber(ev.v) or 0))), "Interface\\Icons\\INV_Misc_Coin_02"
    elseif ev.kind == "rival" then
        return W.Color("RIVALRY:", "ff8000"), string.format("%s declared %s their rival!", who,
            W.CharName(FS.db.global.characters[ev.a] or { fullName = tostring(ev.a) })), "Interface\\Icons\\Ability_Warrior_Challange"
    elseif ev.kind == "record" then
        return W.Color("RECORD:", "ff8000"),
            string.format("%s killed %s in %s, a new personal best!", who, W.Color(ev.a or "?", "ffd100"), W.FightTime(ev.v)),
            "Interface\\Icons\\INV_Misc_PocketWatch_01"
    elseif ev.kind == "fallen" then
        return W.Color("REST IN PEACE:", "aaaaaa"),
            string.format("%s fell for good at level %d in %s.", who, tonumber(ev.v) or 0, ev.z or "an unknown place"),
            "Interface\\Icons\\Spell_Holy_GuardianSpirit"
    elseif ev.kind == "milestone" then
        return W.Color("MILESTONE:", "ffaa33"),
            string.format("%s crossed %s %s!", who, W.Num(ev.v), STAT_LABEL(ev.a)),
            "Interface\\Icons\\Achievement_Quests_Completed_08"
    end
    return "", who, "Interface\\Icons\\INV_Misc_QuestionMark"
end
