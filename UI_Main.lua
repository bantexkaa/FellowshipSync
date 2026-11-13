local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local UI = FS.UI
local W = FS.W

UI.THEME_PALETTES = {
    ["Default Gold"]         = { bg = {0.05, 0.05, 0.06}, border = {0.45, 0.38, 0.12}, accent = {1.00, 0.82, 0.00} },
    ["Horde Red"]            = { bg = {0.09, 0.02, 0.02}, border = {0.75, 0.12, 0.12}, accent = {1.00, 0.25, 0.25} },
    ["Alliance Blue"]        = { bg = {0.02, 0.05, 0.11}, border = {0.15, 0.45, 0.85}, accent = {0.30, 0.65, 1.00} },
    ["Classic Parchment"]    = { bg = {0.12, 0.10, 0.07}, border = {0.60, 0.50, 0.35}, accent = {0.95, 0.80, 0.50} },
    ["Legion Fel"]           = { bg = {0.02, 0.08, 0.03}, border = {0.20, 0.80, 0.15}, accent = {0.35, 1.00, 0.25} },
    ["Scourge Cyan"]         = { bg = {0.02, 0.08, 0.10}, border = {0.15, 0.75, 0.85}, accent = {0.30, 0.90, 1.00} },
    ["Blackrock Lava"]       = { bg = {0.10, 0.04, 0.01}, border = {0.85, 0.35, 0.05}, accent = {1.00, 0.50, 0.10} },
    ["Mists Jade"]           = { bg = {0.02, 0.09, 0.07}, border = {0.10, 0.75, 0.55}, accent = {0.20, 0.95, 0.70} },
    ["Void Purple"]          = { bg = {0.06, 0.02, 0.10}, border = {0.55, 0.20, 0.85}, accent = {0.75, 0.40, 1.00} },
    ["Light Gold"]           = { bg = {0.10, 0.09, 0.04}, border = {0.90, 0.80, 0.35}, accent = {1.00, 0.92, 0.50} },
    ["Death Knight Crimson"] = { bg = {0.08, 0.01, 0.03}, border = {0.77, 0.12, 0.23}, accent = {0.95, 0.20, 0.35} },
    ["Demon Hunter Violet"]  = { bg = {0.07, 0.01, 0.09}, border = {0.64, 0.19, 0.79}, accent = {0.85, 0.30, 1.00} },
    ["Emerald Nature"]       = { bg = {0.02, 0.08, 0.04}, border = {0.20, 0.65, 0.30}, accent = {0.35, 0.85, 0.45} },
    ["Arcane Magenta"]       = { bg = {0.09, 0.02, 0.08}, border = {0.80, 0.25, 0.75}, accent = {1.00, 0.40, 0.95} },
    ["Forsaken Blight"]      = { bg = {0.05, 0.07, 0.03}, border = {0.45, 0.60, 0.20}, accent = {0.65, 0.85, 0.30} },
    ["Silvermoon Red"]       = { bg = {0.10, 0.03, 0.03}, border = {0.85, 0.65, 0.20}, accent = {1.00, 0.80, 0.30} },
    ["Darnassus Moonlight"]  = { bg = {0.03, 0.05, 0.10}, border = {0.45, 0.55, 0.85}, accent = {0.65, 0.75, 1.00} },
    ["Ironforge Bronze"]     = { bg = {0.08, 0.05, 0.03}, border = {0.70, 0.45, 0.25}, accent = {0.90, 0.60, 0.35} },
    ["Tavern Wood"]          = { bg = {0.09, 0.06, 0.03}, border = {0.55, 0.38, 0.20}, accent = {0.85, 0.65, 0.35} },
    ["ElvUI Black"]          = { bg = {0.03, 0.03, 0.03}, border = {0.20, 0.20, 0.20}, accent = {0.90, 0.90, 0.90} }
}

UI.FONT_PATHS = {
    ["Standard Modern"] = "Fonts\\FRIZQT__.TTF",
    ["Classic WoW"]     = "Fonts\\ARIALN.TTF",
    ["Quest Log"]       = "Fonts\\MORPHEUS.TTF",
    ["Combat Damage"]   = "Fonts\\SKURRI.TTF",
    ["Vanilla Chat"]    = "Fonts\\2002.TTF"
}

UI.CLASS_COLORS = {
    WARRIOR = "c79c6e",
    PALADIN = "f58cba",
    HUNTER  = "abd473",
    ROGUE   = "fff569",
    PRIEST  = "ffffff",
    MAGE    = "40c7eb",
    WARLOCK = "8787ed",
    SHAMAN  = "0070de",
    DRUID   = "ff7d0a"
}

-- Uses the game's own class colours, so Death Knight, Monk, Demon Hunter and
-- Evoker are coloured too, and shows the localized class name.
UI.currentScope = "solo"
UI.timeMode = "all"

-- Main-tab groups (each page stays a module; groups just bundle them).
UI.GROUPS = {
    { label = "Leaderboards", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", mods = { "Dashboard", "Combat", "Misc", "FactionWar" } },
    { label = "Players",      icon = "Interface\\Icons\\INV_Misc_Head_Human_01",  mods = { "Profiles", "Records", "Progress" } },
    { label = "History",      icon = "Interface\\Icons\\INV_Misc_Book_09",         mods = { "Deathlog", "Chronicle" } },
    { label = "Fellowship",   icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing", mods = { "FellowshipUI" } },
    { label = "Guild",        icon = "Interface\\Icons\\INV_BannerPVP_02",          mods = { "GuildUI" } },
    { label = "Options",      icon = "Interface\\Icons\\INV_Misc_Gear_01",          mods = { "Options" } },
}

-- The tabs, in order. Each module implements :Build(parent) -> sets .frame, and :Refresh().
UI.VIEWS = {
    { label = "Hall of Fame", mod = "Dashboard" },
    { label = "Deathlog",     mod = "Deathlog" },
    { label = "Combat",       mod = "Combat" },
    { label = "Misc & Gear",  mod = "Misc" },
    { label = "Profiles",     mod = "Profiles" },
    { label = "Faction War",  mod = "FactionWar" },
    { label = "Chronicle",    mod = "Chronicle" },
    { label = "Fellowship",   mod = "FellowshipUI" },
    { label = "Records",      mod = "Records" },
    { label = "Progress",     mod = "Progress" },
    { label = "Guild",        mod = "GuildUI" },
    { label = "Options",      mod = "Options" },
}
UI.SCOPES = {
    { id = "solo",    label = "My Characters" },
    { id = "guild",   label = "Guild" },
    { id = "network", label = "Network" },
    { id = "netaccs", label = "Accounts" },
}
UI.SCOPE_TITLES = { solo = "My Characters", guild = "Guild", network = "Full Network", netaccs = "Network Accounts" }

function UI:FormatClassText(cls)
    return W.Color(W.ClassName(cls), W.ClassHex(cls))
end

function UI:GetActivePalette()
    local name = FS.db and FS.db.profile.theme or "Default Gold"
    return self.THEME_PALETTES[name] or self.THEME_PALETTES["Default Gold"]
end

function UI:GetActiveFont()
    local name = FS.db and FS.db.profile.font or "Standard Modern"
    return self.FONT_PATHS[name] or "Fonts\\FRIZQT__.TTF"
end

function UI:ContentWidth() return 1010 end

function UI:InitializeFrame()
    if self.MainFrame then return end
    local pos = FS.db.profile.framePos

    local f = CreateFrame("Frame", "FellowshipSyncMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(1040, 820)
    if pos then
        f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else
        f:SetPoint("CENTER")
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        FS.db.profile.framePos = { point, x, y } -- current profile, even after switching
    end)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self) if self:IsShown() then self:Hide(); FS:Print("Window closed for combat.") end end)
    f:Hide()
    tinsert(UISpecialFrames, "FellowshipSyncMainFrame")
    self.MainFrame = f
    -- Resizable from the bottom-right corner (never smaller than the design size).
    local size = FS.db.profile.windowSize
    if size and tonumber(size[1]) and tonumber(size[2]) then f:SetSize(size[1], size[2]) end
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(1040, 820, 2400, 1600)
    elseif f.SetMinResize then f:SetMinResize(1040, 820); f:SetMaxResize(2400, 1600) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        FS.db.profile.windowSize = { math.floor(f:GetWidth()), math.floor(f:GetHeight()) }
        UI:RefreshActiveTab()
    end)
    self.resizeGrip = grip

    -- Title bar: name, All-Time / This Week, scope filter, close.
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 14, -8)
    logo:SetTexture("Interface\\AddOns\\FellowshipSync\\Media\\Logo")
    self.logo = logo
    local title = W.Text(f, "GameFontHighlightLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("|cffffd100Fellowship|rSync |cff888888v" .. FS.VERSION .. "|r")

    self.timeButtons = {}
    local prev
    for _, t in ipairs({ { id = "all", label = "All-Time" }, { id = "week", label = "This Week" } }) do
        local b = W.Button(f, t.label, 82, 22, function() UI:SetTimeMode(t.id) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 250, -10) end
        b.id = t.id
        table.insert(self.timeButtons, b)
        prev = b
    end

    self.scopeButtons = {}
    prev = nil
    for _, s in ipairs(self.SCOPES) do
        local b = W.Button(f, s.label, 112, 22, function() UI:SetScope(s.id) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", self.timeButtons[2], "RIGHT", 24, 0) end
        b.id = s.id
        table.insert(self.scopeButtons, b)
        prev = b
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Main tabs: six groups; a group with several pages gets a section row below it.
    self.modIndex = {}
    for i, v in ipairs(self.VIEWS) do self.modIndex[v.mod] = i end
    self.groupOf, self.lastInGroup = {}, {}
    for g, group in ipairs(self.GROUPS) do
        for _, mod in ipairs(group.mods) do if self.modIndex[mod] then self.groupOf[self.modIndex[mod]] = g end end
    end
    for i in ipairs(self.VIEWS) do -- anything not grouped gets its own group
        if not self.groupOf[i] then
            table.insert(self.GROUPS, { label = self.VIEWS[i].label, mods = { self.VIEWS[i].mod } })
            self.groupOf[i] = #self.GROUPS
        end
    end
    self.groupTabs = {}
    local groupWidth = (self:ContentWidth() - (#self.GROUPS - 1) * 4) / #self.GROUPS
    for g, group in ipairs(self.GROUPS) do
        local tab = W.Button(f, group.label, groupWidth, 28, function() UI:SelectGroup(g) end)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 15 + (g - 1) * (groupWidth + 4), -42)
        tab.text:SetFontObject(GameFontHighlight)
        if group.icon then
            tab.icon = tab:CreateTexture(nil, "ARTWORK")
            tab.icon:SetSize(18, 18)
            tab.icon:SetPoint("LEFT", 10, 0)
            tab.icon:SetTexture(group.icon)
            tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        self.groupTabs[g] = tab
    end
    -- Section row: the pages of the selected group
    self.tabs = {}
    for i, v in ipairs(self.VIEWS) do
        local b = W.Button(f, v.label, 130, 22, function() UI:SelectTab(i) end)
        b.text:SetFontObject(GameFontHighlightSmall)
        b:Hide()
        self.tabs[i] = b
    end
    -- Search everything
    self.globalSearch = W.Search(f, 240, "Search everything...", function(q) FS.GlobalSearch:Show(q) end)
    self.globalSearch:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -76)
    -- One "?" in the top bar explains whichever page and section is open (it never overlaps page content).
    local help = W.Button(f, "?", 24, 22)
    help:SetPoint("RIGHT", self.globalSearch, "LEFT", -8, 0)
    help:SetScript("OnEnter", function(btn)
        local view = UI.inspecting and FS.Inspector or FS[UI.VIEWS[UI.currentTab].mod]
        local mod = UI.inspecting and "Inspector" or UI.VIEWS[UI.currentTab].mod
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(W.Plain(view and view.title and view.title.GetText and view.title:GetText() or W.T(UI.VIEWS[UI.currentTab].label)), 1, 0.82, 0)
        GameTooltip:AddLine(FS.HelpText(mod, view and view.current), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.helpButton = help

    -- A coloured connector from the active tab down into the page.
    self.tabConnector = f:CreateTexture(nil, "OVERLAY")
    self.tabConnector:SetHeight(4)

    -- Content area, news ticker and status line.
    local content = W.Box(f, "panel")
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -104)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 34)
    self.ContentFrame = content
    -- Share / Export for whatever you're looking at
    self.shareButton = W.Button(f, "Share", 80, 20, function() FS.Share:ShareCurrent() end)
    self.shareButton:SetPoint("BOTTOMLEFT", 16, 8)
    self.exportButton = W.Button(f, "Export", 80, 20, function() FS.Share:ExportCurrent() end)
    self.exportButton:SetPoint("LEFT", self.shareButton, "RIGHT", 4, 0)

    self.statusText = W.Text(f, "GameFontDisableSmall", "RIGHT")
    self.statusText:SetPoint("BOTTOMRIGHT", -18, 12)
    self.statusText:SetWidth(260)

    if FS.Extras.BuildTicker then FS.Extras:BuildTicker(f) end

    for _, v in ipairs(self.VIEWS) do
        local mod = FS[v.mod]
        if mod and mod.Build then
            mod:Build(content)
            if mod.frame then mod.frame:SetAllPoints(content); mod.frame:Hide() end

        end
    end
    FS.Inspector:Build(content)
    FS.Inspector.frame:SetAllPoints(content)
    FS.Inspector.frame:Hide()

    self.currentTab = 1
    self:ApplyTheme()
    self:SetScope(self.currentScope, true)
    self:SetTimeMode(self.timeMode, true)
    self:SelectTab(1)
end

function UI:ApplyTheme()
    if not self.MainFrame then return end
    FS.Style:ApplyMain()      -- border, background, glow, shadow, scale
    W.Reskin()                -- cards, panels, buttons, sub-tab strips
    FS.Style:ApplyFonts()     -- font and outline everywhere
    if FS.Extras.ApplyTickerVisibility then FS.Extras:ApplyTickerVisibility() end
    self:UpdateButtons()
    self:RefreshActiveTab()
end

function UI:UpdateButtons()
    for _, b in ipairs(self.scopeButtons or {}) do b:SetActive(b.id == self.currentScope) end
    for _, b in ipairs(self.timeButtons or {}) do b:SetActive(b.id == self.timeMode) end
    local group = self.groupOf and self.groupOf[self.currentTab] or 1
    for g, t in ipairs(self.groupTabs or {}) do t:SetActive(g == group and not self.inspecting) end
    -- section row: the selected group's pages (only when it has more than one)
    local x = 0
    local mods = self.GROUPS[group] and self.GROUPS[group].mods or {}
    for i, b in ipairs(self.tabs or {}) do
        local inGroup = self.groupOf[i] == group and #mods > 1
        b:SetShown(inGroup)
        if inGroup then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.MainFrame, "TOPLEFT", 15 + x, -76)
            x = x + 134
            b:SetActive(i == self.currentTab and not self.inspecting)
        end
    end
    local active = self.groupTabs and self.groupTabs[group]
    if self.tabConnector and active then
        local pal = self:GetActivePalette()
        self.tabConnector:ClearAllPoints()
        self.tabConnector:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 6, 0)
        self.tabConnector:SetPoint("TOPRIGHT", active, "BOTTOMRIGHT", -6, 0)
        self.tabConnector:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], 1)
        self.tabConnector:SetShown(not self.inspecting)
    end
    -- Unread guild notices show on the Guild group.
    for g, grp in ipairs(self.GROUPS or {}) do
        for _, mod in ipairs(grp.mods) do
            if mod == "GuildUI" and self.groupTabs and self.groupTabs[g] then
                local unread = FS.Officer.UnreadNotices and FS.Officer:UnreadNotices() or 0
                self.groupTabs[g].text:SetText(unread > 0 and string.format("%s (%d)", W.T(grp.label), unread) or W.T(grp.label))
            end
        end
    end
end

function UI:SelectGroup(g)
    local group = self.GROUPS[g]
    if not group then return end
    self:SelectTab(self.lastInGroup[g] or self.modIndex[group.mods[1]] or 1)
end

function UI:SetScope(scope, silent)
    self.currentScope = scope or "solo"
    self:UpdateButtons()
    if not silent then self:RefreshActiveTab() end
end

function UI:SetTimeMode(mode, silent)
    self.timeMode = mode or "all"
    self:UpdateButtons()
    if not silent then self:RefreshActiveTab() end
end

function UI:HideAllViews()
    for _, v in ipairs(self.VIEWS) do
        local mod = FS[v.mod]
        if mod and mod.frame then mod.frame:Hide() end
    end
    if FS.Inspector.frame then FS.Inspector.frame:Hide() end
end

function UI:SelectTab(index)
    self.currentTab = index or 1
    if self.groupOf and self.groupOf[self.currentTab] then self.lastInGroup[self.groupOf[self.currentTab]] = self.currentTab end
    self.inspecting = false
    self:HideAllViews()
    local mod = FS[self.VIEWS[self.currentTab].mod]
    if mod and mod.frame then mod.frame:Show() end
    self:UpdateButtons()
    self:RefreshActiveTab()
end

-- Opens the deep-dive inspector for a character (or an account's best character).
function UI:OpenInspector(rec, context)
    if not rec then return end
    if rec.isAccount then rec = rec.bestChar or rec.chars and rec.chars[1] end
    if not rec then return end
    self.inspecting = true
    self:HideAllViews()
    FS.Inspector.frame:Show()
    FS.Inspector:Load(rec, context)
    self:UpdateButtons()
end

function UI:CloseInspector()
    self:SelectTab(self.currentTab)
end

function UI:RefreshActiveTab()
    if not self.MainFrame then return end
    local count = #FS:GetFilteredCharacters(self.currentScope)
    self.statusText:SetText(string.format("%s  |  %d %s  |  %s", self.SCOPE_TITLES[self.currentScope] or "",
        count, self.currentScope == "netaccs" and "accounts" or "characters",
        self.timeMode == "week" and "This Week" or "All-Time"))
    if FS.Extras.RefreshTicker then FS.Extras:RefreshTicker() end
    if self.inspecting then
        FS.Inspector:Refresh()
        return
    end
    local mod = FS[self.VIEWS[self.currentTab].mod]
    if mod and mod.Refresh then mod:Refresh() end
end
