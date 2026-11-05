local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local View = FS.FellowshipUI
local UI, W = FS.UI, FS.W
local F = FS.Fellowship

local TABS = {
    { id = "bonds",    label = "Bonds" },
    { id = "bounties", label = "Guild Bounties" },
    { id = "book",     label = "Book of Deeds" },
    { id = "deathmap", label = "Deathmap" },
    { id = "memories", label = "Memory Lane" },
    { id = "wagers",   label = "Wagers" },
    { id = "rivals",   label = "Rivalries" },
    { id = "games",    label = "Games" },
}
local TOP = -90

local function NameFor(key, cls)
    local rec = FS.db.global.characters[key]
    if rec then return W.Label(rec, { owner = false }), rec end
    return W.Color(FS.ShortName(key), cls and W.ClassHex(cls) or "ffffff"), nil
end

function View:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current = "bonds"
    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetWidth(700)
    self.panes = {}
    self:BuildBonds(f)
    self:BuildBounties(f)
    self:BuildBook(f)
    self:BuildDeathmap(f)
    self:BuildMemories(f)
    self:BuildWagers(f)
    self:BuildRivals(f)
    self:BuildGames(f)
end

local function Pane(self, id, parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    self.panes[id] = p
    return p
end

local function Place(list, top, bottom)
    list.frame:ClearAllPoints()
    list.frame:SetPoint("TOPLEFT", 14, top)
    list.frame:SetPoint("BOTTOMRIGHT", -12, bottom or 10)
end

function View:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    for id, p in pairs(self.panes) do p:SetShown(id == self.current) end
    local fn = self["Refresh_" .. self.current]
    if fn then fn(self) end
end

---------------------------------------------------------------------------
-- 1. Bonds
---------------------------------------------------------------------------

function View:BuildBonds(f)
    local p = Pane(self, "bonds", f)
    self.bondList = W.List(p, {
        { label = "#", width = 32 }, { label = "Companion", width = 230 }, { label = "Bond", width = 110 },
        { label = "Time Together", width = 110, justify = "RIGHT" }, { label = "Bosses", width = 70, justify = "RIGHT" },
        { label = "Deaths", width = 70, justify = "RIGHT" }, { label = "Rezzes", width = 70, justify = "RIGHT" },
        { label = "Last Together", width = 150, justify = "RIGHT" },
    }, { onClick = function(rec) UI:OpenInspector(rec) end,
         emptyText = "No bonds yet. Time spent grouped with other players is counted automatically." })
    Place(self.bondList, TOP)
end

function View:Refresh_bonds()
    local solo = UI.currentScope == "solo"
    local rows = {}
    if solo then
        self.title:SetText("Fellowship Bonds  -  Your Closest Companions")
        self.sub:SetText("Time grouped together, bosses killed together, deaths suffered together, and who resurrected you.")
        self.bondList:SetColumnLabel(2, "Companion")
        for i, m in ipairs(F:MyCompanions()) do
            local label, rec = NameFor(m.key, m.cls)
            local level, hex = F.BondLevel(m.time)
            rows[i] = { rec = rec, cells = { W.Rank(i), label, W.Color(level, hex), W.RankValue(i, W.Duration(m.time)),
                W.Num(m.bosses), W.Num(m.deaths), W.Num(m.rezzes), W.Ago(m.last) } }
        end
    else
        self.title:SetText("Fellowship Bonds  -  Strongest Pairs in " .. UI.SCOPE_TITLES[UI.currentScope])
        self.sub:SetText("Who plays together most. Each pair is shown once.")
        self.bondList:SetColumnLabel(2, "Pair")
        for i, pr in ipairs(F:GuildBonds(UI.currentScope)) do
            local a, recA = NameFor(pr.a)
            local b = NameFor(pr.b, pr.cls)
            local level, hex = F.BondLevel(pr.time)
            rows[i] = { rec = recA, cells = { W.Rank(i), a .. W.Color(" & ", "888888") .. b, W.Color(level, hex),
                W.RankValue(i, W.Duration(pr.time)), W.Num(pr.bosses), W.Num(pr.deaths), "", "" } }
            if i >= 200 then break end
        end
    end
    self.bondList:SetRows(rows)
end

---------------------------------------------------------------------------
-- 2. Guild Bounties
---------------------------------------------------------------------------

function View:BuildBounties(f)
    local p = Pane(self, "bounties", f)
    self.bountyCards = {}
    for i = 1, 3 do
        local card = W.Box(p, "card")
        card:SetPoint("TOPLEFT", 14, TOP - (i - 1) * 104)
        card:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        card:SetHeight(96)
        card.title = W.Text(card, "GameFontNormalLarge")
        card.title:SetPoint("TOPLEFT", 12, -10)
        card.status = W.Text(card, "GameFontNormal", "RIGHT")
        card.status:SetPoint("TOPRIGHT", -12, -12)
        card.bar = CreateFrame("StatusBar", nil, card)
        card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        card.bar:SetPoint("TOPLEFT", 12, -36)
        card.bar:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.bar:SetHeight(18)
        card.bar.bg = card.bar:CreateTexture(nil, "BACKGROUND")
        card.bar.bg:SetAllPoints()
        card.bar.bg:SetColorTexture(0, 0, 0, 0.5)
        card.progress = W.Text(card.bar, "GameFontHighlightSmall", "CENTER")
        card.progress:SetAllPoints()
        card.top = W.Text(card, "GameFontHighlightSmall")
        card.top:SetPoint("TOPLEFT", 12, -64)
        card.top:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        self.bountyCards[i] = card
    end
    self.bountyWall = W.List(p, {
        { label = "Completed", width = 130 }, { label = "Bounty", width = 470 }, { label = "Top Contributor", width = 330 },
    }, { noTooltip = true, emptyText = "The Bounty Wall is empty. Finish a weekly bounty together to get on it!" })
    Place(self.bountyWall, TOP - 3 * 104 - 6)
end

function View:Refresh_bounties()
    F:CheckBounties()
    local bounties, players = F:CurrentBounties()
    self.title:SetText("Guild Bounties  -  Week of " .. date("%d.%m.%Y", math.max(0, FS:WeekStart())))
    self.sub:SetText(string.format("Three challenges for the whole guild, new every week. Targets scale with active players (%d this week).", players))
    local pal = W.Pal()
    for i, card in ipairs(self.bountyCards) do
        local b = bounties[i]
        card:SetShown(b ~= nil)
        if b then
            card.title:SetText(b.title)
            W.AccentText(card.title)
            local share = math.min(1, b.progress / math.max(1, b.target))
            card.bar:SetMinMaxValues(0, 1)
            card.bar:SetValue(b.def.under and math.min(1, share) or share)
            if b.def.under then
                card.bar:SetStatusBarColor(b.failed and 0.8 or 0.2, b.failed and 0.2 or 0.7, 0.2, 0.9)
                card.progress:SetText(string.format("%s of %s deaths so far", W.Num(b.progress), W.Num(b.target)))
                card.status:SetText(b.failed and W.Color("FAILED", "ff5555") or W.Color("ON TRACK", "1eff00"))
            else
                card.bar:SetStatusBarColor(pal.accent[1], pal.accent[2], pal.accent[3], 0.9)
                card.progress:SetText(string.format("%s / %s  (%d%%)", F:FormatBountyAmount(b.def, b.progress),
                    F:FormatBountyAmount(b.def, b.target), math.floor(share * 100)))
                card.status:SetText(b.done and W.Color("COMPLETE!", "1eff00") or W.Color(math.floor(share * 100) .. "%", "ffd100"))
            end
            local tops = {}
            for j = 1, math.min(3, #b.contributors) do
                local c = b.contributors[j]
                table.insert(tops, W.CharName(c.rec) .. W.Color(" (" .. F:FormatBountyAmount(b.def, c.v) .. ")", "888888"))
            end
            card.top:SetText(#tops > 0 and ("Top contributors: " .. table.concat(tops, ",  ")) or W.Color("Nobody has contributed yet.", "777777"))
        end
    end
    local wall = {}
    for _, e in pairs(FS.db.global.bountyDone) do table.insert(wall, e) end
    table.sort(wall, function(a, b) return (a.t or 0) > (b.t or 0) end)
    local rows = {}
    for i, e in ipairs(wall) do
        local top = e.top and FS.db.global.characters[e.top]
        rows[i] = { cells = { W.Color(W.Date(e.t), "aaaaaa"), W.Color(e.title, "ffd100"), top and W.Label(top) or "" } }
    end
    self.bountyWall:SetRows(rows)
end

---------------------------------------------------------------------------
-- 3. Book of Deeds
---------------------------------------------------------------------------

function View:BuildBook(f)
    local p = Pane(self, "book", f)
    self.bookChars = W.List(p, { { label = "Character", width = 250 } }, {
        onClick = function(rec) self.bookRec = rec; self:Refresh() end,
    })
    self.bookChars.frame:SetPoint("TOPLEFT", 14, TOP)
    self.bookChars.frame:SetPoint("BOTTOMLEFT", 14, 10)
    self.bookChars.frame:SetWidth(290)
    local page = W.Box(p, "card")
    page:SetPoint("TOPLEFT", 316, TOP)
    page:SetPoint("BOTTOMRIGHT", -14, 10)
    self.bookScroll, self.bookContent = W.ScrollArea(page)
    self.bookScroll:SetPoint("TOPLEFT", 14, -12)
    self.bookScroll:SetPoint("BOTTOMRIGHT", -30, 12)
    self.bookLines = {}
end

function View:BookLine(i, template)
    local fs = self.bookLines[i]
    if not fs then
        fs = self.bookContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        self.bookLines[i] = fs
    end
    fs:SetFontObject(template or GameFontHighlight)
    fs:SetWordWrap(true)
    fs:Show()
    return fs
end

function View:Refresh_book()
    local chars = FS:GetScopeCharacters(UI.currentScope)
    FS:SortByStat(chars, "level")
    if not self.bookRec or not FS.db.global.characters[self.bookRec.fullName] then self.bookRec = FS:GetMyRecord() or chars[1] end
    local rows = {}
    for i, r in ipairs(chars) do
        rows[i] = { rec = r, isSelf = (r == self.bookRec), cells = { W.Label(r) .. W.Color("  " .. tostring(r.level or "?"), "888888") } }
    end
    self.bookChars:SetRows(rows)
    local rec = self.bookRec
    self.title:SetText("The Book of Deeds" .. (rec and ("  -  " .. FS.ShortName(rec.fullName)) or ""))
    self.sub:SetText("A history written from everything FellowshipSync has seen. Pick a character on the left.")

    for _, fs in ipairs(self.bookLines) do fs:Hide() end
    if not rec then return end
    local width = math.max(300, (self.bookScroll:GetWidth() or 600) - 10)
    self.bookContent:SetWidth(width)
    local y, n = 0, 0
    local function line(text, template, height)
        n = n + 1
        local fs = self:BookLine(n, template)
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetText(text)
        y = y + (height or 18)
    end
    line(F:Summary(rec), GameFontHighlight, 58)

    local anniversaries = {}
    for _, a in ipairs(F:OnThisDay("network")) do if a.rec == rec then table.insert(anniversaries, a) end end
    if #anniversaries > 0 then
        line(W.Color("On this day", "ffd100"), GameFontNormal, 20)
        for _, a in ipairs(anniversaries) do
            line(string.format("%d year%s ago: %s", a.years, a.years == 1 and "" or "s", a.text), GameFontHighlightSmall)
        end
        y = y + 8
    end
    line(W.Color("Deeds", "ffd100"), GameFontNormal, 20)
    local deeds = F:Book(rec)
    if #deeds == 0 then line(W.Color("Nothing recorded yet. Every adventure from now on will be written here.", "777777"), GameFontHighlightSmall) end
    for _, deed in ipairs(deeds) do
        line(W.Color(date("%d.%m.%Y", deed.t), "888888") .. "   " .. deed.text, GameFontHighlightSmall)
    end
    self.bookContent:SetHeight(math.max(10, y + 10))
end

---------------------------------------------------------------------------
-- 4. Deathmap
---------------------------------------------------------------------------

function View:BuildDeathmap(f)
    local p = Pane(self, "deathmap", f)
    self.mapCheck = W.Check(p, "Show skulls on the world map", function(on)
        FS.db.profile.deathmap.worldMap = on
        FS.Deathmap:Refresh()
    end)
    self.mapCheck:SetPoint("TOPRIGHT", -250, -46)
    self.zoneList = W.List(p, {
        { label = "#", width = 32 }, { label = "Zone", width = 240 }, { label = "Deaths", width = 70, justify = "RIGHT" },
        { label = "Deadliest Killer", width = 250 }, { label = "Last Victim", width = 230 }, { label = "On Map", width = 60, justify = "RIGHT" },
    }, { noTooltip = true, emptyText = "No deaths recorded in this view. May it stay that way." })
    Place(self.zoneList, TOP)
end

function View:Refresh_deathmap()
    self.title:SetText("Deathmap  -  Danger Zones in " .. UI.SCOPE_TITLES[UI.currentScope])
    self.sub:SetText("Where people die most. Open the world map to see a skull for every open-world death (instances have no positions).")
    self.mapCheck:SetChecked(FS.db.profile.deathmap.worldMap ~= false)
    FS.db.profile.deathmap.scope = (UI.currentScope == "netaccs") and "network" or UI.currentScope
    local rows = {}
    for i, z in ipairs(FS.Deathmap:DangerZones(UI.currentScope)) do
        rows[i] = { cells = { W.Rank(i), W.Color(z.zone, "ffd100"), W.RankValue(i, W.Num(z.deaths)),
            W.Color(z.topKiller or "?", "ff5555") .. W.Color(" (" .. z.topKills .. ")", "888888"),
            z.lastRec and (W.CharName(z.lastRec) .. W.Color("  " .. W.Ago(z.last), "888888")) or "", W.Num(z.mapped) } }
    end
    self.zoneList:SetRows(rows)
end

---------------------------------------------------------------------------
-- 5. Memory Lane
---------------------------------------------------------------------------

function View:BuildMemories(f)
    local p = Pane(self, "memories", f)
    self.memList = W.List(p, {
        { label = "Date", width = 140 }, { label = "Moment", width = 470 }, { label = "Screenshot", width = 320 },
    }, { noTooltip = true, emptyText = "No memories yet. FellowshipSync takes a screenshot at your big moments (see Options > Fellowship)." })
    Place(self.memList, TOP)
end

function View:Refresh_memories()
    local m = FS.db.profile.memory
    self.title:SetText("Memory Lane")
    self.sub:SetText(m.enabled and "Screenshots of your big moments, saved in your World of Warcraft Screenshots folder."
        or "Automatic screenshots are switched off (Options > Fellowship).")
    local rows = {}
    for i, mem in ipairs(FS.db.char.memories) do
        rows[i] = { cells = { W.Color(W.Date(mem.t), "aaaaaa"), W.Color(mem.what, "ffd100"), W.Color(mem.file or "", "888888") } }
    end
    self.memList:SetRows(rows)
end

---------------------------------------------------------------------------
-- 6. Wagers
---------------------------------------------------------------------------

function View:BuildWagers(f)
    local p = Pane(self, "wagers", f)
    self.marksText = W.Text(p, "GameFontNormalLarge", "RIGHT")
    self.marksText:SetPoint("TOPRIGHT", -36, -46)
    self.newStat = W.Button(p, "New Stat Wager", 130, 22, function() self:OpenCreate("stat") end)
    self.newStat:SetPoint("TOPRIGHT", -250, -46)
    self.newCustom = W.Button(p, "New Custom Wager", 140, 22, function() self:OpenCreate("manual") end)
    self.newCustom:SetPoint("RIGHT", self.newStat, "LEFT", -6, 0)
    self.pagePrev = W.Button(p, "<", 24, 22, function() self.wagerPage = (self.wagerPage or 1) - 1; self:Refresh() end)
    self.pagePrev:SetPoint("RIGHT", self.newCustom, "LEFT", -40, 0)
    self.pageText = W.Text(p, "GameFontHighlightSmall", "CENTER")
    self.pageText:SetPoint("LEFT", self.pagePrev, "RIGHT", 2, 0)
    self.pageText:SetWidth(40)
    self.pageNext = W.Button(p, ">", 24, 22, function() self.wagerPage = (self.wagerPage or 1) + 1; self:Refresh() end)
    self.pageNext:SetPoint("LEFT", self.pageText, "RIGHT", 2, 0)

    self.wagerCards = {}
    self.pickIndex = {}
    for i = 1, 3 do
        local card = W.Box(p, "card")
        card:SetPoint("TOPLEFT", 14, TOP - (i - 1) * 96)
        card:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        card:SetHeight(88)
        card.q = W.Text(card, "GameFontNormal")
        card.q:SetPoint("TOPLEFT", 12, -10)
        card.pool = W.Text(card, "GameFontHighlightSmall")
        card.pool:SetPoint("TOPLEFT", 12, -30)
        card.pool:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.mine = W.Text(card, "GameFontHighlightSmall")
        card.mine:SetPoint("BOTTOMLEFT", 12, 12)
        card.prev = W.Button(card, "<", 24, 20, function() self:CyclePick(i, -1) end)
        card.prev:SetPoint("BOTTOMLEFT", 12, 8)
        card.pick = W.Text(card, "GameFontHighlight", "CENTER")
        card.pick:SetPoint("LEFT", card.prev, "RIGHT", 4, 0)
        card.pick:SetWidth(190)
        card.next = W.Button(card, ">", 24, 20, function() self:CyclePick(i, 1) end)
        card.next:SetPoint("LEFT", card.pick, "RIGHT", 4, 0)
        card.bets = {}
        for j, amt in ipairs({ 50, 100, 250 }) do
            local b = W.Button(card, "Bet " .. amt, 80, 20, function() self:Bet(i, amt) end)
            b:SetPoint("LEFT", card.next, "RIGHT", 10 + (j - 1) * 86, 0)
            card.bets[j] = b
        end
        card.declare = W.Button(card, "Declare Winner", 130, 20, function() self:Declare(i) end)
        card.declare:SetPoint("BOTTOMRIGHT", -12, 8)
        self.wagerCards[i] = card
    end
    self.wagerBoard = W.List(p, {
        { label = "#", width = 32 }, { label = "Player", width = 220 }, { label = "Marks", width = 120, justify = "RIGHT" },
    }, { noTooltip = true })
    self.wagerBoard.frame:SetPoint("TOPLEFT", 14, TOP - 3 * 96 - 6)
    self.wagerBoard.frame:SetPoint("BOTTOMLEFT", 14, 10)
    self.wagerBoard.frame:SetWidth(420)
    self.wagerResults = W.List(p, {
        { label = "Settled Question", width = 300 }, { label = "Winner", width = 210 },
    }, { noTooltip = true, emptyText = "Results appear a day after the weekly reset (free-text wagers: when the officer declares)." })
    self.wagerResults.frame:SetPoint("TOPLEFT", 444, TOP - 3 * 96 - 6)
    self.wagerResults.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    self:BuildCreate(p)
end

-- Creation panel for stat wagers (anyone) and free-text wagers (officers).
function View:BuildCreate(p)
    local c = W.Box(p, "accent")
    c:SetPoint("TOPLEFT", 14, TOP)
    c:SetPoint("TOPRIGHT", -14, TOP)
    c:SetHeight(120)
    c:SetFrameLevel(p:GetFrameLevel() + 40)
    c:EnableMouse(true)
    c:Hide()
    c.title = W.Text(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.statPrev = W.Button(c, "<", 24, 22, function() self.createStat = ((self.createStat or 1) - 2) % #FS.Fellowship.WAGER_STATS + 1; self:RefreshCreate() end)
    c.statPrev:SetPoint("TOPLEFT", 12, -40)
    c.statText = W.Text(c, "GameFontHighlight", "CENTER")
    c.statText:SetPoint("LEFT", c.statPrev, "RIGHT", 4, 0)
    c.statText:SetWidth(260)
    c.statNext = W.Button(c, ">", 24, 22, function() self.createStat = (self.createStat or 1) % #FS.Fellowship.WAGER_STATS + 1; self:RefreshCreate() end)
    c.statNext:SetPoint("LEFT", c.statText, "RIGHT", 4, 0)
    c.question = W.Search(c, 560, "Question, e.g. Who wins Friday's duel tournament?")
    c.question:SetPoint("TOPLEFT", 12, -36)
    c.options = W.Search(c, 560, "Options, separated by commas, e.g. Kima, Benny, Olav")
    c.options:SetPoint("TOPLEFT", 12, -64)
    c.create = W.Button(c, "Create", 100, 22, function() self:CreateWager() end)
    c.create:SetPoint("BOTTOMRIGHT", -118, 10)
    c.cancel = W.Button(c, "Cancel", 100, 22, function() c:Hide() end)
    c.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    self.createPanel = c
end

function View:OpenCreate(mode)
    if mode == "manual" and not F:IsOfficer() then
        FS:Print("Only the guild leader and officers can create free-text wagers.")
        return
    end
    self.createMode = mode
    self.createPanel:Show()
    self:RefreshCreate()
end

function View:RefreshCreate()
    local c, stat = self.createPanel, self.createMode == "stat"
    c.title:SetText(stat and "New stat wager: pick a statistic (settled automatically after the weekly reset)"
        or "New free-text wager: you declare the winner yourself")
    W.AccentText(c.title)
    for _, w in ipairs({ c.statPrev, c.statNext, c.statText }) do w:SetShown(stat) end
    c.question:SetShown(not stat)
    c.options:SetShown(not stat)
    local key = F.WAGER_STATS[self.createStat or 1]
    c.statText:SetText("Who will have the most " .. W.Color(FS.STATS[key].label:lower(), "ffd100") .. " this week?")
end

function View:CreateWager()
    local ok, err
    if self.createMode == "stat" then
        ok, err = F:CreateStatWager(F.WAGER_STATS[self.createStat or 1])
    else
        ok, err = F:CreateManualWager(self.createPanel.question:GetText(), self.createPanel.options:GetText())
    end
    if ok then
        self.createPanel:Hide()
        self.createPanel.question:SetText("")
        self.createPanel.options:SetText("")
        FS:Print("Wager created. Your guild will see it with your next sync.")
    else
        FS:Print(err)
    end
    self:Refresh()
end

-- What can be picked: characters, or the options of a free-text wager.
function View:Candidates(wager)
    if wager and wager.kind == "manual" then
        local list = {}
        for _, o in ipairs(wager.options or {}) do table.insert(list, { option = o }) end
        return list
    end
    local list = {}
    for _, r in ipairs(FS:GetScopeCharacters("guild")) do
        if time() - (tonumber(r.lastUpdate) or 0) < 14 * 86400 then table.insert(list, { rec = r }) end
    end
    table.sort(list, function(a, b) return tostring(a.rec.fullName) < tostring(b.rec.fullName) end)
    return list
end

local function CandidateKey(c) return c.option or c.rec.fullName end
local function CandidateText(c) return c.option and W.Color(c.option, "ffffff") or W.CharName(c.rec) end

function View:VisibleWager(i) return self.wagers and self.wagers[((self.wagerPage or 1) - 1) * 3 + i] end

function View:CyclePick(i, delta)
    local n = #self:Candidates(self:VisibleWager(i))
    if n == 0 then return end
    self.pickIndex[i] = (((self.pickIndex[i] or 1) - 1 + delta) % n) + 1
    self:Refresh()
end

function View:Bet(i, amount)
    local wager = self:VisibleWager(i)
    local cands = self:Candidates(wager)
    local pick = cands[self.pickIndex[i] or 1]
    if not wager or not pick then return end
    local ok, err = F:PlaceBet(wager.id, CandidateKey(pick), amount)
    if ok then
        FS:Print(string.format("You bet %d Fellowship Marks on %s: %s", amount, pick.option or FS.ShortName(pick.rec.fullName), wager.def.q))
    else
        FS:Print(err)
    end
    self:Refresh()
end

function View:Declare(i)
    local wager = self:VisibleWager(i)
    local pick = self:Candidates(wager)[self.pickIndex[i] or 1]
    if not wager or not pick then return end
    if self.confirmDeclare ~= wager.id then
        self.confirmDeclare = wager.id
        FS:Print("Click Declare Winner again to confirm: " .. pick.option)
        FS:ScheduleTimer(function() self.confirmDeclare = nil end, 5)
        return
    end
    self.confirmDeclare = nil
    if F:DeclareWinner(wager.id, pick.option) then FS:Print("Winner declared: " .. pick.option) end
    self:Refresh()
end

function View:Refresh_wagers()
    F:SettleWagers()
    local me = FS.Tracker:AccountLabel()
    local myKey = FS:GetPlayerKey()
    self.wagers = F:CurrentWagers()
    local pages = math.max(1, math.ceil(#self.wagers / 3))
    self.wagerPage = math.max(1, math.min(self.wagerPage or 1, pages))
    self.pageText:SetText(self.wagerPage .. "/" .. pages)
    self.pagePrev:SetShown(pages > 1)
    self.pageNext:SetShown(pages > 1)
    self.newCustom:SetActive(F:IsOfficer())
    self.title:SetText("Wagers  -  Fellowship Marks")
    self.sub:SetText("Pretend money only. Everyone starts with " .. F.START_MARKS .. " marks; winners split the pot. Bets close a day before the weekly reset.")
    self.marksText:SetText("Your marks: " .. W.Color(W.Num(F:Balance(me)), "ffd100"))
    local open = F:BetsOpen()
    for i, card in ipairs(self.wagerCards) do
        local w = self:VisibleWager(i)
        card:SetShown(w ~= nil)
        if w then
            local cands = self:Candidates(w)
            local creatorNote = w.creator and W.Color("  (by " .. FS.ShortName(w.creator) .. ")", "888888") or ""
            card.q:SetText(w.def.q .. creatorNote)
            W.AccentText(card.q)
            local stakes, pool = {}, 0
            for _, b in ipairs(F:BetsOn(w.id)) do
                pool = pool + b.amt
                stakes[b.pick] = (stakes[b.pick] or 0) + b.amt
            end
            local top = {}
            for pick, amt in pairs(stakes) do table.insert(top, { pick = pick, amt = amt }) end
            table.sort(top, function(a, b) return a.amt > b.amt end)
            local parts = {}
            for j = 1, math.min(3, #top) do
                local label = (w.kind == "manual") and W.Color(top[j].pick, "ffffff") or NameFor(top[j].pick)
                table.insert(parts, label .. W.Color(" " .. W.Num(top[j].amt), "888888"))
            end
            local settled = FS.db.global.wagerResults[w.id]
            card.pool:SetText("Pot: " .. W.Color(W.Num(pool) .. " marks", "ffd100")
                .. (#parts > 0 and ("   Favourites: " .. table.concat(parts, ",  ")) or "")
                .. (settled and ("   " .. W.Color("Winner: " .. (w.kind == "manual" and settled.winner or FS.ShortName(settled.winner)), "1eff00")) or ""))
            local mine = F:MyBet(w.id)
            local isCreator = w.kind == "manual" and w.creator == myKey and not w.winner
            local betOpen = (w.kind == "manual") and not w.winner or open
            local canBet = betOpen and not mine and #cands > 0
            local showPicker = canBet or isCreator
            for _, btn in ipairs({ card.prev, card.next }) do btn:SetShown(showPicker) end
            for _, btn in ipairs(card.bets) do btn:SetShown(canBet) end
            card.pick:SetShown(showPicker)
            card.declare:SetShown(isCreator)
            card.mine:SetShown(not showPicker)
            if showPicker then
                local pick = cands[self.pickIndex[i] or 1] or cands[1]
                card.pick:SetText(pick and CandidateText(pick) or "")
            elseif mine then
                local label = (w.kind == "manual") and W.Color(mine.pick, "ffffff") or NameFor(mine.pick)
                card.mine:SetText("Your bet: " .. W.Color(W.Num(mine.amt) .. " marks", "ffd100") .. " on " .. label)
            else
                card.mine:SetText(W.Color(betOpen and "Nothing to bet on yet." or "Betting is closed until the weekly reset.", "777777"))
            end
        end
    end
    -- Leaderboard by player
    local owners = { [me] = true }
    for _, b in ipairs(F:AllBets()) do owners[b.owner] = true end
    local board = {}
    for owner in pairs(owners) do table.insert(board, { owner = owner, marks = F:Balance(owner) }) end
    table.sort(board, function(a, b) return a.marks > b.marks end)
    local rows = {}
    for i, e in ipairs(board) do
        rows[i] = { isSelf = e.owner == me, cells = { W.Rank(i), W.Color(e.owner, "ffffff"), W.RankValue(i, W.Num(e.marks)) } }
    end
    self.wagerBoard:SetRows(rows)
    -- Settled questions (last week's built-ins, stat wagers and declared free-text wagers)
    local results = {}
    local lastIdx = FS.WeekIndex(FS:WeekStart()) - 1
    for _, def in ipairs(F.WAGERS) do
        local r = FS.db.global.wagerResults[lastIdx .. ":" .. def.id]
        if r then table.insert(results, { cells = { def.q, NameFor(r.winner) .. W.Color(" (" .. W.FormatStat(def.key, r.value) .. ")", "888888") } }) end
    end
    for _, c in ipairs(F:CustomWagers()) do
        local r = FS.db.global.wagerResults[c.id]
        if r then
            table.insert(results, { cells = { c.q, c.kind == "manual" and W.Color(r.winner, "1eff00")
                or (NameFor(r.winner) .. W.Color(" (" .. W.FormatStat(c.key, r.value) .. ")", "888888")) } })
        end
    end
    self.wagerResults:SetRows(results)
end

---------------------------------------------------------------------------
-- 7. Rivalries
---------------------------------------------------------------------------

function View:BuildRivals(f)
    local p = Pane(self, "rivals", f)
    self.rivalChange = W.Button(p, "Choose a Rival", 140, 22, function() self.pickingRival = true; self:Refresh() end)
    self.rivalChange:SetPoint("TOPRIGHT", -150, -46)
    self.rivalClear = W.Button(p, "Clear Rival", 120, 22, function() F:SetRival(nil); self:Refresh() end)
    self.rivalClear:SetPoint("LEFT", self.rivalChange, "RIGHT", 6, 0)
    self.scoreList = W.List(p, {
        { label = "Stat", width = 250 }, { label = "You", width = 210, justify = "RIGHT" },
        { label = "Rival", width = 210, justify = "RIGHT" }, { label = "Leader", width = 230, justify = "RIGHT" },
    }, { noTooltip = true })
    Place(self.scoreList, TOP)
    self.pickList = W.List(p, {
        { label = "#", width = 32 }, { label = "Pick your rival", width = 360 }, { label = "Level", width = 70, justify = "RIGHT" },
        { label = "GearScore", width = 120, justify = "RIGHT" }, { label = "Named as rival by", width = 300 },
    }, { onClick = function(rec) F:SetRival(rec.fullName); self.pickingRival = false; self:Refresh() end,
         emptyText = "Nobody to pick yet. Sync with your guild first." })
    Place(self.pickList, TOP)
end

function View:Refresh_rivals()
    local me = FS:GetMyRecord()
    local rival = FS.db.char.rival and FS.db.global.characters[FS.db.char.rival]
    local picking = self.pickingRival or not rival
    self.scoreList.frame:SetShown(not picking)
    self.pickList.frame:SetShown(picking)
    self.rivalClear:SetShown(rival ~= nil)
    self.rivalChange.text:SetText(rival and "Change Rival" or "Choose a Rival")

    -- Who named whom
    local namedBy = {}
    for _, r in pairs(FS.db.global.characters) do
        if r.rival and not r.isMock then namedBy[r.rival] = (namedBy[r.rival] and (namedBy[r.rival] .. ", ") or "") .. FS.ShortName(r.fullName) end
    end

    if picking then
        self.title:SetText("Rivalries  -  Pick Your Rival")
        self.sub:SetText("Click a character to make them your rival. They will see it if they use FellowshipSync too.")
        local rows = {}
        local list = FS:GetScopeCharacters(UI.currentScope == "solo" and "network" or UI.currentScope)
        FS:SortByStat(list, "gs")
        for _, r in ipairs(list) do
            if not r.isMyChar then
                table.insert(rows, { rec = r, cells = { W.Rank(#rows + 1), W.Label(r), tostring(r.level or "?"),
                    W.Num(r.gs), namedBy[r.fullName] and W.Color(namedBy[r.fullName], "ff8000") or "" } })
            end
        end
        self.pickList:SetRows(rows)
        return
    end

    local rows, mine, theirs = F:Scorecard(me, rival)
    self.title:SetText(string.format("%s  vs  %s:  %s - %s", W.CharName(me), W.CharName(rival),
        W.Color(mine, mine >= theirs and "1eff00" or "ff5555"), W.Color(theirs, theirs > mine and "1eff00" or "ff5555")))
    local challengers = namedBy[me.fullName]
    self.sub:SetText((FS:IsWeekMode() and "This week. " or "All-time. ") .. (mine > theirs and "You are winning the rivalry!"
        or (mine < theirs and "Your rival is ahead. Time to catch up!" or "Dead even."))
        .. (challengers and ("   Named you as their rival: " .. challengers) or ""))
    local out = {}
    for i, r in ipairs(rows) do
        local leader = (r.leader == 1 and W.Color("You", "1eff00")) or (r.leader == 2 and W.Color(FS.ShortName(rival.fullName), "ff5555")) or W.Color("Tied", "aaaaaa")
        out[i] = { cells = { FS.STATS[r.key] and FS.STATS[r.key].label or r.key, W.FormatStat(r.key, r.mine),
                             W.FormatStat(r.key, r.theirs), leader } }
    end
    self.scoreList:SetRows(out)
end

---------------------------------------------------------------------------
-- 8. Games: Deathroll and the raffle wheel
---------------------------------------------------------------------------

local Games = FS.Games

function View:BuildGames(f)
    local p = Pane(self, "games", f)
    local half = (1010 - 28 - 12) / 2

    -- Deathroll ---------------------------------------------------------------
    local d = W.Box(p, "card")
    d:SetPoint("TOPLEFT", 14, TOP)
    d:SetPoint("BOTTOMLEFT", 14, 10)
    d:SetWidth(half)
    d.title = W.Text(d, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 12, -10)
    d.title:SetText("Deathroll")
    d.record = W.Text(d, "GameFontHighlightSmall", "RIGHT")
    d.record:SetPoint("TOPRIGHT", -12, -14)
    d.help = W.Text(d, "GameFontDisableSmall")
    d.help:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.help:SetText("Take turns rolling up to the last result. Whoever rolls 1 loses.")
    d.opponent = W.Search(d, 200, "Opponent's name")
    d.opponent:SetPoint("TOPLEFT", 12, -58)
    d.useTarget = W.Button(d, "Use Target", 100, 24, function()
        local name = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
        if name and not FS.IsSecret(name) then d.opponent:SetText(name); d.opponent:Fire("OnTextChanged") end
    end)
    d.useTarget:SetPoint("LEFT", d.opponent, "RIGHT", 6, 0)
    d.start = W.Search(d, 100, "Start (1000)")
    d.start:SetPoint("TOPLEFT", 12, -88)
    d.stake = W.Search(d, 200, "Stake, e.g. 100g (optional)")
    d.stake:SetPoint("LEFT", d.start, "RIGHT", 6, 0)
    d.begin = W.Button(d, "Start Deathroll", 140, 24, function()
        local ok, err = Games:StartDeathroll(d.opponent:GetText(), tonumber(d.start:GetText()) or 1000, d.stake:GetText())
        if not ok then FS:Print(err) end
        self:Refresh()
    end)
    d.begin:SetPoint("TOPLEFT", 12, -118)
    d.cancel = W.Button(d, "Cancel", 80, 24, function() Games:CancelDeathroll(); self:Refresh() end)
    d.cancel:SetPoint("LEFT", d.begin, "RIGHT", 6, 0)
    d.status = W.Text(d, "GameFontHighlight")
    d.status:SetPoint("TOPLEFT", 12, -154)
    d.status:SetWidth(half - 24)
    d.roll = W.Button(d, "Roll", 160, 30, function() Games:Roll() end)
    d.roll:SetPoint("TOPLEFT", 12, -178)
    d.log = W.Text(d, "GameFontHighlightSmall")
    d.log:SetPoint("TOPLEFT", 12, -216)
    d.log:SetWidth(half - 24)
    d.log:SetWordWrap(true)
    d.history = W.List(d, {
        { label = "Date", width = 90 }, { label = "Opponent", width = 110 }, { label = "Start", width = 60, justify = "RIGHT" },
        { label = "Result", width = 60 }, { label = "Rolls", width = 50, justify = "RIGHT" }, { label = "Stake", width = 70 },
    }, { noTooltip = true, emptyText = "No deathrolls yet." })
    d.history.frame:SetPoint("TOPLEFT", 8, -300)
    d.history.frame:SetPoint("BOTTOMRIGHT", -4, 8)
    self.dr = d

    -- Raffle --------------------------------------------------------------------
    local r = W.Box(p, "card")
    r:SetPoint("TOPRIGHT", -14, TOP)
    r:SetPoint("BOTTOMRIGHT", -14, 10)
    r:SetWidth(half)
    r.title = W.Text(r, "GameFontNormalLarge")
    r.title:SetPoint("TOPLEFT", 12, -10)
    r.title:SetText("Raffle Wheel")
    r.help = W.Text(r, "GameFontDisableSmall")
    r.help:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.help:SetText("Players join by typing the keyword in chat. Collect the ticket price yourself.")
    r.keyword = W.Search(r, 140, "Keyword", function() Games:RaffleSettings().keyword = strtrim(r.keyword:GetText() or "") end)
    r.keyword:SetPoint("TOPLEFT", 12, -58)
    r.fee = W.Search(r, 110, "Ticket price", function() Games:RaffleSettings().fee = strtrim(r.fee:GetText() or "") end)
    r.fee:SetPoint("LEFT", r.keyword, "RIGHT", 6, 0)
    r.channel = W.Button(r, "", 150, 24, function()
        local s = Games:RaffleSettings()
        s.channel = (s.channel == "guild") and "group" or "guild"
        self:Refresh()
    end)
    r.channel:SetPoint("LEFT", r.fee, "RIGHT", 6, 0)
    r.onlyPaid = W.Check(r, "Only paid tickets can win", function(on) Games:RaffleSettings().onlyPaid = on; self:Refresh() end)
    r.onlyPaid:SetPoint("TOPLEFT", 12, -88)
    r.announce = W.Check(r, "Announce in chat", function(on) Games:RaffleSettings().announce = on end)
    r.announce:SetPoint("TOPLEFT", 230, -88)
    r.toggle = W.Button(r, "Open Raffle", 120, 24, function()
        if Games.raffle.open then Games:CloseRaffle() else
            local ok, err = Games:OpenRaffle()
            if not ok then FS:Print(err) end
        end
        self:Refresh()
    end)
    r.toggle:SetPoint("TOPLEFT", 12, -116)
    r.repost = W.Button(r, "Announce Again", 130, 24, function() Games:AnnounceRaffle() end)
    r.repost:SetPoint("LEFT", r.toggle, "RIGHT", 6, 0)
    r.entrants = W.List(r, {
        { label = "Ticket", width = 160 }, { label = "Paid", width = 60 }, { label = "Joined", width = 80, justify = "RIGHT" },
    }, { noTooltip = true, emptyText = "No tickets yet. Click a name to mark it paid.",
         onClick = function(entry) Games:TogglePaid(entry.name); self:Refresh() end })
    r.entrants.frame:SetPoint("TOPLEFT", 8, -148)
    r.entrants.frame:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.entrants.frame:SetHeight(170)

    r.wheel = W.Box(r, "accent")
    r.wheel:SetPoint("TOPLEFT", 12, -326)
    r.wheel:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.wheel:SetHeight(56)
    r.wheel.name = W.Text(r.wheel, "GameFontNormalHuge", "CENTER")
    r.wheel.name:SetAllPoints()
    r.spin = W.Button(r, "Spin the Wheel!", 160, 28, function() self:SpinWheel() end)
    r.spin:SetPoint("TOP", r.wheel, "BOTTOM", 0, -6)
    r.history = W.List(r, {
        { label = "Date", width = 90 }, { label = "Winner", width = 160 }, { label = "Tickets", width = 60, justify = "RIGHT" },
    }, { noTooltip = true, emptyText = "No raffles drawn yet." })
    r.history.frame:SetPoint("TOPLEFT", 8, -424)
    r.history.frame:SetPoint("BOTTOMRIGHT", -4, 8)
    self.raffleBox = r
end

-- Spins through the names, slowing down, and stops on the (already drawn) winner.
function View:SpinWheel()
    local r = self.raffleBox
    if self.spinning then return end
    local winner, pool = Games:DrawWinner()
    if not winner then FS:Print(pool) return end
    self.spinning = { t = 0, step = 0.04, next = 0, i = math.random(1, #pool), pool = pool, winner = winner, length = 3.5 }
    r.wheel:SetScript("OnUpdate", function(_, dt)
        local s = self.spinning
        s.t = s.t + dt
        if s.t >= s.length then
            r.wheel:SetScript("OnUpdate", nil)
            r.wheel.name:SetText(W.Color(s.winner, "1eff00"))
            Games:AnnounceWinner(s.winner, #s.pool)
            self.spinning = nil
            self:Refresh()
            return
        end
        if s.t >= s.next then
            s.i = s.i % #s.pool + 1
            r.wheel.name:SetText(W.Color(s.pool[s.i], "ffd100"))
            s.step = s.step * 1.12
            s.next = s.t + s.step
        end
    end)
end

function View:Refresh_games()
    self.title:SetText("Games  -  Deathroll & Raffle")
    self.sub:SetText("Gold changes hands between players directly; the addon only keeps score.")
    -- Deathroll
    local d, dr = self.dr, Games.dr
    local won, lost = Games:DeathrollRecord()
    d.record:SetText(string.format("Record: %s won  -  %s lost", W.Color(won, "1eff00"), W.Color(lost, "ff5555")))
    local active = dr and dr.active
    d.begin:SetShown(not active)
    d.cancel:SetShown(active and true or false)
    d.roll:SetShown(active and true or false)
    if active then
        local last = dr.rolls[#dr.rolls]
        local myTurn = not last or last.who == "them"
        d.status:SetText(string.format("vs %s%s  -  %s", W.Color(dr.opponent, "ffd100"),
            dr.stake ~= "" and (" for " .. dr.stake) or "", myTurn and W.Color("your turn", "1eff00") or ("waiting for " .. dr.opponent)))
        d.roll.text:SetText("Roll 1 - " .. W.Num(dr.current))
        d.roll:SetActive(myTurn)
    elseif dr then
        local last = dr.rolls[#dr.rolls]
        d.status:SetText(last and (last.who == "me" and W.Color("You rolled the 1. Better luck next time!", "ff5555")
            or W.Color(dr.opponent .. " rolled the 1. You win!", "1eff00")) or "")
    else
        d.status:SetText(W.Color("Set an opponent and a starting number, then start.", "888888"))
    end
    local lines = {}
    for i = math.max(1, #(dr and dr.rolls or {}) - 7), #(dr and dr.rolls or {}) do
        local roll = dr.rolls[i]
        table.insert(lines, string.format("%s rolled %s (1-%s)", roll.who == "me" and "You" or dr.opponent,
            W.Color(W.Num(roll.value), roll.value == 1 and "ff5555" or "ffffff"), W.Num(roll.max)))
    end
    d.log:SetText(table.concat(lines, "\n"))
    local rows = {}
    for i, g in ipairs(FS.db.global.deathrolls) do
        rows[i] = { cells = { W.Color(date("%d.%m %H:%M", g.t), "aaaaaa"), g.opponent, W.Num(g.start),
            g.won and W.Color("Won", "1eff00") or W.Color("Lost", "ff5555"), W.Num(g.rolls), g.stake or "" } }
    end
    d.history:SetRows(rows)

    -- Raffle
    local r, s, raffle = self.raffleBox, Games:RaffleSettings(), Games.raffle
    if not r.keyword:HasFocus() then r.keyword:SetText(s.keyword or "") end
    if not r.fee:HasFocus() then r.fee:SetText(s.fee or "") end
    r.channel.text:SetText(s.channel == "group" and "Channel: Party/Raid" or "Channel: Guild")
    r.onlyPaid:SetChecked(s.onlyPaid)
    r.announce:SetChecked(s.announce)
    r.toggle.text:SetText(raffle.open and "Close Raffle" or "Open Raffle")
    r.toggle:SetActive(raffle.open)
    r.repost:SetShown(raffle.open)
    local entries = {}
    for i, e in ipairs(raffle.entrants) do
        entries[i] = { rec = e, cells = { W.Color(e.name, "ffffff"), e.paid and W.Color("Paid", "1eff00") or W.Color("No", "888888"),
            W.Color(date("%H:%M", e.joined), "aaaaaa") } }
    end
    r.entrants:SetRows(entries)
    if not self.spinning then
        local pool = Games:Pool()
        r.wheel.name:SetText(#pool > 0 and W.Color(#pool .. " ticket" .. (#pool == 1 and "" or "s") .. " in the wheel", "aaaaaa")
            or W.Color("No tickets yet", "666666"))
    end
    local hist = {}
    for i, h in ipairs(FS.db.global.raffles) do
        hist[i] = { cells = { W.Color(date("%d.%m %H:%M", h.t), "aaaaaa"), W.Color(h.winner, "1eff00"), W.Num(h.entries) } }
    end
    r.history:SetRows(hist)
end
