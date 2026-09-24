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
assert(loadfile(root .. "/addon/OlympusUnited/GuildTrust.lua"))("OlympusUnited", OU)
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
local governancePayload = assert(OU.Protocol.Encode("GDEC", string.rep("d", 40), {
    "olympus", string.rep("g", 32), string.rep("g", 32), "approve", "2147483647", string.rep("p", 40), "9999999999",
}, string.rep("o", 48), 2))
assert(OU.Protocol.Decode(governancePayload), "maximum legal governance fields should round-trip within the v1 ceiling")
for _, fields in ipairs({
    { "OLYMPUS", "olympus i", "Olympus I", "approve", 1, "-", currentTime },
    { "olympus", "olympus i", "Olympus II", "approve", 1, "-", currentTime },
    { "olympus", "olympus", "OLYMPUS", "approve", 1, "-", currentTime },
    { "olympus", "olympus i", "Olympus I", "officer", 1, "-", currentTime },
    { "olympus", "olympus i", "Olympus I", "approve", 0, "-", currentTime },
    { "olympus", "olympus i", "Olympus I", "approve", 1, "bad_value", currentTime },
}) do
    assert(OU.Protocol.Encode("GDEC", "decision-1", fields, "Officer-Forever", 0) == nil,
        "malformed governance fields must fail strict encode validation")
end
local malformedGovernance = table.concat({ "1", "GDEC", "decision-2", "Officer-Forever", "1",
    "olympus", "olympus i", "Olympus II", "approve", "1", "-", tostring(currentTime) }, OU.Protocol._Test.Separator)
assert(OU.Protocol.Decode(malformedGovernance) == nil,
    "a malformed received governance declaration must fail strict decode validation")

local database = OU.State.EnsureDatabase({})
assert(database.enabled == true, "network should default to enabled")
assert(database.bridgeMode == false, "bridge relay should be opt-in")
assert(type(database.bridges) == "table", "trusted bridges should have a saved table")
assert(database.schemaVersion == OU.State.SCHEMA_VERSION and database.participatingGuilds.olympus == "OLYMPUS",
    "schema migration should centralize only the exact authorized production root")
assert(database.chat.delaySeconds == 30, "Olympus Chat should default to a 30-second slow mode")
assert(database.chat.muteNonOlympus == false and type(database.chat.knownPlayers) == "table",
    "non-Olympus chat muting should be opt-in with a bounded saved cache")
assert(database.recruiting.cooldownMinutes == 30, "recruiting cooldown should default to 30 minutes")
assert(database.customLegacyValue == nil, "unknown top-level keys must not enter the saved schema")
local adversarial = {
    enabled = false, guestMode = "yes", notifications = {}, bridgeMode = function() end,
    customLegacyValue = "discarded",
    bridges = { ["Athena-Forever"] = "Athena-Forever", bad = {}, alsoBad = string.rep("x", 80) },
    participatingGuilds = { [" OLYMPUS   I "] = " OLYMPUS   I ", lookalike = {} },
    guildGovernance = {
        ["olympus i"] = { displayName = "Olympus I", state = "approved", firstSeenAt = currentTime - 20,
            lastSeenAt = currentTime - 10, evidenceMask = 1, observations = 2, deniedEvidenceMask = 0,
            generation = 1, decisionId = "g-1", decidedAt = currentTime - 10, sourceClass = "local-officer",
            unknown = "discarded" },
        malformed = { displayName = {}, state = "approved" },
    },
    chat = {
        delaySeconds = 45, muteNonOlympus = "yes", unknown = "discarded",
        knownPlayers = {
            valid = { name = "Valid-Forever", guild = "Other Guild", seenAt = currentTime },
            bad = { name = {}, guild = "Other Guild", seenAt = currentTime },
        },
    },
    window = { point = "OFFSCREEN", x = 0/0, y = math.huge, unknown = true },
    recruiting = {
        cooldownMinutes = 45,
        contacted = { ["Target-Forever"] = currentTime - 60, bad = math.huge },
        doNotContact = { ["Blocked-Forever"] = true, falseEntry = "yes" },
        unknown = "discarded",
    },
}
local migrated = OU.State.EnsureDatabase(adversarial)
assert(migrated.enabled == false and migrated.guestMode == false and migrated.notifications == true
    and migrated.bridgeMode == false and migrated.customLegacyValue == nil,
    "booleans must preserve only exact typed legacy values and unknown keys must be removed")
assert(migrated.recruiting.cooldownMinutes == 45 and migrated.recruiting.contacted["target-forever"]
    and migrated.recruiting.doNotContact["blocked-forever"] and migrated.recruiting.unknown == nil,
    "supported recruiting data should survive only through typed normalized fields")
assert(migrated.window.point == "CENTER" and migrated.window.x == 0 and migrated.window.y == 0,
    "an invalid anchor or non-finite coordinate must reset the whole window position")
assert(migrated.chat.muteNonOlympus == false and migrated.chat.unknown == nil
    and migrated.chat.knownPlayers["valid-forever"] and OU.Util.Count(migrated.chat.knownPlayers) == 1,
    "chat state should repair types and preserve only sanitized known-player observations")
assert(migrated.participatingGuilds["olympus i"] == "Olympus I"
    and migrated.guildGovernance["olympus i"].unknown == nil and migrated.guildGovernance.malformed == nil,
    "only a typed current approved governance record may preserve a non-root allowlist entry")
local idempotent = OU.State.EnsureDatabase(migrated)
assert(idempotent.enabled == migrated.enabled and idempotent.window.point == migrated.window.point
    and idempotent.bridges["athena-forever"] == "Athena-Forever"
    and idempotent.participatingGuilds["olympus i"], "a second migration must be idempotent")
assert(OU.State.SetChatDelay(migrated, 45) and migrated.chat.delaySeconds == 45,
    "valid chat delay should be saved")
assert(not OU.State.SetChatDelay(migrated, 2) and migrated.chat.delaySeconds == 45,
    "chat delay outside the safe range should be rejected")

OU.DB = database
assert(OU.Util.IsParticipatingGuild("  olympus  ") and not OU.Util.IsParticipatingGuild("Not Olympus")
    and not OU.Util.IsParticipatingGuild("Olympus Scammers") and not OU.Util.IsParticipatingGuild("Mount Olympus")
    and not OU.Util.IsParticipatingGuild("ΟLYMPUS") and not OU.Util.IsParticipatingGuild("OLYMPUS\t"),
    "membership must be normalized exact matching with prefix, suffix, substring, and Unicode lookalikes rejected")
assert(OU.State.AddParticipatingGuild == nil and OU.State.RemoveParticipatingGuild == nil,
    "no public raw non-root allowlist mutator may bypass governance")
local bridgeDB = OU.State.EnsureDatabase({})
for index = 1, OU.State.LIMITS.BRIDGES do assert(OU.State.AddBridge(bridgeDB, "Bridge" .. index .. "-Forever")) end
assert(not OU.State.AddBridge(bridgeDB, "BridgeOverflow-Forever")
    and OU.Util.Count(bridgeDB.bridges) == OU.State.LIMITS.BRIDGES,
    "connector additions must reject cap+1")

local runtime = OU.State.NewRuntime()
assert(type(runtime.census) == "table" and type(runtime.census.routes) == "table", "census runtime is isolated and additive")

local governanceBase = currentTime
local function GovernanceRecord(display, state)
    local decided = state ~= "pending"
    return {
        displayName = display, state = state, firstSeenAt = governanceBase, lastSeenAt = governanceBase,
        evidenceMask = 1, observations = 1, deniedEvidenceMask = state == "denied" and 1 or 0,
        generation = decided and 1 or 0,
        decisionId = decided and ("g-periodic-" .. OU.Util.NormalizeGuild(display):gsub(" ", "-")) or nil,
        decidedAt = decided and governanceBase or nil,
        sourceClass = decided and "local-officer" or nil,
    }
end
local function AssertExactGuildMap(actual, expected, message)
    assert(OU.Util.Count(actual) == OU.Util.Count(expected), message .. " (count)")
    for key, display in pairs(expected) do assert(actual[key] == display, message .. " (" .. key .. ")") end
end
local governanceDB = OU.State.EnsureDatabase({})
governanceDB.guildGovernance = {
    ["olympus periodic pending"] = GovernanceRecord("Olympus Periodic Pending", "pending"),
    ["olympus periodic conflict"] = GovernanceRecord("Olympus Periodic Conflict", "conflict"),
    ["olympus periodic approved"] = GovernanceRecord("Olympus Periodic Approved", "approved"),
    ["olympus periodic absent"] = GovernanceRecord("Olympus Periodic Absent", "approved"),
    ["olympus periodic denied"] = GovernanceRecord("Olympus Periodic Denied", "denied"),
    ["olympus malformed state"] = { displayName = "Olympus Malformed State", state = "trusted",
        firstSeenAt = governanceBase, lastSeenAt = governanceBase, evidenceMask = 1, observations = 1,
        deniedEvidenceMask = 0, generation = 0 },
    ["olympus malformed private"] = { displayName = "Olympus Malformed Private", state = "pending",
        firstSeenAt = governanceBase, lastSeenAt = governanceBase, evidenceMask = 1, observations = 1,
        deniedEvidenceMask = 0, generation = 0, message = "must not persist" },
    ["olympus bad display"] = GovernanceRecord("Olympus Different Display", "approved"),
    ["Olympus NonNormalized"] = GovernanceRecord("Olympus NonNormalized", "approved"),
    [17] = GovernanceRecord("Olympus Numeric Key", "approved"),
    olympus = GovernanceRecord("OLYMPUS", "approved"),
}
governanceDB.participatingGuilds["olympus periodic orphan"] = "Olympus Periodic Orphan"
governanceDB.participatingGuilds["olympus periodic pending"] = "Olympus Periodic Pending"
governanceDB.participatingGuilds["olympus periodic conflict"] = "Olympus Periodic Conflict"
governanceDB.participatingGuilds["olympus periodic approved"] = "Wrong Approval Display"
governanceDB.participatingGuilds["olympus periodic denied"] = "Olympus Periodic Denied"
governanceDB.participatingGuilds[" OLYMPUS BAD KEY "] = "Olympus Bad Key"
governanceDB.participatingGuilds.olympus = "Wrong Root"
OU.DB = governanceDB
local governanceRuntime = OU.State.NewRuntime()
local staleParticipation = governanceDB.participatingGuilds

OU.State.Prune(governanceRuntime, governanceBase + OU.GuildTrust.PENDING_TTL - 1)
assert(governanceDB.guildGovernance["olympus periodic pending"]
    and governanceDB.guildGovernance["olympus periodic conflict"],
    "production State.Prune must retain pending and conflict records at TTL-1")
assert(not governanceDB.guildGovernance["olympus malformed state"]
    and not governanceDB.guildGovernance["olympus malformed private"]
    and not governanceDB.guildGovernance["olympus bad display"]
    and not governanceDB.guildGovernance["Olympus NonNormalized"]
    and not governanceDB.guildGovernance[17]
    and not governanceDB.guildGovernance.olympus
    and governanceDB.participatingGuilds.olympus == "OLYMPUS",
    "periodic governance maintenance must fail closed on malformed/private fields and keep the root immutable")
assert(governanceDB.participatingGuilds ~= staleParticipation,
    "periodic governance maintenance must atomically replace rather than incrementally edit participation")
AssertExactGuildMap(governanceDB.participatingGuilds, {
    olympus = "OLYMPUS",
    ["olympus periodic absent"] = "Olympus Periodic Absent",
    ["olympus periodic approved"] = "Olympus Periodic Approved",
}, "State.Prune must derive the exact canonical allowlist from current valid approvals")
for _, guild in ipairs({ "Olympus Periodic Orphan", "Olympus Periodic Pending", "Olympus Periodic Conflict",
    "Olympus Periodic Denied", "Olympus Malformed State", "Olympus Malformed Private",
    "Olympus Bad Display", "Olympus NonNormalized", "Olympus Numeric Key" }) do
    assert(not OU.Util.IsParticipatingGuild(guild, governanceDB),
        "no orphan, non-approved, or malformed key may retain trust before approval: " .. guild)
end

governanceDB.participatingGuilds.olympus = nil
OU.State.Prune(governanceRuntime, governanceBase + OU.GuildTrust.PENDING_TTL)
assert(governanceDB.guildGovernance["olympus periodic pending"]
    and governanceDB.guildGovernance["olympus periodic conflict"]
    and governanceDB.participatingGuilds.olympus == "OLYMPUS",
    "production State.Prune must retain pending and conflict records at the exact 30-day boundary")

OU.State.Prune(governanceRuntime, governanceBase + OU.GuildTrust.PENDING_TTL + 1)
assert(not governanceDB.guildGovernance["olympus periodic pending"]
    and not governanceDB.guildGovernance["olympus periodic conflict"],
    "production State.Prune must remove idle pending and conflict records just after 30 days")
assert(governanceDB.guildGovernance["olympus periodic approved"].state == "approved"
    and governanceDB.guildGovernance["olympus periodic absent"].state == "approved"
    and governanceDB.guildGovernance["olympus periodic denied"].state == "denied"
    and governanceDB.participatingGuilds["olympus periodic approved"] == "Olympus Periodic Approved"
    and governanceDB.participatingGuilds["olympus periodic absent"] == "Olympus Periodic Absent",
    "periodic pruning must preserve valid durable approvals and denials")
local stableGovernanceCount = OU.Util.Count(governanceDB.guildGovernance)
for _ = 1, 10 do
    OU.State.Prune(governanceRuntime, governanceBase + OU.GuildTrust.PENDING_TTL + 1)
end
assert(OU.Util.Count(governanceDB.guildGovernance) == stableGovernanceCount
    and stableGovernanceCount == 3 and OU.Util.Count(governanceDB.participatingGuilds) == 3,
    "repeated production maintenance must remain idempotent and bounded")
local malformedParticipationDB = {
    guildGovernance = { ["olympus projection"] = GovernanceRecord("Olympus Projection", "approved") },
    participatingGuilds = "malformed",
}
OU.DB = malformedParticipationDB
OU.State.Prune(governanceRuntime, governanceBase)
AssertExactGuildMap(malformedParticipationDB.participatingGuilds,
    { olympus = "OLYMPUS", ["olympus projection"] = "Olympus Projection" },
    "malformed participation must become the exact projection")
local missingParticipationDB = {
    guildGovernance = { ["olympus projection"] = GovernanceRecord("Olympus Projection", "approved") },
}
OU.DB = missingParticipationDB
OU.State.Prune(governanceRuntime, governanceBase)
AssertExactGuildMap(missingParticipationDB.participatingGuilds,
    { olympus = "OLYMPUS", ["olympus projection"] = "Olympus Projection" },
    "missing participation must become the exact projection")
for _, malformedGovernance in ipairs({ "malformed", false }) do
    local malformedGovernanceDB = {
        guildGovernance = malformedGovernance,
        participatingGuilds = { olympus = "Wrong Root", orphan = "Orphan" },
    }
    OU.DB = malformedGovernanceDB
    OU.State.Prune(governanceRuntime, governanceBase)
    AssertExactGuildMap(malformedGovernanceDB.participatingGuilds, { olympus = "OLYMPUS" },
        "malformed or missing governance must project to root-only")
end
local missingGovernanceDB = { participatingGuilds = { olympus = "Wrong Root", orphan = "Orphan" } }
OU.DB = missingGovernanceDB
OU.State.Prune(governanceRuntime, governanceBase)
AssertExactGuildMap(missingGovernanceDB.participatingGuilds, { olympus = "OLYMPUS" },
    "missing governance must project to root-only through State.Prune")
local loadedTrust = OU.GuildTrust
local missingModulePruneAt = governanceBase + OU.GuildTrust.PENDING_TTL + 2
OU.GuildTrust = nil
assert(pcall(OU.State.Prune, governanceRuntime, missingModulePruneAt),
    "State.Prune must remain load-order safe when the optional governance module is unavailable")
OU.GuildTrust = loadedTrust
OU.DB = nil
assert(pcall(OU.State.Prune, governanceRuntime, missingModulePruneAt),
    "State.Prune must remain safe when the saved database is unavailable")
OU.DB = database

local helloPayload = assert(OU.Protocol.Encode("HELLO", "hello-1", { "member", "Olympus I", "Stormwind", 60, "WARRIOR" }, "Athena-Forever", 0))
local hello = assert(OU.Protocol.Decode(helloPayload))
local change = assert(OU.State.Apply(runtime, "Athena-Forever", hello, currentTime))
assert(change.kind == "peer", "hello should create a peer")
assert(runtime.peers["athena-forever"].guild == "Olympus I", "peer guild should be stored")

currentTime = currentTime + 2
local post = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-2", { "For Olympus" }, "Athena-Forever", 0))))
change = assert(OU.State.Apply(runtime, "Athena-Forever", post, currentTime))
assert(change.kind == "post" and #runtime.feed == 1, "post should enter the feed")
assert(OU.State.Apply(runtime, "Athena-Forever", post, currentTime + 2) == nil, "duplicates should be rejected")
local fastPost = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-3", { "Too soon" }, "Athena-Forever", 0))))
assert(OU.State.Apply(runtime, "Athena-Forever", fastPost, currentTime + 3) == nil and #runtime.feed == 1,
    "receiver-side slow mode should drop fast repeat messages from one author")
local otherPost = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("POST", "post-4", { "Different speaker" }, "Apollo-Forever", 0))))
assert(OU.State.Apply(runtime, "Apollo-Forever", otherPost, currentTime + 3) and #runtime.feed == 2,
    "slow mode should be per speaker, not a global freeze")

currentTime = currentTime + 3
local layer = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("LREQ", "layer-1", {
    "Stormwind", "Need another layer", currentTime + 600,
}, "Athena-Forever", 0))))
change = assert(OU.State.Apply(runtime, "Athena-Forever", layer, currentTime))
assert(change.kind == "layer" and runtime.layers["layer-1"], "layer request should be active")

currentTime = currentTime + 3
local event = assert(OU.Protocol.Decode(assert(OU.Protocol.Encode("EVENT", "event-1", {
    currentTime + 900, "World boss", "Meet at the gate",
}, "Athena-Forever", 0))))
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

local bounded = OU.State.NewRuntime()
for index = 1, OU.State.LIMITS.DEDUPE do
    assert(OU.State.RememberSeen(bounded, "Origin-Forever", "id-" .. index, currentTime),
        "dedupe entries should admit through the exact cap")
end
assert(not OU.State.RememberSeen(bounded, "Origin-Forever", "overflow", currentTime)
    and OU.Util.Count(bounded.seen) == OU.State.LIMITS.DEDUPE,
    "dedupe must not evict a live key for a rotated id")
currentTime = currentTime + OU.State.LIMITS.DEDUPE_TTL + 1
OU.State.Prune(bounded, currentTime)
assert(OU.State.RememberSeen(bounded, "Origin-Forever", "recovered", currentTime)
    and OU.Util.Count(bounded.seen) == 1, "dedupe saturation should recover after TTL pruning")

local capacity = OU.State.NewRuntime()
for index = 1, OU.State.LIMITS.LAYERS do capacity.layers["layer-" .. index] = { expires = currentTime + 60 } end
local allowed, capacityReason = OU.State._Test.CapacityAllowed(capacity,
    { type = "LREQ", id = "layer-overflow", origin = "Origin-Forever", fields = {} }, currentTime)
assert(not allowed and capacityReason == "layer capacity", "runtime maps must fail closed at cap before insertion")
capacity.layers["layer-1"].expires = currentTime - 1
OU.State.Prune(capacity, currentTime)
allowed = OU.State._Test.CapacityAllowed(capacity,
    { type = "LREQ", id = "layer-recovered", origin = "Origin-Forever", fields = {} }, currentTime)
assert(allowed, "runtime map capacity should recover after pruning")

local windowDB = OU.State.EnsureDatabase({ window = { point = "TOPLEFT", x = 99999, y = -99999 } })
assert(windowDB.window.point == "TOPLEFT" and windowDB.window.x == 4096 and windowDB.window.y == -4096,
    "finite window coordinates should clamp to the safe boundary")

print("Olympus United protocol and state tests passed")
