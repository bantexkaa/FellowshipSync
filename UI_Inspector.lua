local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Inspector = FS.Inspector
local UI, W = FS.UI, FS.W

local WIDTH = 960

local function Icon(path) return "|T" .. path .. ":14:14:0:0|t " end

local function TopEntry(map)
    local bestK, bestV
    for k, v in pairs(map or {}) do
        if not bestV or v > bestV then bestK, bestV = k, v end
    end
    return bestK, bestV
end

-- Stat ledger rows: { label, function(rec) -> text }
local LEDGER = {
    { "GearScore / iLvl", function(r) return string.format("%s GS (%.1f / %.1f)", W.Num(r.gs), r.ilvl or 0, r.ilvlBag or 0) end },
    { "Total Kills",      function(r) return W.Num(FS:GetValue(r, "kills")) end },
    { "Total Deaths",     function(r)
        local d = FS:GetValue(r, "deaths")
        return string.format("%s (%.1f K/D)", W.Num(d), FS:GetValue(r, "kills") / math.max(1, d)) end },
    { "Total Damage",     function(r) return W.Num(FS:GetValue(r, "damage")) end },
    { "Total Healing",    function(r) return W.Num(FS:GetValue(r, "healing")) end },
    { "Largest Hit",      function(r) return W.Num(r.crit) end },
    { "Quests Completed", function(r) return W.Num(FS:GetValue(r, "quests")) end },
    { "Total Jumps",      function(r) return W.Num(FS:GetValue(r, "jumps")) end },
    { "Fish Caught",      function(r) return W.Num(FS:GetValue(r, "fish")) end },
    { "Gold Looted",      function(r) return W.Money(FS:GetValue(r, "goldLooted")) end },
    { "Epics Looted",     function(r) return W.Num(FS:GetValue(r, "epics")) end },
    { "Loot Rolls Won",   function(r) return string.format("%s (%d nat 100 / %d nat 1)", W.Num(FS:GetValue(r, "rollsWon")),
                                         FS:GetValue(r, "rolls100"), FS:GetValue(r, "rolls1")) end },
    { "Critters Butchered", function(r) return W.Num(FS:GetValue(r, "critters")) end },
    { "Repair Bills Paid",  function(r) return W.Money(FS:GetValue(r, "repairs")) end },
    { "Deaths by Falling",  function(r) return W.Num(FS:GetValue(r, "fallDeaths")) end },
    { "Chat Messages",      function(r) return W.Num(FS:GetValue(r, "chat")) end },
    { "AFK Time",           function(r) return W.Num(FS:GetValue(r, "afk")) .. " min" end },
    { "Flight Time",        function(r) return string.format("%s (%s rides)", W.Duration(FS:GetValue(r, "flightTime")), W.Num(FS:GetValue(r, "flightRides"))) end },
    { "Duels Won / Lost",   function(r) return W.Num(FS:GetValue(r, "duelsWon")) .. " / " .. W.Num(FS:GetValue(r, "duelsLost")) end },
    { "Distance on Foot",   function(r)
        local m = FS:GetValue(r, "travelFoot")
        return W.Distance(m) .. (W.ShowSteps() and W.Color(" (" .. W.Steps(m) .. ")", "aaaaaa") or "") end },
    { "Distance Mounted",   function(r) return W.Distance(FS:GetValue(r, "travelMount")) end },
    { "Distance Flying",    function(r) return W.Distance(FS:GetValue(r, "travelFlight")) end },
    { "Distance Swimming",  function(r) return W.Distance(FS:GetValue(r, "travelSwim")) end },
    { "Corpse Runs",        function(r) return string.format("%s (%s as a ghost)", W.Num(FS:GetValue(r, "corpseRuns")), W.Distance(FS:GetValue(r, "corpseDistance"))) end },
    { "Time in Combat",     function(r) return string.format("%s (%s fights)", W.Duration(FS:GetValue(r, "combatTime")), W.Num(FS:GetValue(r, "fights"))) end },
    { "Areas Discovered",   function(r) return W.Num(FS:GetValue(r, "areasDiscovered")) end },
    { "Gold Earned / Spent", function(r) return W.Money(FS:GetValue(r, "moneyIn")) .. " / " .. W.Money(FS:GetValue(r, "moneyOut")) end },
    { "Days Played",        function(r) return string.format("%s (best streak %s)", W.Num(r.daysPlayed), W.Num(r.bestStreak)) end },
    { "Total Distance",     function(r) return W.Distance(FS:GetValue(r, "travelTotal")) end },
    { "Playtime",           function(r) return W.Duration(FS:GetValue(r, "playtime")) end },
}

-- Fall damage can only be measured where the combat log is available.
if FS.HAS_COMBAT_LOG then
    for i, entry in ipairs(LEDGER) do
        if entry[1] == "Deaths by Falling" then
            table.insert(LEDGER, i + 2, { "Close Calls", function(r) return W.Num(FS:GetValue(r, "closeCalls")) end })
            table.insert(LEDGER, i + 1, { "Fall Damage Taken", function(r) return W.Num(FS:GetValue(r, "fallDamage")) end })
            break
        end
    end
end

function Inspector:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    local scroll, c = W.ScrollArea(f)
    scroll:SetPoint("TOPLEFT", 12, -10)
    scroll:SetPoint("BOTTOMRIGHT", -34, 10)
    c:SetSize(WIDTH, 980)
    self.content = c

    -- Header -------------------------------------------------------------
    local h = W.Box(c, "accent")
    h:SetPoint("TOPLEFT")
    h:SetSize(WIDTH, 96)
    self.avatar = h:CreateTexture(nil, "ARTWORK")
    self.avatar:SetSize(56, 56)
    self.avatar:SetPoint("TOPLEFT", 14, -14)
    self.nameText = W.Text(h, "GameFontNormalHuge")
    self.nameText:SetPoint("TOPLEFT", self.avatar, "TOPRIGHT", 12, -2)
    self.subText = W.Text(h, "GameFontHighlight")
    self.subText:SetPoint("TOPLEFT", self.nameText, "BOTTOMLEFT", 0, -4)
    self.metaText = W.Text(h, "GameFontHighlightSmall")
    self.metaText:SetPoint("TOPLEFT", self.subText, "BOTTOMLEFT", 0, -8)
    self.metaText:SetWidth(620)

    local back = W.Button(h, "Back", 70, 22, function() UI:CloseInspector() end)
    back:SetPoint("TOPRIGHT", -12, -10)
    local nextBtn = W.Button(h, "Next >", 70, 22, function() self:Cycle(1) end)
    nextBtn:SetPoint("RIGHT", back, "LEFT", -6, 0)
    local prevBtn = W.Button(h, "< Prev", 70, 22, function() self:Cycle(-1) end)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    local rivalBtn = W.Button(h, "Make Rival", 90, 22, function()
        if self.rec and not self.rec.isMyChar then FS.Fellowship:SetRival(self.rec.fullName); FS:Print(FS.ShortName(self.rec.fullName) .. " is now your rival!") end
    end)
    rivalBtn:SetPoint("RIGHT", prevBtn, "LEFT", -6, 0)
    self.rivalBtn = rivalBtn
    local bookBtn = W.Button(h, "Book of Deeds", 110, 22, function()
        local view = FS.FellowshipUI
        view.bookRec, view.current = self.rec, "book"
        for i, v in ipairs(UI.VIEWS) do if v.mod == "FellowshipUI" then UI:SelectTab(i) end end
    end)
    bookBtn:SetPoint("RIGHT", rivalBtn, "LEFT", -6, 0)
    local compareBtn = W.Button(h, "Compare", 80, 22, function()
        local R = FS.Records
        R.cmpA, R.cmpB, R.current = (FS:GetMyRecord() or {}).fullName, self.rec and self.rec.fullName, "compare"
        for i, v in ipairs(UI.VIEWS) do if v.mod == "Records" then UI:SelectTab(i) end end
    end)
    compareBtn:SetPoint("RIGHT", bookBtn, "LEFT", -6, 0)
    local shareBtn = W.Button(h, "Share", 70, 22, function() FS.Share:Open(self:ShareText()) end)
    shareBtn:SetPoint("RIGHT", compareBtn, "LEFT", -6, 0)
    self.pinBtn = W.Button(h, "Pin", 60, 22, function()
        if not self.rec then return end
        local pins = FS.db.profile.pins
        for i, key in ipairs(pins) do
            if key == self.rec.fullName then table.remove(pins, i); self:UpdatePin() return end
        end
        table.insert(pins, self.rec.fullName)
        for i = #pins, 11, -1 do table.remove(pins, 1) end -- at most 10 pins
        self:UpdatePin()
    end)
    self.pinBtn:SetPoint("RIGHT", shareBtn, "LEFT", -6, 0)
    self.gsLabel = W.Text(h, "GameFontDisableSmall", "RIGHT")
    self.gsLabel:SetPoint("TOPRIGHT", -14, -42)
    self.gsLabel:SetText(FS.HAS_POINTS and ("GEARSCORE & " .. string.upper(FS.POINTS.long)) or "GEARSCORE")
    self.gsText = W.Text(h, "GameFontNormalLarge", "RIGHT")
    self.gsText:SetPoint("TOPRIGHT", self.gsLabel, "BOTTOMRIGHT", 0, -4)

    -- Gear ---------------------------------------------------------------
    local g = W.Box(c, "card")
    g:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -10)
    g:SetSize(WIDTH, 232)
    local gt = W.Text(g, "GameFontNormal")
    gt:SetPoint("TOPLEFT", 12, -10)
    gt:SetText("Equipped 16-Slot Gear & Item Levels")
    self.gearTitle = gt
    self.gearSummary = W.Text(g, "GameFontDisableSmall", "RIGHT")
    self.gearSummary:SetPoint("TOPRIGHT", -12, -12)

    self.slots = {}
    local cellW = (WIDTH - 24 - 3 * 8) / 4
    for i, slot in ipairs(FS.GEAR_SLOTS) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local cell = CreateFrame("Button", nil, g, "BackdropTemplate")
        cell:SetBackdrop(W.FLAT)
        cell:SetBackdropColor(0, 0, 0, 0.4)
        cell:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        cell:SetSize(cellW, 44)
        cell:SetPoint("TOPLEFT", 12 + col * (cellW + 8), -34 - row * 48)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(36, 36)
        cell.icon:SetPoint("LEFT", 4, 0)
        cell.slot = W.Text(cell, "GameFontDisableSmall")
        cell.slot:SetPoint("TOPLEFT", cell.icon, "TOPRIGHT", 6, -2)
        cell.ilvl = W.Text(cell, "GameFontNormalSmall", "RIGHT")
        cell.ilvl:SetPoint("TOPRIGHT", -6, -5)
        cell.item = W.Text(cell, "GameFontHighlightSmall")
        cell.item:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMRIGHT", 6, 3)
        cell.item:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
        cell:SetScript("OnEnter", function(selfCell)
            local link = selfCell.link
            if link and link:find("|Hitem:", 1, true) then
                GameTooltip:SetOwner(selfCell, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link:match("|H(item:[^|]+)|h"))
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.slots[slot] = cell
    end

    -- Professions and Legacy (two columns) ---------------------------------
    local halfW = (WIDTH - 10) / 2
    local p = W.Box(c, "card")
    p:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -10)
    p:SetSize(halfW, 190)
    local pt = W.Text(p, "GameFontNormal")
    pt:SetPoint("TOPLEFT", 12, -10)
    pt:SetText("Professions & Secondary Skills")
    self.profTitle = pt
    self.gatherText = W.Text(p, "GameFontDisableSmall", "RIGHT")
    self.gatherText:SetPoint("TOPRIGHT", -12, -12)
    self.profBars = {}
    for i = 1, 6 do
        local label = W.Text(p, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 25)
        local value = W.Text(p, "GameFontNormalSmall", "RIGHT")
        value:SetPoint("TOPRIGHT", -14, -34 - (i - 1) * 25)
        local bar = CreateFrame("StatusBar", nil, p)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        bar:SetSize(halfW - 28, 6)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(0, 0, 0, 0.5)
        self.profBars[i] = { label = label, value = value, bar = bar }
    end
    self.noProfs = W.Text(p, "GameFontDisable", "CENTER")
    self.noProfs:SetPoint("CENTER")

    local lg = W.Box(c, "card")
    lg:SetPoint("TOPLEFT", p, "TOPRIGHT", 10, 0)
    lg:SetSize(halfW, 190)
    local lt = W.Text(lg, "GameFontNormal")
    lt:SetPoint("TOPLEFT", 12, -10)
    self.legacyTitle = lt
    self.lpText = W.Text(lg, "GameFontNormalSmall", "RIGHT")
    self.lpText:SetPoint("TOPRIGHT", -12, -12)
    self.chipScroll, self.chipContent = W.ScrollArea(lg)
    self.chipScroll:SetPoint("TOPLEFT", 10, -32)
    self.chipScroll:SetPoint("BOTTOMRIGHT", -30, 8)
    self.chips = {}

    -- Stat ledger ----------------------------------------------------------
    local s = W.Box(c, "card")
    s:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -10)
    s:SetSize(WIDTH, 34 + math.ceil(#LEDGER / 3) * 24 + 10)
    local st = W.Text(s, "GameFontNormal")
    st:SetPoint("TOPLEFT", 12, -10)
    st:SetText("Complete Character Stat Ledger")
    self.ledgerTitle = st
    self.nemesisText = W.Text(s, "GameFontHighlightSmall", "RIGHT")
    self.nemesisText:SetPoint("TOPRIGHT", -12, -12)
    self.ledger = {}
    local colW = (WIDTH - 24 - 2 * 10) / 3
    for i = 1, #LEDGER do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local cell = W.Box(s, "pill", true)
        cell:SetSize(colW, 21)
        cell:SetPoint("TOPLEFT", 12 + col * (colW + 10), -34 - row * 24)
        cell.label = W.Text(cell, "GameFontDisableSmall")
        cell.label:SetPoint("LEFT", 8, 0)
        cell.value = W.Text(cell, "GameFontHighlightSmall", "RIGHT")
        cell.value:SetPoint("RIGHT", -8, 0)
        cell.value:SetWidth(colW * 0.6)
        self.ledger[i] = cell
    end
    c:SetHeight(96 + 10 + 232 + 10 + 190 + 10 + s:GetHeight() + 10)
end

function Inspector:Cycle(delta)
    local list = self.context
    if not list or #list == 0 then return end
    local index = 1
    for i, r in ipairs(list) do if r == self.rec then index = i end end
    index = ((index - 1 + delta) % #list) + 1
    local rec = list[index]
    if rec and rec.isAccount then rec = rec.bestChar end
    if rec then self:Load(rec, list) end
end

function Inspector:Load(rec, context)
    self.rec = rec
    if context then
        local list = {}
        for _, r in ipairs(context) do table.insert(list, r) end
        self.context = list
    end
    self:Refresh()
end

function Inspector:Refresh()
    local rec = self.rec
    if not rec then return end
    for _, fs in ipairs({ self.gearTitle, self.profTitle, self.legacyTitle, self.ledgerTitle }) do W.AccentText(fs) end
    self.rivalBtn:SetShown(not rec.isMyChar)
    self:UpdatePin()

    -- Header
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[rec.cls or ""]
    if coords then
        self.avatar:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        self.avatar:SetTexCoord(unpack(coords))
    else
        self.avatar:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        self.avatar:SetTexCoord(0, 1, 0, 1)
    end
    self.nameText:SetText(W.CharName(rec) .. W.Badge(rec, true))
    local sub = string.format("Level %s %s %s", tostring(rec.level or "?"), rec.race or "", W.ClassName(rec.cls))
    if rec.guildName then sub = sub .. "  -  <" .. rec.guildName .. ">" end
    if rec.owner then sub = sub .. "  -  Player: " .. rec.owner end
    self.subText:SetText(sub)

    local meta = {}
    if rec.zone then table.insert(meta, Icon("Interface\\Icons\\INV_Misc_Map_01") .. rec.zone) end
    if rec.hearth then table.insert(meta, Icon("Interface\\Icons\\INV_Misc_Rune_01") .. rec.hearth) end
    if rec.wealth then table.insert(meta, W.Money(rec.wealth)) end
    if rec.rested then
        table.insert(meta, (tonumber(rec.rested) or 0) < 0 and "Max level" or ("Rested " .. rec.rested .. "%"))
    end
    if rec.playtime then
        local played = "Played " .. W.Duration(rec.playtime)
        if rec.playtimeLevel then played = played .. " (" .. W.Duration(rec.playtimeLevel) .. " this level)" end
        table.insert(meta, played)
    end
    table.insert(meta, "|cff888888Updated " .. W.Ago(rec.lastUpdate) .. "|r")
    self.metaText:SetText(table.concat(meta, "    "))
    self.gsText:SetText(W.Color(string.format("%s GS (%.1f Eq / %.1f Overall)", W.Num(rec.gs), rec.ilvl or 0, rec.ilvlBag or 0),
        W.GsHex(rec.gs, rec.ilvl)) .. (FS.HAS_POINTS and ("   " .. W.Color(W.Num(rec.legacy) .. " " .. FS.POINTS.short, "00e6ff")) or ""))

    -- Gear
    local gear = rec.gear or {}
    for _, slot in ipairs(FS.GEAR_SLOTS) do
        local cell, item = self.slots[slot], gear[slot]
        cell.slot:SetText(FS.SLOT_LABELS[slot])
        if item then
            cell.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            cell.ilvl:SetText("iLvl " .. (item.ilvl or 0))
            local name = tostring(item.name or slot)
            if not name:find("|c", 1, true) then name = W.Color("[" .. name .. "]", W.QUALITY_HEX[item.quality or 1] or "ffffff") end
            cell.item:SetText(name)
            cell.link = item.name
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        else
            cell.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            cell.ilvl:SetText("")
            cell.item:SetText(W.Color("Empty", "666666"))
            cell.link = nil
            cell:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
        end
    end
    local summary = string.format("Equipped avg: %.1f iLvl  -  Overall: %.1f iLvl", rec.ilvl or 0, rec.ilvlBag or 0)
    if rec.highest and rec.highest.link then summary = summary .. "  -  Best: " .. rec.highest.link end
    self.gearSummary:SetText(summary)

    -- Professions
    local pal = W.Pal()
    local profs = rec.profs or {}
    for i, pb in ipairs(self.profBars) do
        local prof = profs[i]
        if prof then
            pb.label:SetText(prof.name .. (prof.tier and W.Color(" (" .. prof.tier .. ")", "888888") or "")
                .. (prof.kind == "secondary" and W.Color("  secondary", "666666") or ""))
            pb.value:SetText(string.format("%d / %d", prof.rank or 0, prof.max or 300))
            pb.bar:SetMinMaxValues(0, math.max(1, prof.max or 300))
            pb.bar:SetValue(prof.rank or 0)
            if prof.kind == "secondary" then
                pb.bar:SetStatusBarColor(0.55, 0.55, 0.6, 0.9)
            else
                pb.bar:SetStatusBarColor(pal.accent[1], pal.accent[2], pal.accent[3], 0.9)
            end
        end
        pb.label:SetShown(prof ~= nil); pb.value:SetShown(prof ~= nil); pb.bar:SetShown(prof ~= nil)
    end
    self.noProfs:SetShown(#profs == 0)
    self.noProfs:SetText(rec.isMyChar and "No professions learned yet." or "Not shared by this player.")
    self.gatherText:SetText(string.format("%s gathered  -  %s crafted", W.Num(FS:GetValue(rec, "gathered")), W.Num(FS:GetValue(rec, "crafted"))))

    -- Legacy chips
    self:RefreshLegacy(rec)

    -- Ledger and nemesis
    for i, entry in ipairs(LEDGER) do
        local cell = self.ledger[i]
        cell.label:SetText(entry[1])
        local ok, text = pcall(entry[2], rec)
        cell.value:SetText(ok and text or "-")
        cell.value:SetWidth(math.max(60, (cell:GetWidth() or 300) - (cell.label:GetStringWidth() or 100) - 24))
    end
    local nemesis, nCount = TopEntry(rec.killers)
    local victim, vCount = TopEntry(rec.mobs)
    self.nemesisText:SetText(string.format("Nemesis: %s   -   Top Victim: %s",
        nemesis and W.Color(string.format("%s (%d)", nemesis, nCount), "ff5555") or "none yet",
        victim and W.Color(string.format("%s (%d)", victim, vCount), "00ff96") or "none yet"))
end

function Inspector:RefreshLegacy(rec)
    local catalog = FS.Tracker.legacyCatalog
    local earnedSet = {}
    for _, id in ipairs(rec.legacyEarned or {}) do earnedSet[id] = true end

    local chips = {}
    if catalog then
        self.legacyTitle:SetText("WoW: Forever " .. FS.POINTS.items)
        for _, a in ipairs(catalog) do table.insert(chips, { name = a.name, done = earnedSet[a.id], points = a.points }) end
        table.sort(chips, function(a, b)
            if (a.done and 1 or 0) ~= (b.done and 1 or 0) then return a.done and true or false end
            return tostring(a.name) < tostring(b.name)
        end)
    elseif FS.HAS_POINTS then
        self.legacyTitle:SetText("Recent Achievements")
        for _, id in ipairs(rec.legacyEarned or {}) do
            local _, name, points = FS.Tracker.Safe(GetAchievementInfo, id)
            if name then table.insert(chips, { name = name, done = true, points = points }) end
        end
    else
        -- No achievements in this game: show this character's own milestones instead.
        self.legacyTitle:SetText("Milestones")
        for _, ev in ipairs(FS.db.global.events) do
            if ev.who == rec.fullName and #chips < 24 then
                local label = (ev.kind == "level" and ("Level " .. tostring(ev.v)))
                    or (ev.kind == "prof" and string.format("%s %s", tostring(ev.a), tostring(ev.v)))
                    or (ev.kind == "boss" and ("Defeated " .. tostring(ev.a)))
                    or (ev.kind == "gear" and (W.Num(ev.v) .. " GearScore"))
                    or (ev.kind == "milestone" and W.MilestoneText(ev.a, ev.v))
                if label then table.insert(chips, { name = label, done = true }) end
            end
        end
    end
    W.AccentText(self.legacyTitle)
    if FS.HAS_POINTS then
        self.lpText:SetText(W.Color((rec.legacyMax and string.format("%d / %d", rec.legacy or 0, rec.legacyMax) or W.Num(rec.legacy)) .. " " .. FS.POINTS.short, "00e6ff"))
    else
        self.lpText:SetText("")
    end

    local chipW = (self.chipScroll:GetWidth() > 0 and self.chipScroll:GetWidth() or 420) / 2 - 4
    self.chipContent:SetWidth(chipW * 2 + 8)
    for i, chip in ipairs(chips) do
        local box = self.chips[i]
        if not box then
            box = W.Box(self.chipContent, "pill", true)
            box:SetHeight(20)
            box.text = W.Text(box, "GameFontHighlightSmall")
            box.text:SetPoint("LEFT", 6, 0)
            box.text:SetPoint("RIGHT", -6, 0)
            self.chips[i] = box
        end
        box:SetWidth(chipW)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", ((i - 1) % 2) * (chipW + 8), -math.floor((i - 1) / 2) * 23)
        local label = chip.points and string.format("%s (+%d)", tostring(chip.name), tonumber(chip.points) or 0) or tostring(chip.name)
        box.text:SetText(chip.done and W.Color(label, "ffd100") or W.Color(label, "666666"))
        box:Show()
    end
    for i = #chips + 1, #self.chips do self.chips[i]:Hide() end
    self.chipContent:SetHeight(math.max(10, math.ceil(#chips / 2) * 23))
    if #chips == 0 then
        if not self.noChips then
            self.noChips = W.Text(self.chipContent, "GameFontDisable")
            self.noChips:SetPoint("TOPLEFT", 4, -4)
        end
        self.noChips:SetText(rec.isMyChar and ("No " .. FS.POINTS.items:lower() .. " completed yet.") or "Not shared by this player.")
        self.noChips:Show()
    elseif self.noChips then
        self.noChips:Hide()
    end
end

-- "Kima (60 Warrior): 12,345 kills, 47 deaths (nemesis: Hogger), 1,234 km travelled, 21d 4h played."
function Inspector:ShareText()
    local r = self.rec
    if not r then return nil end
    local nemesis, n = nil, 0
    for name, count in pairs(r.killers or {}) do if count > n then nemesis, n = name, count end end
    return string.format("%s (%s %s): %s GS, %s kills, %s deaths%s, %s travelled, %s played.",
        FS.ShortName(r.fullName), tostring(r.level or "?"), W.Plain(W.ClassName(r.cls)), W.Num(r.gs), W.Num(FS:GetValue(r, "kills")),
        W.Num(FS:GetValue(r, "deaths")), nemesis and (" (nemesis: " .. nemesis .. ")") or "",
        W.Plain(W.Distance(FS:GetValue(r, "travelTotal"))), W.Plain(W.Duration(r.playtime)))
end

function Inspector:UpdatePin()
    if not self.pinBtn or not self.rec then return end
    local pinned = false
    for _, key in ipairs(FS.db.profile.pins) do if key == self.rec.fullName then pinned = true end end
    self.pinBtn.text:SetText(W.T(pinned and "Unpin" or "Pin"))
    self.pinBtn:SetActive(pinned)
end
