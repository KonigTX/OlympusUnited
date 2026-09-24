local _, OU = ...

local Guard = {}
OU.ChatGuard = Guard

local FILTER_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_WHISPER = true,
}

local FRESH_SECONDS = 86400
local RETAIN_SECONDS = 2592000
local MAX_KNOWN_PLAYERS = 2000
local MAX_WHO_RESULTS = 200
local MAX_FRIENDS = 500

local runtime = {
    filtersInstalled = false,
    guidToName = {},
    groupNames = {},
    friendNames = {},
    friendGuids = {},
    olympusNames = {},
}

local function PlainString(value)
    return OU.Util.IsPlainString(value)
end

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function KnownPlayers(database)
    if type(database) ~= "table" or type(database.chat) ~= "table" then return nil end
    if type(database.chat.knownPlayers) ~= "table" then database.chat.knownPlayers = {} end
    return database.chat.knownPlayers
end

local function SafeNumber(value, fallback)
    if Secret(value) or type(value) ~= "number" then return fallback end
    return value
end

local function FullUnitName(unit)
    if not PlainString(unit) then return nil end
    local name, realm
    if UnitFullName then name, realm = UnitFullName(unit) end
    if not name and UnitName then name = UnitName(unit) end
    if not PlainString(name) or name == "" or (realm ~= nil and not PlainString(realm)) then return nil end
    if realm and realm ~= "" and not name:find("-", 1, true) then name = name .. "-" .. realm end
    return name
end

local function AddUnitName(target, unit)
    if UnitExists and not UnitExists(unit) then return end
    local name = FullUnitName(unit)
    local key = name and OU.Util.NormalizeName(name)
    if key then target[key] = true end
end

function Guard.SanitizeDatabase(database)
    if type(database) ~= "table" then return database end
    database.chat = type(database.chat) == "table" and database.chat or {}
    database.chat.muteNonOlympus = database.chat.muteNonOlympus == true

    local candidates = {}
    for _, entry in pairs(type(database.chat.knownPlayers) == "table" and database.chat.knownPlayers or {}) do
        if type(entry) == "table" and PlainString(entry.name) and PlainString(entry.guild)
            and OU.Util.Trim(entry.guild) ~= "" and type(entry.seenAt) == "number" and not Secret(entry.seenAt) then
            local key = OU.Util.NormalizeName(entry.name)
            if key then
                candidates[#candidates + 1] = {
                    key = key,
                    name = OU.Util.Trim(entry.name),
                    guild = OU.Util.Trim(entry.guild),
                    seenAt = math.max(0, math.floor(entry.seenAt)),
                }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.seenAt > b.seenAt end)
    database.chat.knownPlayers = {}
    for index = 1, math.min(#candidates, MAX_KNOWN_PLAYERS) do
        local entry = candidates[index]
        database.chat.knownPlayers[entry.key] = { name = entry.name, guild = entry.guild, seenAt = entry.seenAt }
    end
    return database
end

function Guard.Prune(database, now)
    local known = KnownPlayers(database)
    if not known then return 0 end
    now = SafeNumber(now, OU.Util.Now())
    local entries = {}
    for key, entry in pairs(known) do
        if type(key) == "string" and type(entry) == "table" and PlainString(entry.name)
            and PlainString(entry.guild) and type(entry.seenAt) == "number" and not Secret(entry.seenAt)
            and now - entry.seenAt <= RETAIN_SECONDS then
            entries[#entries + 1] = { key = key, entry = entry }
        else
            known[key] = nil
        end
    end
    table.sort(entries, function(a, b) return a.entry.seenAt > b.entry.seenAt end)
    for index = MAX_KNOWN_PLAYERS + 1, #entries do known[entries[index].key] = nil end
    return math.min(#entries, MAX_KNOWN_PLAYERS)
end

function Guard.Record(name, guild, guid, now, database)
    database = database or OU.DB
    local known = KnownPlayers(database)
    if not known or not PlainString(name) or not PlainString(guild) then return false, "invalid" end
    guild = OU.Util.Trim(guild)
    if guild == "" then return false, "unknown-guild" end
    local key = OU.Util.NormalizeName(name)
    if not key then return false, "invalid-name" end
    now = math.max(0, math.floor(SafeNumber(now, OU.Util.Now())))
    known[key] = { name = OU.Util.Trim(name), guild = guild, seenAt = now }
    if PlainString(guid) and guid ~= "" then runtime.guidToName[guid] = key end
    if OU.Util.Count(known) > MAX_KNOWN_PLAYERS + 100 then Guard.Prune(database, now) end
    return true, OU.Util.IsOlympusGuild(guild) and "olympus" or "outside"
end

function Guard.ImportRoster(names, guild, now, database)
    if type(names) ~= "table" or Secret(names) or not PlainString(guild) or not OU.Util.IsOlympusGuild(guild) then
        return 0
    end
    local imported = 0
    for index = 1, math.min(#names, 1000) do
        if PlainString(names[index]) then
            local key = OU.Util.NormalizeName(names[index])
            if key then
                runtime.olympusNames[key] = true
                imported = imported + 1
            end
        end
    end
    return imported
end

function Guard.ObserveUnit(unit)
    if not PlainString(unit) then return false, "invalid-unit" end
    if UnitExists and not UnitExists(unit) then return false, "missing-unit" end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return false, "not-player" end
    local name = FullUnitName(unit)
    if not name then return false, "unknown-name" end
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if not PlainString(guild) or OU.Util.Trim(guild) == "" then return false, "unknown-guild" end
    local guid = UnitGUID and UnitGUID(unit) or nil
    if guid ~= nil and not PlainString(guid) then guid = nil end
    return Guard.Record(name, guild, guid, OU.Util.Now())
end

function Guard.RefreshGroup()
    runtime.groupNames = {}
    AddUnitName(runtime.groupNames, "player")
    for index = 1, 4 do AddUnitName(runtime.groupNames, "party" .. index) end
    for index = 1, 40 do AddUnitName(runtime.groupNames, "raid" .. index) end
    Guard.ObserveUnit("player")
    for index = 1, 4 do Guard.ObserveUnit("party" .. index) end
    for index = 1, 40 do Guard.ObserveUnit("raid" .. index) end
    return OU.Util.Count(runtime.groupNames)
end

function Guard.RefreshFriends()
    runtime.friendNames, runtime.friendGuids = {}, {}
    if type(C_FriendList) ~= "table" or type(C_FriendList.GetNumFriends) ~= "function"
        or type(C_FriendList.GetFriendInfoByIndex) ~= "function" then return 0 end
    local ok, count = pcall(C_FriendList.GetNumFriends)
    if not ok or Secret(count) or type(count) ~= "number" then return 0 end
    count = math.min(MAX_FRIENDS, math.max(0, math.floor(count)))
    for index = 1, count do
        local infoOK, info = pcall(C_FriendList.GetFriendInfoByIndex, index)
        if infoOK and type(info) == "table" and not Secret(info) then
            if PlainString(info.name) then
                local key = OU.Util.NormalizeName(info.name)
                if key then runtime.friendNames[key] = true end
            end
            if PlainString(info.guid) and info.guid ~= "" then runtime.friendGuids[info.guid] = true end
        end
    end
    return OU.Util.Count(runtime.friendNames)
end

function Guard.ReadWhoResults()
    if type(C_FriendList) ~= "table" or type(C_FriendList.GetNumWhoResults) ~= "function"
        or type(C_FriendList.GetWhoInfo) ~= "function" then return 0 end
    local ok, count = pcall(C_FriendList.GetNumWhoResults)
    if not ok or Secret(count) or type(count) ~= "number" then return 0 end
    count = math.min(MAX_WHO_RESULTS, math.max(0, math.floor(count)))
    local learned = 0
    for index = 1, count do
        local infoOK, info = pcall(C_FriendList.GetWhoInfo, index)
        if infoOK and type(info) == "table" and not Secret(info)
            and PlainString(info.fullName) and PlainString(info.fullGuildName) and info.fullGuildName ~= "" then
            if Guard.Record(info.fullName, info.fullGuildName, nil, OU.Util.Now()) then learned = learned + 1 end
        end
    end
    return learned
end

function Guard.Classify(sender, guid, now, database)
    database = database or OU.DB
    if not PlainString(sender) then return "unknown" end
    now = SafeNumber(now, OU.Util.Now())
    local key = OU.Util.NormalizeName(sender)
    if PlainString(guid) and runtime.guidToName[guid] then key = runtime.guidToName[guid] end
    if key and runtime.olympusNames[key] then return "olympus" end
    local known = KnownPlayers(database)
    local entry = known and key and known[key]
    if type(entry) ~= "table" or not PlainString(entry.guild) or type(entry.seenAt) ~= "number"
        or Secret(entry.seenAt) or now < entry.seenAt or now - entry.seenAt > FRESH_SECONDS then
        return "unknown"
    end
    return OU.Util.IsOlympusGuild(entry.guild) and "olympus" or "outside"
end

function Guard.IsActive(database)
    database = database or OU.DB
    return type(database) == "table" and type(database.chat) == "table"
        and database.chat.muteNonOlympus == true and OU.Identity and OU.Identity.role == "member"
end

function Guard.IsExempt(sender, guid)
    local key = PlainString(sender) and OU.Util.NormalizeName(sender) or nil
    if key and (runtime.groupNames[key] or runtime.friendNames[key]) then return true end
    if PlainString(guid) and runtime.friendGuids[guid] then return true end
    return false
end

function Guard.ShouldMute(event, sender, guid, now, database)
    if not FILTER_EVENTS[event] or not Guard.IsActive(database) or not PlainString(sender) then return false end
    if guid ~= nil and not PlainString(guid) then guid = nil end
    if Guard.IsExempt(sender, guid) then return false end
    return Guard.Classify(sender, guid, now, database) == "outside"
end

local function ChatFilter(_, event, ...)
    local sender = select(2, ...)
    local guid = select(12, ...)
    return Guard.ShouldMute(event, sender, guid, OU.Util.Now())
end

function Guard.InstallFilters()
    if runtime.filtersInstalled then return true end
    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if type(add) ~= "function" then return false, "chat-filter-unavailable" end
    for event in pairs(FILTER_EVENTS) do add(event, ChatFilter) end
    runtime.filtersInstalled = true
    return true
end

function Guard.SetEnabled(enabled)
    if not OU.DB then return false end
    Guard.SanitizeDatabase(OU.DB)
    OU.DB.chat.muteNonOlympus = enabled == true
    if OU.DB.chat.muteNonOlympus then
        Guard.RefreshGroup()
        Guard.RefreshFriends()
    end
    return true
end

function Guard.Start()
    if not OU.DB then return false, "database-unavailable" end
    Guard.SanitizeDatabase(OU.DB)
    Guard.Prune(OU.DB, OU.Util.Now())
    Guard.RefreshGroup()
    Guard.RefreshFriends()
    Guard.ObserveUnit("target")
    Guard.ObserveUnit("mouseover")
    return Guard.InstallFilters()
end

function Guard.OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then return Guard.ObserveUnit("target") end
    if event == "UPDATE_MOUSEOVER_UNIT" then return Guard.ObserveUnit("mouseover") end
    if event == "NAME_PLATE_UNIT_ADDED" then return Guard.ObserveUnit(...) end
    if event == "GROUP_ROSTER_UPDATE" then return Guard.RefreshGroup() end
    if event == "FRIENDLIST_UPDATE" then return Guard.RefreshFriends() end
    if event == "WHO_LIST_UPDATE" then return Guard.ReadWhoResults() end
    if event == "PLAYER_GUILD_UPDATE" then return Guard.RefreshGroup() end
    return false
end

Guard._Test = {
    FILTER_EVENTS = FILTER_EVENTS,
    FRESH_SECONDS = FRESH_SECONDS,
    RETAIN_SECONDS = RETAIN_SECONDS,
    MAX_KNOWN_PLAYERS = MAX_KNOWN_PLAYERS,
    Runtime = runtime,
    ChatFilter = ChatFilter,
}
