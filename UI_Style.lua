local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local UI, W = FS.UI, FS.W
local Style = FS.Style

---------------------------------------------------------------------------
-- Appearance: themes, fonts, borders, backgrounds, glow, shadow and "pop".
-- Fonts, borders and backgrounds from LibSharedMedia-3.0 are added when another
-- addon provides it (SharedMedia, ElvUI, ...).
---------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8x8"
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF"

-- 25 more colour themes (the original 20 stay).
local MORE_THEMES = {
    ["Arcane Violet"]       = { bg = { 0.06, 0.03, 0.10 }, border = { 0.55, 0.30, 0.85 }, accent = { 0.80, 0.55, 1.00 } },
    ["Frost Wyrm"]          = { bg = { 0.03, 0.06, 0.09 }, border = { 0.45, 0.70, 0.85 }, accent = { 0.70, 0.92, 1.00 } },
    ["Emerald Dream"]       = { bg = { 0.02, 0.07, 0.04 }, border = { 0.25, 0.65, 0.35 }, accent = { 0.45, 1.00, 0.60 } },
    ["Sunwell Radiance"]    = { bg = { 0.09, 0.07, 0.02 }, border = { 0.85, 0.65, 0.20 }, accent = { 1.00, 0.90, 0.45 } },
    ["Ironforge Steel"]     = { bg = { 0.07, 0.07, 0.08 }, border = { 0.50, 0.52, 0.56 }, accent = { 0.80, 0.84, 0.90 } },
    ["Darnassus Moon"]      = { bg = { 0.04, 0.04, 0.09 }, border = { 0.40, 0.45, 0.75 }, accent = { 0.75, 0.80, 1.00 } },
    ["Thunder Bluff Earth"] = { bg = { 0.08, 0.05, 0.03 }, border = { 0.60, 0.40, 0.22 }, accent = { 0.95, 0.70, 0.40 } },
    ["Stormwind Royal"]     = { bg = { 0.03, 0.04, 0.10 }, border = { 0.20, 0.35, 0.75 }, accent = { 1.00, 0.82, 0.30 } },
    ["Orgrimmar Iron"]      = { bg = { 0.08, 0.04, 0.03 }, border = { 0.55, 0.25, 0.15 }, accent = { 0.95, 0.45, 0.20 } },
    ["Undercity Plague"]    = { bg = { 0.04, 0.06, 0.03 }, border = { 0.40, 0.55, 0.20 }, accent = { 0.70, 0.95, 0.30 } },
    ["Naxxramas Frost"]     = { bg = { 0.02, 0.05, 0.06 }, border = { 0.20, 0.55, 0.55 }, accent = { 0.40, 1.00, 0.90 } },
    ["Ahn'Qiraj Sands"]     = { bg = { 0.08, 0.06, 0.03 }, border = { 0.70, 0.55, 0.25 }, accent = { 0.95, 0.80, 0.35 } },
    ["Zul'Gurub Jungle"]    = { bg = { 0.03, 0.07, 0.04 }, border = { 0.30, 0.55, 0.25 }, accent = { 0.85, 0.75, 0.25 } },
    ["Outland Nether"]      = { bg = { 0.05, 0.02, 0.07 }, border = { 0.45, 0.80, 0.25 }, accent = { 0.80, 0.40, 1.00 } },
    ["Cataclysm Ember"]     = { bg = { 0.08, 0.03, 0.01 }, border = { 0.80, 0.35, 0.05 }, accent = { 1.00, 0.55, 0.10 } },
    ["Pandaria Bamboo"]     = { bg = { 0.04, 0.07, 0.04 }, border = { 0.45, 0.65, 0.30 }, accent = { 0.95, 0.85, 0.45 } },
    ["Shadowlands Ash"]     = { bg = { 0.05, 0.05, 0.06 }, border = { 0.35, 0.35, 0.40 }, accent = { 0.60, 0.75, 0.95 } },
    ["Dragonflight Bronze"] = { bg = { 0.07, 0.05, 0.03 }, border = { 0.70, 0.50, 0.25 }, accent = { 0.95, 0.75, 0.40 } },
    ["Midnight Eclipse"]    = { bg = { 0.02, 0.02, 0.05 }, border = { 0.30, 0.25, 0.60 }, accent = { 0.95, 0.45, 0.85 } },
    ["Blood Elf Crimson"]   = { bg = { 0.09, 0.02, 0.03 }, border = { 0.75, 0.15, 0.20 }, accent = { 1.00, 0.80, 0.30 } },
    ["Ocean Deep"]          = { bg = { 0.01, 0.04, 0.07 }, border = { 0.10, 0.40, 0.60 }, accent = { 0.20, 0.80, 0.95 } },
    ["Candy Pop"]           = { bg = { 0.08, 0.03, 0.07 }, border = { 0.90, 0.40, 0.70 }, accent = { 1.00, 0.60, 0.85 } },
    ["Monochrome"]          = { bg = { 0.04, 0.04, 0.04 }, border = { 0.45, 0.45, 0.45 }, accent = { 0.95, 0.95, 0.95 } },
    ["High Contrast"]       = { bg = { 0.00, 0.00, 0.00 }, border = { 1.00, 1.00, 1.00 }, accent = { 1.00, 0.90, 0.00 } },
    ["My Class Colour"]     = { dynamic = "class", bg = { 0.05, 0.05, 0.06 }, border = { 0.5, 0.5, 0.5 }, accent = { 1, 1, 1 } },
}
for name, pal in pairs(MORE_THEMES) do UI.THEME_PALETTES[name] = pal end

-- "My Class Colour" follows the class of the character you are playing.
function UI:GetActivePalette()
    local name = FS.db and FS.db.profile.theme or "Default Gold"
    local pal = self.THEME_PALETTES[name] or self.THEME_PALETTES["Default Gold"]
    if pal.dynamic == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls or ""]
        if c then
            local r, g, b = c.r or 1, c.g or 1, c.b or 1
            self.classPalette = self.classPalette or {}
            local p = self.classPalette
            p.bg, p.border, p.accent = { r * 0.08, g * 0.08, b * 0.08 }, { r * 0.65, g * 0.65, b * 0.65 }, { r, g, b }
            return p
        end
        return self.THEME_PALETTES["Default Gold"]
    end
    return pal
end

---------------------------------------------------------------------------
-- Catalogues
---------------------------------------------------------------------------

Style.FONTS = {
    { "Standard Modern", "Fonts\\FRIZQT__.TTF" },
    { "Classic WoW", "Fonts\\ARIALN.TTF" },
    { "Quest Log", "Fonts\\MORPHEUS.TTF" },
    { "Combat Damage", "Fonts\\SKURRI.TTF" },
    { "Vanilla Chat", "Fonts\\2002.TTF" },
    { "Vanilla Chat Bold", "Fonts\\2002B.TTF" },
    { "Storybook", "Fonts\\K_Pagetext.TTF" },
    { "Impact", "Fonts\\K_Damage.TTF" },
    { "Friz Quadrata Cyrillic", "Fonts\\FRIZQT___CYR.TTF" },
    { "Morpheus Cyrillic", "Fonts\\MORPHEUS_CYR.TTF" },
    { "Skurri Cyrillic", "Fonts\\SKURRI_CYR.TTF" },
}
Style.OUTLINES = { { "none", "No outline" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" },
                   { "MONOCHROME", "Pixel (monochrome)" }, { "OUTLINE, MONOCHROME", "Pixel outline" } }
-- { name, edge texture, edge size, inset, extra }
Style.BORDERS = {
    { "Classic WoW Tooltip", "Interface\\Tooltips\\UI-Tooltip-Border", 14, 3 },
    { "Sharp and Modern (1px)", WHITE, 1, 1 },
    { "Bold Line (2px)", WHITE, 2, 2 },
    { "Thick Frame (4px)", WHITE, 4, 4 },
    { "Royal Double Line", "Interface\\DialogFrame\\UI-DialogBox-Border", 16, 5 },
    { "Royal Gold", "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", 16, 5 },
    { "Achievement Wood", "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", 32, 7 },
    { "Toast Frame", "Interface\\FriendsFrame\\UI-Toast-Border", 12, 3 },
    { "Neon Theme Glow", "Interface\\Tooltips\\UI-Tooltip-Border", 18, 3, { neon = true } },
    { "No Border", nil, 0, 0 },
}
-- { name, texture, solid = tinted by the theme colour }
Style.BACKGROUNDS = {
    { "Solid Colour", WHITE, true },
    { "Tooltip", "Interface\\Tooltips\\UI-Tooltip-Background", true },
    { "Dark Dialog", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { "Dialog", "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { "Marble", "Interface\\FrameGeneral\\UI-Background-Marble" },
    { "Rock", "Interface\\FrameGeneral\\UI-Background-Rock" },
    { "Parchment", "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal" },
}
Style.CARD_STYLES = { { "soft", "Soft (follows the border style)" }, { "flat", "Flat (no edges)" }, { "bold", "Bold (accent edges)" } }

-- One-click looks.
Style.PRESETS = {
    { "Classic", { borderStyle = "Classic WoW Tooltip", background = "Dark Dialog", font = "Standard Modern", fontOutline = "none",
                   glow = 0, glowPulse = false, glowCards = false, shadow = true, cardStyle = "soft", pop = 0.2 } },
    { "Clean",   { borderStyle = "Sharp and Modern (1px)", background = "Solid Colour", font = "Classic WoW", fontOutline = "none",
                   glow = 0.15, glowSize = 10, glowPulse = false, glowCards = false, shadow = true, cardStyle = "flat", pop = 0.35 } },
    { "Neon",    { borderStyle = "Neon Theme Glow", background = "Solid Colour", font = "Standard Modern", fontOutline = "OUTLINE",
                   glow = 0.9, glowSize = 22, glowPulse = true, glowToasts = true, glowCards = true, shadow = false, cardStyle = "bold", pop = 1 } },
    { "Royal",   { borderStyle = "Royal Gold", background = "Marble", font = "Quest Log", fontOutline = "none",
                   glow = 0.35, glowSize = 16, glowPulse = false, glowCards = false, shadow = true, cardStyle = "soft", pop = 0.5 } },
    { "Minimal", { borderStyle = "No Border", background = "Solid Colour", font = "Classic WoW", fontOutline = "none",
                   glow = 0, glowPulse = false, glowCards = false, shadow = false, cardStyle = "flat", pop = 0 } },
}

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Names for a dropdown: built-in entries first, then SharedMedia ones not already listed.
local function Names(builtin, mediaType)
    local names, seen = {}, {}
    for _, e in ipairs(builtin) do table.insert(names, e[1]); seen[e[1]] = true end
    local lsm = LSM()
    if lsm and lsm.List then
        local extra = {}
        for _, name in ipairs(lsm:List(mediaType) or {}) do if not seen[name] then table.insert(extra, name) end end
        table.sort(extra)
        for _, name in ipairs(extra) do table.insert(names, name) end
    end
    return names
end
function Style:FontNames() return Names(self.FONTS, "font") end
function Style:BorderNames() return Names(self.BORDERS, "border") end
function Style:BackgroundNames() return Names(self.BACKGROUNDS, "background") end

local function Find(list, name) for _, e in ipairs(list) do if e[1] == name then return e end end end

-- A font that this game version doesn't ship would make text disappear: test it first.
Style.validFont = {}
function Style:IsValidFont(path)
    if self.validFont[path] == nil then
        self.probe = self.probe or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local ok, result = pcall(self.probe.SetFont, self.probe, path, 12, "")
        self.validFont[path] = ok and result ~= false
    end
    return self.validFont[path]
end

function Style:FontPath(name)
    local e = Find(self.FONTS, name)
    local path = e and e[2]
    if not path and LSM() then path = LSM():Fetch("font", name, true) end
    if path and self:IsValidFont(path) then return path end
    return STANDARD_FONT
end

function Style:Border(name)
    local e = Find(self.BORDERS, name)
    if e then return { file = e[2], size = e[3], inset = e[4], neon = e[5] and e[5].neon } end
    local file = LSM() and LSM():Fetch("border", name, true)
    if file then return { file = file, size = 16, inset = 4 } end
    return self:Border("Classic WoW Tooltip")
end

function Style:Background(name)
    local e = Find(self.BACKGROUNDS, name)
    if e then return { file = e[2], solid = e[3] } end
    local file = LSM() and LSM():Fetch("background", name, true)
    if file then return { file = file } end
    return { file = WHITE, solid = true }
end

function Style:ApplyPreset(index)
    local preset = self.PRESETS[index]
    if not preset then return end
    for k, v in pairs(preset[2]) do FS.db.profile[k] = v end
    UI:ApplyTheme()
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

local function Mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
Style.Mix = Mix

-- Border colour with "pop": blends the theme's accent into it.
function Style:BorderColour(pal)
    local p = FS.db.profile
    return Mix(pal.border, pal.accent, math.max(0, math.min(1, tonumber(p.pop) or 0.4)))
end

-- Backdrop for cards and panels, following the chosen border style and card style.
function Style:CardBackdrop()
    local p = FS.db.profile
    local key = tostring(p.borderStyle) .. "|" .. tostring(p.cardStyle)
    if self.cardKey == key and self.cardBackdrop then return self.cardBackdrop, false end
    local style = p.cardStyle or "soft"
    local bd
    if style == "flat" then
        bd = { bgFile = WHITE }
    elseif style == "bold" then
        bd = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } }
    else
        local b = self:Border(p.borderStyle)
        if not b.file then
            bd = { bgFile = WHITE }
        else
            local size = math.max(1, math.floor(b.size * 0.8))
            local inset = math.max(1, math.floor(b.inset * 0.8))
            bd = { bgFile = WHITE, edgeFile = b.file, edgeSize = size, insets = { left = inset, right = inset, top = inset, bottom = inset } }
        end
    end
    self.cardKey, self.cardBackdrop = key, bd
    return bd, true
end

function Style:ApplyMain()
    local f = UI.MainFrame
    if not f then return end
    local p, pal = FS.db.profile, UI:GetActivePalette()
    local b, bg = self:Border(p.borderStyle), self:Background(p.background)
    f:SetScale(tonumber(p.uiScale) or 1)
    f:SetBackdrop({ bgFile = bg.file, tile = not bg.solid, tileSize = bg.solid and 0 or 256,
                    edgeFile = b.file, edgeSize = b.size, insets = { left = b.inset, right = b.inset, top = b.inset, bottom = b.inset } })
    local alpha = tonumber(p.bgAlpha) or 0.95
    if bg.solid then
        f:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], alpha)
    else -- textures keep their own colours, lightly tinted towards the theme
        local t = Mix({ 1, 1, 1 }, pal.accent, 0.15)
        f:SetBackdropColor(t[1] * 0.85, t[2] * 0.85, t[3] * 0.85, alpha)
    end
    local edge = b.neon and pal.accent or self:BorderColour(pal)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)

    local glow = math.max(0, math.min(1, tonumber(p.glow) or 0)) + (b.neon and 0.25 or 0)
    W.SetGlow(f, "glow", pal.accent, math.min(1, glow), tonumber(p.glowSize) or 14, p.glowPulse)
    W.SetGlow(f, "shadow", { 0, 0, 0 }, p.shadow ~= false and 0.65 or 0, 16, false)
end

function Style:ApplyToast(t)
    local p, pal = FS.db.profile, UI:GetActivePalette()
    local b = self:Border(p.borderStyle)
    t:SetBackdrop({ bgFile = WHITE, edgeFile = b.file or WHITE, edgeSize = b.file and math.max(1, math.floor(b.size * 0.8)) or 1,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    t:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], 0.95)
    t:SetBackdropBorderColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
    local strength = p.glowToasts ~= false and math.max(0.4, tonumber(p.glow) or 0) or 0
    W.SetGlow(t, "glow", pal.accent, strength, tonumber(p.glowSize) or 14, p.glowPulse)
end

-- Every text the addon made follows the chosen font and outline.
function Style:ApplyFonts()
    local path, flags = W.FontPath(), W.FontFlags()
    for fs in pairs(W.texts) do
        local _, size = fs:GetFont()
        pcall(fs.SetFont, fs, path, tonumber(size) or 12, flags)
    end
end
