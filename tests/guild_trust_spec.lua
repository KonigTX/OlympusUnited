local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")
local now = 900000
local currentGuild, leaderValue, officerValue = "OLYMPUS", false, false
local guildThrows, leaderThrows, officerThrows, secretBooleans, secretGuild = false, false, false, false, false

function GetServerTime() return now end
function GetTime() return now end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
function GetGuildInfo()
    if guildThrows then error("guild unavailable") end
    return currentGuild
end
function IsGuildLeader()
    if leaderThrows then error("leader unavailable") end
    return leaderValue
end
C_GuildInfo = { IsGuildOfficer = function()
    if officerThrows then error("officer unavailable") end
    return officerValue
end }
function issecretvalue(value)
    return (secretBooleans and type(value) == "boolean") or (secretGuild and type(value) == "string")
end

local OU = {}
for _, file in ipairs({ "Util.lua", "CensusLogic.lua", "Strings.lua", "Protocol.lua", "State.lua", "GuildTrust.lua" }) do
    assert(loadfile(root .. "/addon/OlympusUnited/" .. file))("OlympusUnited", OU)
end
OU.Identity = { name = "Zeus-Forever", guild = "OLYMPUS", role = "member" }

local function Fresh() return OU.State.EnsureDatabase({}) end
local function Message(id, target, display, action, generation, previous, decidedAt)
    local payload = assert(OU.Protocol.Encode("GDEC", id,
        { "olympus", target, display, action, generation, previous, decidedAt }, "RemoteOfficer-Forever", 0))
    return assert(OU.Protocol.Decode(payload))
end

leaderValue, officerValue = true, false
assert(OU.GuildTrust.LocalAuthority() == "authorized", "a plain leader true independently authorizes")
leaderValue, officerValue = false, true
assert(OU.GuildTrust.LocalAuthority() == "authorized", "a plain officer true independently authorizes")
leaderValue, officerValue = false, false
assert(OU.GuildTrust.LocalAuthority() == "not_authorized", "two valid false results deny authority")
currentGuild = "Olympus I"
assert(OU.GuildTrust.LocalAuthority() == "not_authorized", "the wrong exact guild denies authority")
currentGuild = "OLYMPUS"
secretGuild = true
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a secret guild result fails closed")
secretGuild, currentGuild = false, nil
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a nil guild result fails closed")
currentGuild = {}
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a non-string guild result fails closed")
currentGuild = "OLYMPUS"
guildThrows = true
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a thrown guild lookup fails closed")
guildThrows = false
leaderThrows = true
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a failed role result fails closed")
leaderThrows, officerThrows = false, true
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "either unresolved false-side role result fails closed")
officerThrows, secretBooleans = false, true
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "secret role values fail closed")
secretBooleans, leaderValue, officerValue = false, nil, false
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a nil role result fails closed")
leaderValue = {}
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a non-boolean role result fails closed")
local savedLeader = IsGuildLeader
IsGuildLeader = nil
assert(OU.GuildTrust.LocalAuthority() == "unavailable", "a missing role API fails closed")
IsGuildLeader, leaderValue, officerValue = savedLeader, true, false

local database = Fresh()
assert(database.participatingGuilds.olympus == "OLYMPUS" and OU.Util.Count(database.participatingGuilds) == 1,
    "the exact root is pinned as the only production bootstrap")
for _, lookalike in ipairs({ "Not Olympus", "Olympus Scammers", "Mount Olympus" }) do
    assert(OU.GuildTrust.Observe(lookalike, "local-visible", now, database), "ASCII Olympus-like names become review candidates")
    assert(not OU.Util.IsParticipatingGuild(lookalike, database), "discovery must never auto-trust a lookalike")
end
assert(not OU.GuildTrust.Observe("Other Guild", "local-visible", now, database),
    "unrelated names do not consume candidate capacity")
assert(not OU.GuildTrust.Observe("ΟLYMPUS", "local-visible", now, database),
    "Unicode lookalikes are neither folded nor trusted")

local allowedFields = { displayName = true, state = true, firstSeenAt = true, lastSeenAt = true,
    evidenceMask = true, observations = true, deniedEvidenceMask = true, generation = true,
    decisionId = true, decidedAt = true, sourceClass = true }
for key in pairs(database.guildGovernance["not olympus"]) do
    assert(allowedFields[key], "candidate records must remain privacy-minimal: " .. tostring(key))
end
assert(database.guildGovernance["not olympus"].observations == 1
    and database.guildGovernance["not olympus"].evidenceMask == OU.GuildTrust.EVIDENCE["local-visible"],
    "one observation is stored as a bit and saturating count, not a history")

local approved, decision, record = OU.GuildTrust.Decide("approve", "Not Olympus", now, database)
assert(approved and decision.fields[4] == "approve" and record.state == "approved"
    and OU.Util.IsParticipatingGuild("Not Olympus", database), "Approve atomically grants only the exact candidate")
assert(not OU.GuildTrust.Decide("deny", "OLYMPUS", now, database), "the root can never be a decision target")
local denied = assert(OU.GuildTrust.Decide("deny", "Olympus Scammers", now, database))
assert(denied and database.guildGovernance["olympus scammers"].state == "denied"
    and not OU.Util.IsParticipatingGuild("Olympus Scammers", database), "Deny keeps the candidate untrusted")
OU.GuildTrust.Observe("Olympus Scammers", "local-visible", now + 1, database)
assert(database.guildGovernance["olympus scammers"].state == "denied",
    "repeated evidence already present at denial remains suppressed")
OU.GuildTrust.Observe("Olympus Scammers", "configured-connector", now + 2, database)
assert(database.guildGovernance["olympus scammers"].state == "pending"
    and not OU.Util.IsParticipatingGuild("Olympus Scammers", database),
    "the first materially new evidence class reopens review without granting trust")
assert(OU.GuildTrust.Decide("deny", "Olympus Scammers", now + 3, database))
assert(OU.GuildTrust.Decide("review", "Olympus Scammers", now + 4, database))
assert(database.guildGovernance["olympus scammers"].state == "pending",
    "authorized Reconsider clears denial suppression and returns to pending")
assert(OU.GuildTrust.Decide("review", "Not Olympus", now + 5, database))
assert(not OU.Util.IsParticipatingGuild("Not Olympus", database),
    "Reconsider removes an approval before any future traffic can use it")

local capped = Fresh()
for index = 1, OU.GuildTrust.RECORD_CAP do
    assert(OU.GuildTrust.Observe("Olympus Candidate " .. index, "local-visible", now, capped),
        "candidate entries should fill through the exact cap")
end
assert(not OU.GuildTrust.Observe("Olympus Candidate overflow", "local-visible", now, capped)
    and OU.Util.Count(capped.guildGovernance) == OU.GuildTrust.RECORD_CAP,
    "cap+1 is rejected without evicting live decisions or candidates")
for index = 1, 300 do OU.GuildTrust.Observe("Olympus Candidate 1", "local-visible", now, capped) end
assert(capped.guildGovernance["olympus candidate 1"].observations == 255,
    "repeated sightings saturate one counter without allocating evidence history")
local durable = Fresh()
assert(OU.GuildTrust.Observe("Olympus Durable Approved", "local-visible", now, durable))
assert(OU.GuildTrust.Decide("approve", "Olympus Durable Approved", now, durable))
assert(OU.GuildTrust.Observe("Olympus Durable Denied", "local-visible", now, durable))
assert(OU.GuildTrust.Decide("deny", "Olympus Durable Denied", now, durable))
for index = 3, OU.GuildTrust.RECORD_CAP do
    assert(OU.GuildTrust.Observe("Olympus Durable Fill " .. index, "local-visible", now, durable))
end
assert(not OU.GuildTrust.Observe("Olympus Durable Overflow", "local-visible", now, durable)
    and durable.guildGovernance["olympus durable approved"].state == "approved"
    and durable.guildGovernance["olympus durable denied"].state == "denied",
    "candidate saturation never evicts a live approval or durable denial")
local boundary = Fresh()
assert(OU.GuildTrust.Observe("Olympus Boundary", "local-visible", now, boundary))
OU.GuildTrust.Prune(boundary, now + OU.GuildTrust.PENDING_TTL)
assert(boundary.guildGovernance["olympus boundary"], "a candidate remains at the exact day-30 boundary")
OU.GuildTrust.Prune(boundary, now + OU.GuildTrust.PENDING_TTL + 1)
assert(not boundary.guildGovernance["olympus boundary"], "a pending candidate expires just after day 30")

local function GovernanceRecord(display, state, seenAt)
    local decided = state ~= "pending"
    return {
        displayName = display, state = state, firstSeenAt = seenAt, lastSeenAt = seenAt,
        evidenceMask = 1, observations = 1, deniedEvidenceMask = state == "denied" and 1 or 0,
        generation = decided and 1 or 0,
        decisionId = decided and ("g-project-" .. OU.Util.NormalizeGuild(display):gsub(" ", "-")) or nil,
        decidedAt = decided and seenAt or nil,
        sourceClass = decided and "local-officer" or nil,
    }
end
local function AssertExactGuildMap(actual, expected, message)
    assert(OU.Util.Count(actual) == OU.Util.Count(expected), message .. " (count)")
    for key, display in pairs(expected) do assert(actual[key] == display, message .. " (" .. key .. ")") end
end

assert(OU.GuildTrust.Prune("not-a-database", now) == 0,
    "direct pruning a non-table database must be a safe no-op")
local projected = {
    guildGovernance = {
        ["olympus projected approved"] = GovernanceRecord("Olympus Projected Approved", "approved", now),
        ["olympus projected pending"] = GovernanceRecord("Olympus Projected Pending", "pending", now),
        ["olympus projected denied"] = GovernanceRecord("Olympus Projected Denied", "denied", now),
        ["olympus projected conflict"] = GovernanceRecord("Olympus Projected Conflict", "conflict", now),
        ["olympus bad display"] = GovernanceRecord("Olympus Other Display", "approved", now),
        ["Olympus NonNormalized"] = GovernanceRecord("Olympus NonNormalized", "approved", now),
        [9] = GovernanceRecord("Olympus Numeric Key", "approved", now),
        ["olympus private"] = { displayName = "Olympus Private", state = "pending", firstSeenAt = now,
            lastSeenAt = now, evidenceMask = 1, observations = 1, deniedEvidenceMask = 0, generation = 0,
            message = "must not persist" },
    },
    participatingGuilds = "malformed",
}
OU.GuildTrust.Prune(projected, now)
AssertExactGuildMap(projected.participatingGuilds,
    { olympus = "OLYMPUS", ["olympus projected approved"] = "Olympus Projected Approved" },
    "direct prune must atomically derive an exact canonical allowlist")
assert(projected.guildGovernance["olympus projected pending"]
    and projected.guildGovernance["olympus projected denied"]
    and projected.guildGovernance["olympus projected conflict"]
    and not projected.guildGovernance["olympus bad display"]
    and not projected.guildGovernance["Olympus NonNormalized"]
    and not projected.guildGovernance[9]
    and not projected.guildGovernance["olympus private"],
    "direct prune must retain valid governance states while rejecting malformed records, keys, and displays")
projected.participatingGuilds = {
    olympus = "Wrong Root",
    ["olympus projected approved"] = "Wrong Approval Display",
    ["olympus projected orphan"] = "Olympus Projected Orphan",
    ["olympus projected pending"] = "Olympus Projected Pending",
    ["olympus projected denied"] = "Olympus Projected Denied",
    ["olympus projected conflict"] = "Olympus Projected Conflict",
}
local staleProjectedParticipation = projected.participatingGuilds
OU.GuildTrust.Prune(projected, now)
assert(projected.participatingGuilds ~= staleProjectedParticipation,
    "direct prune must replace the participation table atomically")
AssertExactGuildMap(projected.participatingGuilds,
    { olympus = "OLYMPUS", ["olympus projected approved"] = "Olympus Projected Approved" },
    "direct prune must remove orphans and every non-approved state while restoring canonical display")
for _ = 1, 10 do OU.GuildTrust.Prune(projected, now) end
AssertExactGuildMap(projected.participatingGuilds,
    { olympus = "OLYMPUS", ["olympus projected approved"] = "Olympus Projected Approved" },
    "ten direct prune passes at equal time must remain stable")
local rootOnly = { participatingGuilds = { orphan = "Orphan", olympus = "Wrong Root" } }
OU.GuildTrust.Prune(rootOnly, now)
AssertExactGuildMap(rootOnly.participatingGuilds, { olympus = "OLYMPUS" },
    "missing governance must produce the exact root-only projection")

local overCapGovernance = {}
for index = 1, 40 do
    local display = ("Olympus Projection %02d"):format(index)
    overCapGovernance[OU.Util.NormalizeGuild(display)] = GovernanceRecord(display, "approved", now)
end
local migratedOverCap = OU.State.EnsureDatabase({ guildGovernance = overCapGovernance })
local runtimeOverCap = { guildGovernance = overCapGovernance, participatingGuilds = { orphan = "Orphan" } }
OU.GuildTrust.Prune(runtimeOverCap, now)
assert(OU.Util.Count(runtimeOverCap.participatingGuilds) == OU.State.LIMITS.PARTICIPATING_GUILDS,
    "the runtime projection must retain the root and only 31 deterministic approvals")
for key, display in pairs(migratedOverCap.participatingGuilds) do
    assert(runtimeOverCap.participatingGuilds[key] == display,
        "runtime and migration must share the same deterministic over-cap projection")
end
for key, record in pairs(migratedOverCap.guildGovernance) do
    assert(runtimeOverCap.guildGovernance[key].state == record.state,
        "runtime and migration must share the same deterministic over-cap governance state")
end
OU.GuildTrust.Prune(runtimeOverCap, now)
assert(OU.Util.Count(runtimeOverCap.participatingGuilds) == OU.State.LIMITS.PARTICIPATING_GUILDS,
    "a second over-cap projection must remain stable")

local allowlistCap = Fresh()
for index = 1, OU.State.LIMITS.PARTICIPATING_GUILDS - 1 do
    local name = "Olympus Approved " .. index
    assert(OU.GuildTrust.Observe(name, "local-visible", now, allowlistCap))
    assert(OU.GuildTrust.Decide("approve", name, now + index, allowlistCap))
end
assert(OU.Util.Count(allowlistCap.participatingGuilds) == OU.State.LIMITS.PARTICIPATING_GUILDS,
    "the root plus 31 exact approvals fills the allowlist")
assert(OU.GuildTrust.Observe("Olympus Approved overflow", "local-visible", now, allowlistCap))
local capOK, capReason = OU.GuildTrust.Decide("approve", "Olympus Approved overflow", now + 100, allowlistCap)
assert(not capOK and capReason == "allowlist-capacity",
    "a new approval fails closed at the allowlist cap without displacing the root")

local remote = Fresh()
local first = Message("g-remote-1", "olympus remote", "Olympus Remote", "approve", 7, "-", now)
assert(OU.GuildTrust.ApplyRemote(first, now, remote) and OU.Util.IsParticipatingGuild("Olympus Remote", remote),
    "one fresh configured-connector decision may establish a bounded snapshot")
assert(not OU.GuildTrust.ApplyRemote(first, now, remote), "the current decision ID cannot replay")
local chained = Message("g-remote-2", "olympus remote", "Olympus Remote", "deny", 8, "g-remote-1", now + 1)
assert(OU.GuildTrust.ApplyRemote(chained, now + 1, remote)
    and remote.guildGovernance["olympus remote"].state == "denied",
    "a fresh successor with the exact predecessor applies")
local gap = Message("g-remote-gap", "olympus remote", "Olympus Remote", "approve", 10, "g-remote-2", now + 2)
local gapOK, gapReason = OU.GuildTrust.ApplyRemote(gap, now + 2, remote)
assert(not gapOK and gapReason == "decision-conflict" and remote.guildGovernance["olympus remote"].state == "conflict"
    and not OU.Util.IsParticipatingGuild("Olympus Remote", remote), "a generation gap records bounded conflict and fails closed")
OU.GuildTrust.Prune(remote, now + 2 + OU.GuildTrust.PENDING_TTL)
assert(remote.guildGovernance["olympus remote"], "a conflict remains at the exact day-30 boundary")
OU.GuildTrust.Prune(remote, now + 3 + OU.GuildTrust.PENDING_TTL)
assert(not remote.guildGovernance["olympus remote"], "an unresolved conflict is removed just after day 30")
local stale = Message("g-stale", "olympus stale", "Olympus Stale", "approve", 1, "-", now - 601)
assert(not OU.GuildTrust.ApplyRemote(stale, now, remote), "decisions older than 600 seconds are rejected")
local future = Message("g-future", "olympus future", "Olympus Future", "approve", 1, "-", now + 61)
assert(not OU.GuildTrust.ApplyRemote(future, now, remote), "decisions more than 60 seconds in the future are rejected")

currentGuild, leaderValue, officerValue = "Other Guild", true, true
local before = OU.Util.Count(database.participatingGuilds)
assert(not OU.GuildTrust.Decide("approve", "Mount Olympus", now, database)
    and OU.Util.Count(database.participatingGuilds) == before,
    "direct mutation rechecks exact local OLYMPUS authority every time")

print("Olympus United guild trust tests passed")
