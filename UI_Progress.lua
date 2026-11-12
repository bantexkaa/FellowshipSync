local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Progress = FS.Progress
local UI, W = FS.UI, FS.W

---------------------------------------------------------------------------
-- Progress: this session and its live rates, personal goals, a play-time
-- calendar, snapshots to compare against later, and stat titles.
-- Also: the small live-stats panel and the Deathlog's death prediction.
---------------------------------------------------------------------------

local TABS = {
    { id = "session", label = "Session" }, { id = "goals", label = "Goals" }, { id = "calendar", label = "Calendar" },
    { id = "snapshots", label = "Snapshots" }, { id = "titles", label = "Titles" },
}
local TOP = -84

---------------------------------------------------------------------------
-- Session numbers and live rates
---------------------------------------------------------------------------

function Progress:Session()
    local c = FS.db.char
    local s = c.session
    if not s then return nil end
    local st = c.stats
    local secs = math.max(1, time() - (s.start or time()))
    local d = {}
    for _, k in ipairs(FS.Tracker.SESSION_KEYS) do d[k] = math.max(0, (tonumber(st[k]) or 0) - (s.base[k] or 0)) end
    d.distance = d.travelFoot + d.travelMount + d.travelFlight + d.travelSwim
    d.secs, d.xp = secs, tonumber(s.xp) or 0
    local hours = secs / 3600
    d.killsH, d.goldH, d.xpH = d.kills / hours, (d.goldLooted + 0) / hours, d.xp / hours
    local level, max = tonumber(UnitLevel("player")) or 0, FS:MaxLevel()
    d.levels = math.max(0, level - (s.level or level))
    if level < max and d.xp > 0 then
        local cur, need = tonumber(UnitXP and UnitXP("player")) or 0, tonumber(UnitXPMax and UnitXPMax("player")) or 0
        d.toLevel = need > cur and (need - cur) / (d.xp / secs) or nil
    end
    return d
end

function Progress:SessionLine()
    local d = self:Session()
    if not d then return nil end
    local me = FS.ShortName(FS:GetPlayerKey())
    return string.format("%s's session: %s, %s kills, %s deaths, %s quests, %s looted, %s travelled%s.", me,
        W.Plain(W.Duration(d.secs)), W.Num(d.kills), W.Num(d.deaths), W.Num(d.quests), W.Plain(W.Money(d.goldLooted)),
        W.Plain(W.Distance(d.distance)), d.levels > 0 and string.format(", %d level%s", d.levels, d.levels == 1 and "" or "s") or "")
end

---------------------------------------------------------------------------
-- Personal goals
---------------------------------------------------------------------------

function Progress:GoalValue(rec, g)
    if g.key == "level" then return tonumber(rec.level) or 0 end
    return FS:GetValue(rec, g.key, "all")
end

function Progress:GoalLabel(g)
    if g.key == "level" then return "Level " .. W.Num(g.target) end
    local stat = FS.STATS[g.key]
    return W.Plain(W.FormatStat(g.key, g.target)) .. " " .. ((stat and stat.label) or g.key):lower()
end

function Progress:CheckGoals(rec)
    for _, g in ipairs(FS.db.char.goals or {}) do
        if not g.done and self:GoalValue(rec, g) >= g.target then
            g.done = time()
            FS:AddEvent({ kind = "fun", who = FS:GetPlayerKey(), title = "Goal Reached!", a = "You reached your goal: " .. self:GoalLabel(g) .. "!" })
        end
    end
end

---------------------------------------------------------------------------
-- Stat titles: whoever leads a stat in your network holds its title
---------------------------------------------------------------------------

Progress.TITLES = {
    { key = "kills", title = "the Slayer" }, { key = "jumps", title = "the Jumper" }, { key = "longestLife", title = "the Unkillable" },
    { key = "fallDeaths", title = "Gravity's Favourite" }, { key = "nightTime", title = "the Night Owl" },
    { key = "areasDiscovered", title = "the Explorer" }, { key = "fish", title = "the Angler" }, { key = "chat", title = "the Chatterbox" },
    { key = "revengeKills", title = "the Avenger" }, { key = "critters", title = "Bane of Critters" }, { key = "quests", title = "the Questmaster" },
    { key = "rolls1", title = "the Unlucky" }, { key = "embarrassingDeaths", title = "the Clumsy" }, { key = "hearthRegret", title = "the Indecisive" },
}

function Progress:TitleHolders()
    if self.titleCache and time() - self.titleCache.t < 30 then return self.titleCache.list end
    local chars = FS:GetScopeCharacters("network")
    local list = {}
    for _, def in ipairs(self.TITLES) do
        if FS.STATS[def.key] then
            local best, bestV
            for _, r in ipairs(chars) do
                local v = FS:GetValue(r, def.key, "all")
                if v > 0 and (not bestV or v > bestV) then best, bestV = r, v end
            end
            if best then table.insert(list, { def = def, rec = best, value = bestV }) end
        end
    end
    self.titleCache = { t = time(), list = list }
    return list
end

function Progress:TitlesFor(fullName)
    local out = {}
    for _, h in ipairs(self:TitleHolders()) do if h.rec.fullName == fullName then table.insert(out, h.def.title) end end
    return out
end

---------------------------------------------------------------------------
-- Death prediction (just for fun)
---------------------------------------------------------------------------

function FS.DeathPrediction(rec)
    if not rec then return nil end
    local deaths, played = FS:GetValue(rec, "deaths", "all"), tonumber(rec.playtime) or 0
    if deaths < 3 or played <= 0 then return nil end
    local left = played / deaths - (tonumber(rec.curLife) or 0)
    local zone, counts = GetRealZoneText and GetRealZoneText(), {}
    for _, d in ipairs(rec.deathLog or {}) do if d.zone == zone and d.killer then counts[d.killer] = (counts[d.killer] or 0) + 1 end end
    local killer, n = nil, 0
    for k, v in pairs(counts) do if v > n then killer, n = k, v end end
    if not killer then for k, v in pairs(rec.killers or {}) do if v > n then killer, n = k, v end end end
    killer = killer or "something unexpected"
    if left <= 60 then return string.format("At your current pace, %s gets you any moment now.", killer) end
    return string.format("At your current pace, you'll die to %s in about %s.", killer, W.Plain(W.Duration(left)))
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function Card(parent, x, y, w)
    local c = W.Box(parent, "card")
    c:SetSize(w, 62)
    c:SetPoint("TOPLEFT", x, y)
    c.label = W.Text(c, "GameFontDisableSmall")
    c.label:SetPoint("TOPLEFT", 10, -9)
    c.value = W.Text(c, "GameFontNormalLarge")
    c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -5)
    return c
end

function Progress:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current = "session"
    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetWidth(760)
    self.panes = {}
    for _, t in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, f)
        p:SetAllPoints()
        self.panes[t.id] = p
        self["Build_" .. t.id](self, p)
    end
end

function Progress:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    for id, p in pairs(self.panes) do p:SetShown(id == self.current) end
    self["Refresh_" .. self.current](self, self.panes[self.current])
end

-- Session ------------------------------------------------------------------

function Progress:Build_session(p)
    local names = { "Session", "Kills", "Deaths", "Quests", "Gold Looted", "Distance", "Jumps", "Levels" }
    p.cards = {}
    for i, n in ipairs(names) do
        local c = Card(p, 14 + ((i - 1) % 4) * 240, TOP - math.floor((i - 1) / 4) * 70, 232)
        c.label:SetText(string.upper(W.T(n)))
        p.cards[i] = c
    end
    local rates = W.Box(p, "accent")
    rates:SetPoint("TOPLEFT", 14, TOP - 148)
    rates:SetSize(952, 70)
    p.rates = W.Text(rates, "GameFontHighlight")
    p.rates:SetPoint("TOPLEFT", 12, -12)
    p.rates:SetWidth(920)
    p.toLevel = W.Text(rates, "GameFontNormal")
    p.toLevel:SetPoint("TOPLEFT", p.rates, "BOTTOMLEFT", 0, -8)
    p.share = W.Button(p, "Share Session", 140, 24, function() FS.Share:Open(self:SessionLine()) end)
    p.share:SetPoint("TOPLEFT", 14, TOP - 230)
    p.mini = W.Button(p, "Mini Panel", 120, 24, function() self:ToggleMini() end)
    p.mini:SetPoint("LEFT", p.share, "RIGHT", 8, 0)
end

function Progress:Refresh_session(p)
    self.title:SetText(W.T("This Session"))
    self.sub:SetText(W.T("Since you logged in (reloads don't reset it). Rates are per hour of this session."))
    local d = self:Session()
    if not d then return end
    local values = { W.Duration(d.secs), W.Num(d.kills), W.Num(d.deaths), W.Num(d.quests), W.Money(d.goldLooted),
                     W.Distance(d.distance), W.Num(d.jumps), W.Num(d.levels) }
    for i, c in ipairs(p.cards) do c.value:SetText(values[i]); W.AccentText(c.value) end
    p.rates:SetText(string.format("%s %s kills/h     %s %s/h     %s %s XP/h", W.T("Rates:"), W.Num(math.floor(d.killsH)),
        W.T("Gold:"), W.Plain(W.Money(math.floor(d.goldH))), W.T("XP:"), W.Num(math.floor(d.xpH))))
    p.toLevel:SetText(d.toLevel and string.format(W.T("Next level in about %s at this pace."), W.Plain(W.Duration(d.toLevel)))
        or W.Color(W.T("Gain some XP to see your time to next level."), "888888"))
    p.mini:SetActive(FS.db.profile.mini.shown and true or false)
end

-- Goals --------------------------------------------------------------------

local function GoalKeys()
    local keys, labels = { "level" }, { "Level" }
    local list = {}
    for k, def in pairs(FS.STATS) do if def.fmt ~= "pct" then table.insert(list, k) end end
    table.sort(list, function(a, b) return FS.STATS[a].label < FS.STATS[b].label end)
    for _, k in ipairs(list) do table.insert(keys, k); table.insert(labels, FS.STATS[k].label) end
    return keys, labels
end

function Progress:Build_goals(p)
    local keys, labels = GoalKeys()
    p.stat = W.Button(p, labels[1], 220, 24)
    p.stat:SetPoint("TOPLEFT", 14, TOP)
    p.stat.keys, p.stat.labels, p.stat.index = keys, labels, 1
    p.stat:SetScript("OnClick", function(b) b.index = b.index % #b.keys + 1; b.text:SetText(b.labels[b.index]) end)
    p.target = W.Search(p, 120, "Target")
    p.target:SetPoint("LEFT", p.stat, "RIGHT", 8, 0)
    p.days = W.Button(p, W.T("No deadline"), 140, 24)
    p.days:SetPoint("LEFT", p.target, "RIGHT", 8, 0)
    p.days.values, p.days.labels, p.days.index = { 0, 1, 3, 7, 30 }, { "No deadline", "Within 1 day", "Within 3 days", "Within 7 days", "Within 30 days" }, 1
    p.days:SetScript("OnClick", function(b) b.index = b.index % #b.values + 1; b.text:SetText(W.T(b.labels[b.index])) end)
    p.add = W.Button(p, "Add Goal", 110, 24, function()
        local target = tonumber((p.target:GetText() or ""):gsub(",", ""), 10)
        if not target or target <= 0 then FS:Print(W.T("Enter a target number.")) return end
        local goals = FS.db.char.goals
        if #goals >= 10 then FS:Print(W.T("You can have up to 10 goals.")) return end
        local key = p.stat.keys[p.stat.index]
        local stat = FS.STATS[key]
        if stat and stat.fmt == "money" then target = target * 10000 end -- typed in gold
        local days = p.days.values[p.days.index]
        table.insert(goals, { key = key, target = target, t = time(), deadline = days > 0 and (time() + days * 86400) or nil })
        p.target:SetText("")
        self:Refresh()
    end)
    p.add:SetPoint("LEFT", p.days, "RIGHT", 8, 0)
    p.remove = W.Button(p, "Remove", 90, 24, function()
        local goals = FS.db.char.goals
        if self.selectedGoal and goals[self.selectedGoal] then table.remove(goals, self.selectedGoal); self.selectedGoal = nil; self:Refresh() end
    end)
    p.remove:SetPoint("LEFT", p.add, "RIGHT", 8, 0)
    p.list = W.List(p, {
        { label = "Goal", width = 300 }, { label = "Now", width = 140, justify = "RIGHT" }, { label = "Done", width = 80, justify = "RIGHT" },
        { label = "Deadline", width = 140, justify = "RIGHT" }, { label = "Status", width = 160, justify = "RIGHT" },
    }, { id = "goals", noTooltip = true, emptyText = "No goals yet. Pick a stat, type a target and press Add Goal.",
         onClick = function(row) self.selectedGoal = row.index; self:Refresh() end })
    p.list.frame:SetPoint("TOPLEFT", 14, TOP - 34)
    p.list.frame:SetPoint("BOTTOMRIGHT", -12, 10)
end

function Progress:Refresh_goals(p)
    self.title:SetText(W.T("Personal Goals"))
    self.sub:SetText(W.T("Set your own targets (gold is typed in gold). You get a toast when you reach one."))
    local me = FS:GetMyRecord()
    local rows = {}
    for i, g in ipairs(FS.db.char.goals) do
        local v = me and self:GoalValue(me, g) or 0
        local pct = math.min(100, math.floor(v / math.max(1, g.target) * 100))
        local status
        if g.done then status = W.Color(W.T("Reached ") .. date("%d.%m", g.done), "1eff00")
        elseif g.deadline and time() > g.deadline then status = W.Color(W.T("Missed"), "ff5555")
        else status = W.Color(W.T("In progress"), "ffd100") end
        rows[i] = { rec = { index = i }, isSelf = self.selectedGoal == i, cells = { W.Color(self:GoalLabel(g), "ffd100"),
            g.key == "level" and tostring(v) or W.FormatStat(g.key, v), pct .. "%",
            g.deadline and date("%d.%m %H:%M", g.deadline) or "-", status } }
    end
    p.list:SetRows(rows)
    p.remove:SetShown(self.selectedGoal ~= nil)
end

-- Calendar -----------------------------------------------------------------

function Progress:Build_calendar(p)
    p.cells = {}
    local size, gap = 14, 3
    for w = 1, 53 do
        for d = 1, 7 do
            local b = CreateFrame("Button", nil, p)
            b:SetSize(size, size)
            b:SetPoint("TOPLEFT", 50 + (w - 1) * (size + gap), TOP - 30 - (d - 1) * (size + gap))
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b:SetScript("OnEnter", function(btn)
                if not btn.day then return end
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(btn.label or btn.day, 1, 0.82, 0)
                GameTooltip:AddLine(btn.secs > 0 and W.Plain(W.Duration(btn.secs)) .. " " .. W.T("played") or W.T("Not played"), 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.cells[(w - 1) * 7 + d] = b
        end
    end
    p.months = {}
    for i, label in ipairs({ "Mon", "Wed", "Fri" }) do
        local t = W.Text(p, "GameFontDisableSmall")
        t:SetPoint("TOPLEFT", 14, TOP - 30 - ((i - 1) * 2) * (size + gap))
        t:SetText(W.T(label))
    end
    p.summary = W.Text(p, "GameFontHighlight")
    p.summary:SetPoint("TOPLEFT", 50, TOP - 30 - 7 * (size + gap) - 14)
    p.summary:SetWidth(900)
end

function Progress:Refresh_calendar(p)
    self.title:SetText(W.T("Play-Time Calendar"))
    self.sub:SetText(W.T("The last year on this character: darker squares mean more time played. Hover a square for the day."))
    local dayTime = FS.db.char.dayTime or {}
    local pal = W.Pal()
    local today = time()
    local weekday = tonumber(date("%w", today)) -- 0 = Sunday
    local offset = (weekday + 6) % 7          -- Monday = 0
    local most, total, days, best, bestDay = 1, 0, 0, 0, nil
    for _, s in pairs(dayTime) do most = math.max(most, s) end
    for i, b in ipairs(p.cells) do
        local w, d = math.floor((i - 1) / 7), (i - 1) % 7
        local back = (52 - w) * 7 + (offset - d)
        local t = today - back * 86400
        local day = date("%Y-%m-%d", t)
        local secs = (back >= 0) and (dayTime[day] or 0) or 0
        b.day, b.secs, b.label = day, secs, date("%a %d.%m.%Y", t)
        b:SetShown(back >= 0)
        if secs > 0 then
            local level = math.min(1, 0.25 + 0.75 * secs / most)
            b.tex:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], level)
            total, days = total + secs, days + 1
            if secs > best then best, bestDay = secs, b.label end
        else
            b.tex:SetColorTexture(1, 1, 1, 0.06)
        end
    end
    p.summary:SetText(days > 0 and string.format(W.T("%d days played, %s in total. Busiest day: %s (%s)."), days,
        W.Plain(W.Duration(total)), bestDay or "-", W.Plain(W.Duration(best))) or W.Color(W.T("Nothing yet: every day you play fills a square."), "888888"))
end

-- Snapshots ----------------------------------------------------------------

function Progress:SnapshotValues(rec)
    local v = { level = tonumber(rec.level) or 0 }
    for key in pairs(FS.STATS) do v[key] = FS:GetValue(rec, key, "all") end
    return v
end

function Progress:Build_snapshots(p)
    p.name = W.Search(p, 220, "Name (e.g. Before Naxx)")
    p.name:SetPoint("TOPLEFT", 14, TOP)
    p.save = W.Button(p, "Save Snapshot", 140, 24, function()
        local me = FS:GetMyRecord()
        if not me then return end
        local snaps = FS.db.char.snapshots
        local name = strtrim(p.name:GetText() or "")
        if name == "" then name = date("%d.%m.%Y") end
        table.insert(snaps, 1, { name = name:sub(1, 40), t = time(), v = self:SnapshotValues(me) })
        for i = #snaps, 11, -1 do snaps[i] = nil end
        p.name:SetText("")
        self.snapIndex = 1
        self:Refresh()
    end)
    p.save:SetPoint("LEFT", p.name, "RIGHT", 8, 0)
    p.prev = W.Button(p, "<", 26, 24, function() self:CycleSnapshot(-1) end)
    p.prev:SetPoint("LEFT", p.save, "RIGHT", 24, 0)
    p.which = W.Text(p, "GameFontHighlight", "CENTER")
    p.which:SetPoint("LEFT", p.prev, "RIGHT", 4, 0)
    p.which:SetWidth(260)
    p.next = W.Button(p, ">", 26, 24, function() self:CycleSnapshot(1) end)
    p.next:SetPoint("LEFT", p.which, "RIGHT", 4, 0)
    p.delete = W.Button(p, "Remove", 90, 24, function()
        local snaps = FS.db.char.snapshots
        if snaps[self.snapIndex or 1] then table.remove(snaps, self.snapIndex or 1); self.snapIndex = 1; self:Refresh() end
    end)
    p.delete:SetPoint("LEFT", p.next, "RIGHT", 8, 0)
    p.list = W.List(p, {
        { label = "Stat", width = 300 }, { label = "Then", width = 180, justify = "RIGHT" }, { label = "Now", width = 180, justify = "RIGHT" },
        { label = "Change", width = 180, justify = "RIGHT" },
    }, { id = "snapshots", noTooltip = true, emptyText = "Save a snapshot now, and come back later to see how far you've come." })
    p.list.frame:SetPoint("TOPLEFT", 14, TOP - 34)
    p.list.frame:SetPoint("BOTTOMRIGHT", -12, 10)
end

function Progress:CycleSnapshot(delta)
    local n = #FS.db.char.snapshots
    if n == 0 then return end
    self.snapIndex = (((self.snapIndex or 1) - 1 + delta) % n) + 1
    self:Refresh()
end

function Progress:Refresh_snapshots(p)
    self.title:SetText(W.T("Snapshots"))
    self.sub:SetText(W.T("Save your stats at a moment that matters (launch day, before a raid) and see what changed since."))
    local snaps = FS.db.char.snapshots
    local snap = snaps[self.snapIndex or 1]
    p.which:SetText(snap and string.format("%s  (%s)", snap.name, date("%d.%m.%Y", snap.t)) or W.Color(W.T("No snapshots yet"), "888888"))
    for _, b in ipairs({ p.prev, p.next, p.delete }) do b:SetShown(snap ~= nil) end
    local rows = {}
    local me = FS:GetMyRecord()
    if snap and me then
        local now = self:SnapshotValues(me)
        local keys = {}
        for k in pairs(now) do if (now[k] or 0) ~= (snap.v[k] or 0) then table.insert(keys, k) end end
        table.sort(keys, function(a, b)
            local la = a == "level" and "Level" or FS.STATS[a].label
            local lb = b == "level" and "Level" or FS.STATS[b].label
            return la < lb
        end)
        for _, k in ipairs(keys) do
            local then_, now_ = snap.v[k] or 0, now[k] or 0
            local fmt = function(v) return k == "level" and tostring(v) or W.FormatStat(k, v) end
            local diff = now_ - then_
            table.insert(rows, { sv = { [4] = diff }, cells = { k == "level" and "Level" or FS.STATS[k].label, fmt(then_), fmt(now_),
                W.Color((diff > 0 and "+" or "-") .. W.Plain(fmt(math.abs(diff))), diff > 0 and "1eff00" or "ff5555") } })
        end
    end
    p.list:SetRows(rows)
end

-- Titles -------------------------------------------------------------------

function Progress:Build_titles(p)
    p.list = W.List(p, {
        { label = "Title", width = 240 }, { label = "Holder", width = 260 }, { label = "Stat", width = 240 },
        { label = "Value", width = 160, justify = "RIGHT" },
    }, { id = "titles", onClick = function(rec) UI:OpenInspector(rec) end,
         emptyText = "Titles appear once your network has some stats to compete on." })
    p.list.frame:SetPoint("TOPLEFT", 14, TOP)
    p.list.frame:SetPoint("BOTTOMRIGHT", -12, 10)
end

function Progress:Refresh_titles(p)
    self.titleCache = nil
    local holders = self:TitleHolders()
    local mine = {}
    local rows = {}
    for _, h in ipairs(holders) do
        if h.rec.isMyChar then table.insert(mine, h.def.title) end
        table.insert(rows, { rec = h.rec, isSelf = h.rec.isMyChar, cells = { W.Color(h.def.title, "ffd100"), W.Label(h.rec),
            FS.STATS[h.def.key].label, W.FormatStat(h.def.key, h.value) } })
    end
    self.title:SetText(W.T("Titles"))
    self.sub:SetText(#mine > 0 and (W.T("Your titles: ") .. W.Color(table.concat(mine, ", "), "ffd100"))
        or W.T("Lead a stat in your network to earn its title. Titles show in tooltips."))
    p.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Mini panel: a few live session numbers while you play
---------------------------------------------------------------------------

function Progress:BuildMini()
    if self.miniFrame then return end
    local f = W.Box(UIParent, "panel")
    f:SetSize(210, 118)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, rel, x, y = frame:GetPoint()
        FS.db.profile.mini.point = { point, rel, x, y }
    end)
    local pt = FS.db.profile.mini.point
    if pt then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120) end
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(16, 16)
    f.logo:SetPoint("TOPLEFT", 8, -7)
    f.logo:SetTexture(FS.LOGO)
    f.head = W.Text(f, "GameFontNormalSmall")
    f.head:SetPoint("LEFT", f.logo, "RIGHT", 4, 0)
    f.head:SetText(W.T("This Session"))
    local close = W.Button(f, "x", 18, 18, function() self:ToggleMini(false) end)
    close:SetPoint("TOPRIGHT", -5, -5)
    f.lines = {}
    for i = 1, 5 do
        local t = W.Text(f, "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 17)
        t:SetWidth(190)
        f.lines[i] = t
    end
    self.miniFrame = f
end

function Progress:UpdateMini()
    local f = self.miniFrame
    if not f or not f:IsShown() then return end
    local d = self:Session()
    if not d then return end
    local lines = {
        string.format("%s  %s", W.T("Time"), W.Plain(W.Duration(d.secs))),
        string.format("%s  %s  (%s/h)", W.T("Kills"), W.Num(d.kills), W.Num(math.floor(d.killsH))),
        string.format("%s  %s", W.T("Deaths"), W.Num(d.deaths)),
        string.format("%s  %s  (%s/h)", W.T("Gold"), W.Plain(W.Money(d.goldLooted)), W.Plain(W.Money(math.floor(d.goldH)))),
        d.toLevel and string.format("%s  %s", W.T("Next level"), W.Plain(W.Duration(d.toLevel)))
            or string.format("%s  %s", W.T("Travelled"), W.Plain(W.Distance(d.distance))),
    }
    for i, t in ipairs(f.lines) do t:SetText(lines[i]) end
end

function Progress:ToggleMini(show)
    local m = FS.db.profile.mini
    if show == nil then show = not m.shown end
    m.shown = show and true or false
    self:BuildMini()
    self.miniFrame:SetShown(m.shown)
    self:UpdateMini()
    if UI.MainFrame and UI.MainFrame:IsShown() and self.frame and self.frame:IsShown() then self:Refresh() end
end

function Progress:Enable()
    if FS.db.profile.mini.shown then self:ToggleMini(true) end
    FS:ScheduleRepeatingTimer(function() self:UpdateMini() end, 2)
end
