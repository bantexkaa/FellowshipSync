local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Games = FS.Games
local IsSecret = FS.IsSecret

---------------------------------------------------------------------------
-- Deathroll: players take turns "/roll N", each time rolling up to the previous result.
-- Whoever rolls 1 loses. The opponent doesn't need FellowshipSync: their /roll results
-- are read from the normal system messages.
--
-- Raffle: players join by typing a keyword in the chosen chat; the host spins a wheel.
---------------------------------------------------------------------------

local CHANNEL_EVENTS = {
    guild = { CHAT_MSG_GUILD = true },
    group = { CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
              CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true },
}

function Games:Enable()
    LibStub("AceEvent-3.0"):Embed(self)
    FS.SafeRegister(self, "CHAT_MSG_SYSTEM")
    for _, events in pairs(CHANNEL_EVENTS) do
        for ev in pairs(events) do FS.SafeRegister(self, ev, "OnChat") end
    end
    self.raffle = { open = false, entrants = {} }
end

local function Short(name) return FS.ShortName(name or "") end
local function Toast(title, text, icon)
    if FS.db.profile.notify.toasts then FS.Extras:ShowToast(title, text, icon, false) end
end

---------------------------------------------------------------------------
-- Deathroll
---------------------------------------------------------------------------

function Games:StartDeathroll(opponent, start, stake)
    opponent = strtrim(tostring(opponent or ""))
    start = math.floor(tonumber(start) or 0)
    if opponent == "" then return false, "Enter your opponent's name (or target them and press Use Target)." end
    if start < 2 or start > 1000000 then return false, "Start at a number between 2 and 1,000,000." end
    self.dr = { opponent = Short(opponent), start = start, current = start, rolls = {}, active = true,
                stake = strtrim(tostring(stake or "")):sub(1, 30), started = time() }
    return true
end

function Games:Roll()
    local dr = self.dr
    if not dr or not dr.active then return false end
    if RandomRoll then RandomRoll(1, dr.current) end
    return true
end

function Games:CancelDeathroll()
    if self.dr then self.dr.active = false end
    self.dr = nil
end

function Games:CHAT_MSG_SYSTEM(_, msg)
    local dr = self.dr
    if not dr or not dr.active or type(msg) ~= "string" or IsSecret(msg) then return end
    local roll = FS.Tracker.MatchFormat(msg, RANDOM_ROLL_RESULT)
    if not roll then return end
    local name, value, low, high = roll[1], tonumber(roll[2]), tonumber(roll[3]), tonumber(roll[4])
    if low ~= 1 or high ~= dr.current or not value then return end
    local mine = FS:IsMe(name)
    if not mine and Short(name) ~= dr.opponent then return end
    table.insert(dr.rolls, { who = mine and "me" or "them", value = value, max = high })
    dr.current = value
    if value == 1 then self:FinishDeathroll(mine) end
    FS:QueueUIRefresh()
end

function Games:FinishDeathroll(iLost)
    local dr = self.dr
    dr.active = false
    local history = FS.db.global.deathrolls
    table.insert(history, 1, { t = time(), opponent = dr.opponent, start = dr.start, rolls = #dr.rolls, won = not iLost, stake = dr.stake })
    for i = #history, 51, -1 do history[i] = nil end
    Toast(iLost and "Deathroll Lost" or "Deathroll Won!",
        string.format("%s %s after %d rolls%s.", iLost and "You rolled the 1 against" or "You beat", dr.opponent, #dr.rolls,
            dr.stake ~= "" and (" (" .. dr.stake .. ")") or ""), "Interface\\Icons\\INV_Misc_Dice_02")
end

function Games:DeathrollRecord()
    local won, lost = 0, 0
    for _, g in ipairs(FS.db.global.deathrolls) do if g.won then won = won + 1 else lost = lost + 1 end end
    return won, lost
end

---------------------------------------------------------------------------
-- Raffle
---------------------------------------------------------------------------

function Games:RaffleSettings() return FS.db.global.raffleSettings end

function Games:OpenRaffle()
    local s = self:RaffleSettings()
    if strtrim(s.keyword or "") == "" then return false, "Choose a keyword first." end
    self.raffle = { open = true, entrants = {}, opened = time() }
    if s.announce then self:AnnounceRaffle() end
    return true
end

function Games:CloseRaffle() self.raffle.open = false end

function Games:Channels()
    local s = self:RaffleSettings()
    if s.channel == "group" then
        if IsInRaid and IsInRaid() then return { "RAID" } end
        if IsInGroup and IsInGroup() then return { "PARTY" } end
        return {}
    end
    return IsInGuild() and { "GUILD" } or {}
end

function Games:AnnounceRaffle()
    local s = self:RaffleSettings()
    local where = s.channel == "group" and "party/raid chat" or "guild chat"
    FS.Notify:Announce(string.format("[FellowshipSync] Raffle open! Type '%s' in %s to join.%s", s.keyword, where,
        (s.fee or "") ~= "" and string.format(" Ticket: %s to %s.", s.fee, Short(FS:GetPlayerKey())) or ""), self:Channels(), 20)
end

function Games:OnChat(event, msg, sender)
    local r = self.raffle
    if not r or not r.open or IsSecret(msg) or IsSecret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    local s = self:RaffleSettings()
    if not (CHANNEL_EVENTS[s.channel] or {})[event] then return end
    if strtrim(msg):lower() ~= strtrim(s.keyword or ""):lower() then return end
    local name = Short(Ambiguate and Ambiguate(sender, "none") or sender)
    for _, e in ipairs(r.entrants) do if e.name == name then return end end
    table.insert(r.entrants, { name = name, paid = false, joined = time() })
    FS:QueueUIRefresh()
end

function Games:AddEntrant(name)
    name = Short(strtrim(tostring(name or "")))
    if name == "" then return end
    for _, e in ipairs(self.raffle.entrants) do if e.name == name then return end end
    table.insert(self.raffle.entrants, { name = name, paid = false, joined = time() })
end

function Games:TogglePaid(name)
    for _, e in ipairs(self.raffle.entrants) do if e.name == name then e.paid = not e.paid end end
end

function Games:Pool()
    local s, pool = self:RaffleSettings(), {}
    for _, e in ipairs(self.raffle.entrants) do
        if e.paid or not s.onlyPaid then table.insert(pool, e.name) end
    end
    return pool
end

-- Picks the winner now (fair random draw); the wheel animation only shows it.
function Games:DrawWinner()
    local pool = self:Pool()
    if #pool == 0 then return nil, "Nobody to draw from yet." end
    local winner = pool[math.random(1, #pool)]
    self.raffle.open = false
    local history = FS.db.global.raffles
    table.insert(history, 1, { t = time(), winner = winner, entries = #pool, keyword = self:RaffleSettings().keyword })
    for i = #history, 31, -1 do history[i] = nil end
    return winner, pool
end

function Games:AnnounceWinner(winner, entries)
    if self:RaffleSettings().announce then
        FS.Notify:Announce(string.format("[FellowshipSync] The raffle winner is %s! (%d tickets) Congratulations!", winner, entries),
            self:Channels(), 20)
    end
    Toast("Raffle Winner", winner .. " won the raffle!", "Interface\\Icons\\INV_Misc_Coin_17")
end
