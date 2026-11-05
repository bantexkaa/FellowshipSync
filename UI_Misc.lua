local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Misc = FS.Misc
local UI, W = FS.UI, FS.W

local TABS = {
    { id = "gear",   label = "Gear & iLvl" },
    { id = "legacy", label = FS.POINTS.tab },
    { id = "silly",  label = "Silly Boards" },
    { id = "rolls",  label = "Loot Rolls" },
    { id = "prof",   label = "Professions" },
    { id = "travel", label = "Travel" },
    { id = "jumps",  label = "Jumps",   key = "jumps",      title = "Jump Leaderboard" },
    { id = "fish",   label = "Fishing", key = "fish",       title = "Fishing Kings" },
    { id = "quests", label = "Quests",  key = "quests",     title = "Quests Completed" },
    { id = "gold",   label = "Gold",    key = "goldLooted", title = "Total Gold Looted" },
    { id = "epics",  label = "Epics",   key = "epics",      title = "Epics Looted" },
}
local SILLY = {
    { id = "critters",   label = "Critters Butchered", title = "Most Critters Butchered" },
    { id = "repairs",    label = "Repair Bills",       title = "Highest Repair Bills (Gold Wasted)" },
    { id = "chat",       label = "Chatterbox",         title = "Biggest Chatterbox (Messages Sent)" },
    FS.HAS_COMBAT_LOG and { id = "fallDamage", label = "Gravity Victims", title = "Most Fall Damage Taken" }
        or { id = "fallDeaths", label = "Gravity Victims", title = "Most Deaths by Falling" },
    { id = "afk",        label = "AFK Champion",       title = "AFK Champion (Minutes Away)" },
    { id = "flightTime", label = "Frequent Flyer",     title = "Frequent Flyer (Time on Flight Paths)" },
}
local FEED_KINDS = { legacy = true, prof = true, level = true, boss = true }

function Misc:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current, self.silly = "gear", "critters"

    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.sillyTabs = W.SubTabs(f, (function()
        local t = {}
        for _, s in ipairs(SILLY) do table.insert(t, { id = s.id, label = s.label }) end
        return t
    end)(), 980, function(id) self.silly = id; self:Refresh() end, 22)
    self.sillyTabs:SetPoint("TOPLEFT", 14, -48)

    self.title = W.Text(f, "GameFontNormalLarge")
    self.search = W.Search(f, 260, "Search character or owner...", function(q) self.query = q; self:Refresh() end)
    self.search:SetPoint("TOPRIGHT", -36, -44)
    self.sub = W.Text(f, "GameFontDisableSmall")

    local open = function(rec) UI:OpenInspector(rec, self.lastRecs) end
    self.lists = {
        simple = W.List(f, {
            { label = "#", width = 36 }, { label = "Character", width = 400 }, { label = "Class", width = 120 },
            { label = "Value", width = 200, justify = "RIGHT" }, { label = "", width = 130, justify = "RIGHT" },
        }, { onClick = open }),
        gear = W.List(f, {
            { label = "#", width = 36 }, { label = "Character", width = 300 }, { label = "GearScore", width = 90, justify = "RIGHT" },
            { label = "Equipped iLvl", width = 90, justify = "RIGHT" }, { label = "Overall iLvl", width = 90, justify = "RIGHT" },
            { label = "Highest Equipped Item", width = 250 },
        }, { onClick = open }),
        multi = W.List(f, {
            { label = "#", width = 36 }, { label = "Character", width = 300 }, { label = "", width = 260 },
            { label = "", width = 100, justify = "RIGHT" }, { label = "", width = 90, justify = "RIGHT" },
            { label = "", width = 80, justify = "RIGHT" },
        }, { onClick = open }),
        travel = W.List(f, {
            { label = "#", width = 32 }, { label = "Character", width = 230 }, { label = "On Foot", width = 100, justify = "RIGHT" },
            { label = "Steps (est.)", width = 95, justify = "RIGHT" }, { label = "Mounted", width = 100, justify = "RIGHT" },
            { label = "Flying", width = 100, justify = "RIGHT" }, { label = "Swimming", width = 90, justify = "RIGHT" },
            { label = "Total", width = 110, justify = "RIGHT" },
        }, { onClick = open }),
        rolls = W.List(f, {
            { label = "#", width = 30 }, { label = "Character", width = 200 }, { label = "Need", width = 60, justify = "RIGHT" },
            { label = "Greed", width = 60, justify = "RIGHT" }, { label = "Pass", width = 60, justify = "RIGHT" },
            { label = "Won (Need)", width = 80, justify = "RIGHT" }, { label = "Won (Greed)", width = 85, justify = "RIGHT" },
            { label = "Won Total", width = 80, justify = "RIGHT" }, { label = "/roll", width = 50, justify = "RIGHT" },
            { label = "Nat 100", width = 60, justify = "RIGHT" }, { label = "Nat 1", width = 50, justify = "RIGHT" },
        }, { onClick = open }),
        profs = W.List(f, {
            { label = "#", width = 30 }, { label = "Character", width = 200 }, { label = "Main Profession 1", width = 150 },
            { label = "Main Profession 2", width = 150 }, { label = "Secondary Skills", width = 220 },
            { label = "Gathered", width = 70, justify = "RIGHT" }, { label = "Crafted", width = 70, justify = "RIGHT" },
            { label = "Progress", width = 70, justify = "RIGHT" },
        }, { onClick = open }),
        feed = W.List(f, {
            { label = "Date", width = 120 }, { label = "Character", width = 260 }, { label = "Milestone", width = 470 },
            { label = FS.POINTS.short, width = 50, justify = "RIGHT" },
        }, { onClick = open, emptyText = "No milestones yet. Level-ups, profession ranks and " .. FS.POINTS.items:lower() .. " appear here." }),
    }
end

function Misc:ShowList(name, top)
    for key, l in pairs(self.lists) do
        l.frame:SetShown(key == name)
        l.frame:ClearAllPoints()
        l.frame:SetPoint("TOPLEFT", 14, top)
        l.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    end
    return self.lists[name]
end

function Misc:Records()
    local recs = {}
    for _, r in ipairs(FS:GetFilteredCharacters(UI.currentScope)) do
        if W.Matches(r, self.query) then table.insert(recs, r) end
    end
    return recs
end

local function TabById(id) for _, t in ipairs(TABS) do if t.id == id then return t end end end
local function SillyById(id) for _, s in ipairs(SILLY) do if s.id == id then return s end end end

function Misc:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    local isSilly = self.current == "silly"
    self.sillyTabs:SetShown(isSilly)
    if isSilly then self.sillyTabs:Select(self.silly, true) end
    local top = isSilly and -108 or -80
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", 14, isSilly and -84 or -52)
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPRIGHT", -36, isSilly and -82 or -50)
    local suffix = "  -  " .. UI.SCOPE_TITLES[UI.currentScope] .. (FS:IsWeekMode() and " (This Week)" or "")

    local tab = TabById(self.current)
    if self.current == "gear" then
        self.title:SetText("GearScore & Average Item Level" .. suffix)
        self:RefreshGear(self:ShowList("gear", top))
    elseif self.current == "legacy" then
        self.title:SetText(FS.POINTS.feed .. suffix)
        self:RefreshFeed(self:ShowList("feed", top))
    elseif self.current == "rolls" then
        self.title:SetText("The Greed Board" .. suffix)
        self:RefreshRolls(self:ShowList("rolls", top))
    elseif self.current == "travel" then
        self.title:SetText("Globetrotters: Distance Travelled" .. suffix)
        self:RefreshTravel(self:ShowList("travel", top))
    elseif self.current == "prof" then
        self.title:SetText("Profession Tracker" .. suffix)
        self:RefreshProfs(self:ShowList("profs", top))
    elseif isSilly then
        local s = SillyById(self.silly)
        self.title:SetText(s.title .. suffix)
        self:RefreshSimple(self:ShowList("simple", top), s.id)
    else
        self.title:SetText(tab.title .. suffix)
        self:RefreshSimple(self:ShowList("simple", top), tab.key)
    end
end

function Misc:RefreshSimple(list, key)
    local recs = FS:SortByStat(self:Records(), key)
    self.lastRecs = recs
    list:SetColumnLabel(4, FS.STATS[key].label)
    local rows = {}
    for i, r in ipairs(recs) do
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
                    cells = { W.Rank(i), W.Label(r), r.isAccount and "" or UI:FormatClassText(r.cls),
                              W.RankValue(i, W.FormatStat(key, FS:GetValue(r, key))), "" } }
    end
    list:SetRows(rows)
end

function Misc:RefreshGear(list)
    local recs = FS:SortByStat(self:Records(), "gs")
    self.lastRecs = recs
    local rows = {}
    for i, r in ipairs(recs) do
        local best = r.highest
        local bestText = (best and best.link) and (best.link .. W.Color(" (" .. (best.ilvl or 0) .. ")", "aaaaaa")) or W.Color("-", "666666")
        if r.isAccount then bestText = W.Color("Best: " .. FS.ShortName(r.bestChar and r.bestChar.fullName), "aaaaaa") end
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
                    cells = { W.Rank(i), W.Label(r), W.Color(W.Num(r.gs), W.GsHex(r.gs, r.ilvl)),
                              W.Color(string.format("%.1f", r.ilvl or 0), "ffd100"),
                              W.Color(string.format("%.1f", r.ilvlBag or 0), "aaaaaa"), bestText } }
    end
    list:SetRows(rows)
end

function Misc:RefreshTravel(list)
    local recs = FS:SortByStat(self:Records(), "travelTotal")
    self.lastRecs = recs
    local steps = W.ShowSteps()
    list:SetColumnLabel(4, steps and "Steps (est.)" or "")
    local rows = {}
    for i, r in ipairs(recs) do
        local foot = FS:GetValue(r, "travelFoot")
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
                    cells = { W.Rank(i), W.Label(r), W.Distance(foot), steps and W.Color(W.Num(foot / W.METERS_PER_STEP), "aaaaaa") or "",
                              W.Distance(FS:GetValue(r, "travelMount")), W.Distance(FS:GetValue(r, "travelFlight")),
                              W.Distance(FS:GetValue(r, "travelSwim")), W.RankValue(i, W.Distance(FS:GetValue(r, "travelTotal"))) } }
    end
    list:SetRows(rows)
end

function Misc:RefreshRolls(list)
    local recs = FS:SortByStat(self:Records(), "rollsWon")
    self.lastRecs = recs
    local rows = {}
    for i, r in ipairs(recs) do
        local function v(k) return W.Num(FS:GetValue(r, k)) end
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
                    cells = { W.Rank(i), W.Label(r), v("needRolls"), v("greedRolls"), W.Color(v("passRolls"), "888888"),
                              v("wonNeed"), v("wonGreed"), W.RankValue(i, v("rollsWon")), v("rollsTotal"),
                              W.Color(v("rolls100"), "1eff00"), W.Color(v("rolls1"), "ff5555") } }
    end
    list:SetRows(rows)
end

local PROF_ABBR = {
    Alchemy = "Alc", Blacksmithing = "BS", Enchanting = "Enc", Engineering = "Eng", Herbalism = "Herb",
    Leatherworking = "LW", Mining = "Min", Skinning = "Skin", Tailoring = "Tail", Cooking = "Cook",
    Fishing = "Fish", ["First Aid"] = "FA", Jewelcrafting = "JC", Inscription = "Insc", Archaeology = "Arch",
}
-- "Mining 75/100" (the max only when it differs from this game's normal maximum).
function Misc.ProfText(p, short)
    local name = short and (PROF_ABBR[p.name] or p.name) or p.name
    local rank = (p.max and p.max ~= FS.ProfMax()) and string.format("%d/%d", p.rank or 0, p.max) or tostring(p.rank or 0)
    return name .. " " .. rank
end

function Misc.ProfSummary(rec, max)
    local parts = {}
    for i, p in ipairs(rec.profs or {}) do
        if i > (max or 3) then break end
        table.insert(parts, Misc.ProfText(p, true))
    end
    return table.concat(parts, " / ")
end

-- Progress of the main professions (0..1 each), so expansion tiers and Archaeology compare fairly.
function Misc.ProfProgress(rec)
    local total, n = 0, 0
    for _, p in ipairs(rec.profs or {}) do
        if p.kind ~= "secondary" then
            total = total + math.min(1, (p.rank or 0) / math.max(1, p.max or FS.ProfMax()))
            n = n + 1
        end
    end
    return total, n
end

function Misc:RefreshProfs(list)
    local recs = {}
    for _, r in ipairs(self:Records()) do if not r.isAccount then table.insert(recs, r) end end
    table.sort(recs, function(a, b)
        local pa, pb = Misc.ProfProgress(a), Misc.ProfProgress(b)
        if pa == pb then return FS:GetValue(a, "gathered") + FS:GetValue(a, "crafted") > FS:GetValue(b, "gathered") + FS:GetValue(b, "crafted") end
        return pa > pb
    end)
    self.lastRecs = recs
    local rows = {}
    for i, r in ipairs(recs) do
        local main, secondary = {}, {}
        for _, p in ipairs(r.profs or {}) do
            if p.kind == "secondary" then table.insert(secondary, Misc.ProfText(p, true))
            else table.insert(main, Misc.ProfText(p) .. (p.tier and W.Color(" (" .. p.tier .. ")", "888888") or "")) end
        end
        local progress, n = Misc.ProfProgress(r)
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
                    cells = { W.Rank(i), W.Label(r), main[1] or W.Color("-", "666666"), main[2] or W.Color("-", "666666"),
                              #secondary > 0 and table.concat(secondary, ", ") or W.Color("-", "666666"),
                              W.Num(FS:GetValue(r, "gathered")), W.Num(FS:GetValue(r, "crafted")),
                              W.RankValue(i, n > 0 and string.format("%d%%", math.floor(progress / n * 100 + 0.5)) or "-") } }
    end
    list:SetRows(rows)
end

function Misc:RefreshFeed(list)
    local events = FS:GetScopedEvents(UI.currentScope, FEED_KINDS)
    local chars = FS.db.global.characters
    local rows = {}
    for _, ev in ipairs(events) do
        local rec = chars[ev.who]
        if rec and W.Matches(rec, self.query) then
            local text
            if ev.kind == "legacy" then text = "Completed " .. W.Color(ev.a or "?", "ffd100")
            elseif ev.kind == "prof" then text = string.format("Reached %s %d", ev.a or "?", tonumber(ev.v) or 0)
            elseif ev.kind == "boss" then text = "First kill: " .. W.Color(ev.a or "?", "ff8000")
            else text = string.format("Reached level %d", tonumber(ev.v) or 0) end
            local lp = tonumber(ev.lp) or 0
            table.insert(rows, { rec = rec, isSelf = rec.isMyChar and UI.currentScope ~= "solo",
                                 cells = { W.Color(W.Date(ev.t), "aaaaaa"), W.Label(rec), text,
                                           lp > 0 and W.Color("+" .. lp, "00e6ff") or "" } })
        end
    end
    list:SetRows(rows)
end
