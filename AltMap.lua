local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local AltMap = FS.AltMap
local W = FS.W

---------------------------------------------------------------------------
-- Alt Map: your other characters on the world map, where you last played them.
-- Optional (off by default): share those parked positions with guildmates and
-- friends, and see the ones they share - only for characters on your own realm
-- (or a connected realm), so you only see characters you can actually meet.
-- Parked sharing only covers characters you are NOT playing. Where you are now
-- is only sent if you turn on live sharing (also off by default, see the end).
---------------------------------------------------------------------------

local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"
local SIZE = 20
local SHARED_MAX = 100              -- at most this many shared icons
local SHARED_MAX_AGE = 30 * 86400   -- shared positions older than this are ignored
local LIVE_SHARE_EVERY = 15         -- seconds between live position updates you send (only when you moved)
local LIVE_HEARTBEAT = 60           -- ...or at least this often while standing still
local PEER_TIMEOUT = 90             -- a friend's live icon disappears after this long without news
local PEER_MAX = 40

local function Settings() return FS.db.profile.altMap end

function AltMap:Enable()
    self.pins = {}
    self.hbd = LibStub("HereBeDragons-Pins-2.0", true)
    if not WorldMapFrame then return end
    WorldMapFrame:HookScript("OnShow", function() self:Refresh() end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() self:Refresh() end) end
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() self:Rescale(); self:UpdateLive(true); self:DrawTrail() end) end
    WorldMapFrame:HookScript("OnHide", function() self:StopLive() end)
    self:StartTrail()
    FS:ScheduleRepeatingTimer(function() self:ShareLiveTick() end, LIVE_SHARE_EVERY)
end

---------------------------------------------------------------------------
-- Realms: your realm plus its connected realms
---------------------------------------------------------------------------

local function Norm(realm) return (tostring(realm or ""):gsub("[%s%-']", ""):lower()) end

function AltMap:MyRealms()
    if self.realms then return self.realms end
    local set = { [Norm(GetRealmName and GetRealmName())] = true }
    if GetNormalizedRealmName then set[Norm(GetNormalizedRealmName())] = true end
    local connected = GetAutoCompleteRealms and { GetAutoCompleteRealms() }
    if connected and type(connected[1]) == "table" then connected = connected[1] end
    for _, r in ipairs(connected or {}) do if type(r) == "string" then set[Norm(r)] = true end end
    self.realms = set
    return set
end

-- "Kima-Test Realm" / "Kima Stormborn-Test Realm" -> "testrealm"
function AltMap.RealmOf(key) return Norm(tostring(key or ""):match("^[^%-]+%-(.+)$")) end

function AltMap:SameRealm(key) return self:MyRealms()[AltMap.RealmOf(key)] == true end

---------------------------------------------------------------------------
-- Which characters get an icon
---------------------------------------------------------------------------

local function ValidPos(p)
    return type(p) == "table" and tonumber(p.map) and tonumber(p.x) and tonumber(p.y)
        and p.x > 0 and p.x < 1 and p.y > 0 and p.y < 1
end

-- One identity per character, whatever spelling its key has: "Kima-Test Realm",
-- "Kima Stormborn-Test Realm" and "Kima-TestRealm" are the same character.
function AltMap.Identity(key, cls)
    key = tostring(key or "")
    local first = key:match("^([^%s%-]+)") or key
    return first:lower() .. "|" .. AltMap.RealmOf(key) .. "|" .. tostring(cls or "")
end

function AltMap:MyIdentity()
    local _, cls = UnitClass("player")
    return AltMap.Identity(FS:GetPlayerKey(), cls)
end

-- Keeps only the newest position per character.
local function AddNewest(list, index, id, item)
    local i = index[id]
    if not i then
        table.insert(list, item)
        index[id] = #list
    elseif (tonumber(item.pos.t) or 0) > (tonumber(list[i].pos.t) or 0) then
        list[i] = item
    end
end

function AltMap:Markers()
    local out = {}
    if not FS.db then return out end
    local set = Settings()
    local me, myId = FS:GetPlayerKey(), self:MyIdentity()
    local chars = FS.db.global.characters
    local index = {}
    if set.mine ~= false then
        for name, rec in pairs(chars) do
            if rec.isMyChar and (rec.game == nil or rec.game == FS.GAME) and ValidPos(rec.pos) then
                local id = AltMap.Identity(name, rec.cls)
                -- the character you're playing never has a parked icon
                if name ~= me and id ~= myId then
                    AddNewest(out, index, id, { rec = rec, pos = rec.pos, mine = true, id = id })
                end
            end
        end
    end
    if set.showShared then
        local shared, sIndex = {}, {}
        for name, rec in pairs(chars) do
            if not rec.isMyChar and ValidPos(rec.pos) and time() - (tonumber(rec.pos.t) or 0) < SHARED_MAX_AGE
                and (rec.isMock or self:SameRealm(name)) then
                local id = AltMap.Identity(name, rec.cls)
                if not index[id] and id ~= myId then AddNewest(shared, sIndex, id, { rec = rec, pos = rec.pos, id = id }) end
            end
        end
        table.sort(shared, function(a, b) return (a.pos.t or 0) > (b.pos.t or 0) end)
        for i = 1, math.min(#shared, SHARED_MAX) do table.insert(out, shared[i]) end
    end
    return out
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

local function PinTooltip(pin)
    local item = pin.item
    if not item then return end
    local rec, pos = item.rec, item.pos
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(W.CharName(rec))
    GameTooltip:AddLine(string.format("%s %s %s", W.T("Level"), tostring(rec.level or "?"), W.Plain(W.ClassName(rec.cls))), 1, 1, 1)
    if pos.zone and pos.zone ~= "" then GameTooltip:AddLine(pos.zone, 1, 0.82, 0) end
    GameTooltip:AddLine(string.format(W.T("Last played here %s"), W.Plain(W.Ago(pos.t))), 0.8, 0.8, 0.8)
    if not item.mine then GameTooltip:AddLine(string.format(W.T("Shared by %s"), tostring(rec.owner or "?")), 0.6, 0.8, 1) end
    GameTooltip:AddLine(W.T("Click to open their profile."), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function AltMap:GetPin(id, parent)
    local pin = self.pins[id]
    if not pin then
        pin = CreateFrame("Button", nil, parent)
        pin.ring = pin:CreateTexture(nil, "BACKGROUND")
        pin.ring:SetPoint("TOPLEFT", -2, 2)
        pin.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        pin.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        pin:SetScript("OnEnter", PinTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", function(p) if p.item and FS.Nav then FS.Nav:Character(p.item.rec.fullName) end end)
        self.pins[id] = pin
    end
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    return pin
end

function AltMap:Style(pin, item)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.rec.cls or ""]
    if coords then
        pin.tex:SetTexture(CLASS_ICONS)
        pin.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        pin.tex:SetTexture(FS.LOGO)
        pin.tex:SetTexCoord(0, 1, 0, 1)
    end
    -- your own characters get a gold ring, shared ones a blue ring
    if item.mine then pin.ring:SetVertexColor(1, 0.82, 0, 1) else pin.ring:SetVertexColor(0.35, 0.65, 1, 1) end
    pin.baseSize = SIZE
    pin:SetSize(SIZE, SIZE)
end

function AltMap:HideAll()
    for _, pin in pairs(self.pins or {}) do
        if self.hbd and self.hbd.RemoveWorldMapIcon then self.hbd:RemoveWorldMapIcon(self, pin) end
        pin:Hide()
    end
end

function AltMap:Refresh()
    if not FS.db or not self.pins then return end
    self.realms = nil
    self:StartLive()
    if self.hbd then
        self:HideAll()
        self.hbd:RemoveAllWorldMapIcons(self)
        -- shown on the zone map and on the continent map around it
        local flag = HBD_PINS_WORLDMAP_SHOW_CONTINENT or HBD_PINS_WORLDMAP_SHOW_HIDE or 0
        for _, item in ipairs(self:Markers()) do
            local pin = self:GetPin(item.id, UIParent)
            pin.item = item
            self:Style(pin, item)
            self.hbd:AddWorldMapIconMap(self, pin, item.pos.map, item.pos.x, item.pos.y, flag)
        end
        return
    end
    -- Without HereBeDragons: icons on the exact map only.
    self:HideAll()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local level = (canvas:GetFrameLevel() or 1) + 2100
    local n = 0
    for _, item in ipairs(self:Markers()) do
        if item.pos.map == mapID then
            n = n + 1
            local pin = self:GetPin(item.id, canvas)
            pin.item = item
            self:Style(pin, item)
            pin:SetFrameLevel(level)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", item.pos.x * w, -item.pos.y * h)
            pin:Show()
        end
    end
    self:Rescale()
end

function AltMap:Rescale()
    if self.hbd then return end
    local scale = (WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    for _, pin in pairs(self.pins or {}) do pin:SetSize(SIZE / scale, SIZE / scale) end
end

---------------------------------------------------------------------------
-- Live view: the character you are playing right now, updated while the map
-- is open. Only on your own map - never sent to anyone.
-- Off by default. With it: a trail behind you, and a coordinates bar.
---------------------------------------------------------------------------

local LIVE_SIZE = 24
local LIVE_EVERY = 0.2        -- seconds between live updates while the map is open
local TRAIL_EVERY = 0.5       -- seconds between trail checks
local TRAIL_STEP = 0.0015     -- minimum distance (map units) between trail points
local TRAIL_JUMP = 0.08       -- a bigger jump than this starts a new piece of line (hearth, portal)
local TRAIL_MAX = 2000

local function Ok(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- Where you are on a map (the best map for you if none given), or nil indoors.
function AltMap:PlayerPos(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    if not mapID then
        local okMap, best = pcall(C_Map.GetBestMapForUnit, "player")
        mapID = okMap and Ok(best) and best or nil
    end
    if not tonumber(mapID) then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not (okPos and pos and pos.GetXY) then return nil end
    local okXY, x, y = pcall(pos.GetXY, pos)
    if not (okXY and Ok(x) and Ok(y) and tonumber(x) and tonumber(y)) then return nil end
    if x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
    return mapID, x, y
end

local function Coord(v) return string.format("%.1f", v * 100) end

local function LiveTooltip(pin)
    local rec = FS.GetMyRecord and FS:GetMyRecord() or {}
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(W.T("You are here"), 0.3, 1, 0.4)
    GameTooltip:AddLine(W.CharName(rec))
    GameTooltip:AddLine(string.format("%s %s %s", W.T("Level"), tostring(UnitLevel("player") or "?"), W.Plain(W.ClassName(rec.cls))), 1, 1, 1)
    local zone, sub = GetRealZoneText and GetRealZoneText(), GetSubZoneText and GetSubZoneText()
    if Ok(zone) and zone ~= "" then
        if Ok(sub) and sub ~= "" and sub ~= zone then zone = zone .. " - " .. sub end
        GameTooltip:AddLine(zone, 1, 0.82, 0)
    end
    local live = AltMap.live
    if live then GameTooltip:AddLine(Coord(live.x) .. ", " .. Coord(live.y), 0.8, 0.8, 0.8) end
    local session = FS.db.char and FS.db.char.session
    if session and tonumber(session.start) then
        GameTooltip:AddLine(string.format(W.T("Playing for %s this session"), W.Plain(W.Duration(time() - session.start))), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(W.T("Click to open your profile."), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function AltMap:LivePin(parent)
    local pin = self.livePin
    if not pin then
        pin = CreateFrame("Button", nil, parent)
        pin.glow = pin:CreateTexture(nil, "BACKGROUND")
        pin.glow:SetPoint("TOPLEFT", -7, 7)
        pin.glow:SetPoint("BOTTOMRIGHT", 7, -7)
        pin.glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.glow:SetVertexColor(0.3, 1, 0.4, 0.35)
        pin.ring = pin:CreateTexture(nil, "BORDER")
        pin.ring:SetPoint("TOPLEFT", -3, 3)
        pin.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        pin.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.ring:SetVertexColor(0.3, 1, 0.4, 1)
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        -- a soft pulse, so "you" stands out from your parked alts
        if pin.CreateAnimationGroup then
            local ag = pin:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local a = ag:CreateAnimation("Alpha")
            a:SetTarget(pin.glow)
            a:SetFromAlpha(0.15)
            a:SetToAlpha(0.6)
            a:SetDuration(0.8)
            ag:Play()
            pin.pulse = ag
        end
        pin:SetScript("OnEnter", LiveTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", function() if FS.Nav then FS.Nav:Character(FS:GetPlayerKey()) end end)
        self.livePin = pin
    end
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    local _, cls = UnitClass("player")
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls or ""]
    if coords then
        pin.tex:SetTexture(CLASS_ICONS)
        pin.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        pin.tex:SetTexture(FS.LOGO)
        pin.tex:SetTexCoord(0, 1, 0, 1)
    end
    return pin
end

-- The updater only runs while the world map is open.
function AltMap:StartLive()
    if not self.liveFrame then
        self.liveFrame = CreateFrame("Frame")
        self.liveFrame:SetScript("OnUpdate", function(_, elapsed)
            self.liveWait = (self.liveWait or 0) - (elapsed or 0)
            if self.liveWait > 0 then return end
            self.liveWait = LIVE_EVERY
            self:UpdateLive()
            self:UpdateCoords()
            self.peerWait = (self.peerWait or 0) - LIVE_EVERY
            if self.peersDirty or self.peerWait <= 0 then self.peerWait = 2; self:DrawPeers() end
        end)
    end
    self.liveWait = 0
    if WorldMapFrame and WorldMapFrame:IsShown() then self.liveFrame:Show() else self.liveFrame:Hide() end
    self:UpdateLive(true)
    self:UpdateCoords()
    self:DrawPeers()
    self:DrawTrail()
end

function AltMap:StopLive()
    if self.liveFrame then self.liveFrame:Hide() end
end

function AltMap:HideLive()
    if self.livePin then
        if self.hbd and self.hbd.RemoveWorldMapIcon then self.hbd:RemoveWorldMapIcon(self.liveRef, self.livePin) end
        self.livePin:Hide()
    end
    self.live = nil
end

function AltMap:UpdateLive(force)
    if not FS.db then return end
    local set = Settings()
    self.liveRef = self.liveRef or {}
    if set.live ~= true then return self:HideLive() end
    local map, x, y = self:PlayerPos()
    if not map then return self:HideLive() end
    local last = self.live
    -- only move the pin when you actually moved (keeps the map smooth)
    if not force and last and last.map == map and math.abs(last.x - x) < 0.0003 and math.abs(last.y - y) < 0.0003 then return end
    self.live = { map = map, x = x, y = y }
    if self.hbd then
        local pin = self:LivePin(UIParent)
        pin:SetSize(LIVE_SIZE, LIVE_SIZE)
        if self.hbd.RemoveWorldMapIcon then self.hbd:RemoveWorldMapIcon(self.liveRef, pin) end
        local flag = HBD_PINS_WORLDMAP_SHOW_WORLD or HBD_PINS_WORLDMAP_SHOW_CONTINENT or 0
        self.hbd:AddWorldMapIconMap(self.liveRef, pin, map, x, y, flag)
        return
    end
    -- Without HereBeDragons: on the map you're looking at, if you're on it.
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local _, vx, vy = self:PlayerPos(viewed)
    if not (viewed and canvas and vx) then return self:HideLive() end
    self.live = { map = viewed, x = vx, y = vy }
    local pin = self:LivePin(canvas)
    local scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    pin:SetSize(LIVE_SIZE / scale, LIVE_SIZE / scale)
    pin:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2110)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", vx * canvas:GetWidth(), -vy * canvas:GetHeight())
    pin:Show()
end

---------------------------------------------------------------------------
-- Coordinates bar: "You: 42.1, 61.9   Cursor: 50.0, 33.3"
---------------------------------------------------------------------------

function AltMap:UpdateCoords()
    if not WorldMapFrame then return end
    local set = Settings()
    local sc = type(WorldMapFrame.ScrollContainer) == "table" and WorldMapFrame.ScrollContainer or nil
    local holder = sc or WorldMapFrame
    if not self.coordsText then
        local f = CreateFrame("Frame", nil, holder)
        f:SetSize(320, 18)
        f:SetPoint("BOTTOM", holder, "BOTTOM", 0, 4)
        f:SetFrameLevel((holder:GetFrameLevel() or 1) + 2200)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("CENTER")
        self.coordsFrame, self.coordsText = f, f.text
    end
    if set.coords == false then self.coordsFrame:Hide() return end
    local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local _, px, py = self:PlayerPos(viewed)
    local parts = { W.T("You") .. ": " .. (px and (Coord(px) .. ", " .. Coord(py)) or "-") }
    if sc and sc.GetNormalizedCursorPosition and (not sc.IsMouseOver or sc:IsMouseOver()) then
        local ok, cx, cy = pcall(sc.GetNormalizedCursorPosition, sc)
        if ok and tonumber(cx) and tonumber(cy) and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            table.insert(parts, W.T("Cursor") .. ": " .. Coord(cx) .. ", " .. Coord(cy))
        end
    end
    self.coordsText:SetText(table.concat(parts, "     "))
    self.coordsFrame:Show()
end

---------------------------------------------------------------------------
-- Trail (part of the live view): a continuous line behind you showing where
-- you've walked, ridden and flown since you logged in. Kept in memory only.
---------------------------------------------------------------------------

function AltMap:StartTrail()
    self.trail = self.trail or {}
    if self.trailFrame then return end
    self.trailFrame = CreateFrame("Frame")
    self.trailFrame:SetScript("OnUpdate", function(_, elapsed)
        self.trailWait = (self.trailWait or 0) - (elapsed or 0)
        if self.trailWait > 0 then return end
        self.trailWait = TRAIL_EVERY
        self:RecordTrail()
    end)
end

local function TrailOn()
    local set = FS.db and Settings()
    return set and set.live == true and set.trail ~= false
end
AltMap.TrailOn = TrailOn

function AltMap:RecordTrail()
    if not TrailOn() then return end
    local map, x, y = self:PlayerPos()
    if not map then self.trailBreak = true return end -- indoors: the line continues from where you come out
    local last = self.trail[#self.trail]
    if last and last.map == map and math.abs(last.x - x) < TRAIL_STEP and math.abs(last.y - y) < TRAIL_STEP then return end
    -- new map, a long jump (hearth, portal, flight path loading) or back from indoors: start a new piece of line
    local gap = self.trailBreak or not last or last.map ~= map or math.abs(last.x - x) > TRAIL_JUMP or math.abs(last.y - y) > TRAIL_JUMP
    self.trailBreak = nil
    if #self.trail >= TRAIL_MAX then
        table.remove(self.trail, 1)
        if self.trail[1] then self.trail[1].gap = true end
        self.trailDirty = true
    end
    table.insert(self.trail, { map = map, x = x, y = y, gap = gap })
    if WorldMapFrame and WorldMapFrame:IsShown() then
        if self.trailDirty then self:DrawTrail() else self:DrawTrailSegment(#self.trail) end
    end
end

-- The line layer sits on the map canvas, so it zooms and pans with the map.
function AltMap:TrailLayer()
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then return nil end
    if not self.trailLayer then
        self.trailLayer = CreateFrame("Frame", nil, canvas)
        self.trailLayer:SetAllPoints(canvas)
        self.trailLines = {}
    end
    self.trailLayer:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2050)
    return self.trailLayer, canvas
end

-- A trail point on the map you're looking at (zone, continent, world).
function AltMap:OnViewed(p, viewed)
    if p.map == viewed then return p.x, p.y end
    if not self.hbdCore then self.hbdCore = LibStub("HereBeDragons-2.0", true) or false end
    if not self.hbdCore or not self.hbdCore.TranslateZoneCoordinates then return nil end
    local x, y = self.hbdCore:TranslateZoneCoordinates(p.x, p.y, p.map, viewed, true)
    if x and y and x > -0.2 and x < 1.2 and y > -0.2 and y < 1.2 then return x, y end
end

function AltMap:DrawTrailSegment(i, layer, canvas, viewed, w, h, thick)
    if not layer then
        layer, canvas = self:TrailLayer()
        if not layer then return end
        viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        w, h = canvas:GetWidth(), canvas:GetHeight()
        local scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
        thick = 3 / ((scale and scale > 0) and scale or 1)
    end
    local a, b = self.trail[i - 1], self.trail[i]
    if not (a and b) or b.gap then return end
    local x1, y1 = self:OnViewed(a, viewed)
    local x2, y2 = self:OnViewed(b, viewed)
    if not (x1 and x2) then return end
    self.trailUsed = (self.trailUsed or 0) + 1
    local line = self.trailLines[self.trailUsed]
    if not line then
        line = layer:CreateLine(nil, "OVERLAY")
        line:SetColorTexture(0.3, 1, 0.4, 0.85)
        self.trailLines[self.trailUsed] = line
    end
    line:SetThickness(thick)
    line:SetStartPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
    line:SetEndPoint("TOPLEFT", canvas, x2 * w, -y2 * h)
    line:Show()
end

function AltMap:DrawTrail()
    self.trailDirty = nil
    local layer, canvas = self:TrailLayer()
    if not layer then return end
    for _, line in ipairs(self.trailLines) do line:Hide() end
    self.trailUsed = 0
    if not TrailOn() or not WorldMapFrame:IsShown() then return end
    local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    local thick = 3 / ((scale and scale > 0) and scale or 1)
    for i = 2, #self.trail do self:DrawTrailSegment(i, layer, canvas, viewed, w, h, thick) end
end

function AltMap:ClearTrail()
    self.trail = {}
    self:DrawTrail()
end

---------------------------------------------------------------------------
-- Live sharing (opt-in on both sides, off by default)
--   Sending: where you are now, to your guild and trusted Battle.net friends,
--            every 15 s while you move (once a minute standing still).
--   Showing: guildmates' and friends' live spots on your realm or a connected
--            realm, with a cyan ring. Kept in memory only; gone after 90 s
--            without news, when they stop sharing, or when you log out.
---------------------------------------------------------------------------

function AltMap:ShareLiveTick()
    if not FS.db then return end
    local set, privacy = Settings(), FS.db.profile.privacy or {}
    local on = set.shareLive and privacy.shareLocation ~= false
    if not on then
        if self.liveSent then -- tell everyone once that we stopped
            if FS.Comm:SendLive(nil) then self.liveSent = nil end
        end
        return
    end
    local map, x, y = self:PlayerPos()
    if not map then return end -- indoors / in an instance: nothing to send (receivers time out)
    local last, now = self.liveSent, time()
    local moved = not last or last.map ~= map or math.abs(last.x - x) > 0.001 or math.abs(last.y - y) > 0.001
    if not moved and now - last.t < LIVE_HEARTBEAT then return end
    local zone = GetRealZoneText and GetRealZoneText()
    if not (type(zone) == "string" and Ok(zone)) then zone = nil end
    if FS.Comm:SendLive(map, x, y, zone) then self.liveSent = { map = map, x = x, y = y, t = now } end
end

function AltMap:SetPeer(name, data)
    self.peers = self.peers or {}
    if data then
        local set = Settings()
        if not set.showLive or not self:SameRealm(name) then return end
        if not self.peers[name] then
            local n = 0
            for _ in pairs(self.peers) do n = n + 1 end
            if n >= PEER_MAX then return end
        end
        data.name, data.t = name, time()
        self.peers[name] = data
    else
        self.peers[name] = nil
    end
    self.peersDirty = true
    if WorldMapFrame and WorldMapFrame:IsShown() then self:DrawPeers() end
end

local function PeerTooltip(pin)
    local d = pin.peer
    if not d then return end
    local rec = FS.db.global.characters[d.name] or { fullName = d.name, cls = d.cls }
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(W.T("Live"), 0.3, 0.9, 1)
    GameTooltip:AddLine(W.CharName(rec))
    GameTooltip:AddLine(string.format("%s %s %s", W.T("Level"), tostring(d.level or rec.level or "?"), W.Plain(W.ClassName(d.cls or rec.cls))), 1, 1, 1)
    if d.zone and d.zone ~= "" then GameTooltip:AddLine(d.zone, 1, 0.82, 0) end
    GameTooltip:AddLine(string.format(W.T("Updated %s"), W.Plain(W.Ago(d.t))), 0.8, 0.8, 0.8)
    if d.owner then GameTooltip:AddLine(string.format(W.T("Shared by %s"), d.owner), 0.6, 0.8, 1) end
    if FS.db.global.characters[d.name] then GameTooltip:AddLine(W.T("Click to open their profile."), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

function AltMap:PeerPin(i, parent)
    self.peerPins = self.peerPins or {}
    local pin = self.peerPins[i]
    if not pin then
        pin = CreateFrame("Button", nil, parent)
        pin.ring = pin:CreateTexture(nil, "BACKGROUND")
        pin.ring:SetPoint("TOPLEFT", -3, 3)
        pin.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        pin.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        pin.ring:SetVertexColor(0.3, 0.9, 1, 1)
        pin.tex = pin:CreateTexture(nil, "ARTWORK")
        pin.tex:SetAllPoints()
        pin:SetScript("OnEnter", PeerTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", function(p)
            if p.peer and FS.db.global.characters[p.peer.name] and FS.Nav then FS.Nav:Character(p.peer.name) end
        end)
        self.peerPins[i] = pin
    end
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    return pin
end

function AltMap:DrawPeers()
    self.peersDirty = nil
    self.peerRef = self.peerRef or {}
    if self.hbd then self.hbd:RemoveAllWorldMapIcons(self.peerRef) end
    for _, pin in ipairs(self.peerPins or {}) do pin:Hide() end
    if not FS.db then return end
    local now, list = time(), {}
    for name, d in pairs(self.peers or {}) do
        if now - d.t > PEER_TIMEOUT then self.peers[name] = nil else table.insert(list, d) end
    end
    if not Settings().showLive or #list == 0 then return end
    table.sort(list, function(a, b) return a.name < b.name end)
    local canvas, viewed, w, h, scale
    if not self.hbd then
        if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
        viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        if not (viewed and canvas) then return end
        w, h = canvas:GetWidth(), canvas:GetHeight()
        scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
        if not scale or scale <= 0 then scale = 1 end
    end
    local n = 0
    for _, d in ipairs(list) do
        if self.hbd or d.map == viewed then
            n = n + 1
            local pin = self:PeerPin(n, self.hbd and UIParent or canvas)
            pin.peer = d
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.cls or ""]
            if coords then
                pin.tex:SetTexture(CLASS_ICONS)
                pin.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                pin.tex:SetTexture(FS.LOGO)
                pin.tex:SetTexCoord(0, 1, 0, 1)
            end
            if self.hbd then
                pin:SetSize(SIZE, SIZE)
                self.hbd:AddWorldMapIconMap(self.peerRef, pin, d.map, d.x, d.y, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 0)
            else
                pin:SetSize(SIZE / scale, SIZE / scale)
                pin:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2105)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", d.x * w, -d.y * h)
                pin:Show()
            end
        end
    end
end

-- /fsync altmap: what the Alt Map knows (for bug reports)
function AltMap:PrintCheck()
    local me = FS:GetPlayerKey()
    FS:Print(string.format("Alt Map: you are %s (%s). Live view %s, trail %s, %d trail points.", me, self:MyIdentity(),
        Settings().live and "on" or "off", TrailOn() and "on" or "off", #(self.trail or {})))
    local n = 0
    for name, rec in pairs(FS.db.global.characters) do
        if rec.isMyChar and type(rec.pos) == "table" then
            n = n + 1
            FS:Print(string.format("  %s [%s] map %s at %.1f, %.1f (%s)%s", name, AltMap.Identity(name, rec.cls), tostring(rec.pos.map),
                (tonumber(rec.pos.x) or 0) * 100, (tonumber(rec.pos.y) or 0) * 100, W.Plain(W.Ago(rec.pos.t)), rec.isMock and " sample" or ""))
        end
    end
    FS:Print(string.format("%d of your characters have a position; %d icons are drawn.", n, #self:Markers()))
end
