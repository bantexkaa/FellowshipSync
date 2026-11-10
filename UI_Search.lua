local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local UI, W = FS.UI, FS.W

---------------------------------------------------------------------------
-- Help texts ("?" next to each page title), global search, and navigation
-- (used by search results and by clicking a toast).
---------------------------------------------------------------------------

FS.HELP = {
    Dashboard = "Top five of each scoreboard. Choose scoreboards with \"Choose Scoreboards\" and drag a title onto another to swap them. Click any name for the full profile.",
    Combat = "Combat leaderboards. Click a column header to sort.",
    ["Combat.mobs"] = "Every enemy type your characters (or guild) have killed. One kill per enemy, never double-counted.",
    ["Combat.raids"] = "Boss kills, wipes and fastest kills from dungeon and raid encounters, with the first guild member to kill each boss.",
    Misc = "Gear, professions, travel and the silly boards. Click a column header to sort.",
    FactionWar = "Horde against Alliance in 12 categories. The MVP leads the most categories. Outside Retail this always uses your whole network.",
    Profiles = "One card per player with all their synced characters.",
    Records = "Personal bests, habits and about 40 statistics. In My Characters you get your own records page.",
    ["Records.compare"] = "Pick two characters with the arrows. Every stat side by side; the number in the title is how many stats each one leads.",
    Deathlog = "Every death with killer, zone and the last thing said before dying. Search by name, killer or zone.",
    Chronicle = "Guild firsts, levelling speedruns, the weekly newspaper and the Hardcore memorial.",
    FellowshipUI = "Friendship bonds, guild bounties, the Book of Deeds, the Deathmap, wagers, rivalries and games.",
    GuildUI = "Guild tools. Members can read, vote and sign up; officers (chosen by the guild leader) can create things.",
    Options = "All settings. Use Simple for the ten most-used settings, or Advanced for everything.",
}

-- How kills are counted differs per game, so say it where kill numbers appear.
local KILLS_NOTE = {
    combatLog = " Kills are exact here: every killing blow by you or your pet from the combat log.",
    noCombatLog = " On this game version addons can't read the combat log, so kills count enemies that die on your target or nameplates after you or your group tagged them (an estimate).",
}

function FS.HelpText(mod, current)
    local text = (current and FS.HELP[mod .. "." .. current]) or FS.HELP[mod] or "Click a column header to sort. Hover rows for details."
    if mod == "Combat" or mod == "Dashboard" then
        text = text .. (FS.HAS_COMBAT_LOG and KILLS_NOTE.combatLog or KILLS_NOTE.noCombatLog)
    end
    return text
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local Nav = {}
FS.Nav = Nav

local function Open()
    if not (UI.MainFrame and UI.MainFrame:IsShown()) then FS:ToggleUI() end
end

-- Go to a module (and sub-tab), optionally pre-filling its search box.
function Nav:Go(mod, sub, query)
    Open()
    local index = UI.modIndex and UI.modIndex[mod]
    if not index then return end
    local view = FS[mod]
    if sub and view then view.current = sub end
    UI:SelectTab(index)
    if view and view.search and query then
        view.search:SetText(query)
        view.query = query:lower()
        view:Refresh()
    end
end

function Nav:Character(key)
    local rec = FS.db.global.characters[key or ""]
    if not rec then return false end
    Open()
    UI:OpenInspector(rec)
    return true
end

-- Clicking a toast takes you to what it was about.
function Nav:FromEvent(ev)
    if not ev then Open() return end
    local k = ev.kind
    if k == "boss" or k == "record" then return self:Go("Combat", "raids", tostring(ev.a or "")) end
    if k == "milestone" or k == "accmilestone" then return self:Go("Records", "my") end
    if k == "bounty" then return self:Go("FellowshipUI", "bounties") end
    if k == "wager" then return self:Go("FellowshipUI", "wagers") end
    if k == "rival" then return self:Go("FellowshipUI", "rivals") end
    if k == "notice" then return self:Go("GuildUI", "notices") end
    if k == "poll" then return self:Go("GuildUI", "polls") end
    if k == "event" then return self:Go("GuildUI", "events") end
    if k == "death" or k == "fallen" then return self:Go("Deathlog", nil, FS.ShortName(ev.who or "")) end
    if ev.who and self:Character(ev.who) then return end
    Open()
end

---------------------------------------------------------------------------
-- Global search: characters, enemies, bosses, killers and zones
---------------------------------------------------------------------------

local GS = {}
FS.GlobalSearch = GS

function GS:Results(q)
    q = (q or ""):lower()
    if #q < 2 then return {} end
    local out, seen = {}, {}
    local function Add(kind, text, action, key)
        key = kind .. ":" .. key
        if seen[key] or #out >= 14 then return end
        seen[key] = true
        table.insert(out, { kind = kind, text = text, action = action })
    end
    local chars = FS.db.global.characters
    local names = {}
    for name in pairs(chars) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        if name:lower():find(q, 1, true) then
            Add(W.T("Character"), W.CharName(chars[name]), function() Nav:Character(name) end, name)
        end
    end
    for _, rec in pairs(chars) do
        for mob in pairs(rec.mobs or {}) do
            if mob:lower():find(q, 1, true) then Add(W.T("Enemy"), mob, function() Nav:Go("Combat", "mobs", mob) end, mob) end
        end
        for boss in pairs(rec.encounters or {}) do
            if boss:lower():find(q, 1, true) then Add(W.T("Boss"), boss, function() Nav:Go("Combat", "raids", boss) end, boss) end
        end
        for _, d in ipairs(rec.deathLog or {}) do
            if d.killer and d.killer:lower():find(q, 1, true) then
                Add(W.T("Killer"), d.killer, function() Nav:Go("Deathlog", nil, d.killer) end, d.killer)
            end
            if d.zone and d.zone ~= "" and d.zone:lower():find(q, 1, true) then
                Add(W.T("Zone"), d.zone, function() Nav:Go("Deathlog", nil, d.zone) end, d.zone)
            end
        end
        for _, z in ipairs(rec.zones or {}) do
            if type(z[1]) == "string" and z[1]:lower():find(q, 1, true) then
                Add(W.T("Zone"), z[1], function() Nav:Go("Records", "zones", z[1]) end, z[1])
            end
        end
    end
    local order = { [W.T("Character")] = 1, [W.T("Boss")] = 2, [W.T("Enemy")] = 3, [W.T("Killer")] = 4, [W.T("Zone")] = 5 }
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return (order[a.kind] or 9) < (order[b.kind] or 9) end
        return W.Plain(a.text) < W.Plain(b.text)
    end)
    return out
end

function GS:Build()
    if self.frame then return end
    local f = W.Box(UI.MainFrame, "panel")
    f:SetFrameStrata("DIALOG")
    f:SetWidth(340)
    f:SetPoint("TOPRIGHT", UI.globalSearch, "BOTTOMRIGHT", 0, -2)
    f.rows = {}
    for i = 1, 14 do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 20)
        b:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.15)
        b.kind = W.Text(b, "GameFontDisableSmall")
        b.kind:SetPoint("LEFT", 4, 0)
        b.kind:SetWidth(70)
        b.label = W.Text(b, "GameFontHighlightSmall")
        b.label:SetPoint("LEFT", 78, 0)
        b.label:SetWidth(250)
        b:SetScript("OnClick", function(btn)
            f:Hide()
            UI.globalSearch:SetText("")
            if btn.action then btn.action() end
        end)
        f.rows[i] = b
    end
    f.none = W.Text(f, "GameFontDisableSmall")
    f.none:SetPoint("TOPLEFT", 10, -10)
    self.frame = f
end

function GS:Show(q)
    if not UI.MainFrame then return end
    self:Build()
    local results = self:Results(q)
    local f = self.frame
    if #(q or "") < 2 then f:Hide() return end
    for i, b in ipairs(f.rows) do
        local r = results[i]
        b:SetShown(r ~= nil)
        if r then b.kind:SetText(r.kind); b.label:SetText(r.text); b.action = r.action end
    end
    f.none:SetShown(#results == 0)
    f.none:SetText(W.T("Nothing found."))
    f:SetHeight(math.max(32, #results * 20 + 12))
    f:Show()
    self.results = results
end
