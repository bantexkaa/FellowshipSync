local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Tracker = FS.Tracker
local IsSecret = FS.IsSecret

---------------------------------------------------------------------------
-- Where each number comes from (Midnight engine: no combat log access).
--  * Blizzard Statistics, found by NAME at runtime (English clients), with a few
--    known IDs as fallback. Verify with /fsync stats.
--  * Our own counters from events that addons may still read.
-- When both exist we keep the larger value, so they never double count.
---------------------------------------------------------------------------
local STAT_NAMES = {
    kills       = { "^Total kills$" },
    deaths      = { "^Total deaths$" },
    quests      = { "^Quests completed$" },
    damage      = { "^Total damage done$" },
    healing     = { "^Total healing done$" },
    crit        = { "^Largest hit dealt$" },
    critters    = { "^Critters killed$" },
    fallDeaths  = { "^Deaths from falling$" },
    duelsWon    = { "^Duels won$" },
    duelsLost   = { "^Duels lost$" },
    flightRides = { "^Flight paths taken$" },
    fish        = { "^Fish and other things caught$", "^Fish caught$" },
    epics       = { "^Epic items looted$", "^Epic items acquired$" },
    goldLooted  = { "^Gold looted$", "^Total gold looted$" },
    repairs     = { "^Total gold spent on repairs$", "^Gold spent on repairs$" },
    bgPlayed    = { "^Battlegrounds played$" },
    bgWon       = { "^Battlegrounds won$" },
    bandages    = { "^Bandages used$" },
    needRolls   = { "^Need rolls made" },
    greedRolls  = { "^Greed rolls made" },
}
local FALLBACK_IDS = { kills = 1197, deaths = 60, quests = 98, critters = 108 }
local MONEY_STATS = { goldLooted = true, repairs = true }

-- Milestone ladders ---------------------------------------------------------------
-- Counts: 50, 100, 200, 500, 750, 1,000, 1,500, 2,000, then every 1,000 up to 10,000,
-- every 5,000 up to 100,000, and every 50,000 after that, forever.
local function Ladder(v)
    local best = 0
    for _, t in ipairs({ 50, 100, 200, 500, 750, 1000, 1500, 2000 }) do if v >= t then best = t end end
    if v >= 3000 then best = math.min(10000, math.floor(v / 1000) * 1000) end
    if v >= 15000 then best = math.min(100000, math.floor(v / 5000) * 5000) end
    if v >= 150000 then best = math.floor(v / 50000) * 50000 end
    return best
end
-- Chat comes fast: the same ladder from 1,000.
local function ChatLadder(v) local r = Ladder(v) return r >= 1000 and r or 0 end
-- All characters together: bigger steps.
local function AccountLadder(v)
    local best = 0
    for _, t in ipairs({ 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000 }) do if v >= t then best = t end end
    if v >= 750000 then best = math.floor(v / 250000) * 250000 end
    return best
end
local GOLD, DAY = 10000, 86400
local function Steps(v, unit, list, every, from)
    local x, best = v / unit, 0
    for _, t in ipairs(list) do if x >= t then best = t end end
    if x >= from then best = math.floor(x / every) * every end
    return best * unit
end
local function GoldLadder(c) return Steps(c, GOLD, { 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 }, 100000, 200000) end
local function AccountGold(c) return Steps(c, GOLD, { 1000, 5000, 10000, 25000, 50000, 100000, 250000 }, 250000, 500000) end
local function TimeLadder(s) return Steps(s, DAY, { 1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120 }, 30, 150) end
local function AccountTime(s) return Steps(s, DAY, { 7, 14, 30, 60, 90, 180, 365 }, 100, 465) end

-- Distance in the chosen unit (u = metres or yards): metres/yards first, then whole km/miles.
local function DistLadder(u, imperial)
    local factor = imperial and 1760 or 1000
    local best = 0
    for _, t in ipairs(imperial and { 50, 100, 250, 500, 1000 } or { 50, 100, 250, 500, 750 }) do if u >= t then best = t end end
    local k = u / factor
    for _, t in ipairs({ 1, 2, 5, 10, 15, 20, 25, 50, 75, 100 }) do if k >= t then best = t * factor end end
    if k >= 150 then best = math.min(500, math.floor(k / 50) * 50) * factor end
    if k >= 600 then best = math.min(1000, math.floor(k / 100) * 100) * factor end
    if k >= 1250 then best = math.min(5000, math.floor(k / 250) * 250) * factor end
    local last = imperial and 500 or 1000
    if k >= 5000 + last then best = math.floor(k / last) * last * factor end
    return best
end
local function AccountDist(u, imperial)
    local factor = imperial and 1760 or 1000
    return Steps(u, factor, { 100, 250, 500, 1000, 2500, 5000 }, 2500, 7500)
end
Tracker.Ladder, Tracker.DistLadder, Tracker.AccountLadder = Ladder, DistLadder, AccountLadder

-- Which stats get milestones: { key, character ladder, account ladder }
local MILESTONE_STATS = {}
for _, key in ipairs({ "kills", "deaths", "quests", "critters", "fish", "jumps", "bossKills", "duelsWon", "epics", "hearths",
                       "areasDiscovered", "flightPathsFound", "flightRides", "corpseRuns", "emotes", "potions", "foodDrink",
                       "bandages", "trades", "mailsSent", "whispersSent", "rollsWon", "crafted", "gathered", "instanceRuns",
                       "fights", "pvpKills", "fallDeaths" }) do
    table.insert(MILESTONE_STATS, { key, Ladder, AccountLadder })
end
table.insert(MILESTONE_STATS, { "chat", ChatLadder, AccountLadder })
table.insert(MILESTONE_STATS, { "goldLooted", GoldLadder, AccountGold })
table.insert(MILESTONE_STATS, { "moneyIn", GoldLadder, AccountGold })
table.insert(MILESTONE_STATS, { "playtime", TimeLadder, AccountTime })
table.insert(MILESTONE_STATS, { "combatTime", TimeLadder, AccountTime })

-- Fun one-offs: { key, stat, metres }
local SPECIALS = { { "marathon", "travelFoot", 42195 }, { "ultra", "travelFoot", 100000 }, { "legend", "travelTotal", 1000000 } }
-- Level steps dated for Guild Firsts: the game's extra steps (Forever: the Legacy
-- class challenges 25/45) plus max level.
local function LevelStamps()
    local list = {}
    for _, l in ipairs(FS.GAME_INFO.levels or {}) do table.insert(list, l) end
    table.insert(list, FS:MaxLevel())
    return list
end
local LAST_WORDS_CHANNELS = { SAY = true, YELL = true, PARTY = true, RAID = true, GUILD = true,
                              INSTANCE_CHAT = true, RAID_WARNING = true, EMOTE = true }

-- GearScore weights per slot and quality (FellowshipSync's own formula).
local SLOT_WEIGHT = {
    Head = 1, Chest = 1, Legs = 1, Shoulder = 0.75, Hands = 0.75, Waist = 0.75, Feet = 0.75,
    Neck = 0.5625, Back = 0.5625, Wrist = 0.5625, Finger0 = 0.5625, Finger1 = 0.5625,
    Trinket0 = 0.5625, Trinket1 = 0.5625, MainHand = 1, SecondaryHand = 1,
}
local QUALITY_MULT = { [0] = 0.5, [1] = 0.75, [2] = 0.9, [3] = 1.0, [4] = 1.15, [5] = 1.3, [6] = 1.3, [7] = 1.0 }

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Pack(...) return { n = select("#", ...), ... } end

-- Calls a game API without letting an error (or a removed function) break us.
local function Safe(fn, ...)
    if not fn then return nil end
    local r = Pack(pcall(fn, ...))
    if not r[1] then return nil end
    return unpack(r, 2, r.n)
end
Tracker.Safe = Safe

local function Clean(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

-- Turns a Blizzard format string ("You receive loot: %s.") into a Lua pattern
-- and remembers which argument each capture is (handles "%2$s" too).
local function FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local order, nextIndex = {}, 1
    local pattern = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^])", "%%%1")
    pattern = pattern:gsub("%%(%d?)%$?([sd])", function(pos, kind)
        local index = tonumber(pos)
        if not index then index = nextIndex; nextIndex = nextIndex + 1 end
        table.insert(order, index)
        return kind == "d" and "(%d+)" or "(.+)"
    end)
    return "^" .. pattern .. "$", order
end

local function MatchFormat(msg, fmt)
    local pattern, order = FormatToPattern(fmt)
    if not pattern then return nil end
    local caps = { msg:match(pattern) }
    if #caps == 0 then return nil end
    local args = {}
    for i, index in ipairs(order) do args[index] = caps[i] end
    return args
end
Tracker.MatchFormat = MatchFormat

local function ParseStatistic(raw, isMoney)
    if raw == nil or IsSecret(raw) then return nil end
    if type(raw) == "number" then return raw end
    if type(raw) ~= "string" or raw == "" or raw == "--" then return nil end
    if raw:find("|T", 1, true) then
        if not isMoney then return nil end
        local s = raw
        for _ = 1, 3 do s = s:gsub("(%d)[,%.%s](%d%d%d)", "%1%2") end
        local function amount(icon)
            return tonumber(s:match("(%d+)%s*|T[^|]-" .. icon)) or 0
        end
        return amount("GoldIcon") * 10000 + amount("SilverIcon") * 100 + amount("CopperIcon")
    end
    local value = tonumber((raw:gsub("[^%d]", "")))
    if value and isMoney then value = value * 10000 end -- plain number means gold
    return value
end

local function ItemQuality(link)
    if type(link) ~= "string" then return nil end
    local q = tonumber(link:match("|cnIQ(%d)"))
    if q then return q end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    local byHex = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6, ["00ccff"] = 7 }
    if hex and byHex[hex:lower()] then return byHex[hex:lower()] end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = Safe(getInfo, link)
    return quality
end
Tracker.ItemQuality = ItemQuality

local function ItemLevel(link)
    local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    return math.floor(tonumber((Safe(fn, link))) or 0)
end

local function EquipLoc(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, equipLoc = Safe(fn, link)
    return equipLoc
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return Safe(C_Spell.GetSpellName, spellID) end
    if GetSpellInfo then return (Safe(GetSpellInfo, spellID)) end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function Tracker:Enable()
    self.db = FS.db
    local events = {
        "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_FLAGS_CHANGED", "TIME_PLAYED_MSG", "PLAYER_LOGOUT", "PLAYER_LEVEL_UP",
        "ACHIEVEMENT_EARNED", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL",
        "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_MONEY",
        "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY",
        "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TARGET_CHANGED", "MIRROR_TIMER_START", "MIRROR_TIMER_STOP",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_TURNED_IN", "ENCOUNTER_START", "ENCOUNTER_END",
        "PLAYER_REGEN_DISABLED", "UI_INFO_MESSAGE", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CONFIRM_XP_LOSS",
        "PLAYER_UNGHOST", "PLAYER_ALIVE", "UPDATE_BATTLEFIELD_SCORE", "RESURRECT_REQUEST",
    }
    LibStub("AceEvent-3.0"):Embed(self)
    for _, ev in ipairs(events) do FS.SafeRegister(self, ev) end

    -- Health changes on your target and on enemy nameplates: used to notice kills.
    -- Only units we are watching are looked at, so this stays cheap in raids.
    self.watched, self.counted = {}, {}
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_HEALTH")
    f:SetScript("OnEvent", function(_, _, unit) if self.watched[unit] then self:CheckUnitDeath(unit) end end)
    self.unitFrame = f
    self.guidInfo, self.guidCount = {}, 0

    -- Classic Era, TBC and Mists: exact kills, damage and killers from the combat log.
    if self.CombatLog and self.CombatLog.Enable then self.useCombatLog = self.CombatLog:Enable() end

    self:InstallHooks()
    FS:ScheduleRepeatingTimer(function() self:Tick() end, 1)
    FS:ScheduleRepeatingTimer(function() self:Snapshot(); FS:RefreshUIIfShown() end, 60)
    FS:ScheduleRepeatingTimer(function() FS.Comm:BroadcastStats(false) end, 600)

    self:Snapshot()
end

function Tracker:Stats() return self.db.char.stats end

function Tracker:CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Consumable sub-types (the same numbers in every game version).
local CONSUMABLE = { [1] = "potions", [2] = "potions", [3] = "potions", [5] = "foodDrink", [7] = "bandages" }
function Tracker:OnItemUsed(itemID)
    if not itemID or IsSecret(itemID) then return end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID, subclassID = Safe(fn, itemID)
    if classID == 0 and CONSUMABLE[subclassID] then self:Add(CONSUMABLE[subclassID]) end
end

function Tracker:Add(key, amount)
    local st = self.db.char.stats
    st[key] = (tonumber(st[key]) or 0) + (amount or 1)
end

function Tracker:InstallHooks()
    if self.hooked then return end
    self.hooked = true

    if JumpOrAscendStart then
        hooksecurefunc("JumpOrAscendStart", function() self:Add("jumps") end)
    end

    local function OnChatSent(msg, chatType)
        if self.postingChronicle then return end -- our own recaps and announcements don't count
        self:Add("chat")
        if chatType == "WHISPER" then self:Add("whispersSent") end
        if type(msg) == "string" and not IsSecret(msg) and LAST_WORDS_CHANNELS[chatType or ""] then
            self.lastWords, self.lastWordsAt = msg:sub(1, 120), time()
        end
    end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        hooksecurefunc(C_ChatInfo, "SendChatMessage", OnChatSent)
    elseif SendChatMessage then
        hooksecurefunc("SendChatMessage", OnChatSent)
    end
    if BNSendWhisper then hooksecurefunc("BNSendWhisper", function() self:Add("whispersSent") end) end
    local function OnEmote(token)
        if type(token) ~= "string" or IsSecret(token) then return end
        self:Add("emotes")
        local counts = self.db.char.emoteCounts
        token = token:upper():sub(1, 20)
        if counts[token] or self:CountKeys(counts) < 60 then counts[token] = (counts[token] or 0) + 1 end
    end
    if C_ChatInfo and C_ChatInfo.PerformEmote then hooksecurefunc(C_ChatInfo, "PerformEmote", OnEmote)
    elseif DoEmote then hooksecurefunc("DoEmote", OnEmote) end
    if SendMail then hooksecurefunc("SendMail", function() self:Add("mailsSent") end) end
    if C_QuestLog and C_QuestLog.AbandonQuest then hooksecurefunc(C_QuestLog, "AbandonQuest", function() self:Add("questsAbandoned") end)
    elseif AbandonQuest then hooksecurefunc("AbandonQuest", function() self:Add("questsAbandoned") end) end
    -- Consumables: items used from bags or action bars, sorted by item type.
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            self:OnItemUsed(C_Container.GetContainerItemID and Safe(C_Container.GetContainerItemID, bag, slot))
        end)
    elseif UseContainerItem then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            self:OnItemUsed(GetContainerItemID and Safe(GetContainerItemID, bag, slot))
        end)
    end
    if UseAction then
        hooksecurefunc("UseAction", function(slot)
            local kind, id = Safe(GetActionInfo, slot)
            if kind == "item" then self:OnItemUsed(id) end
        end)
    end
end

---------------------------------------------------------------------------
-- Blizzard statistics
---------------------------------------------------------------------------

function Tracker:DiscoverStatistics()
    if self.statIds then return self.statIds end
    local ids = {}
    for k, id in pairs(FALLBACK_IDS) do ids[k] = id end
    if GetStatisticsCategoryList and GetCategoryNumAchievements and GetAchievementInfo then
        for _, cat in ipairs(Safe(GetStatisticsCategoryList) or {}) do
            for i = 1, (Safe(GetCategoryNumAchievements, cat) or 0) do
                local id, name = Safe(GetAchievementInfo, cat, i)
                if id and type(name) == "string" then
                    for key, patterns in pairs(STAT_NAMES) do
                        for _, p in ipairs(patterns) do
                            if name:find(p) then ids[key] = id end
                        end
                    end
                end
            end
        end
    end
    self.statIds = ids
    return ids
end

function Tracker:UpdateStatistics()
    if not GetStatistic or InCombatLockdown() then return end
    local st = self:Stats()
    for key, id in pairs(self:DiscoverStatistics()) do
        local value = ParseStatistic(Safe(GetStatistic, id), MONEY_STATS[key])
        if value and value > (tonumber(st[key]) or 0) then st[key] = value end
    end
end

function Tracker:PrintStatisticCheck()
    self.statIds = nil
    FS:Print("Statistics FellowshipSync reads (key -> id, name = value):")
    for key, id in pairs(self:DiscoverStatistics()) do
        local _, name = Safe(GetAchievementInfo, id)
        FS:Print(string.format("  %s -> #%d '%s' = %s", key, id, tostring(name), tostring(Safe(GetStatistic, id))))
    end
    for key in pairs(STAT_NAMES) do
        if not self.statIds[key] then FS:Print("  |cffff8800" .. key .. ": not found (own tracking only)|r") end
    end
end

---------------------------------------------------------------------------
-- Points: on WoW: Forever the Legacy Challenges window is built on the
-- achievement functions, so challenges are read from there and their points
-- are Legacy Points. On Retail these are normal Achievement Points, and only
-- the most recent achievements are listed (Retail has thousands).
---------------------------------------------------------------------------

function Tracker:ScanLegacy()
    local apiTotal = tonumber((Safe(GetTotalAchievementPoints))) or 0
    local total = apiTotal
    local catalog, earned, maxPoints, earnedPoints = nil, {}, 0, 0
    self.legacyScanAt = time()

    if FS.IS_FOREVER and GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo then
        -- Forever shows its Legacy Challenges through the achievement functions. Each completed
        -- challenge is worth one Legacy Point, whatever the achievement-points field says
        -- (it can be 0 for Legacy Challenges), so we count the challenges themselves.
        catalog = {}
        local cats = Safe(GetCategoryList) or {}
        local diag = { categories = #cats, challenges = 0, completed = 0, apiTotal = apiTotal, pointsField = 0 }
        for _, cat in ipairs(cats) do
            for i = 1, (Safe(GetCategoryNumAchievements, cat, true) or 0) do
                local id, name, points, completed, month, day, year, _, _, icon = Safe(GetAchievementInfo, cat, i)
                if id and not FS.IsSecret(id) and #catalog < 500 then
                    diag.challenges = diag.challenges + 1
                    diag.pointsField = diag.pointsField + (tonumber(points) or 0)
                    local done = completed and true or false
                    table.insert(catalog, { id = id, name = name, points = 1, done = done, icon = icon,
                                            date = (done and tonumber(year)) and time({ year = 2000 + year, month = month, day = day, hour = 12 }) or nil })
                    maxPoints = maxPoints + 1
                    if done then earnedPoints = earnedPoints + 1; diag.completed = diag.completed + 1 end
                end
            end
        end
        local firsts = self.db.char.firsts
        for _, a in ipairs(catalog) do
            if a.done then
                table.insert(earned, a.id)
                if not firsts["lg:" .. a.id] then firsts["lg:" .. a.id] = a.date or 0 end
            end
        end
        -- Our own count is the Legacy total; the game's figure is only a fallback.
        total = earnedPoints > 0 and earnedPoints or apiTotal
        self.legacyDiag = diag
    elseif GetLatestCompletedAchievements then
        for _, id in ipairs({ Safe(GetLatestCompletedAchievements) }) do
            if type(id) == "number" then table.insert(earned, id) end
        end
    end

    self.legacyCatalog = catalog
    self.legacyMax = catalog and maxPoints > 0 and maxPoints or nil
    self.legacyEarned = earned
    self.legacyTotal = total
end

function Tracker:PrintLegacyCheck()
    self:ScanLegacy()
    FS:Print(string.format("%s: %s", FS.POINTS.long, tostring(self.legacyTotal or 0)))
    local d = self.legacyDiag
    if d then
        FS:Print(string.format("Found %d categories and %d challenges; %d completed. Game's points total: %d (points field sum: %d).",
            d.categories, d.challenges, d.completed, d.apiTotal, d.pointsField))
        if d.challenges == 0 then
            FS:Print("No challenges were listed yet. Open the Legacy window once, then type /fsync legacy again.")
        end
    elseif self.legacyCatalog == nil then
        FS:Print("Showing your most recent achievements (this game has achievements, not Legacy Challenges).")
    end
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------

-- Professions: the two main professions first, then secondary skills (Fishing, Cooking,
-- First Aid, Archaeology). Retail splits professions per expansion: the expansion name is kept
-- as "tier" and progress uses that tier's own maximum. Archaeology is never split.
function Tracker:ScanProfessions()
    local list = {}
    local function add(name, rank, maxRank, kind, tier)
        if type(name) == "string" and tonumber(rank) then
            table.insert(list, { name = name, rank = tonumber(rank), max = tonumber(maxRank) or FS.ProfMax(), kind = kind,
                                 tier = (type(tier) == "string" and tier ~= "" and tier ~= name) and tier or nil })
        end
    end
    if GetProfessions and GetProfessionInfo then
        -- GetProfessions(): main 1, main 2, Archaeology, Fishing, Cooking (and First Aid on old clients)
        local n = select("#", GetProfessions())
        for i = 1, n do
            local index = select(i, GetProfessions())
            if index then
                local name, _, rank, maxRank, _, _, _, _, _, _, tierName = Safe(GetProfessionInfo, index)
                add(name, rank, maxRank, i <= 2 and "primary" or "secondary", tierName)
            end
        end
    end
    if #list == 0 and GetNumSkillLines and GetSkillLineInfo then
        local section
        for i = 1, (Safe(GetNumSkillLines) or 0) do
            local name, isHeader, _, rank, _, _, maxRank = Safe(GetSkillLineInfo, i)
            if isHeader then
                section = ((name == TRADE_SKILLS or name == "Professions") and "primary")
                    or ((name == SECONDARY_SKILLS or name == "Secondary Skills") and "secondary") or nil
            elseif section then
                add(name, rank, maxRank, section)
            end
        end
    end
    -- Main professions first, then by progress within each group.
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == "primary" end
        return (a.rank / math.max(1, a.max)) > (b.rank / math.max(1, b.max))
    end)

    -- Milestones at fixed brackets: every 50 on Classic games (Retail: 25/50/75/100 per expansion),
    -- the same for main and secondary professions. Retail Archaeology isn't split by expansion,
    -- so it uses hundreds up to 950. "Maxed" is the game's real maximum, not the current cap.
    local gameSteps = FS.GAME_INFO.profSteps
    local ARCHAEOLOGY = { 100, 200, 300, 400, 500, 600, 700, 800, 900, 950 }
    local function StepsFor(p)
        if FS.GAME == "retail" and (p.max or 0) > gameSteps[#gameSteps] then return ARCHAEOLOGY end
        return gameSteps
    end
    -- Forever's Legacy Race also looks at 150 / 225 / 300 (recorded quietly).
    local LEGACY = FS.IS_FOREVER and { 150, 225, 300 } or {}
    local known, firsts = self.db.char.profRanks, self.db.char.firsts
    for _, p in ipairs(list) do
        local id = p.name .. (p.tier and (" (" .. p.tier .. ")") or "")
        local before = known[id]
        local steps = StepsFor(p)
        local top = steps[#steps]
        if before then
            for _, th in ipairs(steps) do
                if before < th and p.rank >= th then
                    FS:AddEvent({ kind = "prof", who = FS:GetPlayerKey(), a = p.name, v = th, i = top })
                end
            end
        end
        known[id] = p.rank
        local marks = {}
        for _, th in ipairs(steps) do if th >= 100 or th == top then marks[th] = true end end
        for _, th in ipairs(LEGACY) do marks[th] = true end
        for th in pairs(marks) do
            local key = "prof:" .. p.name .. ":" .. th
            if p.rank >= th and firsts[key] == nil then
                firsts[key] = before and before < th and time() or 0 -- reached before install: known, but no date
            end
        end
        if p.rank >= top then
            local key = "prof:" .. p.name .. ":max"
            if firsts[key] == nil then firsts[key] = before and before < top and time() or 0 end
        end
    end
    self.professions = list
    return list
end

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------

function Tracker:ScanGear()
    local gear, highest = {}, nil
    local gs, twoHander, ilvlSum = 0, false, 0
    for _, slot in ipairs(FS.GEAR_SLOTS) do
        local ok, slotId = pcall(GetInventorySlotInfo, slot .. "Slot")
        local link = ok and slotId and GetInventoryItemLink("player", slotId)
        if link then
            local ilvl = ItemLevel(link)
            local quality = GetInventoryItemQuality("player", slotId) or ItemQuality(link) or 1
            gear[slot] = { name = link, ilvl = ilvl, quality = quality, icon = GetInventoryItemTexture("player", slotId) }
            local weight = SLOT_WEIGHT[slot] or 0.5
            if slot == "MainHand" and EquipLoc(link) == "INVTYPE_2HWEAPON" then weight = 2; twoHander = true end
            if slot == "SecondaryHand" and twoHander then weight = 0 end
            ilvlSum = ilvlSum + ilvl * ((slot == "MainHand" and twoHander) and 2 or 1)
            gs = gs + weight * ilvl * (QUALITY_MULT[quality] or 1)
            if not highest or ilvl > highest.ilvl then
                highest = { link = link, ilvl = ilvl, quality = quality }
            end
        end
    end
    return gear, math.floor(gs + 0.5), highest, ilvlSum / #FS.GEAR_SLOTS
end

---------------------------------------------------------------------------
-- Building your own character record
---------------------------------------------------------------------------

function Tracker:Ruleset(faction)
    local setting = FS.db.profile.ruleset or "auto"
    local kind = setting
    if setting == "auto" then
        kind = (C_GameRules and C_GameRules.IsHardcoreActive and Safe(C_GameRules.IsHardcoreActive)) and "HC" or "PvE"
    end
    return ((faction == "Alliance") and "A" or "H") .. "-" .. kind
end

function Tracker:IsHardcore()
    return (self:Ruleset(UnitFactionGroup("player")):match("%-HC$")) ~= nil
end

function Tracker:Snapshot()
    if not self.db then return end
    self:UpdateStatistics()
    -- Rescan at least once a minute: challenge data may arrive after login, and completing
    -- a Legacy Challenge doesn't always fire the achievement event.
    if not self.legacyEarned or time() - (self.legacyScanAt or 0) >= 60 or (self.legacyTotal or 0) == 0 then self:ScanLegacy() end
    if not self.professions then self:ScanProfessions() end

    local key = FS:GetPlayerKey()
    local chars = self.db.global.characters
    local rec = chars[key] or {}
    local st = self:Stats()
    local c = self.db.char

    local _, cls = UnitClass("player")
    local faction = UnitFactionGroup("player") or "Neutral"
    local overall, equipped = 0, 0
    if GetAverageItemLevel then
        local o, e = GetAverageItemLevel()
        overall, equipped = tonumber(o) or 0, tonumber(e) or 0
    end
    local gear, gs, highest, gearAvg = self:ScanGear()
    if equipped <= 0 then equipped = gearAvg end  -- games without GetAverageItemLevel
    local level = UnitLevel("player") or 1
    local maxLevel = FS:MaxLevel()

    rec.fullName = key
    rec.owner = self:AccountLabel()
    rec.isMyChar, rec.isMock = true, nil
    rec.inGuild = IsInGuild() and true or false
    rec.guildName = IsInGuild() and (Safe(GetGuildInfo, "player")) or nil
    rec.cls = cls or "WARRIOR"
    rec.race = (Safe(UnitRace, "player"))
    rec.faction = faction
    rec.level = level
    rec.ruleset = self:Ruleset(faction)
    rec.zone = GetRealZoneText() or rec.zone
    rec.hearth = (Safe(GetBindLocation))
    if level >= maxLevel then
        rec.rested = -1
    else
        local xpMax = tonumber(UnitXPMax("player")) or 0
        local rested = tonumber((Safe(GetXPExhaustion))) or 0
        rec.rested = xpMax > 0 and math.floor(rested / xpMax * 100) or 0
    end
    rec.ilvl = tonumber(string.format("%.1f", equipped)) or 0
    rec.ilvlBag = tonumber(string.format("%.1f", math.max(overall, equipped))) or 0
    rec.gs = gs
    rec.gear = gear
    rec.highest = highest
    rec.wealth = GetMoney() or 0
    rec.legacy = self.legacyTotal or 0
    rec.legacyMax = self.legacyMax
    rec.game = FS.GAME
    rec.legacyEarned = self.legacyEarned
    rec.profs = self.professions
    rec.playtimeLevel = c.playtimeLevel
    for _, k in ipairs(FS.COUNTER_KEYS) do rec[k] = math.floor(tonumber(st[k]) or 0) end
    rec.crit = math.floor(tonumber(st.crit) or 0)
    rec.deathLog = c.deathLog
    rec.killers = c.killers
    rec.mobs = c.mobs
    rec.mobFirst = c.mobFirst
    for _, th in ipairs(LevelStamps()) do
        if level >= th and c.firsts["lv" .. th] == nil then c.firsts["lv" .. th] = 0 end
    end
    rec.firsts = c.firsts
    rec.levelTimes = c.levelTimes
    rec.encounters = c.encounters
    rec.version = FS.VERSION
    c.firstSeen = c.firstSeen or time()
    rec.firstSeen = c.firstSeen
    rec.bonds = c.bonds
    rec.rival = c.rival
    rec.lastWk = c.lastWk
    rec.bets = self.db.global.bets
    -- Personal bests and habits
    local r = c.records
    local session = time() - (tonumber(c.sessionStart) or time())
    r.longestSession = math.max(tonumber(r.longestSession) or 0, session)
    r.killsSession = math.max(tonumber(r.killsSession) or 0, (tonumber(st.kills) or 0) - (self.sessionKills or tonumber(st.kills) or 0))
    for _, d in pairs(c.daily) do
        r.levelsDay = math.max(tonumber(r.levelsDay) or 0, d.levels or 0)
        r.goldDay = math.max(tonumber(r.goldDay) or 0, d.gold or 0)
    end
    local current, best, days = self:Streaks()
    r.bestStreak = math.max(tonumber(r.bestStreak) or 0, best)
    r.curStreak = current
    rec.daysPlayed, rec.bestStreak = days, r.bestStreak
    rec.longestSession = r.longestSession
    rec.longestLife = math.max(tonumber(r.longestLife) or 0, tonumber(c.life) or 0)
    rec.curLife = c.life
    rec.records = r
    rec.biggestLoot = tonumber(st.biggestLoot) or 0
    rec.companions = self:CountKeys(c.bonds)
    local hk = GetPVPLifetimeStats and Safe(GetPVPLifetimeStats)
    if tonumber(hk) then rec.honorKills = math.max(tonumber(rec.honorKills) or 0, hk) end
    rec.hours = c.hours
    local zones = {}
    for z, sec in pairs(c.zoneTime) do table.insert(zones, { z, sec }) end
    table.sort(zones, function(a, b) return a[2] > b[2] end)
    for i = #zones, 11, -1 do zones[i] = nil end
    rec.zones = zones
    local fav, favN = nil, 0
    for token, n in pairs(c.emoteCounts) do if n > favN then fav, favN = token, n end end
    rec.favEmote = fav
    if FS.Officer.SeasonProgress then rec.seasons = FS.Officer:SeasonProgress(rec) end
    rec.hc = c.hc
    rec.lastUpdate = time()
    chars[key] = rec

    self:UpdateWeekly(rec)
    self:CheckMilestones(rec)
    return rec
end

function Tracker:AccountLabel()
    if self.accountLabel then return self.accountLabel end
    if BNGetInfo then
        local _, battleTag = Safe(BNGetInfo)
        if type(battleTag) == "string" and not IsSecret(battleTag) then
            self.accountLabel = battleTag:match("^([^#]+)")
            if self.accountLabel then return self.accountLabel end
        end
    end
    return UnitName("player") or "Unknown"
end

-- "This Week" values = counter now minus counter at the last weekly reset.
-- Seconds until the weekly reset. The game knows best; if it doesn't say, use the
-- region's usual reset (UTC): Americas Tue 15:00, Europe Wed 04:00, Asia Wed 23:00.
local REGION_RESET = { [1] = { 3, 15 }, [3] = { 4, 4 }, [2] = { 4, 23 }, [4] = { 4, 23 }, [5] = { 4, 23 } }
function Tracker:SecondsUntilReset()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and tonumber((Safe(C_DateAndTime.GetSecondsUntilWeeklyReset)))
    if untilReset and untilReset > 0 then return untilReset, true end
    local region = GetCurrentRegion and tonumber((Safe(GetCurrentRegion))) or 1
    local rule = REGION_RESET[region] or REGION_RESET[1]
    local now = time()
    local utc = date("!*t", now)
    local days = (rule[1] - utc.wday) % 7
    local target = now + days * 86400 + (rule[2] - utc.hour) * 3600 - utc.min * 60 - utc.sec
    if target <= now then target = target + 7 * 86400 end
    return target - now, false
end

function Tracker:UpdateWeekly(rec)
    local week, now = self.db.char.week, time()
    if not week.resetAt or now >= week.resetAt or not week.base then
        -- Keep the week that just ended (for bounties and wagers) before starting a new one.
        if week.resetAt and week.resetAt > 0 and week.base and rec.wk then
            local final = {}
            for _, k in ipairs(FS.COUNTER_KEYS) do
                final[k] = math.max(0, (tonumber(rec[k]) or 0) - (tonumber(week.base[k]) or 0))
            end
            self.db.char.lastWk = { idx = FS.WeekIndex(week.resetAt - 7 * 86400), v = final }
        end
        week.base = {}
        for _, k in ipairs(FS.COUNTER_KEYS) do week.base[k] = tonumber(rec[k]) or 0 end
        week.resetAt = now + self:SecondsUntilReset()
    end
    -- Re-align to the game's own reset timer (region-correct, e.g. Wednesday in EU), in case
    -- the week was ever started from a fallback guess.
    local untilReset = self:SecondsUntilReset()
    if untilReset and untilReset > 0 and math.abs(week.resetAt - (now + untilReset)) > 3600 then
        week.resetAt = now + untilReset
    end
    rec.wk = {}
    for _, k in ipairs(FS.COUNTER_KEYS) do
        rec.wk[k] = math.max(0, (tonumber(rec[k]) or 0) - (tonumber(week.base[k]) or 0))
    end
end

function Tracker:CheckMilestones(rec)
    local c = self.db.char
    local first = not c.milestonesInit
    local batch = {}
    -- Records a step; a stat seen for the first time starts quietly at today's value.
    local function Step(store, key, reached, ev)
        if store[key] == nil then store[key] = reached return end
        if reached > store[key] then
            if not first and ev then table.insert(batch, ev) end
            store[key] = reached
        end
    end

    -- Character milestones
    for _, m in ipairs(MILESTONE_STATS) do
        local key = m[1]
        if FS.STATS[key] then
            local reached = m[2](FS:GetValue(rec, key, "all"))
            Step(c.milestones, key, reached, { kind = "milestone", who = rec.fullName, a = key, v = reached })
        end
    end
    -- Distance, in the chosen unit (each unit keeps its own ladder)
    local imperial = FS.db.profile.distanceUnits == "imperial"
    local perUnit = imperial and 0.9144 or 1
    local unitTag = imperial and ":yd" or ":m"
    local reachedDist = DistLadder(FS:GetValue(rec, "travelTotal", "all") / perUnit, imperial)
    Step(c.milestones, "travelTotal" .. unitTag, reachedDist,
        { kind = "milestone", who = rec.fullName, a = "travelTotal", v = reachedDist * perUnit })
    -- Fun one-offs: a marathon, an ultra, a long-distance legend
    for _, sp in ipairs(SPECIALS) do
        local done = FS:GetValue(rec, sp[2], "all") >= sp[3] and 1 or 0
        Step(c.milestones, "special:" .. sp[1], done, { kind = "milestone", who = rec.fullName, a = sp[1], v = sp[3] })
    end

    -- Account milestones: all your characters in this game together. No toast when only one
    -- character counts, or when this character crossed the number on its own (no double toasts).
    local g = FS.db.global
    g.accMilestones = g.accMilestones or {}
    local acc = g.accMilestones[FS.GAME] or {}
    g.accMilestones[FS.GAME] = acc
    local mine = {}
    for _, r in ipairs(FS:GetScopeCharacters("solo")) do if not r.isMock then table.insert(mine, r) end end
    local function Account(key, ladder, own, toMeters)
        local sum, contributors = 0, 0
        for _, r in ipairs(mine) do
            local v = (toMeters and FS:GetValue(r, "travelTotal", "all") / perUnit) or FS:GetValue(r, key, "all")
            sum = sum + v
            if v > 0 then contributors = contributors + 1 end
        end
        local reached = ladder(sum)
        local storeKey = key .. (toMeters and unitTag or "")
        local ev
        if contributors >= 2 and own < reached then
            ev = { kind = "accmilestone", who = rec.fullName, a = key, v = toMeters and reached * perUnit or reached }
        end
        Step(acc, storeKey, reached, ev)
        if ev == nil and acc[storeKey] and reached > (acc[storeKey] or 0) then acc[storeKey] = reached end
    end
    for _, m in ipairs(MILESTONE_STATS) do
        if FS.STATS[m[1]] then Account(m[1], m[3], FS:GetValue(rec, m[1], "all")) end
    end
    Account("travelTotal", function(u) return AccountDist(u, imperial) end, FS:GetValue(rec, "travelTotal", "all") / perUnit, true)

    -- Several at once (after an update, or a big session): one summary toast instead of many.
    if #batch >= 3 then
        local parts = {}
        for i, ev in ipairs(batch) do
            ev.quiet = true
            FS:AddEvent(ev)
            if i <= 3 then table.insert(parts, FS.W.MilestoneText(ev.a, ev.v)) end
        end
        local want = FS.db.profile.notify.toasts and FS.db.profile.notify.own.milestone ~= false
        if want then
            FS.Extras:ShowToast("Milestones!", string.format("%s %s%s", FS.ShortName(rec.fullName), table.concat(parts, ", "),
                #batch > 3 and string.format(" and %d more", #batch - 3) or ""), "Interface\\Icons\\Achievement_Quests_Completed_08", false)
        end
    else
        for _, ev in ipairs(batch) do FS:AddEvent(ev) end
    end
    if first then c.milestonesInit = true end

    -- GearScore: a toast only at round steps, sized for each game's scale.
    local gs = tonumber(rec.gs) or 0
    local step = FS.GAME_INFO.gsStep or 50
    local reached = math.floor(gs / step) * step
    if c.gsStep == nil then c.gsStep = reached end -- start from today's GearScore, no toast
    if reached > c.gsStep then
        if reached > 0 and rec.highest then
            FS:AddEvent({ kind = "gear", who = rec.fullName, a = rec.highest.link, v = reached, i = rec.ilvl })
        end
        c.gsStep = reached
    end
    if gs > (c.gsBest or 0) then c.gsBest = gs end
end

---------------------------------------------------------------------------
-- Ticker (once per second): travel, flight paths, falling, target deaths
---------------------------------------------------------------------------

function Tracker:Tick()
    local st = self:Stats()

    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if onTaxi then
        st.flightTime = (st.flightTime or 0) + 1
        if not self.wasOnTaxi then st.flightRides = (st.flightRides or 0) + 1 end
    end
    self.wasOnTaxi = onTaxi

    if IsFalling and IsFalling() then self.lastFallingAt = GetTime() end
    self:TrackTravel(st, onTaxi)
    self:CheckTargetDeath()
    self:TickHabits(st)
end

-- Once a second: where you are, when you play, time in combat, ghost runs, how long you've lived.
function Tracker:TickHabits(st)
    local c = self.db.char
    if InCombatLockdown() then
        st.combatTime = (st.combatTime or 0) + 1
        -- Close calls: below 10% health in a fight you survive (Classic games; Retail and Forever hide health).
        if FS.HAS_COMBAT_LOG and UnitHealth and UnitHealthMax then
            local hp, max = Clean(UnitHealth("player")), Clean(UnitHealthMax("player"))
            if hp and max and max > 0 and hp > 0 and hp / max < 0.1 then self.closeCall = true end
        end
    end
    local zone = Clean(GetRealZoneText())
    if type(zone) == "string" and zone ~= "" then
        if c.zoneTime[zone] or self:CountKeys(c.zoneTime) < 150 then c.zoneTime[zone] = (c.zoneTime[zone] or 0) + 1 end
    end
    local hour = tonumber(date("%H")) or 0
    c.hours[hour + 1] = (c.hours[hour + 1] or 0) + 1
    if hour < 5 then st.nightTime = (st.nightTime or 0) + 1 elseif hour < 9 then st.morningTime = (st.morningTime or 0) + 1 end
    local today = date("%Y-%m-%d")
    if not c.days[today] then
        c.days[today] = true
        self:TrimDays()
    end
    local ghost = UnitIsGhost and Clean(UnitIsGhost("player"))
    if ghost and not self.wasGhost then st.corpseRuns = (st.corpseRuns or 0) + 1 end
    self.wasGhost = ghost
    if not UnitIsDeadOrGhost("player") then c.life = (c.life or 0) + 1 end
end

-- Keep the last ~400 days.
function Tracker:TrimDays()
    local days, list = self.db.char.days, {}
    for d in pairs(days) do table.insert(list, d) end
    if #list <= 400 then return end
    table.sort(list)
    for i = 1, #list - 400 do days[list[i]] = nil end
end

-- Daily streaks, counted back from today.
function Tracker:Streaks()
    local days = self.db.char.days
    local current, t = 0, time()
    while days[date("%Y-%m-%d", t)] do current = current + 1; t = t - 86400 end
    local list, best, run, prev = {}, 0, 0, nil
    for d in pairs(days) do table.insert(list, d) end
    table.sort(list)
    for _, d in ipairs(list) do
        local y, m, dd = d:match("(%d+)-(%d+)-(%d+)")
        local stamp = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
        run = (prev and math.abs(stamp - prev - 86400) < 7200) and run + 1 or 1
        best, prev = math.max(best, run), stamp
    end
    return current, math.max(best, current), #list
end

function Tracker:Daily()
    local c, today = self.db.char, date("%Y-%m-%d")
    local d = c.daily[today]
    if not d then
        d = { levels = 0, gold = 0 }
        c.daily[today] = d
        local list = {}
        for k in pairs(c.daily) do table.insert(list, k) end
        table.sort(list)
        for i = 1, #list - 60 do c.daily[list[i]] = nil end
    end
    return d
end

function Tracker:TrackTravel(st, onTaxi)
    local ghost = UnitIsGhost and Clean(UnitIsGhost("player"))
    if not UnitPosition or (UnitIsDeadOrGhost("player") and not ghost) then self.posValid = false return end
    local y, x, _, instanceID = UnitPosition("player")
    if not y or IsSecret(y) or IsSecret(x) then self.posValid = false return end
    local p = self.pos or {}
    self.pos = p
    if self.posValid and p.inst == instanceID then
        local dx, dy = x - p.x, y - p.y
        local yards = math.sqrt(dx * dx + dy * dy)
        if yards > 0.5 and yards < 250 then
            local meters = yards * 0.9144
            if ghost then
                st.corpseDistance = (st.corpseDistance or 0) + meters
            elseif onTaxi or (IsFlying and IsFlying()) then
                st.travelFlight = (st.travelFlight or 0) + meters
            elseif IsSwimming and IsSwimming() then
                st.travelSwim = (st.travelSwim or 0) + meters
            elseif IsMounted and IsMounted() then
                st.travelMount = (st.travelMount or 0) + meters
            else
                st.travelFoot = (st.travelFoot or 0) + meters
            end
        end
    end
    p.x, p.y, p.inst = x, y, instanceID
    self.posValid = true
end

---------------------------------------------------------------------------
-- Kill tracking (the "Enemies" board / bestiary).
-- Without the combat log, we watch your target and every enemy nameplate.
-- When one of them dies and was tagged by you or your group (not "tap denied"),
-- it counts once. Each creature GUID is only ever counted once.
---------------------------------------------------------------------------

function Tracker:WatchUnit(unit)
    if not UnitExists(unit) then self.watched[unit] = nil return end
    local guid = Clean(UnitGUID(unit))
    local name = Clean(UnitName(unit))
    if not guid or not name or Clean(UnitIsDead(unit)) then self.watched[unit] = nil return end
    local w = self.watched[unit]
    if w and w.guid == guid then return w end
    local class = Clean(UnitClassification(unit))
    -- Boss: flagged by the game, or a world boss. A "??" level alone is not enough,
    -- because low-level characters see ?? on ordinary high-level mobs.
    local isBoss = class == "worldboss"
    if UnitIsBossMob then
        isBoss = isBoss or (Clean(UnitIsBossMob(unit)) and true or false)
    else
        isBoss = isBoss or (Clean(UnitLevel(unit)) == -1 and class == "elite")
    end
    w = { guid = guid, name = name, hostile = Clean(UnitCanAttack("player", unit)) and true or false,
          isPlayer = Clean(UnitIsPlayer(unit)) and true or false, boss = isBoss,
          critter = Clean(UnitCreatureType(unit)) == "Critter", level = Clean(UnitLevel(unit)) }
    self.watched[unit] = w
    -- Remember what we saw about this creature (the combat log only gives a GUID and a name).
    if not self.guidInfo[guid] then
        self.guidCount = self.guidCount + 1
        if self.guidCount > 500 then self.guidInfo, self.guidCount = {}, 1 end
        self.guidInfo[guid] = w
    end
    return w
end

function Tracker:CheckUnitDeath(unit)
    local w = self.watched[unit]
    if not w then return end
    local guid = Clean(UnitGUID(unit))
    if guid ~= w.guid then self:WatchUnit(unit) return end
    if Clean(UnitIsDead(unit)) then
        self.watched[unit] = nil
        if self.useCombatLog then return end -- the combat log counts kills exactly
        if w.hostile and not w.isPlayer and not Clean(UnitIsTapDenied(unit)) then
            self:CountKill(guid, w.name, w.boss)
        end
    end
end

function Tracker:CountKill(guid, name, isBoss)
    local now = GetTime()
    if self.counted[guid] then return end
    self.counted[guid] = now
    local c = self.db.char
    local mobs = c.mobs
    mobs[name] = (mobs[name] or 0) + 1
    if not c.mobFirst[name] then c.mobFirst[name] = time() end
    if isBoss and not c.firsts["boss:" .. name] then
        c.firsts["boss:" .. name] = time()
        FS:AddEvent({ kind = "boss", who = FS:GetPlayerKey(), a = name })
    end
    self.killsSinceTrim = (self.killsSinceTrim or 0) + 1
    if self.killsSinceTrim > 200 then -- forget old GUIDs now and then
        self.killsSinceTrim = 0
        for g, t in pairs(self.counted) do if now - t > 600 then self.counted[g] = nil end end
    end
end

function Tracker:NAME_PLATE_UNIT_ADDED(_, unit) self:WatchUnit(unit) end

function Tracker:NAME_PLATE_UNIT_REMOVED(_, unit)
    self:CheckUnitDeath(unit) -- plates vanish when the mob dies; check before forgetting it
    self.watched[unit] = nil
end

function Tracker:PLAYER_TARGET_CHANGED()
    local w = self:WatchUnit("target")
    if w and w.hostile then
        self.lastHostile = { name = w.name, desc = self:DescribeTarget(), at = GetTime() }
    end
end

function Tracker:CheckTargetDeath()
    if not self.watched then return end
    if self.watched.target then
        self:CheckUnitDeath("target")
    end
    local w = self:WatchUnit("target")
    if w and w.hostile and self.lastHostile and self.lastHostile.name == w.name then
        self.lastHostile.at = GetTime()
    end
end

function Tracker:TrimCounts(map, keep)
    local list = {}
    for k, v in pairs(map) do table.insert(list, { k = k, v = v }) end
    if #list <= keep then return end
    table.sort(list, function(a, b) return a.v > b.v end)
    for i = keep + 1, #list do map[list[i].k] = nil end
end

function Tracker:DescribeTarget()
    local level = Clean(UnitLevel("target"))
    local lvlText = (level and level > 0) and tostring(level) or "??"
    if Clean(UnitIsPlayer("target")) then
        local race = Clean((UnitRace("target"))) or ""
        local cls = Clean((UnitClass("target"))) or ""
        return string.format("Lvl %s %s %s", lvlText, race, cls)
    end
    local class = Clean(UnitClassification("target")) or "normal"
    local tag = (class == "worldboss" and "Boss") or ((class == "elite" or class == "rareelite") and "Elite")
        or (class == "rare" and "Rare") or (Clean(UnitCreatureType("target")) or "")
    return string.format("Lvl %s %s", lvlText, tag)
end

---------------------------------------------------------------------------
-- Deaths
---------------------------------------------------------------------------

function Tracker:MIRROR_TIMER_START(_, timer) if timer == "BREATH" then self.breathActive = true end end
function Tracker:MIRROR_TIMER_STOP(_, timer) if timer == "BREATH" then self.breathActive = false end end

function Tracker:GuessKiller()
    local hit = self.CombatLog and self.CombatLog.lastHit
    if self.useCombatLog and hit and GetTime() - hit.at < 8 then
        local info = hit.guid and self.guidInfo[hit.guid]
        local desc = hit.spell and hit.spell ~= "" and string.format("%s, %s damage", hit.spell, tostring(hit.amount)) or ""
        if info and info.level then desc = string.format("Lvl %s - %s", info.level > 0 and info.level or "??", desc) end
        return hit.name, desc
    end
    if GetTime() - (self.lastFallingAt or -100) < 3 then return "Falling", "Gravity always wins" end
    if self.breathActive then return "Drowning", "Ran out of breath" end
    if UnitExists("target") and Clean(UnitCanAttack("player", "target")) and not Clean(UnitIsDead("target")) then
        local name = Clean(UnitName("target"))
        if name then return name, self:DescribeTarget() end
    end
    local h = self.lastHostile
    if h and GetTime() - h.at < 30 then return h.name, h.desc end
    return "Unknown", ""
end

function Tracker:PLAYER_DEAD()
    local c = self.db.char
    local killer, desc = self:GuessKiller()
    local entry = {
        t = time(), zone = GetRealZoneText() or "Unknown", killer = killer, kdesc = desc,
        lvl = UnitLevel("player"),
        words = (self.lastWords and time() - (self.lastWordsAt or 0) < 900) and self.lastWords or nil,
    }
    -- Where exactly (for the Deathmap). Not available inside instances.
    local mapID = C_Map and C_Map.GetBestMapForUnit and Clean(Safe(C_Map.GetBestMapForUnit, "player"))
    local pos = mapID and C_Map.GetPlayerMapPosition and Safe(C_Map.GetPlayerMapPosition, mapID, "player")
    if pos and pos.GetXY then
        local x, y = Safe(pos.GetXY, pos)
        if Clean(x) and Clean(y) and x > 0 and y > 0 then
            entry.map, entry.x, entry.y = mapID, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
        end
    end
    table.insert(c.deathLog, 1, entry)
    for i = #c.deathLog, 11, -1 do c.deathLog[i] = nil end
    c.killers[killer] = (c.killers[killer] or 0) + 1
    self:TrimCounts(c.killers, 10)
    self:Add("deaths")
    if killer == "Falling" then self:Add("fallDeaths") end
    local rec = c.records
    rec.longestLife = math.max(tonumber(rec.longestLife) or 0, tonumber(c.life) or 0)
    c.life = 0
    self.closeCall = false
    FS:AddEvent({ kind = "death", who = FS:GetPlayerKey(), a = killer, z = entry.zone, t = entry.t })
    if self:IsHardcore() and not c.hc then
        c.hc = { t = entry.t, zone = entry.zone, killer = killer, kdesc = desc, lvl = entry.lvl, words = entry.words,
                 played = tonumber(self:Stats().playtime) or 0, map = entry.map, x = entry.x, y = entry.y }
        FS:AddEvent({ kind = "fallen", who = FS:GetPlayerKey(), a = killer, z = entry.zone, v = entry.lvl, t = entry.t })
    end
    self:Snapshot()
end

---------------------------------------------------------------------------
-- Loot, money, repairs, fishing, rolls, duels, crafting
---------------------------------------------------------------------------

function Tracker:CHAT_MSG_LOOT(_, msg)
    if type(msg) ~= "string" or IsSecret(msg) then return end
    -- Multi-item patterns first: "%s." would otherwise swallow the "x5" into the item name.
    local args = MatchFormat(msg, LOOT_ITEM_SELF_MULTIPLE) or MatchFormat(msg, LOOT_ITEM_SELF)
    if args and args[1] then
        local q = ItemQuality(args[1])
        local n = tonumber(args[2]) or 1
        if q and q >= 4 then self:Add("epics", n) end
        if q and q ~= 4 and q <= 5 then self:Add("lootQ" .. q, n) end
        return
    end
    args = MatchFormat(msg, LOOT_ITEM_CREATED_SELF_MULTIPLE) or MatchFormat(msg, LOOT_ITEM_CREATED_SELF)
    if args then self:Add("crafted", tonumber(args[2]) or 1) return end
    -- Need / Greed / Pass: remember what we picked per item, to know how a win was made.
    self.rollPick = self.rollPick or {}
    local function Picked(fmt, kind, stat)
        local a = fmt and MatchFormat(msg, fmt)
        if not a then return false end
        self:Add(stat)
        if a[1] then self.rollPick[a[1]] = kind end
        return true
    end
    if Picked(LOOT_ROLL_NEED_SELF, "need", "needRolls") or Picked(LOOT_ROLL_GREED_SELF, "greed", "greedRolls")
        or Picked(LOOT_ROLL_DISENCHANT_SELF, "greed", "greedRolls") or Picked(LOOT_ROLL_PASSED_SELF, "pass", "passRolls")
        or Picked(LOOT_ROLL_PASSED_SELF_AUTO, "pass", "passRolls") then
        return
    end
    local won = LOOT_ROLL_YOU_WON and MatchFormat(msg, LOOT_ROLL_YOU_WON)
    if won then
        self:Add("rollsWon")
        local kind = won[1] and self.rollPick[won[1]]
        if kind == "need" then self:Add("wonNeed") elseif kind == "greed" then self:Add("wonGreed") end
        if won[1] then self.rollPick[won[1]] = nil end
    end
end

function Tracker:CHAT_MSG_SYSTEM(_, msg)
    if type(msg) ~= "string" or IsSecret(msg) then return end
    self:OnInfoText(msg)
    local roll = MatchFormat(msg, RANDOM_ROLL_RESULT)
    if roll and FS:IsMe(roll[1]) then
        self:Add("rollsTotal")
        local value, low, high = tonumber(roll[2]), tonumber(roll[3]), tonumber(roll[4])
        if low == 1 and high == 100 then
            if value == 100 then self:Add("rolls100") elseif value == 1 then self:Add("rolls1") end
        end
        return
    end
    for _, fmt in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
        local duel = MatchFormat(msg, fmt)
        if duel then
            if FS:IsMe(duel[1]) then self:Add("duelsWon") elseif FS:IsMe(duel[2]) then self:Add("duelsLost") end
            return
        end
    end
end

function Tracker:LOOT_READY()
    if IsFishingLoot and IsFishingLoot() then
        local count = 0
        for i = 1, (GetNumLootItems() or 0) do
            local _, _, quantity = GetLootSlotInfo(i)
            count = count + (tonumber(quantity) or 1)
        end
        if count > 0 then self:Add("fish", count) end
    end
end

function Tracker:LOOT_OPENED() self.lootOpen, self.lootMoney = true, GetMoney() end
function Tracker:LOOT_CLOSED() self.lootOpen = false end

function Tracker:PLAYER_MONEY()
    local now = GetMoney() or 0
    local delta = now - (self.lastMoney or now)
    self.lastMoney = now
    if delta > 0 then
        self:Add("moneyIn", delta)
        local d = self:Daily()
        d.gold = d.gold + delta
        if self.atMerchant then self:Add("vendorSales", delta) end
        if self.lootOpen and delta > (tonumber(self:Stats().biggestLoot) or 0) then self:Stats().biggestLoot = delta end
    elseif delta < 0 then
        self:Add("moneyOut", -delta)
        if self.atMerchant then self.merchantSpent = (self.merchantSpent or 0) - delta end
    end
    if self.lootOpen then
        local now = GetMoney()
        if now > (self.lootMoney or now) then self:Add("goldLooted", now - self.lootMoney) end
        self.lootMoney = now
    end
end

function Tracker:MERCHANT_SHOW()
    self.atMerchant, self.merchantSpent, self.merchantRepairs = true, 0, 0
    self.repairCost = (GetRepairAllCost and GetRepairAllCost()) or 0
end
function Tracker:MERCHANT_CLOSED()
    -- Money spent at the vendor, minus repairs (counted separately).
    if self.atMerchant then
        self:Add("vendorSpent", math.max(0, (self.merchantSpent or 0) - (self.merchantRepairs or 0)))
    end
    self.atMerchant = false
    self:Snapshot()
end

function Tracker:UPDATE_INVENTORY_DURABILITY()
    if not self.atMerchant or not GetRepairAllCost then return end
    local cost = GetRepairAllCost() or 0
    if cost < (self.repairCost or 0) then
        self:Add("repairs", self.repairCost - cost)
        self.merchantRepairs = (self.merchantRepairs or 0) + (self.repairCost - cost)
    end
    self.repairCost = cost
end

local GATHER_SPELLS = { 2575, 2366, 8613 } -- Mining, Herb Gathering, Skinning
function Tracker:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if unit ~= "player" or IsSecret(spellID) then return end
    local cast = SpellName(spellID)
    if cast and (cast == SpellName(8690) or cast == "Hearthstone") then self:Add("hearths") end
    if not self.gatherNames then
        self.gatherNames = { Mining = true, ["Herb Gathering"] = true, Skinning = true }
        for _, id in ipairs(GATHER_SPELLS) do
            local n = SpellName(id)
            if n then self.gatherNames[n] = true end
        end
    end
    local name = SpellName(spellID)
    if name and self.gatherNames[name] then self:Add("gathered") end
end

function Tracker:QUEST_TURNED_IN(_, _, _, money)
    self:Add("quests")
    money = Clean(money)
    if tonumber(money) and money > 0 then self:Add("goldQuests", money) end
end

-- Combat, info messages, whispers, spirit healer, battlegrounds.
function Tracker:PLAYER_REGEN_DISABLED() self:Add("fights"); self.closeCall = false end

function Tracker:OnInfoText(msg)
    if type(msg) ~= "string" or IsSecret(msg) then return end
    if ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then self:Add("flightPathsFound")
    elseif ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then self:Add("trades")
    elseif MatchFormat(msg, ERR_ZONE_EXPLORED) or MatchFormat(msg, ERR_ZONE_EXPLORED_XP) then self:Add("areasDiscovered") end
end
function Tracker:UI_INFO_MESSAGE(_, a, b) self:OnInfoText(type(a) == "string" and a or b) end

function Tracker:CHAT_MSG_WHISPER() self:Add("whispersReceived") end
function Tracker:CHAT_MSG_BN_WHISPER() self:Add("whispersReceived") end
function Tracker:RESURRECT_REQUEST() self:Add("rezzed") end
function Tracker:CONFIRM_XP_LOSS() self.spiritAt = GetTime() end
function Tracker:PLAYER_UNGHOST()
    if self.spiritAt and GetTime() - self.spiritAt < 120 then self:Add("spiritHealer") end
    self.spiritAt = nil
end
function Tracker:PLAYER_ALIVE() self:PLAYER_UNGHOST() end

function Tracker:UPDATE_BATTLEFIELD_SCORE()
    local winner = GetBattlefieldWinner and Clean(GetBattlefieldWinner())
    if winner == nil or self.bgCounted then return end
    self.bgCounted = true
    self:Add("bgPlayed")
    local mine = (UnitFactionGroup("player") == "Horde") and 0 or 1
    if winner == mine then self:Add("bgWon") end
end

function Tracker:CHAT_MSG_SKILL()
    if self.profTimer then return end
    self.profTimer = FS:ScheduleTimer(function() self.profTimer = nil; self:ScanProfessions() end, 2)
end

---------------------------------------------------------------------------
-- Level, achievements, AFK, playtime, login
---------------------------------------------------------------------------

function Tracker:PLAYER_LEVEL_UP(_, level)
    level = tonumber(level)
    if not level then return end
    -- Dated in played time. (Right after login the played-time report that
    -- follows dates the current level instead.)
    local day = self:Daily()
    day.levels = day.levels + 1
    local played = self:PlayedNow()
    local times = self.db.char.levelTimes
    if played and not times[level] then times[level] = math.floor(played) end
    for _, th in ipairs(LevelStamps()) do
        if level >= th and not self.db.char.firsts["lv" .. th] then self.db.char.firsts["lv" .. th] = time() end
    end
    FS:AddEvent({ kind = "level", who = FS:GetPlayerKey(), v = level })
    FS:ScheduleTimer(function() self:Snapshot() end, 2)
end

function Tracker:ACHIEVEMENT_EARNED(_, id)
    local _, name, points = Safe(GetAchievementInfo, id)
    if name then
        FS:AddEvent({ kind = "legacy", who = FS:GetPlayerKey(), a = name, lp = tonumber(points) or 0 })
    end
    self:ScanLegacy()
end

function Tracker:PLAYER_FLAGS_CHANGED(_, unit)
    if unit ~= "player" then return end
    local afk = Clean(UnitIsAFK("player"))
    if afk and not self.afkSince then
        self.afkSince = GetTime()
    elseif not afk and self.afkSince then
        self:Add("afk", math.floor((GetTime() - self.afkSince) / 60))
        self.afkSince = nil
    end
end

function Tracker:TIME_PLAYED_MSG(_, total, atLevel)
    if IsSecret(total) then return end
    total, atLevel = tonumber(total), tonumber(atLevel)
    if not total then return end
    self:Stats().playtime = math.floor(total)
    -- Keep a played-time clock running from here, for timing level-ups exactly.
    self.playedBase, self.playedAt = total, GetTime()
    local times = self.db.char.levelTimes
    if atLevel then
        self.db.char.playtimeLevel = math.floor(atLevel)
        local level = UnitLevel("player")
        if level and not times[level] then times[level] = math.floor(total - atLevel) end
    end
end

-- Played seconds right now (needs one TIME_PLAYED_MSG this session).
function Tracker:PlayedNow()
    if not self.playedBase then return nil end
    return self.playedBase + (GetTime() - self.playedAt)
end

---------------------------------------------------------------------------
-- Dungeons and raids: every boss fight is reported by the game, in all versions.
---------------------------------------------------------------------------

local function InstanceName()
    local name = GetInstanceInfo and Clean((GetInstanceInfo()))
    return type(name) == "string" and name or "Unknown"
end

function Tracker:ENCOUNTER_START(_, _, name)
    if type(name) ~= "string" or IsSecret(name) then return end
    self.encounter = { name = name, start = GetTime(), instance = InstanceName() }
end

function Tracker:ENCOUNTER_END(_, _, name, _, _, success)
    if type(name) ~= "string" or IsSecret(name) or IsSecret(success) then return end
    local c = self.db.char
    local e = c.encounters[name]
    if not e then
        local n = 0
        for _ in pairs(c.encounters) do n = n + 1 end
        if n >= 300 then return end
        e = { instance = InstanceName(), kills = 0, wipes = 0 }
        c.encounters[name] = e
    end
    local fight = self.encounter
    local duration = (fight and fight.name == name) and math.floor(GetTime() - fight.start + 0.5) or nil
    self.encounter = nil
    if success == 1 or success == true then
        e.kills = e.kills + 1
        if duration and duration > 0 and (not e.best or duration < e.best) then
            if e.best then -- faster than your previous best (the first kill is its own event)
                FS:AddEvent({ kind = "record", who = FS:GetPlayerKey(), a = name, v = duration, z = e.instance })
            end
            e.best = duration
        end
        e.first = e.first or time()
        self:Add("bossKills")
        if not c.firsts["boss:" .. name] then
            c.firsts["boss:" .. name] = time()
            FS:AddEvent({ kind = "boss", who = FS:GetPlayerKey(), a = name })
        end
    else
        e.wipes = e.wipes + 1
        self:Add("wipes")
    end
end

function Tracker:PLAYER_ENTERING_WORLD(_, isLogin, isReload)
    self.posValid = false
    self.bgCounted = false
    self.lastMoney = GetMoney()
    local c = self.db.char
    if isLogin then
        self:Add("sessions")
        c.sessionStart = time()
        self.sessionKills = tonumber(self:Stats().kills) or 0
    elseif isReload then
        self:Add("reloads")
    end
    c.sessionStart = c.sessionStart or time()
    self.sessionKills = self.sessionKills or tonumber(self:Stats().kills) or 0
    -- Dungeon / raid visits (re-entering the same instance within 30 minutes is the same visit).
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then
        local name = GetInstanceInfo and Clean((GetInstanceInfo()))
        local last = c.lastInstance
        if type(name) == "string" and not (last and last.name == name and time() - last.t < 1800) then
            self:Add("instanceRuns")
            if c.instances[name] or self:CountKeys(c.instances) < 150 then c.instances[name] = (c.instances[name] or 0) + 1 end
        end
        if type(name) == "string" then c.lastInstance = { name = name, t = time() } end
    elseif c.lastInstance then
        c.lastInstance.t = time()
    end
    FS:ScheduleTimer(function() self:ScanProfessions(); self:Snapshot(); FS:RefreshUIIfShown() end, 3)
    if isLogin or isReload then
        FS:ScheduleTimer(function() if RequestTimePlayed then RequestTimePlayed() end end, 10)
        FS:ScheduleTimer(function() FS.Comm:BroadcastStats(false) end, 20)
    elseif FS.Comm.pending then
        FS:ScheduleTimer(function() FS.Comm:BroadcastStats(false) end, 10)
    end
end

function Tracker:PLAYER_REGEN_ENABLED()
    if self.closeCall and not UnitIsDeadOrGhost("player") then self:Add("closeCalls") end
    self.closeCall = false
    FS:ScheduleTimer(function() self:Snapshot() end, 2)
    if FS.Comm.pending then FS:ScheduleTimer(function() FS.Comm:BroadcastStats(false) end, 5) end
end

function Tracker:PLAYER_EQUIPMENT_CHANGED()
    if self.gearTimer then return end
    self.gearTimer = FS:ScheduleTimer(function() self.gearTimer = nil; self:Snapshot(); FS:RefreshUIIfShown() end, 2)
end

function Tracker:PLAYER_LOGOUT()
    if self.afkSince then
        self:Add("afk", math.floor((GetTime() - self.afkSince) / 60))
        self.afkSince = nil
    end
    self:Snapshot()
end
