local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Fellowship = FS.Fellowship
local W = FS.W
local IsSecret = FS.IsSecret

local function Clean(v) if v == nil or IsSecret(v) then return nil end return v end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function Fellowship:Enable()
    LibStub("AceEvent-3.0"):Embed(self)
    for _, ev in ipairs({ "RESURRECT_REQUEST", "ENCOUNTER_END", "PLAYER_DEAD" }) do FS.SafeRegister(self, ev) end
    FS:ScheduleRepeatingTimer(function() self:SampleGroup() end, 10)
    FS:ScheduleRepeatingTimer(function() self:CheckBounties(); self:SettleWagers() end, 300)
    FS:ScheduleTimer(function() self:CheckBounties(); self:SettleWagers(); self:OnThisDayToast() end, 20)
end

---------------------------------------------------------------------------
-- 1. Fellowship Bonds: who you actually play with
---------------------------------------------------------------------------

Fellowship.BOND_LEVELS = {
    { 0,      "Acquaintance",   "aaaaaa" },
    { 3600,   "Companion",      "1eff00" },
    { 18000,  "Comrade",        "0070dd" },
    { 72000,  "Battle-Sibling", "a335ee" },
    { 180000, "Fellowship",     "ff8000" },
}

function Fellowship.BondLevel(seconds)
    local level = Fellowship.BOND_LEVELS[1]
    for _, l in ipairs(Fellowship.BOND_LEVELS) do if (seconds or 0) >= l[1] then level = l end end
    return level[2], level[3]
end

-- Group members as character keys in our own "Name-Realm" format.
function Fellowship:MemberKey(unit)
    local name, second = UnitName(unit)
    name = Clean(name)
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    second = Clean(second)
    if FS.IS_FOREVER and second and second ~= "" then return name .. " " .. second .. "-" .. (GetRealmName() or "") end
    if second and second ~= "" then return name .. "-" .. second end
    return name .. "-" .. (GetRealmName() or "")
end

function Fellowship:GroupMembers()
    local out = {}
    if not IsInGroup or not IsInGroup() then return out end
    local raid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, raid and count or (count - 1) do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local key = self:MemberKey(unit)
            if key then
                local _, cls = UnitClass(unit)
                table.insert(out, { key = key, cls = Clean(cls) })
            end
        end
    end
    return out
end

function Fellowship:Bond(key, cls)
    local bonds = FS.db.char.bonds
    local b = bonds[key]
    if not b then
        local n = 0
        for _ in pairs(bonds) do n = n + 1 end
        if n >= 200 then -- forget the weakest bond to make room
            local weakest, wt
            for k, v in pairs(bonds) do if not wt or (v.time or 0) < wt then weakest, wt = k, v.time or 0 end end
            bonds[weakest] = nil
        end
        b = { time = 0, bosses = 0, deaths = 0, rezzes = 0 }
        bonds[key] = b
    end
    if cls then b.cls = cls end
    return b
end

function Fellowship:SampleGroup()
    for _, m in ipairs(self:GroupMembers()) do
        local b = self:Bond(m.key, m.cls)
        b.time = b.time + 10
        b.last = time()
    end
end

function Fellowship:ENCOUNTER_END(_, _, name, _, _, success)
    if IsSecret(success) or not (success == 1 or success == true) then return end
    for _, m in ipairs(self:GroupMembers()) do local b = self:Bond(m.key, m.cls); b.bosses = b.bosses + 1 end
end

function Fellowship:PLAYER_DEAD()
    for _, m in ipairs(self:GroupMembers()) do local b = self:Bond(m.key, m.cls); b.deaths = b.deaths + 1 end
end

function Fellowship:RESURRECT_REQUEST(_, name)
    name = Clean(name)
    if type(name) ~= "string" or name == "" then return end
    local key = name:find("-", 1, true) and name or (name .. "-" .. (GetRealmName() or ""))
    local b = self:Bond(key)
    b.rezzes = b.rezzes + 1
end

-- Your companions across all your characters (merged), strongest first.
function Fellowship:MyCompanions()
    local merged = {}
    for _, rec in ipairs(FS:GetScopeCharacters("solo")) do
        for key, b in pairs(rec.bonds or {}) do
            local m = merged[key] or { key = key, time = 0, bosses = 0, deaths = 0, rezzes = 0, last = 0, with = {} }
            m.time, m.bosses = m.time + (b.time or 0), m.bosses + (b.bosses or 0)
            m.deaths, m.rezzes = m.deaths + (b.deaths or 0), m.rezzes + (b.rezzes or 0)
            m.last, m.cls = math.max(m.last, b.last or 0), m.cls or b.cls
            m.with[rec.fullName] = (m.with[rec.fullName] or 0) + (b.time or 0)
            merged[key] = m
        end
    end
    local list = {}
    for _, m in pairs(merged) do table.insert(list, m) end
    table.sort(list, function(a, b) return a.time > b.time end)
    return list
end

-- Strongest pairs in a scope (each pair once, using the larger of both sides).
function Fellowship:GuildBonds(scope)
    local pairsByKey = {}
    for _, rec in ipairs(FS:GetScopeCharacters(scope)) do
        for key, b in pairs(rec.bonds or {}) do
            local a, c = rec.fullName, key
            local id = (a < c) and (a .. "|" .. c) or (c .. "|" .. a)
            local p = pairsByKey[id]
            if not p or (b.time or 0) > p.time then
                pairsByKey[id] = { a = a, b = c, time = b.time or 0, bosses = b.bosses or 0, deaths = b.deaths or 0, cls = b.cls }
            end
        end
    end
    local list = {}
    for _, p in pairs(pairsByKey) do table.insert(list, p) end
    table.sort(list, function(x, y) return x.time > y.time end)
    return list
end

---------------------------------------------------------------------------
-- 2. Guild Bounties: three weekly challenges, the same for everyone
---------------------------------------------------------------------------

Fellowship.BOUNTIES = {
    { id = "slay",    key = "kills",       title = "Slay %s enemies",            base = 1500 },
    { id = "quest",   key = "quests",      title = "Complete %s quests",         base = 120 },
    { id = "fish",    key = "fish",        title = "Catch %s fish",              base = 150 },
    { id = "gather",  key = "gathered",    title = "Gather %s herbs, ore and skins", base = 200 },
    { id = "craft",   key = "crafted",     title = "Craft %s items",             base = 150 },
    { id = "critter", key = "critters",    title = "Butcher %s critters",        base = 60 },
    { id = "jump",    key = "jumps",       title = "Jump %s times",              base = 3000 },
    { id = "travel",  key = "travelTotal", title = "Travel %s together",         base = 200000 },
    { id = "gold",    key = "goldLooted",  title = "Loot %s",                    base = 1000000 },
    { id = "boss",    key = "bossKills",   title = "Defeat %s bosses",           base = 20 },
    { id = "duel",    key = "duelsWon",    title = "Win %s duels",               base = 25 },
    { id = "safe",    key = "deaths",      title = "Stay under %s deaths all week", base = 25, under = true },
}

-- Deterministic pick from a week number, so every guild member sees the same list.
-- Park-Miller generator: every product stays below 2^53, so all clients get exactly the same numbers.
local function Seeded(seed, count, n)
    local picked, used, state = {}, {}, (math.floor(seed) % 2147483646) + 1
    while #picked < math.min(count, n) do
        state = (state * 16807) % 2147483647
        local i = (state % n) + 1
        if not used[i] then used[i] = true; table.insert(picked, i) end
    end
    return picked
end

-- Guild members active this week (by player, not character).
function Fellowship:ActivePlayers(weekStart)
    local owners, n = {}, 0
    for _, rec in ipairs(FS:GetScopeCharacters("guild")) do
        if (tonumber(rec.lastUpdate) or 0) >= weekStart and not owners[rec.owner or rec.fullName] then
            owners[rec.owner or rec.fullName] = true
            n = n + 1
        end
    end
    return n
end

function Fellowship.BountyTarget(b, players)
    local mult = (players <= 5 and 1) or (players <= 15 and 3) or (players <= 40 and 8) or 15
    return b.base * mult
end

function Fellowship:FormatBountyAmount(b, value)
    if b.key == "travelTotal" then return W.Distance(value) end
    if b.key == "goldLooted" then return W.Num(math.floor(value / 10000)) .. " gold" end
    return W.Num(value)
end

-- This week's bounties with live progress and top contributors.
function Fellowship:CurrentBounties()
    local weekStart = FS:WeekStart()
    local idx = FS.WeekIndex(weekStart)
    local players = self:ActivePlayers(weekStart)
    local list = {}
    for _, i in ipairs(Seeded(idx, 3, #self.BOUNTIES)) do
        local b = self.BOUNTIES[i]
        local target = self.BountyTarget(b, players)
        local progress, contributors = 0, {}
        for _, rec in ipairs(FS:GetScopeCharacters("guild")) do
            local v = FS:GetValue(rec, b.key, "week")
            if v > 0 then
                progress = progress + v
                table.insert(contributors, { rec = rec, v = v })
            end
        end
        table.sort(contributors, function(x, y) return x.v > y.v end)
        table.insert(list, {
            def = b, id = idx .. ":" .. b.id, week = idx, target = target, progress = progress, contributors = contributors,
            title = string.format(b.title, self:FormatBountyAmount(b, target)),
            done = not b.under and progress >= target, failed = b.under and progress >= target,
        })
    end
    return list, players
end

-- Marks finished bounties (and last week's "stay under" bounty) on the wall.
function Fellowship:CheckBounties()
    if not FS.db then return end
    local wall = FS.db.global.bountyDone
    for _, b in ipairs(self:CurrentBounties()) do
        if b.done and not wall[b.id] then
            local top = b.contributors[1]
            wall[b.id] = { title = b.title, t = time(), top = top and top.rec.fullName, week = b.week }
            FS:AddEvent({ kind = "bounty", who = FS:GetPlayerKey(), a = b.title })
        end
    end
    -- "Stay under" bounties can only be judged once the week is over.
    local lastIdx = FS.WeekIndex(FS:WeekStart()) - 1
    local players = math.max(1, self:ActivePlayers(FS:WeekStart() - 7 * 86400))
    for _, i in ipairs(Seeded(lastIdx, 3, #self.BOUNTIES)) do
        local b = self.BOUNTIES[i]
        local id = lastIdx .. ":" .. b.id
        if b.under and not wall[id] then
            local total, seen = 0, false
            for _, rec in ipairs(FS:GetScopeCharacters("guild")) do
                if rec.lastWk and rec.lastWk.idx == lastIdx then
                    seen = true
                    total = total + (tonumber(rec.lastWk.v and rec.lastWk.v[b.key]) or 0)
                end
            end
            local target = self.BountyTarget(b, players)
            if seen and total < target then
                wall[id] = { title = string.format(b.title, W.Num(target)), t = time(), week = lastIdx }
                FS:AddEvent({ kind = "bounty", who = FS:GetPlayerKey(), a = wall[id].title })
            end
        end
    end
end

---------------------------------------------------------------------------
-- 3. The Book of Deeds: a written history per character
---------------------------------------------------------------------------

function Fellowship:Book(rec)
    local deeds = {}
    local function add(t, text) if (tonumber(t) or 0) > 0 then table.insert(deeds, { t = t, text = text }) end end
    add(rec.firstSeen, "First recorded by FellowshipSync.")
    for key, t in pairs(rec.firsts or {}) do
        local lvl = tonumber(key:match("^lv(%d+)$"))
        local boss = key:match("^boss:(.+)$")
        local prof, rank = key:match("^prof:(.+):(%d+)$")
        local lg = tonumber(key:match("^lg:(%d+)$"))
        if lvl then add(t, "Reached level " .. lvl .. ".")
        elseif boss then add(t, "Defeated " .. W.Color(boss, "ff8000") .. " for the first time.")
        elseif prof then add(t, (tonumber(rank) == FS.ProfMax() and "Became a master of " or "Reached ") .. prof .. " " .. rank .. ".")
        elseif lg then
            local _, name = FS.Tracker.Safe(GetAchievementInfo, lg)
            add(t, "Completed the " .. FS.POINTS.item .. " " .. W.Color(name or ("#" .. lg), "00e6ff") .. ".")
        end
    end
    local deaths = rec.deathLog or {}
    for i, d in ipairs(deaths) do
        local first = i == #deaths
        add(d.t, string.format("%s %s%s.", first and "Fell for the first time (on record) to" or "Was slain by",
            W.Color(d.killer or "something", "ff5555"), (d.zone and d.zone ~= "") and (" in " .. d.zone) or ""))
    end
    for _, ev in ipairs(FS.db.global.events) do
        if ev.who == rec.fullName then
            if ev.kind == "gear" then add(ev.t, "Reached " .. W.Num(ev.v) .. " GearScore.")
            elseif ev.kind == "milestone" then
                add(ev.t, "Passed " .. W.Num(ev.v) .. " " .. ((FS.STATS[ev.a] and FS.STATS[ev.a].label) or tostring(ev.a)):lower() .. ".")
            elseif ev.kind == "record" then add(ev.t, "Set a record: " .. tostring(ev.a) .. " in " .. W.FightTime(ev.v) .. ".") end
        end
    end
    if rec.hc then
        add(rec.hc.t, W.Color(string.format("Fell for good at level %s in %s.", tostring(rec.hc.lvl or "?"), rec.hc.zone or "an unknown place"), "ff5555")
            .. (rec.hc.words and (' Last words: "' .. rec.hc.words .. '"') or ""))
    end
    table.sort(deeds, function(a, b) return a.t < b.t end)
    return deeds
end

function Fellowship:Summary(rec)
    local nemesis, n = nil, 0
    for k, v in pairs(rec.killers or {}) do if v > n then nemesis, n = k, v end end
    local parts = {
        string.format("%s, a level %s %s %s%s.", W.CharName(rec), tostring(rec.level or "?"), rec.race or "", W.ClassName(rec.cls),
            rec.guildName and (" of <" .. rec.guildName .. ">") or ""),
        string.format("Has played %s, slain %s enemies and died %s times%s.", W.Duration(rec.playtime),
            W.Num(rec.kills), W.Num(rec.deaths), nemesis and (" (most often to " .. nemesis .. ")") or ""),
        string.format("Has travelled %s and completed %s quests.", W.Distance(FS:GetValue(rec, "travelTotal", "all")), W.Num(rec.quests)),
    }
    return table.concat(parts, " ")
end

-- Anniversaries: things that happened on this calendar day in earlier years.
function Fellowship:OnThisDay(scope)
    local today, year = date("%m-%d"), tonumber(date("%Y"))
    local out = {}
    for _, rec in ipairs(FS:GetScopeCharacters(scope or "network")) do
        for _, deed in ipairs(self:Book(rec)) do
            local y = tonumber(date("%Y", deed.t))
            if date("%m-%d", deed.t) == today and y and y < year then
                table.insert(out, { rec = rec, years = year - y, text = deed.text, t = deed.t })
            end
        end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

function Fellowship:OnThisDayToast()
    local c = FS.db.char
    local today = date("%Y-%m-%d")
    if c.onThisDayShown == today then return end
    local list = self:OnThisDay("network")
    if #list == 0 then return end
    c.onThisDayShown = today
    local first = list[1]
    if FS.db.profile.notify.own.onthisday ~= false then
        FS.Extras:ShowToast("On This Day", string.format("%d year%s ago today, %s %s", first.years, first.years == 1 and "" or "s",
            W.CharName(first.rec), first.text:sub(1, 1):lower() .. first.text:sub(2)), "Interface\\Icons\\INV_Misc_Book_09", false)
    end
end

---------------------------------------------------------------------------
-- 5. Memory Lane: screenshots of big moments
---------------------------------------------------------------------------

function Fellowship:MemoryKind(ev)
    local m, max = FS.db.profile.memory, FS:MaxLevel()
    if not m.enabled or not ev.mine then return nil end
    if ev.kind == "level" then
        local v = tonumber(ev.v) or 0
        if v == max and m.maxlevel then return "Reached max level" end
        if v % 10 == 0 and m.levels then return "Reached level " .. v end
    elseif ev.kind == "boss" then
        local first = FS.Notify.IsGuildFirst and FS.Notify:IsGuildFirst(ev, "boss:" .. tostring(ev.a))
        if first and m.firsts then return "Guild first: " .. tostring(ev.a) end
        if m.boss then return "First kill: " .. tostring(ev.a) end
    elseif ev.kind == "record" and m.record then return "New record: " .. tostring(ev.a)
    elseif ev.kind == "legacy" and m.legacy then return FS.POINTS.item .. ": " .. FS.Notify.Plain(ev.a)
    elseif ev.kind == "fallen" and m.fallen then return "Fell for good"
    elseif ev.kind == "bounty" and m.bounty then return "Guild bounty: " .. tostring(ev.a) end
end

function Fellowship:OnEvent(ev)
    local what = self:MemoryKind(ev)
    if not what then return end
    if time() - (self.lastShot or 0) < 10 then return end -- never more than one every 10 seconds
    self.lastShot = time()
    local log = FS.db.char.memories
    -- Taken about a second later so the toast is in the picture.
    FS:ScheduleTimer(function()
        if Screenshot then pcall(Screenshot) end
        table.insert(log, 1, { t = time(), what = what, file = date("WoWScrnShot_%m%d%y_%H%M%S") .. ".jpg" })
        for i = #log, 201, -1 do log[i] = nil end
        FS:QueueUIRefresh()
    end, 1.2)
end

---------------------------------------------------------------------------
-- 6. Wagers: pretend "Fellowship Marks" on weekly questions
---------------------------------------------------------------------------

Fellowship.START_MARKS = 1000
Fellowship.WAGERS = {
    { id = "kills",  key = "kills",  q = "Who will slay the most enemies this week?" },
    { id = "deaths", key = "deaths", q = "Who will die the most this week?" },
    { id = "jumps",  key = "jumps",  q = "Who will jump the most this week?" },
    { id = "quests", key = "quests", q = "Who will complete the most quests this week?" },
    { id = "gold",   key = "goldLooted", q = "Who will loot the most gold this week?" },
}

-- The three built-in questions, then custom wagers (stat-based and officer free-text).
function Fellowship:CurrentWagers()
    local idx = FS.WeekIndex(FS:WeekStart())
    local list = {}
    for _, i in ipairs(Seeded(idx + 7919, 3, #self.WAGERS)) do
        local w = self.WAGERS[i]
        table.insert(list, { def = w, id = idx .. ":" .. w.id, week = idx, kind = "builtin" })
    end
    for _, c in ipairs(self:CustomWagers()) do
        local active = (c.kind == "stat" and c.week == idx) or (c.kind == "manual" and (not c.winner or time() - (c.settled or 0) < 3 * 86400))
        if active then
            table.insert(list, { def = { q = c.q, key = c.key }, id = c.id, week = c.week, kind = c.kind, options = c.opts,
                                 creator = c.creator, winner = c.winner })
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Custom wagers
---------------------------------------------------------------------------

Fellowship.WAGER_STATS = { "kills", "deaths", "quests", "jumps", "fish", "critters", "goldLooted", "bossKills", "wipes",
                           "duelsWon", "travelTotal", "emotes", "corpseRuns", "chat", "epics", "areasDiscovered" }

-- Guild leader or officer? For yourself the game says so directly; for others the
-- guild roster decides (rank 0 = guild leader, rank 1 = the first officer rank).
function Fellowship:IsOfficer(charKey)
    if not charKey or charKey == FS:GetPlayerKey() then
        return (IsGuildLeader and IsGuildLeader()) or (CanGuildPromote and CanGuildPromote())
            or (C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer()) or false
    end
    if not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    local short = FS.ShortName(charKey)
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and (name == charKey or FS.ShortName(name) == short) then return (tonumber(rankIndex) or 99) <= 1 end
    end
    return false
end

-- Everyone's custom wagers that are allowed: stat wagers from guild members,
-- free-text wagers only from officers (checked against the roster).
function Fellowship:CustomWagers()
    local out, seen = {}, {}
    local me = FS:GetPlayerKey()
    for _, c in ipairs(FS.db.global.customWagers) do
        c.creator = c.creator or me
        if not seen[c.id] then seen[c.id] = true; table.insert(out, c) end
    end
    for name, rec in pairs(FS.db.global.characters) do
        if not rec.isMyChar and not rec.isMock and rec.customWagers then
            for _, c in ipairs(rec.customWagers) do
                local allowed = (c.kind == "stat" and rec.inGuild) or (c.kind == "manual" and self:IsOfficer(name))
                if allowed and not seen[c.id] then
                    seen[c.id] = true
                    c.creator = name
                    table.insert(out, c)
                end
            end
        end
    end
    return out
end

function Fellowship:CreateStatWager(key)
    local def = FS.STATS[key]
    if not def or not def.weekly then return false, "That statistic can't be used." end
    local idx, mine = FS.WeekIndex(FS:WeekStart()), 0
    for _, c in ipairs(FS.db.global.customWagers) do
        if c.kind == "stat" and c.week == idx then
            mine = mine + 1
            if c.key == key then return false, "You already have a wager on that this week." end
        end
    end
    if mine >= 2 then return false, "You can have at most two stat wagers per week." end
    table.insert(FS.db.global.customWagers, { id = FS:GetPlayerKey() .. ":" .. time() .. ":" .. (#FS.db.global.customWagers + 1), kind = "stat", key = key, week = idx,
        q = "Who will have the most " .. def.label:lower() .. " this week?", created = time() })
    self:PruneCustom()
    return true
end

function Fellowship:CreateManualWager(question, optionsText)
    if not self:IsOfficer() then return false, "Only the guild leader and officers can create free-text wagers." end
    question = strtrim(tostring(question or "")):sub(1, 100)
    if question == "" then return false, "Write a question first." end
    local opts = {}
    for part in tostring(optionsText or ""):gmatch("[^,]+") do
        part = strtrim(part):sub(1, 40)
        if part ~= "" and #opts < 8 then table.insert(opts, part) end
    end
    if #opts < 2 then return false, "Give at least two options, separated by commas." end
    table.insert(FS.db.global.customWagers, { id = FS:GetPlayerKey() .. ":" .. time() .. ":" .. (#FS.db.global.customWagers + 1), kind = "manual", q = question, opts = opts,
        week = FS.WeekIndex(FS:WeekStart()), created = time() })
    self:PruneCustom()
    return true
end

-- The creator of a free-text wager picks the winning option.
function Fellowship:DeclareWinner(id, option)
    for _, c in ipairs(FS.db.global.customWagers) do
        if c.id == id and c.kind == "manual" and not c.winner then
            for _, o in ipairs(c.opts) do
                if o == option then
                    c.winner, c.settled = option, time()
                    self:SettleWagers()
                    return true
                end
            end
        end
    end
    return false
end

function Fellowship:PruneCustom()
    local list = FS.db.global.customWagers
    for i = #list, 1, -1 do
        if time() - (list[i].created or 0) > 21 * 86400 then table.remove(list, i) end
    end
end

-- Every known bet: { owner, w, pick, amt, t }, one per player and wager.
function Fellowship:AllBets()
    local seen, out = {}, {}
    local function addFrom(owner, bets)
        for _, b in ipairs(bets or {}) do
            local id = tostring(owner) .. "|" .. tostring(b.w)
            if type(b.w) == "string" and type(b.pick) == "string" and tonumber(b.amt) and not seen[id] then
                seen[id] = true
                table.insert(out, { owner = owner, w = b.w, pick = b.pick, amt = tonumber(b.amt), t = b.t })
            end
        end
    end
    addFrom(FS.Tracker:AccountLabel(), FS.db.global.bets)
    for _, rec in pairs(FS.db.global.characters) do
        if not rec.isMyChar and not rec.isMock then addFrom(rec.owner, rec.bets) end
    end
    return out
end

function Fellowship:BetsOn(wagerId)
    local out = {}
    for _, b in ipairs(self:AllBets()) do if b.w == wagerId then table.insert(out, b) end end
    return out
end

function Fellowship:MyBet(wagerId)
    for _, b in ipairs(FS.db.global.bets) do if b.w == wagerId then return b end end
end

function Fellowship:BetsOpen()
    local week = FS.db.char.week
    return time() < (tonumber(week.resetAt) or 0) - 86400 -- closes a day before the reset
end

function Fellowship:Balance(owner)
    local balance = self.START_MARKS
    for _, b in ipairs(self:AllBets()) do
        if b.owner == owner then
            balance = balance - b.amt + (self:Payout(b) or 0)
        end
    end
    return balance
end

function Fellowship:PlaceBet(wagerId, pick, amount)
    if not self:BetsOpen() then return false, "Betting for this week is closed." end
    if self:MyBet(wagerId) then return false, "You already bet on this question." end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "Bet at least 1 mark." end
    if amount > self:Balance(FS.Tracker:AccountLabel()) then return false, "Not enough Fellowship Marks." end
    table.insert(FS.db.global.bets, { w = wagerId, pick = pick, amt = amount, t = time() })
    for i = #FS.db.global.bets, 61, -1 do table.remove(FS.db.global.bets, 1) end
    return true
end

-- Settles last week's wagers from everyone's final numbers (a day into the new week,
-- so most guildmates have synced by then). The pot is split among the winners.
function Fellowship:SettleWagers()
    if not FS.db then return end
    local results = FS.db.global.wagerResults
    -- Free-text wagers are settled as soon as their creator declares the winner.
    for _, c in ipairs(self:CustomWagers()) do
        if c.kind == "manual" and c.winner and not results[c.id] then
            results[c.id] = { winner = c.winner, at = time() }
            self:NoteMyResult(c.id, c.q)
        end
    end
    local weekStart = FS:WeekStart()
    if time() - weekStart < 86400 then return end
    local lastIdx = FS.WeekIndex(weekStart) - 1
    local due = {}
    for _, i in ipairs(Seeded(lastIdx + 7919, 3, #self.WAGERS)) do
        local w = self.WAGERS[i]
        table.insert(due, { w = w, id = lastIdx .. ":" .. w.id })
    end
    for _, c in ipairs(self:CustomWagers()) do
        if c.kind == "stat" and c.week == lastIdx then table.insert(due, { w = { key = c.key, q = c.q }, id = c.id }) end
    end
    for _, item in ipairs(due) do
        local w, id = item.w, item.id
        if not results[id] then
            local best, bestV
            for _, rec in ipairs(FS:GetScopeCharacters("guild")) do
                local v = rec.lastWk and rec.lastWk.idx == lastIdx and tonumber(rec.lastWk.v and rec.lastWk.v[w.key])
                if v and (not bestV or v > bestV or (v == bestV and rec.fullName < best)) then best, bestV = rec.fullName, v end
            end
            if best then
                results[id] = { winner = best, value = bestV, at = time() }
                self:NoteMyResult(id, w.q)
            end
        end
    end
end

-- Toast for the player's own bet on a wager that was just settled.
function Fellowship:NoteMyResult(id, question)
    local mine = self:MyBet(id)
    if not mine then return end
    local won = self:Payout({ w = id, pick = mine.pick, amt = mine.amt, owner = FS.Tracker:AccountLabel() }) or 0
    FS:AddEvent({ kind = "wager", who = FS:GetPlayerKey(), a = question, v = won - mine.amt })
end

-- Marks returned for one bet (nil while unsettled). No winners: everyone gets their stake back.
function Fellowship:Payout(bet)
    local result = FS.db.global.wagerResults[bet.w]
    if not result then return nil end
    local pool, winners = 0, 0
    for _, b in ipairs(self:BetsOn(bet.w)) do
        pool = pool + b.amt
        if b.pick == result.winner then winners = winners + b.amt end
    end
    if winners == 0 then return bet.amt end
    if bet.pick ~= result.winner then return 0 end
    return math.floor(pool * bet.amt / winners)
end

---------------------------------------------------------------------------
-- 7. Rivalries
---------------------------------------------------------------------------

Fellowship.RIVAL_STATS = { "gs", "kills", "deaths", "damage", "healing", "quests", "jumps", "goldLooted", "bossKills",
                           "duelsWon", "critters", "fish", "travelTotal", "playtime" }

function Fellowship:SetRival(key)
    FS.db.char.rival = key
    FS.Tracker:Snapshot()
end

-- Rows { key, mine, theirs, leader } and the tally (you, rival).
function Fellowship:Scorecard(me, rival)
    local rows, a, b = {}, 0, 0
    for _, key in ipairs(self.RIVAL_STATS) do
        local x, y = FS:GetValue(me, key), FS:GetValue(rival, key)
        local lower = FS.STATS[key] and FS.STATS[key].lower
        local leader = (x == y) and 0 or (((x > y) ~= (lower == true)) and 1 or 2)
        if leader == 1 then a = a + 1 elseif leader == 2 then b = b + 1 end
        table.insert(rows, { key = key, mine = x, theirs = y, leader = leader })
    end
    return rows, a, b
end

-- Someone just named one of your characters as their rival.
function Fellowship:CheckNamedRival(rec, previous)
    if rec.rival and rec.rival ~= previous then
        local target = FS.db.global.characters[rec.rival]
        if target and target.isMyChar and not target.isMock then
            FS:AddEvent({ kind = "rival", who = rec.fullName, a = rec.rival, t = time() }, true)
        end
    end
end
