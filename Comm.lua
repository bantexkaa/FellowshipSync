local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Comm = FS.Comm
local L = addonTable.L or {}
local IsSecret = FS.IsSecret

---------------------------------------------------------------------------
-- How data travels
--  * GUILD:  AceComm over the guild addon channel (one faction, connected realms).
--  * BNET:   Battle.net game data to online friends in the same WoW version.
--            Works across factions and realms. Friends only get full stats after
--            they answer a small "hello", so friends without the addon aren't spammed.
--  * BRIDGE: a guild member who receives a friend's stats passes them into the
--            guild once (hop limit 1). Others hold back if they see a copy arrive.
--  * PASSWORD (optional): friends must prove they know your Battle.net password
--            (challenge/response with SHA-256, the password is never sent) before
--            they receive anything. Protected stats are never bridged onwards.
-- Every packet carries the record time + a sequence number, so the same update
-- arriving by several routes is only applied once.
---------------------------------------------------------------------------

local PREFIX = FS.COMM_PREFIX
local PROTOCOL = 5
local MAX_STRING = 300
local MAX_MOBS = 3000
local MAX_FIRSTS = 400
local FULL_LIST_COOLDOWN = 300
local BN_CHUNK = 3800         -- Battle.net game data is limited to ~4 KB per message
local BN_PEER_WINDOW = 7200   -- a friend who answered within 2 h gets full stats
local SESSION = math.random(1, 65535)
local STRETCH_ROUNDS = 500     -- slows down password guessing; computed once per session
local HANDSHAKE_COOLDOWN = 30  -- seconds between answering the same friend's hello

local GROUPS = {
    always           = { "cls", "race", "faction", "ruleset", "level", "gs", "ilvl", "ilvlBag", "legacy", "legacyMax",
                         "quests", "epics", "guildName" },
    shareCombat      = { "kills", "deaths", "damage", "healing", "crit", "duelsWon", "duelsLost", "fallDeaths", "bossKills", "wipes",
                         "combatTime", "fights", "spiritHealer", "rezzed", "closeCalls", "pvpKills", "honorKills", "bgPlayed", "bgWon",
                         "longestLife" },
    shareJourney     = { "travelFoot", "travelMount", "travelFlight", "flightTime", "flightRides", "travelSwim", "corpseRuns", "travelFootLate", "travelMountLate",
                         "corpseDistance", "hearths", "flightPathsFound", "areasDiscovered", "instanceRuns" },
    shareWealth      = { "wealth", "goldLooted", "repairs", "moneyIn", "moneyOut", "goldQuests", "vendorSales", "vendorSpent", "biggestLoot" },
    shareSilly       = { "critters", "jumps", "chat", "afk", "fish", "rollsWon", "rollsTotal", "rolls100", "rolls1", "fallDamage",
                         "lootQ0", "lootQ1", "lootQ2", "lootQ3", "lootQ5", "potions", "foodDrink", "bandages", "questsAbandoned",
                         "embarrassingDeaths", "leapsOfFaith", "hearthRegret", "revengeKills", "highestFall", "biggestRepair",
                         "needRolls", "greedRolls", "passRolls", "wonNeed", "wonGreed" },
    sharePlaytime    = { "restedLevels", "playtime", "playtimeLevel", "rested", "sessions", "reloads", "nightTime", "morningTime", "daysPlayed",
                         "bestStreak", "longestSession" },
    shareSocial      = { "whispersSent", "whispersReceived", "emotes", "trades", "mailsSent", "companions" },
    shareLocation    = { "zone", "hearth" },
    shareProfessions = { "gathered", "crafted" },
}
local STRING_FIELDS = { cls = true, race = true, faction = true, ruleset = true, zone = true, hearth = true, guildName = true }
local VALID_FACTIONS = { Alliance = true, Horde = true, Neutral = true }
local EVENT_KINDS = { death = true, gear = true, legacy = true, level = true, prof = true, milestone = true, boss = true, fallen = true, record = true }

local FIELD_GROUP, ALL_FIELDS = {}, {}
for group, fields in pairs(GROUPS) do
    for _, f in ipairs(fields) do FIELD_GROUP[f] = group; table.insert(ALL_FIELDS, f) end
end
local VALID_SLOTS = {}
for _, s in ipairs(FS.GEAR_SLOTS) do VALID_SLOTS[s] = true end

Comm.seen, Comm.relayed, Comm.bnetPeers, Comm.helloSent = {}, {}, {}, {}
Comm.chunks, Comm.queue, Comm.seq, Comm.msgId = {}, {}, 0, 0
Comm.verified, Comm.helloNonce, Comm.ackNonce, Comm.lastHandshake = {}, {}, {}, {}

local function Str(v, max)
    if type(v) ~= "string" or IsSecret(v) then return nil end
    return v:sub(1, max or MAX_STRING)
end
local function Num(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function KeyHash(s)
    s = tostring(s or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function Encode(tbl)
    local AceSerializer = LibStub("AceSerializer-3.0", true)
    if not AceSerializer then return nil end
    local serialized = AceSerializer:Serialize(tbl)
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(serialized)
        if compressed then return "D:" .. LibDeflate:EncodeForWoWAddonChannel(compressed) end
    end
    return "S:" .. serialized
end

local function Decode(message)
    local tag, body = message:sub(1, 2), message:sub(3)
    if tag == "D:" then
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate then return nil end
        local decoded = LibDeflate:DecodeForWoWAddonChannel(body)
        body = decoded and LibDeflate:DecompressDeflate(decoded)
        if not body then return nil end
    elseif tag ~= "S:" then
        return nil
    end
    local AceSerializer = LibStub("AceSerializer-3.0", true)
    if not AceSerializer then return nil end
    local ok, payload = AceSerializer:Deserialize(body)
    if ok and type(payload) == "table" then return payload end
end

local function TopCounts(map, n, extra)
    local list = {}
    for k, v in pairs(map or {}) do table.insert(list, { k, v, extra and extra[k] or nil }) end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

---------------------------------------------------------------------------
-- Building packets
---------------------------------------------------------------------------

function Comm:BuildPacket(rec, full, isAlt)
    local profile = FS.db.profile
    local privacy = profile.privacy or {}
    local data, week = {}, {}
    for _, f in ipairs(ALL_FIELDS) do
        local group = FIELD_GROUP[f]
        if (group == "always" or privacy[group] ~= false) and rec[f] ~= nil then
            if STRING_FIELDS[f] then data[f] = tostring(rec[f]) else data[f] = math.floor(tonumber(rec[f]) or 0) end
            if rec.wk and rec.wk[f] then week[f] = math.floor(rec.wk[f]) end
        end
    end

    local packet = {
        v = PROTOCOL, k = KeyHash(FS.db.global.networkKey),
        n = rec.fullName, o = rec.owner, d = data, wk = week, lg = rec.legacyEarned, gm = FS.GAME, ver = FS.VERSION,
        ts = rec.lastUpdate, sq = self.seq, h = 0, nr = (profile.allowRelay == false or self:Protected()) or nil,
    }

    if profile.shareGear ~= false then
        if type(rec.gear) == "table" then
            packet.g = {}
            for slot, item in pairs(rec.gear) do packet.g[slot] = { item.name, item.ilvl, item.quality, item.icon } end
        end
        if rec.highest then packet.hi = { rec.highest.link, rec.highest.ilvl, rec.highest.quality } end
    end
    if privacy.shareProfessions ~= false and rec.profs then
        packet.p = {}
        for _, p in ipairs(rec.profs) do table.insert(packet.p, { p.name, p.rank, p.max, p.kind, p.tier }) end
    end

    -- Firsts (dated achievements). Boss firsts count as combat data.
    packet.fs = {}
    local n = 0
    for key, t in pairs(rec.firsts or {}) do
        if n < MAX_FIRSTS and (privacy.shareCombat ~= false or not key:find("^boss:")) then
            packet.fs[key] = t; n = n + 1
        end
    end

    if privacy.shareCombat ~= false then
        packet.dl = {}
        for i = 1, math.min(5, #(rec.deathLog or {})) do
            local e = rec.deathLog[i]
            local where = privacy.shareLocation ~= false
            table.insert(packet.dl, {
                e.t, where and e.zone or "", e.killer, e.kdesc, e.lvl,
                privacy.shareLastWords ~= false and e.words or nil,
                where and e.map or nil, where and e.x or nil, where and e.y or nil,
            })
        end
        if rec.hc then
            local h = rec.hc
            local where = privacy.shareLocation ~= false
            packet.hc = { h.t, where and h.zone or "", h.killer, h.kdesc, h.lvl,
                          privacy.shareLastWords ~= false and h.words or nil, h.played,
                          where and h.map or nil, where and h.x or nil, where and h.y or nil }
        end
        packet.kc = TopCounts(rec.killers, 5)
        -- Kill list: only enemies whose count changed since the last send (as totals,
        -- so a repeated message can't double count); the full list on request.
        if full then
            packet.mf = TopCounts(rec.mobs, MAX_MOBS, rec.mobFirst)
        elseif isAlt then
            -- Alts only send their kill list in full (the "changed since last time" bookkeeping
            -- belongs to the character you are playing).
        else
            local sent = FS.db.char.mobsSent
            packet.md = {}
            for name, count in pairs(rec.mobs or {}) do
                if sent[name] ~= count then table.insert(packet.md, { name, count, rec.mobFirst and rec.mobFirst[name] }) end
            end
        end
    end
    if self.requestFullLists then packet.rq = true end
    packet.fsn = rec.firstSeen
    -- Habits: favourite zones, the play-time clock, personal bests, favourite emote.
    if privacy.shareLocation ~= false and rec.zones then packet.zt = rec.zones end
    if privacy.sharePlaytime ~= false and rec.hours then
        packet.hr = {}
        for h = 1, 24 do packet.hr[h] = math.floor(tonumber(rec.hours[h]) or 0) end
    end
    if privacy.shareSilly ~= false and rec.records then
        local r = rec.records
        packet.rc = { r.killsSession, r.levelsDay, r.goldDay, r.curStreak }
    end
    if privacy.shareSocial ~= false then packet.fe = rec.favEmote end
    if isAlt then packet.alt = true end
    if not isAlt and FS.Officer.BuildPayload then packet.gd = FS.Officer:BuildPayload() end -- guild tools
    if rec.seasons then packet.sn = rec.seasons end

    -- Social: bonds (top 15), rival and wagers.
    if privacy.shareSocial ~= false then
        local bonds = {}
        for key, b in pairs(rec.bonds or {}) do table.insert(bonds, { key, b.time, b.bosses, b.deaths, b.rezzes, b.cls, b.last }) end
        table.sort(bonds, function(x, y) return (x[2] or 0) > (y[2] or 0) end)
        for i = #bonds, 16, -1 do bonds[i] = nil end
        packet.bd, packet.rv = bonds, rec.rival
        if not isAlt then
            packet.cw = {}
            for _, c in ipairs(FS.db.global.customWagers or {}) do
                if #packet.cw < 6 then
                    table.insert(packet.cw, { c.id, c.kind, c.q, c.key, c.opts, c.week, c.created, c.winner })
                end
            end
        end
        packet.bt = {}
        for i = math.max(1, #(rec.bets or {}) - 19), #(rec.bets or {}) do
            local b = rec.bets[i]
            table.insert(packet.bt, { b.w, b.pick, b.amt, b.t })
        end
    end
    -- Last week's final numbers (bounties and wagers), filtered like everything else.
    if rec.lastWk and rec.lastWk.v then
        local v = {}
        for f, value in pairs(rec.lastWk.v) do
            local group = FIELD_GROUP[f]
            if group and (group == "always" or privacy[group] ~= false) then v[f] = math.floor(value) end
        end
        packet.lw = { rec.lastWk.idx, v }
    end

    -- Levelling times (played seconds per level) for the speedrun board.
    if privacy.sharePlaytime ~= false then
        packet.lt = {}
        for level, played in pairs(rec.levelTimes or {}) do table.insert(packet.lt, { level, played }) end
    end
    -- Dungeon & raid log.
    if privacy.shareCombat ~= false then
        packet.en = {}
        for boss, e in pairs(rec.encounters or {}) do
            if #packet.en >= 200 then break end
            table.insert(packet.en, { boss, e.instance, e.kills, e.wipes, e.best, e.first })
        end
    end

    packet.ev = {}
    for _, ev in ipairs(FS.db.global.events) do
        if ev.mine and ev.who == rec.fullName and #packet.ev < 8 then
            if (ev.kind ~= "death" and ev.kind ~= "fallen" and ev.kind ~= "record") or privacy.shareCombat ~= false then
                table.insert(packet.ev, { ev.kind, ev.t, ev.a, ev.v, ev.lp, ev.z, ev.i })
            end
        end
    end
    return packet
end

function Comm:CanSendNow()
    if InCombatLockdown() then return false, "you are in combat" end
    if IsInInstance and IsInInstance() then return false, "addon messages are restricted inside instances" end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "chat messaging is locked down right now"
    end
    return true
end

---------------------------------------------------------------------------
-- Battle.net transport
---------------------------------------------------------------------------

-- Online friends' WoW game accounts in the same game version as us.
function Comm:FriendAccounts()
    local out = {}
    if not (BNGetNumFriends and BNSendGameData and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts
            and C_BattleNet.GetFriendGameAccountInfo) then return out end
    for i = 1, (BNGetNumFriends() or 0) do
        for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
            local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
            if type(g) == "table" and g.isOnline and g.gameAccountID and g.clientProgram == (BNET_CLIENT_WOW or "WoW")
                and (not g.wowProjectID or not WOW_PROJECT_ID or g.wowProjectID == WOW_PROJECT_ID) then
                table.insert(out, g.gameAccountID)
            end
        end
    end
    return out
end

function Comm:KnownPeers()
    local n = 0
    for id in pairs(self.bnetPeers) do if self:MayShareWith(id) then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- Password handshake
--   1. A -> B  hello { ch = nonceA }
--   2. B -> A  ack   { ch = nonceB, pr = Proof(nonceA) }   A checks pr with ITS password
--   3. A -> B  ack2  { pr = Proof(nonceB) }                 B checks pr with ITS password
-- Each side only sends stats to friends who proved knowledge of its own password.
-- Without a password set, every friend with FellowshipSync is trusted (old behaviour).
---------------------------------------------------------------------------

function Comm:Password() return FS.db and FS.db.profile.bnetPassword or "" end
function Comm:Protected() return self:Password() ~= "" end

function Comm:StretchedKey()
    local pw = self:Password()
    if self.keyFor ~= pw then
        local key = "FellowshipSync:" .. pw
        for _ = 1, STRETCH_ROUNDS do key = FS.Sha256(key .. pw) or key end
        self.keyFor, self.key = pw, key
    end
    return self.key
end

function Comm:Proof(nonce) return FS.Sha256(self:StretchedKey() .. ":" .. tostring(nonce)) end

function Comm:Nonce()
    return string.format("%08x%08x%04x", math.random(0, 2147483646), math.random(0, 2147483646), time() % 65536)
end

function Comm:MayShareWith(id)
    if self:Protected() then return self.verified[id] ~= nil end
    local seen = self.bnetPeers[id]
    return seen ~= nil and time() - seen < BN_PEER_WINDOW
end

-- Called when the password changes: everyone has to prove themselves again.
function Comm:ResetTrust()
    for _, t in ipairs({ self.verified, self.helloSent, self.helloNonce, self.ackNonce, self.lastHandshake }) do wipe(t) end
    self.keyFor, self.key = nil, nil
end

function Comm:SendHandshake(target, fields)
    fields.v, fields.k, fields.gm, fields.ver = PROTOCOL, KeyHash(FS.db.global.networkKey), FS.GAME, FS.VERSION
    local text = Encode(fields)
    if text then self:SendBNet(target, text) end
end

function Comm:SendHello(target)
    local nonce = self:Nonce()
    self.helloNonce[target] = nonce
    self.helloSent[target] = true
    self:SendHandshake(target, { hello = true, ch = nonce })
end

function Comm:Handshake(p, id)
    self.bnetPeers[id] = time()
    local theirNonce = Str(p.ch, 40)
    if p.hello then
        if time() - (self.lastHandshake[id] or 0) < HANDSHAKE_COOLDOWN or not theirNonce then return end
        self.lastHandshake[id] = time()
        local mine = self:Nonce()
        self.ackNonce[id] = mine
        self:SendHandshake(id, { ack = true, ch = mine, pr = self:Proof(theirNonce) })
    elseif p.ack then
        local expected = self.helloNonce[id]
        if not expected then return end
        self.helloNonce[id] = nil
        if Str(p.pr, 64) == self:Proof(expected) then self.verified[id] = time() end
        if theirNonce then self:SendHandshake(id, { ack2 = true, pr = self:Proof(theirNonce) }) end
        if self:MayShareWith(id) then FS:ScheduleTimer(function() self:SendTo(id, true) end, 1) end
    elseif p.ack2 then
        local expected = self.ackNonce[id]
        if not expected then return end
        self.ackNonce[id] = nil
        if Str(p.pr, 64) == self:Proof(expected) then self.verified[id] = time() end
        if self:MayShareWith(id) then FS:ScheduleTimer(function() self:SendTo(id, true) end, 1) end
    end
end

function Comm:SendBNet(target, text)
    self.msgId = self.msgId + 1
    local id = string.format("%x%x", SESSION, self.msgId)
    local total = math.ceil(#text / BN_CHUNK)
    for i = 1, total do
        table.insert(self.queue, { target, id .. ":" .. i .. ":" .. total .. ":" .. text:sub((i - 1) * BN_CHUNK + 1, i * BN_CHUNK) })
    end
    self:Pump()
end

-- Sends queued chunks four per second so we never flood Battle.net.
function Comm:Pump()
    if self.pumping then return end
    local item = table.remove(self.queue, 1)
    if not item then return end
    self.pumping = true
    pcall(BNSendGameData, item[1], PREFIX, item[2])
    FS:ScheduleTimer(function() self.pumping = false; self:Pump() end, 0.25)
end

function Comm:OnBNetAddon(prefix, text, _, senderID)
    if prefix ~= PREFIX or IsSecret(text) or IsSecret(senderID) or type(text) ~= "string" or not senderID then return end
    local id, idx, total, body = text:match("^(%x+):(%d+):(%d+):(.*)$")
    idx, total = tonumber(idx), tonumber(total)
    if not id or not idx or not total or total < 1 or total > 40 or idx < 1 or idx > total then return end
    local key = tostring(senderID) .. ":" .. id
    local buf = self.chunks[key]
    if not buf then
        for k, b in pairs(self.chunks) do if time() - b.at > 120 then self.chunks[k] = nil end end
        buf = { parts = {}, got = 0, total = total, at = time() }
        self.chunks[key] = buf
    end
    if buf.total ~= total then return end
    if not buf.parts[idx] then buf.parts[idx] = body; buf.got = buf.got + 1 end
    if buf.got == buf.total then
        self.chunks[key] = nil
        self:HandleMessage(table.concat(buf.parts), "BNET", nil, senderID)
    end
end

-- Sends our current stats straight to one friend (answer to "hello" / requests).
-- Your other characters (last known stats), when it is time to share them.
local ALT_INTERVAL = 3600
function Comm:AltRecords(force)
    local out = {}
    if FS.db.profile.shareAlts == false then return out end
    if not force and time() - (self.altsSentAt or 0) < ALT_INTERVAL then return out end
    local me = FS:GetPlayerKey()
    for name, rec in pairs(FS.db.global.characters) do
        if rec.isMyChar and not rec.isMock and name ~= me and (rec.game == nil or rec.game == FS.GAME) then
            table.insert(out, rec)
        end
    end
    table.sort(out, function(a, b) return (a.lastUpdate or 0) > (b.lastUpdate or 0) end)
    for i = #out, 21, -1 do out[i] = nil end -- at most 20 alts per round
    return out
end

-- Encoded packets for this round: the character you play, then your alts if due.
function Comm:BuildRound(full, forceAlts)
    local rec = FS.Tracker:Snapshot()
    if not rec then return nil end
    local texts = {}
    self.seq = self.seq + 1
    local text = Encode(self:BuildPacket(rec, full))
    if not text then return nil end
    table.insert(texts, text)
    local alts = self:AltRecords(forceAlts or full)
    for _, alt in ipairs(alts) do
        self.seq = self.seq + 1
        local t = Encode(self:BuildPacket(alt, full, true))
        if t then table.insert(texts, t) end
    end
    if #alts > 0 then self.altsSentAt = time() end
    return texts, rec, #alts
end

-- Sends our current stats (and alts) straight to one friend (answer to "hello" / requests).
function Comm:SendTo(target, full)
    if not self:MayShareWith(target) or not self:CanSendNow() then return end
    local texts = self:BuildRound(full, true)
    for _, text in ipairs(texts or {}) do self:SendBNet(target, text) end
end

---------------------------------------------------------------------------
-- Broadcasting
---------------------------------------------------------------------------

function Comm:BroadcastStats(manual)
    if not FS.db then return end
    local profile = FS.db.profile
    local toGuild = profile.syncGuild ~= false and IsInGuild()
    local friends = (profile.syncBNet ~= false) and self:FriendAccounts() or {}
    if not toGuild and #friends == 0 then
        if manual then FS:Print("Nobody to sync with yet: join a guild, or have Battle.net friends online in WoW.") end
        return
    end
    local ok, reason = self:CanSendNow()
    if not ok then
        self.pending = true
        if manual then FS:Print("Sync postponed: " .. reason .. ". It will be sent automatically afterwards.") end
        return
    end
    local firstOfSession = not self.askedThisSession
    if firstOfSession then
        self.askedThisSession, self.requestFullLists = true, true
    end
    local texts, rec, altCount = self:BuildRound(self.sendFullList, firstOfSession or manual)
    if not texts then
        FS:Print("|cffff5555AceSerializer-3.0 is missing.|r Check Libs\\Ace3 and the .toc file.")
        return
    end
    self.pending = false

    if toGuild then
        for _, text in ipairs(texts) do FS:SendCommMessage(PREFIX, text, "GUILD", nil, "BULK") end
    end
    local direct = 0
    for _, target in ipairs(friends) do
        if self:MayShareWith(target) then
            for _, text in ipairs(texts) do self:SendBNet(target, text) end
            direct = direct + 1
        elseif not self.helloSent[target] then
            self:SendHello(target)
        end
    end

    local sent = FS.db.char.mobsSent
    for name, count in pairs(rec.mobs or {}) do sent[name] = count end
    self.sendFullList, self.requestFullLists = false, false
    self.lastSent = time()
    if manual then
        FS:Print(string.format("Stats sent%s%s%s.", toGuild and " to your guild" or "",
            direct > 0 and string.format("%s %d Battle.net friend%s", toGuild and " and" or " to", direct, direct == 1 and "" or "s") or "",
            altCount > 0 and string.format(" (plus %d of your other characters)", altCount) or ""))
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function ReadGear(g)
    if type(g) ~= "table" then return nil end
    local gear = {}
    for slot, item in pairs(g) do
        if VALID_SLOTS[slot] and type(item) == "table" then
            gear[slot] = { name = Str(item[1]) or slot, ilvl = Num(item[2]) or 0, quality = Num(item[3]) or 1,
                           icon = Num(item[4]) or Str(item[4], 120) }
        end
    end
    return gear
end

local function ReadCounts(list, max, firsts)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, math.min(#list, max) do
        local e = list[i]
        if type(e) == "table" and Str(e[1], 64) and Num(e[2]) then
            out[Str(e[1], 64)] = Num(e[2])
            if firsts and Num(e[3]) then firsts[Str(e[1], 64)] = Num(e[3]) end
        end
    end
    return out
end

function Comm:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    if IsSecret(message) or IsSecret(sender) or type(message) ~= "string" then return end
    if FS:IsMe(sender) then return end
    self:HandleMessage(message, distribution, sender, nil)
end

function Comm:HandleMessage(message, distribution, sender, bnetID)
    local p = Decode(message)
    if not p then return end
    -- Version check first: even if a newer version's data can't be read, say so.
    if p.k == KeyHash(FS.db.global.networkKey) and (not p.gm or p.gm == FS.GAME) then
        local ver = type(p.ver) == "string" and not IsSecret(p.ver) and #p.ver <= 11 and p.ver or nil -- never truncate
        FS:NoteVersion(ver, Str(p.n, 80) and FS.ShortName(Str(p.n, 80)) or (sender and Ambiguate(sender, "none")))
    end
    if p.v ~= PROTOCOL or p.k ~= KeyHash(FS.db.global.networkKey) then return end
    if p.gm and p.gm ~= FS.GAME then return end -- never mix Forever and Retail data

    if p.hello or p.ack or p.ack2 then -- Battle.net handshake (never valid over the guild channel)
        if bnetID and FS.db.profile.syncBNet ~= false then self:Handshake(p, bnetID) end
        return
    end

    local name = Str(p.n, 80)
    if not name or name == "" then return end
    local chars = FS.db.global.characters
    local existing = chars[name]
    if existing and existing.isMyChar and not existing.isMock then return end

    -- Drop updates we already have (same update via guild, friend and bridge).
    local ts, sq = Num(p.ts) or 0, Num(p.sq) or 0
    local updateKey = name .. ":" .. ts .. ":" .. sq
    if p.rl then self.relayed[updateKey] = true end
    if bnetID then self.bnetPeers[bnetID] = time() end
    local s = self.seen[name]
    if s and (ts < s.ts or (ts == s.ts and sq <= s.sq)) then return end
    self.seen[name] = { ts = ts, sq = sq }

    local rec = existing or {}
    local data = type(p.d) == "table" and p.d or {}
    local week = type(p.wk) == "table" and p.wk or {}

    rec.fullName = name
    rec.owner = Str(p.o, 48) or (sender and Ambiguate(sender, "none")) or "Unknown"
    rec.isMyChar, rec.isMock = false, nil
    if distribution == "GUILD" and not p.rl then rec.inGuild = true end
    rec.via = (distribution == "BNET" and "bnet") or (p.rl and "relay") or rec.via or "guild"

    rec.wk = {}
    for _, f in ipairs(ALL_FIELDS) do
        if STRING_FIELDS[f] then rec[f] = Str(data[f], 64) else rec[f] = Num(data[f]); rec.wk[f] = Num(week[f]) end
    end
    if not VALID_FACTIONS[rec.faction or ""] then
        rec.faction = (tostring(rec.ruleset or ""):sub(1, 1) == "A") and "Alliance" or "Horde"
    end

    rec.gear = ReadGear(p.g)
    rec.highest = nil
    if type(p.hi) == "table" and Str(p.hi[1]) then
        rec.highest = { link = Str(p.hi[1]), ilvl = Num(p.hi[2]) or 0, quality = Num(p.hi[3]) or 1 }
    end
    rec.profs = nil
    if type(p.p) == "table" then
        rec.profs = {}
        for i = 1, math.min(#p.p, 8) do
            local e = p.p[i]
            if type(e) == "table" and Str(e[1], 40) then
                local kind = (e[4] == "primary" or e[4] == "secondary") and e[4] or "primary"
                table.insert(rec.profs, { name = Str(e[1], 40), rank = Num(e[2]) or 0, max = Num(e[3]) or FS.ProfMax(),
                                          kind = kind, tier = Str(e[5], 40) })
            end
        end
    end
    rec.legacyEarned = nil
    if type(p.lg) == "table" then
        rec.legacyEarned = {}
        for i = 1, math.min(#p.lg, 100) do if Num(p.lg[i]) then table.insert(rec.legacyEarned, Num(p.lg[i])) end end
    end
    rec.firsts = {}
    if type(p.fs) == "table" then
        local n = 0
        for key, t in pairs(p.fs) do
            if n >= MAX_FIRSTS then break end
            if Str(key, 80) and Num(t) then rec.firsts[Str(key, 80)] = Num(t); n = n + 1 end
        end
    end
    rec.deathLog = {}
    if type(p.dl) == "table" then
        for i = 1, math.min(#p.dl, 5) do
            local e = p.dl[i]
            if type(e) == "table" and Num(e[1]) then
                local d = { t = Num(e[1]), zone = Str(e[2], 64) or "", killer = Str(e[3], 64) or "Unknown",
                            kdesc = Str(e[4], 64) or "", lvl = Num(e[5]), words = Str(e[6], 120) }
                local map, x, y = Num(e[7]), Num(e[8]), Num(e[9])
                if map and x and y and x > 0 and x < 1 and y > 0 and y < 1 then d.map, d.x, d.y = map, x, y end
                table.insert(rec.deathLog, d)
            end
        end
    end
    rec.hc = nil
    if type(p.hc) == "table" and Num(p.hc[1]) then
        local h = p.hc
        rec.hc = { t = Num(h[1]), zone = Str(h[2], 64) or "", killer = Str(h[3], 64) or "Unknown", kdesc = Str(h[4], 64) or "",
                   lvl = Num(h[5]), words = Str(h[6], 120), played = Num(h[7]) }
        local map, x, y = Num(h[8]), Num(h[9]), Num(h[10])
        if map and x and y and x > 0 and x < 1 and y > 0 and y < 1 then rec.hc.map, rec.hc.x, rec.hc.y = map, x, y end
    end
    rec.killers = ReadCounts(p.kc, 5)
    rec.mobFirst = rec.mobFirst or {}
    if type(p.mf) == "table" then
        rec.mobFirst = {}
        rec.mobs = ReadCounts(p.mf, MAX_MOBS, rec.mobFirst)
    elseif type(p.md) == "table" then
        rec.mobs = rec.mobs or {}
        local known = 0
        for _ in pairs(rec.mobs) do known = known + 1 end
        for mob, count in pairs(ReadCounts(p.md, MAX_MOBS, rec.mobFirst)) do
            if rec.mobs[mob] or known < MAX_MOBS then
                if not rec.mobs[mob] then known = known + 1 end
                rec.mobs[mob] = count
            end
        end
    end
    rec.version = type(p.ver) == "string" and #p.ver <= 11 and p.ver:match("^[%d%.]+$") and p.ver or nil
    rec.levelTimes = {}
    if type(p.lt) == "table" then
        for i = 1, math.min(#p.lt, 120) do
            local e = p.lt[i]
            local level, played = type(e) == "table" and Num(e[1]), type(e) == "table" and Num(e[2])
            if level and played and level >= 1 and level <= 200 and played >= 0 then rec.levelTimes[level] = played end
        end
    end
    rec.encounters = {}
    if type(p.en) == "table" then
        for i = 1, math.min(#p.en, 200) do
            local e = p.en[i]
            if type(e) == "table" and Str(e[1], 64) then
                rec.encounters[Str(e[1], 64)] = { instance = Str(e[2], 64) or "Unknown", kills = Num(e[3]) or 0, wipes = Num(e[4]) or 0,
                                                  best = Num(e[5]), first = Num(e[6]) }
            end
        end
    end
    rec.firstSeen = Num(p.fsn)
    rec.zones = {}
    if type(p.zt) == "table" then
        for i = 1, math.min(#p.zt, 10) do
            local e = p.zt[i]
            if type(e) == "table" and Str(e[1], 64) and Num(e[2]) then table.insert(rec.zones, { Str(e[1], 64), Num(e[2]) }) end
        end
    end
    rec.hours = nil
    if type(p.hr) == "table" then
        rec.hours = {}
        for h = 1, 24 do rec.hours[h] = Num(p.hr[h]) or 0 end
    end
    rec.records = nil
    if type(p.rc) == "table" then
        rec.records = { killsSession = Num(p.rc[1]), levelsDay = Num(p.rc[2]), goldDay = Num(p.rc[3]), curStreak = Num(p.rc[4]) }
    end
    rec.favEmote = Str(p.fe, 20)
    rec.bonds = {}
    if type(p.bd) == "table" then
        for i = 1, math.min(#p.bd, 15) do
            local e = p.bd[i]
            if type(e) == "table" and Str(e[1], 80) and Num(e[2]) then
                rec.bonds[Str(e[1], 80)] = { time = Num(e[2]), bosses = Num(e[3]) or 0, deaths = Num(e[4]) or 0,
                                             rezzes = Num(e[5]) or 0, cls = Str(e[6], 20), last = Num(e[7]) }
            end
        end
    end
    -- Custom wagers created by this player (checked again when shown: officers only for free-text).
    rec.customWagers = nil
    if type(p.cw) == "table" then
        rec.customWagers = {}
        for i = 1, math.min(#p.cw, 6) do
            local e = p.cw[i]
            if type(e) == "table" and Str(e[1], 80) and (e[2] == "stat" or e[2] == "manual") and Str(e[3], 100) then
                local c = { id = Str(e[1], 80), kind = e[2], q = Str(e[3], 100), week = Num(e[6]), created = Num(e[7]) }
                if c.kind == "stat" then
                    c.key = Str(e[4], 30)
                    if not (c.key and FS.STATS[c.key] and FS.STATS[c.key].weekly) then c = nil end
                else
                    c.opts = {}
                    if type(e[5]) == "table" then
                        for j = 1, math.min(#e[5], 8) do if Str(e[5][j], 40) then table.insert(c.opts, Str(e[5][j], 40)) end end
                    end
                    for _, o in ipairs(c.opts) do if o == e[8] then c.winner = o end end
                    if #c.opts < 2 then c = nil end
                end
                if c then table.insert(rec.customWagers, c) end
            end
        end
    end
    local previousRival = rec.rival
    rec.rival = Str(p.rv, 80)
    rec.bets = {}
    if type(p.bt) == "table" then
        for i = 1, math.min(#p.bt, 20) do
            local e = p.bt[i]
            if type(e) == "table" and Str(e[1], 40) and Str(e[2], 80) and Num(e[3]) and Num(e[3]) > 0 and Num(e[3]) <= 100000 then
                table.insert(rec.bets, { w = Str(e[1], 40), pick = Str(e[2], 80), amt = math.floor(Num(e[3])), t = Num(e[4]) })
            end
        end
    end
    rec.lastWk = nil
    if type(p.lw) == "table" and Num(p.lw[1]) and type(p.lw[2]) == "table" then
        local v = {}
        for f, value in pairs(p.lw[2]) do if FIELD_GROUP[f] and Num(value) then v[f] = Num(value) end end
        rec.lastWk = { idx = Num(p.lw[1]), v = v }
    end
    rec.game = FS.GAME
    -- Live updates are "now"; an alt's last known stats keep their real date.
    local stamped = Num(p.ts)
    rec.lastUpdate = (p.alt and stamped and stamped > 0) and math.min(time(), stamped) or time()
    rec.isAlt = p.alt and true or nil
    chars[name] = rec
    FS:Touch()
    if FS.Fellowship.CheckNamedRival then FS.Fellowship:CheckNamedRival(rec, previousRival) end
    rec.seasons = nil
    if type(p.sn) == "table" then
        rec.seasons = {}
        local n = 0
        for id, map in pairs(p.sn) do
            if n >= 6 then break end
            if Str(id, 120) and type(map) == "table" then
                local clean = {}
                for k, v in pairs(map) do if Str(k, 30) and Num(v) then clean[Str(k, 30)] = Num(v) end end
                rec.seasons[Str(id, 120)] = clean
                n = n + 1
            end
        end
    end
    if p.gd and not p.alt and FS.Officer.Ingest then FS.Officer:Ingest(p.gd, name) end

    if type(p.ev) == "table" then
        for i = 1, math.min(#p.ev, 8) do
            local e = p.ev[i]
            if type(e) == "table" and EVENT_KINDS[e[1]] and Num(e[2]) then
                FS:AddEvent({ kind = e[1], who = name, t = Num(e[2]), a = Str(e[3]), v = Num(e[4]), lp = Num(e[5]),
                              z = Str(e[6], 64), i = Num(e[7]) }, true)
            end
        end
    end

    if not p.alt then self:MaybeAnswerRequest(p, distribution, bnetID) end -- alt data never asks for replies
    self:MaybeBridge(p, distribution, updateKey)
    FS:QueueUIRefresh()
end

-- Someone asked for full kill lists (they just logged in).
function Comm:MaybeAnswerRequest(p, distribution, bnetID)
    if not p.rq or FS.db.profile.privacy.shareCombat == false then return end
    if distribution == "BNET" then
        if bnetID then FS:ScheduleTimer(function() self:SendTo(bnetID, true) end, math.random(3, 15)) end
        return
    end
    if self.replyTimer or time() - (self.lastFullSent or 0) <= FULL_LIST_COOLDOWN then return end
    self.replyTimer = FS:ScheduleTimer(function()
        self.replyTimer = nil
        self.lastFullSent = time()
        self.sendFullList = true
        self:BroadcastStats(false)
    end, math.random(5, 45))
end

-- Pass a friend's update into our guild, once, unless someone beat us to it.
function Comm:MaybeBridge(p, distribution, updateKey)
    local profile = FS.db.profile
    if distribution ~= "BNET" or p.rl or p.nr or (tonumber(p.h) or 0) >= 1 then return end
    if profile.relayBNet == false or profile.syncGuild == false or not IsInGuild() then return end
    FS:ScheduleTimer(function()
        if self.relayed[updateKey] or not self:CanSendNow() then return end
        self.relayed[updateKey] = true
        p.h, p.rl, p.rq = 1, true, nil
        local text = Encode(p)
        if text then FS:SendCommMessage(PREFIX, text, "GUILD", nil, "BULK") end
    end, math.random(2, 12))
end
