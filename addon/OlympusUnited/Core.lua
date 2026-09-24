local ADDON_NAME, OU = ...
local L = OU.L

local GOLD = "|cffffc84a"
local BLUE = "|cff59c7ff"
local RESET = "|r"

local function RefreshGuildTrust()
    if not OU.GuildTrust or not OU.DB then return end
    OU.GuildTrust.RefreshAuthority()
    local ok, guild = false, nil
    if type(GetGuildInfo) == "function" then ok, guild = pcall(GetGuildInfo, "player") end
    if ok and OU.Util.IsPlainString(guild) then
        OU.GuildTrust.Observe(guild, "local-visible", OU.Util.Now(), OU.DB)
    end
end

function OU.Print(message)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(GOLD .. "Olympus United" .. RESET .. "  " .. tostring(message))
    end
end

function OU.Result(ok, err, successMessage)
    if ok then
        if successMessage then OU.Print(successMessage) end
        return true
    end
    OU.Print("|cffff6b6b" .. tostring(err or L.CHAT_FALLBACK_ERROR) .. RESET)
    return false
end

function OU.StatusText()
    if not OU.DB or not OU.Runtime then return L.STATUS_LOADING end
    local identity = OU.Identity or OU.Util.PlayerIdentity()
    local role = identity.role == "member" and (GOLD .. L.STATUS_MEMBER .. RESET) or (BLUE .. L.STATUS_GUEST .. RESET)
    local connections = {}
    if IsInGuild and IsInGuild() then connections[#connections + 1] = L.STATUS_GUILD end
    if OU.DB.bridgeMode then connections[#connections + 1] = L.STATUS_LINKING end
    local linkCount = OU.Util.Count(OU.DB.bridges)
    if linkCount == 1 then
        connections[#connections + 1] = L.STATUS_LINK_ONE
    elseif linkCount > 1 then
        connections[#connections + 1] = L.STATUS_LINKS:format(linkCount)
    end
    local connection = #connections > 0 and table.concat(connections, "  •  ") or L.STATUS_OFFLINE
    return role .. "  •  " .. connection .. "  •  " .. L.STATUS_PEOPLE:format(OU.Util.Count(OU.Runtime.peers))
end

function OU.OnNetworkChange(change)
    if type(change) ~= "table" or type(change.kind) ~= "string" then return false end
    OU.State.Prune(OU.Runtime, OU.Util.Now())
    if OU.RefreshUI then OU.RefreshUI() end
    if not OU.DB.notifications then return true end

    if change.kind == "offer" then
        OU.Print(L.CHAT_LAYER_OFFER:format(OU.Util.ShortName(change.value.sender)))
    elseif change.kind == "event" then
        OU.Print(L.CHAT_NEW_EVENT:format(change.value.title, OU.Util.FormatStart(change.value.startsAt)))
    end
    return true
end

local controller = CreateFrame("Frame")
OU.Controller = controller

controller:RegisterEvent("ADDON_LOADED")
controller:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then return end
        OlympusUnitedDB = OU.State.EnsureDatabase(OlympusUnitedDB)
        OU.DB = OlympusUnitedDB
        OU.Runtime = OU.State.NewRuntime()
        OU.Identity = OU.Util.PlayerIdentity()

        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_GUILD_UPDATE")
        self:RegisterEvent("GUILD_ROSTER_UPDATE")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("FRIENDLIST_UPDATE")
        self:RegisterEvent("WHO_LIST_UPDATE")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        RefreshGuildTrust()
        if OU.ChatGuard then OU.ChatGuard.Start() end
        OU.Network.RegisterPrefix()
        if OU.CreateUI then OU.CreateUI() end
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function() OU.Network.SendHello() end)
        else
            OU.Network.SendHello()
        end
        if OU.Census then
            if C_Timer and C_Timer.After then C_Timer.After(3, function() OU.Census.Start() end)
            else OU.Census.Start() end
        end
        OU.Print(L.CHAT_READY)
    elseif event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
        OU.Network.OnAddonMessage(...)
    elseif event == "GUILD_ROSTER_UPDATE" then
        if OU.GuildRoster then OU.GuildRoster.OnEvent(event, ...) end
        OU.Identity = OU.Util.PlayerIdentity()
        RefreshGuildTrust()
        if OU.RefreshUI then OU.RefreshUI() end
    elseif event == "PLAYER_GUILD_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
        OU.Identity = OU.Util.PlayerIdentity()
        if event == "PLAYER_GUILD_UPDATE" then RefreshGuildTrust() end
        if OU.ChatGuard then OU.ChatGuard.OnEvent(event, ...) end
        OU.Network.SendHello()
        if event == "PLAYER_GUILD_UPDATE" and OU.Census then OU.Census.OnGuildChanged() end
        if OU.RefreshUI then OU.RefreshUI() end
    elseif OU.ChatGuard then
        OU.ChatGuard.OnEvent(event, ...)
    end
end)

OU._Test = OU._Test or {}
OU._Test.Controller = controller
