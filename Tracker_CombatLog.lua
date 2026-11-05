local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Tracker = FS.Tracker
local CL = {}
Tracker.CombatLog = CL

---------------------------------------------------------------------------
-- Combat log tracking for Classic Era, TBC Anniversary and Mists Classic.
-- Retail (Midnight) and WoW: Forever forbid this, so it is never registered there.
--   * kills:   your (or your pet's) killing blows; NPCs also go into the bestiary.
--              Each kill belongs to exactly one player, so guild totals don't double count.
--   * damage / healing (effective, without overhealing) / largest hit
--   * fall damage, and who or what hit you last (for the deathlog)
---------------------------------------------------------------------------

local band = bit and bit.band or function() return 0 end
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local DAMAGE = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true, DAMAGE_SHIELD = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local ENVIRONMENT = { FALLING = "Falling", DROWNING = "Drowning", FIRE = "Fire", LAVA = "Lava", SLIME = "Slime", FATIGUE = "Fatigue" }

function CL:Enable()
    if not FS.HAS_COMBAT_LOG or not CombatLogGetCurrentEventInfo then return false end
    local f = CreateFrame("Frame")
    if not pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED") then return false end
    pcall(f.RegisterEvent, f, "UNIT_PET")
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            CL:OnCombatEvent(CombatLogGetCurrentEventInfo())
        else
            CL:UpdateGuids()
        end
    end)
    self.frame = f
    self:UpdateGuids()
    return true
end

function CL:UpdateGuids()
    self.me = UnitGUID("player")
    self.pet = UnitExists("pet") and UnitGUID("pet") or nil
end

function CL:OnCombatEvent(_, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, dstFlags, _, a12, a13, a14, a15, a16, _, a18, _, _, a21)
    local me = self.me
    local fromMe = srcGUID == me
    local fromPet = not fromMe and srcGUID ~= nil and srcGUID == self.pet
    local toMe = dstGUID == me
    if not (fromMe or fromPet or toMe) then return end -- most events: nothing to do

    local st = Tracker.db.char.stats
    local amount, spell, crit
    if sub == "SWING_DAMAGE" then
        amount, crit = a12, a18
    elseif DAMAGE[sub] then
        spell, amount, crit = a13, a15, a21
    elseif HEAL[sub] then
        if fromMe then st.healing = (st.healing or 0) + math.max(0, (tonumber(a15) or 0) - (tonumber(a16) or 0)) end
        return
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        if toMe then
            local kind = ENVIRONMENT[tostring(a12):upper()] or tostring(a12)
            local hurt = tonumber(a13) or 0
            if kind == "Falling" then st.fallDamage = (st.fallDamage or 0) + hurt end
            self.lastHit = { name = kind, spell = "", amount = hurt, at = GetTime() }
        end
        return
    elseif sub == "PARTY_KILL" then
        if fromMe or fromPet then
            st.kills = (st.kills or 0) + 1
            if band(dstFlags or 0, TYPE_PLAYER) ~= 0 then st.pvpKills = (st.pvpKills or 0) + 1 end
            if dstName and band(dstFlags or 0, TYPE_PLAYER) == 0 then
                local info = Tracker.guidInfo and Tracker.guidInfo[dstGUID]
                if info and info.critter then st.critters = (st.critters or 0) + 1 end
                Tracker:CountKill(dstGUID, dstName, info and info.boss)
            end
        end
        return
    end

    amount = tonumber(amount)
    if not amount then return end
    if fromMe or fromPet then
        st.damage = (st.damage or 0) + amount
        if fromMe and amount > (tonumber(st.crit) or 0) then
            st.crit = amount
            Tracker.db.char.critSpell = spell or "Melee"
        end
    end
    if toMe and not fromMe then
        self.lastHit = { name = srcName or "Unknown", spell = spell or "Melee", amount = amount, at = GetTime(), guid = srcGUID }
    end
end
