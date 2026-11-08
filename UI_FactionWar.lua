local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local FactionWar = FS.FactionWar
local UI, W = FS.UI, FS.W

local HORDE = { 0.80, 0.15, 0.15 }
local ALLIANCE = { 0.12, 0.45, 0.90 }

-- mode: "avg" (average per character), "sum", "account" (Legacy is account-wide).
local CATEGORIES = {
    { key = "gs",          title = "Average GearScore (highest level chars)", mode = "avgTop" },
    { key = "legacy",      title = FS.POINTS.long .. " Earned", mode = "account" },
    { key = "damage",      title = "Total Damage Done",      mode = "sum" },
    { key = "deaths",      title = "Total Deaths (fewer is better)", mode = "sum", lower = true },
    { key = "kills",       title = "Total Kills",            mode = "sum" },
    { key = "healing",     title = "Total Healing Done",     mode = "sum" },
    { key = "quests",      title = "Quests Completed",       mode = "sum" },
    { key = "goldLooted",  title = "Gold Looted",            mode = "sum" },
    { key = "duelsWon",    title = "Duels Won",              mode = "sum" },
    { key = "critters",    title = "Critters Butchered",     mode = "sum" },
    { key = "jumps",       title = "Total Jumps",            mode = "sum" },
    { key = "flightTime",  title = "Time on Flight Paths",   mode = "sum" },
}

if not FS.HAS_POINTS then
    for i = #CATEGORIES, 1, -1 do if CATEGORIES[i].key == "legacy" then table.remove(CATEGORIES, i) end end
end

function FactionWar:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.title = W.Text(f, "GameFontNormalLarge", "CENTER")
    self.title:SetPoint("TOP", 0, -12)

    local banner = W.Box(f, "card")
    banner:SetPoint("TOPLEFT", 14, -40)
    banner:SetPoint("TOPRIGHT", -14, -40)
    banner:SetHeight(84)
    self.banner = banner

    local function Side(anchor, x, r, g, b, name, icon, justify)
        local box = CreateFrame("Frame", nil, banner, "BackdropTemplate")
        box:SetBackdrop(W.FLAT)
        box:SetBackdropColor(r * 0.25, g * 0.25, b * 0.25, 0.9)
        box:SetBackdropBorderColor(r, g, b, 1)
        box:SetSize(360, 64)
        box:SetPoint(anchor, x, 0)
        local tex = box:CreateTexture(nil, "ARTWORK")
        tex:SetSize(44, 44)
        tex:SetTexture(icon)
        tex:SetPoint(justify == "LEFT" and "LEFT" or "RIGHT", justify == "LEFT" and 10 or -10, 0)
        box.name = W.Text(box, "GameFontNormalHuge", justify)
        box.name:SetPoint(justify == "LEFT" and "TOPLEFT" or "TOPRIGHT", justify == "LEFT" and 62 or -62, -10)
        box.name:SetText(name)
        box.name:SetTextColor(r + 0.2, g + 0.2, b + 0.2, 1)
        box.mvp = W.Text(box, "GameFontHighlightSmall", justify)
        box.mvp:SetPoint(justify == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", justify == "LEFT" and 62 or -62, 10)
        return box
    end
    self.horde = Side("LEFT", 10, HORDE[1], HORDE[2], HORDE[3], "THE HORDE", "Interface\\Icons\\INV_BannerPVP_01", "LEFT")
    self.alliance = Side("RIGHT", -10, ALLIANCE[1], ALLIANCE[2], ALLIANCE[3], "THE ALLIANCE", "Interface\\Icons\\INV_BannerPVP_02", "RIGHT")
    self.scoreLabel = W.Text(banner, "GameFontDisableSmall", "CENTER")
    self.scoreLabel:SetPoint("TOP", 0, -16)
    self.scoreLabel:SetText("CATEGORIES LED")
    self.score = W.Text(banner, "GameFontNormalHuge", "CENTER")
    self.score:SetPoint("TOP", self.scoreLabel, "BOTTOM", 0, -6)

    -- Outside Retail a guild is always one faction: point people to Network / Accounts.
    self.notice = W.Box(f, "accent")
    self.notice:SetPoint("TOPLEFT", 14, -40)
    self.notice:SetPoint("TOPRIGHT", -14, -40)
    self.notice:SetHeight(110)
    self.notice:SetFrameLevel(f:GetFrameLevel() + 40)
    self.notice.text = W.Text(self.notice, "GameFontHighlight", "CENTER")
    self.notice.text:SetPoint("TOP", 0, -20)
    self.notice.text:SetWidth(900)
    self.notice.text:SetWordWrap(true)
    self.notice.button = W.Button(self.notice, "Show Network", 160, 24, function() UI:SetScope("network") end)
    self.notice.button:SetPoint("BOTTOM", -86, 16)
    self.notice.button2 = W.Button(self.notice, "Show Accounts", 160, 24, function() UI:SetScope("netaccs") end)
    self.notice.button2:SetPoint("BOTTOM", 86, 16)
    self.notice:Hide()

    self.rows = {}
    local colW = (1010 - 28 - 12) / 2
    for i, cat in ipairs(CATEGORIES) do
        local col, rowIndex = (i - 1) % 2, math.floor((i - 1) / 2)
        local row = W.Box(f, "card")
        row:SetSize(colW, 78)
        row:SetPoint("TOPLEFT", 14 + col * (colW + 12), -134 - rowIndex * 86)
        row.title = W.Text(row, "GameFontNormal", "CENTER")
        row.title:SetPoint("TOP", 0, -8)
        row.title:SetText(cat.title)
        local bar = CreateFrame("Frame", nil, row)
        bar:SetPoint("TOPLEFT", 12, -28)
        bar:SetPoint("TOPRIGHT", -12, -28)
        bar:SetHeight(22)
        row.hBar = bar:CreateTexture(nil, "ARTWORK")
        row.hBar:SetPoint("TOPLEFT")
        row.hBar:SetPoint("BOTTOMLEFT")
        row.hBar:SetColorTexture(HORDE[1], HORDE[2], HORDE[3], 0.95)
        row.aBar = bar:CreateTexture(nil, "ARTWORK")
        row.aBar:SetPoint("TOPRIGHT")
        row.aBar:SetPoint("BOTTOMRIGHT")
        row.aBar:SetColorTexture(ALLIANCE[1], ALLIANCE[2], ALLIANCE[3], 0.95)
        row.hText = W.Text(bar, "GameFontHighlightSmall")
        row.hText:SetPoint("LEFT", 6, 0)
        row.aText = W.Text(bar, "GameFontHighlightSmall", "RIGHT")
        row.aText:SetPoint("RIGHT", -6, 0)
        row.barWidth = colW - 24
        row.verdictH = W.Text(row, "GameFontNormalSmall")
        row.verdictH:SetPoint("BOTTOMLEFT", 12, 8)
        row.verdictA = W.Text(row, "GameFontNormalSmall", "RIGHT")
        row.verdictA:SetPoint("BOTTOMRIGHT", -12, 8)
        self.rows[i] = row
    end
end

local function Aggregate(chars, cat)
    local out = { Horde = { sum = 0, count = 0 }, Alliance = { sum = 0, count = 0 } }
    if cat.mode == "account" then
        local best = { Horde = {}, Alliance = {} }
        for _, c in ipairs(chars) do
            local side = c.faction == "Alliance" and "Alliance" or "Horde"
            local owner = c.owner or c.fullName
            best[side][owner] = math.max(best[side][owner] or 0, FS:GetValue(c, cat.key))
        end
        for side, owners in pairs(best) do
            for _, v in pairs(owners) do out[side].sum = out[side].sum + v; out[side].count = out[side].count + 1 end
        end
        return out
    end
    local pool = chars
    if cat.mode == "avgTop" then
        local top = 0
        for _, c in ipairs(chars) do top = math.max(top, tonumber(c.level) or 0) end
        pool = {}
        for _, c in ipairs(chars) do if (tonumber(c.level) or 0) >= top then table.insert(pool, c) end end
    end
    for _, c in ipairs(pool) do
        local side = c.faction == "Alliance" and "Alliance" or "Horde"
        out[side].sum = out[side].sum + FS:GetValue(c, cat.key)
        out[side].count = out[side].count + 1
    end
    if cat.mode == "avgTop" then
        for _, s in pairs(out) do s.sum = s.count > 0 and (s.sum / s.count) or 0 end
    end
    return out
end

function FactionWar:Refresh()
    if not self.frame then return end
    local chars = FS:GetScopeCharacters(UI.currentScope)
    self.title:SetText("Faction War: Horde vs Alliance  -  " .. UI.SCOPE_TITLES[UI.currentScope] .. (FS:IsWeekMode() and " (This Week)" or ""))

    local singleFaction = FS.GAME ~= "retail" and (UI.currentScope == "solo" or UI.currentScope == "guild")
    self.notice:SetShown(singleFaction)
    if singleFaction then
        self.notice.text:SetText("In " .. FS.GAME_INFO.name .. " a guild is always one faction, so there is no war to show here.\n"
            .. "Faction War compares everyone you know through Battle.net friends and bridging - switch to Network or Accounts.")
    end

    -- MVP: the character who leads the most categories for their faction
    -- (not just the best geared one, so non-raiders can be MVP too).
    local mvp, leads = {}, {}
    for _, cat in ipairs(CATEGORIES) do
        if not cat.lower then
            local best = {}
            for _, c in ipairs(chars) do
                local side = c.faction == "Alliance" and "Alliance" or "Horde"
                local v = FS:GetValue(c, cat.key)
                if v > 0 and (not best[side] or v > best[side].v) then best[side] = { c = c, v = v } end
            end
            for _, b in pairs(best) do leads[b.c] = (leads[b.c] or 0) + 1 end
        end
    end
    for c, n in pairs(leads) do
        local side = c.faction == "Alliance" and "Alliance" or "Horde"
        if not mvp[side] or n > mvp[side].n or (n == mvp[side].n and tostring(c.fullName) < tostring(mvp[side].c.fullName)) then
            mvp[side] = { c = c, n = n }
        end
    end
    local function MvpText(side, label)
        local m = mvp[side]
        if not m then return "No " .. label .. " characters in view" end
        return string.format("MVP: %s (leads %d categor%s)", W.CharName(m.c), m.n, m.n == 1 and "y" or "ies")
    end
    self.horde.mvp:SetText(MvpText("Horde", "Horde"))
    self.alliance.mvp:SetText(MvpText("Alliance", "Alliance"))

    local hordeWins, allianceWins = 0, 0
    for i, cat in ipairs(CATEGORIES) do
        local row, agg = self.rows[i], Aggregate(chars, cat)
        local h, a = agg.Horde.sum, agg.Alliance.sum
        local total = h + a
        local hPct = total > 0 and h / total or 0.5
        row.hBar:SetWidth(math.max(1, row.barWidth * hPct))
        row.aBar:SetWidth(math.max(1, row.barWidth * (1 - hPct)))
        local def = FS.STATS[cat.key]
        local fmt = function(v) return cat.mode == "avgTop" and W.Num(v) or (def and def.fmt == "duration" and W.Duration(v)) or W.Short(v) end
        if def and def.fmt == "money" then fmt = function(v) return W.Num(math.floor(v / 10000)) .. "g" end end
        row.hText:SetText(string.format("%d%% (%s)", math.floor(hPct * 100 + 0.5), fmt(h)))
        row.aText:SetText(string.format("(%s) %d%%", fmt(a), math.floor((1 - hPct) * 100 + 0.5)))
        W.AccentText(row.title)

        local hordeBetter
        if h == a then hordeBetter = nil elseif cat.lower then hordeBetter = h < a else hordeBetter = h > a end
        if hordeBetter == true then
            hordeWins = hordeWins + 1
            row.verdictH:SetText(W.Color(cat.lower and "HORDE SURVIVES BETTER" or "HORDE LEADS", "ff5555"))
            row.verdictA:SetText(W.Color("ALLIANCE", "5599ff"))
        elseif hordeBetter == false then
            allianceWins = allianceWins + 1
            row.verdictH:SetText(W.Color("HORDE", "ff5555"))
            row.verdictA:SetText(W.Color(cat.lower and "ALLIANCE SURVIVES BETTER" or "ALLIANCE LEADS", "5599ff"))
        else
            row.verdictH:SetText(W.Color("TIED", "aaaaaa"))
            row.verdictA:SetText("")
        end
    end
    self.score:SetText(W.Color(hordeWins, "ff4444") .. "  -  " .. W.Color(allianceWins, "3399ff"))
end

function FactionWar:ShareText()
    if not self.score then return nil end
    local hm = self.horde and self.horde.mvp and W.Plain(self.horde.mvp:GetText() or "") or ""
    local am = self.alliance and self.alliance.mvp and W.Plain(self.alliance.mvp:GetText() or "") or ""
    return string.format("Faction War - Horde %s Alliance (categories led). Horde %s / Alliance %s",
        W.Plain(self.score:GetText() or "?"), hm, am)
end
