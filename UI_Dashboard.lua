local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Dashboard = FS.Dashboard
local UI, W = FS.UI, FS.W

local CARD_H, GAP, COLS, ROWS = 148, 10, 3, 5

local function WidgetState(scope)
    local all = FS.db.profile.hofWidgets
    all[scope] = all[scope] or {}
    return all[scope]
end

function Dashboard:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f

    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -12)

    self.chooseBtn = W.Button(f, "Choose Scoreboards", 160, 22, function() self:ToggleSettings() end)
    self.chooseBtn:SetPoint("LEFT", self.title, "RIGHT", 14, 0)
    self.countText = W.Text(f, "GameFontDisableSmall")
    self.countText:SetPoint("LEFT", self.chooseBtn, "RIGHT", 10, 0)

    local items = {}
    for _, s in ipairs(UI.SCOPES) do table.insert(items, { id = s.id, label = UI.SCOPE_TITLES[s.id] }) end
    self.subTabs = W.SubTabs(f, items, 980, function(id) UI:SetScope(id) end)
    self.subTabs:SetPoint("TOPLEFT", 14, -42)

    self:BuildBanner(f)

    self.scroll, self.grid = W.ScrollArea(f)
    self.scroll:SetPoint("BOTTOMRIGHT", -36, 10)
    self.cards = {}

    self:BuildSettings(f)
end

---------------------------------------------------------------------------
-- Solo roster banner (blueprint: "Personal Roster Overview")
---------------------------------------------------------------------------

function Dashboard:BuildBanner(f)
    local b = W.Box(f, "accent")
    b:SetPoint("TOPLEFT", 14, -82)
    b:SetSize(980, 100)
    self.banner = b

    -- Row 1: title. Row 2: the four summary pills. Row 3: quick-inspect buttons.
    b.head = W.Text(b, "GameFontNormalLarge")
    b.head:SetPoint("TOPLEFT", 12, -10)

    b.pills = {}
    for i = 1, 4 do
        local p = W.Box(b, "pill", true)
        p:SetSize(232, 22)
        p:SetPoint("TOPLEFT", 12 + (i - 1) * 240, -36)
        p.text = W.Text(p, "GameFontHighlightSmall", "CENTER")
        p.text:SetAllPoints()
        b.pills[i] = p
    end

    b.inspectLabel = W.Text(b, "GameFontNormalSmall")
    b.inspectLabel:SetPoint("BOTTOMLEFT", 12, 12)
    b.inspectLabel:SetText("Inspect:")
    b.charButtons = {}
end

function Dashboard:RefreshBanner(chars)
    local b = self.banner
    local owner = FS.Tracker:AccountLabel()
    b.head:SetText(string.upper(owner) .. "  -  Personal Roster Overview")
    W.AccentText(b.head)

    local bestGs, bestIlvl, lp, lpMax, played, gold = 0, 0, 0, nil, 0, 0
    for _, c in ipairs(chars) do
        if (c.gs or 0) > bestGs then bestGs, bestIlvl = c.gs or 0, c.ilvl or 0 end
        lp = math.max(lp, tonumber(c.legacy) or 0)
        lpMax = lpMax or c.legacyMax
        played = played + FS:GetValue(c, "playtime")
        gold = gold + (tonumber(c.wealth) or 0)
    end
    local pills = {
        "Highest GS: " .. W.Color(string.format("%s (%.1f)", W.Num(bestGs), bestIlvl), W.GsHex(bestGs, bestIlvl)),
        FS.HAS_POINTS and ("Account " .. FS.POINTS.short .. ": " .. W.Color(lpMax and string.format("%d / %d", lp, lpMax) or W.Num(lp), "00e6ff"))
            or ("Characters: " .. W.Color(#chars, "00e6ff")),
        (FS:IsWeekMode() and "Played this week: " or "Total played: ") .. W.Color(W.Duration(played), "ffd100"),
        "Total gold: " .. W.Money(gold),
    }
    for i, p in ipairs(b.pills) do p.text:SetText(pills[i]) end

    FS:SortByStat(chars, "gs")
    local x, maxX = 70, 960
    for i, c in ipairs(chars) do
        local btn = b.charButtons[i]
        if not btn then
            btn = W.Button(b, "", 140, 22, function(self) UI:OpenInspector(self.rec, chars) end)
            btn:SetScript("OnEnter", function(self) W.CharTooltip(self, self.rec) end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b.charButtons[i] = btn
        end
        btn.rec = c
        btn.text:SetText(string.format("%s |cffaaaaaaLvl %d|r", W.CharName(c), tonumber(c.level) or 0))
        local w = math.min(170, (btn.text:GetStringWidth() or 100) + 18)
        btn:SetWidth(w)
        if x + w <= maxX then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x, 8)
            btn:Show()
            x = x + w + 4
        else
            btn:Hide()
        end
    end
    for i = #chars + 1, #b.charButtons do b.charButtons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Scoreboard chooser
---------------------------------------------------------------------------

function Dashboard:BuildSettings(f)
    local s = W.Box(f, "accent")
    s:SetPoint("TOPLEFT", 14, -80)
    s:SetSize(980, 32 + math.ceil(#FS.HOF_WIDGETS / 5) * 25 + 10)
    s:SetFrameLevel(f:GetFrameLevel() + 30)
    s:EnableMouse(true)
    s:Hide()
    self.settings = s

    s.head = W.Text(s, "GameFontNormal")
    s.head:SetPoint("TOPLEFT", 12, -10)

    local function Act(fn) return function() fn(); self:Refresh() end end
    local syncBtn = W.Button(s, "Sync Layout to All 4 Tabs", 180, 20, Act(function()
        local src = WidgetState(UI.currentScope)
        for _, scope in ipairs({ "solo", "guild", "network", "netaccs" }) do
            local dst = WidgetState(scope)
            for _, w in ipairs(FS.HOF_WIDGETS) do dst[w.id] = src[w.id] and true or false end
            local order = {}
            for _, w in ipairs(self:OrderedWidgets(UI.currentScope)) do table.insert(order, w.id) end
            FS.db.profile.hofOrder[scope] = order
        end
    end))
    syncBtn:SetPoint("TOPRIGHT", -10, -8)
    local resetBtn = W.Button(s, "Reset Default 9", 120, 20, Act(function()
        local st = WidgetState(UI.currentScope)
        for _, w in ipairs(FS.HOF_WIDGETS) do st[w.id] = w.on end
    end))
    resetBtn:SetPoint("RIGHT", syncBtn, "LEFT", -6, 0)
    local allBtn = W.Button(s, "Show All " .. #FS.HOF_WIDGETS, 100, 20, Act(function()
        local st = WidgetState(UI.currentScope)
        for _, w in ipairs(FS.HOF_WIDGETS) do st[w.id] = true end
    end))
    allBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
    local orderBtn = W.Button(s, "Reset Order", 100, 20, Act(function()
        FS.db.profile.hofOrder = FS.db.profile.hofOrder or {}
        FS.db.profile.hofOrder[UI.currentScope] = nil
    end))
    orderBtn:SetPoint("RIGHT", allBtn, "LEFT", -6, 0)

    self.checks = {}
    for i, w in ipairs(FS.HOF_WIDGETS) do
        local cb = W.Check(s, w.title, function(checked)
            WidgetState(UI.currentScope)[w.id] = checked
            self:Refresh()
        end)
        local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
        cb:SetPoint("TOPLEFT", 12 + col * 192, -36 - row * 25)
        cb.widgetId = w.id
        self.checks[i] = cb
    end
end

function Dashboard:ToggleSettings()
    self.settings:SetShown(not self.settings:IsShown())
    self:Refresh()
end

---------------------------------------------------------------------------
-- Scoreboard cards
---------------------------------------------------------------------------

function Dashboard:GetCard(i)
    if self.cards[i] then return self.cards[i] end
    local card = W.Box(self.grid, "card")
    card:SetHeight(CARD_H)
    card.title = W.Text(card, "GameFontNormal", "CENTER")
    card.title:SetPoint("TOPLEFT", 8, -9)
    card.title:SetPoint("TOPRIGHT", -8, -9)
    -- Drag the title bar onto another scoreboard to swap their places.
    local handle = CreateFrame("Button", nil, card)
    handle:SetPoint("TOPLEFT", 4, -4)
    handle:SetPoint("TOPRIGHT", -4, -4)
    handle:SetHeight(22)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnEnter", function(selfHandle)
        GameTooltip:SetOwner(selfHandle, "ANCHOR_TOP")
        GameTooltip:AddLine("Drag onto another scoreboard to move it", 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    handle:SetScript("OnDragStart", function() card:SetAlpha(0.45); self.dragging = card end)
    handle:SetScript("OnDragStop", function()
        card:SetAlpha(1)
        self.dragging = nil
        for _, other in ipairs(self.cards) do
            -- frame:IsMouseOver() works in every game version (the old global MouseIsOver is gone).
            if other ~= card and other:IsShown() and other:IsMouseOver() then
                self:MoveWidget(card.widgetId, other.widgetId)
                break
            end
        end
    end)
    card.handle = handle
    card.rows = {}
    for r = 1, ROWS do
        local row = CreateFrame("Button", nil, card)
        row:SetHeight(21)
        row:SetPoint("TOPLEFT", 8, -30 - (r - 1) * 22)
        row:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        row.selfBg = row:CreateTexture(nil, "BACKGROUND")
        row.selfBg:SetAllPoints()
        row.value = W.Text(row, "GameFontNormalSmall", "RIGHT")
        row.value:SetPoint("RIGHT", -4, 0)
        row.name = W.Text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row:SetScript("OnClick", function(self) if self.rec then UI:OpenInspector(self.rec, card.list) end end)
        row:SetScript("OnEnter", function(self) if self.rec then W.CharTooltip(self, self.rec) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card.rows[r] = row
    end
    self.cards[i] = card
    return card
end

-- Scoreboards in the player's chosen order (new ones are appended).
function Dashboard:OrderedWidgets(scope)
    local orders = FS.db.profile.hofOrder or {}
    FS.db.profile.hofOrder = orders
    local byId, out, seen = {}, {}, {}
    for _, w in ipairs(FS.HOF_WIDGETS) do byId[w.id] = w end
    for _, id in ipairs(orders[scope] or {}) do
        if byId[id] and not seen[id] then table.insert(out, byId[id]); seen[id] = true end
    end
    for _, w in ipairs(FS.HOF_WIDGETS) do if not seen[w.id] then table.insert(out, w) end end
    return out
end

function Dashboard:MoveWidget(fromId, toId)
    local scope = UI.currentScope
    local list = self:OrderedWidgets(scope)
    local ids, fromIndex, toIndex = {}, nil, nil
    for i, w in ipairs(list) do
        ids[i] = w.id
        if w.id == fromId then fromIndex = i end
        if w.id == toId then toIndex = i end
    end
    if not fromIndex or not toIndex then return end
    ids[fromIndex], ids[toIndex] = ids[toIndex], ids[fromIndex]
    FS.db.profile.hofOrder[scope] = ids
    self:Refresh()
end

function Dashboard:CardValue(widget, rec)
    if widget.id == "gear" then
        return W.Color(string.format("%s (%.1f)", W.Num(rec.gs), tonumber(rec.ilvl) or 0), W.GsHex(rec.gs, rec.ilvl))
    end
    return W.FormatStat(widget.key, FS:GetValue(rec, widget.key))
end

function Dashboard:Refresh()
    if not self.frame then return end
    local scope = UI.currentScope
    local state = WidgetState(scope)
    local chars = FS:GetFilteredCharacters(scope)

    self.title:SetText("Hall of Fame  -  " .. UI.SCOPE_TITLES[scope] .. (FS:IsWeekMode() and "  (This Week)" or ""))
    self.subTabs:Select(scope, true)

    local shown = 0
    for _, w in ipairs(FS.HOF_WIDGETS) do if state[w.id] then shown = shown + 1 end end
    self.countText:SetText(string.format("(%d of %d scoreboards shown)", shown, #FS.HOF_WIDGETS))
    self.settings.head:SetText("Customizing scoreboards for: " .. UI.SCOPE_TITLES[scope])
    W.AccentText(self.settings.head)
    for _, cb in ipairs(self.checks) do cb:SetChecked(state[cb.widgetId] and true or false) end

    local solo = scope == "solo"
    self.banner:SetShown(solo)
    if solo then self:RefreshBanner(FS:GetFilteredCharacters("solo")) end
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 14, solo and -190 or -82)
    self.scroll:SetPoint("BOTTOMRIGHT", -36, 10)

    local width = math.max(600, (self.scroll:GetWidth() or 960))
    self.grid:SetWidth(width)
    local cardW = (width - GAP * (COLS - 1)) / COLS
    local font, size = W.FontPath(), math.max(10, W.TextSize() - 1)

    local index = 0
    for _, widget in ipairs(self:OrderedWidgets(scope)) do
        if state[widget.id] then
            index = index + 1
            local card = self:GetCard(index)
            card:SetWidth(cardW)
            card:ClearAllPoints()
            local col, row = (index - 1) % COLS, math.floor((index - 1) / COLS)
            card:SetPoint("TOPLEFT", self.grid, "TOPLEFT", col * (cardW + GAP), -row * (CARD_H + GAP))
            card.title:SetText(widget.title)
            card.widgetId = widget.id
            W.AccentText(card.title)

            local sorted = {}
            for i, c in ipairs(chars) do sorted[i] = c end
            FS:SortByStat(sorted, widget.key)
            card.list = sorted
            local pal = W.Pal()
            for r, row in ipairs(card.rows) do
                local rec = sorted[r]
                row.rec = rec
                row.name:SetFont(font, size, W.FontFlags())
                row.value:SetFont(font, size, W.FontFlags())
                if rec then
                    row.name:SetText(W.Rank(r) .. " " .. W.Label(rec, { owner = scope ~= "solo" }))
                    row.value:SetText(W.RankValue(r, self:CardValue(widget, rec)))
                    row.value:SetWidth(math.min(cardW * 0.6, (row.value:GetStringWidth() or 60) + 6))
                    if rec.isMyChar and scope ~= "solo" then
                        row.selfBg:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], 0.10)
                    else
                        row.selfBg:SetColorTexture(0, 0, 0, 0)
                    end
                    row:Show()
                else
                    row:Hide()
                end
            end
            card:Show()
        end
    end
    for i = index + 1, #self.cards do self.cards[i]:Hide() end
    self.grid:SetHeight(math.max(100, math.ceil(index / COLS) * (CARD_H + GAP)))
end
