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
