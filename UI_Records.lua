local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Records = FS.Records
local UI, W = FS.UI, FS.W

local TABS = {
    { id = "my",       label = "My Records" },
    { id = "zones",    label = "Zones" },
    { id = "loot",     label = "Loot" },
    { id = "gold",     label = "Gold Flow" },
    { id = "survival", label = "Survival" },
    { id = "pvp",      label = "PvP" },
    { id = "social",   label = "Social" },
    { id = "habits",   label = "Habits" },
    { id = "shame",    label = "Shame" },
    { id = "luck",     label = "Luck" },
    { id = "compare",  label = "Compare" },
}
local TOP = -84

-- Column sets for the simple ranked lists: { label, key or function(rec), width }
local function V(key) return function(r) return W.FormatStat(key, FS:GetValue(r, key)) end end
local function Pct(n, d) return d > 0 and string.format("%d%%", math.floor(n / d * 100 + 0.5)) or "-" end
local function WalkedShare(r)
    local foot, ride = FS:GetValue(r, "travelFootLate"), FS:GetValue(r, "travelMountLate")
    return foot + ride, foot
end
local function RollRate(r)
    local made = FS:GetValue(r, "needRolls") + FS:GetValue(r, "greedRolls")
    local won = FS:GetValue(r, "wonNeed") + FS:GetValue(r, "wonGreed")
    return made, won
end
local LISTS = {
    shame = { title = "Hall of Shame", sort = function(r) return FS:GetValue(r, "embarrassingDeaths") + FS:GetValue(r, "leapsOfFaith") end,
              cols = { { "Embarrassing", V("embarrassingDeaths") }, { "Leaps of Faith", V("leapsOfFaith") },
                       { "Biggest Fall", function(r) local v = tonumber(r.highestFall) or 0 return v > 0 and (v .. "% hp") or "-" end },
                       { "Hearth Regrets", V("hearthRegret") }, { "Biggest Repair", function(r) return W.Money(r.biggestRepair) end },
                       { "Walked", function(r) local all, foot = WalkedShare(r) return Pct(foot, all) end },
                       { "Spirit Healer", V("spiritHealer") }, { "Corpse Runs", V("corpseRuns") } } },
    luck = { title = "Luck & Revenge", sort = function(r) return FS:GetValue(r, "revengeKills") end,
             cols = { { "Revenge Kills", V("revengeKills") },
                      { "Roll Win Rate", function(r) local made, won = RollRate(r) return Pct(won, made) end },
                      { "vs Guild", function(r)
                          local made, won = RollRate(r)
                          local avg = Records.luckAvg
                          if made == 0 or not avg then return "-" end
                          local diff = math.floor((won / made - avg) * 100 + 0.5)
                          return W.Color((diff > 0 and "+" or "") .. diff .. "%", diff >= 0 and "1eff00" or "ff5555") end },
                      { "Natural 1s", V("rolls1") }, { "Natural 100s", V("rolls100") },
                      { "Rolls Lost", function(r) local made, won = RollRate(r) return W.Num(math.max(0, made - won)) end },
                      { "Levels from Rest", function(r) local v = tonumber(r.restedLevels) or 0 return v > 0 and W.Decimal(v) or "-" end } } },
    loot = { title = "Loot by Quality", sort = function(r)
                local t = 0
                for _, k in ipairs({ "lootQ0", "lootQ1", "lootQ2", "lootQ3", "epics", "lootQ5" }) do t = t + FS:GetValue(r, k) end
                return t end,
             cols = { { "Poor", V("lootQ0"), "9d9d9d" }, { "Common", V("lootQ1"), "ffffff" }, { "Uncommon", V("lootQ2"), "1eff00" },
                      { "Rare", V("lootQ3"), "0070dd" }, { "Epic", V("epics"), "a335ee" }, { "Legendary", V("lootQ5"), "ff8000" },
                      { "Biggest Loot", function(r) return W.Money(r.biggestLoot) end } } },
    gold = { title = "Gold Flow", sort = function(r) return FS:GetValue(r, "moneyIn") end,
             cols = { { "Earned", V("moneyIn") }, { "Spent", V("moneyOut") },
                      { "Net", function(r)
                          local net = FS:GetValue(r, "moneyIn") - FS:GetValue(r, "moneyOut")
                          return (net < 0 and "|cffff5555-|r" or "") .. W.Money(math.abs(net)) end },
                      { "From Quests", V("goldQuests") }, { "Vendor Sales", V("vendorSales") }, { "Vendor Buys", V("vendorSpent") } } },
    survival = { title = "Survival", sort = function(r) return FS:GetValue(r, "combatTime") end,
                 cols = { { "In Combat", V("combatTime") }, { "Fights", V("fights") }, { "Corpse Runs", V("corpseRuns") },
                          { "Spirit Healer", V("spiritHealer") }, { "Rezzed", V("rezzed") }, { "Potions", V("potions") },
                          { "Food", V("foodDrink") }, { "Bandages", V("bandages") } } },
    pvp = { title = "Player versus Player", sort = function(r) return FS:GetValue(r, "honorKills") + FS:GetValue(r, "pvpKills") end,
            cols = { { "Honorable Kills", V("honorKills") }, { "Players Slain", V("pvpKills") }, { "BGs Played", V("bgPlayed") },
                     { "BGs Won", V("bgWon") },
                     { "Win Rate", function(r)
                         local p = FS:GetValue(r, "bgPlayed")
                         return p > 0 and string.format("%d%%", math.floor(FS:GetValue(r, "bgWon") / p * 100 + 0.5)) or "-" end },
                     { "Duels Won", V("duelsWon") } } },
    social = { title = "Social Butterflies", sort = function(r) return FS:GetValue(r, "whispersSent") + FS:GetValue(r, "emotes") + FS:GetValue(r, "chat") end,
               cols = { { "Chat", V("chat") }, { "Whispers Sent", V("whispersSent") }, { "Received", V("whispersReceived") },
                        { "Emotes", V("emotes") }, { "Favourite", function(r) return r.favEmote and ("/" .. r.favEmote:lower()) or "-" end },
                        { "Trades", V("trades") }, { "Mail Sent", V("mailsSent") }, { "Companions", V("companions") } } },
    habits = { title = "Habits", sort = function(r) return FS:GetValue(r, "daysPlayed") end,
               cols = { { "Sessions", V("sessions") },
                        { "Avg Session", function(r)
                            local s = FS:GetValue(r, "sessions")
                            return s > 0 and W.Duration(FS:GetValue(r, "playtime") / s) or "-" end },
                        { "Longest", V("longestSession") }, { "Days Played", V("daysPlayed") }, { "Best Streak", V("bestStreak") },
                        { "Night Owl", V("nightTime") }, { "Early Bird", V("morningTime") }, { "Reloads", V("reloads") } } },
}

function Records:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current = "my"
    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetWidth(760)
    self.search = W.Search(f, 240, "Search character or owner...", function(q) self.query = q; self:Refresh() end)
    self.search:SetPoint("TOPRIGHT", -36, -44)

    -- One generic list with up to 9 value columns.
    local cols = { { label = "#", width = 30 }, { label = "Character", width = 200 } }
    for i = 1, 8 do table.insert(cols, { label = "", width = 80, justify = "RIGHT" }) end
    self.list = W.List(f, cols, { onClick = function(rec) UI:OpenInspector(rec, self.lastRecs) end })
    self.list.frame:SetPoint("TOPLEFT", 14, TOP)
    self.list.frame:SetPoint("BOTTOMRIGHT", -12, 10)

    self.zoneList = W.List(f, {
        { label = "#", width = 30 }, { label = "Zone", width = 300 }, { label = "Time", width = 140, justify = "RIGHT" },
        { label = "", width = 140, justify = "RIGHT" }, { label = "", width = 300 },
    }, { noTooltip = true, emptyText = "No time recorded in any zone yet." })
    self.zoneList.frame:SetPoint("TOPLEFT", 14, TOP)
    self.zoneList.frame:SetPoint("BOTTOMRIGHT", -12, 10)

    self:BuildMyRecords(f)
    self:BuildCompare(f)
end

function Records:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    self.cmpPage:SetShown(self.current == "compare")
    if self.current == "compare" then
        self.myPage:Hide(); self.zoneList.frame:Hide(); self.list.frame:Hide(); self.search:Hide()
        return self:RefreshCompare()
    end
    local my = self.current == "my" and UI.currentScope == "solo"
    self.myPage:SetShown(my)
    self.zoneList.frame:SetShown(self.current == "zones")
    self.list.frame:SetShown(not my and self.current ~= "zones")
    self.search:SetShown(not my)
    local suffix = "  -  " .. UI.SCOPE_TITLES[UI.currentScope] .. (FS:IsWeekMode() and " (This Week)" or "")
    if self.current == "my" then
        if my then return self:RefreshMyRecords() end
        return self:RefreshRecordsBoard(suffix)
    elseif self.current == "zones" then
        return self:RefreshZones(suffix)
    end
    local def = LISTS[self.current]
    self.title:SetText(def.title .. suffix)
    local subs = {
        shame = "Embarrassing = killed by falling, drowning, lava, a critter or something 10+ levels lower. Leap of faith = died falling within 5 s of jumping. Walked = on foot after you could ride.",
        luck = "Revenge = killing the kind of enemy that last killed you. vs Guild = your roll win rate compared with the guild average.",
    }
    self.sub:SetText(subs[self.current] or (self.current == "survival" and FS.HAS_COMBAT_LOG and "Close calls (survived below 10% health) are in each character's Inspector."
        or "Click a character to inspect them."))
    for i = 1, 8 do self.list:SetColumnLabel(i + 2, def.cols[i] and def.cols[i][1] or "") end
    local recs = {}
    for _, r in ipairs(FS:GetFilteredCharacters(UI.currentScope)) do
        if W.Matches(r, self.query) then table.insert(recs, r) end
    end
    if self.current == "luck" then -- the guild's average roll win rate, for "vs Guild"
        local made, won = 0, 0
        for _, r in ipairs(FS:GetScopeCharacters("guild")) do local m, w = RollRate(r); made, won = made + m, won + w end
        self.luckAvg = made > 0 and won / made or nil
    end
    table.sort(recs, function(a, b)
        local x, y = def.sort(a), def.sort(b)
        if x == y then return tostring(a.fullName) < tostring(b.fullName) end
        return x > y
    end)
    self.lastRecs = recs
    local rows = {}
    for i, r in ipairs(recs) do
        local cells = { W.Rank(i), W.Label(r) }
        for c = 1, 8 do
            local col = def.cols[c]
            local text = col and col[2](r) or ""
            if col and col[3] then text = W.Color(text, col[3]) end
            cells[c + 2] = text
        end
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo", cells = cells }
    end
    self.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------

function Records:RefreshZones(suffix)
    local solo = UI.currentScope == "solo"
    self.title:SetText((solo and "Where You Live" or "Most Popular Zones") .. suffix)
    self.sub:SetText(solo and "Time spent in each zone across your characters." or "Total time everyone in view has spent in each zone.")
    self.explorerRank = true
    local zones = {}
    for _, r in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        for _, z in ipairs(r.zones or {}) do
            local name, sec = z[1], tonumber(z[2]) or 0
            local e = zones[name] or { zone = name, time = 0, players = {}, top = nil, topTime = 0 }
            e.time = e.time + sec
            e.players[r.owner or r.fullName] = true
            if sec > e.topTime then e.top, e.topTime = r, sec end
            zones[name] = e
        end
    end
    local list, total = {}, 0
    for _, e in pairs(zones) do
        if not self.query or self.query == "" or e.zone:lower():find(self.query, 1, true) then table.insert(list, e) end
        total = total + e.time
    end
    table.sort(list, function(a, b) return a.time > b.time end)
    self.zoneList:SetColumnLabel(4, solo and "Share" or "Players")
    self.zoneList:SetColumnLabel(5, solo and "" or "Top Resident")
    local rows = {}
    for i, e in ipairs(list) do
        local players = 0
        for _ in pairs(e.players) do players = players + 1 end
        rows[i] = { cells = { W.Rank(i), W.Color(e.zone, "ffd100"), W.RankValue(i, W.Duration(e.time)),
            solo and string.format("%d%%", math.floor(e.time / math.max(1, total) * 100 + 0.5)) or W.Num(players),
            (not solo and e.top) and (W.CharName(e.top) .. W.Color(" " .. W.Duration(e.topTime), "888888")) or "" } }
        if i >= 150 then break end
    end
    self.zoneList:SetRows(rows)
    if solo then -- explorer rank from the zones you've visited
        local n = 0
        for _ in pairs(zones) do n = n + 1 end
        local rank = n >= 30 and "Cartographer" or (n >= 10 and "Wanderer" or "Tourist")
        self.sub:SetText(string.format("%s   %s", self.sub:GetText(), W.Color(string.format(W.T("%d zones visited: %s"), n, W.T(rank)), "ffd100")))
    end
end

---------------------------------------------------------------------------
-- My Records (personal page) and the records leaderboard
---------------------------------------------------------------------------

function Records:BuildMyRecords(f)
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    self.myPage = page
    local scroll, c = W.ScrollArea(page)
    scroll:SetPoint("TOPLEFT", 14, TOP)
    scroll:SetPoint("BOTTOMRIGHT", -34, 10)
    c:SetSize(950, 560)
    self.myContent = c

    self.prevChar = W.Button(page, "<", 26, 22, function() self:CycleChar(-1) end)
    self.prevChar:SetPoint("TOPRIGHT", -150, -44)
    self.nextChar = W.Button(page, ">", 26, 22, function() self:CycleChar(1) end)
    self.nextChar:SetPoint("LEFT", self.prevChar, "RIGHT", 4, 0)

    -- Personal bests (2 rows of 3)
    self.cards = {}
    local cw = (950 - 20) / 3
    for i = 1, 6 do
        local card = W.Box(c, "card")
        card:SetSize(cw, 70)
        card:SetPoint("TOPLEFT", ((i - 1) % 3) * (cw + 10), -math.floor((i - 1) / 3) * 78)
        card.label = W.Text(card, "GameFontDisableSmall")
        card.label:SetPoint("TOPLEFT", 12, -10)
        card.value = W.Text(card, "GameFontNormalLarge")
        card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -6)
        card.note = W.Text(card, "GameFontHighlightSmall")
        card.note:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -4)
        self.cards[i] = card
    end

    -- Streaks
    local streak = W.Box(c, "accent")
    streak:SetSize(950, 34)
    streak:SetPoint("TOPLEFT", 0, -160)
    self.streakText = W.Text(streak, "GameFontHighlight")
    self.streakText:SetPoint("LEFT", 12, 0)

    -- Play-time clock
    local clock = W.Box(c, "card")
    clock:SetSize(950, 140)
    clock:SetPoint("TOPLEFT", 0, -204)
    self.clockTitle = W.Text(clock, "GameFontNormal")
    self.clockTitle:SetPoint("TOPLEFT", 12, -10)
    self.clockVerdict = W.Text(clock, "GameFontHighlight", "RIGHT")
    self.clockVerdict:SetPoint("TOPRIGHT", -12, -10)
    self.bars = {}
    local bw = (950 - 24) / 24
    for h = 1, 24 do
        local bar = clock:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("BOTTOMLEFT", 12 + (h - 1) * bw, 22)
        bar:SetSize(bw - 3, 1)
        self.bars[h] = bar
        if (h - 1) % 3 == 0 then
            local label = W.Text(clock, "GameFontDisableSmall")
            label:SetPoint("BOTTOMLEFT", 12 + (h - 1) * bw, 6)
            label:SetText(string.format("%02d", h - 1))
        end
    end

    -- Favourites and lifetime
    local half = (950 - 10) / 2
    local fav = W.Box(c, "card")
    fav:SetSize(half, 150)
    fav:SetPoint("TOPLEFT", 0, -354)
    local life = W.Box(c, "card")
    life:SetSize(half, 150)
    life:SetPoint("TOPLEFT", half + 10, -354)
    self.favTitle, self.lifeTitle = W.Text(fav, "GameFontNormal"), W.Text(life, "GameFontNormal")
    self.favTitle:SetPoint("TOPLEFT", 12, -10)
    self.lifeTitle:SetPoint("TOPLEFT", 12, -10)
    self.favTitle:SetText("Favourites")
    self.lifeTitle:SetText("Lifetime")
    self.favLines, self.lifeLines = {}, {}
    for i = 1, 5 do
        local a = W.Text(fav, "GameFontHighlightSmall")
        a:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 22)
        a:SetWidth(half - 24)
        self.favLines[i] = a
        local b = W.Text(life, "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 22)
        b:SetWidth(half - 24)
        self.lifeLines[i] = b
    end
end

function Records:MyChars()
    local list = FS:GetScopeCharacters("solo")
    table.sort(list, function(a, b) return (a.lastUpdate or 0) > (b.lastUpdate or 0) end)
    return list
end

function Records:CycleChar(delta)
    local list = self:MyChars()
    if #list == 0 then return end
    local index = 1
    for i, r in ipairs(list) do if r == self.myRec then index = i end end
    self.myRec = list[((index - 1 + delta) % #list) + 1]
    self:Refresh()
end

local function Verdict(hours)
    local best, bestH = -1, 1
    for h = 1, 24 do if (hours[h] or 0) > best then best, bestH = hours[h] or 0, h end end
    if best <= 0 then return "Not enough data yet", nil end
    local h = bestH - 1
    if h < 5 then return "Night Owl", h end
    if h < 9 then return "Early Bird", h end
    if h < 12 then return "Morning Adventurer", h end
    if h < 17 then return "Afternoon Hero", h end
    if h < 21 then return "Evening Raider", h end
    return "Late-Night Legend", h
end

function Records:RefreshMyRecords()
    local list = self:MyChars()
    if not self.myRec or not FS.db.global.characters[self.myRec.fullName] then self.myRec = FS:GetMyRecord() or list[1] end
    local rec = self.myRec
    self.prevChar:SetShown(#list > 1)
    self.nextChar:SetShown(#list > 1)
    if not rec then return end
    local r = rec.records or {}
    self.title:SetText("My Records  -  " .. W.CharName(rec))
    self.sub:SetText("Personal bests, streaks and habits. Use < > to switch between your characters.")

    local fastest, fastestBoss
    for boss, e in pairs(rec.encounters or {}) do
        if e.best and (not fastest or e.best < fastest) then fastest, fastestBoss = e.best, boss end
    end
    local cards = {
        { "Longest Life", W.Duration(rec.longestLife), "Current life: " .. W.Duration(rec.curLife or 0) },
        { "Longest Session", W.Duration(rec.longestSession), W.Num(rec.sessions) .. " sessions in total" },
        { "Most Kills in a Session", W.Num(r.killsSession), "Total kills: " .. W.Num(rec.kills) },
        { "Most Levels in a Day", W.Num(r.levelsDay), "Now level " .. tostring(rec.level or "?") },
        { "Best Gold Day", W.Money(r.goldDay), "Biggest single loot: " .. W.Money(rec.biggestLoot) },
        { "Fastest Boss Kill", fastest and W.FightTime(fastest) or "-", fastestBoss or "No boss kills yet" },
    }
    for i, card in ipairs(self.cards) do
        card.label:SetText(string.upper(cards[i][1]))
        card.value:SetText(cards[i][2])
        W.AccentText(card.value)
        card.note:SetText(cards[i][3])
    end
    self.streakText:SetText(string.format("Days played: %s     Current streak: %s     Best streak: %s days in a row",
        W.Color(W.Num(rec.daysPlayed), "ffd100"), W.Color(W.Num(r.curStreak or 0) .. " days", "1eff00"), W.Color(W.Num(rec.bestStreak), "ffd100")))

    local hours = rec.hours or {}
    local most = 1
    for h = 1, 24 do most = math.max(most, hours[h] or 0) end
    local pal = W.Pal()
    local verdict, peak = Verdict(hours)
    for h, bar in ipairs(self.bars) do
        local v = hours[h] or 0
        bar:SetHeight(math.max(1, v / most * 80))
        local hot = peak and (h - 1) == peak
        bar:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], hot and 1 or 0.55)
    end
    self.clockTitle:SetText("When You Play")
    W.AccentText(self.clockTitle)
    if peak then
        local article = verdict:match("^[AEIOU]") and "an" or "a"
        self.clockVerdict:SetText(string.format("You're %s %s (busiest hour %02d:00)", article, W.Color(verdict, "ffd100"), peak))
    else
        self.clockVerdict:SetText(W.Color(verdict, "888888"))
    end
    W.AccentText(self.favTitle)
    W.AccentText(self.lifeTitle)

    local zone = rec.zones and rec.zones[1]
    local companion, ctime
    for key, b in pairs(rec.bonds or {}) do if not ctime or (b.time or 0) > ctime then companion, ctime = key, b.time or 0 end end
    local enemy, ekills
    for name, n in pairs(rec.mobs or {}) do if not ekills or n > ekills then enemy, ekills = name, n end end
    local nemesis, nk
    for name, n in pairs(rec.killers or {}) do if not nk or n > nk then nemesis, nk = name, n end end
    local fav = {
        "Zone: " .. (zone and (W.Color(zone[1], "ffd100") .. W.Color("  " .. W.Duration(zone[2]), "888888")) or "-"),
        "Companion: " .. (companion and (W.Color(FS.ShortName(companion), "ffffff") .. W.Color("  " .. W.Duration(ctime), "888888")) or "-"),
        "Favourite enemy: " .. (enemy and (W.Color(enemy, "ffd100") .. W.Color("  " .. W.Num(ekills) .. " slain", "888888")) or "-"),
        "Nemesis: " .. (nemesis and W.Color(nemesis .. " (" .. nk .. ")", "ff5555") or "-"),
        "Emote: " .. (rec.favEmote and W.Color("/" .. rec.favEmote:lower(), "ffd100") or "-"),
    }
    local lifetime = {
        string.format("Played %s over %s sessions (avg %s)", W.Duration(rec.playtime), W.Num(rec.sessions),
            W.Duration((tonumber(rec.playtime) or 0) / math.max(1, tonumber(rec.sessions) or 1))),
        string.format("Explored %s areas, found %s flight paths, hearthed %s times", W.Num(rec.areasDiscovered), W.Num(rec.flightPathsFound), W.Num(rec.hearths)),
        string.format("Swam %s, ran %s as a ghost (%s corpse runs)", W.Distance(rec.travelSwim), W.Distance(rec.corpseDistance), W.Num(rec.corpseRuns)),
        string.format("%s in combat over %s fights%s", W.Duration(rec.combatTime), W.Num(rec.fights),
            FS.HAS_COMBAT_LOG and string.format(", %s close calls", W.Num(rec.closeCalls)) or ""),
        string.format("%s whispers sent, %s emotes, %s UI reloads", W.Num(rec.whispersSent), W.Num(rec.emotes), W.Num(rec.reloads)),
    }
    for i = 1, 5 do self.favLines[i]:SetText(fav[i]); self.lifeLines[i]:SetText(lifetime[i]) end
end

function Records:RefreshRecordsBoard(suffix)
    self.title:SetText("Records Board" .. suffix)
    self.sub:SetText("Personal bests side by side. Switch to My Characters for your own records page.")
    local labels = { "Longest Life", "Longest Session", "Kills/Session", "Levels/Day", "Best Gold Day", "Days Played", "Best Streak", "Sessions" }
    for i = 1, 8 do self.list:SetColumnLabel(i + 2, labels[i]) end
    local recs = {}
    for _, r in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        if W.Matches(r, self.query) then table.insert(recs, r) end
    end
    table.sort(recs, function(a, b) return (tonumber(a.longestLife) or 0) > (tonumber(b.longestLife) or 0) end)
    self.lastRecs = recs
    local rows = {}
    for i, r in ipairs(recs) do
        local rc = r.records or {}
        rows[i] = { rec = r, isSelf = r.isMyChar, cells = { W.Rank(i), W.Label(r), W.RankValue(i, W.Duration(r.longestLife)),
            W.Duration(r.longestSession), W.Num(rc.killsSession), W.Num(rc.levelsDay), W.Money(rc.goldDay),
            W.Num(r.daysPlayed), W.Num(r.bestStreak), W.Num(FS:GetValue(r, "sessions")) } }
    end
    self.list:SetRows(rows)
end

---------------------------------------------------------------------------
-- Compare: any two characters, every stat side by side
---------------------------------------------------------------------------

function Records:BuildCompare(f)
    local page = CreateFrame("Frame", nil, f)
    page:SetAllPoints()
    page:Hide()
    self.cmpPage = page
    local function Picker(x, side)
        local prev = W.Button(page, "<", 26, 22, function() self:CycleCompare(side, -1) end)
        prev:SetPoint("TOPLEFT", x, -84)
        local label = W.Text(page, "GameFontHighlight", "CENTER")
        label:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        label:SetWidth(240)
        local nextB = W.Button(page, ">", 26, 22, function() self:CycleCompare(side, 1) end)
        nextB:SetPoint("LEFT", label, "RIGHT", 4, 0)
        return label
    end
    self.cmpLabelA = Picker(14, "A")
    self.cmpLabelB = Picker(340, "B")
    self.cmpList = W.List(page, {
        { label = "Stat", width = 260 }, { label = "Left", width = 200, justify = "RIGHT" },
        { label = "Right", width = 200, justify = "RIGHT" }, { label = "Leader", width = 200, justify = "RIGHT" },
    }, { noTooltip = true, id = "compare", emptyText = "Pick two characters with the arrows above." })
    self.cmpList.frame:SetPoint("TOPLEFT", 14, -114)
    self.cmpList.frame:SetPoint("BOTTOMRIGHT", -12, 10)
end

function Records:CompareCandidates()
    local list = FS:GetScopeCharacters(UI.currentScope == "solo" and "network" or UI.currentScope)
    table.sort(list, function(a, b) return tostring(a.fullName) < tostring(b.fullName) end)
    return list
end

function Records:CycleCompare(side, delta)
    local list = self:CompareCandidates()
    if #list == 0 then return end
    local field = side == "A" and "cmpA" or "cmpB"
    local index = 0
    for i, r in ipairs(list) do if r.fullName == self[field] then index = i end end
    self[field] = list[((index - 1 + delta) % #list) + 1].fullName
    self:Refresh()
end

function Records:RefreshCompare()
    local chars, list = FS.db.global.characters, self:CompareCandidates()
    if not chars[self.cmpA or ""] then self.cmpA = (FS:GetMyRecord() or list[1] or {}).fullName end
    if not chars[self.cmpB or ""] then
        for _, r in ipairs(list) do if r.fullName ~= self.cmpA then self.cmpB = r.fullName break end end
    end
    local a, b = chars[self.cmpA or ""], chars[self.cmpB or ""]
    self.cmpLabelA:SetText(a and W.CharName(a) or "-")
    self.cmpLabelB:SetText(b and W.CharName(b) or "-")
    self.cmpList:SetColumnLabel(2, a and FS.ShortName(a.fullName) or "Left")
    self.cmpList:SetColumnLabel(3, b and FS.ShortName(b.fullName) or "Right")
    if not a or not b then
        self.title:SetText(W.T("Compare"))
        self.sub:SetText(W.T("Pick two characters with the arrows above."))
        self.cmpList:SetRows({})
        return
    end
    local keys = {}
    for key in pairs(FS.STATS) do table.insert(keys, key) end
    table.sort(keys, function(x, y) return FS.STATS[x].label < FS.STATS[y].label end)
    local rows, wa, wb = {}, 0, 0
    for _, key in ipairs(keys) do
        local x, y = FS:GetValue(a, key), FS:GetValue(b, key)
        if x ~= 0 or y ~= 0 then
            local lower = FS.STATS[key].lower
            local lead = (x == y) and 0 or (((x > y) ~= (lower == true)) and 1 or 2)
            if lead == 1 then wa = wa + 1 elseif lead == 2 then wb = wb + 1 end
            table.insert(rows, { sv = { [2] = x, [3] = y }, cells = { FS.STATS[key].label, W.FormatStat(key, x), W.FormatStat(key, y),
                lead == 1 and W.Color(FS.ShortName(a.fullName), "1eff00") or lead == 2 and W.Color(FS.ShortName(b.fullName), "1eff00") or W.Color("-", "888888") } })
        end
    end
    self.cmpList:SetRows(rows)
    self.title:SetText(string.format("%s  %s - %s  %s", W.CharName(a), W.Color(wa, "1eff00"), W.Color(wb, "1eff00"), W.CharName(b)))
    self.sub:SetText(string.format(W.T("Every stat side by side (%s). The number is how many stats each one leads."),
        FS:IsWeekMode() and W.T("This Week") or W.T("All-Time")))
end

function Records:ShareText()
    if self.current == "compare" then
        local a, b = FS.db.global.characters[self.cmpA or ""], FS.db.global.characters[self.cmpB or ""]
        if a and b then return W.Plain(self.title:GetText()) .. " (stats led)" end
    elseif self.current == "my" and UI.currentScope == "solo" and self.myRec then
        local r, rc = self.myRec, self.myRec.records or {}
        return string.format("%s's records: longest life %s, longest session %s, %s kills in one session, best streak %s days.",
            FS.ShortName(r.fullName), W.Plain(W.Duration(r.longestLife)), W.Plain(W.Duration(r.longestSession)),
            W.Num(rc.killsSession), W.Num(r.bestStreak))
    end
end
