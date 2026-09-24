local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")
local now = 500000
local units = {
    player = { name = "Zeus", realm = "Forever", guild = "Olympus I", guid = "Player-Self" },
    target = { name = "Outsider", realm = "Forever", guild = "Other Guild", guid = "Player-Outside" },
    party1 = { name = "Teammate", realm = "Forever", guild = "Other Guild", guid = "Player-Team" },
}
local whoResults = {
    { fullName = "WhoOutside-Forever", fullGuildName = "Another Guild" },
    { fullName = "WhoOlympus-Forever", fullGuildName = "Olympus II" },
}
local filters = {}
unpack = unpack or table.unpack

function GetServerTime() return now end
function GetTime() return now end
function GetNormalizedRealmName() return "Forever" end
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) return units[unit] ~= nil end
function UnitFullName(unit)
    local value = units[unit]
    if not value then return nil end
    return value.name, value.realm
end
function UnitName(unit)
    local value = units[unit]
    return value and value.name or nil
end
function UnitGUID(unit)
    local value = units[unit]
    return value and value.guid or nil
end
function GetGuildInfo(unit)
    local value = units[unit]
    return value and value.guild or nil
end
function IsGuildLeader() return true end
C_GuildInfo = { IsGuildOfficer = function() return false end }

ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        assert(filters[event] == nil, "each chat filter should be installed once")
        filters[event] = callback
    end,
}

C_FriendList = {
    GetNumFriends = function() return 1 end,
    GetFriendInfoByIndex = function(index)
        if index == 1 then return { name = "Friend-Forever", guid = "Player-Friend" } end
    end,
    GetNumWhoResults = function() return #whoResults, #whoResults end,
    GetWhoInfo = function(index) return whoResults[index] end,
}

local OU = {}
assert(loadfile(root .. "/addon/OlympusUnited/Util.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/State.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/GuildTrust.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/ChatGuard.lua"))("OlympusUnited", OU)

OU.DB = OU.State.EnsureDatabase({ guildGovernance = {
    ["olympus i"] = { displayName = "Olympus I", state = "approved", firstSeenAt = now - 10,
        lastSeenAt = now, evidenceMask = 1, observations = 1, deniedEvidenceMask = 0,
        generation = 1, decisionId = "g-guard-1", decidedAt = now, sourceClass = "local-officer" },
    ["olympus ii"] = { displayName = "Olympus II", state = "approved", firstSeenAt = now - 10,
        lastSeenAt = now, evidenceMask = 1, observations = 1, deniedEvidenceMask = 0,
        generation = 1, decisionId = "g-guard-2", decidedAt = now, sourceClass = "local-officer" },
} })
OU.Identity = { name = "Zeus-Forever", guild = "Olympus I", role = "member" }
assert(OU.ChatGuard.Start(), "chat guard should install through Blizzard's supported filter API")
assert(OU.Util.Count(filters) == 6 and filters.CHAT_MSG_CHANNEL and filters.CHAT_MSG_WHISPER,
    "only public chat and incoming whispers should be filtered")

OU.ChatGuard.SetEnabled(true)
assert(OU.ChatGuard.Classify("Outsider-Forever", "Player-Outside", now) == "outside",
    "observed non-Olympus guild members should be classified")
assert(OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Outsider-Forever", "Player-Outside", now),
    "confirmed non-Olympus players should be hidden from public channels")
assert(OU.ChatGuard.ShouldMute("CHAT_MSG_WHISPER", "Outsider-Forever", "Player-Outside", now),
    "confirmed non-Olympus incoming whispers should be hidden")
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_GUILD", "Outsider-Forever", "Player-Outside", now),
    "guild, party, raid, and instance contexts should remain untouched")
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Mystery-Forever", "Player-Mystery", now),
    "unknown players must remain visible instead of being guessed outside Olympus")

OU.ChatGuard.Record("Friend-Forever", "Other Guild", "Player-Friend", now)
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_WHISPER", "Friend-Forever", "Player-Friend", now),
    "friends should remain visible")
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Teammate-Forever", "Player-Team", now),
    "current group members should remain visible")

assert(OU.ChatGuard.ImportRoster({ "Athena" }, "Olympus II", now) == 1,
    "explicit Olympus Census rosters should improve the positive member cache")
assert(OU.ChatGuard.Classify("Athena-Forever", nil, now) == "olympus",
    "imported Olympus members should never be muted")
assert(OU.DB.chat.knownPlayers["athena-forever"] == nil,
    "Census member names should remain session-only")
assert(not OU.ChatGuard.Record("Unguilded-Forever", "", nil, now),
    "missing guild data should never be treated as proof of non-Olympus membership")

local primaryDB, primaryGuild = OU.DB, units.player.guild
units.player.guild = "OLYMPUS"
local function FreshTrustDB()
    return OU.State.EnsureDatabase({})
end
local function Approve(database, guild, at)
    assert(OU.GuildTrust.Observe(guild, "local-visible", at, database))
    local ok, decision = OU.GuildTrust.Decide("approve", guild, at, database)
    assert(ok, "the exact-root leader fixture should approve a reviewed guild")
    return decision
end

local denyDB = FreshTrustDB()
Approve(denyDB, "Olympus Denied", now)
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "DeniedMember-Forever" }, "Olympus Denied", now, denyDB) == 1
    and OU.ChatGuard.Classify("DeniedMember-Forever", nil, now, denyDB) == "olympus",
    "an approved exact guild may contribute a session-only positive Census name")
assert(OU.GuildTrust.Decide("deny", "Olympus Denied", now + 1, denyDB))
assert(OU.ChatGuard.Classify("DeniedMember-Forever", nil, now + 1, denyDB) ~= "olympus",
    "Deny must immediately revoke positive Census-name classification")
OU.ChatGuard.OnGuildTrustChanged(denyDB, now + 1)
assert(not OU.ChatGuard._Test.Runtime.olympusNames["deniedmember-forever"],
    "the trust-change notification should eagerly remove a denied guild's stale cache source")

local reviewDB = FreshTrustDB()
Approve(reviewDB, "Olympus Review", now + 2)
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "ReviewMember-Forever" }, "Olympus Review", now + 2, reviewDB) == 1)
assert(OU.GuildTrust.Decide("review", "Olympus Review", now + 3, reviewDB))
assert(OU.ChatGuard.Classify("ReviewMember-Forever", nil, now + 3, reviewDB) ~= "olympus",
    "Reconsider must independently fail closed against the current exact allowlist")

local conflictDB = FreshTrustDB()
Approve(conflictDB, "Olympus Conflict", now + 4)
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "ConflictMember-Forever" }, "Olympus Conflict", now + 4, conflictDB) == 1)
local conflictMessage = { id = "g-chatguard-conflict", fields = {
    "olympus", "olympus conflict", "Olympus Conflict", "deny", 3, "g-wrong", now + 5,
} }
local conflictOK, conflictReason = OU.GuildTrust.ApplyRemote(conflictMessage, now + 5, conflictDB)
assert(not conflictOK and conflictReason == "decision-conflict"
    and OU.ChatGuard.Classify("ConflictMember-Forever", nil, now + 5, conflictDB) ~= "olympus",
    "a governance conflict must immediately revoke the former guild's positive cache source")

local sharedDB = FreshTrustDB()
Approve(sharedDB, "Olympus Shared A", now + 6)
Approve(sharedDB, "Olympus Shared B", now + 7)
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "SharedMember-Forever" }, "Olympus Shared A", now + 7, sharedDB) == 1)
assert(OU.ChatGuard.ImportRoster({ "SharedMember-Forever" }, "Olympus Shared B", now + 7, sharedDB) == 1)
assert(OU.Util.Count(OU.ChatGuard._Test.Runtime.olympusNames["sharedmember-forever"].sources) == 2,
    "one cached player should retain bounded exact sources from two approved guilds")
assert(OU.GuildTrust.Decide("deny", "Olympus Shared A", now + 8, sharedDB))
assert(OU.ChatGuard.Classify("SharedMember-Forever", nil, now + 8, sharedDB) == "olympus",
    "revoking one source must preserve classification from another still-approved exact guild")
assert(OU.GuildTrust.Decide("review", "Olympus Shared B", now + 9, sharedDB))
assert(OU.ChatGuard.Classify("SharedMember-Forever", nil, now + 9, sharedDB) ~= "olympus",
    "classification must fail open once every observed source loses approval")

local rootDB = FreshTrustDB()
Approve(rootDB, "Olympus Root Companion", now + 10)
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "RootMember-Forever" }, "OLYMPUS", now + 10, rootDB) == 1)
assert(OU.ChatGuard.ImportRoster({ "RootMember-Forever" }, "Olympus Root Companion", now + 10, rootDB) == 1)
assert(OU.GuildTrust.Decide("deny", "Olympus Root Companion", now + 11, rootDB))
assert(OU.ChatGuard.Classify("RootMember-Forever", nil, now + 11, rootDB) == "olympus",
    "revoking a sister guild must not invalidate an independently observed root-guild source")

local pendingDB = FreshTrustDB()
assert(OU.GuildTrust.Observe("Olympus Pending", "local-visible", now + 12, pendingDB))
OU.ChatGuard._Test.Runtime.olympusNames = {}
assert(OU.ChatGuard.ImportRoster({ "PendingMember-Forever" }, "Olympus Pending", now + 12, pendingDB) == 0
    and OU.ChatGuard.Classify("PendingMember-Forever", nil, now + 12, pendingDB) == "unknown",
    "a candidate or pending guild must never create a positive roster-cache source")

OU.ChatGuard._Test.Runtime.olympusNames = {}
local ttlStart = now + 20
assert(OU.ChatGuard.ImportRoster({ "TtlMember-Forever" }, "OLYMPUS", ttlStart, rootDB) == 1)
OU.ChatGuard.PruneRuntime(ttlStart + OU.ChatGuard._Test.RUNTIME_TTL, rootDB)
assert(OU.ChatGuard.Classify("TtlMember-Forever", nil,
    ttlStart + OU.ChatGuard._Test.RUNTIME_TTL, rootDB) == "olympus",
    "a positive source remains valid at the exact 24-hour boundary")
OU.ChatGuard.PruneRuntime(ttlStart + OU.ChatGuard._Test.RUNTIME_TTL + 1, rootDB)
assert(OU.ChatGuard.Classify("TtlMember-Forever", nil,
    ttlStart + OU.ChatGuard._Test.RUNTIME_TTL + 1, rootDB) == "unknown",
    "a positive source expires immediately after 24 hours")
OU.ChatGuard._Test.Runtime.olympusNames = {}
units.player.guild, OU.DB = primaryGuild, primaryDB

assert(OU.ChatGuard.ReadWhoResults() == 2,
    "existing Who results should be consumed without launching or replacing Who queries")
assert(OU.ChatGuard.Classify("WhoOutside-Forever", nil, now) == "outside"
    and OU.ChatGuard.Classify("WhoOlympus-Forever", nil, now) == "olympus",
    "Who results should update both sides of the guild classification")
OU.ChatGuard.Record("Lookalike-Forever", "Not Olympus", nil, now)
OU.ChatGuard.Record("Suffix-Forever", "Olympus Scammers", nil, now)
OU.ChatGuard.Record("Mountain-Forever", "Mount Olympus", nil, now)
assert(OU.ChatGuard.Classify("Lookalike-Forever", nil, now) == "outside"
    and OU.ChatGuard.Classify("Suffix-Forever", nil, now) == "outside"
    and OU.ChatGuard.Classify("Mountain-Forever", nil, now) == "outside",
    "lookalike guild names must never enter the positive classification")
assert(OU.DB.guildGovernance["not olympus"].state == "pending"
    and OU.DB.guildGovernance["olympus scammers"].state == "pending"
    and OU.DB.guildGovernance["mount olympus"].state == "pending",
    "passive chat-guard observations create review candidates without positive classification")
local suppressed = OU.DB.guildGovernance["not olympus"]
suppressed.state = "denied"
suppressed.deniedEvidenceMask = suppressed.evidenceMask
suppressed.generation, suppressed.decisionId, suppressed.decidedAt, suppressed.sourceClass =
    1, "g-guard-deny", now, "local-officer"
OU.ChatGuard.Record("Lookalike-Forever", "Not Olympus", nil, now + 1)
assert(suppressed.state == "denied", "a repeated local-visible source remains suppressed after denial")
OU.GuildTrust.Observe("Not Olympus", "configured-connector", now + 2, OU.DB)
assert(suppressed.state == "pending" and not OU.Util.IsParticipatingGuild("Not Olympus"),
    "a materially new connector evidence bit reopens review but never positive classification")
for key in pairs(suppressed) do
    assert(key ~= "name" and key ~= "guid" and key ~= "origin" and key ~= "connector" and key ~= "message",
        "candidate state must not persist player identity or message content")
end

local args = { "hello", "Outsider-Forever", "", "", "", "", 0, 0, "", 0, 123, "Player-Outside" }
assert(filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", unpack(args)) == true,
    "the installed filter should read the documented sender and GUID positions")

now = now + OU.ChatGuard._Test.FRESH_SECONDS + 1
assert(OU.ChatGuard.Classify("Outsider-Forever", "Player-Outside", now) == "unknown"
    and not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Outsider-Forever", "Player-Outside", now),
    "stale guild observations should fail open")
OU.ChatGuard.PruneRuntime(now)
assert(OU.Util.Count(OU.ChatGuard._Test.Runtime.guidToName) == 0
    and OU.Util.Count(OU.ChatGuard._Test.Runtime.olympusNames) == 0,
    "timestamped GUID and positive-name caches must expire after 24 hours")

OU.ChatGuard.SetEnabled(false)
now = 500000
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Outsider-Forever", "Player-Outside", now),
    "the option should disable immediately")
OU.ChatGuard.SetEnabled(true)
OU.Identity.role = "guest"
assert(not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Outsider-Forever", "Player-Outside", now),
    "the guard should stay inactive outside an Olympus guild")

local repaired = OU.ChatGuard.SanitizeDatabase({ chat = {
    muteNonOlympus = "yes",
    knownPlayers = {
        bad = "frame-like-value",
        valid = { name = "Valid-Forever", guild = "Other Guild", seenAt = now },
        unknown = { name = "Unknown-Forever", guild = "", seenAt = now },
    },
} })
assert(repaired.chat.muteNonOlympus == false and OU.Util.Count(repaired.chat.knownPlayers) == 1
    and repaired.chat.knownPlayers["valid-forever"],
    "saved state should retain only typed, bounded observations")

now = 700000
OU.ChatGuard._Test.Runtime.guidToName = {}
for index = 1, OU.ChatGuard._Test.MAX_GUID_CACHE + 1 do
    OU.ChatGuard.Record("One-Forever", "Other Guild", "Guid-" .. index, now, OU.DB)
end
assert(OU.Util.Count(OU.ChatGuard._Test.Runtime.guidToName) == OU.ChatGuard._Test.MAX_GUID_CACHE,
    "GUID cache must never exceed its hard bound")
OU.ChatGuard._Test.Runtime.olympusNames = {}
for batch = 1, 5 do
    local roster = {}
    for index = 1, 1000 do roster[index] = ("Member-%d-%d-Forever"):format(batch, index) end
    OU.ChatGuard.ImportRoster(roster, "Olympus II", now, OU.DB)
end
assert(OU.Util.Count(OU.ChatGuard._Test.Runtime.olympusNames) == OU.ChatGuard._Test.MAX_OLYMPUS_CACHE,
    "session-only positive-name cache must reject cap+1")
for _, entry in pairs(OU.ChatGuard._Test.Runtime.olympusNames) do
    assert(type(entry) == "table" and type(entry.sources) == "table"
        and OU.Util.Count(entry.sources) <= OU.ChatGuard._Test.MAX_OLYMPUS_SOURCES
        and entry.sources["olympus ii"] == now,
        "each bounded positive-name entry should retain only exact normalized source guild timestamps")
end

OU.ChatGuard._Test.Runtime.filtersInstalled = false
local modernFilters = ChatFrameUtil
ChatFrameUtil = nil
local installed, installError = OU.ChatGuard.InstallFilters()
assert(not installed and installError == "chat-filter-unavailable",
    "missing proven modern chat API must fail safely without a legacy global fallback")
ChatFrameUtil = modernFilters

print("Olympus United chat guard tests passed")
