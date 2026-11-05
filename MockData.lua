local addonName, addonTable = ...
local FS = addonTable.FellowshipSync

-- /fsync test : fills the database with realistic sample players so every tab
-- can be previewed. Everything here is flagged isMock and removed by /fsync clearmock.

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "MAGE", "WARLOCK", "SHAMAN", "DRUID" }
local RACES = { Horde = { "Orc", "Undead", "Tauren", "Troll" }, Alliance = { "Human", "Dwarf", "Night Elf", "Gnome" } }
local OWNERS = { "Katrine", "Olav", "Erik", "Benny", "Lars", "Morten", "Stian", "Anna", "Trond", "Jonas", "Petter", "Markus",
                 "Ingrid", "Sigrid", "Henrik", "Maja", "Oskar", "Nora", "Emil", "Thea" }
local NAME_A = { "Heal", "Ice", "Frost", "Shadow", "Bear", "Chain", "Holy", "Stab", "Bow", "Tiny", "Grim", "Iron", "Storm", "Moon", "Sun", "Blood" }
local NAME_B = { "trine", "blocker", "bite", "hug", "heal", "anna", "benny", "master", "evil", "fist", "beard", "caller", "shade", "fang" }
local ZONES = { "Orgrimmar", "Stormwind City", "Stranglethorn Vale", "Ashenvale", "Tanaris", "Blackrock Mountain", "Undercity",
                "The Barrens", "Hillsbrad Foothills", "Thousand Needles", "Ironforge", "Westfall", "Duskwood", "Feralas" }
local KILLERS = { { "Onyxia", "Lvl ?? Boss" }, { "Gankmaster", "Lvl 60 Undead Rogue" }, { "Falling", "Gravity always wins" },
                  { "Defias Pillager", "Lvl 15 Humanoid" }, { "Murloc Tidehunter", "Lvl 12 Humanoid" }, { "Ragnaros", "Lvl ?? Boss" },
                  { "Drowning", "Ran out of breath" }, { "Hakkar", "Lvl ?? Boss" }, { "Bloodscalp Berserker", "Lvl 38 Elite" } }
local WORDS = { "tror kysten er klar naa gutta", "hvem var det som traakka paa eggene?!", "faar ikke casta frostnova!!",
                "LEEROY JENKINS", "it's fine, I can solo this", "wait, wrong pull", "brb", "anyone got a rez?", "watch this jump" }
local BOSSES = { "Onyxia", "Hogger", "Edwin VanCleef", "Mutanus the Devourer", "Ragnaros" }
-- Boss fights per game: { boss, instance }
local ENCOUNTERS = {
    era = { { "Lucifron", "Molten Core" }, { "Magmadar", "Molten Core" }, { "Ragnaros", "Molten Core" }, { "Onyxia", "Onyxia's Lair" },
            { "Edwin VanCleef", "The Deadmines" }, { "Mutanus the Devourer", "Wailing Caverns" }, { "Bazzalan", "Ragefire Chasm" } },
    tbc = { { "Attumen the Huntsman", "Karazhan" }, { "Prince Malchezaar", "Karazhan" }, { "Gruul the Dragonkiller", "Gruul's Lair" },
            { "Magtheridon", "Magtheridon's Lair" }, { "Omor the Unscarred", "Hellfire Ramparts" }, { "Murmur", "Shadow Labyrinth" } },
    mists = { { "The Stone Guard", "Mogu'shan Vaults" }, { "Elegon", "Mogu'shan Vaults" }, { "Imperial Vizier Zor'lok", "Heart of Fear" },
              { "Sha of Fear", "Terrace of Endless Spring" }, { "Gu Cloudstrike", "Temple of the Jade Serpent" } },
    retail = { { "Vexie and the Geargrinders", "Liberation of Undermine" }, { "Chrome King Gallywix", "Liberation of Undermine" },
               { "Ulgrax the Devourer", "Nerub-ar Palace" }, { "Speaker Brokk", "The Stonevault" } },
}
ENCOUNTERS.forever = ENCOUNTERS.era
local MOBS = { "Defias Pillager", "Murloc Tidehunter", "Savannah Prowler", "Bristleback Quilboar", "Rot Hide Gnoll",
               "Mottled Boar", "Kobold Vermin", "Scarlet Crusader", "Venom Web Spider", "Stonetalon Harpy" }
local PROFS = { { "Mining", "Engineering" }, { "Herbalism", "Alchemy" }, { "Skinning", "Leatherworking" },
                { "Tailoring", "Enchanting" }, { "Mining", "Blacksmithing" } }
local ITEMS = {
    Head = { "Judgement Crown", "INV_Helmet_74" }, Neck = { "Onyxia Tooth Pendant", "INV_Jewelry_Necklace_09" },
    Shoulder = { "Lawbringer Spaulders", "INV_Shoulder_37" }, Back = { "Cape of the Black Baron", "INV_Misc_Cape_20" },
    Chest = { "Lawbringer Chestguard", "INV_Chest_Plate03" }, Wrist = { "Lawbringer Bracers", "INV_Bracer_18" },
    Hands = { "Flameguard Gauntlets", "INV_Gauntlets_19" }, Waist = { "Onslaught Girdle", "INV_Belt_29" },
    Legs = { "Judgement Legplates", "INV_Pants_Plate_17" }, Feet = { "Lawbringer Boots", "INV_Boots_Plate_09" },
    Finger0 = { "Band of Accuria", "INV_Jewelry_Ring_15" }, Finger1 = { "Don Julio's Band", "INV_Jewelry_Ring_39" },
    Trinket0 = { "Hand of Justice", "INV_Jewelry_Talisman_01" }, Trinket1 = { "Blackhand's Breadth", "INV_Misc_StoneTablet_01" },
    MainHand = { "Obsidian Edged Blade", "INV_Sword_50" }, SecondaryHand = { "Libram of Fervor", "INV_Relics_LibramofHope" },
}

local function Pick(t) return t[math.random(1, #t)] end

-- Professions as they really look in each game.
function FS.MockProfessions(pair, level)
    local max, share = FS.ProfMax(), level / FS:MaxLevel()
    local function rank(m) return math.max(1, math.min(m, math.floor(m * share * (0.6 + math.random() * 0.5)))) end
    local list = {}
    if FS.GAME == "retail" then
        for _, name in ipairs(pair) do table.insert(list, { name = name, rank = rank(100), max = 100, kind = "primary", tier = "Khaz Algar " .. name }) end
        table.insert(list, { name = "Cooking", rank = rank(100), max = 100, kind = "secondary", tier = "Khaz Algar Cooking" })
        table.insert(list, { name = "Fishing", rank = rank(100), max = 100, kind = "secondary", tier = "Khaz Algar Fishing" })
        table.insert(list, { name = "Archaeology", rank = rank(950), max = 950, kind = "secondary" })
        return list
    end
    for _, name in ipairs(pair) do table.insert(list, { name = name, rank = rank(max), max = max, kind = "primary" }) end
    table.insert(list, { name = "Fishing", rank = rank(max), max = max, kind = "secondary" })
    table.insert(list, { name = "Cooking", rank = rank(max), max = max, kind = "secondary" })
    table.insert(list, { name = "First Aid", rank = rank(max), max = max, kind = "secondary" })
    if FS.GAME == "mists" then table.insert(list, { name = "Archaeology", rank = rank(600), max = 600, kind = "secondary" }) end
    return list
end

local function MockGear(level)
    local gear, best = {}, nil
    for _, slot in ipairs(FS.GEAR_SLOTS) do
        if math.random() > 0.08 then
            local top, maxLevel = FS.GAME_INFO.ilvlTop or 66, FS:MaxLevel()
            local base = math.max(5, math.floor(top * level / maxLevel * (0.78 + math.random() * 0.22)))
            local quality = (level >= maxLevel - 2 and math.random() > 0.4) and 4 or ((level >= maxLevel / 2) and 3 or 2)
            local hex = FS.W.QUALITY_HEX[quality]
            local item = ITEMS[slot]
            gear[slot] = { name = "|cff" .. hex .. "[" .. item[1] .. "]|r", ilvl = base, quality = quality,
                           icon = "Interface\\Icons\\" .. item[2] }
            if not best or base > best.ilvl then best = { link = gear[slot].name, ilvl = base, quality = quality } end
        end
    end
    return gear, best
end

function FS:InjectMockData()
    self:ClearMockData()
    self.Tracker:Snapshot()
    local chars = self.db.global.characters
    local me = self.Tracker:AccountLabel()
    local count = 0

    for o = 0, #OWNERS do
        local owner = o == 0 and me or OWNERS[o]
        local faction = (o % 3 == 1) and "Alliance" or "Horde"
        local ruleset = (faction == "Alliance" and "A-" or "H-") .. ((o % 4 == 1) and "PvP" or (o % 5 == 2) and "HC" or "PvE")
        local legacy = FS.IS_FOREVER and math.random(4, 40) or (FS.HAS_POINTS and math.random(1500, 32000)) or 0
        local online = math.random() > 0.5
        for c = 1, (o == 0 and 5 or math.random(1, 4)) do
            count = count + 1
            local name = Pick(NAME_A) .. Pick(NAME_B) .. tostring(count) .. "-TestRealm"
            -- Never overwrite a real (synced or own) character with sample data.
            while chars[name] and not chars[name].isMock do name = "Sample" .. name end
            local maxLevel = FS:MaxLevel()
            local level = (c == 1) and maxLevel or math.random(10, maxLevel)
            local gear, best = MockGear(level)
            local gs, sumIlvl, n = 0, 0, 0
            for _, item in pairs(gear) do gs = gs + item.ilvl * 0.75 * (item.quality >= 4 and 1.15 or 1); sumIlvl = sumIlvl + item.ilvl; n = n + 1 end
            local ilvl = n > 0 and tonumber(string.format("%.1f", sumIlvl / n)) or 0
            local profPair = Pick(PROFS)
            local scale = level / maxLevel

            local rec = {
                fullName = name, owner = owner, isMock = true, isMyChar = (o == 0),
                inGuild = (o == 0) or (o % 2 == 0), guildName = ((o == 0) or (o % 2 == 0)) and "Fellowship" or nil,
                cls = Pick(CLASSES), race = Pick(RACES[faction]), faction = faction, ruleset = ruleset, level = level,
                zone = Pick(ZONES), hearth = Pick(ZONES), rested = (level >= 60) and -1 or math.random(0, 150),
                gs = math.floor(gs * 1.2), ilvl = ilvl, ilvlBag = ilvl + math.random(0, 15) / 10,
                gear = gear, highest = best, legacy = legacy, legacyMax = FS.IS_FOREVER and 65 or nil, game = FS.GAME, wealth = math.random(1, 2000) * 10000,
                playtime = math.floor(scale * math.random(20, 600) * 3600), playtimeLevel = math.random(1, 50) * 3600,
                kills = math.floor(scale * math.random(200, 60000)), deaths = math.random(0, 450),
                damage = math.floor(scale * math.random(100000, 20000000)), healing = math.floor(scale * math.random(5000, 20000000)),
                crit = math.floor(scale * math.random(200, 4200)), critters = math.random(0, 1300),
                repairs = math.random(0, 500000), fallDeaths = math.random(0, 25), fallDamage = math.random(0, 90000), jumps = math.random(100, 16000),
                epics = math.floor(scale * math.random(0, 16)), goldLooted = math.random(1000, 45000000),
                quests = math.floor(scale * math.random(20, 1400)), fish = math.random(0, 2400), chat = math.random(10, 9000),
                afk = math.random(0, 5000), flightTime = math.random(0, 120000), flightRides = math.random(0, 200),
                travelFoot = math.random(5000, 850000), travelMount = math.random(15000, 2500000), travelFlight = math.random(50000, 8500000),
                duelsWon = math.random(0, 90), duelsLost = math.random(0, 60),
                rollsWon = math.random(0, 90), rollsTotal = math.random(0, 300), rolls100 = math.random(0, 3), rolls1 = math.random(0, 6),
                gathered = math.random(0, 3200), crafted = math.random(0, 900),
                profs = FS.MockProfessions(profPair, level),
                deathLog = {}, killers = {}, mobs = {},
                lastUpdate = online and time() - math.random(0, 600) or time() - math.random(3600, 400000),
            }
            -- Levelling times: roughly 2.5 days played to 60, faster for some, slower for others.
            rec.levelTimes = {}
            local pace = math.random(70, 160) / 100
            local played = 0
            for l = 2, level do
                played = played + math.floor((900 + l * l * 18) * pace)
                if math.random() > 0.08 then rec.levelTimes[l] = played end
            end
            rec.playtime = math.max(rec.playtime or 0, played)
            -- Boss log
            rec.encounters = {}
            if level >= maxLevel * 0.5 then
                for _, e in ipairs(ENCOUNTERS[FS.GAME] or ENCOUNTERS.era) do
                    if math.random() > 0.35 then
                        local kills = math.random(0, 12)
                        rec.encounters[e[1]] = { instance = e[2], kills = kills, wipes = math.random(0, 9),
                                                 best = kills > 0 and math.random(45, 600) or nil,
                                                 first = kills > 0 and (time() - math.random(3600, 2500000)) or nil }
                    end
                end
            end
            rec.bossKills, rec.wipes = 0, 0
            for _, e in pairs(rec.encounters) do rec.bossKills = rec.bossKills + e.kills; rec.wipes = rec.wipes + e.wipes end
            rec.version = (math.random() > 0.85) and "2.6.0" or FS.VERSION
            rec.firstSeen = time() - math.random(86400, 3000000)
            -- Records tab: every new counter gets a plausible value
            local RANGES = {
                travelSwim = 40000, corpseRuns = 300, corpseDistance = 90000, hearths = 400, flightPathsFound = 40,
                areasDiscovered = 300, instanceRuns = 200, lootQ0 = 4000, lootQ1 = 3000, lootQ2 = 900, lootQ3 = 150, lootQ5 = 1,
                moneyIn = 50000000, moneyOut = 40000000, goldQuests = 8000000, vendorSales = 12000000, vendorSpent = 6000000,
                combatTime = 400000, fights = 9000, spiritHealer = 25, rezzed = 120, closeCalls = 60, potions = 500,
                foodDrink = 900, bandages = 400, pvpKills = 300, bgPlayed = 150, bgWon = 80, whispersSent = 3000,
                whispersReceived = 3500, emotes = 800, trades = 200, mailsSent = 300, sessions = 400, reloads = 250,
                questsAbandoned = 60, nightTime = 90000, morningTime = 40000,
            }
            for key, max in pairs(RANGES) do rec[key] = math.floor(math.random(0, max) * scale) end
            rec.bgWon = math.min(rec.bgWon, rec.bgPlayed)
            rec.honorKills = math.random(0, 5000)
            rec.biggestLoot = math.random(100, 2000000)
            rec.daysPlayed = math.random(5, 300)
            rec.bestStreak = math.random(1, 40)
            rec.longestSession = math.random(1800, 40000)
            rec.longestLife = math.random(600, 300000)
            rec.curLife = math.random(0, rec.longestLife)
            rec.companions = math.random(0, 120)
            rec.favEmote = Pick({ "DANCE", "HUG", "FLEX", "LOL", "CHEER", "SALUTE" })
            rec.records = { killsSession = math.random(10, 900), levelsDay = math.random(1, 12), goldDay = math.random(1000, 9000000),
                            curStreak = math.random(0, rec.bestStreak) }
            rec.hours = {}
            local peak = math.random(0, 23)
            for h = 1, 24 do
                local dist = math.min(math.abs(h - 1 - peak), 24 - math.abs(h - 1 - peak))
                rec.hours[h] = math.max(0, math.floor((12 - dist) * math.random(200, 900)))
            end
            rec.zones = {}
            local used = {}
            for _ = 1, 6 do
                local z = Pick(ZONES)
                if not used[z] then used[z] = true; table.insert(rec.zones, { z, math.random(600, 400000) }) end
            end
            table.sort(rec.zones, function(a, b) return a[2] > b[2] end)
            for _, d in ipairs(rec.deathLog) do -- open-world deaths get a map position
                if math.random() > 0.3 then d.map, d.x, d.y = 1429 + (count % 5), math.random(100, 900) / 1000, math.random(100, 900) / 1000 end
            end
            rec.lastWk = { idx = FS.WeekIndex(FS:WeekStart()) - 1, v = {} }
            for _, k in ipairs(FS.COUNTER_KEYS) do rec.lastWk.v[k] = math.floor((tonumber(rec[k]) or 0) * math.random(1, 10) / 100) end
            rec.wk = {}
            for _, k in ipairs(FS.COUNTER_KEYS) do rec.wk[k] = math.floor((tonumber(rec[k]) or 0) * math.random(0, 12) / 100) end
            for d = 1, math.random(0, 3) do
                local killer = Pick(KILLERS)
                table.insert(rec.deathLog, { t = time() - math.random(600, 900000), zone = Pick(ZONES), killer = killer[1],
                                             kdesc = killer[2], lvl = level, words = math.random() > 0.3 and Pick(WORDS) or nil })
                rec.killers[killer[1]] = (rec.killers[killer[1]] or 0) + math.random(1, 9)
            end
            rec.mobFirst, rec.firsts = {}, {}
            for _ = 1, 4 do
                local m = Pick(MOBS)
                rec.mobs[m] = (rec.mobs[m] or 0) + math.random(5, 900)
                rec.mobFirst[m] = time() - math.random(3600, 2000000)
            end
            local function stamp() return time() - math.random(3600, 2500000) end
            local steps = { maxLevel }
            for _, l in ipairs(FS.GAME_INFO.levels or {}) do table.insert(steps, l) end
            for _, th in ipairs(steps) do if level >= th then rec.firsts["lv" .. th] = stamp() end end
            for _, p in ipairs(rec.profs) do
                for i, th in ipairs(FS.GAME_INFO.profSteps) do
                    if i >= 2 and p.kind == "primary" and p.rank >= th then rec.firsts["prof:" .. p.name .. ":" .. th] = stamp() end
                end
            end
            if level >= maxLevel - 2 and math.random() > 0.5 then
                local b = Pick(BOSSES)
                rec.firsts["boss:" .. b] = stamp()
                rec.mobs[b] = math.random(1, 6)
                rec.mobFirst[b] = rec.firsts["boss:" .. b]
            end
            if ruleset:match("HC$") and #rec.deathLog > 0 then
                local d = rec.deathLog[#rec.deathLog]
                rec.hc = { t = d.t, zone = d.zone, killer = d.killer, kdesc = d.kdesc, lvl = level, words = d.words, played = rec.playtime }
            end
            chars[name] = rec

            if math.random() > 0.6 then
                local evs = {
                    { kind = "level", v = level, lp = 0 },
                    { kind = "prof", a = profPair[2], v = FS.GAME_INFO.profSteps[2] },
                    { kind = "gear", a = best and best.link or "gear", v = rec.gs },
                    { kind = "milestone", a = "jumps", v = 10000 },
                }
                if FS.IS_FOREVER then
                    table.insert(evs, { kind = "legacy", a = "Reach level " .. ((level >= 60) and 60 or 25) .. " as " .. FS.W.ClassName(rec.cls), lp = 1 })
                elseif FS.HAS_POINTS then
                    table.insert(evs, { kind = "legacy", a = "Explore Elwynn Forest", lp = 10 })
                end
                local ev = Pick(evs)
                ev.who, ev.t, ev.mock = name, time() - math.random(60, 400000), true
                self:AddEvent(ev, true)
            end
            for _, d in ipairs(rec.deathLog) do
                self:AddEvent({ kind = "death", who = name, a = d.killer, z = d.zone, t = d.t, mock = true }, true)
            end
        end
    end
    -- Bonds, rivals and bets between the test players
    local names = {}
    for name, rec in pairs(chars) do if rec.isMock then table.insert(names, name) end end
    table.sort(names)
    local wagers = self.Fellowship:CurrentWagers()
    for i, name in ipairs(names) do
        local rec = chars[name]
        rec.bonds = {}
        for _ = 1, math.random(1, 5) do
            local other = names[math.random(1, #names)]
            if other ~= name then
                rec.bonds[other] = { time = math.random(600, 400000), bosses = math.random(0, 40), deaths = math.random(0, 15),
                                     rezzes = math.random(0, 6), cls = chars[other].cls, last = time() - math.random(60, 900000) }
            end
        end
        if math.random() > 0.8 then rec.rival = names[math.random(1, #names)] end
        rec.bets = {}
        if not rec.isMyChar and math.random() > 0.6 then
            local w = wagers[math.random(1, #wagers)]
            table.insert(rec.bets, { w = w.id, pick = names[math.random(1, #names)], amt = ({ 50, 100, 250 })[math.random(1, 3)], t = time() })
        end
    end
    self:Print(string.format("Added %d test characters across %d players. Remove them with /fsync clearmock.", count, #OWNERS + 1))
    self:RefreshUIIfShown()
end
