local addonName, addonTable = ...

---------------------------------------------------------------------------
-- Safety check for the libraries FellowshipSync is built on.
--  * Ace3 missing: the addon can't run. Say so clearly in chat (and on /fsync)
--    instead of failing silently, and keep the other files from throwing errors.
--  * LibDeflate missing: the addon runs, but can't read compressed sync messages
--    from other players. Warn once.
---------------------------------------------------------------------------

local ACE = { "AceAddon-3.0", "AceDB-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0",
              "AceConsole-3.0", "AceTimer-3.0", "AceGUI-3.0" }

local function Has(lib) return LibStub and LibStub(lib, true) ~= nil end
local function Say(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end end
local function OnLogin(fn)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() C_Timer.After(5, fn) end)
end

local missing = {}
for _, lib in ipairs(ACE) do if not Has(lib) then table.insert(missing, lib) end end

if #missing == 0 then
    if not Has("LibDeflate") then
        OnLogin(function()
            Say("|cffffd100FellowshipSync:|r LibDeflate is missing, so some sync messages from other players can't be read. "
                .. "Reinstall FellowshipSync from CurseForge, or install LibDeflate as an addon.")
        end)
    end
    return
end

addonTable.libsMissing = missing

-- A harmless stand-in, so the rest of the addon's files load without errors.
local stub
stub = setmetatable({}, {
    __index = function(_, key) if type(key) == "string" then return stub end end,
    __newindex = function() end,
    __call = function() return stub end,
    __concat = function() return "" end,
    __tostring = function() return "" end,
})
addonTable.FellowshipSync = stub

local MESSAGE = "|cffff5555FellowshipSync could not start:|r libraries are missing (" .. table.concat(missing, ", ") .. "). "
    .. "Reinstall FellowshipSync from CurseForge, or install |cffffd100Ace3|r and |cffffd100LibDeflate|r as addons, then /reload."
local function Explain() Say(MESSAGE) end

if SlashCmdList then
    SLASH_FELLOWSHIPSYNCMISSING1 = "/fsync"
    SLASH_FELLOWSHIPSYNCMISSING2 = "/fellowshipsync"
    SlashCmdList.FELLOWSHIPSYNCMISSING = Explain
end
FellowshipSync_OnAddonCompartmentClick = Explain -- the Retail addon-compartment button
OnLogin(Explain)
