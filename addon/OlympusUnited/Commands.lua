local _, OU = ...
local L = OU.L

local function Help()
    OU.Print("|cffffc84a" .. L.HELP_HEADER .. "|r")
    OU.Print(L.HELP_OPEN)
    OU.Print(L.HELP_UPDATE)
    OU.Print(L.HELP_CHAT_DELAY)
    OU.Print(L.HELP_CHAT_MUTE)
    OU.Print(L.HELP_LAYER)
    OU.Print(L.HELP_EVENT)
    OU.Print(L.HELP_LINK)
    OU.Print(L.HELP_GUEST)
    OU.Print(L.HELP_NOTIFY)
    OU.Print(L.HELP_RECRUIT)
    OU.Print(L.HELP_DNC)
    OU.Print(L.HELP_STATUS)
    OU.Print(L.HELP_CENSUS)
end

local function SetChatMute(input)
    local value = OU.Util.Trim(input):lower()
    if value ~= "on" and value ~= "off" then OU.Print(L.HELP_CHAT_MUTE_USAGE); return end
    if value == "on" and (not OU.Identity or OU.Identity.role ~= "member") then
        OU.Print(L.HELP_CHAT_MUTE_USAGE)
        return
    end
    OU.ChatGuard.SetEnabled(value == "on")
    OU.Print(value == "on" and L.CHAT_MUTE_ON or L.CHAT_MUTE_OFF)
    if OU.RefreshUI then OU.RefreshUI() end
end

local function SetChatDelay(input)
    local ok, delay, changed = OU.State.SetChatDelay(OU.DB, OU.Util.Trim(input))
    if not ok then OU.Print(L.HELP_CHAT_DELAY_USAGE); return end
    if changed then OU.Print(L.CHAT_DELAY_SET:format(delay)) end
    if OU.RefreshUI then OU.RefreshUI() end
end

local function Bridge(input)
    local action, name = input:match("^(%S+)%s*(.-)$")
    action = (action or ""):lower()
    if action == "on" or action == "off" then
        OU.Network.SetBridgeMode(action == "on")
        OU.Print(OU.DB.bridgeMode and L.LINKING_ON or L.LINKING_OFF)
    elseif action == "add" and name ~= "" then
        local ok, err = OU.Network.AddBridge(name)
        OU.Result(ok, err, ok and L.CONNECTOR_ADDED:format(name) or nil)
    elseif action == "remove" and name ~= "" then
        local ok, err = OU.Network.RemoveBridge(name)
        OU.Result(ok, err, ok and L.CONNECTOR_REMOVED:format(name) or nil)
    elseif action == "list" then
        local count = 0
        for _, displayName in pairs(OU.DB.bridges) do
            count = count + 1
            OU.Print(L.LINK_LIST_ITEM:format(displayName))
        end
        if count == 0 then OU.Print(L.LINKS_NONE) end
    else
        OU.Print(L.HELP_LINK_USAGE)
    end
    if OU.RefreshUI then OU.RefreshUI() end
end

local function SetGuest(value)
    OU.DB.guestMode = value
    OU.Identity = OU.Util.PlayerIdentity()
    OU.Print(value and L.GUEST_ON or L.GUEST_OFF)
    if value then OU.Network.SendHello() end
    if OU.RefreshUI then OU.RefreshUI() end
end

local function DNC(input)
    local action, name = input:match("^(%S+)%s+(.+)$")
    action = action and action:lower() or ""
    local key = OU.Util.NormalizeName(name)
    if action == "add" and key then
        OU.DB.recruiting.doNotContact[key] = true
        OU.Print(L.DNC_ADDED:format(name))
    elseif action == "remove" and key then
        OU.DB.recruiting.doNotContact[key] = nil
        OU.Print(L.DNC_REMOVED:format(name))
    elseif action == "list" or input == "list" then
        local count = 0
        for player in pairs(OU.DB.recruiting.doNotContact) do
            count = count + 1
            OU.Print(L.DNC_LIST_ITEM:format(player))
        end
        if count == 0 then OU.Print(L.DNC_EMPTY) end
    else
        OU.Print(L.HELP_DNC_USAGE)
    end
end

local function Claim(name)
    name = OU.Util.Trim(name)
    if name == "" then OU.Print(L.HELP_CLAIM_USAGE) return end
    local ok, reason, detail = OU.Network.ClaimRecruit(name)
    if ok then
        OU.Print(L.CLAIM_SUCCESS:format(name))
    elseif reason == "do-not-contact" then
        OU.Print("|cffff6666" .. L.CLAIM_BLOCKED:format(name) .. "|r")
    elseif reason == "cooldown" then
        OU.Print(L.CLAIM_COOLDOWN:format(name, OU.Util.FormatAge(detail)))
    elseif reason == "claimed" then
        OU.Print(L.CLAIM_TAKEN:format(name, OU.Util.ShortName(detail.sender)))
    else
        OU.Result(false, reason)
    end
end

local function CensusCommand(input)
    input = OU.Util.Trim(input):lower()
    if input == "" or input == "open" then
        OU.Open("CENSUS")
    elseif input == "status" then
        local totals = OU.CensusLogic.Totals(OU.Runtime.census.summaries, OU.Util.Now())
        local online = totals.onlineKnown and tostring(totals.online) or "unavailable"
        OU.Print(L.CENSUS_STATUS:format(totals.current + totals.stale, totals.members, online))
    elseif input == "help" or input == "?" then
        OU.Print(L.CENSUS_HELP_1)
        OU.Print(L.CENSUS_HELP_2)
        OU.Print(L.CENSUS_HELP_3)
    else
        OU.Print(L.HELP_CENSUS)
    end
end

SLASH_OLYMPUSUNITED1 = "/ou"
SLASH_OLYMPUSUNITED2 = "/outh"
SLASH_OLYMPUSUNITED3 = "/olympusunited"

SlashCmdList.OLYMPUSUNITED = function(input)
    if not OU.DB then return end
    local command, rest = OU.Util.Trim(input):match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()

    if command == "" or command == "open" then
        OU.Toggle()
    elseif command == "say" or command == "chat" then
        OU.Result(OU.Network.Post(rest))
    elseif command == "slow" or command == "slowmode" then
        SetChatDelay(rest)
    elseif command == "mute" then
        SetChatMute(rest)
    elseif command == "layer" then
        OU.Result(OU.Network.RequestLayer(rest), nil, L.LAYER_REQUESTED)
    elseif command == "event" then
        local minutes, title = rest:match("^(%d+)%s+(.+)$")
        if not minutes then OU.Print(L.HELP_EVENT_USAGE)
        else OU.Result(OU.Network.CreateEvent(minutes, title, ""), nil, L.EVENT_SHARED) end
    elseif command == "bridge" then
        Bridge(rest)
    elseif command == "guest" and (rest == "on" or rest == "off") then
        SetGuest(rest == "on")
    elseif command == "notify" and (rest == "on" or rest == "off") then
        OU.DB.notifications = rest == "on"
        OU.Print(OU.DB.notifications and L.NOTIFICATIONS_ON or L.NOTIFICATIONS_OFF)
    elseif command == "claim" then
        Claim(rest)
    elseif command == "release" then
        OU.Result(OU.Network.ReleaseRecruit(rest), nil, L.CLAIM_RELEASED)
    elseif command == "dnc" then
        DNC(rest)
    elseif command == "status" then
        OU.Print(OU.StatusText())
        OU.Print(L.STATUS_COUNTS:format(
            #OU.Runtime.feed,
            OU.Util.Count(OU.Runtime.layers),
            OU.Util.Count(OU.Runtime.events),
            OU.Util.Count(OU.Runtime.claims)))
    elseif command == "census" then
        CensusCommand(rest)
    elseif command == "help" or command == "?" then
        Help()
    else
        Help()
    end
end
