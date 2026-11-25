local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Share = FS.Share
local UI, W = FS.UI, FS.W
local T = function(s) return W.T(s) end

---------------------------------------------------------------------------
-- Share in chat: one line, previewed, never automatic, with a cooldown.
-- Export: the list you're looking at as CSV text.
-- What's new: a short note once after an update.
---------------------------------------------------------------------------

Share.COOLDOWN = 30
Share.last = {}
local CHANNELS = { { "guild", "Guild" }, { "group", "Party / Raid" }, { "say", "Say" } }

-- Plain, single-line chat text (max 255 characters including the prefix).
function Share:Clean(text)
    local s = W.Plain(text):gsub("[\r\n]+", " "):gsub("%s%s+", " ")
    local prefix = FS.db.profile.share.prefix ~= false and "[FellowshipSync] " or ""
    local room = 255 - #prefix
    if #s > room then s = s:sub(1, room - 3) .. "..." end
    return prefix .. s
end

function Share:ChatType(channel)
    if channel == "guild" then return IsInGuild() and "GUILD" or nil end
    if channel == "group" then
        if IsInRaid and IsInRaid() then return "RAID" end
        return (IsInGroup and IsInGroup()) and "PARTY" or nil
    end
    return "SAY"
end

function Share:Build()
    if self.frame then return end
    local f = W.Box(UIParent, "panel")
    f:SetSize(560, 190)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:Hide()
    f.title = W.Text(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(T("Share in Chat"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    f.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.preview:SetPoint("TOPLEFT", 14, -42)
    f.preview:SetWidth(530)
    f.preview:SetJustifyH("LEFT")
    f.preview:SetWordWrap(true)
    f.channels = {}
    for i, c in ipairs(CHANNELS) do
        local b = W.Button(f, c[2], 120, 24, function()
            FS.db.profile.share.channel = c[1]
            self.confirmSay = false
            self:Update()
        end)
        b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 126, 14)
        b.value = c[1]
        f.channels[i] = b
    end
    f.send = W.Button(f, "Send", 150, 24, function() self:Send() end)
    f.send:SetPoint("BOTTOMRIGHT", -14, 14)
    f.note = W.Text(f, "GameFontDisableSmall", "RIGHT")
    f.note:SetPoint("BOTTOMRIGHT", -14, 44)
    self.frame = f
end

function Share:Open(text)
    if not text or W.Plain(text) == "" then FS:Print(T("Nothing to share here.")) return end
    self:Build()
    self.text = self:Clean(text)
    self.confirmSay = false
    self:Update()
    self.frame:Show()
end

function Share:Update()
    local f, channel = self.frame, FS.db.profile.share.channel or "guild"
    f.preview:SetText(self.text or "")
    for _, b in ipairs(f.channels) do b:SetActive(b.value == channel) end
    local wait = self.COOLDOWN - (time() - (self.last[channel] or 0))
    if not self:ChatType(channel) then
        f.note:SetText(W.Color(channel == "guild" and T("You are not in a guild.") or T("You are not in a group."), "ff5555"))
    elseif wait > 0 then
        f.note:SetText(W.Color(string.format(T("Wait %d seconds before sharing here again."), wait), "ffd100"))
    else
        f.note:SetText(string.format(T("%d characters - one chat line"), #(self.text or "")))
    end
    f.send.text:SetText(self.confirmSay and T("Click again to say it") or T("Send"))
end

function Share:Send()
    local channel = FS.db.profile.share.channel or "guild"
    local chatType = self:ChatType(channel)
    if not chatType then self:Update() return end
    if time() - (self.last[channel] or 0) < self.COOLDOWN then self:Update() return end
    if channel == "say" and not self.confirmSay then
        self.confirmSay = true -- Say reaches strangers: one extra click
        self:Update()
        return
    end
    FS.Tracker.postingChronicle = true -- our own message doesn't count as chat
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, self.text, chatType)
    FS.Tracker.postingChronicle = false
    self.last[channel] = time()
    self.frame:Hide()
end

-- The biggest list visible in the current view (for Share's "top 3" and Export).
function Share:VisibleList()
    local best
    for list in pairs(W.lists) do
        if list.frame:IsVisible() and list.shownRows and #list.shownRows > 0 then
            if not best or #list.shownRows > #best.shownRows then best = list end
        end
    end
    return best
end

function Share:ActiveView()
    if UI.inspecting then return FS.Inspector end
    local v = UI.VIEWS[UI.currentTab]
    return v and FS[v.mod]
end

-- Main window "Share" button: the view's own summary, or the top 3 of the list shown.
function Share:ShareCurrent()
    local view = self:ActiveView()
    local text = view and view.ShareText and view:ShareText()
    if not text then
        local list = self:VisibleList()
        local title = view and view.title and view.title.GetText and view.title:GetText()
        text = list and list:TopLine(3, title)
    end
    self:Open(text)
end

-- Main window "Export" button: the list shown, as CSV.
local function Csv(value)
    local s = W.Plain(value)
    if s:find('[,"]') then s = '"' .. s:gsub('"', '""') .. '"' end
    return s
end
function Share:ExportCurrent()
    local list = self:VisibleList()
    if not list then FS:Print(T("There is no list to export here.")) return end
    local lines, head = {}, {}
    for _, col in ipairs(list.columns) do table.insert(head, Csv(col.headerText:GetText() or col.label)) end
    table.insert(lines, table.concat(head, ","))
    for _, row in ipairs(list.shownRows) do
        local cells = {}
        for c = 1, #list.columns do table.insert(cells, Csv(row.cells[c] or "")) end
        table.insert(lines, table.concat(cells, ","))
    end
    W.CopyBox(T("Export (CSV)"), table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- What's new (shown once after an update; never on a fresh install)
---------------------------------------------------------------------------

FS.WHATS_NEW = {
    ["3.13"] = {
        "New: People I've Met (Fellowship > People). A log of the players you group, trade and whisper with, who killed you, and who you cross paths with, with level, guild and where you met.",
        "Everyone is pencilled in and fades after 30 days (90 if you grouped, traded or talked). Keep someone and they stay forever, with a note.",
        "Remember this player: a key binding (Key Bindings > AddOns), /fsync remember <note>, or put /fsync remember in a macro.",
        "The game tooltip shows \"Met 4 times, first 12 days ago in The Barrens\" and your note.",
        "\"FS\" next to a name means they also use FellowshipSync in your network. This log stays on your computer and is never shared.",
    },
    ["3.12.4"] = {
        "Fixed a false \"AceSerializer-3.0 is missing\" message right after login. Nothing was missing: the first sync now simply waits until your character has loaded.",
    },
    ["3.12.3"] = {
        "Fixed an error at logout (\"bad argument to pairs\" in Tracker.lua) when another addon loads the settings library first.",
        "Fixed characters being saved twice when the game reports no realm name right after login. Existing doubles are merged automatically, which also removes the extra icons on the Alt Map.",
    },
    ["3.12.2"] = {
        "Alt Map: each of your characters now shows only once, at its last known place, and the character you're playing never has a parked icon.",
        "Live view is now off by default. Turn it on in Options > Basics or Options > Fellowship > Alt Map.",
        "The live view now draws a real trail behind you: a continuous line of where you've been this session, instead of scattered dots.",
    },
    ["3.12.1"] = {
        "Quieter guild chat: automatic chat announcements are now off for everyone. Switch them back on in Options > Notifications if you want them.",
        "When on: at most one every 10 minutes (max level and Hardcore deaths always go out), and if several of you kill a boss together, only one of you announces it.",
    },
    ["3.12"] = {
        "Live view: the character you're playing now shows on the world map with a glowing green ring, moving with you while the map is open.",
        "Hover it for your zone, subzone, coordinates and how long you've played this session. Click it for your profile.",
        "New coordinates bar under the world map: where you are and where your cursor points.",
        "Optional: a trail of where you've been this session.",
        "Optional (off by default): share where you are right now with your guild and friends, and see the ones who share theirs (cyan ring, your realm or a connected realm). Nothing is stored; icons vanish 90 seconds after someone stops.",
        "Settings in Options > Fellowship > Alt Map (the live view is also under Basics).",
    },
    ["3.11"] = {
        "Alt Map: your other characters now show on the world map, where you last played them. Hover for the zone, click for their profile.",
        "Optional (off by default): share where your other characters are parked with your guild and friends - never where you are right now.",
        "Optional (off by default): see the characters guildmates and friends share, only for your own or a connected realm.",
        "Find the settings in Options > Fellowship > Alt Map (the main one is also under Basics).",
    },
    ["3.10.1"] = {
        "Much faster with big guilds and networks: pages draw up to 8 times faster, and long lists only draw the rows you can see.",
        "The ? help button now sits in the top bar, next to search, and explains whichever page you're on (no more overlapping).",
        "Options: a clear bar at the top switches between the most-used settings and all settings.",
        "/fsync debug: a report you can copy into a bug report (versions, libraries, settings, recent errors).",
        "/fsync perf: memory, saved-data size and how long FellowshipSync's background work takes.",
        "Light mode for older PCs (Options): skips zone time, the play-time clock and calendar, falls and hearthstone tracking.",
    },
    ["3.10"] = {
        "New Progress page (Players group): Session, Goals, Calendar, Snapshots and Titles.",
        "Session summary with live rates: kills, gold and XP per hour, and your time to next level. Share it in chat.",
        "Mini panel: a few live numbers on screen while you play (/fsync mini).",
        "Personal goals with a toast when you reach them, and a play-time calendar for the last year.",
        "Snapshots: save your stats at a moment that matters and see what changed since.",
        "Stat titles like the Jumper or the Night Owl for whoever leads a stat, shown in tooltips.",
        "Your longest-held quest, an explorer rank, and a (just for fun) death prediction in the Deathlog.",
        "FellowshipSync now has its own logo in the addon list, on the minimap button and in the window.",
    },
    ["3.9"] = {
        "Hall of Shame (Records): embarrassing deaths, leaps of faith, biggest fall survived, hearthstone regrets, biggest repair bill, and how much you walked when you could ride.",
        "Luck & Revenge (Records): your roll win rate against the guild average, natural 1s, rolls lost, revenge kills and levels earned from rested XP.",
        "Revenge! Kill the kind of enemy that last killed you and you'll know about it.",
        "A Spirit Healer loyalty card every 10th visit.",
        "Did you know? A new fun fact from your own numbers each time you open the window.",
        "New scoreboards (Hall of Shame, Avengers) and Weekly Chronicle awards.",
    },
    ["3.8"] = {
        "Tidier window: six groups (Leaderboards, Players, History, Fellowship, Guild, Options) with pages underneath.",
        "Search everything: characters, enemies, bosses, killers and zones from one box.",
        "Click a toast to jump straight to what it's about.",
        "Pin players (Inspector > Pin): they also show at the top of leaderboards. Your rival is pinned automatically.",
        "Leaderboards show who moved up or down this week.",
        "A ? next to every page title explains what it shows and how it's counted.",
        "Options: Simple (the most-used settings) or Advanced (everything); choose which page and view the window opens on.",
        "Colour-blind friendly colours (Options).",
    },
    ["3.7.1"] = {
        "Legacy Points now show correctly on WoW: Forever (each completed Legacy Challenge counts as one point).",
        "Milestones for most stats: kills, quests, jumps, fish, gold, playtime, exploration and many more.",
        "Distance milestones in metres, then whole kilometres (or yards, then miles) - plus a marathon surprise.",
        "Account milestones: all your characters together (can be switched off in Notifications).",
        "Several milestones at once now arrive as one summary toast.",
        "Legacy Race: a new By Player view showing each character's next Legacy Point.",
    },
    ["3.7"] = {
        "Sort any list: click a column header (click again to reverse). Your choice is saved.",
        "FellowshipSync settings now also live in Esc > Options > AddOns.",
        "Share button: post a one-line summary in guild, party/raid or say chat.",
        "Export button: copy any list as CSV for spreadsheets or Discord.",
        "Fewer, better milestones: professions every 50, GearScore in round steps, level-ups every 10.",
        "Key binding to open the window, and the window can be resized from its corner.",
        "Guildmates' stats in the game tooltip, and a Compare view for any two characters.",
        "German, French and Spanish translations of the main interface.",
    },
}

function Share:CheckWhatsNew()
    local g = FS.db.global
    local version = FS.VERSION
    local seen = g.lastVersion
    g.lastVersion = version
    if not seen or seen == version then return end -- fresh install or same version
    -- This exact version's notes; or, when coming from an older version family, that family's notes.
    local family = version:match("^(%d+%.%d+)") or ""
    local notes = FS.WHATS_NEW[version] or ((seen:match("^(%d+%.%d+)") ~= family) and FS.WHATS_NEW[family]) or nil
    if not notes then return end
    local f = self.whatsNew
    if not f then
        f = W.Box(UIParent, "panel")
        f:SetSize(560, 300)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f.title = W.Text(f, "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.body:SetPoint("TOPLEFT", 16, -44)
        f.body:SetWidth(528)
        f.body:SetJustifyH("LEFT")
        f.body:SetWordWrap(true)
        f.ok = W.Button(f, "Got it", 120, 26, function() f:Hide() end)
        f.ok:SetPoint("BOTTOMRIGHT", -16, 14)
        self.whatsNew = f
    end
    f.title:SetText(string.format(T("What's new in FellowshipSync %s"), version))
    local lines = {}
    for _, n in ipairs(notes) do table.insert(lines, "- " .. T(n)) end
    f.body:SetText(table.concat(lines, "\n"))
    f:Show()
end
