local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Chronicle = FS.Chronicle
local UI, W = FS.UI, FS.W

-- The Legacy Race only exists on WoW: Forever, so Retail doesn't get that tab.
local TABS = { { id = "firsts", label = "Guild Firsts" }, { id = "speedrun", label = "Speedrun" } }
if FS.IS_FOREVER then table.insert(TABS, { id = "race", label = "Legacy Race" }) end
table.insert(TABS, { id = "weekly", label = "Weekly Chronicle" })
table.insert(TABS, { id = "memorial", label = "Hardcore Memorial" })
-- WoW: Forever's Legacy challenges: every class to 25/45/60 and the six
-- crafting professions to 150/225/300.
local RACE_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RACE_PROFS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" }
local WEEKLY_AWARDS = {
    { "Slayer of the Week", "kills" }, { "Most Deaths", "deaths" }, { "Quest Master", "quests" },
    { "Treasure Hunter", "goldLooted" }, { "Kangaroo of the Week", "jumps" }, { "Chatterbox", "chat" },
    { "AFK Champion", "afk" }, { "Critter Menace", "critters" }, { "Frequent Flyer", "flightTime" },
    { "Globetrotter", "travelTotal" },
    { "Duelist", "duelsWon" }, { "Epic Hauler", "epics" }, { "Busiest Crafter", "crafted" },
    { "Boss Slayer", "bossKills" }, { "Wipe Lord", "wipes" },
    { "Corpse Runner", "corpseRuns" }, { "Explorer", "areasDiscovered" }, { "Chug Champion", "potions" },
    { "Night Owl", "nightTime" }, { "Social Butterfly", "whispersSent" }, { "Hearth Hopper", "hearths" },
}

local function Safe(fn, ...) return FS.Tracker.Safe(fn, ...) end

function Chronicle:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.current = "firsts"
    self.tabs = W.SubTabs(f, TABS, 980, function(id) self.current = id; self:Refresh() end)
    self.tabs:SetPoint("TOPLEFT", 14, -10)
    self.title = W.Text(f, "GameFontNormalLarge")
    self.title:SetPoint("TOPLEFT", 14, -46)
    self.sub = W.Text(f, "GameFontDisableSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
    self.sub:SetWidth(760)

    local open = function(rec) UI:OpenInspector(rec) end
    self.lists = {
        firsts = W.List(f, {
            { label = "Feat", width = 330 }, { label = "First", width = 260 },
            { label = "When", width = 120 }, { label = "Runner-up", width = 220 },
        }, { onClick = open, emptyText = "No dated firsts yet. Firsts are recorded from the moment FellowshipSync is installed (and from Legacy Challenge dates in WoW: Forever)." }),
        race = W.List(f, {
            { label = "Challenge", width = 150 }, { label = "Lvl 25 / Skill 150", width = 175 },
            { label = "Lvl 45 / Skill 225", width = 175 }, { label = "Lvl 60 / Skill 300", width = 175 },
            { label = "Closest to the next step", width = 250 },
        }, { noTooltip = true }),
        speedrun = W.List(f, (function()
            local cols = { { label = "#", width = 36 }, { label = "Character", width = 200 } }
            for _, lvl in ipairs(FS.GAME_INFO.splits) do
                table.insert(cols, { label = "Lvl " .. lvl, width = 88, justify = "RIGHT" })
            end
            table.insert(cols, { label = "Now", width = 120, justify = "RIGHT" })
            return cols
        end)(), { onClick = open, emptyText = "No levelling times yet. Level-ups are timed in played time from the moment FellowshipSync is installed." }),
        weekly = W.List(f, {
            { label = "Award", width = 200 }, { label = "Winner", width = 330 },
            { label = "This Week", width = 150, justify = "RIGHT" }, { label = "Runner-up", width = 250 },
        }, { onClick = open, emptyText = "Nothing has happened this week yet." }),
    }
    for _, l in pairs(self.lists) do
        l.frame:SetPoint("TOPLEFT", 14, -84)
        l.frame:SetPoint("BOTTOMRIGHT", -12, 10)
    end

    self.postBtn = W.Button(f, "Post to Guild Chat", 150, 22, function() self:PostWeekly() end)
    self.postBtn:SetPoint("TOPRIGHT", -36, -46)
    self.exportBtn = W.Button(f, "Export for Discord", 150, 22, function() self:ShowExport() end)
    self.exportBtn:SetPoint("RIGHT", self.postBtn, "LEFT", -6, 0)
    self.chooseBtn = W.Button(f, "Choose Lines", 120, 22, function() self.choosePanel:SetShown(not self.choosePanel:IsShown()); self:Refresh() end)
    self.chooseBtn:SetPoint("RIGHT", self.exportBtn, "LEFT", -6, 0)
    self:BuildChooser(f)
    self:BuildExport(f)

    self.memScroll, self.memContent = W.ScrollArea(f)
    self.memScroll:SetPoint("TOPLEFT", 14, -84)
    self.memScroll:SetPoint("BOTTOMRIGHT", -36, 10)
    self.stones = {}
    self.memEmpty = W.Text(f, "GameFontDisable", "CENTER")
    self.memEmpty:SetPoint("CENTER")
    self.memEmpty:SetText("No fallen heroes. Hardcore characters are remembered here after their final death.")
end

function Chronicle:Refresh()
    if not self.frame then return end
    self.tabs:Select(self.current, true)
    if self.current == "race" and not FS.IS_FOREVER then self.current = "firsts"; self.tabs:Select("firsts", true) end
    for id, l in pairs(self.lists) do l.frame:SetShown(id == self.current) end
    local memorial = self.current == "memorial"
    self.memScroll:SetShown(memorial)
    self.memEmpty:Hide()
    local weekly = self.current == "weekly"
    for _, b in ipairs({ self.postBtn, self.exportBtn, self.chooseBtn }) do b:SetShown(weekly) end
    if not weekly then self.choosePanel:Hide(); self.exportFrame:Hide() end
    local scope = UI.SCOPE_TITLES[UI.currentScope]
    if self.current == "firsts" then
        self.title:SetText("Guild Firsts  -  " .. scope)
        self.sub:SetText("Who did it first. Records are permanent and dated; feats from before FellowshipSync was installed have no date and are not counted.")
        self:RefreshFirsts()
    elseif self.current == "speedrun" then
        self.title:SetText("Levelling Speedrun  -  " .. scope)
        self.sub:SetText("Played time when each level was reached. Fastest to max level first; levels reached before installing show as -.")
        self:RefreshSpeedrun()
    elseif self.current == "race" then
        self.title:SetText("Legacy Race  -  " .. scope)
        self.sub:SetText("The WoW: Forever Legacy challenges: how many players have done each step, who was first, and who is closest to the next one.")
        self:RefreshRace()
    elseif self.current == "weekly" then
        self.title:SetText("Weekly Chronicle  -  from " .. date("%a %d.%m", math.max(0, FS:WeekStart())))
        self.sub:SetText("This week's champions, records and casualties. Resets with the weekly server reset.")
        self:RefreshWeekly()
    else
        self.title:SetText("Hardcore Memorial  -  " .. scope)
        self:RefreshMemorial()
    end
end

---------------------------------------------------------------------------
-- 2. Guild Firsts
---------------------------------------------------------------------------

local function FeatLabel(key)
    local kind, rest = key:match("^(%w+):(.+)$")
    local lvl = tonumber(key:match("^lv(%d+)$"))
    if lvl then return "First to reach level " .. lvl, 1 end
    if kind == "classmax" then return "First " .. W.ClassName(rest) .. " to level " .. FS:MaxLevel(), 2 end
    if kind == "boss" then return "First to defeat " .. W.Color(rest, "ff8000"), 3 end
    if kind == "prof" then
        local prof, rank = rest:match("^(.+):(%d+)$")
        if tonumber(rank) == FS.ProfMax() then return "First to master " .. prof .. " (" .. rank .. ")", 4 end
        return nil
    end
    if kind == "lg" then
        local _, name = Safe(GetAchievementInfo, tonumber(rest))
        return "First to complete " .. W.Color(name or (FS.POINTS.item .. " #" .. rest), "00e6ff"), 5
    end
end

function Chronicle:RefreshFirsts()
    local chars = FS:GetScopeCharacters(UI.currentScope)
    local feats = {}
    local function add(key, rec, t)
        feats[key] = feats[key] or {}
        table.insert(feats[key], { rec = rec, t = t })
    end
    local mobFirst = {} -- enemy -> earliest { rec, t }
    for _, rec in ipairs(chars) do
        for key, t in pairs(rec.firsts or {}) do
            if (tonumber(t) or 0) > 0 then
                add(key, rec, t)
                if key == "lv" .. FS:MaxLevel() and rec.cls then add("classmax:" .. rec.cls, rec, t) end
            end
        end
        for mob, t in pairs(rec.mobFirst or {}) do
            t = tonumber(t) or 0
            if t > 0 and (not mobFirst[mob] or t < mobFirst[mob].t) then mobFirst[mob] = { rec = rec, t = t } end
        end
    end

    local rows = {}
    for key, list in pairs(feats) do
        local label, order = FeatLabel(key)
        if label then
            table.sort(list, function(a, b) return a.t < b.t end)
            local first, second = list[1], list[2]
            table.insert(rows, { order = order, t = first.t, rec = first.rec, isSelf = first.rec.isMyChar,
                cells = { label, W.Label(first.rec), W.Color(W.Date(first.t), "aaaaaa"),
                          second and (W.CharName(second.rec) .. W.Color(" (" .. date("%d.%m", second.t) .. ")", "888888")) or W.Color("-", "666666") } })
        end
    end
    table.sort(rows, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.t < b.t end)

    -- Bestiary pioneers: who discovered the most enemy types first.
    local pioneers = {}
    for _, d in pairs(mobFirst) do pioneers[d.rec] = (pioneers[d.rec] or 0) + 1 end
    local plist = {}
    for rec, n in pairs(pioneers) do table.insert(plist, { rec = rec, n = n }) end
    table.sort(plist, function(a, b) return a.n > b.n end)
    for i = 1, math.min(5, #plist) do
        local pnr = plist[i]
        table.insert(rows, { rec = pnr.rec, isSelf = pnr.rec.isMyChar,
            cells = { "Bestiary pioneer #" .. i, W.Label(pnr.rec), W.Color(W.Num(pnr.n) .. " enemy types", "ffd100"), "" } })
    end
    self.lists.firsts:SetRows(rows)
end

---------------------------------------------------------------------------
-- Speedrun: played time per level
---------------------------------------------------------------------------

function Chronicle:RefreshSpeedrun()
    local maxLevel = FS:MaxLevel()
    local recs = {}
    for _, rec in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        if rec.levelTimes and next(rec.levelTimes) then table.insert(recs, rec) end
    end
    local function Finish(r) return tonumber(r.levelTimes[maxLevel]) end
    table.sort(recs, function(a, b)
        local fa, fb = Finish(a), Finish(b)
        if fa and fb then return fa < fb end
        if fa or fb then return fa ~= nil end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return tostring(a.fullName) < tostring(b.fullName)
    end)
    local rows = {}
    for i, r in ipairs(recs) do
        local cells = { Finish(r) and W.Rank(i) or W.Color("-", "666666"), W.Label(r) }
        for _, lvl in ipairs(FS.GAME_INFO.splits) do
            local t = tonumber(r.levelTimes[lvl])
            local text = t and t > 0 and W.Duration(t) or W.Color("-", "555555")
            if lvl == maxLevel and t and t > 0 then text = W.RankValue(i, text) end
            table.insert(cells, text)
        end
        local now = (tonumber(r.level) or 0) >= maxLevel and W.Color("Max level", "1eff00")
            or string.format("Lvl %s  %s", tostring(r.level or "?"), W.Color(W.Duration(r.playtime), "aaaaaa"))
        table.insert(cells, now)
        rows[i] = { rec = r, isSelf = r.isMyChar and UI.currentScope ~= "solo", cells = cells }
    end
    self.lists.speedrun:SetRows(rows)
end

---------------------------------------------------------------------------
-- 3. Legacy Race
---------------------------------------------------------------------------

local function RaceCell(done, first, solo, closestText)
    if solo then return done > 0 and W.Color("Done", "1eff00") or (closestText or W.Color("-", "666666")) end
    if done == 0 then return W.Color("nobody yet", "666666") end
    local text = W.Color(done .. (done == 1 and " player" or " players"), "ffffff")
    if first then text = text .. W.Color("  1st: " .. first, "ffd100") end
    return text
end

function Chronicle:RefreshRace()
    local chars = FS:GetScopeCharacters(UI.currentScope)
    local solo = UI.currentScope == "solo"
    local rows = {}

    local function Row(label, steps, value, stampKey, maxValue)
        local cells = { label }
        local closest
        for i, th in ipairs(steps) do
            local owners, firstT, firstOwner = {}, nil, nil
            for _, rec in ipairs(chars) do
                local v = value(rec)
                if v and v >= th then
                    owners[rec.owner or rec.fullName] = true
                    local t = tonumber(rec.firsts and rec.firsts[stampKey(th)]) or 0
                    if t > 0 and (not firstT or t < firstT) then firstT, firstOwner = t, rec.owner or FS.ShortName(rec.fullName) end
                end
            end
            local done = 0
            for _ in pairs(owners) do done = done + 1 end
            cells[i + 1] = RaceCell(done, firstOwner, solo)
        end
        -- Closest: the highest value still below the top step.
        for _, rec in ipairs(chars) do
            local v = value(rec)
            if v and v < maxValue and (not closest or v > closest.v) then closest = { rec = rec, v = v } end
        end
        if closest then
            local nextStep = maxValue
            for _, th in ipairs(steps) do if closest.v < th then nextStep = th break end end
            cells[5] = string.format("%s  %s", W.CharName(closest.rec), W.Color(closest.v .. " / " .. nextStep, "aaaaaa"))
        else
            cells[5] = W.Color("-", "666666")
        end
        table.insert(rows, { cells = cells })
    end

    for _, cls in ipairs(RACE_CLASSES) do
        Row(W.Color(W.ClassName(cls), W.ClassHex(cls)), { 25, 45, 60 },
            function(rec) return rec.cls == cls and tonumber(rec.level) or nil end,
            function(th) return "lv" .. th end, 60)
    end
    for _, prof in ipairs(RACE_PROFS) do
        Row(prof, { 150, 225, 300 }, function(rec)
            for _, p in ipairs(rec.profs or {}) do if p.name == prof then return tonumber(p.rank) end end
        end, function(th) return "prof:" .. prof .. ":" .. th end, 300)
    end
    self.lists.race:SetRows(rows)
end

---------------------------------------------------------------------------
-- 4. Weekly Chronicle
---------------------------------------------------------------------------

function Chronicle:BuildWeekly()
    local chars = FS:GetScopeCharacters(UI.currentScope)
    local weekStart = FS:WeekStart()
    local lines = {}
    for _, award in ipairs(WEEKLY_AWARDS) do
        local key = award[2]
        local sorted = {}
        for _, rec in ipairs(chars) do
            if FS:GetValue(rec, key, "week") > 0 then table.insert(sorted, rec) end
        end
        table.sort(sorted, function(a, b) return FS:GetValue(a, key, "week") > FS:GetValue(b, key, "week") end)
        if sorted[1] then
            local value = W.FormatStat(key, FS:GetValue(sorted[1], key, "week"))
            table.insert(lines, { award = award[1], rec = sorted[1], value = value, runner = sorted[2],
                                  runnerValue = sorted[2] and W.FormatStat(key, FS:GetValue(sorted[2], key, "week")) })
        end
    end

    -- Deaths and the best last words of the week
    local deaths, best = 0, nil
    for _, rec in ipairs(chars) do
        for _, d in ipairs(rec.deathLog or {}) do
            if (d.t or 0) >= weekStart then
                deaths = deaths + 1
                if d.words and (not best or #d.words > #best.words) then best = { rec = rec, words = d.words } end
            end
        end
    end
    if deaths > 0 then
        table.insert(lines, { award = "Casualties", text = W.Num(deaths) .. " deaths this week", value = "" })
    end
    if best then
        table.insert(lines, { award = "Last Words of the Week", rec = best.rec, value = "", note = '"' .. best.words .. '"' })
    end

    -- Records, bosses, discoveries
    local gear, bestGear = 0, nil
    local events = FS:GetScopedEvents(UI.currentScope)
    local fallen = 0
    for _, ev in ipairs(events) do
        if ev.t >= weekStart then
            if ev.kind == "gear" then
                gear = gear + 1
                if not bestGear or (ev.v or 0) > (bestGear.v or 0) then bestGear = ev end
            elseif ev.kind == "fallen" then fallen = fallen + 1 end
        end
    end
    if bestGear then
        table.insert(lines, { award = "Gear Record", rec = FS.db.global.characters[bestGear.who], value = W.Num(bestGear.v) .. " GS",
                              note = gear > 1 and (gear .. " new records this week") or nil })
    end
    local bosses, discoveries = {}, {}
    local mobFirst = {}
    for _, rec in ipairs(chars) do
        for key, t in pairs(rec.firsts or {}) do
            local boss = key:match("^boss:(.+)$")
            if boss and (tonumber(t) or 0) >= weekStart then table.insert(bosses, boss) end
        end
        for mob, t in pairs(rec.mobFirst or {}) do
            t = tonumber(t) or 0
            if t > 0 and (not mobFirst[mob] or t < mobFirst[mob]) then mobFirst[mob] = t end
        end
    end
    for _, t in pairs(mobFirst) do if t >= weekStart then table.insert(discoveries, t) end end
    if #bosses > 0 then
        table.sort(bosses)
        table.insert(lines, { award = "Bosses Down", text = table.concat(bosses, ", "), value = W.Num(#bosses) })
    end
    if #discoveries > 0 then
        table.insert(lines, { award = "New Enemies Discovered", text = "Bestiary grew by " .. W.Num(#discoveries), value = "" })
    end
    if fallen > 0 then
        table.insert(lines, { award = "Fallen Heroes", text = W.Num(fallen) .. " Hardcore characters fell", value = "" })
    end
    return lines
end

function Chronicle:RefreshWeekly()
    for _, cb in ipairs(self.lineChecks or {}) do cb:SetChecked(self:IsPicked(cb.award)) end
    local rows = {}
    for _, line in ipairs(self:BuildWeekly()) do
        local winner = line.rec and W.Label(line.rec) or (line.text or "")
        if line.note then winner = winner .. "  " .. W.Color(line.note, "ffd100") end
        local picked = self:IsPicked(line.award)
        table.insert(rows, { rec = line.rec, isSelf = line.rec and line.rec.isMyChar,
            cells = { W.Color(line.award, picked and "ffd100" or "666666"), winner, line.value or "",
                      line.runner and (W.CharName(line.runner) .. W.Color(" (" .. line.runnerValue .. ")", "888888")) or "" } })
    end
    self.lists.weekly:SetRows(rows)
end

local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|", ""))
end

-- Every line the Chronicle can have, in order (used for the "Choose Lines" panel).
local SPECIAL_LINES = { "Casualties", "Last Words of the Week", "Gear Record", "Bosses Down", "New Enemies Discovered", "Fallen Heroes" }
function Chronicle:AllLineNames()
    local names = {}
    for _, a in ipairs(WEEKLY_AWARDS) do table.insert(names, a[1]) end
    for _, n in ipairs(SPECIAL_LINES) do table.insert(names, n) end
    return names
end

function Chronicle:IsPicked(award) return not FS.db.profile.chronicle.skip[award] end

function Chronicle:BuildChooser(f)
    local p = W.Box(f, "accent")
    p:SetPoint("TOPLEFT", 14, -78)
    p:SetPoint("TOPRIGHT", -14, -78)
    p:SetFrameLevel(f:GetFrameLevel() + 40)
    p:EnableMouse(true)
    p:Hide()
    local names = self:AllLineNames()
    p:SetHeight(40 + math.ceil(#names / 4) * 24)
    local head = W.Text(p, "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText("Lines to include when posting or exporting:")
    self.lineChecks = {}
    for i, name in ipairs(names) do
        local cb = W.Check(p, name, function(on)
            FS.db.profile.chronicle.skip[name] = (not on) or nil
            self:Refresh()
        end)
        cb:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 240, -32 - math.floor((i - 1) / 4) * 24)
        cb.award = name
        self.lineChecks[i] = cb
    end
    local all = W.Button(p, "All", 60, 20, function() wipe(FS.db.profile.chronicle.skip); self:Refresh() end)
    all:SetPoint("TOPRIGHT", -74, -8)
    local none = W.Button(p, "None", 60, 20, function()
        for _, n in ipairs(names) do FS.db.profile.chronicle.skip[n] = true end
        self:Refresh()
    end)
    none:SetPoint("TOPRIGHT", -8, -8)
    self.choosePanel = p
end

-- One plain sentence per Chronicle line (discord = with **bold** award names).
function Chronicle:LineText(line, discord)
    local award = discord and ("**" .. line.award .. ":** ") or (line.award .. ": ")
    local body
    if line.rec then
        body = FS.ShortName(line.rec.fullName)
        if line.value and line.value ~= "" then body = body .. (discord and " - " or " (") .. Plain(line.value) .. (discord and "" or ")") end
        if line.note then body = body .. " " .. Plain(line.note) end
        if discord and line.runner then
            body = body .. string.format(" (runner-up: %s, %s)", FS.ShortName(line.runner.fullName), Plain(line.runnerValue))
        end
    else
        body = Plain(line.text or "")
    end
    return award .. body
end

function Chronicle:PickedLines()
    local out = {}
    for _, line in ipairs(self:BuildWeekly()) do
        if self:IsPicked(line.award) then table.insert(out, line) end
    end
    return out
end

-- Posts the chosen lines to guild chat, one line per message (paced), after a confirmation click.
function Chronicle:PostWeekly()
    if not IsInGuild() then FS:Print("You are not in a guild.") return end
    local lines = self:PickedLines()
    if #lines == 0 then FS:Print("Nothing to post: choose at least one line (Choose Lines).") return end
    if not self.confirmPost then
        self.confirmPost = true
        self.postBtn.text:SetText(string.format("Post %d lines?", #lines + 1))
        FS:ScheduleTimer(function() self.confirmPost = false; self.postBtn.text:SetText("Post to Guild Chat") end, 5)
        return
    end
    self.confirmPost = false
    self.postBtn.text:SetText("Post to Guild Chat")
    local week = date("%A %d.%m", math.max(0, FS:WeekStart()))
    FS.Notify:Announce("[FellowshipSync] Weekly Chronicle - week starting " .. week, { "GUILD" }, 40)
    for _, line in ipairs(lines) do FS.Notify:Announce(self:LineText(line):sub(1, 255), { "GUILD" }, 40) end
end

-- Export window: copy the text for Discord (Ctrl+A, Ctrl+C).
function Chronicle:BuildExport(f)
    local e = W.Box(f, "accent")
    e:SetSize(640, 400)
    e:SetPoint("CENTER")
    e:SetFrameLevel(f:GetFrameLevel() + 60)
    e:EnableMouse(true)
    e:Hide()
    local title = W.Text(e, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Export for Discord")
    local hint = W.Text(e, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Press Ctrl+A then Ctrl+C to copy, and paste it into Discord.")
    local close = W.Button(e, "Close", 80, 22, function() e:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    local scroll = CreateFrame("ScrollFrame", nil, e, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(580)
    box:SetScript("OnEscapePressed", function() e:Hide() end)
    scroll:SetScrollChild(box)
    self.exportFrame, self.exportBox = e, box
end

function Chronicle:ExportText()
    local out = { string.format("**The Fellowship Chronicle** - week starting %s", date("%A %d.%m.%Y", math.max(0, FS:WeekStart()))), "" }
    for _, line in ipairs(self:PickedLines()) do table.insert(out, "- " .. self:LineText(line, true)) end
    table.insert(out, "")
    table.insert(out, "_Shared with FellowshipSync_")
    return table.concat(out, "\n")
end

function Chronicle:ShowExport()
    self.exportBox:SetText(self:ExportText())
    self.exportFrame:Show()
    self.exportBox:SetFocus()
    self.exportBox:HighlightText()
end

---------------------------------------------------------------------------
-- 5. Hardcore Memorial
---------------------------------------------------------------------------

function Chronicle:GetStone(i)
    if self.stones[i] then return self.stones[i] end
    local s = CreateFrame("Button", nil, self.memContent, "BackdropTemplate")
    s:SetBackdrop(W.SOFT)
    s:SetBackdropColor(0.13, 0.13, 0.14, 0.95)
    s:SetBackdropBorderColor(0.45, 0.45, 0.48, 1)
    s:SetHeight(84)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(48, 48)
    s.icon:SetPoint("LEFT", 14, 0)
    s.icon:SetTexture("Interface\\Icons\\Spell_Holy_GuardianSpirit")
    s.icon:SetDesaturated(true)
    s.name = W.Text(s, "GameFontNormalLarge")
    s.name:SetPoint("TOPLEFT", s.icon, "TOPRIGHT", 14, 2)
    s.date = W.Text(s, "GameFontDisableSmall", "RIGHT")
    s.date:SetPoint("TOPRIGHT", -14, -12)
    s.line = W.Text(s, "GameFontHighlight")
    s.line:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -5)
    s.line:SetPoint("RIGHT", s, "RIGHT", -14, 0)
    s.words = W.Text(s, "GameFontNormalSmall")
    s.words:SetPoint("TOPLEFT", s.line, "BOTTOMLEFT", 0, -5)
    s.words:SetPoint("RIGHT", s, "RIGHT", -14, 0)
    s:SetScript("OnClick", function(self) if self.rec then UI:OpenInspector(self.rec) end end)
    self.stones[i] = s
    return s
end

function Chronicle:RefreshMemorial()
    local fallen = {}
    for _, rec in ipairs(FS:GetScopeCharacters(UI.currentScope)) do
        local hc = rec.hc
        -- Older data: a Hardcore character with a death but no memorial entry yet.
        if not hc and tostring(rec.ruleset or ""):match("%-HC$") and rec.deathLog and #rec.deathLog > 0 then
            hc = rec.deathLog[#rec.deathLog]
        end
        if hc then table.insert(fallen, { rec = rec, hc = hc }) end
    end
    table.sort(fallen, function(a, b) return (a.hc.t or 0) > (b.hc.t or 0) end)

    local levels, lived = 0, 0
    for _, f in ipairs(fallen) do levels = levels + (tonumber(f.hc.lvl) or 0); lived = lived + (tonumber(f.hc.played) or 0) end
    if #fallen > 0 then
        self.sub:SetText(string.format("%d fallen heroes  -  average level %.1f  -  %s lived together. Click a stone to remember them.",
            #fallen, levels / #fallen, W.Duration(lived)))
    else
        self.sub:SetText("Hardcore characters are remembered here after their final death (ruleset HC, auto-detected or set in Options).")
    end

    local width = math.max(600, self.memScroll:GetWidth() or 960)
    self.memContent:SetWidth(width)
    for i, f in ipairs(fallen) do
        local s, rec, hc = self:GetStone(i), f.rec, f.hc
        s.rec = rec
        s:SetWidth(width)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 0, -(i - 1) * 92)
        s.name:SetText("Here lies " .. W.CharName(rec) .. W.Color(string.format("  level %s %s %s", tostring(hc.lvl or rec.level or "?"),
            rec.race or "", W.ClassName(rec.cls)), "aaaaaa") .. W.Badge(rec, true))
        s.date:SetText(W.Date(hc.t))
        local killer = W.Color(hc.killer or "Unknown", "ff6060")
        if hc.kdesc and hc.kdesc ~= "" then killer = killer .. W.Color(" (" .. hc.kdesc .. ")", "aaaaaa") end
        s.line:SetText(string.format("Fell in %s to %s%s.", (hc.zone and hc.zone ~= "") and hc.zone or "an unknown place", killer,
            hc.played and hc.played > 0 and ("  Lived " .. W.Duration(hc.played)) or ""))
        s.words:SetText(hc.words and W.Color('Last words: "' .. hc.words .. '"', "ffd100") or W.Color("They left no last words.", "777777"))
        s:Show()
    end
    for i = #fallen + 1, #self.stones do self.stones[i]:Hide() end
    self.memContent:SetHeight(math.max(10, #fallen * 92))
    self.memEmpty:SetShown(#fallen == 0)
end
