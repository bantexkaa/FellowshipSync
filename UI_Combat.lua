local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Combat = FS.Combat
local UI, W = FS.UI, FS.W

local BOARDS = {
    { id = "deaths",  label = "Deaths",         key = "deaths",  title = "Total Deaths per Character" },
    { id = "kills",   label = "Kills",          key = "kills",   title = "Total Kills per Character" },
    { id = "duels",   label = "Duels",          key = "duelsWon", title = "Duels Won / Lost" },
    { id = "mobs",    label = "Enemies (Mobs)", title = "Bestiary: Enemies Slain" },
    { id = "raids",   label = "Dungeons & Raids", title = "Dungeon & Raid Log" },
    { id = "damage",  label = "Damage",         key = "damage",  title = "Total Damage Done" },
    { id = "healing", label = "Healing",        key = "healing", title = "Total Healing Done" },
    { id = "crit",    label = "Largest Hit",    key = "crit",    title = "Largest Single Hit (Blizzard statistic)" },
}

function Combat:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current = "deaths"

    local items = {}
    for _, b in ipairs(BOARDS) do table.insert(items, { id = b.id, label = b.label }) end
    self.tabs = W.SubTabs(f, items, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)

    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.search = W.Search(f, 260, "Search character or owner...", function(q) self.query = q; self:Refresh() end)
    self.search:SetPoint("TOPRIGHT", -36, -44)

    self.charList = W.List(f, {
        { label = "#", width = 36 },
        { label = "Character", width = 380 },
        { label = "Class", width = 110 },
        { label = "Value", width = 170, justify = "RIGHT" },
        { label = "", width = 190, justify = "RIGHT" },
    }, { onClick = function(rec) UI:OpenInspector(rec, self.lastRecs) end })
    self.mobList = W.List(f, {
        { label = "#", width = 40 },
        { label = "Enemy", width = 330 },
        { label = "Times Slain", width = 120, justify = "RIGHT" },
        { label = "Slayers", width = 70, justify = "RIGHT" },
        { label = "Top Slayer", width = 310, justify = "RIGHT" },
    }, { noTooltip = true, emptyText = "No kills recorded yet. Enemies count when they die near you (target or nameplate) and you or your group tagged them." })
    self.raidList = W.List(f, {
        { label = "#", width = 36 }, { label = "Boss", width = 210 }, { label = "Instance", width = 170 },
        { label = "Kills", width = 60, justify = "RIGHT" }, { label = "Wipes", width = 60, justify = "RIGHT" },
        { label = "Fastest Kill", width = 170, justify = "RIGHT" }, { label = "First Kill", width = 170, justify = "RIGHT" },
    }, { onClick = function(rec) UI:OpenInspector(rec) end,
         emptyText = "No boss fights recorded yet. Every boss kill and wipe in dungeons and raids is logged automatically." })
    self.raidList.frame:SetPoint("TOPLEFT", 14, -76)
    self.raidList.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    self.bestiary = W.Text(f, "GameFontHighlightSmall")
    self.bestiary:SetPoint("LEFT", self.title, "RIGHT", 16, 0)
    for _, l in ipairs({ self.charList, self.mobList }) do
        l.frame:SetPoint("TOPLEFT", 14, -76)
        l.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    end
end

local function BoardById(id)
    for _, b in ipairs(BOARDS) do if b.id == id then return b end end
end

function Combat:Refresh()
    if not self.frame then return end
    local board = BoardById(self.current)
    self.tabs:Select(self.current, true)
    self.title:SetText(board.title .. "  -  " .. UI.SCOPE_TITLES[UI.currentScope] .. (FS:IsWeekMode() and " (This Week)" or ""))
    self.bestiary:SetText("")
    self.raidList.frame:Hide()
    if board.id == "mobs" then return self:RefreshMobs() end
    if board.id == "raids" then return self:RefreshRaids() end

    self.mobList.frame:Hide()
    self.charList.frame:Show()
    local recs = {}
    for _, r in ipairs(FS:GetFilteredCharacters(UI.currentScope)) do
        if W.Matches(r, self.query) then table.insert(recs, r) end
    end
    FS:SortByStat(recs, board.key)
    self.lastRecs = recs

    local extraLabel = ({ deaths = "K/D Ratio", kills = "K/D Ratio", duels = "Win Rate", damage = "Healing",
                          healing = "Damage", crit = "Total Damage" })[board.id] or ""
    self.charList:SetColumnLabel(4, board.id == "duels" and "Won / Lost" or (FS.STATS[board.key] and FS.STATS[board.key].label) or "Value")
    self.charList:SetColumnLabel(5, extraLabel)

    local rows = {}
    for i, r in ipairs(recs) do
        local value = W.FormatStat(board.key, FS:GetValue(r, board.key))
        local extra = ""
        if board.id == "deaths" or board.id == "kills" then
            extra = string.format("%.2f", FS:GetValue(r, "kills") / math.max(1, FS:GetValue(r, "deaths")))
        elseif board.id == "duels" then
            local won, lost = FS:GetValue(r, "duelsWon"), FS:GetValue(r, "duelsLost")
            value = W.Num(won) .. " / " .. W.Num(lost)
            extra = (won + lost) > 0 and string.format("%d%%", math.floor(won / (won + lost) * 100 + 0.5)) or "-"
        elseif board.id == "damage" then extra = W.Short(FS:GetValue(r, "healing"))
        elseif board.id == "healing" then extra = W.Short(FS:GetValue(r, "damage"))
        elseif board.id == "crit" then extra = W.Short(FS:GetValue(r, "damage")) end
        rows[i] = {
            rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo",
            cells = { W.Rank(i), W.Label(r), r.isAccount and "" or UI:FormatClassText(r.cls), W.RankValue(i, value), extra },
        }
    end
    self.charList:SetRows(rows)
end

function Combat:RefreshMobs()
    self.charList.frame:Hide()
    self.mobList.frame:Show()
    local totals, slayers, top = {}, {}, {}
    local kills = 0
    for _, r in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        for name, count in pairs(r.mobs or {}) do
            totals[name] = (totals[name] or 0) + count
            slayers[name] = (slayers[name] or 0) + 1
            kills = kills + count
            if not top[name] or count > top[name].count then top[name] = { rec = r, count = count } end
        end
    end
    local list, kinds = {}, 0
    for name, count in pairs(totals) do
        kinds = kinds + 1
        if not self.query or self.query == "" or name:lower():find(self.query, 1, true) then
            table.insert(list, { name = name, count = count })
        end
    end
    table.sort(list, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    self.bestiary:SetText(string.format("%s enemy types discovered  -  %s kills", W.Color(W.Num(kinds), "ffd100"), W.Color(W.Num(kills), "ffd100")))

    local rows = {}
    for i, m in ipairs(list) do
        local t = top[m.name]
        rows[i] = { cells = { W.Rank(i), W.Color(m.name, "ffd100"), W.RankValue(i, W.Num(m.count)), W.Num(slayers[m.name]),
                              W.CharName(t.rec) .. W.Color(" (" .. W.Num(t.count) .. ")", "888888") } }
    end
    self.mobList:SetRows(rows)
end

-- Every boss in view: kills and wipes (each group member counts their own), the
-- fastest kill and who killed it first. The "Wall of Shame" names the top wiper.
function Combat:RefreshRaids()
    self.charList.frame:Hide()
    self.mobList.frame:Hide()
    self.raidList.frame:Show()
    local bosses, wipers = {}, {}
    local kills, wipes = 0, 0
    for _, r in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        for name, e in pairs(r.encounters or {}) do
            local b = bosses[name]
            if not b then
                b = { name = name, instance = e.instance, kills = 0, wipes = 0 }
                bosses[name] = b
            end
            b.kills, b.wipes = b.kills + (e.kills or 0), b.wipes + (e.wipes or 0)
            kills, wipes = kills + (e.kills or 0), wipes + (e.wipes or 0)
            if e.best and (not b.best or e.best < b.best) then b.best, b.bestRec = e.best, r end
            if e.first and (not b.first or e.first < b.first) then b.first, b.firstRec = e.first, r end
            wipers[r] = (wipers[r] or 0) + (e.wipes or 0)
        end
    end
    local list = {}
    for _, b in pairs(bosses) do
        local hay = (b.name .. " " .. tostring(b.instance)):lower()
        if not self.query or self.query == "" or hay:find(self.query, 1, true) then table.insert(list, b) end
    end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    local shame, shameN = nil, 0
    for r, n in pairs(wipers) do if n > shameN then shame, shameN = r, n end end
    self.bestiary:SetText(string.format("%s bosses  -  %s kills  -  %s wipes%s", W.Color(W.Num(#list), "ffd100"),
        W.Color(W.Num(kills), "1eff00"), W.Color(W.Num(wipes), "ff5555"),
        shame and ("   Wall of Shame: " .. W.CharName(shame) .. W.Color(" (" .. W.Num(shameN) .. " wipes)", "ff5555")) or ""))
    local rows = {}
    for i, b in ipairs(list) do
        rows[i] = { rec = b.firstRec or b.bestRec, cells = {
            W.Rank(i), W.Color(b.name, "ff8000"), W.Color(b.instance or "?", "aaaaaa"), W.Num(b.kills),
            b.wipes > 0 and W.Color(W.Num(b.wipes), "ff5555") or "0",
            b.best and (W.FightTime(b.best) .. "  " .. W.CharName(b.bestRec)) or W.Color("-", "666666"),
            b.firstRec and (W.CharName(b.firstRec) .. W.Color(" " .. date("%d.%m", b.first), "888888")) or W.Color("-", "666666") } }
    end
    self.raidList:SetRows(rows)
end
