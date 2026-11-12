local addonName, addonTable = ...
local FellowshipSync = addonTable.FellowshipSync
local Options = FellowshipSync.Options
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)


local function IndexOf(list, value)
    for i, v in ipairs(list) do if v == value then return i end end
    return 1
end

-- Built from UI_Main's palette table, so all 20 themes appear (the old list had 10).
local function ThemeList()
    local list = {}
    for name in pairs(FellowshipSync.UI.THEME_PALETTES) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function Apply()
    if FellowshipSync.UI and FellowshipSync.UI.ApplyTheme then FellowshipSync.UI:ApplyTheme() end
end

function Options:Build(parentFrame)
    if self.panel then return end

    self.home = parentFrame
    local baseFrame = CreateFrame("Frame", "FellowshipSyncOptionsContainer", parentFrame)
    baseFrame:SetAllPoints()
    baseFrame:Hide()
    self.panel = baseFrame
    self.frame = baseFrame

    -- FIX: AceGUI only lays out its children when it is told its size through
    -- its own SetWidth/SetHeight. SetAllPoints() bypasses that, so the old panel
    -- had zero size and everything inside it was invisible.
    local root = AceGUI:Create("SimpleGroup")
    root:SetLayout("Fill")
    root.frame:SetParent(baseFrame)
    root.frame:ClearAllPoints()
    root.frame:SetPoint("TOPLEFT", baseFrame, "TOPLEFT", 10, -10)
    root.frame:SetFrameStrata(baseFrame:GetFrameStrata())
    root.frame:Show()
    self.root = root

    local tabGroup = AceGUI:Create("TabGroup")
    -- FIX: was "Flow". An AceGUI ScrollFrame must sit in a "Fill" container,
    -- otherwise it gets no height and nothing shows.
    tabGroup:SetLayout("Fill")
    self.fullTabs = {
        { text = FellowshipSync.W.T("Cosmetics & UI"), value = "cosmetics" },
        { text = FellowshipSync.W.T("Notifications"),  value = "notify" },
        { text = FellowshipSync.W.T("Fellowship"),     value = "fellowship" },
        { text = FellowshipSync.W.T("Network & Sharing"), value = "network" },
        { text = FellowshipSync.W.T("Data Privacy"),   value = "privacy" },
        { text = FellowshipSync.W.T("Profiles"),       value = "profiles" },
        { text = FellowshipSync.W.T("Database Tools"), value = "tools" }
    }
    -- Simple (Basics) or Advanced (all tabs), switched with the button at the top right
    self.modeButton = FellowshipSync.W.Button(baseFrame, "", 190, 22, function()
        local prof = FellowshipSync.db.profile
        prof.optionsMode = (prof.optionsMode == "advanced") and "simple" or "advanced"
        self:ApplyMode()
    end)
    self.modeButton:SetPoint("TOPRIGHT", baseFrame, "TOPRIGHT", -12, -6)
    self.modeButton:SetFrameLevel((baseFrame:GetFrameLevel() or 1) + 50)
    self.tabGroup = tabGroup
    self:ApplyMode(true)
    tabGroup:SetCallback("OnGroupSelected", function(container, _, group)
        self.currentGroup = group
        self:DrawGroup(container, group)
    end)
    root:AddChild(tabGroup)
    self.tabGroup = tabGroup

    baseFrame:SetScript("OnShow", function()
        self:Resize()
        self.tabGroup:SelectTab(self.currentGroup or "cosmetics")
    end)
end

-- The same options page lives in the FellowshipSync window and in Blizzard's
-- Esc > Options > AddOns > FellowshipSync. It moves to wherever it is opened.
function Options:AttachTo(parent)
    if not self.panel or self.panel:GetParent() == parent then return end
    self.panel:SetParent(parent)
    self.panel:ClearAllPoints()
    self.panel:SetAllPoints(parent)
    self.root.frame:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
    self.panel:Show()
    self:Resize()
    self.tabGroup:SelectTab(self.currentGroup or "cosmetics")
end

-- The window's Options tab is open: bring the page back if Blizzard's settings had it.
function Options:Refresh()
    if self.home then self:AttachTo(self.home) end
end

function Options:RegisterBlizzard()
    if self.blizzPanel then return end
    local p = CreateFrame("Frame")
    p.name = "FellowshipSync"
    p:SetScript("OnShow", function()
        if not FellowshipSync.UI.MainFrame then FellowshipSync.UI:InitializeFrame() end
        self:AttachTo(p)
    end)
    p:SetScript("OnHide", function()
        if not (self.home and self.panel) then return end
        self:AttachTo(self.home)
        local UI = FellowshipSync.UI
        local open = UI.MainFrame and UI.MainFrame:IsShown() and UI.VIEWS[UI.currentTab] and UI.VIEWS[UI.currentTab].mod == "Options"
        self.panel:SetShown(open and true or false)
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(p, "FellowshipSync")
        Settings.RegisterAddOnCategory(category)
        self.blizzCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
    self.blizzPanel = p
end

-- Redraws the open options page (after a profile switch the settings differ).
function Options:Redraw()
    if self.tabGroup and self.panel and self.panel:IsShown() then
        self.tabGroup:SelectTab(self.currentGroup or "cosmetics")
    end
end

function Options:Resize()
    local w, h = self.panel:GetWidth(), self.panel:GetHeight()
    if not w or w <= 0 then return end
    self.root:SetWidth(w - 20)
    self.root:SetHeight(h - 20)
    self.root:DoLayout()
end

local function AddHeading(scroll, text)
    local h = AceGUI:Create("Heading")
    h:SetText(FellowshipSync.W.T(text))
    h:SetFullWidth(true)
    scroll:AddChild(h)
end

local function AddCheck(scroll, label, value, onChange, width)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(FellowshipSync.W.T(label))
    if width then cb:SetWidth(width) else cb:SetFullWidth(true) end
    cb:SetValue(value and true or false)
    cb:SetCallback("OnValueChanged", function(_, _, val) onChange(val) end)
    scroll:AddChild(cb)
    return cb
end

-- choices: { {value, label}, ... }
local function AddChoice(scroll, label, choices, current, onChange, width)
    local list, index = {}, 1
    for i, c in ipairs(choices) do
        list[i] = c[2]
        if c[1] == current then index = i end
    end
    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(FellowshipSync.W.T(label))
    dd:SetWidth(width or 220)
    dd:SetList(list)
    if current ~= nil then dd:SetValue(index) end -- nothing pre-selected for "copy from" / "delete"
    dd:SetCallback("OnValueChanged", function(_, _, key) onChange(choices[key][1]) end)
    scroll:AddChild(dd)
    return dd
end

local function AddButton(scroll, text, width, onClick)
    local b = AceGUI:Create("Button")
    b:SetText(FellowshipSync.W.T(text))
    b:SetWidth(width or 160)
    b:SetCallback("OnClick", function() onClick(b) end)
    scroll:AddChild(b)
    return b
end

-- A secret text field: shown as **** and locked until "Reveal" is pressed.
-- (No password-mode edit boxes: AceGUI reuses edit boxes, and the mode doesn't redraw reliably.)
local function AddSecret(scroll, label, getValue, onSave, width)
    local box = AceGUI:Create("EditBox")
    box:SetLabel(label)
    box:SetWidth(width or 320)
    local revealed = false
    local function Render()
        local value = getValue() or ""
        if revealed or value == "" then
            box:SetDisabled(false)
            box:SetText(value)
        else
            box:SetText(string.rep("*", math.min(#value, 16)))
            box:SetDisabled(true)
        end
    end
    box:SetCallback("OnEnterPressed", function(_, _, text)
        if revealed or (getValue() or "") == "" then onSave(strtrim(text or "")) end
        Render()
    end)
    scroll:AddChild(box)
    local button = AceGUI:Create("Button")
    button:SetText("Reveal")
    button:SetWidth(90)
    button:SetCallback("OnClick", function()
        revealed = not revealed
        button:SetText(revealed and "Hide" or "Reveal")
        Render()
    end)
    scroll:AddChild(button)
    Render()
    return box, button
end

local function AddLabel(scroll, text)
    local l = AceGUI:Create("Label")
    l:SetText(FellowshipSync.W.T(text))
    l:SetFullWidth(true)
    scroll:AddChild(l)
    return l
end

function Options:ApplyMode(silent)
    local simple = FellowshipSync.db.profile.optionsMode ~= "advanced"
    self.tabGroup:SetTabs(simple and { { text = FellowshipSync.W.T("Basics"), value = "basics" } } or self.fullTabs)
    self.modeButton.text:SetText(FellowshipSync.W.T(simple and "Show all settings (Advanced)" or "Show fewer settings (Simple)"))
    if simple then self.currentGroup = "basics"
    elseif self.currentGroup == "basics" or not self.currentGroup then self.currentGroup = "cosmetics" end
    if not silent then self.tabGroup:SelectTab(self.currentGroup) end
end

-- The settings most people change, on one page.
function Options:DrawBasics(scroll, profile, container, group)
    local FS = FellowshipSync
    local Style = FS.Style
    local redraw = function() self:DrawGroup(container, group) end
    AddHeading(scroll, "Look")
    for i, preset in ipairs(Style.PRESETS) do
        AddButton(scroll, preset[1], 110, function() Style:ApplyPreset(i); redraw() end)
    end
    local themes = ThemeList()
    local t = AceGUI:Create("Dropdown")
    t:SetLabel(FS.W.T("Colour Theme"))
    t:SetWidth(260)
    t:SetList(themes)
    t:SetValue(IndexOf(themes, profile.theme))
    t:SetCallback("OnValueChanged", function(_, _, key) profile.theme = themes[key]; Apply() end)
    scroll:AddChild(t)
    AddCheck(scroll, "Colour-blind friendly colours (blue/orange instead of green/red)", profile.colorblind,
        function(v) profile.colorblind = v; Apply() end, 420)
    AddCheck(scroll, "Show the minimap button", not profile.minimap.hide, function(v)
        profile.minimap.hide = not v
        FS.Extras:UpdateMinimapButton()
    end, 420)
    AddHeading(scroll, "Window")
    local pages = { { "last", "Where I left off" } }
    for _, v in ipairs(FS.UI.VIEWS) do table.insert(pages, { v.mod, v.label }) end
    AddChoice(scroll, "Open on", pages, profile.startTab or "last", function(v) profile.startTab = v end, 260)
    AddChoice(scroll, "Open in view", { { "last", "Where I left off" }, { "solo", "My Characters" }, { "guild", "Guild" },
        { "network", "Network" }, { "netaccs", "Accounts" } }, profile.startScope or "last", function(v) profile.startScope = v end, 260)
    AddChoice(scroll, "Distances", { { "metric", "Metres / kilometres" }, { "imperial", "Yards / miles" } },
        profile.distanceUnits or "metric", function(v) profile.distanceUnits = v; Apply() end, 260)
    AddHeading(scroll, "Notifications")
    local n = profile.notify
    AddCheck(scroll, "Show toasts", n.toasts, function(v) n.toasts = v end, 420)
    AddChoice(scroll, "My level-ups", { { "tens", "Every 10 levels + max" }, { "all", "Every level" }, { "max", "Max level only" }, { "off", "Off" } },
        n.own.level, function(v) n.own.level = v end, 260)
    AddChoice(scroll, "Guild boss kills", { { "first", "Guild firsts only" }, { "all", "Every first kill" }, { "off", "Off" } },
        n.guild.boss, function(v) n.guild.boss = v end, 260)
    AddHeading(scroll, "Sharing")
    AddCheck(scroll, "Share with my guild", profile.syncGuild ~= false, function(v) profile.syncGuild = v end, 420)
    AddCheck(scroll, "Share with my Battle.net friends", profile.syncBNet ~= false, function(v) profile.syncBNet = v end, 420)
    AddCheck(scroll, "Show FellowshipSync stats in the game tooltip", profile.unitTooltip ~= false, function(v) profile.unitTooltip = v end, 420)
end

function Options:DrawGroup(container, group)
    container:ReleaseChildren()
    local profile = FellowshipSync.db.profile

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    container:AddChild(scroll)

    if group == "basics" then
        self:DrawBasics(scroll, profile, container, group)
    elseif group == "cosmetics" then
        local Style = FellowshipSync.Style
        local redraw = function() Apply(); self:DrawGroup(container, group) end

        AddHeading(scroll, "Style Presets")
        for i, preset in ipairs(Style.PRESETS) do
            AddButton(scroll, preset[1], 110, function() Style:ApplyPreset(i); self:DrawGroup(container, group) end)
        end
        AddLabel(scroll, "One click sets border, background, font, glow and card style together. Fine-tune anything below.")

        AddHeading(scroll, "Colours")
        local themes = ThemeList()
        local tDrop = AceGUI:Create("Dropdown")
        tDrop:SetLabel("Colour Theme (" .. #themes .. ")")
        tDrop:SetWidth(260)
        tDrop:SetList(themes)
        tDrop:SetValue(IndexOf(themes, profile.theme))
        tDrop:SetCallback("OnValueChanged", function(_, _, key) profile.theme = themes[key]; Apply() end)
        scroll:AddChild(tDrop)
        local pop = AceGUI:Create("Slider")
        pop:SetLabel("Pop (accent colour in borders and buttons)")
        pop:SetWidth(260)
        pop:SetSliderValues(0, 1, 0.05)
        pop:SetIsPercent(true)
        pop:SetValue(tonumber(profile.pop) or 0.4)
        pop:SetCallback("OnValueChanged", function(_, _, v) profile.pop = v; Apply() end)
        scroll:AddChild(pop)

        AddHeading(scroll, "Frame")
        local function Pick(label, names, key, width)
            local choices = {}
            for _, n in ipairs(names) do table.insert(choices, { n, n }) end
            AddChoice(scroll, label, choices, profile[key], function(v) profile[key] = v; Apply() end, width or 260)
        end
        Pick("Border Style (" .. #Style:BorderNames() .. ")", Style:BorderNames(), "borderStyle")
        Pick("Background", Style:BackgroundNames(), "background")
        AddChoice(scroll, "Card Style", Style.CARD_STYLES, profile.cardStyle or "soft", function(v) profile.cardStyle = v; Apply() end, 260)
        local aSlider = AceGUI:Create("Slider")
        aSlider:SetLabel("Background Opacity")
        aSlider:SetWidth(260)
        aSlider:SetSliderValues(0.30, 1.00, 0.05)
        aSlider:SetIsPercent(true)
        aSlider:SetValue(tonumber(profile.bgAlpha) or 0.95)
        aSlider:SetCallback("OnValueChanged", function(_, _, val) profile.bgAlpha = val; Apply() end)
        scroll:AddChild(aSlider)

        AddHeading(scroll, "Glow & Shadow")
        local glow = AceGUI:Create("Slider")
        glow:SetLabel("Glow Strength")
        glow:SetWidth(260)
        glow:SetSliderValues(0, 1, 0.05)
        glow:SetIsPercent(true)
        glow:SetValue(tonumber(profile.glow) or 0.35)
        glow:SetCallback("OnValueChanged", function(_, _, v) profile.glow = v; Apply() end)
        scroll:AddChild(glow)
        local gsize = AceGUI:Create("Slider")
        gsize:SetLabel("Glow Size")
        gsize:SetWidth(260)
        gsize:SetSliderValues(4, 40, 1)
        gsize:SetValue(tonumber(profile.glowSize) or 14)
        gsize:SetCallback("OnValueChanged", function(_, _, v) profile.glowSize = v; Apply() end)
        scroll:AddChild(gsize)
        AddCheck(scroll, "Pulse (the glow breathes slowly)", profile.glowPulse, function(v) profile.glowPulse = v; Apply() end, 300)
        AddCheck(scroll, "Glow around toasts", profile.glowToasts ~= false, function(v) profile.glowToasts = v; Apply() end, 300)
        AddCheck(scroll, "Glow around scoreboard cards", profile.glowCards, function(v) profile.glowCards = v; Apply() end, 300)
        AddCheck(scroll, "Drop shadow behind the window", profile.shadow ~= false, function(v) profile.shadow = v; Apply() end, 300)

        AddHeading(scroll, "Text")
        Pick("Font (" .. #Style:FontNames() .. ")", Style:FontNames(), "font")
        AddChoice(scroll, "Font Outline", Style.OUTLINES, profile.fontOutline or "none",
            function(v) profile.fontOutline = v; Apply() end, 260)
        local tSlider = AceGUI:Create("Slider")
        tSlider:SetLabel("List Text Size")
        tSlider:SetWidth(260)
        tSlider:SetSliderValues(9, 18, 1)
        tSlider:SetValue(tonumber(profile.textSize) or 12)
        tSlider:SetCallback("OnValueChanged", function(_, _, val) profile.textSize = val; Apply() end)
        scroll:AddChild(tSlider)
        local sSlider = AceGUI:Create("Slider")
        sSlider:SetLabel("Window Scale")
        sSlider:SetWidth(260)
        sSlider:SetSliderValues(0.50, 2.50, 0.05)
        sSlider:SetValue(tonumber(profile.uiScale) or 1.0)
        sSlider:SetCallback("OnValueChanged", function(_, _, val) profile.uiScale = val end)
        sSlider:SetCallback("OnMouseUp", function() Apply() end)
        scroll:AddChild(sSlider)
        if not (LibStub and LibStub("LibSharedMedia-3.0", true)) then
            AddLabel(scroll, "|cff888888Tip: with SharedMedia (or ElvUI) installed, its fonts, borders and backgrounds appear in these lists too.|r")
        end

        AddHeading(scroll, "Window & Lists")
        AddCheck(scroll, "Colour-blind friendly colours (blue/orange instead of green/red)", profile.colorblind,
            function(v) profile.colorblind = v; Apply() end, 420)
        AddCheck(scroll, "Show pinned players (your rival and pins) at the top of leaderboards", profile.showPins ~= false,
            function(v) profile.showPins = v; Apply() end, 420)
        local pages = { { "last", "Where I left off" } }
        for _, v in ipairs(FellowshipSync.UI.VIEWS) do table.insert(pages, { v.mod, v.label }) end
        AddChoice(scroll, "Open on", pages, profile.startTab or "last", function(v) profile.startTab = v end, 260)
        AddChoice(scroll, "Open in view", { { "last", "Where I left off" }, { "solo", "My Characters" }, { "guild", "Guild" },
            { "network", "Network" }, { "netaccs", "Accounts" } }, profile.startScope or "last", function(v) profile.startScope = v end, 260)

        AddHeading(scroll, "Distance")
        local UNITS = { "metric", "imperial" }
        local units = AceGUI:Create("Dropdown")
        units:SetLabel("Distance units")
        units:SetWidth(260)
        units:SetList({ "Metric (meters / kilometers)", "Imperial (yards / miles)" })
        units:SetValue(IndexOf(UNITS, profile.distanceUnits or "metric"))
        units:SetCallback("OnValueChanged", function(_, _, key) profile.distanceUnits = UNITS[key]; Apply() end)
        scroll:AddChild(units)
        local steps = AceGUI:Create("CheckBox")
        steps:SetLabel("Show estimated steps for distance on foot")
        steps:SetWidth(320)
        steps:SetValue(profile.showSteps ~= false)
        steps:SetCallback("OnValueChanged", function(_, _, val) profile.showSteps = val; Apply() end)
        scroll:AddChild(steps)

        AddHeading(scroll, "Window")
        local toggles = {
            { key = "showTicker", label = "Show the news ticker at the bottom of the window" },
        }
        for _, t in ipairs(toggles) do
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(t.label)
            cb:SetFullWidth(true)
            cb:SetValue(profile[t.key] ~= false)
            cb:SetCallback("OnValueChanged", function(_, _, val) profile[t.key] = val; Apply() end)
            scroll:AddChild(cb)
        end
        local mm = AceGUI:Create("CheckBox")
        mm:SetLabel("Show minimap button")
        mm:SetFullWidth(true)
        mm:SetValue(not profile.minimap.hide)
        mm:SetCallback("OnValueChanged", function(_, _, val)
            profile.minimap.hide = not val
            FellowshipSync.Extras:UpdateMinimapButton()
        end)
        scroll:AddChild(mm)

    elseif group == "notify" then
        self:DrawNotifications(scroll, profile.notify, container, group)

    elseif group == "profiles" then
        self:DrawProfiles(scroll, container, group)

    elseif group == "fellowship" then
        self:DrawFellowship(scroll, profile, container, group)

    elseif group == "network" then
        AddHeading(scroll, "Guild Sync")

        local syncGuild = AceGUI:Create("CheckBox")
        syncGuild:SetLabel("Share my stats with guild members who use FellowshipSync")
        syncGuild:SetFullWidth(true)
        syncGuild:SetValue(profile.syncGuild ~= false)
        syncGuild:SetCallback("OnValueChanged", function(_, _, val) profile.syncGuild = val end)
        scroll:AddChild(syncGuild)

        AddCheck(scroll, "Show FellowshipSync stats in the game tooltip when I hover guildmates and friends", profile.unitTooltip ~= false,
            function(v) profile.unitTooltip = v end)
        AddCheck(scroll, "Also share my other characters (their last known stats, at login and hourly)", profile.shareAlts ~= false,
            function(v) profile.shareAlts = v end)

        AddHeading(scroll, "Battle.net Friends (cross-faction / cross-realm)")
        local bnetToggles = {
            { key = "syncBNet", label = "Share my stats with Battle.net friends who use FellowshipSync (any faction or realm)" },
            { key = "relayBNet", label = "Pass my friends' stats on to my guild (makes Faction War work across factions)" },
            { key = "allowRelay", label = "Allow my friends to pass MY stats on to their guilds (always off while a password is set)" },
        }
        for _, t in ipairs(bnetToggles) do
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(t.label)
            cb:SetFullWidth(true)
            cb:SetValue(profile[t.key] ~= false)
            cb:SetCallback("OnValueChanged", function(_, _, val) profile[t.key] = val end)
            scroll:AddChild(cb)
        end
        AddSecret(scroll, "Battle.net password (empty = share with every friend who has FellowshipSync)",
            function() return profile.bnetPassword end,
            function(text)
                profile.bnetPassword = text
                FellowshipSync.Comm:ResetTrust()
                FellowshipSync:Print(text == "" and "Battle.net password removed: every friend with FellowshipSync can receive your stats."
                    or "Battle.net password set: only friends who enter the same password receive your stats.")
                self:DrawGroup(container, group)
            end)
        local protected = FellowshipSync.Comm:Protected()
        AddLabel(scroll, (protected
            and "|cff1eff00Password active.|r Friends must enter the same password here before they receive anything from you. "
              .. "Your stats are not passed on to their guilds. Guild members still see your stats unless you turn off guild sync above. "
              .. "Use a password you don't use anywhere else."
            or "|cffffd100No password.|r Any Battle.net friend with FellowshipSync receives your stats.") .. "\n")
        local friendsOnline = #FellowshipSync.Comm:FriendAccounts()
        AddLabel(scroll, string.format("Friends online in WoW: %d   -   %s: %d\n", friendsOnline,
            protected and "verified with your password" or "using FellowshipSync", FellowshipSync.Comm:KnownPeers()))
        AddHeading(scroll, "Display & Identity")

        local badges = AceGUI:Create("CheckBox")
        badges:SetLabel("Show faction / ruleset badges (H-PvE, A-PvP) behind names on network lists")
        badges:SetFullWidth(true)
        badges:SetValue(profile.showBadges ~= false)
        badges:SetCallback("OnValueChanged", function(_, _, val) profile.showBadges = val; Apply() end)
        scroll:AddChild(badges)

        local gear = AceGUI:Create("CheckBox")
        gear:SetLabel("Share equipped GearScore, item level and 16-slot loadout")
        gear:SetFullWidth(true)
        gear:SetValue(profile.shareGear ~= false)
        gear:SetCallback("OnValueChanged", function(_, _, val) profile.shareGear = val end)
        scroll:AddChild(gear)

        local RULES = { "auto", "PvE", "PvP", "HC", "RP" }
        local RULE_LABELS = { "Detect automatically", "PvE realm", "PvP realm", "Hardcore", "Roleplay" }
        local rules = AceGUI:Create("Dropdown")
        rules:SetLabel("My realm ruleset (shown as your badge)")
        rules:SetWidth(260)
        rules:SetList(RULE_LABELS)
        rules:SetValue(IndexOf(RULES, profile.ruleset or "auto"))
        rules:SetCallback("OnValueChanged", function(_, _, key) profile.ruleset = RULES[key]; FellowshipSync.Tracker:Snapshot() end)
        scroll:AddChild(rules)

        AddSecret(scroll, "Secret Network Key (only players with the same key see each other)",
            function() return FellowshipSync.db.global.networkKey end,
            function(text)
                if text == "" then return end
                FellowshipSync.db.global.networkKey = text
                FellowshipSync:Print("Network key updated.")
            end)

        local sendBtn = AceGUI:Create("Button")
        sendBtn:SetText("Broadcast My Stats Now")
        sendBtn:SetWidth(220)
        sendBtn:SetCallback("OnClick", function() FellowshipSync.Comm:BroadcastStats(true) end)
        scroll:AddChild(sendBtn)

        local last = FellowshipSync.Comm.lastSent
        AddLabel(scroll, "\nStats are sent automatically 20 seconds after login and every 10 minutes. "
            .. "Sending is paused in combat and inside instances (a game restriction) and resumes afterwards."
            .. (last and ("\nLast sent: " .. date("%H:%M:%S", last)) or ""))

    elseif group == "privacy" then
        AddHeading(scroll, "What other players can see")
        local priv = {
            { id = "shareCombat",   label = "Combat (kills, deaths, damage, healing)" },
            { id = "shareJourney",  label = "Journey (distance on foot, mounted, flying)" },
            { id = "shareWealth",   label = "Economy (gold, repair bills)" },
            { id = "shareSilly",    label = "Fun stats (critters, jumps, fall damage, chat, AFK time)" },
            { id = "sharePlaytime", label = "Playtime" },
            { id = "shareLocation", label = "Current zone, hearthstone and death zones" },
            { id = "shareProfessions", label = "Professions, nodes gathered and items crafted" },
            { id = "shareLastWords", label = "Famous last words in the Deathlog (your last /say, party, guild... message)" },
            { id = "shareSocial", label = "Fellowship: who I play with (bonds), my rival and my wagers" },
        }
        for _, p in ipairs(priv) do
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(p.label)
            cb:SetFullWidth(true)
            cb:SetValue(profile.privacy[p.id] ~= false)
            cb:SetCallback("OnValueChanged", function(_, _, val) profile.privacy[p.id] = val end)
            scroll:AddChild(cb)
        end
        local gearCb = AceGUI:Create("CheckBox")
        gearCb:SetLabel("Equipped gear (for the inspector)")
        gearCb:SetFullWidth(true)
        gearCb:SetValue(profile.shareGear ~= false)
        gearCb:SetCallback("OnValueChanged", function(_, _, val) profile.shareGear = val end)
        scroll:AddChild(gearCb)
        AddLabel(scroll, "\nClass, race, faction, level, item level, " .. FellowshipSync.POINTS.long:lower() .. " and quests are always shared. "
            .. "Your owner name is the name part of your BattleTag, never the #number.")

    elseif group == "tools" then
        AddHeading(scroll, "Database Tools")

        local total, mine, mock = 0, 0, 0
        for _, d in pairs(FellowshipSync.db.global.characters) do
            total = total + 1
            if d.isMyChar and not d.isMock then mine = mine + 1 end
            if d.isMock then mock = mock + 1 end
        end
        AddLabel(scroll, string.format("Cached characters: %d   (yours: %d, test data: %d)", total, mine, mock))
        AddLabel(scroll, string.format("Your version: %s   -   Newest seen: %s\n", FellowshipSync.VERSION,
            FellowshipSync.newestSeen and (FellowshipSync.newestSeen .. " (" .. tostring(FellowshipSync.newestSeenBy) .. ") - update on CurseForge")
            or "you are up to date"))

        AddButton(scroll, "Run Setup Guide Again", 200, function() FellowshipSync.Setup:Show() end)
        local wipeBtn = AceGUI:Create("Button")
        wipeBtn:SetText("Wipe Network Cache")
        wipeBtn:SetWidth(200)
        wipeBtn:SetCallback("OnClick", function()
            FellowshipSync:WipeNetworkCache()
            self:DrawGroup(container, group)
        end)
        scroll:AddChild(wipeBtn)

        local mockBtn = AceGUI:Create("Button")
        mockBtn:SetText("Add Test Data (230)")
        mockBtn:SetWidth(200)
        mockBtn:SetCallback("OnClick", function()
            FellowshipSync:InjectMockData()
            self:DrawGroup(container, group)
        end)
        scroll:AddChild(mockBtn)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Remove Test Data")
        clearBtn:SetWidth(200)
        clearBtn:SetCallback("OnClick", function()
            FellowshipSync:ClearMockData()
            self:DrawGroup(container, group)
        end)
        scroll:AddChild(clearBtn)

        AddLabel(scroll, "\nWiping keeps your own characters and removes everyone else; they come back as they sync again.")
    end
end

---------------------------------------------------------------------------
-- Notifications tab
---------------------------------------------------------------------------

function Options:DrawNotifications(scroll, n, container, group)
    local FS = FellowshipSync
    local redraw = function() self:DrawGroup(container, group) end

    AddHeading(scroll, "Toasts")
    AddCheck(scroll, "Show toasts (small pop-ups at the top of the screen)", n.toasts, function(v) n.toasts = v; redraw() end)
    if n.toasts then
        AddLabel(scroll, "|cffffd100Your own events|r")
        AddChoice(scroll, "Level-ups", { { "tens", "Every 10 levels + max" }, { "all", "Every level" }, { "max", "Max level only" }, { "off", "Off" } },
            n.own.level, function(v) n.own.level = v end)
        local own = {
            { "boss", "First boss kills" }, { "record", "New fastest boss kills" }, { "gear", "GearScore records" },
            { "prof", "Profession ranks (" .. table.concat(FS.GAME_INFO.profSteps, "/") .. ")" }, { "milestone", "Milestones (jumps, kills, distance, gold...)" },
            { "account", "Account milestones (all your characters together)" },
            { "fun", "Fun moments (revenge, Spirit Healer loyalty card...)" },
            { "fallen", "Hardcore: your character's final death" },
            { "bounty", "Guild bounty completed" }, { "wager", "Wager results" }, { "onthisday", "On this day (anniversaries)" },
        }
        if FS.HAS_POINTS then table.insert(own, 1, { "legacy", FS.POINTS.items .. " completed" }) end
        for _, o in ipairs(own) do
            AddCheck(scroll, o[2], n.own[o[1]], function(v) n.own[o[1]] = v end, 300)
        end

        AddLabel(scroll, "\n|cffffd100Guildmates & friends|r  |cff888888(only news from the last 15 minutes)|r")
        AddChoice(scroll, "Boss kills", { { "first", "Guild firsts only" }, { "all", "Every first kill" }, { "off", "Off" } },
            n.guild.boss, function(v) n.guild.boss = v end)
        AddChoice(scroll, "Level-ups", { { "max", "Max level only" }, { "tens", "Every 10 levels" }, { "off", "Off" } },
            n.guild.level, function(v) n.guild.level = v end)
        local guild = {
            { "fallen", "Hardcore deaths (RIP)" }, { "death", "Every death (busy!)" }, { "record", "New fastest boss kills" },
            { "prof", "Maxed professions (" .. FS.ProfMax() .. ")" }, { "rival", "Someone names me as their rival" },
            { "notices", "Guild notices and polls from officers" }, { "events", "Guild events and 15-minute reminders" },
        }
        if FS.HAS_POINTS then table.insert(guild, 1, { "legacy", FS.POINTS.items .. " completed" }) end
        for _, o in ipairs(guild) do
            AddCheck(scroll, o[2], n.guild[o[1]], function(v) n.guild[o[1]] = v end, 300)
        end
        AddCheck(scroll, "A newer FellowshipSync version is available", n.versionToast ~= false, function(v) n.versionToast = v end, 300)

        AddLabel(scroll, "\n|cffffd100Behaviour|r")
        local dur = AceGUI:Create("Slider")
        dur:SetLabel("Seconds on screen")
        dur:SetWidth(220)
        dur:SetSliderValues(2, 15, 1)
        dur:SetValue(tonumber(n.duration) or 5)
        dur:SetCallback("OnValueChanged", function(_, _, v) n.duration = v end)
        scroll:AddChild(dur)
        local size = AceGUI:Create("Slider")
        size:SetLabel("Toast size")
        size:SetWidth(220)
        size:SetSliderValues(0.6, 1.6, 0.05)
        size:SetIsPercent(true)
        size:SetValue(tonumber(n.scale) or 1)
        size:SetCallback("OnValueChanged", function(_, _, v) n.scale = v; FS.Extras:ApplyToastLayout() end)
        scroll:AddChild(size)
        local sounds = {}
        for _, s in ipairs(FS.Extras:AvailableSounds()) do table.insert(sounds, { s.id, s.label }) end
        AddChoice(scroll, "Sound for my toasts", sounds, n.sound, function(v) n.sound = v; FS.Extras:PlayToastSound(false) end)
        AddChoice(scroll, "Sound for guild toasts", sounds, n.guildSound or n.sound, function(v) n.guildSound = v; FS.Extras:PlayToastSound(true) end)
        AddCheck(scroll, "Wait until combat ends", n.pauseInCombat ~= false, function(v) n.pauseInCombat = v end, 300)
        AddCheck(scroll, "Hold guild toasts while I'm in a dungeon or raid", n.holdInInstances ~= false, function(v) n.holdInInstances = v end, 340)
        AddButton(scroll, FS.Extras.moving and "Lock Position" or "Move Toasts", 140, function()
            FS.Extras:ToggleToastMover(); redraw()
        end)
        AddButton(scroll, "Reset Position", 140, function()
            n.point = { "TOP", 0, -150 }; FS.Extras:ApplyToastLayout()
        end)
        AddButton(scroll, "Test Toast", 120, function() FS.Extras:TestToast() end)
    end

    AddHeading(scroll, "Chat Announcements")
    AddCheck(scroll, "Announce my own big moments in chat", n.announce, function(v) n.announce = v; redraw() end)
    if n.announce then
        AddChoice(scroll, "Where", { { "guild", "Guild chat" }, { "group", "Party / raid chat" }, { "both", "Guild and group" } },
            n.channel, function(v) n.channel = v end)
        AddChoice(scroll, "Boss kills", { { "first", "Guild firsts only" }, { "all", "Every first kill" }, { "off", "Off" } },
            n.ann.boss, function(v) n.ann.boss = v end)
        local ann = {
            { "maxlevel", "Reaching max level (with my levelling time)" }, { "levels", "Every 10 levels" },
            { "record", "New fastest boss kills" }, { "prof", "Maxed professions (" .. FS.ProfMax() .. ")" },
            { "fallen", "Hardcore: my final death" },
        }
        if FS.HAS_POINTS then table.insert(ann, 3, { "legacy", FS.POINTS.items .. " completed" }) end
        for _, o in ipairs(ann) do
            AddCheck(scroll, o[2], n.ann[o[1]], function(v) n.ann[o[1]] = v end, 320)
        end
        AddCheck(scroll, "Include last words in Hardcore death announcements", n.lastWords ~= false, function(v) n.lastWords = v end, 360)
        AddCheck(scroll, "Start messages with [FellowshipSync]", n.prefix ~= false, function(v) n.prefix = v end, 300)
        AddButton(scroll, "Preview", 120, function() FS.Notify:Preview() end)
        AddLabel(scroll, "Messages are plain text, at most one every few seconds, and wait until you are out of combat.")
    end
end

---------------------------------------------------------------------------
-- Profiles tab
---------------------------------------------------------------------------

function Options:DrawProfiles(scroll, container, group)
    local db = FellowshipSync.db
    local redraw = function() self:DrawGroup(container, group) end
    local current = db:GetCurrentProfile()
    local charProfile = db.keys and db.keys.char or FellowshipSync:GetPlayerKey()
    local names = {}
    for _, name in ipairs((db:GetProfiles({}))) do table.insert(names, name) end
    table.sort(names)

    AddHeading(scroll, "Profiles")
    AddLabel(scroll, "A profile holds all FellowshipSync settings (look, notifications, sharing, privacy, minimap). "
        .. "By default every character on your account uses the same profile, |cffffd100Default|r, so you set things up once. "
        .. "Your statistics are always kept per character.\n")
    AddLabel(scroll, "This character uses: |cff1eff00" .. current .. "|r" ..
        (current == "Default" and "  (account-wide)" or (current == charProfile and "  (only this character)" or "")) .. "\n")

    if current ~= "Default" then
        AddButton(scroll, "Use Account-wide Settings", 220, function() db:SetProfile("Default"); redraw() end)
    end
    if current ~= charProfile then
        AddButton(scroll, "Give This Character Its Own Settings", 260, function()
            db:SetProfile(charProfile)
            db:CopyProfile(current) -- start from the settings you had
            redraw()
        end)
    end

    local choices = {}
    for _, name in ipairs(names) do table.insert(choices, { name, name }) end
    AddChoice(scroll, "Switch to profile", choices, current, function(v) db:SetProfile(v); redraw() end, 260)

    local newName = AceGUI:Create("EditBox")
    newName:SetLabel("New profile (starts as a copy of the current one)")
    newName:SetWidth(320)
    newName:SetCallback("OnEnterPressed", function(_, _, text)
        text = strtrim(text or "")
        if text == "" then return end
        db:SetProfile(text)
        db:CopyProfile(current)
        redraw()
    end)
    scroll:AddChild(newName)

    local others = {}
    for _, name in ipairs(names) do if name ~= current then table.insert(others, { name, name }) end end
    if #others > 0 then
        AddLabel(scroll, "")
        AddChoice(scroll, "Copy settings from", others, nil, function(v) db:CopyProfile(v); redraw() end, 260)
        local deletable = {}
        for _, o in ipairs(others) do if o[1] ~= "Default" then table.insert(deletable, o) end end
        if #deletable > 0 then
            AddChoice(scroll, "Delete profile", deletable, nil, function(v)
                db:DeleteProfile(v)
                FellowshipSync:Print("Deleted profile " .. v .. ".")
                redraw()
            end, 260)
        end
    end
    AddLabel(scroll, "")
    AddButton(scroll, self.confirmReset and "Click again to reset" or "Reset Current Profile", 200, function()
        if self.confirmReset then
            self.confirmReset = false
            db:ResetProfile()
            FellowshipSync:Print("Profile " .. current .. " reset to default settings.")
        else
            self.confirmReset = true
            FellowshipSync:ScheduleTimer(function() self.confirmReset = false end, 5)
        end
        redraw()
    end)
end

---------------------------------------------------------------------------
-- Fellowship tab: Memory Lane and Deathmap
---------------------------------------------------------------------------

function Options:DrawFellowship(scroll, profile, container, group)
    local m, d = profile.memory, profile.deathmap
    local redraw = function() self:DrawGroup(container, group) end
    AddHeading(scroll, "Memory Lane")
    AddCheck(scroll, "Take a screenshot at my big moments (about a second later, so the toast is in the picture)", m.enabled,
        function(v) m.enabled = v; redraw() end)
    if m.enabled then
        local kinds = {
            { "maxlevel", "Reaching max level" }, { "levels", "Every 10 levels" }, { "firsts", "Guild first boss kills" },
            { "boss", "My first kill of any boss" }, { "record", "New fastest boss kills" }, { "fallen", "Hardcore: my final death" },
            { "bounty", "Guild bounty completed" },
        }
        if FellowshipSync.HAS_POINTS then table.insert(kinds, 3, { "legacy", FellowshipSync.POINTS.items .. " completed" }) end
        for _, k in ipairs(kinds) do AddCheck(scroll, k[2], m[k[1]], function(v) m[k[1]] = v end, 300) end
        AddLabel(scroll, "Screenshots go to your World of Warcraft Screenshots folder. At most one every 10 seconds.")
    end
    AddHeading(scroll, "Deathmap")
    AddCheck(scroll, "Show a skull on the world map for every recorded death", d.worldMap ~= false, function(v)
        d.worldMap = v; FellowshipSync.Deathmap:Refresh()
    end)
    local refresh = function() FellowshipSync.Deathmap:Refresh() end
    AddChoice(scroll, "Whose deaths", { { "solo", "My characters" }, { "guild", "Guild" }, { "network", "Everyone I know" } },
        d.scope or "guild", function(v) d.scope = v; refresh() end)
    AddChoice(scroll, "Show", { { "skulls", "Skulls" }, { "hot", "Hot zones" }, { "both", "Skulls and hot zones" } },
        d.mode or "skulls", function(v) d.mode = v; refresh() end)
    AddChoice(scroll, "Time window", { { 0, "All time" }, { 7, "Last 7 days" }, { 30, "Last 30 days" }, { 90, "Last 90 days" } },
        d.days or 0, function(v) d.days = v; refresh() end)
    AddChoice(scroll, "Hot zone size", { { "fine", "Small, precise areas" }, { "medium", "Medium areas" }, { "coarse", "Large areas" } },
        d.hotGrid or "medium", function(v) d.hotGrid = v; refresh() end)
    local size = AceGUI:Create("Slider")
    size:SetLabel("Skull size")
    size:SetWidth(220)
    size:SetSliderValues(8, 32, 1)
    size:SetValue(tonumber(d.size) or 14)
    size:SetCallback("OnValueChanged", function(_, _, v) d.size = v; refresh() end)
    scroll:AddChild(size)
    local max = AceGUI:Create("Slider")
    max:SetLabel("Most skulls shown")
    max:SetWidth(220)
    max:SetSliderValues(25, 1000, 25)
    max:SetValue(tonumber(d.max) or 400)
    max:SetCallback("OnValueChanged", function(_, _, v) d.max = v; refresh() end)
    scroll:AddChild(max)
    AddCheck(scroll, "Hardcore final deaths only", d.hcOnly, function(v) d.hcOnly = v; refresh() end, 300)
    AddCheck(scroll, "Highlight my own deaths in gold", d.highlightMine ~= false, function(v) d.highlightMine = v; refresh() end, 300)
end
