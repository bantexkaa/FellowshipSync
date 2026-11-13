local addonName, addonTable = ...
local FS = addonTable.FellowshipSync
local Diag = FS.Diag
local W = FS.W

---------------------------------------------------------------------------
-- /fsync debug: a copyable report for bug reports.
-- /fsync perf:  memory, saved-data size and how long the once-a-second work takes.
---------------------------------------------------------------------------

local function Has(lib) return LibStub and LibStub(lib, true) ~= nil end
local function YesNo(v) return v and "yes" or "no" end

-- Times the once-a-second update (the addon's main recurring work).
function Diag:Enable()
    self.perf = { count = 0, total = 0, max = 0 }
    local T = FS.Tracker
    local original = T.Tick
    T.Tick = function(tracker, ...)
        if not debugprofilestop then return original(tracker, ...) end
        local start = debugprofilestop()
        original(tracker, ...)
        local ms = debugprofilestop() - start
        local p = Diag.perf
        p.count, p.total = p.count + 1, p.total + ms
        if ms > p.max then p.max = ms end
    end
    self:CountSent()
end

-- Counts what we send, to show in the report.
function Diag:CountSent()
    local C = FS.Comm
    if not C or not C.BroadcastStats or self.wrappedComm then return end
    self.wrappedComm = true
    self.sends = 0
    local original = C.BroadcastStats
    C.BroadcastStats = function(comm, ...)
        Diag.sends = Diag.sends + 1
        return original(comm, ...)
    end
end

function Diag:Memory()
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
    pcall(UpdateAddOnMemoryUsage)
    local ok, kb = pcall(GetAddOnMemoryUsage, addonName or "FellowshipSync")
    return ok and tonumber(kb) or nil
end

-- Rough size of the saved data (serialised the same way sync does).
function Diag:SavedSize()
    local ser = LibStub and LibStub("AceSerializer-3.0", true)
    if not ser then return nil end
    local ok1, g = pcall(ser.Serialize, ser, FS.db.global)
    local ok2, c = pcall(ser.Serialize, ser, FS.db.char)
    return (ok1 and #g or 0) + (ok2 and #c or 0)
end

local function Kb(bytes) return bytes and string.format("%.1f KB", bytes / 1024) or "?" end

function Diag:PerfLines()
    local p = self.perf or { count = 0, total = 0, max = 0 }
    local mem = self:Memory()
    local size = self:SavedSize()
    local chars, mine = 0, 0
    for _, r in pairs(FS.db.global.characters) do chars = chars + 1; if r.isMyChar then mine = mine + 1 end end
    return {
        string.format("Memory in use: %s", mem and string.format("%.0f KB", mem) or "not available in this client"),
        string.format("Saved data: about %s (%d characters known, %d of them yours, %d news items)", Kb(size), chars, mine, #FS.db.global.events),
        string.format("Once-a-second update: %s average, %s slowest (%d measured)",
            p.count > 0 and string.format("%.2f ms", p.total / p.count) or "-", p.count > 0 and string.format("%.2f ms", p.max) or "-", p.count),
        string.format("Light mode: %s", FS.db.profile.lightMode and "on" or "off"),
    }
end

function Diag:PrintPerf()
    FS:Print(W.T("Performance check:"))
    for _, line in ipairs(self:PerfLines()) do FS:Print("  " .. line) end
    local p = self.perf
    if p and p.count > 10 and p.total / p.count > 2 then
        FS:Print("  |cffffd100" .. W.T("Tip: Light mode (Options) skips the least important trackers.") .. "|r")
    end
end

-- Recent FellowshipSync errors, if BugGrabber (BugSack) is installed.
function Diag:RecentErrors()
    local out = {}
    local bg = _G.BugGrabber
    local db = bg and bg.GetDB and select(2, pcall(bg.GetDB, bg))
    if type(db) ~= "table" then return out end
    for i = #db, 1, -1 do
        local e = db[i]
        local msg = type(e) == "table" and tostring(e.message or "") or ""
        if msg:find("FellowshipSync") then
            table.insert(out, string.format("x%d %s", tonumber(e.counter) or 1, msg:sub(1, 300)))
            if #out >= 5 then break end
        end
    end
    return out
end

function Diag:Report()
    local L = {}
    local function add(...) table.insert(L, string.format(...)) end
    local version, build, _, toc = GetBuildInfo()
    local p = FS.db.profile
    add("FellowshipSync debug report - %s", date("%Y-%m-%d %H:%M"))
    add("Addon: %s | Game: %s | Client: %s (build %s, interface %s) | Locale: %s | Region: %s",
        FS.VERSION, FS.GAME_INFO.name, tostring(version), tostring(build), tostring(toc), tostring(GetLocale and GetLocale()),
        tostring(GetCurrentRegion and GetCurrentRegion()))
    local me = FS:GetMyRecord() or {}
    local guild, rankName, rankIndex = GetGuildInfo("player")
    add("Character: level %s %s | Guild: %s | Rank: %s (%s) | Officer powers: %s", tostring(me.level), tostring(me.cls),
        tostring(guild or "none"), tostring(rankName or "-"), tostring(rankIndex or "-"),
        YesNo(FS.Officer.AmIOfficer and FS.Officer:AmIOfficer()))
    local libs = {}
    for _, lib in ipairs({ "AceAddon-3.0", "AceDB-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceGUI-3.0", "LibDeflate",
                           "LibDataBroker-1.1", "LibDBIcon-1.0", "HereBeDragons-Pins-2.0", "LibSharedMedia-3.0" }) do
        table.insert(libs, lib .. "=" .. (Has(lib) and "ok" or "missing"))
    end
    add("Libraries: %s", table.concat(libs, ", "))
    local off = {}
    for key, v in pairs(p.privacy or {}) do if v == false then table.insert(off, key) end end
    table.sort(off)
    add("Settings: profile '%s' | guild sync %s | Battle.net %s | relay %s | alts %s | password %s | toasts %s | light mode %s | options %s",
        tostring(FS.db.GetCurrentProfile and FS.db:GetCurrentProfile()), YesNo(p.syncGuild ~= false), YesNo(p.syncBNet ~= false),
        YesNo(p.relayBNet ~= false), YesNo(p.shareAlts ~= false), YesNo((p.bnetPassword or "") ~= ""), YesNo(p.notify.toasts),
        YesNo(p.lightMode), tostring(p.optionsMode))
    add("Privacy turned off: %s", #off > 0 and table.concat(off, ", ") or "nothing")
    local objects = 0
    local store = FS.Officer.Store and FS.Officer:Store()
    if store then for _ in pairs(store.objects) do objects = objects + 1 end end
    add("Data: %d news items | %d guild-tool items | %d deaths logged | %d goals | %d snapshots",
        #FS.db.global.events, objects, #(FS.db.char.deathLog or {}), #(FS.db.char.goals or {}), #(FS.db.char.snapshots or {}))
    add("Sync: last sent %s | sends this session %s", FS.Comm.lastSent and (time() - FS.Comm.lastSent .. "s ago") or "not yet",
        tostring(self.sends or 0))
    local d = FS.Tracker.legacyDiag
    if d then
        add("Legacy: %s points | %d categories, %d challenges, %d completed, game total %d", tostring(FS.Tracker.legacyTotal),
            d.categories, d.challenges, d.completed, d.apiTotal)
    end
    local found, missing = 0, {}
    local ids = FS.Tracker.statIds or (FS.Tracker.DiscoverStatistics and FS.Tracker:DiscoverStatistics()) or {}
    for _ in pairs(ids) do found = found + 1 end
    for key in pairs(FS.Tracker.STAT_NAMES or {}) do if not ids[key] then table.insert(missing, key) end end
    table.sort(missing)
    add("Blizzard statistics found: %d%s", found, #missing > 0 and (" | not found: " .. table.concat(missing, ", ")) or "")
    for _, line in ipairs(self:PerfLines()) do add("%s", line) end
    local errors = self:RecentErrors()
    if #errors > 0 then
        add("Recent FellowshipSync errors (BugSack):")
        for _, e in ipairs(errors) do add("  %s", e) end
    else
        add("Recent errors: none found%s", _G.BugGrabber and "" or " (install BugSack to include them here)")
    end
    return table.concat(L, "\n")
end

function Diag:ShowReport()
    W.CopyBox(W.T("FellowshipSync debug report"), self:Report())
end
