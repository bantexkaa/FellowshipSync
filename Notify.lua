local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Notify = FS.Notify
local W = FS.W

---------------------------------------------------------------------------
-- Toasts and chat announcements. Every event goes through FS:AddEvent, which
-- calls Notify:OnEvent. Your own events can become toasts and (optionally)
-- chat announcements; guildmates' and friends' events can become toasts.
---------------------------------------------------------------------------

local RECENT = 900          -- only toast network events from the last 15 minutes
local CHAT_SPACING = 2.5    -- seconds between chat announcements
local AUTO_COOLDOWN = 600   -- automatic announcements: at most one per 10 minutes (max level and Hardcore deaths excepted)
local DEDUPE_WINDOW = 90    -- skip a boss announcement if someone else already posted it this recently

function Notify:Settings() return FS.db.profile.notify end

local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|", "/"))
end
Notify.Plain = Plain

---------------------------------------------------------------------------
-- Facts used in the messages
---------------------------------------------------------------------------

-- Nobody else (guild, friends, your alts) has a dated first for this key before this event.
function Notify:IsGuildFirst(ev, key)
    for name, rec in pairs(FS.db.global.characters) do
        if name ~= ev.who and not rec.isMock then
            local t = tonumber(rec.firsts and rec.firsts[key]) or 0
            if t > 0 and t < (ev.t or time()) then return false end
        end
    end
    return true
end

-- Played time to max level and rank among everyone known (e.g. 2d 4h, #3).
function Notify:Speedrun(who)
    local rec = FS.db.global.characters[who]
    local maxLevel = FS:MaxLevel()
    local t = rec and rec.levelTimes and tonumber(rec.levelTimes[maxLevel])
    if not t or t <= 0 then return nil end
    local rank = 1
    for name, other in pairs(FS.db.global.characters) do
        local o = other.levelTimes and tonumber(other.levelTimes[maxLevel])
        if name ~= who and not other.isMock and o and o > 0 and o < t then rank = rank + 1 end
    end
    return t, rank
end

---------------------------------------------------------------------------
-- What the player wants to hear about
---------------------------------------------------------------------------

function Notify:WantOwnToast(ev)
    local own = self:Settings().own
    if ev.kind == "accmilestone" then return own.account ~= false end
    if ev.kind == "fun" then return own.fun ~= false end
    if ev.kind == "level" then
        local v = tonumber(ev.v) or 0
        return own.level == "all" or (own.level == "max" and v == FS:MaxLevel())
            or (own.level == "tens" and (v % 10 == 0 or v == FS:MaxLevel()))
    end
    if ev.kind == "death" then return false end -- the game makes that clear already
    return own[ev.kind] ~= false and own[ev.kind] ~= nil
end

function Notify:WantGuildToast(ev)
    local g = self:Settings().guild
    local kind = ev.kind
    if kind == "boss" then
        if g.boss == "all" then return true end
        return g.boss == "first" and self:IsGuildFirst(ev, "boss:" .. tostring(ev.a))
    elseif kind == "level" then
        local v, max = tonumber(ev.v) or 0, FS:MaxLevel()
        return (g.level == "max" and v == max) or (g.level == "tens" and (v == max or v % 10 == 0))
    elseif kind == "prof" then
        return g.prof == true and (tonumber(ev.v) or 0) >= FS.ProfMax()
    end
    return g[kind] == true
end

function Notify:WantAnnounce(ev)
    local a = self:Settings().ann
    local kind, max = ev.kind, FS:MaxLevel()
    if kind == "level" then
        local v = tonumber(ev.v) or 0
        return (a.maxlevel and v == max) or (a.levels and v % 10 == 0 and v ~= max)
    elseif kind == "boss" then
        if a.boss == "all" then return true end
        return a.boss == "first" and self:IsGuildFirst(ev, "boss:" .. tostring(ev.a))
    elseif kind == "prof" then
        return a.prof == true and (tonumber(ev.v) or 0) >= FS.ProfMax()
    end
    return a[kind] == true
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------

-- title, description, icon for a toast. mine = your own event.
function Notify:ToastText(ev, mine)
    if ev.kind == "fun" then return ev.title or "Fun!", tostring(ev.a or ""), "Interface\\Icons\\INV_Misc_Toy_07" end
    local _, sentence, icon = W.EventText(ev)
    local rec = FS.db.global.characters[ev.who]
    local who = rec and W.CharName(rec) or FS.ShortName(ev.who)
    local kind = ev.kind
    if kind == "level" and tonumber(ev.v) == FS:MaxLevel() then
        local t, rank = self:Speedrun(ev.who)
        local speed = t and string.format(" after %s played (#%d)", W.Duration(t), rank) or ""
        return mine and "Max Level!" or "Guild: Max Level",
            (mine and "You" or who) .. " reached level " .. ev.v .. speed .. "!", icon
    elseif kind == "boss" then
        local first = self:IsGuildFirst(ev, "boss:" .. tostring(ev.a))
        return first and "Guild First!" or (mine and "First Boss Kill!" or "Boss Down"),
            string.format("%s defeated %s%s", mine and "You" or who, W.Color(ev.a or "?", "ffd100"),
                first and " before anyone else!" or " for the first time."), icon
    elseif kind == "record" then
        return mine and "New Record!" or "Guild: New Record",
            string.format("%s down in %s%s", W.Color(ev.a or "?", "ffd100"), W.FightTime(ev.v), mine and "" or (" by " .. who)), icon
    elseif kind == "fallen" then
        return "Rest in Peace", sentence, icon
    elseif kind == "death" then
        return "Guild: Death", sentence, icon
    elseif kind == "bounty" then
        return "Guild Bounty Complete!", W.Color(tostring(ev.a), "ffd100") .. " - well done, everyone!", icon
    elseif kind == "wager" then
        local v = tonumber(ev.v) or 0
        return v >= 0 and "Wager Won!" or "Wager Lost",
            string.format("%s %s Fellowship Marks: %s", v >= 0 and "You won" or "You lost", W.Num(math.abs(v)), tostring(ev.a)), icon
    elseif kind == "rival" then
        return "You Have a Rival!", who .. " named " .. W.CharName(FS.db.global.characters[ev.a] or {}) .. " as their rival.", icon
    end
    local titles = { gear = "New GearScore Record!", legacy = FS.POINTS.item .. " Complete!", level = "Level Up!",
                     prof = "Profession Milestone!", milestone = "Milestone Reached!", accmilestone = "Account Milestone!" }
    return (mine and titles[kind]) or ("Guild: " .. (titles[kind] or "News")), sentence, icon
end

-- Plain chat line for one of your own events.
function Notify:ChatText(ev)
    local n = self:Settings()
    local name = FS.ShortName(ev.who)
    local kind, text = ev.kind, nil
    if kind == "level" then
        local t, rank = self:Speedrun(ev.who)
        if tonumber(ev.v) == FS:MaxLevel() and t then
            text = string.format("%s reached level %s after %s played! (#%d fastest)", name, ev.v, W.Duration(t), rank)
        else
            text = string.format("%s reached level %s!", name, tostring(ev.v))
        end
    elseif kind == "boss" then
        local first = self:IsGuildFirst(ev, "boss:" .. tostring(ev.a))
        text = string.format("%s defeated %s for the first time!%s", name, tostring(ev.a), first and " (guild first)" or "")
    elseif kind == "record" then
        text = string.format("New record: %s down in %s!", tostring(ev.a), W.FightTime(ev.v))
    elseif kind == "legacy" then
        text = string.format("%s completed the %s: %s!", name, FS.POINTS.item, Plain(ev.a))
    elseif kind == "prof" then
        text = string.format("%s reached %s %s!", name, tostring(ev.a), tostring(ev.v))
    elseif kind == "fallen" then
        local rec = FS.db.global.characters[ev.who]
        local hc = rec and rec.hc
        text = string.format("RIP %s, level %s %s, fell in %s to %s.", name, tostring(ev.v or "?"),
            rec and W.ClassName(rec.cls) or "", ev.z or "an unknown place", ev.a or "unknown causes")
        if n.lastWords and hc and hc.words then text = text .. ' Last words: "' .. hc.words .. '"' end
    end
    if not text then return nil end
    text = Plain(text)
    if n.prefix then text = "[FellowshipSync] " .. text end
    return text:sub(1, 255)
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

function Notify:OnEvent(ev)
    if ev.mock or ev.quiet or not FS.db then return end -- quiet: already part of a summary toast
    local n = self:Settings()
    if ev.mine then
        if n.toasts and self:WantOwnToast(ev) then
            local title, desc, icon = self:ToastText(ev, true)
            FS.Extras:ShowToast(title, desc, icon, false, ev)
        end
        if n.announce and self:WantAnnounce(ev) then self:AutoAnnounce(ev) end
        return
    end
    if (tonumber(ev.t) or 0) < time() - RECENT then return end -- old news (e.g. right after someone logs in)
    if n.toasts and self:WantGuildToast(ev) then
        local title, desc, icon = self:ToastText(ev, false)
        FS.Extras:ShowToast(title, desc, icon, true, ev)
    end
end

function Notify:VersionNotice(version, who)
    if self:Settings().versionToast == false then return end
    FS.Extras:ShowToast("Update Available", string.format("FellowshipSync %s is out%s. You have %s.", version,
        who and (" (" .. who .. " has it)") or "", FS.VERSION), "Interface\\Icons\\INV_Misc_Note_01", false)
end

---------------------------------------------------------------------------
-- Chat announcements: queued, paced, and only sent when the game allows it.
---------------------------------------------------------------------------

function Notify:Channels()
    local channel, out = self:Settings().channel, {}
    if (channel == "guild" or channel == "both") and IsInGuild() then table.insert(out, "GUILD") end
    if channel == "group" or channel == "both" then
        if IsInRaid and IsInRaid() then table.insert(out, "RAID")
        elseif IsInGroup and IsInGroup() then table.insert(out, "PARTY") end
    end
    return out
end

---------------------------------------------------------------------------
-- Keeping guild chat quiet
--   * Automatic announcements are off by default; 3.12 switches them off once
--     for everyone who had them on (with a note), since guilds found them spammy.
--   * At most one automatic announcement per 10 minutes.
--   * Boss kills and records: wait a few seconds and stay quiet if a groupmate's
--     FellowshipSync already announced the same boss.
---------------------------------------------------------------------------

function Notify:QuietChatOnce()
    local n = FS.db and self:Settings()
    if not n or n.chatReset312 then return end
    n.chatReset312 = true
    if n.announce then
        n.announce = false
        FS:Print("Chat announcements are now off by default, to keep guild chat quiet. "
            .. "You can switch them back on in Options > Notifications.")
    end
end

local function Unsecret(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v or nil end

function Notify:WatchChat()
    if self.chatWatch then return end
    self.recentChat = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                         "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, _, msg, sender)
        msg, sender = Unsecret(msg), Unsecret(sender)
        if not msg or not msg:find("[FellowshipSync]", 1, true) or (sender and FS:IsMe(sender)) then return end
        local now = time()
        for i = #self.recentChat, 1, -1 do if now - self.recentChat[i].t > DEDUPE_WINDOW then table.remove(self.recentChat, i) end end
        table.insert(self.recentChat, { t = now, msg = msg })
    end)
    self.chatWatch = f
end

function Notify:SomeoneSaid(key)
    if not key or key == "" then return false end
    local now = time()
    for _, r in ipairs(self.recentChat or {}) do
        if now - r.t <= DEDUPE_WINDOW and r.msg:find(key, 1, true) then return true end
    end
    return false
end

function Notify:AutoAnnounce(ev)
    local text = self:ChatText(ev)
    if not text then return end
    local important = ev.kind == "fallen" or (ev.kind == "level" and (tonumber(ev.v) or 0) == FS:MaxLevel())
    if not important and time() - (self.lastAuto or 0) < AUTO_COOLDOWN then return end
    self.lastAuto = time()
    local key = (ev.kind == "boss" or ev.kind == "record") and ev.a and Plain(ev.a) or nil
    if not key then return self:Announce(text) end
    -- Several of you killed it together: let one of you speak.
    self:WatchChat()
    FS:ScheduleTimer(function()
        if not self:SomeoneSaid(key) then self:Announce(text) end
    end, math.random(2, 8))
end

-- channels: optional list (e.g. { "GUILD" }); default = the channel chosen in Options.
function Notify:Announce(text, channels, limit)
    if not text then return end
    self.chatQueue = self.chatQueue or {}
    if #self.chatQueue >= (limit or 10) then return end
    table.insert(self.chatQueue, { text = text, channels = channels })
    self:PumpChat()
end

function Notify:CanChat()
    if InCombatLockdown() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
    return true
end

function Notify:PumpChat()
    if self.chatBusy or not self.chatQueue or #self.chatQueue == 0 then return end
    if not self:CanChat() then
        self.chatBusy = true -- try again shortly
        FS:ScheduleTimer(function() self.chatBusy = false; self:PumpChat() end, 5)
        return
    end
    local item = table.remove(self.chatQueue, 1)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    FS.Tracker.postingChronicle = true
    for _, channel in ipairs(item.channels or self:Channels()) do pcall(send, item.text:sub(1, 255), channel) end
    FS.Tracker.postingChronicle = false
    self.chatBusy = true
    FS:ScheduleTimer(function() self.chatBusy = false; self:PumpChat() end, CHAT_SPACING)
end

-- Shows what an announcement would look like, in your own chat frame only.
function Notify:Preview()
    local me = FS:GetPlayerKey()
    local samples = {
        { kind = "level", who = me, v = FS:MaxLevel(), t = time() },
        { kind = "boss", who = me, a = "Ragnaros", t = time() },
        { kind = "record", who = me, a = "Ragnaros", v = 95, t = time() },
    }
    if FS.HAS_POINTS then table.insert(samples, { kind = "legacy", who = me, a = "Reach level 25", t = time() }) end
    FS:Print("Announcement preview (only you can see this):")
    for _, ev in ipairs(samples) do
        local text = self:ChatText(ev)
        if text then FS:Print("  " .. text) end
    end
end
