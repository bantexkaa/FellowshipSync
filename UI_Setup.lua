local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Setup = FS.Setup
local W = FS.W

---------------------------------------------------------------------------
-- First-time setup guide: quick start, or tailor sharing, privacy,
-- notifications and look in five short steps. Re-run with /fsync setup.
---------------------------------------------------------------------------

local STEPS = { "Welcome", "Sharing", "Privacy", "Notifications", "Look" }
local PRIVACY = {
    { "shareCombat", "Combat: kills, deaths, damage, healing, deathlog" },
    { "shareJourney", "Journey: distances, flights, exploration" },
    { "shareWealth", "Gold: wealth, gold looted and spent" },
    { "shareSilly", "Fun stats: jumps, critters, emotes, loot, rolls" },
    { "sharePlaytime", "Playtime and levelling times" },
    { "shareLocation", "Where I am: zone, hearthstone, death positions" },
    { "shareProfessions", "Professions" },
    { "shareLastWords", "Famous last words in the Deathlog" },
    { "shareSocial", "Fellowship: bonds, rival, wagers" },
}

local function Input(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 24)
    box:SetBackdrop(W.FLAT)
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-- A row of mutually exclusive buttons: options = { {value, label}, ... }
local function Choice(parent, options, width, onPick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(#options * (width + 6), 24)
    row.buttons = {}
    for i, o in ipairs(options) do
        local b = W.Button(row, o[2], width, 24, function() row:Set(o[1]); onPick(o[1]) end)
        b:SetPoint("LEFT", (i - 1) * (width + 6), 0)
        b.value = o[1]
        row.buttons[i] = b
    end
    function row:Set(value) for _, b in ipairs(self.buttons) do b:SetActive(b.value == value) end end
    return row
end

function Setup:Build()
    if self.frame then return end
    local f = W.Box(UIParent, "panel")
    f:SetSize(620, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    _G.FellowshipSyncSetup = f
    tinsert(UISpecialFrames, "FellowshipSyncSetup")
    self.frame = f

    f.title = W.Text(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 20, -16)
    f.progress = W.Text(f, "GameFontDisableSmall", "RIGHT")
    f.progress:SetPoint("TOPRIGHT", -20, -20)
    self.back = W.Button(f, "Back", 100, 26, function() self:Go(self.step - 1) end)
    self.back:SetPoint("BOTTOMLEFT", 20, 16)
    self.nextBtn = W.Button(f, "Next", 120, 26, function()
        if self.step < #STEPS then self:Go(self.step + 1) else self:Finish() end
    end)
    self.nextBtn:SetPoint("BOTTOMRIGHT", -20, 16)
    self.skip = W.Button(f, "Skip for now", 120, 26, function() self:Finish(true) end)
    self.skip:SetPoint("RIGHT", self.nextBtn, "LEFT", -8, 0)

    self.pages = {}
    for i = 1, #STEPS do
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 20, -50)
        p:SetPoint("BOTTOMRIGHT", -20, 56)
        p:Hide()
        self.pages[i] = p
    end
    self:BuildWelcome(self.pages[1])
    self:BuildSharing(self.pages[2])
    self:BuildPrivacy(self.pages[3])
    self:BuildNotifications(self.pages[4])
    self:BuildLook(self.pages[5])
end

local function Para(page, text, y, template)
    local fs = page:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetWidth(580)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    return fs
end

function Setup:BuildWelcome(p)
    Para(p, "Welcome to |cffffd100Fellowship|rSync!", 0, "GameFontNormalLarge")
    Para(p, "FellowshipSync records your adventures and shares them with your guild and friends: leaderboards, a deathlog, "
        .. "a guild bestiary, weekly bounties, your own Book of Deeds and much more.\n\nHow would you like to start?", -30)
    local quick = W.Button(p, "Quick Start (recommended settings)", 280, 34, function() self:Finish() end)
    quick:SetPoint("TOPLEFT", 0, -130)
    local tailor = W.Button(p, "Let me choose what to share", 280, 34, function() self:Go(2) end)
    tailor:SetPoint("LEFT", quick, "RIGHT", 16, 0)
    Para(p, "Recommended: share with your guild and Battle.net friends, everything visible, toasts for big moments, "
        .. "no chat announcements. You can change any of this later in Options.", -186, "GameFontDisableSmall")
end

function Setup:BuildSharing(p)
    Para(p, "Who should see your stats?", 0, "GameFontNormal")
    p.checks = {}
    local rows = {
        { "syncGuild", "My guild (members who use FellowshipSync)" },
        { "syncBNet", "My Battle.net friends who use FellowshipSync (any faction or realm)" },
        { "relayBNet", "Pass my friends' stats on to my guild (makes Faction War work)" },
        { "shareAlts", "Also share my other characters' last known stats" },
    }
    for i, r in ipairs(rows) do
        local cb = W.Check(p, r[2], function(v) FS.db.profile[r[1]] = v end)
        cb:SetPoint("TOPLEFT", 0, -28 - (i - 1) * 28)
        cb.key = r[1]
        p.checks[i] = cb
    end
    Para(p, "Battle.net password (optional): only friends who enter the same password receive your stats.", -148, "GameFontHighlightSmall")
    p.password = Input(p, 260)
    p.password:SetPoint("TOPLEFT", 0, -172)
    p.password:SetScript("OnTextChanged", function(box)
        FS.db.profile.bnetPassword = strtrim(box:GetText() or "")
        if FS.Comm.ResetTrust then FS.Comm:ResetTrust() end
    end)
end

function Setup:BuildPrivacy(p)
    Para(p, "What may others see? Untick anything you'd rather keep to yourself.", 0, "GameFontNormal")
    p.checks = {}
    for i, r in ipairs(PRIVACY) do
        local cb = W.Check(p, r[2], function(v) FS.db.profile.privacy[r[1]] = v end)
        cb:SetPoint("TOPLEFT", 0, -26 - (i - 1) * 26)
        cb.key = r[1]
        p.checks[i] = cb
    end
    p.gear = W.Check(p, "My equipped gear (for the inspector)", function(v) FS.db.profile.shareGear = v end)
    p.gear:SetPoint("TOPLEFT", 0, -26 - #PRIVACY * 26)
end

function Setup:BuildNotifications(p)
    local n = function() return FS.db.profile.notify end
    Para(p, "Pop-up toasts for my own moments", 0, "GameFontNormal")
    p.toasts = Choice(p, { { "all", "Everything" }, { "big", "Big moments only" }, { "off", "Off" } }, 150, function(v) self:SetToastStyle(v) end)
    p.toasts:SetPoint("TOPLEFT", 0, -22)
    Para(p, "Toasts for guildmates and friends (guild firsts, max level, Hardcore deaths)", -62, "GameFontNormal")
    p.guild = Choice(p, { { "on", "On" }, { "off", "Off" } }, 150, function(v) self:SetGuildToasts(v == "on") end)
    p.guild:SetPoint("TOPLEFT", 0, -84)
    p.announce = W.Check(p, "Announce my big moments in guild chat (max level, guild firsts, records)", function(v) n().announce = v end)
    p.announce:SetPoint("TOPLEFT", 0, -126)
    p.shots = W.Check(p, "Take screenshots of my big moments (Memory Lane)", function(v) FS.db.profile.memory.enabled = v end)
    p.shots:SetPoint("TOPLEFT", 0, -154)
    p.map = W.Check(p, "Show deaths on the world map (Deathmap)", function(v) FS.db.profile.deathmap.worldMap = v end)
    p.map:SetPoint("TOPLEFT", 0, -182)
end

function Setup:BuildLook(p)
    Para(p, "Colour theme", 0, "GameFontNormal")
    p.prev = W.Button(p, "<", 28, 24, function() self:CycleTheme(-1) end)
    p.prev:SetPoint("TOPLEFT", 0, -22)
    p.theme = W.Text(p, "GameFontHighlight", "CENTER")
    p.theme:SetPoint("LEFT", p.prev, "RIGHT", 6, 0)
    p.theme:SetWidth(200)
    p.next = W.Button(p, ">", 28, 24, function() self:CycleTheme(1) end)
    p.next:SetPoint("LEFT", p.theme, "RIGHT", 6, 0)
    Para(p, "Style", -62, "GameFontNormal")
    local presets = {}
    for i, preset in ipairs(FS.Style.PRESETS) do presets[i] = { i, preset[1] } end
    p.style = Choice(p, presets, 104, function(i) FS.Style:ApplyPreset(i) end)
    p.style:SetPoint("TOPLEFT", 0, -84)
    Para(p, "Distances", -124, "GameFontNormal")
    p.units = Choice(p, { { "metric", "Meters / kilometers" }, { "imperial", "Yards / miles" } }, 180,
        function(v) FS.db.profile.distanceUnits = v end)
    p.units:SetPoint("TOPLEFT", 0, -146)
    p.minimap = W.Check(p, "Show the minimap button", function(v)
        FS.db.profile.minimap.hide = not v
        FS.Extras:UpdateMinimapButton()
    end)
    p.minimap:SetPoint("TOPLEFT", 0, -186)
    p.ticker = W.Check(p, "Show the news ticker at the bottom of the window", function(v) FS.db.profile.showTicker = v end)
    p.ticker:SetPoint("TOPLEFT", 0, -214)
    Para(p, "More themes, fonts, borders, glow and shadow: Options > Cosmetics & UI.", -248, "GameFontDisableSmall")
end

function Setup:SetToastStyle(style)
    local n = FS.db.profile.notify
    n.toasts = style ~= "off"
    if style == "all" then
        n.own.level = "all"
        for _, k in ipairs({ "gear", "prof", "milestone" }) do n.own[k] = true end
    elseif style == "big" then
        n.own.level = "max"
        for _, k in ipairs({ "gear", "prof", "milestone" }) do n.own[k] = false end
    end
end

function Setup:SetGuildToasts(on)
    local g = FS.db.profile.notify.guild
    g.boss, g.level = on and "first" or "off", on and "max" or "off"
    g.fallen, g.record, g.rival = on, on, on
end

function Setup:CycleTheme(delta)
    local names = {}
    for name in pairs(FS.UI.THEME_PALETTES) do table.insert(names, name) end
    table.sort(names)
    local index = 1
    for i, name in ipairs(names) do if name == FS.db.profile.theme then index = i end end
    FS.db.profile.theme = names[((index - 1 + delta) % #names) + 1]
    self.pages[5].theme:SetText(FS.db.profile.theme)
    if FS.UI.MainFrame then FS.UI:ApplyTheme() end
end

-- Puts the current settings into the controls of a page.
function Setup:Fill(i)
    local profile, p = FS.db.profile, self.pages[i]
    if i == 2 then
        for _, cb in ipairs(p.checks) do cb:SetChecked(profile[cb.key] ~= false) end
        p.password:SetText(profile.bnetPassword or "")
    elseif i == 3 then
        for _, cb in ipairs(p.checks) do cb:SetChecked(profile.privacy[cb.key] ~= false) end
        p.gear:SetChecked(profile.shareGear ~= false)
    elseif i == 4 then
        local n = profile.notify
        p.toasts:Set(not n.toasts and "off" or (n.own.level == "max" and "big" or "all"))
        p.guild:Set((n.guild.boss ~= "off" or n.guild.level ~= "off") and "on" or "off")
        p.announce:SetChecked(n.announce and true or false)
        p.shots:SetChecked(profile.memory.enabled ~= false)
        p.map:SetChecked(profile.deathmap.worldMap ~= false)
    elseif i == 5 then
        p.theme:SetText(profile.theme)
        p.units:Set(profile.distanceUnits or "metric")
        p.minimap:SetChecked(not profile.minimap.hide)
        p.ticker:SetChecked(profile.showTicker ~= false)
    end
end

function Setup:Go(i)
    self.step = math.max(1, math.min(#STEPS, i))
    for n, p in ipairs(self.pages) do p:SetShown(n == self.step) end
    self:Fill(self.step)
    local f = self.frame
    f.title:SetText(self.step == 1 and "FellowshipSync Setup" or STEPS[self.step])
    W.AccentText(f.title)
    f.progress:SetText(string.format("Step %d of %d", self.step, #STEPS))
    self.back:SetShown(self.step > 1)
    self.nextBtn:SetShown(self.step > 1)
    self.nextBtn.text:SetText(self.step == #STEPS and "Finish" or "Next")
    self.skip:SetShown(self.step == 1)
end

function Setup:Show()
    self:Build()
    self:Go(1)
    self.frame:Show()
end

function Setup:Finish(skipped)
    FS.db.global.setupDone = true
    self.frame:Hide()
    if FS.UI.MainFrame then FS.UI:ApplyTheme() end
    FS.Extras:UpdateMinimapButton()
    if FS.Deathmap.Refresh then FS.Deathmap:Refresh() end
    FS:Print(skipped and "Setup skipped. Run it any time with /fsync setup."
        or "You're all set! Type /fsync to open FellowshipSync. Change anything later in Options.")
end
