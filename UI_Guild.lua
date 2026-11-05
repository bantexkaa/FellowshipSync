local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local View = FS.GuildUI
local Officer = FS.Officer
local UI, W = FS.UI, FS.W

local TABS = {
    { id = "roster", label = "Roster" }, { id = "notices", label = "Notices" }, { id = "polls", label = "Polls" },
    { id = "events", label = "Events" }, { id = "attendance", label = "Attendance" }, { id = "awards", label = "Awards" },
    { id = "goals", label = "Goals" }, { id = "seasons", label = "Seasons" }, { id = "bank", label = "Bank" },
    { id = "officers", label = "Officers" },
}
local TOP, FORM = -84, -118

local function Who(key)
    local rec = FS.db.global.characters[key or ""]
    return rec and W.CharName(rec) or W.Color(FS.ShortName(key or "?"), "ffffff")
end

function View:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current, self.selected = "roster", {}
    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetWidth(760)
    self.badge = W.Text(f, "GameFontNormal", "RIGHT")
    self.badge:SetPoint("TOPRIGHT", -36, -48)
    self.panes = {}
    for _, t in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, f)
        p:SetAllPoints()
        self.panes[t.id] = p
        self["Build_" .. t.id](self, p)
    end
end

-- Helpers for the panes
local function List(self, p, cols, top, onClick)
    local l = W.List(p, cols, { dense = true, noTooltip = true, onClick = onClick })
    l.frame:SetPoint("TOPLEFT", 14, top)
    l.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    return l
end
local function Input(p, width, hint, x, y)
    local box = W.Search(p, width, hint)
    box:SetPoint("TOPLEFT", x, y)
    return box
end
local function Btn(p, label, width, x, y, fn)
    local b = W.Button(p, label, width, 24, fn)
    b:SetPoint("TOPLEFT", x, y)
    return b
end
local function Cycle(p, values, labels, x, y, width)
    local b = W.Button(p, "", width or 150, 24)
    b:SetPoint("TOPLEFT", x, y)
    b.values, b.labels, b.index = values, labels or values, 1
    b:SetScript("OnClick", function(self) self.index = self.index % #self.values + 1; self.text:SetText(self.labels[self.index]) end)
    b.text:SetText(b.labels[1])
    function b:Value() return self.values[self.index] end
    return b
end
local function Report(ok, err) if not ok and err then FS:Print(err) end return ok end

function View:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    for id, p in pairs(self.panes) do p:SetShown(id == self.current) end
    local guild = Officer:GuildName()
    local officer = Officer:AmIOfficer()
    self.badge:SetText(guild and (W.Color("<" .. guild .. ">", "40ff40") .. (officer and W.Color("  Officer", "ffd100") or "")) or "")
    for _, p in pairs(self.panes) do if p.officerOnly then for _, w in ipairs(p.officerOnly) do w:SetShown(officer) end end end
    if not guild then
        self.title:SetText("Guild")
        self.sub:SetText("Join a guild to use the guild tools.")
        return
    end
    self["Refresh_" .. self.current](self, self.panes[self.current], officer)
end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------

function View:Build_roster(p)
    p.filter = W.Button(p, "Show: Everyone", 160, 24, function()
        self.inactiveOnly = not self.inactiveOnly
        self:Refresh()
    end)
    p.filter:SetPoint("TOPRIGHT", -36, -84)
    p.list = List(self, p, {
        { label = "#", width = 30 }, { label = "Member", width = 190 }, { label = "Rank", width = 110 }, { label = "Level", width = 50, justify = "RIGHT" },
        { label = "Last Seen", width = 110, justify = "RIGHT" }, { label = "FellowshipSync", width = 110, justify = "RIGHT" },
        { label = "Played This Week", width = 120, justify = "RIGHT" }, { label = "Zone", width = 160 },
    }, -114)
end

function View:Refresh_roster(p)
    Officer:RefreshRoster()
    local days = FS.db.profile.officer.inactiveDays or 14
    self.title:SetText("Guild Roster")
    self.sub:SetText(string.format("Everyone in the guild, with or without the addon. Inactive = not seen for %d+ days (change in Officers).", days))
    p.filter.text:SetText(self.inactiveOnly and ("Show: Inactive (" .. days .. "d+)") or "Show: Everyone")
    p.filter:SetActive(self.inactiveOnly)
    local byKey = {}
    for name, rec in pairs(FS.db.global.characters) do byKey[Officer.Norm(name)] = rec end
    local list, inactive = {}, 0
    for _, m in ipairs(Officer.roster or {}) do
        if m.daysOff >= days then inactive = inactive + 1 end
        if not self.inactiveOnly or m.daysOff >= days then table.insert(list, m) end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.daysOff ~= b.daysOff then return a.daysOff < b.daysOff end
        return a.name < b.name
    end)
    local rows = {}
    for i, m in ipairs(list) do
        local rec = byKey[Officer.Norm(m.name)]
        local seen = m.online and W.Color("Online", "1eff00") or (m.daysOff < 1 and "today" or (math.floor(m.daysOff) .. " days ago"))
        if m.daysOff >= days then seen = W.Color(seen, "ff5555") end
        rows[i] = { cells = { tostring(i), W.Color(FS.ShortName(m.name), W.ClassHex(m.class)), m.rank or "", tostring(m.level or ""),
            seen, rec and W.Color(rec.version or "yes", "1eff00") or W.Color("-", "666666"),
            rec and W.Duration(FS:GetValue(rec, "playtime", "week")) or "", m.zone or "" } }
    end
    p.list:SetRows(rows)
    self.sub:SetText(self.sub:GetText() .. string.format("   %d members, %d inactive.", #(Officer.roster or {}), inactive))
end

---------------------------------------------------------------------------
-- Notices
---------------------------------------------------------------------------

function View:Build_notices(p)
    p.text = Input(p, 620, "Write a notice for the guild...", 14, -84)
    p.post = Btn(p, "Post Notice", 120, 642, -84, function()
        local text = strtrim(p.text:GetText() or "")
        if text ~= "" and Report(Officer:Create("notice", { text = text:sub(1, 240) })) then p.text:SetText("") end
        self:Refresh()
    end)
    p.remove = Btn(p, "Remove Selected", 140, 770, -84, function()
        if self.selected.notices then Report(Officer:Remove(self.selected.notices)); self.selected.notices = nil; self:Refresh() end
    end)
    p.officerOnly = { p.text, p.post, p.remove }
    p.list = List(self, p, {
        { label = "Posted", width = 110 }, { label = "From", width = 140 }, { label = "Notice", width = 560 }, { label = "Read", width = 110, justify = "RIGHT" },
    }, FORM, function(o) self.selected.notices = o.id; Officer:Respond(o.id, true); self:Refresh() end)
end

function View:Refresh_notices(p, officer)
    self.title:SetText("Guild Notices")
    self.sub:SetText("Messages from officers. Click a notice to mark it read" .. (officer and "; officers see how many have read it." or "."))
    local rows = {}
    for i, o in ipairs(Officer:Visible("notice")) do
        local reads = 0
        for _ in pairs(Officer:Responses(o.id)) do reads = reads + 1 end
        local mine = Officer:MyResponse(o.id)
        rows[i] = { rec = o, isSelf = self.selected.notices == o.id, cells = { W.Color(date("%d.%m %H:%M", o.t), "aaaaaa"), Who(o.author),
            mine and o.text or W.Color(o.text or "", "ffffff") .. W.Color("  NEW", "ffd100"),
            officer and (reads .. " read") or (mine and W.Color("Read", "1eff00") or W.Color("Unread", "ffd100")) } }
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Polls
---------------------------------------------------------------------------

function View:Build_polls(p)
    p.q = Input(p, 300, "Question", 14, -84)
    p.opts = Input(p, 290, "Options, separated by commas", 320, -84)
    p.len = Cycle(p, { 1, 3, 7 }, { "Open 1 day", "Open 3 days", "Open 7 days" }, 616, -84, 120)
    p.create = Btn(p, "Create Poll", 110, 742, -84, function()
        local opts = {}
        for o in (p.opts:GetText() or ""):gmatch("[^,]+") do o = strtrim(o); if o ~= "" and #opts < 6 then table.insert(opts, o:sub(1, 40)) end end
        local q = strtrim(p.q:GetText() or "")
        if q == "" or #opts < 2 then FS:Print("A poll needs a question and at least two options.") return end
        if Report(Officer:Create("poll", { q = q:sub(1, 160), options = opts, closes = time() + p.len:Value() * 86400 })) then
            p.q:SetText(""); p.opts:SetText("")
        end
        self:Refresh()
    end)
    p.remove = Btn(p, "Remove", 90, 858, -84, function()
        if self.selected.polls then Report(Officer:Remove(self.selected.polls)); self.selected.polls = nil; self:Refresh() end
    end)
    p.officerOnly = { p.q, p.opts, p.len, p.create, p.remove }
    p.list = List(self, p, {
        { label = "Question", width = 280 }, { label = "Results", width = 420 }, { label = "Votes", width = 60, justify = "RIGHT" },
        { label = "Closes", width = 110, justify = "RIGHT" },
    }, FORM, function(o) self.selected.polls = o.id; self:Refresh() end)
    p.list.frame:SetPoint("BOTTOMRIGHT", -12, 44)
    p.voteLabel = W.Text(p, "GameFontNormal")
    p.voteLabel:SetPoint("BOTTOMLEFT", 14, 16)
    p.votes = {}
    for i = 1, 6 do
        local b = W.Button(p, "", 120, 24, function()
            if self.selected.polls then Officer:Respond(self.selected.polls, i); self:Refresh() end
        end)
        b:SetPoint("BOTTOMLEFT", 120 + (i - 1) * 126, 12)
        p.votes[i] = b
    end
end

function View:Refresh_polls(p)
    self.title:SetText("Guild Polls")
    self.sub:SetText("Click a poll, then vote with the buttons below. Results update as guildmates sync.")
    local rows, selected = {}, nil
    for i, o in ipairs(Officer:Visible("poll")) do
        local counts, total = {}, 0
        for _, v in pairs(Officer:Responses(o.id)) do v = tonumber(v); if v then counts[v] = (counts[v] or 0) + 1; total = total + 1 end end
        local parts = {}
        for j, opt in ipairs(o.options or {}) do
            local text = string.format("%s (%d)", opt, counts[j] or 0)
            if Officer:MyResponse(o.id) == j then text = W.Color(text, "1eff00") end
            table.insert(parts, text)
        end
        local open = (o.closes or 0) > time()
        rows[i] = { rec = o, isSelf = self.selected.polls == o.id, cells = { o.q or "", table.concat(parts, "  /  "), tostring(total),
            open and date("%d.%m %H:%M", o.closes) or W.Color("Closed", "888888") } }
        if self.selected.polls == o.id then selected = o end
    end
    p.list:SetRows(rows)
    local open = selected and (selected.closes or 0) > time()
    p.voteLabel:SetText(selected and (open and "Your vote:" or "Poll closed") or W.Color("Select a poll to vote", "888888"))
    for i, b in ipairs(p.votes) do
        local opt = open and selected.options and selected.options[i]
        b:SetShown(opt ~= nil)
        if opt then b.text:SetText(opt); b:SetActive(Officer:MyResponse(selected.id) == i) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function View:Build_events(p)
    p.etitle = Input(p, 240, "Event (e.g. Molten Core)", 14, -84)
    p.day = Input(p, 110, "YYYY-MM-DD", 260, -84)
    p.time = Input(p, 70, "HH:MM", 376, -84)
    p.note = Input(p, 250, "Note (optional)", 452, -84)
    p.create = Btn(p, "Create Event", 120, 708, -84, function()
        local y, mo, d = (p.day:GetText() or ""):match("(%d%d%d%d)%-(%d%d?)%-(%d%d?)")
        local h, mi = (p.time:GetText() or ""):match("(%d%d?):(%d%d)")
        local title = strtrim(p.etitle:GetText() or "")
        if title == "" or not y or not h then FS:Print("Give the event a name, a date (YYYY-MM-DD) and a time (HH:MM).") return end
        local when = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
        if Report(Officer:Create("event", { title = title:sub(1, 80), when = when, note = strtrim(p.note:GetText() or ""):sub(1, 160) })) then
            p.etitle:SetText(""); p.note:SetText("")
        end
        self:Refresh()
    end)
    p.remove = Btn(p, "Remove", 90, 834, -84, function()
        if self.selected.events then Report(Officer:Remove(self.selected.events)); self.selected.events = nil; self:Refresh() end
    end)
    p.officerOnly = { p.etitle, p.day, p.time, p.note, p.create, p.remove }
    p.list = List(self, p, {
        { label = "When", width = 130 }, { label = "Event", width = 220 }, { label = "Coming", width = 70, justify = "RIGHT" },
        { label = "Maybe", width = 70, justify = "RIGHT" }, { label = "Can't", width = 70, justify = "RIGHT" },
        { label = "You", width = 90, justify = "RIGHT" }, { label = "Note", width = 260 },
    }, FORM, function(o) self.selected.events = o.id; self:Refresh() end)
    p.list.frame:SetPoint("BOTTOMRIGHT", -12, 64)
    p.who = W.Text(p, "GameFontHighlightSmall")
    p.who:SetPoint("BOTTOMLEFT", 14, 44)
    p.who:SetWidth(950)
    p.rsvp = {}
    for i, r in ipairs({ { "yes", "Coming" }, { "maybe", "Maybe" }, { "no", "Can't come" } }) do
        local b = W.Button(p, r[2], 120, 24, function()
            if self.selected.events then Officer:Respond(self.selected.events, r[1]); self:Refresh() end
        end)
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 126, 12)
        b.value = r[1]
        p.rsvp[i] = b
    end
end

function View:Refresh_events(p)
    self.title:SetText("Guild Events")
    self.sub:SetText("Click an event and tell the officers if you are coming. You get a reminder 15 minutes before it starts.")
    local rows, selected = {}, nil
    local events = Officer:Visible("event")
    table.sort(events, function(a, b) return (a.when or 0) < (b.when or 0) end)
    for _, o in ipairs(events) do
        local c = { yes = 0, maybe = 0, no = 0 }
        for _, v in pairs(Officer:Responses(o.id)) do if c[v] then c[v] = c[v] + 1 end end
        local mine = Officer:MyResponse(o.id)
        local past = (o.when or 0) < time() - 3 * 3600
        table.insert(rows, { rec = o, isSelf = self.selected.events == o.id, cells = {
            W.Color(date("%a %d.%m %H:%M", o.when or 0), past and "666666" or "ffd100"), o.title or "",
            W.Color(c.yes, "1eff00"), W.Color(c.maybe, "ffd100"), W.Color(c.no, "ff5555"),
            mine == "yes" and W.Color("Coming", "1eff00") or mine == "maybe" and "Maybe" or mine == "no" and W.Color("Can't", "ff5555") or "-",
            o.note or "" } })
        if self.selected.events == o.id then selected = o end
    end
    p.list:SetRows(rows)
    if selected then
        local names = { yes = {}, maybe = {} }
        for key, v in pairs(Officer:Responses(selected.id)) do if names[v] then table.insert(names[v], FS.ShortName(key)) end end
        p.who:SetText(W.Color("Coming: ", "1eff00") .. table.concat(names.yes, ", ") .. "    " .. W.Color("Maybe: ", "ffd100") .. table.concat(names.maybe, ", "))
    else
        p.who:SetText(W.Color("Select an event to sign up.", "888888"))
    end
    for _, b in ipairs(p.rsvp) do b:SetShown(selected ~= nil); b:SetActive(selected and Officer:MyResponse(selected.id) == b.value) end
end

---------------------------------------------------------------------------
-- Attendance
---------------------------------------------------------------------------

function View:Build_attendance(p)
    p.range = Cycle(p, { 30, 60, 90 }, { "Last 30 days", "Last 60 days", "Last 90 days" }, 830, -84, 130)
    p.range:HookScript("OnClick", function() self:Refresh() end)
    p.list = List(self, p, {
        { label = "#", width = 30 }, { label = "Member", width = 260 }, { label = "Raid Nights", width = 110, justify = "RIGHT" },
        { label = "Attendance", width = 110, justify = "RIGHT" }, { label = "Last Raid", width = 130, justify = "RIGHT" },
    }, -114)
end

function View:Refresh_attendance(p)
    local list, nights = Officer:Attendance(p.range:Value())
    self.title:SetText("Raid Attendance")
    self.sub:SetText(string.format("Recorded automatically at every boss fight in a raid group: %d raid night%s. Officers share their records with everyone.",
        nights, nights == 1 and "" or "s"))
    local rows = {}
    for i, m in ipairs(list) do
        local pct = math.floor(m.share * 100 + 0.5)
        rows[i] = { cells = { tostring(i), Who(m.name), m.nights .. " / " .. nights,
            W.Color(pct .. "%", pct >= 75 and "1eff00" or (pct >= 40 and "ffd100" or "ff5555")), m.last } }
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Awards
---------------------------------------------------------------------------

function View:Build_awards(p)
    p.atitle = Input(p, 220, "Award (e.g. Raider of the Month)", 14, -84)
    p.to = Input(p, 180, "Character name", 240, -84)
    p.note = Input(p, 300, "Why (optional)", 426, -84)
    p.grant = Btn(p, "Give Award", 110, 732, -84, function()
        local title, name = strtrim(p.atitle:GetText() or ""), strtrim(p.to:GetText() or "")
        local target
        for key in pairs(FS.db.global.characters) do
            if FS.ShortName(key):lower() == name:lower() or key:lower() == name:lower() then target = key end
        end
        if title == "" or not target then FS:Print("Name the award and a character FellowshipSync knows.") return end
        if Report(Officer:Create("award", { title = title:sub(1, 80), to = target, note = strtrim(p.note:GetText() or ""):sub(1, 160) })) then
            p.atitle:SetText(""); p.to:SetText(""); p.note:SetText("")
        end
        self:Refresh()
    end)
    p.remove = Btn(p, "Remove", 90, 848, -84, function()
        if self.selected.awards then Report(Officer:Remove(self.selected.awards)); self.selected.awards = nil; self:Refresh() end
    end)
    p.officerOnly = { p.atitle, p.to, p.note, p.grant, p.remove }
    p.list = List(self, p, {
        { label = "Date", width = 100 }, { label = "Award", width = 220 }, { label = "Given To", width = 180 },
        { label = "From", width = 140 }, { label = "Why", width = 300 },
    }, FORM, function(o) self.selected.awards = o.id; self:Refresh() end)
end

function View:Refresh_awards(p)
    self.title:SetText("Guild Awards")
    self.sub:SetText("Titles given by officers. They show in tooltips, profiles and each character's Book of Deeds.")
    local rows = {}
    for i, o in ipairs(Officer:Visible("award")) do
        rows[i] = { rec = o, isSelf = self.selected.awards == o.id, cells = { W.Color(date("%d.%m.%Y", o.t), "aaaaaa"),
            W.Color(o.title or "", "ffd100"), Who(o.to), Who(o.author), o.note or "" } }
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------

local function WeeklyKeys()
    local keys, labels = {}, {}
    for _, k in ipairs(FS.COUNTER_KEYS) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return FS.STATS[a].label < FS.STATS[b].label end)
    for i, k in ipairs(keys) do labels[i] = FS.STATS[k].label end
    return keys, labels
end

function View:Build_goals(p)
    local keys, labels = WeeklyKeys()
    p.gtitle = Input(p, 240, "Goal (e.g. Ore for the guild bank)", 14, -84)
    p.kind = Cycle(p, { "manual", "stat" }, { "Officers count it", "Counts a stat" }, 260, -84, 140)
    p.stat = Cycle(p, keys, labels, 406, -84, 170)
    p.target = Input(p, 90, "Target", 582, -84)
    p.create = Btn(p, "Create Goal", 110, 678, -84, function()
        local title, target = strtrim(p.gtitle:GetText() or ""), tonumber(p.target:GetText())
        if title == "" or not target or target <= 0 then FS:Print("Give the goal a name and a target number.") return end
        if Report(Officer:Create("goal", { title = title:sub(1, 80), kind = p.kind:Value(), key = p.stat:Value(), target = target,
            progress = 0, finish = time() + 7 * 86400 })) then p.gtitle:SetText(""); p.target:SetText("") end
        self:Refresh()
    end)
    p.add = Input(p, 70, "+ amount", 794, -84)
    p.addBtn = Btn(p, "Add", 60, 870, -84, function()
        local id, n = self.selected.goals, tonumber(p.add:GetText())
        local o = id and Officer:Store().objects[id]
        if o and n and o.kind ~= "stat" then Report(Officer:Update(id, { progress = (tonumber(o.progress) or 0) + n })); p.add:SetText("") end
        self:Refresh()
    end)
    p.remove = Btn(p, "X", 30, 934, -84, function()
        if self.selected.goals then Report(Officer:Remove(self.selected.goals)); self.selected.goals = nil; self:Refresh() end
    end)
    p.officerOnly = { p.gtitle, p.kind, p.stat, p.target, p.create, p.add, p.addBtn, p.remove }
    p.list = List(self, p, {
        { label = "Goal", width = 260 }, { label = "Progress", width = 220, justify = "RIGHT" }, { label = "Done", width = 70, justify = "RIGHT" },
        { label = "Counts", width = 180 }, { label = "From", width = 130 }, { label = "Ends", width = 100, justify = "RIGHT" },
    }, FORM, function(o) self.selected.goals = o.id; self:Refresh() end)
end

function View:Refresh_goals(p)
    self.title:SetText("Guild Goals")
    self.sub:SetText("Officers' own goals. Stat goals count this week's numbers for the whole guild; other goals are counted by officers (select one, then Add).")
    local rows = {}
    for i, o in ipairs(Officer:Visible("goal")) do
        local value = Officer:GoalProgress(o)
        local pct = math.min(100, math.floor(value / math.max(1, o.target or 1) * 100))
        rows[i] = { rec = o, isSelf = self.selected.goals == o.id, cells = { W.Color(o.title or "", "ffd100"),
            W.Num(value) .. " / " .. W.Num(o.target), W.Color(pct .. "%", pct >= 100 and "1eff00" or "ffffff"),
            o.kind == "stat" and (FS.STATS[o.key] and FS.STATS[o.key].label or o.key) or "Counted by officers",
            Who(o.author), date("%d.%m", o.finish or 0) } }
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Seasons
---------------------------------------------------------------------------

function View:Build_seasons(p)
    local keys, labels = WeeklyKeys()
    p.stitle = Input(p, 200, "Season name", 14, -84)
    p.len = Cycle(p, { 7, 14, 28 }, { "1 week", "2 weeks", "4 weeks" }, 220, -84, 90)
    p.k1 = Cycle(p, keys, labels, 316, -84, 150)
    p.k2 = Cycle(p, keys, labels, 472, -84, 150)
    p.k2.index = 2; p.k2.text:SetText(labels[2])
    p.k3 = Cycle(p, keys, labels, 628, -84, 150)
    p.k3.index = 3; p.k3.text:SetText(labels[3])
    p.start = Btn(p, "Start Season", 120, 784, -84, function()
        local title = strtrim(p.stitle:GetText() or "")
        if title == "" then FS:Print("Give the season a name.") return end
        local ks, seen = {}, {}
        for _, c in ipairs({ p.k1, p.k2, p.k3 }) do if not seen[c:Value()] then seen[c:Value()] = true; table.insert(ks, c:Value()) end end
        if Report(Officer:Create("season", { title = title:sub(1, 80), start = time(), finish = time() + p.len:Value() * 86400, keys = ks })) then
            p.stitle:SetText("")
        end
        self:Refresh()
    end)
    p.officerOnly = { p.stitle, p.len, p.k1, p.k2, p.k3, p.start }
    p.list = List(self, p, {
        { label = "Season", width = 180 }, { label = "Stat", width = 170 }, { label = "1st", width = 170 }, { label = "2nd", width = 160 },
        { label = "3rd", width = 160 }, { label = "Ends", width = 100, justify = "RIGHT" },
    }, FORM)
end

function View:Refresh_seasons(p)
    self.title:SetText("Seasons & Hall of Champions")
    self.sub:SetText("Competitions run by officers. Progress counts from each player's first sync after the start; winners are crowned when it ends.")
    local rows = {}
    for _, o in ipairs(Officer:Visible("season")) do
        local ended = (o.finish or 0) < time()
        for _, k in ipairs(o.keys or {}) do
            local label = FS.STATS[k] and FS.STATS[k].label or k
            local cells = { W.Color(o.title or "", ended and "ffd100" or "ffffff"), label }
            if ended and o.final then
                local w = o.final[k]
                cells[3] = w and (W.Color("Champion: ", "ffd100") .. Who(w.winner) .. W.Color(" (" .. W.FormatStat(k, w.value) .. ")", "888888")) or "-"
                cells[4], cells[5] = "", ""
            else
                local st = Officer:Standings(o, k)
                for place = 1, 3 do
                    local e = st[place]
                    cells[2 + place] = e and (Who(e.rec.fullName) .. W.Color(" " .. W.FormatStat(k, e.v), "888888")) or "-"
                end
            end
            cells[6] = ended and W.Color("Ended", "888888") or date("%d.%m %H:%M", o.finish or 0)
            table.insert(rows, { cells = cells })
        end
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------

function View:Build_bank(p)
    p.list = List(self, p, {
        { label = "#", width = 30 }, { label = "Member", width = 300 }, { label = "Gold Donated", width = 200, justify = "RIGHT" },
    }, TOP)
end

function View:Refresh_bank(p)
    self.title:SetText("Guild Bank Donations")
    self.sub:SetText(GetNumGuildBankMoneyTransactions and "Read from the guild bank's money log each time you or an officer opens the guild bank."
        or "This game version has no guild bank.")
    local rows = {}
    for i, d in ipairs(Officer:Donations()) do
        rows[i] = { cells = { W.Rank(i), W.Color(FS.ShortName(d.name), "ffffff"), W.RankValue(i, W.Money(d.amount)) } }
    end
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Officers (settings)
---------------------------------------------------------------------------

function View:Build_officers(p)
    p.info = W.Text(p, "GameFontHighlight")
    p.info:SetPoint("TOPLEFT", 14, -86)
    p.info:SetWidth(950)
    p.rankChecks = {}
    for i = 1, 10 do
        local cb = W.Check(p, "", function() end)
        cb:SetPoint("TOPLEFT", 14 + ((i - 1) % 5) * 190, -130 - math.floor((i - 1) / 5) * 28)
        p.rankChecks[i] = cb
    end
    p.save = Btn(p, "Save Officer Ranks", 170, 14, -194, function()
        local ranks = {}
        for i, cb in ipairs(p.rankChecks) do if cb:IsShown() and cb:GetChecked() and i > 1 then table.insert(ranks, i - 1) end end
        Report(Officer:Create("ranks", { ranks = ranks }))
        self:Refresh()
    end)
    p.daysLabel = W.Text(p, "GameFontNormal")
    p.daysLabel:SetPoint("TOPLEFT", 14, -240)
    p.daysLabel:SetText("Inactive after:")
    p.days = Cycle(p, { 7, 14, 30, 60 }, { "7 days", "14 days", "30 days", "60 days" }, 130, -236, 100)
    p.days:HookScript("OnClick", function() FS.db.profile.officer.inactiveDays = p.days:Value(); self:Refresh() end)
    p.help = W.Text(p, "GameFontDisableSmall")
    p.help:SetPoint("TOPLEFT", 14, -280)
    p.help:SetWidth(950)
    p.help:SetWordWrap(true)
    p.help:SetText("Officer ranks can post notices, create polls, events, goals and seasons, give awards, and share attendance and bank records. "
        .. "Every member's addon checks the sender's rank in its own guild roster, so nobody else can post as an officer. "
        .. "Only the guild leader chooses the officer ranks; the guild leader always counts as an officer.")
end

function View:Refresh_officers(p)
    local leader, idx = Officer:IsLeader(), Officer:MyRankIndex()
    local _, rankName = GetGuildInfo("player")
    self.title:SetText("Officer Settings")
    self.sub:SetText("Who counts as an officer in FellowshipSync.")
    p.info:SetText(string.format("Your rank: %s%s", tostring(rankName or "?"),
        Officer:AmIOfficer() and W.Color("  (officer powers)", "1eff00") or W.Color("  (member)", "aaaaaa")))
    local set = Officer:OfficerRanks()
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i, cb in ipairs(p.rankChecks) do
        local shown = i <= n
        cb:SetShown(shown)
        if shown then
            cb.label:SetText((GuildControlGetRankName and GuildControlGetRankName(i) or ("Rank " .. i)) .. (i == 1 and " (leader)" or ""))
            cb:SetChecked(set[i - 1] == true)
            cb:SetEnabled(leader and i > 1)
        end
    end
    p.save:SetShown(leader)
    local days = FS.db.profile.officer.inactiveDays or 14
    for i, v in ipairs(p.days.values) do if v == days then p.days.index = i; p.days.text:SetText(p.days.labels[i]) end end
end
