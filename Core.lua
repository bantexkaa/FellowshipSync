local addonName, addonTable = ...
if addonTable.libsMissing then return end -- Bootstrap.lua explains what's missing

local FellowshipSync = LibStub("AceAddon-3.0"):NewAddon("FellowshipSync",
    "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")
addonTable.FellowshipSync = FellowshipSync
_G.FellowshipSync = FellowshipSync -- for the addon compartment / debugging
local L = addonTable.L or {}

for _, m in ipairs({ "UI", "W", "Tracker", "Comm", "Dashboard", "Inspector", "Deathlog", "Combat",
                     "Misc", "Profiles", "FactionWar", "Chronicle", "Options", "Extras", "Notify",
                     "Fellowship", "Deathmap", "FellowshipUI", "Records", "Games", "Setup", "Style", "Officer", "GuildUI", "Share" }) do
    FellowshipSync[m] = FellowshipSync[m] or {}
end

---------------------------------------------------------------------------
-- Which game are we in? Detected from the interface number (one range per
-- game); WoW: Forever also reports its own project ("Camelot").
--   retail 12.x | forever 1.60 (16xxx) | era 1.15 (11xxx) | tbc 2.5 (20xxx) | mists 5.5 (50xxx)
---------------------------------------------------------------------------
local tocVersion = select(4, GetBuildInfo()) or 0
local function DetectGame()
    if (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT) or (tocVersion >= 16000 and tocVersion < 17000) then
        return "forever"
    end
    if tocVersion >= 100000 then return "retail" end
    if tocVersion >= 50000 and tocVersion < 60000 then return "mists" end
    if tocVersion >= 20000 and tocVersion < 30000 then return "tbc" end
    if tocVersion >= 10000 and tocVersion < 20000 then return "era" end
    return "retail"
end

-- What each game offers addons.
--   combatLog:    addons may read COMBAT_LOG_EVENT_UNFILTERED (not on Retail 12.x or Forever)
--   achievements: achievement + statistics API exists
--   ilvlTop:      roughly the best item level, used to colour GearScore
--   levels:       level steps that are stamped for Guild Firsts (max level is always included)
local GAMES = {
    -- profSteps: profession ranks that count as milestones; the last one is "maxed".
    -- Retail professions are split per expansion (100 ranks each); Archaeology is not.
    retail  = { name = "Retail",                    achievements = true,  combatLog = false, ilvlTop = 290, maxLevel = 90,
                splits = { 20, 40, 60, 80, 90 }, profSteps = { 25, 50, 75, 100 }, gsStep = 250 },
    forever = { name = "WoW: Forever",              achievements = true,  combatLog = false, ilvlTop = 66,  maxLevel = 60, levels = { 25, 45 },
                splits = { 10, 20, 30, 40, 50, 60 }, profSteps = { 50, 100, 150, 200, 250, 300 }, gsStep = 50 },
    era     = { name = "Classic Era",               achievements = false, combatLog = true,  ilvlTop = 66,  maxLevel = 60,
                splits = { 10, 20, 30, 40, 50, 60 }, profSteps = { 50, 100, 150, 200, 250, 300 }, gsStep = 50 },
    tbc     = { name = "TBC Anniversary",           achievements = false, combatLog = true,  ilvlTop = 141, maxLevel = 70, levels = { 60 },
                splits = { 20, 40, 60, 65, 70 }, profSteps = { 50, 100, 150, 200, 250, 300, 350, 375 }, gsStep = 100 },
    mists   = { name = "Mists of Pandaria Classic", achievements = true,  combatLog = true,  ilvlTop = 496, maxLevel = 90, levels = { 85 },
                splits = { 20, 40, 60, 80, 85, 90 }, profSteps = { 50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600 }, gsStep = 250 },
}
FellowshipSync.GAME = DetectGame()
FellowshipSync.GAME_INFO = GAMES[FellowshipSync.GAME]
FellowshipSync.IS_FOREVER = FellowshipSync.GAME == "forever"
FellowshipSync.HAS_COMBAT_LOG = FellowshipSync.GAME_INFO.combatLog
FellowshipSync.HAS_POINTS = FellowshipSync.GAME_INFO.achievements

-- Forever: Legacy Points from Legacy Challenges. Retail and Mists: Achievement
-- Points. Classic Era and TBC have no achievements, so points are hidden there.
if FellowshipSync.IS_FOREVER then
    FellowshipSync.POINTS = { long = "Legacy Points", short = "LP", item = "Legacy Challenge", items = "Legacy Challenges", feed = "Legacy Points & Milestones", tab = "Legacy" }
elseif FellowshipSync.HAS_POINTS then
    FellowshipSync.POINTS = { long = "Achievement Points", short = "AP", item = "Achievement", items = "Achievements", feed = "Achievements & Milestones", tab = "Achievements" }
else
    FellowshipSync.POINTS = { long = "Milestones", short = "", item = "Milestone", items = "Milestones", feed = "Milestones", tab = "Milestones" }
end

-- "2.10.0" > "2.9.3": compares number by number.
function FellowshipSync.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- Someone uses a newer version: tell the player once per session.
function FellowshipSync:NoteVersion(version, who)
    -- Only plausible version numbers: "2.7" or "2.7.0", each part below 1000.
    if type(version) ~= "string" or #version > 11 then return end
    local parts = { version:match("^(%d+)%.(%d+)%.?(%d*)$") }
    if #parts == 0 then return end
    for _, n in ipairs(parts) do if n ~= "" and tonumber(n) >= 1000 then return end end
    if self.CompareVersions(version, self.VERSION) <= 0 then return end
    if self.newestSeen and self.CompareVersions(version, self.newestSeen) <= 0 then return end
    self.newestSeen, self.newestSeenBy = version, who
    if self.Notify.VersionNotice then self.Notify:VersionNotice(version, who) end
    self:Print(string.format("A newer version of FellowshipSync (%s) is in use%s. You have %s - update it on CurseForge to keep everything in sync.",
        version, who and (" by " .. who) or "", self.VERSION))
end

-- Highest profession rank in this game (Retail: per expansion).
function FellowshipSync.ProfMax()
    local steps = FellowshipSync.GAME_INFO.profSteps
    return steps[#steps]
end

function FellowshipSync:MaxLevel()
    local ok, n = pcall(GetMaxPlayerLevel or function() end)
    n = ok and tonumber(n)
    return (n and n > 0) and n or self.GAME_INFO.maxLevel
end

-- Registers a game event only if this client has it (older clients lack some,
-- and registering an unknown event is an error).
function FellowshipSync.SafeRegister(obj, event, handler)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    local ok = pcall(obj.RegisterEvent, obj, event, handler)
    return ok
end

local DB_VERSION = 3
FellowshipSync.COMM_PREFIX = "FSYNC_V1"
-- The version comes from the .toc, where the release packager writes the tag (v3.6.2 -> 3.6.2).
-- An unpackaged copy still says "@project-version@", so fall back to the number below.
local FALLBACK_VERSION = "3.7.1"
do
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(addonName or "FellowshipSync", "Version")
    v = type(v) == "string" and v:match("^v?(%d+%.%d+%.?%d*)") or nil
    FellowshipSync.VERSION = v or FALLBACK_VERSION
end

-- The 16 slots shown in the inspector (shirt and tabard are cosmetic and skipped).
FellowshipSync.GEAR_SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand"
}
FellowshipSync.SLOT_LABELS = {
    Head = "Head", Neck = "Neck", Shoulder = "Shoulder", Back = "Back", Chest = "Chest",
    Wrist = "Wrist", Hands = "Hands", Waist = "Waist", Legs = "Legs", Feet = "Feet",
    Finger0 = "Ring 1", Finger1 = "Ring 2", Trinket0 = "Trinket 1", Trinket1 = "Trinket 2",
    MainHand = "Main Hand", SecondaryHand = "Off Hand"
}

---------------------------------------------------------------------------
-- STAT REGISTRY: one place that describes every number the addon shows.
--   fmt:    how the value is displayed (see W.FormatStat)
--   weekly: counter that also has a "This Week" value
--   agg:    how Network Accounts combines characters ("sum" default, or "max")
--   lower:  smaller is better (Faction War)
---------------------------------------------------------------------------
FellowshipSync.STATS = {
    gs          = { label = "GearScore",          fmt = "gs",       agg = "max" },
    ilvl        = { label = "Equipped iLvl",      fmt = "ilvl",     agg = "max" },
    ilvlBag     = { label = "Overall iLvl",       fmt = "ilvl",     agg = "max" },
    level       = { label = "Level",              fmt = "num",      agg = "max" },
    legacy      = { label = FellowshipSync.POINTS.long, fmt = "lp", agg = "max" }, -- LP on Forever, AP on Retail
    playtime    = { label = "Playtime",           fmt = "duration", weekly = true },
    kills       = { label = "Total Kills",        fmt = "num",      weekly = true },
    deaths      = { label = "Deaths",             fmt = "num",      weekly = true, lower = true },
    damage      = { label = "Total Damage",       fmt = "short",    weekly = true },
    healing     = { label = "Healing Done",       fmt = "short",    weekly = true },
    crit        = { label = "Largest Hit",        fmt = "num",      agg = "max" },
    critters    = { label = "Critters Butchered", fmt = "num",      weekly = true },
    repairs     = { label = "Repair Bills",       fmt = "money",    weekly = true },
    fallDeaths  = { label = "Deaths by Falling",  fmt = "num",      weekly = true, lower = true },
    fallDamage  = { label = "Fall Damage Taken",  fmt = "num",      weekly = true },
    jumps       = { label = "Total Jumps",        fmt = "num",      weekly = true },
    epics       = { label = "Epics Looted",       fmt = "num",      weekly = true },
    goldLooted  = { label = "Gold Looted",        fmt = "money",    weekly = true },
    wealth      = { label = "Gold on Hand",       fmt = "money" },
    quests      = { label = "Quests Done",        fmt = "num",      weekly = true },
    fish        = { label = "Fish Caught",        fmt = "num",      weekly = true },
    chat        = { label = "Chat Messages",      fmt = "num",      weekly = true },
    afk         = { label = "AFK Time",           fmt = "minutes",  weekly = true },
    flightTime  = { label = "Flight Time",        fmt = "duration", weekly = true },
    flightRides = { label = "Flights Taken",      fmt = "num",      weekly = true },
    travelFoot  = { label = "Distance on Foot",   fmt = "distance", weekly = true },
    travelMount = { label = "Distance Mounted",   fmt = "distance", weekly = true },
    travelFlight= { label = "Distance Flying",    fmt = "distance", weekly = true },
    -- Calculated (foot + mounted + flying), never stored or synced on its own.
    travelTotal = { label = "Total Distance",     fmt = "distance", weekly = true, derived = true },
    duelsWon    = { label = "Duels Won",          fmt = "num",      weekly = true },
    duelsLost   = { label = "Duels Lost",         fmt = "num",      weekly = true, lower = true },
    rollsWon    = { label = "Loot Rolls Won",     fmt = "num",      weekly = true },
    needRolls   = { label = "Need Rolls",         fmt = "num",      weekly = true },
    greedRolls  = { label = "Greed Rolls",        fmt = "num",      weekly = true },
    passRolls   = { label = "Passed Rolls",       fmt = "num",      weekly = true },
    wonNeed     = { label = "Won on Need",        fmt = "num",      weekly = true },
    wonGreed    = { label = "Won on Greed",       fmt = "num",      weekly = true },
    rollsTotal  = { label = "/roll Used",         fmt = "num",      weekly = true },
    rolls100    = { label = "Natural 100s",       fmt = "num",      weekly = true },
    rolls1      = { label = "Natural 1s",         fmt = "num",      weekly = true },
    gathered    = { label = "Nodes Gathered",     fmt = "num",      weekly = true },
    bossKills   = { label = "Boss Kills",         fmt = "num",      weekly = true },
    wipes       = { label = "Wipes",              fmt = "num",      weekly = true, lower = true },
    -- Travel & world
    travelSwim       = { label = "Distance Swimming",   fmt = "distance", weekly = true },
    corpseRuns       = { label = "Corpse Runs",         fmt = "num",      weekly = true },
    corpseDistance   = { label = "Distance as a Ghost", fmt = "distance", weekly = true },
    hearths          = { label = "Hearthstone Uses",    fmt = "num",      weekly = true },
    flightPathsFound = { label = "Flight Paths Found",  fmt = "num",      weekly = true },
    areasDiscovered  = { label = "Areas Discovered",    fmt = "num",      weekly = true },
    instanceRuns     = { label = "Dungeon & Raid Visits", fmt = "num",    weekly = true },
    -- Loot & gold
    lootQ0       = { label = "Poor Items Looted",     fmt = "num",   weekly = true },
    lootQ1       = { label = "Common Items Looted",   fmt = "num",   weekly = true },
    lootQ2       = { label = "Uncommon Items Looted", fmt = "num",   weekly = true },
    lootQ3       = { label = "Rare Items Looted",     fmt = "num",   weekly = true },
    lootQ5       = { label = "Legendaries Looted",    fmt = "num",   weekly = true },
    moneyIn      = { label = "Gold Earned",           fmt = "money", weekly = true },
    moneyOut     = { label = "Gold Spent",            fmt = "money", weekly = true },
    goldQuests   = { label = "Gold from Quests",      fmt = "money", weekly = true },
    vendorSales  = { label = "Vendor Sales",          fmt = "money", weekly = true },
    vendorSpent  = { label = "Vendor Purchases",      fmt = "money", weekly = true },
    biggestLoot  = { label = "Biggest Single Loot",   fmt = "money", agg = "max" },
    -- Survival & combat
    combatTime   = { label = "Time in Combat",        fmt = "duration", weekly = true },
    fights       = { label = "Fights",                fmt = "num",   weekly = true },
    spiritHealer = { label = "Spirit Healer Visits",  fmt = "num",   weekly = true },
    rezzed       = { label = "Resurrected by Others", fmt = "num",   weekly = true },
    closeCalls   = { label = "Close Calls",           fmt = "num",   weekly = true },
    potions      = { label = "Potions & Elixirs",     fmt = "num",   weekly = true },
    foodDrink    = { label = "Food & Drink",          fmt = "num",   weekly = true },
    bandages     = { label = "Bandages Used",         fmt = "num",   weekly = true },
    pvpKills     = { label = "Players Slain",         fmt = "num",   weekly = true },
    honorKills   = { label = "Honorable Kills",       fmt = "num",   agg = "max" },
    bgPlayed     = { label = "Battlegrounds Played",  fmt = "num",   weekly = true },
    bgWon        = { label = "Battlegrounds Won",     fmt = "num",   weekly = true },
    -- Social
    whispersSent     = { label = "Whispers Sent",     fmt = "num",   weekly = true },
    whispersReceived = { label = "Whispers Received", fmt = "num",   weekly = true },
    emotes           = { label = "Emotes Used",       fmt = "num",   weekly = true },
    trades           = { label = "Trades Completed",  fmt = "num",   weekly = true },
    mailsSent        = { label = "Mail Sent",         fmt = "num",   weekly = true },
    companions       = { label = "Players Grouped With", fmt = "num", agg = "max" },
    -- Habits & personal bests
    sessions         = { label = "Sessions",          fmt = "num",   weekly = true },
    reloads          = { label = "UI Reloads",        fmt = "num",   weekly = true },
    questsAbandoned  = { label = "Quests Abandoned",  fmt = "num",   weekly = true },
    nightTime        = { label = "Night Owl Time",    fmt = "duration", weekly = true },
    morningTime      = { label = "Early Bird Time",   fmt = "duration", weekly = true },
    daysPlayed       = { label = "Days Played",       fmt = "num",   agg = "max" },
    bestStreak       = { label = "Best Daily Streak", fmt = "num",   agg = "max" },
    longestSession   = { label = "Longest Session",   fmt = "duration", agg = "max" },
    longestLife      = { label = "Longest Life",      fmt = "duration", agg = "max" },
    crafted     = { label = "Items Crafted",      fmt = "num",      weekly = true },
}
-- Counters the tracker owns per character (everything weekly).
FellowshipSync.COUNTER_KEYS = {}
for key, def in pairs(FellowshipSync.STATS) do
    if def.weekly and not def.derived then table.insert(FellowshipSync.COUNTER_KEYS, key) end
end
table.sort(FellowshipSync.COUNTER_KEYS)

local function NewCounters()
    local t = {}
    for _, k in ipairs(FellowshipSync.COUNTER_KEYS) do t[k] = 0 end
    return t
end

-- The Hall of Fame scoreboards (blueprint order). The points board is left out
-- in games without achievements.
FellowshipSync.HOF_WIDGETS = {
    { id = "gear",     key = "gs",         title = "GearScore & iLvl",   on = true },
    { id = "legacy",   key = "legacy",     title = FellowshipSync.POINTS.long, on = true },
    { id = "playtime", key = "playtime",   title = "Playtime",           on = true },
    { id = "kills",    key = "kills",      title = "Total Kills",        on = true },
    { id = "deaths",   key = "deaths",     title = "Deaths",             on = true },
    { id = "damage",   key = "damage",     title = "Total Damage",       on = true },
    { id = "healing",  key = "healing",    title = "Healing Done",       on = true },
    { id = "critters", key = "critters",   title = "Critters Butchered", on = true },
    { id = "repairs",  key = "repairs",    title = "Repair Bills",       on = true },
    { id = "fall",     key = FellowshipSync.HAS_COMBAT_LOG and "fallDamage" or "fallDeaths",
                       title = FellowshipSync.HAS_COMBAT_LOG and "Fall Damage Taken" or "Deaths by Falling", on = false },
    { id = "crit",     key = "crit",       title = "Largest Hit",        on = false },
    { id = "jumps",    key = "jumps",      title = "Total Jumps",        on = false },
    { id = "epics",    key = "epics",      title = "Epics Looted",       on = false },
    { id = "gold",     key = "goldLooted", title = "Gold Looted",        on = false },
    { id = "quests",   key = "quests",     title = "Quests Done",        on = false },
    { id = "fish",     key = "fish",       title = "Fish Caught",        on = false },
    { id = "chat",     key = "chat",       title = "Chatterbox",         on = false },
    { id = "afk",      key = "afk",        title = "AFK Champion",       on = false },
    { id = "travel",   key = "flightTime", title = "Flight Time",        on = false },
    { id = "distance", key = "travelTotal", title = "Distance Travelled", on = false },
    { id = "corpse",   key = "corpseRuns",  title = "Corpse Runs",        on = false },
    { id = "combat",   key = "combatTime",  title = "Time in Combat",     on = false },
    { id = "hearth",   key = "hearths",     title = "Hearth Hoppers",     on = false },
    { id = "explorer", key = "areasDiscovered", title = "Explorers",      on = false },
    { id = "potions",  key = "potions",     title = "Chug Champions",     on = false },
    { id = "night",    key = "nightTime",   title = "Night Owls",         on = false },
    { id = "emotes",   key = "emotes",      title = "Most Emotes",        on = false },
}

if not FellowshipSync.HAS_POINTS then
    for i = #FellowshipSync.HOF_WIDGETS, 1, -1 do
        if FellowshipSync.HOF_WIDGETS[i].id == "legacy" then table.remove(FellowshipSync.HOF_WIDGETS, i) end
    end
end

local function DefaultWidgetState()
    local state = {}
    for _, scope in ipairs({ "solo", "guild", "network", "netaccs" }) do
        state[scope] = {}
        for _, w in ipairs(FellowshipSync.HOF_WIDGETS) do state[scope][w.id] = w.on end
    end
    return state
end

local defaults = {
    global = {
        networkKey = "FellowshipForever2026",
        dbVersion = 0,
        characters = {},
        events = {},
        bets = {},          -- this account's wagers: { w = wagerId, pick = charKey, amt = marks, t = time }
        wagerResults = {},  -- wagerId -> { winner = charKey, at = time }
        bountyDone = {},    -- "week:id" -> { title, t, top }
        customWagers = {},  -- wagers this account created (stat-based or officer free-text)
        deathrolls = {},    -- deathroll history
        raffles = {},       -- raffle history
        guildData = {},
        listSort = {},      -- list id -> { col, desc } (sorting is remembered)     -- guild name -> officer objects, responses, attendance, bank (see Officer.lua)
        raffleSettings = { keyword = "raffle", fee = "10g", channel = "guild", onlyPaid = false, announce = true },
        setupDone = false,  -- the first-time setup guide was completed or skipped
    },
    profile = {
        theme = "Default Gold",
        font = "Standard Modern",
        borderStyle = "Classic WoW Tooltip",
        background = "Solid Colour",   -- window background texture
        fontOutline = "none",          -- none | OUTLINE | THICKOUTLINE | MONOCHROME
        cardStyle = "soft",            -- soft | flat | bold
        pop = 0.4,                     -- how much of the accent colour goes into borders and buttons (0-1)
        glow = 0.35,                   -- outer glow strength (0-1)
        glowSize = 14,
        glowPulse = false,
        glowToasts = true,
        glowCards = false,
        shadow = true,
        officer = { inactiveDays = 14 },
        share = { channel = "guild", prefix = true },
        unitTooltip = true,            -- guildmates' stats in the game tooltip
        uiScale = 1.0,
        textSize = 12,
        bgAlpha = 0.95,
        syncGuild = true,
        shareGear = true,
        showBadges = true,
        syncBNet = true,      -- share with Battle.net friends (any faction / realm)
        shareAlts = true,     -- also share my other characters' last known stats
        relayBNet = true,     -- pass friends' stats on to my guild
        allowRelay = true,    -- let friends pass MY stats on to their guild
        ruleset = "auto",
        notify = {
            toasts = true,
            -- Your own events. level: "all" | "max" | "off"
            own = { level = "tens", account = true, legacy = true, gear = true, prof = true, milestone = true, boss = true, record = true, fallen = true,
                    bounty = true, wager = true, onthisday = true },
            -- Guildmates' and friends' events. boss: "first" | "all" | "off"; level: "max" | "tens" | "off"
            guild = { boss = "first", level = "max", legacy = false, fallen = true, death = false, record = true, prof = false,
                      rival = true, notices = true, events = true },
            versionToast = true,
            duration = 5, scale = 1.0, sound = "epic", guildSound = "quest", pauseInCombat = true, holdInInstances = true,
            point = { "TOP", 0, -150 },
            -- Chat announcements of your own events (off by default). channel: "guild" | "group" | "both"
            announce = false, channel = "guild", prefix = true, lastWords = true,
            ann = { maxlevel = true, boss = "first", record = true, legacy = false, fallen = true, prof = false, levels = false },
        },
        showTicker = true,
        distanceUnits = "metric", -- "metric" (m / km) or "imperial" (yd / mi)
        showSteps = true,         -- estimated steps next to distance on foot
        minimap = { hide = false, angle = 215 },
        hofWidgets = DefaultWidgetState(),
        chronicle = { skip = {} }, -- Weekly Chronicle lines left out of posts / exports
        -- Memory Lane: automatic screenshots of big moments
        memory = { enabled = true, maxlevel = true, boss = true, firsts = true, record = false, legacy = true,
                   fallen = true, levels = false, bounty = true },
        -- Deathmap: skulls on the world map. scope: "solo" | "guild" | "network"
        deathmap = { worldMap = true, scope = "guild", size = 14, max = 400, days = 0, mode = "skulls", hotGrid = "medium",
                     hcOnly = false, highlightMine = true },
        privacy = {
            shareLocation = true, shareWealth = true, sharePlaytime = true, shareSilly = true,
            shareJourney = true, shareCombat = true, shareProfessions = true, shareLastWords = true,
            shareSocial = true, -- bonds, rival and wagers
        },
    },
    char = {
        stats = NewCounters(),
        week = { resetAt = 0, base = {} },
        milestones = {},
        profRanks = {},
        deathLog = {},
        killers = {},
        mobs = {},
        mobsSent = {},
        mobFirst = {},   -- enemy name -> when you first killed one
        firsts = {},     -- "lv60", "prof:Mining:300", "boss:Onyxia", "lg:<id>" -> time (0 = before install)
        levelTimes = {}, -- level -> played seconds when it was reached (speedrun board)
        encounters = {}, -- boss name -> { instance, kills, wipes, best, first }
        gsBest = 0,
        bonds = {},      -- companion key -> { time, bosses, deaths, rezzes, last, cls }
        zoneTime = {},   -- zone -> seconds
        hours = {},      -- [1..24] seconds played in each hour of the day
        days = {},       -- "YYYY-MM-DD" -> true (days played)
        daily = {},      -- "YYYY-MM-DD" -> { levels, gold } (last 60 days)
        emoteCounts = {},-- emote token -> uses
        instances = {},  -- instance name -> visits
        records = {},    -- personal bests: longestLife, longestSession, killsSession, levelsDay, goldDay, bestStreak
        life = 0,        -- seconds alive since the last death (played time)
        memories = {},   -- Memory Lane log
        -- rival, lastWk (last week's final numbers), firstSeen are added when known
    },
}

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end
FellowshipSync.IsSecret = IsSecret

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function FellowshipSync:OnInitialize()
    -- One shared "Default" profile for every character (account-wide settings);
    -- characters can switch to their own profile under Options > Profiles.
    self.db = LibStub("AceDB-3.0"):New("FellowshipSyncDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    self:MigrateDatabase()
    self:RegisterComm(self.COMM_PREFIX, "OnCommReceived")
    self:RegisterChatCommand("fsync", "HandleSlash")
    self:RegisterChatCommand("testsync", "InjectMockData")
end

function FellowshipSync:MigrateDatabase()
    -- v2.8: the old single toast switch moved into the notification settings.
    if self.db.profile.showToasts == false then self.db.profile.notify.toasts = false end
    self.db.profile.showToasts = nil
    local g = self.db.global
    if (tonumber(g.dbVersion) or 0) < DB_VERSION then
        -- v3 changed units (money in copper, playtime in seconds), so the cache starts fresh.
        wipe(g.characters)
        wipe(g.events)
        self.db.profile.stats = nil
        g.dbVersion = DB_VERSION
        self.didMigrate = true
    end
end

function FellowshipSync:OnEnable()
    if self.Extras.Enable then self.Extras:Enable() end
    self.Tracker:Enable()
    if self.Fellowship.Enable then self.Fellowship:Enable() end
    if self.Deathmap.Enable then self.Deathmap:Enable() end
    if self.Officer.Enable then self.Officer:Enable() end
    if self.Options.RegisterBlizzard then self.Options:RegisterBlizzard() end
    if self.Extras.EnableUnitTooltip then self.Extras:EnableUnitTooltip() end
    self:ScheduleTimer(function() if not InCombatLockdown() then self.Share:CheckWhatsNew() end end, 12)
    if self.Games.Enable then self.Games:Enable() end
    -- First time: offer the setup guide a few seconds after login.
    if not self.db.global.setupDone then
        self:ScheduleTimer(function() if self.Setup.Show and not InCombatLockdown() then self.Setup:Show() end end, 6)
    end
    FellowshipSync.SafeRegister(self, "BN_CHAT_MSG_ADDON", function(_, ...) self.Comm:OnBNetAddon(...) end)
    if self.didMigrate then
        self:Print("Updated to v" .. self.VERSION .. ". Cached characters were reset once; log in on each alt to re-add it.")
        self.didMigrate = nil
    end
    self:Print(string.format(L["ADDON_LOADED"] or "FellowshipSync v%s loaded. Type /fsync to open.", self.VERSION))
end

-- A different profile means different settings everywhere: reapply them all.
function FellowshipSync:OnProfileChanged()
    if self.db.profile.showToasts ~= nil then self:MigrateDatabase() end
    if self.Comm.ResetTrust then self.Comm:ResetTrust() end -- the Battle.net password may differ
    if self.Extras.UpdateMinimapButton then self.Extras:UpdateMinimapButton() end
    if self.Extras.ApplyToastLayout then self.Extras:ApplyToastLayout() end
    if self.UI.MainFrame then
        self.UI:ApplyTheme()
        if self.Options.Redraw then self.Options:Redraw() end
    end
end

function FellowshipSync:OnCommReceived(prefix, message, distribution, sender)
    if self.Comm.OnCommReceived then self.Comm:OnCommReceived(prefix, message, distribution, sender) end
end

---------------------------------------------------------------------------
-- Character access
---------------------------------------------------------------------------

-- Forever names are "first name + surname": UnitName returns the surname in
-- its second value, so both are part of the key (two "Kima"s must not collide).
function FellowshipSync:GetPlayerName()
    local first, second = UnitName("player")
    if self.IS_FOREVER and type(second) == "string" and second ~= "" then return first .. " " .. second end
    return first or "Player"
end

function FellowshipSync:GetPlayerKey()
    return self:GetPlayerName() .. "-" .. (GetRealmName() or "Realm")
end

-- Every name the game may use for us in chat ("Kima", "Kima Stormborn", "Kima-Realm").
function FellowshipSync:IsMe(name)
    if type(name) ~= "string" then return false end
    local first = UnitName("player")
    local full = self:GetPlayerName()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return name == first or name == full or name == first .. "-" .. realm or name == full .. "-" .. realm
        or name == full:gsub(" ", "-")
end

function FellowshipSync:GetMyRecord()
    return self.db and self.db.global.characters[self:GetPlayerKey()]
end

-- Short display name: "Kima-Some Realm" -> "Kima"
function FellowshipSync.ShortName(fullName)
    return (tostring(fullName or "?"):match("^([^%-]+)")) or tostring(fullName)
end

-- Value of a stat for a record, honouring the All-Time / This Week toggle.
function FellowshipSync:GetValue(rec, key, mode)
    if not rec then return 0 end
    if key == "travelTotal" then
        return self:GetValue(rec, "travelFoot", mode) + self:GetValue(rec, "travelMount", mode)
            + self:GetValue(rec, "travelFlight", mode) + self:GetValue(rec, "travelSwim", mode)
    end
    local def = self.STATS[key]
    if def and def.weekly and (mode or self.UI.timeMode) == "week" then
        if not rec.isAccount and (tonumber(rec.lastUpdate) or 0) < self:WeekStart() then return 0 end
        return tonumber(rec.wk and rec.wk[key]) or 0
    end
    return tonumber(rec[key]) or 0
end

-- A number for each reset week (the same for everyone in a region), used to
-- pick that week's bounties and wagers without having to sync them.
function FellowshipSync.WeekIndex(weekStart)
    return math.floor(((tonumber(weekStart) or 0) + 3600) / (7 * 86400))
end

-- Start of the current reset week (the tracker stores the next reset time).
function FellowshipSync:WeekStart()
    local week = self.db and self.db.char.week
    return (tonumber(week and week.resetAt) or 0) - 7 * 86400
end

function FellowshipSync:IsWeekMode()
    return self.UI.timeMode == "week"
end

-- Aggregates characters into one record per account (owner).
local function BuildAccounts(chars)
    local accounts, order = {}, {}
    for _, d in pairs(chars) do
        local owner = d.owner or "Unknown"
        local acc = accounts[owner]
        if not acc then
            acc = {
                fullName = owner, owner = owner, isAccount = true, charCount = 0, chars = {},
                cls = d.cls, faction = d.faction, ruleset = d.ruleset, wk = {},
                isMyChar = d.isMyChar, isMock = d.isMock, lastUpdate = 0,
            }
            accounts[owner] = acc
            table.insert(order, acc)
        end
        acc.charCount = acc.charCount + 1
        table.insert(acc.chars, d)
        acc.lastUpdate = math.max(acc.lastUpdate, tonumber(d.lastUpdate) or 0)
        acc.isMyChar = acc.isMyChar or d.isMyChar
        for key, def in pairs(FellowshipSync.STATS) do
          if not def.derived then
            local v = tonumber(d[key]) or 0
            if def.agg == "max" then
                acc[key] = math.max(acc[key] or 0, v)
            else
                acc[key] = (acc[key] or 0) + v
            end
            if def.weekly and (tonumber(d.lastUpdate) or 0) >= FellowshipSync:WeekStart() then
                acc.wk[key] = (acc.wk[key] or 0) + (tonumber(d.wk and d.wk[key]) or 0)
            end
          end
        end
        -- The account's face is its best-geared character.
        if (tonumber(d.gs) or 0) >= (acc.bestGs or -1) then
            acc.bestGs = tonumber(d.gs) or 0
            acc.cls, acc.faction, acc.ruleset, acc.bestChar = d.cls, d.faction, d.ruleset, d
        end
    end
    return order
end
FellowshipSync.BuildAccounts = BuildAccounts

-- scope: "solo" | "guild" | "network" | "netaccs"
function FellowshipSync:GetFilteredCharacters(scope)
    local result = {}
    if not self.db then return result end
    scope = scope or self.UI.currentScope or "solo"
    local chars = self.db.global.characters

    if scope == "netaccs" then return BuildAccounts(chars) end

    for name, d in pairs(chars) do
        d.fullName = name
        if (scope == "solo" and d.isMyChar)
            or (scope == "guild" and (d.inGuild or d.isMyChar))
            or (scope == "network") then
            table.insert(result, d)
        end
    end
    return result
end

-- Same as above but never aggregated (for death logs, profiles, mobs...).
function FellowshipSync:GetScopeCharacters(scope)
    scope = scope or self.UI.currentScope or "solo"
    if scope == "netaccs" then scope = "network" end
    return self:GetFilteredCharacters(scope)
end

-- Sorted copy, highest first (or lowest first when asc).
function FellowshipSync:SortByStat(list, key, asc)
    table.sort(list, function(a, b)
        local va, vb = self:GetValue(a, key), self:GetValue(b, key)
        if va == vb then return tostring(a.fullName) < tostring(b.fullName) end
        if asc then return va < vb end
        return va > vb
    end)
    return list
end

---------------------------------------------------------------------------
-- Event feed (news ticker, legacy milestones, deathlog toasts)
---------------------------------------------------------------------------

function FellowshipSync:AddEvent(ev, fromNetwork)
    if type(ev) ~= "table" or not ev.kind or not ev.who then return end
    ev.t = tonumber(ev.t) or time()
    -- Identity includes the value too: two level-ups in the same second are two events.
    ev.id = ev.id or (ev.who .. ":" .. ev.t .. ":" .. ev.kind .. ":" .. tostring(ev.a or "") .. ":" .. tostring(ev.v or ""))
    local events = self.db.global.events
    for _, e in ipairs(events) do
        if e.id == ev.id then return end
    end
    table.insert(events, ev)
    table.sort(events, function(a, b) return a.t > b.t end)
    for i = #events, 151, -1 do events[i] = nil end
    if not fromNetwork then ev.mine = true end
    if self.Extras.OnNewEvent then self.Extras:OnNewEvent(ev) end
    self:QueueUIRefresh()
end

-- Events whose character is visible in the given scope.
function FellowshipSync:GetScopedEvents(scope, kindFilter)
    local visible = {}
    for _, d in ipairs(self:GetScopeCharacters(scope)) do visible[d.fullName] = d end
    local out = {}
    for _, ev in ipairs(self.db.global.events) do
        if visible[ev.who] and (not kindFilter or kindFilter[ev.kind]) then
            table.insert(out, ev)
        end
    end
    return out, visible
end

---------------------------------------------------------------------------
-- UI refresh helpers
---------------------------------------------------------------------------

function FellowshipSync:RefreshUIIfShown()
    local UI = self.UI
    if UI and UI.MainFrame and UI.MainFrame:IsShown() and UI.RefreshActiveTab then
        UI:RefreshActiveTab()
    end
end

function FellowshipSync:QueueUIRefresh()
    if self.uiRefreshTimer then return end
    self.uiRefreshTimer = self:ScheduleTimer(function()
        self.uiRefreshTimer = nil
        self:RefreshUIIfShown()
    end, 1)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

function FellowshipSync:HandleSlash(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "" or cmd == "show" then
        self:ToggleUI()
    elseif cmd == "sync" then
        self.Comm:BroadcastStats(true)
    elseif cmd == "test" then
        self:InjectMockData()
    elseif cmd == "clearmock" then
        self:ClearMockData()
    elseif cmd == "wipe" then
        self:WipeNetworkCache()
    elseif cmd == "stats" then
        self.Tracker:PrintStatisticCheck()
    elseif cmd == "legacy" then
        self.Tracker:PrintLegacyCheck()
    elseif cmd == "game" then
        self:Print(string.format("Detected game: %s (project %s, interface %s). Max level %d. %s. Combat log: %s.",
            self.GAME_INFO.name, tostring(WOW_PROJECT_ID), tostring(tocVersion), self:MaxLevel(),
            self.HAS_POINTS and ("Points shown as " .. self.POINTS.long) or "No achievements in this game",
            self.HAS_COMBAT_LOG and "used" or "not available"))
    elseif cmd == "setup" then
        self.Setup:Show()
    elseif cmd == "minimap" then
        local mm = self.db.profile.minimap
        mm.hide = not mm.hide
        self.Extras:UpdateMinimapButton()
    else
        self:Print("Commands: /fsync, /fsync sync, /fsync test, /fsync clearmock, /fsync wipe, /fsync stats, /fsync legacy, /fsync game, /fsync setup, /fsync minimap")
    end
end

function FellowshipSync:ToggleUI()
    if InCombatLockdown() then self:Print("|cffff5555Cannot open FellowshipSync while in combat.|r") return end
    local UI = self.UI
    if UI.MainFrame and UI.MainFrame:IsShown() then UI.MainFrame:Hide() return end
    self.Tracker:Snapshot()
    local firstOpen = not UI.MainFrame
    UI:InitializeFrame()
    UI.MainFrame:Show()
    if not firstOpen then UI:RefreshActiveTab() end
end

-- Addon compartment (the puzzle-piece menu by the minimap).
function FellowshipSync_OnAddonCompartmentClick()
    FellowshipSync:ToggleUI()
end

function FellowshipSync:WipeNetworkCache()
    -- Forget which updates were seen, so wiped players reappear with their very next message.
    if self.Comm.seen then wipe(self.Comm.seen) end
    if self.Comm.relayed then wipe(self.Comm.relayed) end
    local chars = self.db.global.characters
    for name, d in pairs(chars) do
        if not d.isMyChar or d.isMock then chars[name] = nil end
    end
    local events = self.db.global.events
    for i = #events, 1, -1 do
        if not chars[events[i].who] then table.remove(events, i) end
    end
    self.Tracker:Snapshot()
    self:Print(L["CACHE_WIPED"] or "Cleared cached network characters.")
    self:RefreshUIIfShown()
end

function FellowshipSync:ClearMockData()
    local chars, removed = self.db.global.characters, 0
    for name, d in pairs(chars) do
        if d.isMock then chars[name] = nil; removed = removed + 1 end
    end
    local events = self.db.global.events
    for i = #events, 1, -1 do
        if events[i].mock then table.remove(events, i) end
    end
    self:Print(string.format("Removed %d test characters.", removed))
    self:RefreshUIIfShown()
end

-- Key binding (Esc > Options > Key Bindings > AddOns) and the toggle it calls.
BINDING_HEADER_FELLOWSHIPSYNC = "FellowshipSync"
BINDING_NAME_FELLOWSHIPSYNC_TOGGLE = "Open / close FellowshipSync"
function FellowshipSync_Toggle() FellowshipSync:ToggleUI() end
