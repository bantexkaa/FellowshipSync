local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Deathlog = FS.Deathlog
local UI, W = FS.UI, FS.W

local ENTRY_H = 62

function Deathlog:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -12)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.sub:SetText("Every death with zone, killer and famous last words (the last thing you said before dying).")

    self.search = W.Search(f, 300, "Search character, owner, killer or zone...", function(q) self.query = q; self:Refresh() end)
    self.search:SetPoint("TOPRIGHT", -36, -12)

    self.scroll, self.content = W.ScrollArea(f)
    self.scroll:SetPoint("TOPLEFT", 14, -56)
    self.scroll:SetPoint("BOTTOMRIGHT", -36, 10)
    self.entries = {}
    self.empty = W.Text(f, "GameFontDisable", "CENTER")
    self.empty:SetPoint("CENTER")
    self.empty:SetText("No deaths recorded in this view. Stay safe out there!")
end

function Deathlog:GetEntry(i)
    if self.entries[i] then return self.entries[i] end
    local e = CreateFrame("Button", nil, self.content, "BackdropTemplate")
    e:SetBackdrop(W.FLAT)
    e:SetHeight(ENTRY_H)
    e.date = W.Text(e, "GameFontDisableSmall")
    e.date:SetPoint("TOPLEFT", 10, -7)
    e.zone = W.Text(e, "GameFontDisableSmall", "RIGHT")
    e.zone:SetPoint("TOPRIGHT", -10, -7)
    e.body = W.Text(e, "GameFontHighlight")
    e.body:SetPoint("TOPLEFT", 10, -24)
    e.body:SetPoint("RIGHT", e, "RIGHT", -10, 0)
    e.quote = W.Text(e, "GameFontNormalSmall")
    e.quote:SetPoint("TOPLEFT", 10, -43)
    e.quote:SetPoint("RIGHT", e, "RIGHT", -10, 0)
    e.bar = e:CreateTexture(nil, "ARTWORK")
    e.bar:SetPoint("TOPLEFT")
    e.bar:SetPoint("BOTTOMLEFT")
    e.bar:SetWidth(3)
    e.bar:SetColorTexture(0.8, 0.15, 0.15, 0.9)
    local hl = e:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.2, 0.2, 0.08)
    e:SetScript("OnClick", function(self) if self.rec then UI:OpenInspector(self.rec) end end)
    self.entries[i] = e
    return e
end

function Deathlog:Refresh()
    if not self.frame then return end
    local scope = UI.currentScope
    self.title:SetText("Deathlog  -  " .. UI.SCOPE_TITLES[scope] .. (FS:IsWeekMode() and " (This Week)" or ""))

    local deaths = {}
    local since = FS:IsWeekMode() and FS:WeekStart() or 0
    for _, rec in ipairs(FS:GetScopeCharacters(scope)) do
        for _, d in ipairs(rec.deathLog or {}) do
            local hay = table.concat({ tostring(rec.fullName), tostring(rec.owner), tostring(d.killer), tostring(d.zone) }, " "):lower()
            local matches = not self.query or self.query == "" or hay:find(self.query, 1, true)
            if (d.t or 0) >= since and matches then
                table.insert(deaths, { rec = rec, d = d })
            end
        end
    end
    table.sort(deaths, function(a, b) return (a.d.t or 0) > (b.d.t or 0) end)
    for i = #deaths, 201, -1 do deaths[i] = nil end

    local width = math.max(600, self.scroll:GetWidth() or 960)
    self.content:SetWidth(width)
    for i, item in ipairs(deaths) do
        local e, rec, d = self:GetEntry(i), item.rec, item.d
        e.rec = rec
        e:SetWidth(width)
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", 0, -(i - 1) * (ENTRY_H + 6))
        e:SetBackdropColor(0.09, 0.04, 0.04, 0.85)
        e:SetBackdropBorderColor(0.35, 0.12, 0.12, 1)
        e.date:SetText(W.Date(d.t))
        e.zone:SetText(d.zone ~= "" and d.zone or "Unknown zone")
        local killer = W.Color(d.killer or "Unknown", "ff4040")
        if d.kdesc and d.kdesc ~= "" then killer = killer .. W.Color(" (" .. d.kdesc .. ")", "aaaaaa") end
        local owner = rec.owner and W.Color(string.format(" (%s - %s GS)", rec.owner, W.Num(rec.gs)), "888888") or ""
        e.body:SetText(string.format("%s%s%s was killed by %s%s.", W.CharName(rec), owner, W.Badge(rec), killer,
            d.lvl and (" at level " .. d.lvl) or ""))
        if d.words then
            e.quote:SetText(W.Color('Famous last words: "' .. d.words .. '"', "ffd100"))
        else
            e.quote:SetText(W.Color("No last words. They went quietly.", "666666"))
        end
        e:Show()
    end
    for i = #deaths + 1, #self.entries do self.entries[i]:Hide() end
    self.content:SetHeight(math.max(10, #deaths * (ENTRY_H + 6)))
    self.empty:SetShown(#deaths == 0)
end
