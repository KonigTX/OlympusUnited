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
assert(loadfile(root .. "/addon/OlympusUnited/ChatGuard.lua"))("OlympusUnited", OU)

OU.DB = OU.State.EnsureDatabase({})
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

assert(OU.ChatGuard.ReadWhoResults() == 2,
    "existing Who results should be consumed without launching or replacing Who queries")
assert(OU.ChatGuard.Classify("WhoOutside-Forever", nil, now) == "outside"
    and OU.ChatGuard.Classify("WhoOlympus-Forever", nil, now) == "olympus",
    "Who results should update both sides of the guild classification")

local args = { "hello", "Outsider-Forever", "", "", "", "", 0, 0, "", 0, 123, "Player-Outside" }
assert(filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", unpack(args)) == true,
    "the installed filter should read the documented sender and GUID positions")

now = now + OU.ChatGuard._Test.FRESH_SECONDS + 1
assert(OU.ChatGuard.Classify("Outsider-Forever", "Player-Outside", now) == "unknown"
    and not OU.ChatGuard.ShouldMute("CHAT_MSG_CHANNEL", "Outsider-Forever", "Player-Outside", now),
    "stale guild observations should fail open")

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

print("Olympus United chat guard tests passed")
