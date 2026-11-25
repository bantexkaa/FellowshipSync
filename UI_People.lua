local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local View = FS.FellowshipUI
local UI, W = FS.UI, FS.W
local People = FS.People

---------------------------------------------------------------------------
-- Fellowship > People: everyone you've met (this computer only)
---------------------------------------------------------------------------

local FILTERS = {
    { id = "all",     label = "Everyone" },
    { id = "kept",    label = "Kept" },
    { id = "grouped", label = "Grouped & talked" },
    { id = "enemies", label = "Enemies" },
}
local TOP = -90
local CARD_H = 96

local function NameText(rec)
    local name = FS.ShortName(rec.k)
    local hex = rec.cls and W.ClassHex(rec.cls) or "dddddd"
    local text = W.Color(name, hex)
    if People:InNetwork(rec) then text = text .. W.Color("  FS", "ffd100") end
    return text
end

function View:BuildPeople(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    self.panes.people = p
    self.peopleFilter = "all"

    self.peopleTabs = W.SubTabs(p, FILTERS, 500, function(id) self.peopleFilter = id; self.peopleSel = nil; self:Refresh() end, 22)
    self.peopleTabs:SetPoint("TOPLEFT", 14, TOP)
    self.peopleSearch = W.Search(p, 300, "Search name, guild, zone or note...", function(q) self.peopleQuery = q; self:Refresh() end)
    self.peopleSearch:SetPoint("TOPRIGHT", -14, TOP - 3)

    self.peopleList = W.List(p, {
        { label = "", width = 16 },
        { label = "Name", width = 190 }, { label = "Level", width = 46, justify = "RIGHT" },
        { label = "Guild", width = 130 }, { label = "How you met", width = 200 },
        { label = "Met", width = 44, justify = "RIGHT" }, { label = "Last seen", width = 100, justify = "RIGHT" },
        { label = "Where", width = 130 },
    }, {
        id = "people",
        onClick = function(rec) self.peopleSel = rec.k; self:Refresh() end,
        emptyText = "Nobody yet. Players you group, trade, talk with or cross paths with appear here.",
    })
    self.peopleList.frame:SetPoint("TOPLEFT", 14, TOP - 38)
    self.peopleList.frame:SetPoint("BOTTOMRIGHT", -12, CARD_H + 16)

    -- The selected person
    local card = W.Box(p, "card")
    card:SetPoint("BOTTOMLEFT", 14, 10)
    card:SetPoint("BOTTOMRIGHT", -12, 10)
    card:SetHeight(CARD_H)
    self.peopleCard = card
    card.name = W.Text(card, "GameFontNormalLarge")
    card.name:SetPoint("TOPLEFT", 12, -10)
    card.info = W.Text(card, "GameFontHighlightSmall")
    card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    card.info:SetWidth(560)
    card.how = W.Text(card, "GameFontDisableSmall")
    card.how:SetPoint("TOPLEFT", card.info, "BOTTOMLEFT", 0, -3)
    card.how:SetWidth(560)

    local note = CreateFrame("EditBox", nil, card, "BackdropTemplate")
    note:SetSize(520, 22)
    note:SetPoint("BOTTOMLEFT", 12, 8)
    note:SetBackdrop(W.FLAT)
    note:SetBackdropColor(0, 0, 0, 0.6)
    note:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    note:SetAutoFocus(false)
    note:SetFontObject(ChatFontNormal)
    note:SetTextInsets(8, 8, 0, 0)
    note:SetMaxLetters(120)
    note.hint = W.Text(note, "GameFontDisableSmall")
    note.hint:SetPoint("LEFT", 8, 0)
    note.hint:SetText(W.T("Add a note (saving it keeps this person)..."))
    note:SetScript("OnTextChanged", function(box) box.hint:SetShown((box:GetText() or "") == "") end)
    note:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    note:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        if self.peopleSel then
            local text = strtrim(box:GetText() or "")
            People:Ink(self.peopleSel, true, text)
            self:Refresh()
        end
    end)
    card.note = note

    card.keep = W.Button(card, "Keep", 110, 24, function()
        local rec = self.peopleSel and People:Data()[self.peopleSel]
        if rec then People:Ink(rec.k, not rec.ink); self:Refresh() end
    end)
    card.keep:SetPoint("TOPRIGHT", -12, -10)
    card.forget = W.Button(card, "Forget", 110, 24, function()
        if self.peopleSel then People:Forget(self.peopleSel); self.peopleSel = nil; self:Refresh() end
    end)
    card.forget:SetPoint("TOPRIGHT", card.keep, "BOTTOMRIGHT", 0, -4)
    card.profile = W.Button(card, "Profile", 110, 24, function()
        local rec = self.peopleSel and People:Data()[self.peopleSel]
        local c = rec and People:InNetwork(rec)
        if c then UI:OpenInspector(c) end
    end)
    card.profile:SetPoint("RIGHT", card.keep, "LEFT", -6, 0)
    card.tip = W.Text(card, "GameFontDisableSmall", "RIGHT")
    card.tip:SetPoint("BOTTOMRIGHT", -12, 12)
end

function View:Refresh_people()
    local set = People:Settings()
    local data = People:Data()
    local list = People:List(self.peopleFilter, self.peopleQuery)
    local kept = 0
    for _, rec in pairs(data) do if type(rec) == "table" and rec.ink then kept = kept + 1 end end
    self.title:SetText(W.T("People I've Met"))
    self.sub:SetText(string.format(W.T("%d people, %d kept. Others are pencilled in and fade after %d days (90+ if you grouped, traded or talked). Only on this computer, never shared."),
        #list, kept, tonumber(set.days) or 30))
    self.peopleTabs:Select(self.peopleFilter, true)

    local rows = {}
    for i, rec in ipairs(list) do
        rows[i] = {
            rec = rec,
            isSelf = rec.k == self.peopleSel,
            sv = { [1] = rec.ink and 1 or 0, [3] = rec.lvl, [6] = rec.met, [7] = rec.last },
            cells = {
                rec.ink and W.Color("*", "ffd100") or "",
                NameText(rec),
                rec.lvl and tostring(rec.lvl) or "?",
                rec.guild and W.Color("<" .. rec.guild .. ">", "40ff40") or "",
                People.Interacted(rec) and People:HowMet(rec) or W.Color(W.T("Crossed paths"), "888888"),
                W.Num(rec.met or 1),
                W.Ago(rec.last),
                rec.zone or "",
            },
        }
    end
    self.peopleList:SetRows(rows)
    self:RefreshPeopleCard()
end

function View:RefreshPeopleCard()
    local card = self.peopleCard
    local rec = self.peopleSel and People:Data()[self.peopleSel]
    if not rec then
        card.name:SetText(W.T("Pick someone from the list"))
        card.info:SetText(W.T("Tip: target or hover a player and use \"Remember this player\" (Key Bindings > AddOns) or type /fsync remember <note>."))
        card.how:SetText("")
        card.note:Hide(); card.keep:Hide(); card.forget:Hide(); card.profile:Hide()
        card.tip:SetText("")
        return
    end
    card.note:Show(); card.keep:Show(); card.forget:Show()
    card.name:SetText((rec.ink and W.Color("* ", "ffd100") or "") .. NameText(rec)
        .. (rec.guild and W.Color("  <" .. rec.guild .. ">", "40ff40") or ""))
    local parts = {}
    if rec.lvl then table.insert(parts, W.T("Level") .. " " .. rec.lvl) end
    if rec.race then table.insert(parts, rec.race) end
    if rec.cls then table.insert(parts, W.Plain(W.ClassName(rec.cls))) end
    if rec.enemy then table.insert(parts, W.Color(W.T("Enemy"), "ff5555")) end
    table.insert(parts, string.format(W.T("first met %s"), W.Plain(W.Ago(rec.first))) .. (rec.firstZone and (" " .. W.T("in") .. " " .. rec.firstZone) or ""))
    table.insert(parts, string.format(W.T("last seen %s"), W.Plain(W.Ago(rec.last))) .. (rec.zone and (" " .. W.T("in") .. " " .. rec.zone) or ""))
    card.info:SetText(table.concat(parts, "  -  "))
    card.how:SetText(string.format(W.T("Met %d times: %s"), rec.met or 1, People:HowMet(rec)))
    if not card.note:HasFocus() then card.note:SetText(rec.note or "") end
    card.keep.text:SetText(W.T(rec.ink and "Stop keeping" or "Keep"))
    card.profile:SetShown(People:InNetwork(rec) ~= nil)
    if rec.ink then
        card.tip:SetText(W.T("Kept: never removed."))
    else
        local days = math.max(0, math.ceil((People:ExpireAfter(rec, tonumber(People:Settings().days) or 30) - time()) / 86400))
        card.tip:SetText(string.format(W.T("Pencilled in: fades in %d days unless you meet again."), days))
    end
end
