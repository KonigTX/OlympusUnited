local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")

local currentTime = 100000
function GetServerTime() return currentTime end
function GetTime() return currentTime end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
function UnitFullName() return "Zeus", "Forever" end
function UnitLevel() return 60 end
function UnitClass() return "Warrior", "WARRIOR" end
function GetGuildInfo() return "Olympus I" end
function GetRealZoneText() return "Stormwind City" end

local OU = {}
assert(loadfile(root .. "/addon/OlympusUnited/Util.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/CensusLogic.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Strings.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Protocol.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/State.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/ChatGuard.lua"))("OlympusUnited", OU)

local special = "hello;world%forever"
local payload = assert(OU.Protocol.Encode("POST", "post-1", { special }, "Zeus-Forever", 0))
local decoded = assert(OU.Protocol.Decode(payload))
assert(decoded.type == "POST", "message type should round-trip")
assert(decoded.id == "post-1", "message id should round-trip")
assert(decoded.fields[1] == special, "escaped fields should round-trip")
assert(decoded.origin == "Zeus-Forever" and decoded.hops == 0, "relay envelope should round-trip")

local tooLong, longError = OU.Protocol.Encode("POST", "post-long", { string.rep("x", 251) })
assert(tooLong == nil and longError, "oversized payloads must be rejected")
assert(OU.Protocol.Decode("99" .. OU.Protocol._Test.Separator .. "POST" .. OU.Protocol._Test.Separator .. "x") == nil,
    "unknown protocol versions must be rejected")

local exact = assert(OU.Protocol.Encode("POST", "x", { string.rep("a", 237) }, "a", 0))
assert(#exact == 250 and OU.Protocol.Decode(exact), "250 encoded bytes must pass encode and decode")
assert(OU.Protocol.Decode(exact .. "a") == nil, "251 encoded bytes must be rejected by decode")
local escaped = assert(OU.Protocol.Encode("POST", "escape", { string.rep("%;", 20) }, "a", 0))
assert(#escaped > 40 and assert(OU.Protocol.Decode(escaped)).fields[1] == string.rep("%;", 20),
    "percent and semicolon expansion must be measured after escaping and round-trip")

local maxLease = assert(OU.Protocol.Encode("CLEASE", string.rep("a", 40), {
    string.rep("g", 32), "9999999999", "9999999999", "999999",
}, string.rep("o", 48), 0))
assert(#maxLease == 162, "maximum legal CLEASE header must be exactly 162 bytes")
local maxRequest = assert(OU.Protocol.Encode("CREQ", string.rep("a", 40), {
    string.rep("r", 20), string.rep("g", 32), string.rep("s", 20), string.rep("t", 48),
}, string.rep("o", 48), 0))
assert(#maxRequest == 222, "maximum legal CREQ header must be exactly 222 bytes")
local encoded16 = string.rep("%", 5) .. "c"
assert(#OU.Protocol._Test.Escape(encoded16) == 16, "fixture must expand to sixteen encoded bytes")
local exactPage = assert(OU.Protocol.Encode("CPAGE", string.rep("p", 40), {
    string.rep("r", 20), "1000", "1000", "1000", string.rep("a", 48), string.rep("b", 48), encoded16,
}, string.rep("o", 48), 0))
assert(#exactPage == 250 and OU.Protocol.Decode(exactPage), "exact 250-byte CPAGE with 48/48/16 encoded names must pass")
assert(OU.Protocol.Encode("CPAGE", string.rep("p", 40), {
    string.rep("r", 20), "1000", "1000", "1000", string.rep("a", 48), string.rep("b", 48), encoded16 .. "d",
}, string.rep("o", 48), 0) == nil, "251-byte CPAGE must fail encode")
assert(OU.Protocol.Encode("CLEASE", string.rep("a", 41), { "g", 1, 1, 1 }, "o", 0) == nil,
    "census envelope ids are capped at 40 ASCII bytes")

local database = OU.State.EnsureDatabase({})
assert(database.enabled == true, "network should default to enabled")
assert(database.bridgeMode == false, "bridge relay should be opt-in")
assert(type(database.bridges) == "table", "trusted bridges should have a saved table")
assert(database.chat.delaySeconds == 30, "Olympus Chat should default to a 30-second slow mode")
assert(database.chat.muteNonOlympus == false and type(database.chat.knownPlayers) == "table",
    "non-Olympus chat muting should be opt-in with a bounded saved cache")
assert(database.recruiting.cooldownMinutes == 30, "recruiting cooldown should default to 30 minutes")
assert(database.customLegacyValue == nil, "empty migration fixture remains additive")
local migrated = OU.State.EnsureDatabase({ enabled = false, customLegacyValue = "kept", recruiting = { cooldownMinutes = 45 } })
assert(migrated.enabled == false and migrated.customLegacyValue == "kept" and migrated.recruiting.cooldownMinutes == 45,
    "0.2.x settings and unknown keys must survive additive defaults")
assert(OU.State.SetChatDelay(migrated, 45) and migrated.chat.delaySeconds == 45,
    "valid chat delay should be saved")
assert(not OU.State.SetChatDelay(migrated, 2) and migrated.chat.delaySeconds == 45,
    "chat delay outside the safe range should be rejected")

local runtime = OU.State.NewRuntime()
assert(type(runtime.census) == "table" and type(runtime.census.routes) == "table", "census runtime is isolated and additive")
local helloPayload = assert(OU.Protocol.Encode("HELLO", "hello-1", { "member", "Olympus I", "Stormwind", 60, "WARRIOR" }))
local hello = assert(OU.Protocol.Decode(helloPayload))
local change = assert(OU.State.Apply(runtime, "Athena-Forever", hello, currentTime))
assert(change.kind == "peer", "hello should create a peer")
assert(runtime.peers["athena-forever"].guild == "Olympus I", "peer guild should be stored")

currentTime = currentTime + 2
local post = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-2", { "For Olympus" }))))
change = assert(OU.State.Apply(runtime, "Athena-Forever", post, currentTime))
assert(change.kind == "post" and #runtime.feed == 1, "post should enter the feed")
assert(OU.State.Apply(runtime, "Athena-Forever", post, currentTime + 2) == nil, "duplicates should be rejected")
local fastPost = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-3", { "Too soon" }))))
assert(OU.State.Apply(runtime, "Athena-Forever", fastPost, currentTime + 3) == nil and #runtime.feed == 1,
    "receiver-side slow mode should drop fast repeat messages from one author")
local otherPost = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-4", { "Different speaker" }))))
assert(OU.State.Apply(runtime, "Apollo-Forever", otherPost, currentTime + 3) and #runtime.feed == 2,
    "slow mode should be per speaker, not a global freeze")

currentTime = currentTime + 3
local layer = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("LREQ", "layer-1", {
    "Stormwind", "Need another layer", currentTime + 600,
}))))
change = assert(OU.State.Apply(runtime, "Athena-Forever", layer, currentTime))
assert(change.kind == "layer" and runtime.layers["layer-1"], "layer request should be active")

currentTime = currentTime + 3
local event = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("EVENT", "event-1", {
    currentTime + 900, "World boss", "Meet at the gate",
}))))
change = assert(OU.State.Apply(runtime, "Athena-Forever", event, currentTime))
assert(change.kind == "event" and runtime.events["event-1"], "event should be active")

assert(OU.State.ContactStatus(database, runtime, "Target", currentTime) == "available",
    "new recruiting targets should be available")
OU.State.MarkContacted(database, "Target", currentTime)
local status, remaining = OU.State.ContactStatus(database, runtime, "Target", currentTime + 10)
assert(status == "cooldown" and remaining > 0, "recent contacts should be cooling down")
database.recruiting.doNotContact["blocked-forever"] = true
assert(OU.State.ContactStatus(database, runtime, "Blocked", currentTime) == "do-not-contact",
    "private do-not-contact entries must win")

currentTime = currentTime + 1000
OU.State.Prune(runtime, currentTime)
assert(runtime.layers["layer-1"] == nil, "expired layer requests should be pruned")

print("Olympus United protocol and state tests passed")
