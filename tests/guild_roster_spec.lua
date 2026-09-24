local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")

local now, timers = 600000, {}
function GetServerTime() return now end
function GetTime() return now end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
local SECRET = "\0SECRET\0"
local SECRET_TABLE = {}
function issecretvalue(value) return value == SECRET or value == SECRET_TABLE end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }
Enum = { ClubMemberPresence = { Online = 1, OnlineMobile = 2, Away = 3, Busy = 4, Offline = 5, Unknown = 6 } }

local ids = { 11, 12 }
local members = {
    [11] = setmetatable({ name = "Athena-Forever", presence = 1 }, { __index = function(_, key) error("unexpected member field read: " .. tostring(key)) end }),
    [12] = setmetatable({ name = "Zeus-Forever", presence = 5 }, { __index = function(_, key) error("unexpected member field read: " .. tostring(key)) end }),
}
C_GuildInfo = { GuildRoster = function() end }
C_Club = {
    GetGuildClubId = function() return 9 end,
    GetClubInfo = function() return { name = "Olympus I", memberCount = 2 } end,
    GetClubMembers = function() return ids end,
    GetMemberInfo = function(_, id) return members[id] end,
}

local OU = {}
assert(loadfile(root .. "/addon/OlympusUnited/Util.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/CensusLogic.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Protocol.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/GuildRoster.lua"))("OlympusUnited", OU)

local result = OU.GuildRoster.ReadComplete()
assert(result.ok and result.total == 2 and result.online == 1, "complete name/presence roster should capture")
assert(result.names[1] == "Athena-Forever", "names should be deterministic")

local callbackResult
assert(OU.GuildRoster.Request(function(value) callbackResult = value end), "roster request should start")
assert(#timers == 1 and timers[1].delay == 10, "request should install a ten-second timeout")
assert(OU.GuildRoster.OnEvent("GUILD_ROSTER_UPDATE"), "roster event should complete the pending request")
assert(callbackResult and callbackResult.ok, "event completion should return a complete snapshot")
timers[1].callback()
assert(callbackResult.ok, "stale timeout cannot replace an event result")

members[12] = { name = SECRET, presence = 5 }
assert(OU.GuildRoster.ReadComplete().ok == false, "secret names fail closed")
members[12] = { name = "Athena-Forever", presence = 5 }
assert(OU.GuildRoster.ReadComplete().reason == "duplicate-name", "duplicate normalized names fail closed")
members[12] = { name = "Zeus-Forever", presence = 6 }
result = OU.GuildRoster.ReadComplete()
assert(result.ok and result.online == nil, "unknown presence keeps the roster but makes online unavailable")
C_Club.GetClubInfo = function() return SECRET_TABLE end
assert(OU.GuildRoster.ReadComplete().reason == "club-info", "secret club-info tables fail closed before indexing")
C_Club.GetClubInfo = function() return { name = "Olympus I", memberCount = 2 } end
C_Club.GetClubMembers = function() return SECRET_TABLE end
assert(OU.GuildRoster.ReadComplete().reason == "member-list", "secret member-list tables fail closed before length reads")
C_Club.GetClubMembers = function() return ids end
C_Club.GetMemberInfo = function() return SECRET_TABLE end
assert(OU.GuildRoster.ReadComplete().reason == "member-info", "secret member-info tables fail closed before indexing")
C_Club.GetMemberInfo = function(_, id) return members[id] end
C_Club.GetClubInfo = function() return { name = "Olympus I", memberCount = 3 } end
assert(OU.GuildRoster.ReadComplete().reason == "count-mismatch", "partial roster counts fail closed")
C_Club.GetMemberInfo = nil
local capable, reason = OU.GuildRoster.Capabilities()
assert(not capable and reason == "missing-api", "missing capabilities fail closed without legacy guesses")

C_Club.GetMemberInfo = function(_, id) return members[id] end
C_Club.GetClubInfo = function() return { name = "Olympus I", memberCount = 2 } end
callbackResult = nil
assert(OU.GuildRoster.Request(function(value) callbackResult = value end))
timers[#timers].callback()
assert(callbackResult and callbackResult.reason == "timeout", "timeout returns a typed unavailable result")

print("Olympus United guild roster tests passed")
