local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Extras = FS.Extras
local UI, W = FS.UI, FS.W

function Extras:Enable()
    self:BuildMinimapButton()
    self:BuildToast()
end

---------------------------------------------------------------------------
-- Minimap button (drag to move around the minimap; right-click for Options)
---------------------------------------------------------------------------

local ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local function MinimapClick(button)
    if button == "RightButton" then
        FS:ToggleUI()
        if UI.MainFrame and UI.MainFrame:IsShown() then UI:SelectTab(#UI.VIEWS) end
    else
        FS:ToggleUI()
    end
end

local function MinimapTooltip(tt)
    tt:AddLine("|cffffd100Fellowship|rSync")
    tt:AddLine("Left-click: open / close", 1, 1, 1)
    tt:AddLine("Right-click: options", 1, 1, 1)
    tt:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
end

function Extras:BuildMinimapButton()
    if self.minimapButton or self.dbIcon or not Minimap then return end
    local mm = FS.db.profile.minimap
    mm.minimapPos = mm.minimapPos or mm.angle or 215

    -- Preferred: the standard LibDBIcon button (works with square minimaps and button collectors).
    local LDB = LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub("LibDBIcon-1.0", true)
    if LDB and DBI then
        local launcher = LDB:GetDataObjectByName("FellowshipSync") or LDB:NewDataObject("FellowshipSync", {
            type = "launcher", text = "FellowshipSync", icon = ICON,
            OnClick = function(_, button) MinimapClick(button) end,
            OnTooltipShow = MinimapTooltip,
        })
        if launcher then
            DBI:Register("FellowshipSync", launcher, mm)
            self.dbIcon = DBI
            return
        end
    end

    local b = CreateFrame("Button", "FellowshipSyncMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button) MinimapClick(button) end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Extras.DragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapButton = b
    self:UpdateMinimapButton()
end

function Extras.DragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg((math.atan2 or math.atan)(cy / scale - my, cx / scale - mx)) % 360
    FS.db.profile.minimap.angle, FS.db.profile.minimap.minimapPos = angle, angle
    Extras:UpdateMinimapButton()
end

function Extras:UpdateMinimapButton()
    local mm = FS.db.profile.minimap
    if self.dbIcon then
        mm.minimapPos = mm.minimapPos or mm.angle or 215
        self.dbIcon:Refresh("FellowshipSync", mm) -- also picks up a profile switch
        if mm.hide then self.dbIcon:Hide("FellowshipSync") else self.dbIcon:Show("FellowshipSync") end
        return
    end
    local b = self.minimapButton
    if not b then return end
    if mm.hide then b:Hide() return end
    local angle = math.rad(tonumber(mm.minimapPos or mm.angle) or 215)
    local radius = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    b:Show()
end

---------------------------------------------------------------------------
-- Toasts: your own milestones pop up briefly at the top of the screen.
---------------------------------------------------------------------------

-- Only sounds that exist in the current game version are offered.
Extras.SOUNDS = {
    { id = "epic",      label = "Epic loot",          kit = "UI_EPICLOOT_TOAST" },
    { id = "legendary", label = "Legendary loot",     kit = "UI_LEGENDARY_LOOT_TOAST" },
    { id = "quest",     label = "Quest complete",     kit = "IG_QUEST_LIST_COMPLETE" },
    { id = "raid",      label = "Raid warning",       kit = "RAID_WARNING" },
    { id = "ready",     label = "Ready check",        kit = "READY_CHECK" },
    { id = "bnet",      label = "Battle.net toast",   kit = "UI_BNET_TOAST" },
    { id = "whisper",   label = "Whisper",            kit = "TELL_MESSAGE" },
    { id = "coins",     label = "Coins",              kit = "LOOT_WINDOW_COIN_SOUND" },
    { id = "bell",      label = "Alarm bell",         kit = "ALARM_CLOCK_WARNING_3" },
    { id = "invite",    label = "Group invite",       kit = "IG_PLAYER_INVITE" },
    { id = "levelup",   label = "Level up",           kit = "LEVELUPSOUND" },
    { id = "boss",      label = "Boss whisper",       kit = "UI_RAID_BOSS_WHISPER_WARNING" },
    { id = "none",      label = "No sound" },
}

function Extras:AvailableSounds()
    local out = {}
    for _, s in ipairs(self.SOUNDS) do
        if not s.kit or (SOUNDKIT and SOUNDKIT[s.kit]) then table.insert(out, s) end
    end
    return out
end

function Extras:BuildToast()
    if self.toast then return end
    local t = CreateFrame("Button", "FellowshipSyncToast", UIParent, "BackdropTemplate")
    t:SetSize(380, 66)
    t:SetFrameStrata("DIALOG")
    t:SetBackdrop(W.SOFT)
    t:SetMovable(true)
    t:SetClampedToScreen(true)
    t:RegisterForDrag("LeftButton")
    t:Hide()
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(44, 44)
    t.icon:SetPoint("LEFT", 11, 0)
    t.tag = W.Text(t, "GameFontDisableSmall")
    t.tag:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 0)
    t.tag:SetText("FELLOWSHIPSYNC")
    t.title = W.Text(t, "GameFontNormal")
    t.title:SetPoint("TOPLEFT", t.tag, "BOTTOMLEFT", 0, -2)
    t.desc = W.Text(t, "GameFontHighlightSmall")
    t.desc:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -2)
    t.desc:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    t:SetScript("OnClick", function(self) if not Extras.moving then self.elapsed = 99 end end)
    t:SetScript("OnDragStart", function(self) if Extras.moving then self:StartMoving() end end)
    t:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        FS.db.profile.notify.point = { point, x, y }
    end)
    t:SetScript("OnUpdate", function(self, dt)
        if Extras.moving then self:SetAlpha(1) return end
        local hold = tonumber(FS.db.profile.notify.duration) or 5
        self.elapsed = (self.elapsed or 0) + dt
        if self.elapsed < 0.3 then self:SetAlpha(self.elapsed / 0.3)
        elseif self.elapsed < hold then self:SetAlpha(1)
        elseif self.elapsed < hold + 0.8 then self:SetAlpha(1 - (self.elapsed - hold) / 0.8)
        else self:Hide(); Extras:NextToast() end
    end)
    -- Held toasts are released after combat and when leaving an instance.
    t:RegisterEvent("PLAYER_REGEN_ENABLED")
    t:RegisterEvent("PLAYER_ENTERING_WORLD")
    t:SetScript("OnEvent", function() if not t:IsShown() then Extras:NextToast() end end)
    self.toast, self.toastQueue = t, {}
    self:ApplyToastLayout()
end

function Extras:ApplyToastLayout()
    local t = self.toast
    if not t then return end
    local n = FS.db.profile.notify
    local p = n.point or { "TOP", 0, -150 }
    t:ClearAllPoints()
    t:SetPoint(p[1] or "TOP", UIParent, p[1] or "TOP", tonumber(p[2]) or 0, tonumber(p[3]) or -150)
    t:SetScale(tonumber(n.scale) or 1)
end

-- isGuild: a guildmate's / friend's event (can be held while in instances).
function Extras:ShowToast(title, desc, icon, isGuild)
    if not self.toast or not FS.db.profile.notify.toasts then return end
    local q = self.toastQueue
    if #q >= 8 then
        -- Busy moment (e.g. a raid night): fold the rest into one summary toast.
        local last = q[#q]
        if not last.summary then
            last = { title = "More News", desc = "", icon = "Interface\\Icons\\INV_Misc_Note_02", count = 0, summary = true }
            table.insert(q, last)
        end
        last.count = last.count + 1
        last.desc = string.format("+%d more updates. Open FellowshipSync (/fsync) to read them.", last.count)
        return
    end
    table.insert(q, { title = title, desc = desc, icon = icon, guild = isGuild })
    if not self.toast:IsShown() then self:NextToast() end
end

function Extras:CanShowNow(item)
    local n = FS.db.profile.notify
    if n.pauseInCombat ~= false and InCombatLockdown() then return false end
    if item.guild and n.holdInInstances ~= false and IsInInstance and IsInInstance() then return false end
    return true
end

function Extras:NextToast()
    local q = self.toastQueue
    if not q or self.moving then return end
    local index
    for i, item in ipairs(q) do
        if self:CanShowNow(item) then index = i break end
    end
    if not index then return end -- everything is on hold for now
    local item = table.remove(q, index)
    local t, pal = self.toast, W.Pal()
    FS.Style:ApplyToast(t)
    t.title:SetText(item.title)
    t.desc:SetText(item.desc)
    t.icon:SetTexture(item.icon or "Interface\\Icons\\Achievement_General")
    t.elapsed = 0
    t:SetAlpha(0)
    t:Show()
    self:PlayToastSound(item.guild)
end

function Extras:PlayToastSound(isGuild)
    local n = FS.db.profile.notify
    local choice = isGuild and (n.guildSound or n.sound) or n.sound
    for _, s in ipairs(self.SOUNDS) do
        if s.id == choice and s.kit and PlaySound and SOUNDKIT and SOUNDKIT[s.kit] then
            pcall(PlaySound, SOUNDKIT[s.kit])
        end
    end
end

-- Lets the player drag the toast where they want it. Call again to lock.
function Extras:ToggleToastMover()
    if not self.toast then return end
    self.moving = not self.moving
    local t = self.toast
    if self.moving then
        t.title:SetText("Drag me where you want toasts")
        t.desc:SetText("Click \"Lock Position\" in Options when you are done.")
        t.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        local pal = W.Pal()
        t:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], 0.95)
        t:SetBackdropBorderColor(pal.accent[1], pal.accent[2], pal.accent[3], 1)
        t:SetAlpha(1)
        t:Show()
    else
        t:Hide()
        self:NextToast()
    end
    return self.moving
end

function Extras:TestToast()
    self:ShowToast("Test Toast", "This is how FellowshipSync toasts look and sound.", "Interface\\Icons\\Achievement_General", false)
end

-- Called by FS:AddEvent for every new event.
function Extras:OnNewEvent(ev)
    if FS.Notify.OnEvent then FS.Notify:OnEvent(ev) end
    if FS.Fellowship.OnEvent then FS.Fellowship:OnEvent(ev) end -- Memory Lane screenshots
end

---------------------------------------------------------------------------
-- News ticker along the bottom of the main window ("the gossip feed").
---------------------------------------------------------------------------

function Extras:BuildTicker(parent)
    local bar = W.Box(parent, "header", true)
    bar:SetPoint("BOTTOMLEFT", 184, 8) -- right of the Share / Export buttons
    bar:SetSize(560, 22)
    self.tickerBar = bar
    local label = W.Text(bar, "GameFontNormalSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText("NEWS:")
    self.tickerLabel = label

    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT", 52, 0)
    clip:SetPoint("BOTTOMRIGHT", -6, 0)
    clip:SetClipsChildren(true)
    local text = W.Text(clip, "GameFontHighlightSmall")
    text:SetPoint("LEFT", clip, "LEFT", 0, 0)
    self.tickerText, self.tickerClip = text, clip
    self.tickerX = 0

    clip:SetScript("OnUpdate", function(_, dt)
        local width = text:GetStringWidth() or 0
        if width <= 0 then return end
        self.tickerX = self.tickerX - dt * 45
        if self.tickerX < -width then
            self.tickerX = clip:GetWidth() or 600
            if self.pendingTicker then text:SetText(self.pendingTicker); self.pendingTicker = nil end
        end
        text:ClearAllPoints()
        text:SetPoint("LEFT", clip, "LEFT", self.tickerX, 0)
    end)
end

function Extras:ApplyTickerVisibility()
    if self.tickerBar then self.tickerBar:SetShown(FS.db.profile.showTicker ~= false) end
    if self.tickerLabel then W.AccentText(self.tickerLabel) end
end

function Extras:RefreshTicker()
    if not self.tickerText then return end
    local events = FS:GetScopedEvents(UI.currentScope)
    local parts = {}
    for i = 1, math.min(12, #events) do
        local tag, sentence = W.EventText(events[i])
        table.insert(parts, tag .. " " .. sentence)
    end
    local text = #parts > 0 and table.concat(parts, "        ")
        or "No news yet. Deaths, level-ups, " .. FS.POINTS.items:lower() .. " and gear records from everyone in this view show up here."
    if self.tickerText:GetText() == nil or self.tickerText:GetText() == "" then
        self.tickerText:SetText(text)
    elseif text ~= self.tickerText:GetText() then
        self.pendingTicker = text -- swap in after the current pass so it doesn't jump
    end
end

---------------------------------------------------------------------------
-- Game tooltip: a few FellowshipSync lines when hovering a known player
---------------------------------------------------------------------------

function Extras:AddUnitLines(tt)
    if not FS.db or FS.db.profile.unitTooltip == false or not tt or not tt.GetUnit then return end
    local _, unit = tt:GetUnit()
    if not unit or FS.IsSecret(unit) then return end
    local isPlayer = UnitIsPlayer(unit)
    if FS.IsSecret(isPlayer) or not isPlayer then return end
    local key = FS.Fellowship:MemberKey(unit)
    local rec = key and FS.db.global.characters[key]
    if not rec or rec.isMock or rec.isMyChar then return end
    local nemesis, n = nil, 0
    for name, count in pairs(rec.killers or {}) do if count > n then nemesis, n = name, count end end
    tt:AddLine(" ")
    tt:AddDoubleLine("|cffffd100Fellowship|rSync", string.format("%s GS  -  %s kills  -  %s deaths",
        W.Num(rec.gs), W.Num(rec.kills), W.Num(rec.deaths)), 1, 1, 1, 0.9, 0.9, 0.9)
    if nemesis then tt:AddDoubleLine(W.T("Nemesis"), nemesis, 0.7, 0.7, 0.7, 1, 0.4, 0.4) end
    for _, award in ipairs(FS.Officer.AwardsFor and FS.Officer:AwardsFor(rec.fullName) or {}) do
        tt:AddDoubleLine(W.T("Award"), tostring(award.title), 0.7, 0.7, 0.7, 1, 0.82, 0)
        break
    end
    tt:Show()
end

function Extras:EnableUnitTooltip()
    if self.unitTooltipHooked then return end
    self.unitTooltipHooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then Extras:AddUnitLines(tt) end
        end)
    elseif GameTooltip and GameTooltip.HookScript and (not GameTooltip.HasScript or GameTooltip:HasScript("OnTooltipSetUnit")) then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) Extras:AddUnitLines(tt) end)
    end
end
