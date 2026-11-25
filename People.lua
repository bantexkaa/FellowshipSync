local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local People = FS.People

---------------------------------------------------------------------------
-- People I've Met
--   A personal log of the players you meet: who you grouped, traded and
--   whispered with, who killed you, and who you simply crossed paths with.
--
--   * Pencilled in: everyone you meet. Removed after a while (30 days by
--     default; people you grouped, traded or talked with last 3x longer).
--   * Inked in: people you chose to keep ("Remember this player"). Never removed.
--
--   Everything stays on this computer. Nothing here is ever synced.
---------------------------------------------------------------------------

local NEW_MEETING = 30 * 60   -- seeing someone again after this long counts as a new meeting
local SEEN_THROTTLE = 60      -- don't touch the same person more than once a minute just for "seen"
local PENCIL_MAX = 3000       -- most pencilled entries kept (oldest go first)
local INTERACTED_FACTOR = 3   -- grouped / traded / whispered / killed you: kept this many times longer
local ENEMY_WINDOW = 20       -- an enemy player seen this recently gets the blame when you die

People.KINDS = {
    { id = "g",    label = "Grouped" },
    { id = "tr",   label = "Traded" },
    { id = "w",    label = "Whispered" },
    { id = "kill", label = "Killed you" },
    { id = "seen", label = "Crossed paths" },
}

local function IsSecret(v) return issecretvalue and issecretvalue(v) end
local function Clean(v) if v == nil or IsSecret(v) then return nil end return v end

function People:Settings()
    local p = FS.db and FS.db.profile.people
    return p or { enabled = true, seen = true, days = 30, tooltip = true }
end

function People:Data()
    local g = FS.db.global
    g.people = g.people or {}
    return g.people
end

local function Interacted(rec) return (rec.g or 0) + (rec.tr or 0) + (rec.w or 0) + (rec.kill or 0) > 0 end
People.Interacted = Interacted

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

-- Same key format as the rest of FellowshipSync, so we can tell when someone
-- you met also plays with FellowshipSync in your network.
function People:UnitKey(unit)
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or not Clean(isPlayer) then return nil end
    local okMe, isMe = pcall(UnitIsUnit, unit, "player")
    if okMe and Clean(isMe) then return nil end
    return FS.Fellowship:MemberKey(unit)
end

function People:Touch(key, kind, unit, extra)
    if not key or key == "" or key:sub(-1) == "-" then return nil end
    local set = self:Settings()
    if set.enabled == false then return nil end
    local data, now = self:Data(), time()
    local rec = data[key]
    if not rec then
        if kind == "seen" and set.seen == false then return nil end
        rec = { k = key, first = now, met = 0, firstZone = Clean(GetRealZoneText and GetRealZoneText()), game = FS.GAME }
        data[key] = rec
        self.dirty = true
    end
    if now - (rec.last or 0) > NEW_MEETING then rec.met = (rec.met or 0) + 1 end
    rec.last = now
    local zone = Clean(GetRealZoneText and GetRealZoneText())
    if zone and zone ~= "" then rec.zone = zone end
    if kind ~= "seen" or (rec.seenAt or 0) < now - NEW_MEETING then
        rec[kind] = (rec[kind] or 0) + 1
        if kind == "seen" then rec.seenAt = now end
    end
    if unit then self:Describe(rec, unit) end
    if extra then for k, v in pairs(extra) do rec[k] = v end end
    self.dirty = true
    return rec
end

local function Ask(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return Clean(a), Clean(b), Clean(c)
end

function People:Describe(rec, unit)
    local _, classFile = Ask(UnitClass, unit)
    if classFile then rec.cls = classFile end
    local race = Ask(UnitRace, unit)
    if race then rec.race = race end
    local level = Ask(UnitLevel, unit)
    if type(level) == "number" and level > 0 then rec.lvl = level end
    local guild = Ask(GetGuildInfo, unit)
    if type(guild) == "string" and guild ~= "" then rec.guild = guild end
    local fac = Ask(UnitFactionGroup, unit)
    if fac then rec.fac = fac end
    local canAttack = Ask(UnitCanAttack, "player", unit)
    if canAttack ~= nil then
        -- an enemy is someone of the other faction you could attack (not a duel partner)
        rec.enemy = (canAttack and fac and fac ~= UnitFactionGroup("player")) or nil
    end
end

function People:SeeUnit(unit)
    if not FS.db or self:Settings().enabled == false then return end
    local key = self:UnitKey(unit)
    if not key then return end
    local now = GetTime()
    self.recent = self.recent or {}
    local data = self:Data()
    local rec = data[key]
    if rec then
        local okc, canAttack = pcall(UnitCanAttack, "player", unit)
        if okc and Clean(canAttack) and rec.enemy then self.lastEnemy = { key = key, at = now } end
    end
    if self.recent[key] and now - self.recent[key] < SEEN_THROTTLE then return end
    self.recent[key] = now
    rec = self:Touch(key, "seen", unit)
    if rec and rec.enemy then self.lastEnemy = { key = key, at = now } end
end

function People:ScanGroup()
    if not FS.db then return end
    local current = {}
    local raid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, count do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        local key = self:UnitKey(unit)
        if key then
            current[key] = true
            -- counted once per time you group up, not on every roster change
            if not (self.grouped and self.grouped[key]) then self:Touch(key, "g", unit) end
        end
    end
    self.grouped = current
end

function People:WhisperFrom(name, guid)
    if not FS.db then return end
    name = Clean(name)
    if not name or name == "" or FS:IsMe(name) then return end
    local base, realm = name:match("^([^%-]+)%-?(.*)$")
    if not base then return end
    local norm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm == "" or realm == norm then realm = FS:GetRealm() or "" end
    local key = base .. "-" .. realm
    -- Forever names have a surname the chat leaves out; use the entry we already have
    local data = self:Data()
    if not data[key] then
        local first = base:match("^[^%s%-]+")
        for k in pairs(data) do
            if k:match("^[^%s%-]+") == first and k:sub(-#realm - 1) == "-" .. realm then key = k break end
        end
    end
    -- one "whispered" per conversation (10 minutes apart)
    self.lastWhisper = self.lastWhisper or {}
    local now = time()
    if self.lastWhisper[key] and now - self.lastWhisper[key] < 600 then
        if data[key] then data[key].last = now end
        self.lastWhisper[key] = now
        return
    end
    self.lastWhisper[key] = now
    local rec = self:Touch(key, "w")
    if rec and guid and GetPlayerInfoByGUID then
        local ok, _, classFile, race = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            if Clean(classFile) then rec.cls = classFile end
            if Clean(race) then rec.race = race end
        end
    end
end

function People:Died()
    local e = self.lastEnemy
    if not e or GetTime() - e.at > ENEMY_WINDOW then return end
    local rec = self:Data()[e.key]
    if rec then
        rec.kill = (rec.kill or 0) + 1
        rec.last = time()
        self.dirty = true
    end
    self.lastEnemy = nil
end

---------------------------------------------------------------------------
-- Keeping and forgetting
---------------------------------------------------------------------------

function People:Ink(key, on, note)
    local rec = self:Data()[key]
    if not rec then return nil end
    rec.ink = on and true or nil
    if note ~= nil then rec.note = (note ~= "" and note) or nil end
    self.dirty = true
    return rec
end

function People:Forget(key)
    self:Data()[key] = nil
    self.dirty = true
end

-- "/fsync remember [note]" and the key binding: your target, or whoever you're hovering.
function People:RememberCurrent(note)
    for _, unit in ipairs({ "target", "mouseover" }) do
        local key = self:UnitKey(unit)
        if key then
            local rec = self:Data()[key] or self:Touch(key, "seen", unit)
            if not rec then return end
            self:Describe(rec, unit)
            self:Ink(key, true, note and note ~= "" and note or nil)
            FS:Print(string.format(FS.W.T("Remembered %s. Find them under Fellowship > People."), FS.ShortName(key))
                .. (rec.note and ("  \"" .. rec.note .. "\"") or ""))
            self:RefreshUI()
            return rec
        end
    end
    FS:Print(FS.W.T("Target or hover a player first, then use Remember."))
end

function People:ExpireAfter(rec, days)
    if rec.ink then return math.huge end
    return (rec.last or 0) + days * 86400 * (Interacted(rec) and INTERACTED_FACTOR or 1)
end

-- Removes pencilled entries that are too old, and the oldest if there are too many.
function People:Tidy()
    if not FS.db then return 0 end
    local data, now = self:Data(), time()
    local days = tonumber(self:Settings().days) or 30
    local removed, pencilled = 0, {}
    for key, rec in pairs(data) do
        if type(rec) ~= "table" then
            data[key] = nil
        elseif not rec.ink then
            if self:ExpireAfter(rec, days) < now then
                data[key] = nil
                removed = removed + 1
            else
                table.insert(pencilled, rec)
            end
        end
    end
    if #pencilled > PENCIL_MAX then
        table.sort(pencilled, function(a, b) return (a.last or 0) < (b.last or 0) end)
        for i = 1, #pencilled - PENCIL_MAX do
            data[pencilled[i].k] = nil
            removed = removed + 1
        end
    end
    return removed
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

function People:HowMet(rec)
    local parts = {}
    for _, kind in ipairs(self.KINDS) do
        local n = rec[kind.id]
        if n and n > 0 and kind.id ~= "seen" then
            table.insert(parts, FS.W.T(kind.label) .. (n > 1 and (" " .. n .. "x") or ""))
        end
    end
    if #parts == 0 then return FS.W.T("Crossed paths") end
    return table.concat(parts, ", ")
end

-- filter: "all", "kept", "grouped", "enemies"
function People:List(filter, query)
    local out = {}
    query = query and query ~= "" and query:lower() or nil
    for key, rec in pairs(self:Data()) do
        if type(rec) == "table" and (rec.game == nil or rec.game == FS.GAME) then
            local ok = filter == nil or filter == "all"
                or (filter == "kept" and rec.ink)
                or (filter == "grouped" and ((rec.g or 0) > 0 or (rec.tr or 0) > 0 or (rec.w or 0) > 0))
                or (filter == "enemies" and (rec.enemy or (rec.kill or 0) > 0))
            if ok and query then
                local hay = table.concat({ key, rec.guild or "", rec.zone or "", rec.firstZone or "", rec.note or "",
                    rec.race or "", rec.cls or "" }, " "):lower()
                ok = hay:find(query, 1, true) ~= nil
            end
            if ok then table.insert(out, rec) end
        end
    end
    table.sort(out, function(a, b) return (a.last or 0) > (b.last or 0) end)
    return out
end

function People:InNetwork(rec)
    local c = FS.db.global.characters[rec.k]
    return c and not c.isMock and not c.isMyChar and c or nil
end

---------------------------------------------------------------------------
-- Game tooltip: "Met 4 times, first 12 days ago in The Barrens"
---------------------------------------------------------------------------

function People:AddTooltip(tt)
    if not FS.db or not tt or not tt.GetUnit then return end
    local set = self:Settings()
    if set.enabled == false or set.tooltip == false then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not ok or not unit or IsSecret(unit) then return end
    local key = self:UnitKey(unit)
    local rec = key and self:Data()[key]
    if not rec then return end
    -- Not worth a line the first time you see someone, unless you kept them.
    if (rec.met or 0) < 2 and not Interacted(rec) and not rec.ink then return end
    local W = FS.W
    local line = string.format(W.T("Met %d times, first %s"), rec.met or 1, W.Plain(W.Ago(rec.first)))
    if rec.firstZone then line = line .. " " .. W.T("in") .. " " .. rec.firstZone end
    tt:AddLine((rec.ink and "|cffffd100*|r " or "") .. line, 0.75, 0.85, 1)
    if Interacted(rec) then tt:AddLine(self:HowMet(rec), 0.7, 0.7, 0.7) end
    if rec.note then tt:AddLine("\"" .. rec.note .. "\"", 0.6, 1, 0.6, true) end
    tt:Show()
end

function People:HookTooltip()
    if self.tooltipHooked then return end
    self.tooltipHooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then People:AddTooltip(tt) end
        end)
    elseif GameTooltip and GameTooltip.HookScript and (not GameTooltip.HasScript or GameTooltip:HasScript("OnTooltipSetUnit")) then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) People:AddTooltip(tt) end)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function People:RefreshUI()
    local view = FS.FellowshipUI
    if view and view.frame and view.frame:IsShown() and view.current == "people" then view:Refresh() end
end

function People:Enable()
    if self.frame then return end
    self:Tidy()
    self:HookTooltip()
    local f = CreateFrame("Frame")
    self.frame = f
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "TRADE_SHOW", "CHAT_MSG_WHISPER",
                         "CHAT_MSG_WHISPER_INFORM", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                         "NAME_PLATE_UNIT_ADDED", "PLAYER_DEAD" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, ...)
        if not FS.db or People:Settings().enabled == false then return end
        local ok, err = pcall(People.OnEvent, People, event, ...)
        if not ok and FS.Diag and FS.Diag.Note then FS.Diag:Note("People: " .. tostring(err)) end
    end)
    -- tidy once a day for people who never log out
    FS:ScheduleRepeatingTimer(function() People:Tidy() end, 86400)
end

function People:OnEvent(event, a1, a2, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        self:ScanGroup()
    elseif event == "TRADE_SHOW" then
        local key = self:UnitKey("npc") or self:UnitKey("NPC")
        if key then self:Touch(key, "tr", "npc") end
    elseif event == "CHAT_MSG_WHISPER" then
        local guid = select(10, ...)
        self:WhisperFrom(a2, guid)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local guid = select(10, ...)
        self:WhisperFrom(a2, guid)
    elseif event == "PLAYER_TARGET_CHANGED" then
        if self:Settings().seen ~= false then self:SeeUnit("target") end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if self:Settings().seen ~= false then self:SeeUnit("mouseover") end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if self:Settings().seen ~= false and a1 then self:SeeUnit(a1) end
    elseif event == "PLAYER_DEAD" then
        self:Died()
    end
end
