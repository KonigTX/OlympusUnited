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
local RUNTIME_TTL = 86400
local MAX_GUID_CACHE = 2000
local MAX_OLYMPUS_CACHE = 4000
local MAX_OLYMPUS_SOURCES = OU.State.LIMITS.PARTICIPATING_GUILDS

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

    local candidates, now = {}, OU.Util.Now()
    for _, entry in pairs(type(database.chat.knownPlayers) == "table" and database.chat.knownPlayers or {}) do
        if type(entry) == "table" and PlainString(entry.name) and PlainString(entry.guild)
            and OU.Util.Trim(entry.guild) ~= "" and type(entry.seenAt) == "number" and not Secret(entry.seenAt) then
            local key = OU.Util.NormalizeName(entry.name)
            if key and entry.seenAt >= 0 and entry.seenAt <= now + 60 and now - entry.seenAt <= RETAIN_SECONDS then
                candidates[#candidates + 1] = {
                    key = key,
                    name = OU.Util.Trim(entry.name),
                    guild = OU.Util.Trim(entry.guild),
                    seenAt = math.max(0, math.floor(entry.seenAt)),
                }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
        return a.key < b.key
    end)
    database.chat.knownPlayers = {}
    for _, entry in ipairs(candidates) do
        if not database.chat.knownPlayers[entry.key] and OU.Util.Count(database.chat.knownPlayers) < MAX_KNOWN_PLAYERS then
            database.chat.knownPlayers[entry.key] = { name = entry.name, guild = entry.guild, seenAt = entry.seenAt }
        end
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
            and entry.seenAt >= 0 and entry.seenAt <= now + 60 and now - entry.seenAt <= RETAIN_SECONDS then
            entries[#entries + 1] = { key = key, entry = entry }
        else
            known[key] = nil
        end
    end
    table.sort(entries, function(a, b) return a.entry.seenAt > b.entry.seenAt end)
    for index = MAX_KNOWN_PLAYERS + 1, #entries do known[entries[index].key] = nil end
    return math.min(#entries, MAX_KNOWN_PLAYERS)
end

local function PruneRosterSources(key, entry, database, now)
    if type(key) ~= "string" or type(entry) ~= "table" or Secret(entry)
        or type(entry.sources) ~= "table" or Secret(entry.sources) then return false end
    local valid = {}
    for guildKey, seenAt in pairs(entry.sources) do
        if PlainString(guildKey) and OU.Util.NormalizeGuild(guildKey) == guildKey
            and type(seenAt) == "number" and not Secret(seenAt)
            and now >= seenAt and now - seenAt <= RUNTIME_TTL
            and OU.Util.IsParticipatingGuild(guildKey, database) then
            valid[#valid + 1] = { key = guildKey, seenAt = seenAt }
        else
            entry.sources[guildKey] = nil
        end
    end
    table.sort(valid, function(a, b)
        if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
        return a.key < b.key
    end)
    for index = MAX_OLYMPUS_SOURCES + 1, #valid do entry.sources[valid[index].key] = nil end
    if #valid == 0 then return false end
    entry.seenAt = valid[1].seenAt
    return true
end

function Guard.PruneRuntime(now, database)
    database = database or OU.DB
    now = SafeNumber(now, OU.Util.Now())
    for guid, entry in pairs(runtime.guidToName) do
        if type(entry) ~= "table" or not PlainString(entry.key) or type(entry.seenAt) ~= "number"
            or now < entry.seenAt or now - entry.seenAt > RUNTIME_TTL then runtime.guidToName[guid] = nil end
    end
    for key, entry in pairs(runtime.olympusNames) do
        if not PruneRosterSources(key, entry, database, now) then runtime.olympusNames[key] = nil end
    end
end

function Guard.OnGuildTrustChanged(database, now)
    Guard.PruneRuntime(now, database)
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
    if OU.GuildTrust then OU.GuildTrust.Observe(guild, "local-visible", now, database) end
    Guard.Prune(database, now)
    if not known[key] and OU.Util.Count(known) >= MAX_KNOWN_PLAYERS then return false, "full" end
    known[key] = { name = OU.Util.Trim(name), guild = guild, seenAt = now }
    Guard.PruneRuntime(now)
    if PlainString(guid) and guid ~= "" and (runtime.guidToName[guid] or OU.Util.Count(runtime.guidToName) < MAX_GUID_CACHE) then
        runtime.guidToName[guid] = { key = key, seenAt = now }
    end
    return true, OU.Util.IsParticipatingGuild(guild) and "olympus" or "outside"
end

function Guard.ImportRoster(names, guild, now, database)
    database = database or OU.DB
    local guildKey = PlainString(guild) and OU.Util.NormalizeGuild(guild) or nil
    if type(names) ~= "table" or Secret(names) or not guildKey
        or not OU.Util.IsParticipatingGuild(guildKey, database) then
        return 0
    end
    now = math.max(0, math.floor(SafeNumber(now, OU.Util.Now())))
    Guard.PruneRuntime(now, database)
    local imported = 0
    for index = 1, math.min(#names, 1000) do
        if PlainString(names[index]) then
            local key = OU.Util.NormalizeName(names[index])
            if key then
                local entry = runtime.olympusNames[key]
                if not entry and OU.Util.Count(runtime.olympusNames) < MAX_OLYMPUS_CACHE then
                    entry = { seenAt = now, sources = {} }
                    runtime.olympusNames[key] = entry
                end
                if entry and (entry.sources[guildKey] or OU.Util.Count(entry.sources) < MAX_OLYMPUS_SOURCES) then
                    entry.sources[guildKey] = now
                    entry.seenAt = math.max(tonumber(entry.seenAt) or 0, now)
                    imported = imported + 1
                end
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
    local guildOK, guild = false, nil
    if type(GetGuildInfo) == "function" then guildOK, guild = pcall(GetGuildInfo, unit) end
    if not guildOK or not PlainString(guild) or OU.Util.Trim(guild) == "" then return false, "unknown-guild" end
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
    local guidEntry = PlainString(guid) and runtime.guidToName[guid] or nil
    if type(guidEntry) == "table" and type(guidEntry.seenAt) == "number" and now >= guidEntry.seenAt
        and now - guidEntry.seenAt <= RUNTIME_TTL then key = guidEntry.key end
    local olympusSeen = key and runtime.olympusNames[key]
    if olympusSeen and PruneRosterSources(key, olympusSeen, database, now) then return "olympus" end
    if key and olympusSeen then runtime.olympusNames[key] = nil end
    local known = KnownPlayers(database)
    local entry = known and key and known[key]
    if type(entry) ~= "table" or not PlainString(entry.guild) or type(entry.seenAt) ~= "number"
        or Secret(entry.seenAt) or now < entry.seenAt or now - entry.seenAt > FRESH_SECONDS then
        return "unknown"
    end
    return OU.Util.IsParticipatingGuild(entry.guild) and "olympus" or "outside"
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
    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
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
    Guard.PruneRuntime(OU.Util.Now())
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
    RUNTIME_TTL = RUNTIME_TTL,
    MAX_GUID_CACHE = MAX_GUID_CACHE,
    MAX_OLYMPUS_CACHE = MAX_OLYMPUS_CACHE,
    MAX_OLYMPUS_SOURCES = MAX_OLYMPUS_SOURCES,
    Runtime = runtime,
    ChatFilter = ChatFilter,
    PruneRosterSources = PruneRosterSources,
}
