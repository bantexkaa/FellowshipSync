local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Deathmap = FS.Deathmap
local W = FS.W

---------------------------------------------------------------------------
-- Deathmap: skulls and "hot zones" on the world map for recorded deaths.
-- Everything is adjustable in Options > Fellowship: whose deaths, skull size,
-- how many, time window, skulls / hot zones / both, hot-zone grid, Hardcore only,
-- and highlighting your own deaths. Positions exist for open-world deaths only.
---------------------------------------------------------------------------

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GRID = { fine = 40, medium = 20, coarse = 10 }

local function Settings() return FS.db.profile.deathmap end

function Deathmap:Enable()
    self.pins, self.zones = {}, {}
    -- Preferred: HereBeDragons places pins through the map's own pin system in every game version.
    self.hbd = LibStub("HereBeDragons-Pins-2.0", true)
    if not WorldMapFrame then return end
    WorldMapFrame:HookScript("OnShow", function() self:Refresh() end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() self:Refresh() end) end
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() self:Rescale() end) end
end

-- Deaths with map positions that pass the player's filters, newest first.
function Deathmap:Deaths(mapID, scope)
    local d = Settings()
    local since = (tonumber(d.days) or 0) > 0 and (time() - d.days * 86400) or 0
    local out = {}
    for _, rec in ipairs(FS:GetScopeCharacters(scope or d.scope or "guild")) do
        local hcT = rec.hc and rec.hc.t
        local seen = false
        for _, death in ipairs(rec.deathLog or {}) do
            if death.t == hcT then seen = true end
            if death.map and death.x and death.y and (not mapID or death.map == mapID) and (death.t or 0) >= since then
                local final = (death.t == hcT)
                if not d.hcOnly or final then table.insert(out, { rec = rec, d = death, final = final }) end
            end
        end
        local hc = rec.hc
        if hc and not seen and hc.map and hc.x and (not mapID or hc.map == mapID) and (hc.t or 0) >= since then
            table.insert(out, { rec = rec, d = hc, final = true })
        end
    end
    table.sort(out, function(a, b) return (a.d.t or 0) > (b.d.t or 0) end)
    return out
end

-- Groups deaths into grid cells per map: { map, x, y, count, killers, top }
function Deathmap:HotZones(deaths)
    local g = GRID[Settings().hotGrid or "medium"] or 20
    local cells, list = {}, {}
    for _, item in ipairs(deaths) do
        local d = item.d
        local cx, cy = math.floor(d.x * g), math.floor(d.y * g)
        local key = d.map .. ":" .. cx .. ":" .. cy
        local c = cells[key]
        if not c then
            c = { map = d.map, x = (cx + 0.5) / g, y = (cy + 0.5) / g, count = 0, killers = {}, zone = d.zone }
            cells[key] = c
            table.insert(list, c)
        end
        c.count = c.count + 1
        c.killers[d.killer or "Unknown"] = (c.killers[d.killer or "Unknown"] or 0) + 1
    end
    local most = 1
    for _, c in ipairs(list) do
        most = math.max(most, c.count)
        local n = 0
        for k, v in pairs(c.killers) do if v > n then c.top, n = k, v end end
    end
    for _, c in ipairs(list) do c.heat = c.count / most end
    return list
end

local function SkullTooltip(self)
    local item = self.item
    if not item then return end
    local d = item.d
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(W.CharName(item.rec) .. (item.final and W.Color("  (fell for good)", "ff5555") or ""))
    GameTooltip:AddLine("Killed by " .. tostring(d.killer or "Unknown") .. ((d.kdesc and d.kdesc ~= "") and (" (" .. d.kdesc .. ")") or ""), 1, 0.4, 0.4)
    GameTooltip:AddLine(W.Date(d.t) .. (d.lvl and ("  -  level " .. d.lvl) or ""), 0.8, 0.8, 0.8)
    if d.words then GameTooltip:AddLine('"' .. d.words .. '"', 1, 0.82, 0, true) end
    GameTooltip:Show()
end

local function ZoneTooltip(self)
    local z = self.zone
    if not z then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(W.Color("Hot zone", "ff5555") .. (z.zone and ("  -  " .. z.zone) or ""))
    GameTooltip:AddLine(string.format("%d death%s here", z.count, z.count == 1 and "" or "s"), 1, 1, 1)
    if z.top then GameTooltip:AddLine("Deadliest: " .. z.top, 1, 0.4, 0.4) end
    GameTooltip:Show()
end

function Deathmap:GetPin(i, parent)
    local pin = self.pins[i]
    if not pin then
        pin = CreateFrame("Button", nil, parent)
        pin.tex = pin:CreateTexture(nil, "OVERLAY")
        pin.tex:SetAllPoints()
        pin.tex:SetTexture(SKULL)
        pin:SetScript("OnEnter", SkullTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.pins[i] = pin
    end
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    return pin
end

function Deathmap:GetZone(i, parent)
    local z = self.zones[i]
    if not z then
        z = CreateFrame("Button", nil, parent)
        z.tex = z:CreateTexture(nil, "ARTWORK")
        z.tex:SetAllPoints()
        z.tex:SetTexture(CIRCLE)
        z:SetScript("OnEnter", ZoneTooltip)
        z:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.zones[i] = z
    end
    if z:GetParent() ~= parent then z:SetParent(parent) end
    return z
end

-- Colour and size for one skull / hot zone.
function Deathmap:StyleSkull(pin, item)
    local size = tonumber(Settings().size) or 14
    pin.baseSize = size
    pin:SetSize(size, size)
    if item.final then
        pin.tex:SetVertexColor(1, 0.2, 0.2)
    elseif Settings().highlightMine ~= false and item.rec.isMyChar then
        pin.tex:SetVertexColor(1, 0.82, 0)
    else
        pin.tex:SetVertexColor(0.9, 0.9, 0.9)
    end
end

function Deathmap:StyleZone(z, cell)
    local size = (tonumber(Settings().size) or 14) * (1.6 + cell.heat * 2.4)
    z.baseSize = size
    z:SetSize(size, size)
    z.tex:SetVertexColor(1, 0.85 - cell.heat * 0.75, 0.1, 0.25 + cell.heat * 0.35)
end

-- Everything to draw: skulls and/or hot zones, limited to the chosen maximum.
function Deathmap:Markers(mapID)
    local d = Settings()
    local deaths = self:Deaths(mapID)
    local mode = d.mode or "skulls"
    local skulls, zones = {}, {}
    if mode == "skulls" or mode == "both" then
        for i = 1, math.min(#deaths, tonumber(d.max) or 400) do skulls[i] = deaths[i] end
    end
    if mode == "hot" or mode == "both" then zones = self:HotZones(deaths) end
    return skulls, zones
end

function Deathmap:HideAll()
    for _, pin in ipairs(self.pins or {}) do pin:Hide() end
    for _, z in ipairs(self.zones or {}) do z:Hide() end
end

function Deathmap:RefreshHBD()
    self.hbd:RemoveAllWorldMapIcons(self)
    self:HideAll()
    if not Settings().worldMap then return end
    local skulls, zones = self:Markers(nil) -- every map: HereBeDragons shows each pin on its own map
    local flag = HBD_PINS_WORLDMAP_SHOW_HIDE or 0
    for i, cell in ipairs(zones) do
        local z = self:GetZone(i, UIParent)
        z.zone = cell
        self:StyleZone(z, cell)
        self.hbd:AddWorldMapIconMap(self, z, cell.map, cell.x, cell.y, flag)
    end
    for i, item in ipairs(skulls) do
        local pin = self:GetPin(i, UIParent)
        pin.item = item
        self:StyleSkull(pin, item)
        self.hbd:AddWorldMapIconMap(self, pin, item.d.map, item.d.x, item.d.y, flag)
    end
end

function Deathmap:Refresh()
    if not FS.db then return end
    if self.hbd then return self:RefreshHBD() end
    self:HideAll()
    if not Settings().worldMap or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local level = (canvas:GetFrameLevel() or 1) + 2000
    local skulls, zones = self:Markers(mapID)
    for i, cell in ipairs(zones) do
        local z = self:GetZone(i, canvas)
        z.zone = cell
        self:StyleZone(z, cell)
        z:SetFrameLevel(level)
        z:ClearAllPoints()
        z:SetPoint("CENTER", canvas, "TOPLEFT", cell.x * w, -cell.y * h)
        z:Show()
    end
    for i, item in ipairs(skulls) do
        local pin = self:GetPin(i, canvas)
        pin.item = item
        self:StyleSkull(pin, item)
        pin:SetFrameLevel(level + 1)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", item.d.x * w, -item.d.y * h)
        pin:Show()
    end
    self:Rescale()
end

-- Keep markers the same size on screen when the map is zoomed (HereBeDragons does this itself).
function Deathmap:Rescale()
    if self.hbd then return end
    local scale = (WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    for _, list in ipairs({ self.pins or {}, self.zones or {} }) do
        for _, f in ipairs(list) do
            local base = f.baseSize or 14
            f:SetSize(base / scale, base / scale)
        end
    end
end

-- Zones ranked by deaths (every recorded death, with or without a position).
function Deathmap:DangerZones(scope)
    local zones = {}
    for _, rec in ipairs(FS:GetScopeCharacters(scope)) do
        for _, d in ipairs(rec.deathLog or {}) do
            local name = (d.zone and d.zone ~= "") and d.zone or "Unknown"
            local z = zones[name] or { zone = name, deaths = 0, killers = {}, last = 0, mapped = 0 }
            z.deaths = z.deaths + 1
            z.killers[d.killer or "Unknown"] = (z.killers[d.killer or "Unknown"] or 0) + 1
            if (d.t or 0) > z.last then z.last, z.lastRec = d.t, rec end
            if d.map then z.mapped = z.mapped + 1 end
            zones[name] = z
        end
    end
    local list = {}
    for _, z in pairs(zones) do
        local top, n = nil, 0
        for k, v in pairs(z.killers) do if v > n then top, n = k, v end end
        z.topKiller, z.topKills = top, n
        table.insert(list, z)
    end
    table.sort(list, function(a, b) if a.deaths == b.deaths then return a.zone < b.zone end return a.deaths > b.deaths end)
    return list
end
