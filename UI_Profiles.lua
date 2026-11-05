local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Profiles = FS.Profiles
local UI, W = FS.UI, FS.W

local ROW_H, HEAD_H = 40, 34
local ONLINE_WINDOW = 900 -- seconds since last sync to count as online

function Profiles:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -12)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetText("One card per player. Click any character to inspect it.")
    self.search = W.Search(f, 320, "Search player, character, GearScore or zone...", function(q) self.query = q; self:Refresh() end)
    self.search:SetPoint("TOPRIGHT", -36, -12)
    self.scroll, self.content = W.ScrollArea(f)
    self.scroll:SetPoint("TOPLEFT", 14, -56)
    self.scroll:SetPoint("BOTTOMRIGHT", -36, 10)
    self.cards = {}
end

function Profiles:GetCard(i)
    if self.cards[i] then return self.cards[i] end
    local card = W.Box(self.content, "card")
    card.dot = card:CreateTexture(nil, "ARTWORK")
    card.dot:SetSize(10, 10)
    card.dot:SetPoint("TOPLEFT", 12, -13)
    card.head = W.Text(card, "GameFontNormalLarge")
    card.head:SetPoint("LEFT", card.dot, "RIGHT", 6, 0)
    card.lp = W.Text(card, "GameFontNormal", "RIGHT")
    card.lp:SetPoint("TOPRIGHT", -12, -10)
    card.rows = {}
    -- Own account uses the accent look, everyone else the normal card look.
    function card:UpdateLook()
        local pal = W.Pal()
        if self.themeRole == "accent" then
            self:SetBackdropColor(pal.accent[1] * 0.12, pal.accent[2] * 0.12, pal.accent[3] * 0.12, 0.92)
            self:SetBackdropBorderColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
        else
            self:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
            self:SetBackdropBorderColor(pal.border[1], pal.border[2], pal.border[3], 0.8)
        end
    end
    self.cards[i] = card
    return card
end

function Profiles:GetRow(card, j)
    if card.rows[j] then return card.rows[j] end
    local row = CreateFrame("Button", nil, card, "BackdropTemplate")
    row:SetBackdrop(W.FLAT)
    row:SetHeight(ROW_H - 4)
    row.name = W.Text(row, "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 8, -5)
    row.info = W.Text(row, "GameFontDisableSmall")
    row.info:SetPoint("BOTTOMLEFT", 8, 5)
    row.profs = W.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.profs:SetPoint("TOPRIGHT", -8, -5)
    row.zone = W.Text(row, "GameFontDisableSmall", "RIGHT")
    row.zone:SetPoint("BOTTOMRIGHT", -8, 5)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.10)
    row:SetScript("OnClick", function(self) if self.rec then UI:OpenInspector(self.rec, self.siblings) end end)
    row:SetScript("OnEnter", function(self) if self.rec then W.CharTooltip(self, self.rec) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.rows[j] = row
    return row
end

local function AccountMatches(acc, q)
    if not q or q == "" then return true end
    if tostring(acc.owner):lower():find(q, 1, true) then return true end
    for _, c in ipairs(acc.chars) do if W.Matches(c, q) then return true end end
    return false
end

function Profiles:Refresh()
    if not self.frame then return end
    self.title:SetText("Player Cards & Rosters  -  " .. UI.SCOPE_TITLES[UI.currentScope])
    local accounts = {}
    for _, acc in ipairs(FS.BuildAccounts(FS:GetScopeCharacters(UI.currentScope))) do
        if AccountMatches(acc, self.query) then
            acc.online = acc.isMyChar or (time() - (acc.lastUpdate or 0) < ONLINE_WINDOW)
            table.insert(accounts, acc)
        end
    end
    table.sort(accounts, function(a, b)
        if (a.isMyChar and 1 or 0) ~= (b.isMyChar and 1 or 0) then return a.isMyChar and true or false end
        if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
        if (a.legacy or 0) ~= (b.legacy or 0) then return (a.legacy or 0) > (b.legacy or 0) end
        return tostring(a.owner) < tostring(b.owner)
    end)

    local width = math.max(600, self.scroll:GetWidth() or 960)
    self.content:SetWidth(width)
    local colW = (width - 10) / 2
    local colY = { 0, 0 }
    local pal = W.Pal()

    for i, acc in ipairs(accounts) do
        local card = self:GetCard(i)
        local col = (colY[1] <= colY[2]) and 1 or 2
        local height = HEAD_H + #acc.chars * ROW_H + 8
        card:SetSize(colW, height)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", (col - 1) * (colW + 10), -colY[col])
        colY[col] = colY[col] + height + 10

        card.dot:SetColorTexture(acc.online and 0.1 or 0.35, acc.online and 0.9 or 0.35, acc.online and 0.3 or 0.35, 1)
        card.head:SetText(string.upper(acc.owner or "?") .. W.Badge(acc, true))
        if acc.isMyChar then W.AccentText(card.head) else card.head:SetTextColor(1, 1, 1, 1) end
        if FS.HAS_POINTS then
            card.lp:SetText(W.Color(W.Num(acc.legacy) .. " " .. FS.POINTS.short, "00e6ff"))
        else
            card.lp:SetText(W.Color("Best: " .. W.Num(acc.gs) .. " GS", W.GsHex(acc.gs, acc.ilvl)))
        end
        card.themeRole = acc.isMyChar and "accent" or "card"
        card:UpdateLook()

        FS:SortByStat(acc.chars, "gs")
        for j, c in ipairs(acc.chars) do
            local row = self:GetRow(card, j)
            row.rec, row.siblings = c, acc.chars
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, -(HEAD_H + (j - 1) * ROW_H))
            row:SetPoint("RIGHT", card, "RIGHT", -8, 0)
            row:SetBackdropColor(0, 0, 0, 0.35)
            row:SetBackdropBorderColor(pal.border[1] * 0.5, pal.border[2] * 0.5, pal.border[3] * 0.5, 1)
            row.name:SetText(string.format("%s  |cffaaaaaaLvl %s %s|r", W.CharName(c), tostring(c.level or "?"), W.ClassName(c.cls):sub(1, 3)))
            row.info:SetText(W.Color(string.format("%s GS - %.1f iLvl", W.Num(c.gs), c.ilvl or 0), W.GsHex(c.gs, c.ilvl)))
            row.profs:SetText(FS.Misc.ProfSummary(c, 2))
            row.zone:SetText(c.zone or "")
            row:Show()
        end
        for j = #acc.chars + 1, #card.rows do card.rows[j]:Hide() end
        card:Show()
    end
    for i = #accounts + 1, #self.cards do self.cards[i]:Hide() end
    self.content:SetHeight(math.max(10, math.max(colY[1], colY[2])))
end
