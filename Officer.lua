local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Officer = FS.Officer
local IsSecret = FS.IsSecret

---------------------------------------------------------------------------
-- Guild tools for officers: notices, polls, events, awards, goals, seasons,
-- attendance and guild bank donations. Everything travels with the normal sync.
-- Trust: each member's addon checks the SENDER's rank in its own guild roster;
-- only officer ranks (chosen by the guild leader) may create or change things.
---------------------------------------------------------------------------

local MAX_TEXT = 240
local TYPES = { notice = true, poll = true, event = true, award = true, goal = true, season = true, raid = true, bank = true, ranks = true }

local function Str(v, max) if type(v) ~= "string" or IsSecret(v) then return nil end return v:sub(1, max or MAX_TEXT) end
local function Num(v) v = tonumber(v); if not v or v ~= v or v == math.huge or v == -math.huge then return nil end return v end
function Officer.Norm(name) return (tostring(name or ""):gsub("%s", ""):lower()) end
local Norm = Officer.Norm

function Officer:Enable()
    LibStub("AceEvent-3.0"):Embed(self)
    for _, ev in ipairs({ "GUILD_ROSTER_UPDATE", "ENCOUNTER_END", "GUILDBANKFRAME_OPENED", "GUILDBANKLOG_UPDATE" }) do
        FS.SafeRegister(self, ev)
    end
    self.counter = 0
    FS:ScheduleTimer(function() self:RequestRoster() end, 5)
    FS:ScheduleRepeatingTimer(function() self:RequestRoster(); self:Tick() end, 60)
end

---------------------------------------------------------------------------
-- Guild, roster and ranks
---------------------------------------------------------------------------

function Officer:GuildName()
    if not IsInGuild() then return nil end
    local g = GetGuildInfo("player")
    if type(g) == "string" and not IsSecret(g) and g ~= "" then return g end
end

function Officer:Store()
    local g = self:GuildName()
    if not g then return nil end
    local all = FS.db.global.guildData
    all[g] = all[g] or {}
    local s = all[g]
    s.objects, s.responses, s.raids, s.bank = s.objects or {}, s.responses or {}, s.raids or {}, s.bank or { seen = {}, totals = {} }
    s.seasonBase = s.seasonBase or {}
    return s
end

function Officer:RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
    self:RefreshRoster()
end

function Officer:GUILD_ROSTER_UPDATE() self:RefreshRoster() end

function Officer:RefreshRoster()
    local roster, byName = {}, {}
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, rankName, rankIndex, level, _, zone, note, _, online, _, class = GetGuildRosterInfo(i)
        if type(name) == "string" and not IsSecret(name) then
            local days = 0
            if not online and GetGuildRosterLastOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                days = (tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30 + (tonumber(d) or 0) + (tonumber(h) or 0) / 24
            end
            local e = { name = name, rank = rankName, rankIndex = tonumber(rankIndex) or 99, level = tonumber(level),
                        zone = zone, note = note, online = online and true or false, class = class, daysOff = days }
            table.insert(roster, e)
            byName[Norm(name)] = e
            local short = Norm(name:match("^[^%-]+"))
            byName[short] = byName[short] or e
        end
    end
    self.roster, self.byName = roster, byName
end

function Officer:Member(name)
    if not self.byName then self:RefreshRoster() end
    local n = Norm(name)
    return self.byName[n] or self.byName[Norm(tostring(name):match("^[^%-]+"))]
end

-- Officer ranks (rank 0 = guild leader, always). Default: ranks 0 and 1.
function Officer:OfficerRanks()
    local s = self:Store()
    local obj = s and s.objects.ranks
    local set = { [0] = true }
    for _, r in ipairs((obj and obj.ranks) or { 1 }) do set[tonumber(r) or -1] = true end
    return set
end

function Officer:MyRankIndex()
    local _, _, idx = GetGuildInfo("player")
    return tonumber(idx)
end
function Officer:IsLeader() return self:MyRankIndex() == 0 end
function Officer:AmIOfficer()
    local idx = self:MyRankIndex()
    return idx ~= nil and self:OfficerRanks()[idx] == true
end
function Officer:IsOfficerName(name)
    local m = self:Member(name)
    return m ~= nil and self:OfficerRanks()[m.rankIndex] == true
end
function Officer:IsLeaderName(name)
    local m = self:Member(name)
    return m ~= nil and m.rankIndex == 0
end

---------------------------------------------------------------------------
-- Creating and changing things (officers only)
---------------------------------------------------------------------------

function Officer:Visible(type_)
    local s, out = self:Store(), {}
    if not s then return out end
    for id, o in pairs(s.objects) do
        if o.type == type_ and not o.removed then o.id = id; table.insert(out, o) end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

function Officer:Create(type_, fields)
    local s = self:Store()
    if not s then return nil, "You are not in a guild." end
    if type_ == "ranks" then
        if not self:IsLeader() then return nil, "Only the guild leader can choose officer ranks." end
    elseif not self:AmIOfficer() then
        return nil, "Only officers can do this."
    end
    self.counter = (self.counter or 0) + 1
    local id = (type_ == "ranks") and "ranks" or (FS:GetPlayerKey() .. ":" .. type_ .. ":" .. time() .. ":" .. self.counter)
    local o = { type = type_, author = FS:GetPlayerKey(), by = FS:GetPlayerKey(), t = time(), u = time() }
    for k, v in pairs(fields or {}) do o[k] = v end
    s.objects[id] = o
    self:Changed()
    return id
end

function Officer:Update(id, fields)
    local s = self:Store()
    local o = s and s.objects[id]
    if not o then return false end
    if not self:AmIOfficer() then return false, "Only officers can do this." end
    for k, v in pairs(fields) do o[k] = v end
    o.u, o.by = math.max(time(), (o.u or 0) + 1), FS:GetPlayerKey()
    self:Changed()
    return true
end

function Officer:Remove(id) return self:Update(id, { removed = true }) end

-- Sends changes soon, so guildmates see them within seconds.
function Officer:Changed()
    FS:QueueUIRefresh()
    if self.sendTimer then return end
    self.sendTimer = FS:ScheduleTimer(function() self.sendTimer = nil; FS.Comm:BroadcastStats(false) end, 3)
end

---------------------------------------------------------------------------
-- Member responses: notice read, poll vote, event RSVP
---------------------------------------------------------------------------

function Officer:Respond(id, value)
    local s = self:Store()
    if not s then return end
    s.responses[id] = s.responses[id] or {}
    s.responses[id][FS:GetPlayerKey()] = value
    self:Changed()
end

function Officer:Responses(id)
    local s = self:Store()
    return (s and s.responses[id]) or {}
end

function Officer:MyResponse(id) return self:Responses(id)[FS:GetPlayerKey()] end

function Officer:UnreadNotices()
    local n = 0
    for _, o in ipairs(self:Visible("notice")) do if not self:MyResponse(o.id) then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- Sync: what goes into our packet, and reading guildmates' packets
---------------------------------------------------------------------------

local FIELDS = { "type", "author", "by", "t", "u", "removed", "text", "q", "options", "closes", "title", "when", "note",
                 "to", "kind", "key", "target", "progress", "finish", "start", "keys", "final", "date", "names", "totals", "ranks" }

function Officer:BuildPayload()
    local s = self:Store()
    if not s then return nil end
    local me = FS:GetPlayerKey()
    local objects, raids = {}, {}
    for id, o in pairs(s.objects) do
        if o.by == me or (o.by == nil and o.author == me) then
            local copy = { id = id }
            for _, f in ipairs(FIELDS) do copy[f] = o[f] end
            if o.type == "raid" then table.insert(raids, copy) else table.insert(objects, copy) end
        end
    end
    table.sort(objects, function(a, b) return (a.u or 0) > (b.u or 0) end)
    table.sort(raids, function(a, b) return tostring(a.date) > tostring(b.date) end)
    for i = #objects, 41, -1 do objects[i] = nil end
    for i = #raids, 31, -1 do raids[i] = nil end
    for _, r in ipairs(raids) do table.insert(objects, r) end
    local responses = {}
    for id, map in pairs(s.responses) do
        if map[me] ~= nil and #responses < 60 then table.insert(responses, { id, map[me] }) end
    end
    return { g = self:GuildName(), o = objects, r = responses }
end

local function CleanList(v, maxItems, maxLen)
    if type(v) ~= "table" then return nil end
    local out = {}
    for i = 1, math.min(#v, maxItems) do
        local x = Str(v[i], maxLen) or Num(v[i])
        if x ~= nil then table.insert(out, x) end
    end
    return out
end

local function CleanObject(raw)
    if type(raw) ~= "table" or not TYPES[raw.type] or not Str(raw.id, 120) then return nil end
    local o = {
        type = raw.type, author = Str(raw.author, 80), by = Str(raw.by, 80), t = Num(raw.t), u = Num(raw.u),
        removed = raw.removed == true or nil, text = Str(raw.text), q = Str(raw.q, 160), title = Str(raw.title, 80),
        note = Str(raw.note, 160), to = Str(raw.to, 80), kind = Str(raw.kind, 10), key = Str(raw.key, 30),
        when = Num(raw.when), closes = Num(raw.closes), target = Num(raw.target), progress = Num(raw.progress),
        finish = Num(raw.finish), start = Num(raw.start), date = Str(raw.date, 12),
        options = CleanList(raw.options, 8, 40), keys = CleanList(raw.keys, 3, 30), names = CleanList(raw.names, 80, 80),
        ranks = CleanList(raw.ranks, 10, 3),
    }
    if type(raw.totals) == "table" then
        o.totals = {}
        local n = 0
        for name, amount in pairs(raw.totals) do
            if n >= 200 then break end
            if Str(name, 80) and Num(amount) then o.totals[Str(name, 80)] = Num(amount); n = n + 1 end
        end
    end
    if type(raw.final) == "table" then
        o.final = {}
        for key, w in pairs(raw.final) do
            if Str(key, 30) and type(w) == "table" and Str(w.winner, 80) then
                o.final[Str(key, 30)] = { winner = Str(w.winner, 80), value = Num(w.value) or 0 }
            end
        end
    end
    if not o.t or not o.u then return nil end
    return o, Str(raw.id, 120)
end

-- Called by Comm for every guildmate's packet (sender = the character that sent it).
function Officer:Ingest(payload, sender)
    if type(payload) ~= "table" then return end
    local s = self:Store()
    if not s or Str(payload.g, 64) ~= self:GuildName() then return end
    local senderIsOfficer = self:IsOfficerName(sender)
    for i = 1, math.min(type(payload.o) == "table" and #payload.o or 0, 80) do
        local o, id = CleanObject(payload.o[i])
        local allowed = o and ((o.type == "ranks" and self:IsLeaderName(sender)) or (o.type ~= "ranks" and senderIsOfficer))
        if allowed then
            o.by = sender
            local old = s.objects[id]
            if not old or (o.u or 0) > (old.u or 0) then
                local isNew = old == nil
                s.objects[id] = o
                if isNew and not o.removed then self:Announce(o) end
            end
        end
    end
    for i = 1, math.min(type(payload.r) == "table" and #payload.r or 0, 80) do
        local e = payload.r[i]
        local id, value = type(e) == "table" and Str(e[1], 120), type(e) == "table" and (Str(e[2], 20) or Num(e[2]) or (e[2] == true or nil))
        if id and value ~= nil then
            s.responses[id] = s.responses[id] or {}
            s.responses[id][sender] = value
        end
    end
    FS:QueueUIRefresh()
end

-- New things from officers pop up as toasts (if wanted).
function Officer:Announce(o)
    local g = FS.db.profile.notify.guild
    if not FS.db.profile.notify.toasts or time() - (o.t or 0) > 3 * 86400 then return end
    local who = FS.ShortName(o.author or "")
    if o.type == "notice" and g.notices ~= false then
        FS.Extras:ShowToast("Guild Notice", (o.text or "") .. FS.W.Color("  - " .. who, "888888"), "Interface\\Icons\\INV_Letter_15", true, { kind = "notice" })
    elseif o.type == "poll" and g.notices ~= false then
        FS.Extras:ShowToast("New Guild Poll", tostring(o.q) .. "  (vote in the Guild tab)", "Interface\\Icons\\INV_Misc_Note_05", true, { kind = "poll" })
    elseif o.type == "event" and g.events ~= false then
        FS.Extras:ShowToast("New Guild Event", string.format("%s - %s", tostring(o.title), date("%a %d.%m %H:%M", o.when or 0)),
            "Interface\\Icons\\INV_Misc_PocketWatch_02", true, { kind = "event" })
    elseif o.type == "award" and FS.db.global.characters[o.to or ""] and FS.db.global.characters[o.to].isMyChar then
        FS.Extras:ShowToast("You Received an Award!", tostring(o.title) .. FS.W.Color("  from " .. who, "888888"),
            "Interface\\Icons\\Achievement_Guildperk_Honorablemention", false)
    end
end

---------------------------------------------------------------------------
-- Automatic: attendance, guild bank, reminders, seasons
---------------------------------------------------------------------------

-- Every boss attempt in a raid group records which guild members were there.
function Officer:ENCOUNTER_END()
    local s = self:Store()
    if not s or not IsInRaid or not IsInRaid() then return end
    local day = date("%Y-%m-%d")
    local names = s.raids[day] or {}
    names[FS:GetPlayerKey()] = true
    for i = 1, (GetNumGroupMembers() or 0) do
        local unit = "raid" .. i
        if UnitExists(unit) and (not UnitIsInMyGuild or UnitIsInMyGuild(unit)) then
            local key = FS.Fellowship:MemberKey(unit)
            if key then names[key] = true end
        end
    end
    s.raids[day] = names
    if self:AmIOfficer() then
        local list = {}
        for k in pairs(names) do table.insert(list, k) end
        local id = "raid:" .. day .. ":" .. FS:GetPlayerKey()
        local o = s.objects[id] or { type = "raid", author = FS:GetPlayerKey(), t = time(), date = day }
        o.names, o.u, o.by = list, time(), FS:GetPlayerKey()
        s.objects[id] = o
    end
end

-- Attendance over the last `days` days: raid nights and each member's share.
function Officer:Attendance(days)
    local s = self:Store()
    if not s then return {}, 0 end
    local cutoff = date("%Y-%m-%d", time() - (days or 30) * 86400)
    local nights = {}
    for day, names in pairs(s.raids) do if day >= cutoff then nights[day] = nights[day] or {}; for k in pairs(names) do nights[day][Norm(k)] = k end end end
    for _, o in pairs(s.objects) do
        if o.type == "raid" and not o.removed and o.date and o.date >= cutoff then
            nights[o.date] = nights[o.date] or {}
            for _, k in ipairs(o.names or {}) do nights[o.date][Norm(k)] = k end
        end
    end
    local total, members = 0, {}
    for day, names in pairs(nights) do
        total = total + 1
        for n, display in pairs(names) do
            local m = members[n] or { name = display, nights = 0, last = "" }
            m.nights = m.nights + 1
            if day > m.last then m.last = day end
            members[n] = m
        end
    end
    local list = {}
    for _, m in pairs(members) do m.share = total > 0 and m.nights / total or 0; table.insert(list, m) end
    table.sort(list, function(a, b) if a.nights == b.nights then return a.name < b.name end return a.nights > b.nights end)
    return list, total
end

-- Guild bank money log: deposits per member (whenever you open the guild bank).
function Officer:GUILDBANKFRAME_OPENED()
    if QueryGuildBankLog then pcall(QueryGuildBankLog, (MAX_GUILDBANK_TABS or 8) + 1) end
end

function Officer:GUILDBANKLOG_UPDATE()
    local s = self:Store()
    if not s or not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then return end
    local bank, changed = s.bank, false
    for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
        local kind, name, amount, y, m, d, h = GetGuildBankMoneyTransaction(i)
        if kind == "deposit" and type(name) == "string" and tonumber(amount) then
            local ago = ((((tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30 + (tonumber(d) or 0)) * 24) + (tonumber(h) or 0)) * 3600
            local key = name .. ":" .. amount .. ":" .. math.floor((time() - ago) / 7200)
            if not bank.seen[key] then
                bank.seen[key] = time()
                bank.totals[name] = (bank.totals[name] or 0) + amount
                changed = true
            end
        end
    end
    bank.since = bank.since or time()
    if changed and self:AmIOfficer() then
        local id = "bank:" .. FS:GetPlayerKey()
        local o = s.objects[id] or { type = "bank", author = FS:GetPlayerKey(), t = time() }
        o.totals, o.u, o.by = bank.totals, time(), FS:GetPlayerKey()
        s.objects[id] = o
        self:Changed()
    end
end

-- Donations: the biggest total seen per member (own log and officers' logs).
function Officer:Donations()
    local s = self:Store()
    local best = {}
    if not s then return {} end
    local function merge(t) for name, v in pairs(t or {}) do if (best[name] or 0) < v then best[name] = v end end end
    merge(s.bank.totals)
    for _, o in pairs(s.objects) do if o.type == "bank" and not o.removed then merge(o.totals) end end
    local list = {}
    for name, v in pairs(best) do table.insert(list, { name = name, amount = v }) end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    return list
end

-- Goal progress: stat goals count this week's numbers for the whole guild.
function Officer:GoalProgress(o)
    if o.kind ~= "stat" then return tonumber(o.progress) or 0 end
    local sum = 0
    for _, rec in ipairs(FS:GetScopeCharacters("guild")) do sum = sum + FS:GetValue(rec, o.key, "week") end
    return sum
end

-- Seasons: everyone keeps their own starting numbers and shares their progress.
function Officer:SeasonProgress(rec)
    local s = self:Store()
    if not s then return {} end
    local out = {}
    for _, o in ipairs(self:Visible("season")) do
        if (o.start or 0) <= time() then
            local bkey = o.id .. "|" .. tostring(rec.fullName) -- per character
            local base = s.seasonBase[bkey]
            if not base then
                base = {}
                for _, k in ipairs(o.keys or {}) do base[k] = FS:GetValue(rec, k, "all") end
                s.seasonBase[bkey] = base
            end
            local p = {}
            if time() <= (o.finish or 0) then
                for _, k in ipairs(o.keys or {}) do p[k] = math.max(0, FS:GetValue(rec, k, "all") - (base[k] or 0)) end
                s.seasonLast = s.seasonLast or {}
                s.seasonLast[bkey] = p
            else
                p = (s.seasonLast and s.seasonLast[bkey]) or {}
            end
            out[o.id] = p
        end
    end
    return out
end

function Officer:Standings(o, key)
    local list = {}
    for _, rec in ipairs(FS:GetScopeCharacters("guild")) do
        local v = rec.seasons and rec.seasons[o.id] and tonumber(rec.seasons[o.id][key])
        if v and v > 0 then table.insert(list, { rec = rec, v = v }) end
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    return list
end

-- Once a minute: event reminders and closing finished seasons.
function Officer:Tick()
    local s = self:Store()
    if not s then return end
    s.reminded = s.reminded or {}
    for _, o in ipairs(self:Visible("event")) do
        local left = (o.when or 0) - time()
        if left > 0 and left <= 15 * 60 and not s.reminded[o.id] and self:MyResponse(o.id) ~= "no" then
            s.reminded[o.id] = true
            if FS.db.profile.notify.guild.events ~= false then
                FS.Extras:ShowToast("Starting Soon", string.format("%s starts in %d minutes!", tostring(o.title), math.ceil(left / 60)),
                    "Interface\\Icons\\INV_Misc_PocketWatch_02", true)
            end
        end
    end
    if self:AmIOfficer() then
        for _, o in ipairs(self:Visible("season")) do
            if (o.finish or 0) < time() and not o.final then
                local final = {}
                for _, k in ipairs(o.keys or {}) do
                    local top = self:Standings(o, k)[1]
                    if top then final[k] = { winner = top.rec.fullName, value = top.v } end
                end
                self:Update(o.id, { final = final })
            end
        end
    end
end

function Officer:AwardsFor(charKey)
    local out = {}
    for _, o in ipairs(self:Visible("award")) do if o.to == charKey then table.insert(out, o) end end
    return out
end
