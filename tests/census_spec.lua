local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")

local now = 500000
function GetServerTime() return now end
function GetTime() return now end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
function UnitFullName() return "Zeus", "Forever" end
function UnitLevel() return 60 end
function UnitClass() return "Warrior", "WARRIOR" end
function GetGuildInfo() return "Olympus I" end
function GetRealZoneText() return "Stormwind" end
local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }

local OU = {}
assert(loadfile(root .. "/addon/OlympusUnited/Util.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/CensusLogic.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Protocol.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Strings.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/State.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/GuildTrust.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Census.lua"))("OlympusUnited", OU)

local L = OU.CensusLogic
assert(L.NormalizeGuild("  Olympus   II ") == "olympus ii", "guild keys collapse case and spacing")

local old = { term = 7, leaseStartedAt = 100, reporter = "Zulu-Forever", leaseSeq = 1 }
local newerStart = { term = 7, leaseStartedAt = 101, reporter = "Alpha-Forever", leaseSeq = 99 }
assert(L.CompareLease(old, newerStart) > 0, "older lease start must beat a lower reporter joining later")
local sameStartLow = { term = 7, leaseStartedAt = 100, reporter = "Alpha-Forever", leaseSeq = 0 }
assert(L.CompareLease(sameStartLow, old) > 0, "lower reporter wins at the same election start")
local renewed = { term = 7, leaseStartedAt = 100, reporter = "Zulu-Forever", leaseSeq = 2 }
assert(L.CompareLease(renewed, old) > 0, "sequence refresh applies inside one lineage")
local otherReporterHighSeq = { term = 7, leaseStartedAt = 100, reporter = "Zulu2-Forever", leaseSeq = 999 }
assert(L.CompareLease(old, otherReporterHighSeq) > 0, "sequence cannot cross reporter lineages")
assert(L.CompareLease({ term = 8, leaseStartedAt = 999, reporter = "Zulu" }, old) > 0, "higher term wins first")

local requestAlpha = L.RequestID("Alpha-Forever", now, 1)
local requestBeta = L.RequestID("Beta-Forever", now, 1)
local requestAlphaNext = L.RequestID("Alpha-Forever", now, 2)
assert(requestAlpha ~= requestBeta, "request correlation includes requester-specific uniqueness across clients")
assert(requestAlpha ~= requestAlphaNext, "request correlation remains unique for repeated local requests")
assert(#requestAlpha <= 20 and requestAlpha:match("^[a-z0-9%-]+$"), "request correlation remains a legal bounded token")
local requestType, requestEnvelope, requestFields = OU.Protocol.RosterRequest(
    requestAlpha, "olympus i", "snap-request", "Reporter-Forever")
assert(OU.Protocol.Encode(requestType, requestEnvelope, requestFields, "Alpha-Forever", 0),
    "requester-specific correlation remains encodable under the protocol ceiling")

local summaries = {
    a = { guildKey = "olympus i", guildDisplay = "Olympus I", term = 2, revision = 1, capturedAt = now - 60, total = 100, online = 10, reporter = "A" },
    duplicate = { guildKey = " OLYMPUS   I ", guildDisplay = "Olympus I", term = 1, revision = 99, capturedAt = now, total = 999, online = 999, reporter = "B" },
    b = { guildKey = "olympus ii", guildDisplay = "Olympus II", term = 2, revision = 1, capturedAt = now - 1300, total = 50, online = nil, reporter = "C" },
    c = { guildKey = "olympus iii", guildDisplay = "Olympus III", term = 2, revision = 1, capturedAt = now - 2800, total = 70, online = 7, reporter = "D" },
}
local totals = L.Totals(summaries, now)
assert(totals.members == 150 and totals.online == 10, "fresh and stale unique guild summaries contribute once")
assert(totals.current == 1 and totals.stale == 1 and totals.expired == 1, "freshness buckets are distinct")
assert(totals.onlineKnown == false, "unavailable online totals remain distinct from zero")

local names = { "Alpha-Forever", "Beta;Percent%-Forever", string.rep("x", 48) }
local pages = assert(L.BuildPages("req-1", names, "Reporter-Forever"))
assert(#pages >= 1, "names should form bounded pages")
for index, page in ipairs(pages) do
    local t, id, fields = OU.Protocol.Page("req-1", index, #pages, #names, page)
    local payload = assert(OU.Protocol.Encode(t, id, fields, "Reporter-Forever", 0))
    assert(#payload <= 250, "every page must honor the encoded payload ceiling")
    assert(id == "p-req-1-" .. L.Base36(index), "every page has a unique correlated envelope id")
end

local assembly = assert(L.NewAssembly("req-1", "Reporter-Forever", #names, #pages, now))
local status, complete
for index, page in ipairs(pages) do status, complete = L.ApplyPage(assembly, index, #pages, #names, page, now + index) end
assert(status == "complete" and #complete == #names, "strict assembly completes only at the exact unique count")
assert(L.ApplyPage(assembly, 1, #pages + 1, #names, pages[1], now) == nil, "mismatched page declarations are rejected")

local thousand = {}
for index = 1, 1000 do thousand[index] = ("Member%04d-Forever"):format(index) end
local manyPages = assert(L.BuildPages("req-1000", thousand, "Reporter-Forever"))
assert(#manyPages <= 1000, "one thousand names remain representable")

local sent = {}
OU.Identity = { name = "Zulu-Forever", guild = "Olympus I", role = "member" }
local function ApprovedGuilds(names)
    local result = {}
    for index, name in ipairs(names) do
        local key = OU.Util.NormalizeGuild(name)
        result[key] = { displayName = name, state = "approved", firstSeenAt = now - 10,
            lastSeenAt = now, evidenceMask = 1, observations = 1, deniedEvidenceMask = 0,
            generation = 1, decisionId = "g-census-" .. index, decidedAt = now, sourceClass = "local-officer" }
    end
    return result
end
OU.DB = OU.State.EnsureDatabase({ guildGovernance = ApprovedGuilds({ "Olympus I", "Olympus II" }) })
OU.Runtime = OU.State.NewRuntime()
OU.Network = {
    SendGuildOnly = function(messageType, id, fields, origin, hops)
        sent[#sent + 1] = { type = messageType, id = id, fields = fields, origin = origin, hops = hops }
        return true
    end,
    Send = function(messageType, id, fields)
        sent[#sent + 1] = { type = messageType, id = id, fields = fields, origin = OU.Identity.name, hops = 0 }
        return true
    end,
}

now = 500004
OU.Runtime.census.localCapture = { state = "complete", guild = "Olympus I", guildKey = "olympus i",
    names = { "Zulu-Forever" }, total = 1, online = 1, capturedAt = now, snapshotId = "snap-boundary", revision = 0 }
assert(OU.Census.BeginElection(OU.Runtime, now), "the boundary fixture should begin an election")
local boundaryProposal = OU.Runtime.census.candidate
local boundaryTerm = math.floor(now / L.CONSTANTS.ELECTION_WINDOW) + 1
assert(boundaryProposal.term == boundaryTerm and boundaryProposal.closesAt == boundaryTerm * L.CONSTANTS.ELECTION_WINDOW,
    "election term and close must derive from the shared five-second server-time round")
local boundaryPeer = OU.State.NewRuntime()
local boundaryCandidate = { type = "CCAND", id = "c-boundary", origin = "Zulu-Forever", hops = 0,
    fields = { "olympus i", "Olympus I", boundaryTerm } }
assert(OU.Census.ApplyMessage(boundaryPeer, "Zulu-Forever", boundaryCandidate, now + 2),
    "a peer should accept a candidate received across the local five-second boundary")
local peerProposal = boundaryPeer.census.candidates["olympus i"]["zulu-forever"]
assert(peerProposal.leaseStartedAt == boundaryProposal.leaseStartedAt and peerProposal.closesAt == boundaryProposal.closesAt,
    "peers must converge on the transmitted election round instead of their receipt-time bucket")

now = 500000
timers = {}
OU.Runtime = OU.State.NewRuntime()
OU.Runtime.census.localCapture = { state = "complete", guild = "Olympus I", guildKey = "olympus i",
    names = { "Zulu-Forever" }, total = 1, online = 1, capturedAt = now, snapshotId = "snap-1", revision = 0 }
assert(OU.Census.BeginElection(OU.Runtime, now), "a complete capture should begin an election")
assert(sent[#sent].type == "CCAND", "election begins with one guild-local candidate")
local electionTimer = timers[#timers]
electionTimer.callback()
local lease = OU.Runtime.census.leases["olympus i"]
assert(lease and lease.reporter == "Zulu-Forever", "the deterministic winner becomes reporter")
local stableStart = lease.leaseStartedAt
local summaryTimersBeforeRenewal, renewalTimer = 0
for _, timer in ipairs(timers) do
    if timer.delay == L.CONSTANTS.SUMMARY_REFRESH then summaryTimersBeforeRenewal = summaryTimersBeforeRenewal + 1 end
    if timer.delay == L.CONSTANTS.LEASE_RENEW and not renewalTimer then renewalTimer = timer end
end
assert(summaryTimersBeforeRenewal == 1 and renewalTimer, "reporter starts one lease timer and one summary timer")
renewalTimer.callback()
local summaryTimersAfterRenewal = 0
for _, timer in ipairs(timers) do
    if timer.delay == L.CONSTANTS.SUMMARY_REFRESH then summaryTimersAfterRenewal = summaryTimersAfterRenewal + 1 end
end
assert(summaryTimersAfterRenewal == summaryTimersBeforeRenewal,
    "lease renewal must continue only its own chain and never multiply summary timers")

now = now + 10
local candidate = { type = "CCAND", id = "c-a", origin = "Alpha-Forever", hops = 0,
    fields = { "olympus i", "Olympus I", lease.term + 1 } }
assert(OU.Census.ApplyMessage(OU.Runtime, "Alpha-Forever", candidate, now), "healthy reporter observes a join candidate")
lease = OU.Runtime.census.leases["olympus i"]
assert(lease.term == candidate.fields[3] and lease.leaseStartedAt == stableStart,
    "reassertion adopts max term but preserves the incumbent lease start")

local raceRuntime = OU.State.NewRuntime()
local higherFirst = { type = "CLEASE", id = "l-z", origin = "Zulu-Forever", fields = { "olympus i", 9, 700000, 1 } }
local lowerSecond = { type = "CLEASE", id = "l-a", origin = "Alpha-Forever", fields = { "olympus i", 9, 700000, 1 } }
assert(OU.Census.ApplyMessage(raceRuntime, "Zulu-Forever", higherFirst, now))
assert(OU.Census.ApplyMessage(raceRuntime, "Alpha-Forever", lowerSecond, now))
assert(raceRuntime.census.leases["olympus i"].reporter == "Alpha-Forever",
    "equal-start lower identity supersedes a higher identity that leased first")
local joiner = { type = "CLEASE", id = "l-join", origin = "Aardvark-Forever", fields = { "olympus i", 9, 700001, 999 } }
assert(OU.Census.ApplyMessage(raceRuntime, "Aardvark-Forever", joiner, now) == nil,
    "a lower identity joining later cannot preempt an older incumbent")
local refresh = { type = "CLEASE", id = "l-refresh", origin = "Alpha-Forever", fields = { "olympus i", 9, 700000, 2 } }
assert(OU.Census.ApplyMessage(raceRuntime, "Alpha-Forever", refresh, now), "same-lineage sequence refresh is accepted")
local lowerTerm = { type = "CLEASE", id = "l-old", origin = "A-Forever", fields = { "olympus i", 8, 1, 999 } }
assert(OU.Census.ApplyMessage(raceRuntime, "A-Forever", lowerTerm, now) == nil, "lower-term leases are rejected")

raceRuntime.census.leases["olympus i"] = { guildKey = "olympus i", term = 9, leaseStartedAt = 700000,
    leaseSeq = 2, reporter = "Alpha-Forever", receivedAt = now }
local summary = { type = "CSUM", id = "s-new", origin = "Alpha-Forever", fields = {
    "olympus i", "Olympus I", 9, 2, "snap-2", now, 10, 3,
} }
assert(OU.Census.ApplyMessage(raceRuntime, "Alpha-Forever", summary, now), "elected reporter summary is accepted")
local staleSummary = { type = "CSUM", id = "s-old", origin = "Alpha-Forever", fields = {
    "olympus i", "Olympus I", 8, 99, "snap-old", now, 999, 999,
} }
assert(OU.Census.ApplyMessage(raceRuntime, "Alpha-Forever", staleSummary, now) == nil,
    "lower-term summaries cannot displace current state")

local failureRuntime = OU.State.NewRuntime()
failureRuntime.census.assemblies["retry-busy"] = { state = "loading", requestId = "retry-busy", guildKey = "olympus ii" }
failureRuntime.census.cooldowns["olympus ii|requester"] = now + L.CONSTANTS.REQUEST_COOLDOWN
local busyFailure = { type = "CFAIL", id = "f-busy", origin = "Reporter-Forever", fields = { "retry-busy", "busy" } }
assert(OU.Census.ReceiveFailure(failureRuntime, busyFailure, now), "busy failure should update the visible request")
assert(failureRuntime.census.cooldowns["olympus ii|requester"] == nil,
    "busy failure must clear the requester cooldown so try shortly is actionable")
failureRuntime.census.assemblies["retry-cooldown"] = { state = "loading", requestId = "retry-cooldown", guildKey = "olympus ii" }
failureRuntime.census.cooldowns["olympus ii|requester"] = now + L.CONSTANTS.REQUEST_COOLDOWN
local cooldownFailure = { type = "CFAIL", id = "f-cooldown", origin = "Reporter-Forever", fields = { "retry-cooldown", "cooldown" } }
assert(OU.Census.ReceiveFailure(failureRuntime, cooldownFailure, now), "cooldown failure should update the visible request")
assert(failureRuntime.census.cooldowns["olympus ii|requester"] > now,
    "explicit cooldown failure must retain the requester cooldown")

timers = {}
local tickRuntime = OU.State.NewRuntime()
OU.Runtime = tickRuntime
tickRuntime.census.localCapture = { state = "complete", guild = "Olympus I", guildKey = "olympus i",
    names = { "Zulu-Forever" }, total = 1, online = 1, capturedAt = now, snapshotId = "snap-tick", revision = 0 }
tickRuntime.census.leases["olympus i"] = { guildKey = "olympus i", term = 1, leaseStartedAt = now,
    leaseSeq = 1, reporter = "Alpha-Forever", receivedAt = now }
tickRuntime.census.summaries["olympus ii"] = { guildKey = "olympus ii", guildDisplay = "Olympus II",
    term = 1, revision = 1, snapshotId = "snap-freshness", capturedAt = now, total = 10,
    online = 1, reporter = "Reporter-Forever", receivedAt = now }
local refreshes = 0
OU.RefreshUI = function() refreshes = refreshes + 1 end
local governanceTickBase = now
local function PeriodicGovernanceRecord(display, state)
    local decided = state ~= "pending"
    return {
        displayName = display, state = state, firstSeenAt = governanceTickBase, lastSeenAt = governanceTickBase,
        evidenceMask = 1, observations = 1, deniedEvidenceMask = state == "denied" and 1 or 0,
        generation = decided and 1 or 0,
        decisionId = decided and ("g-tick-" .. OU.Util.NormalizeGuild(display):gsub(" ", "-")) or nil,
        decidedAt = decided and governanceTickBase or nil,
        sourceClass = decided and "local-officer" or nil,
    }
end
local function AssertExactGuildMap(actual, expected, message)
    assert(OU.Util.Count(actual) == OU.Util.Count(expected), message .. " (count)")
    for key, display in pairs(expected) do assert(actual[key] == display, message .. " (" .. key .. ")") end
end
OU.DB.guildGovernance["olympus tick pending"] = PeriodicGovernanceRecord("Olympus Tick Pending", "pending")
OU.DB.guildGovernance["olympus tick conflict"] = PeriodicGovernanceRecord("Olympus Tick Conflict", "conflict")
OU.DB.guildGovernance["olympus tick approved"] = PeriodicGovernanceRecord("Olympus Tick Approved", "approved")
OU.DB.guildGovernance["olympus tick absent"] = PeriodicGovernanceRecord("Olympus Tick Absent", "approved")
OU.DB.guildGovernance["olympus tick denied"] = PeriodicGovernanceRecord("Olympus Tick Denied", "denied")
OU.DB.guildGovernance["olympus tick malformed"] = { displayName = "Olympus Tick Malformed", state = "invalid" }
OU.DB.participatingGuilds["olympus tick orphan"] = "Olympus Tick Orphan"
OU.DB.participatingGuilds["olympus tick pending"] = "Olympus Tick Pending"
OU.DB.participatingGuilds["olympus tick conflict"] = "Olympus Tick Conflict"
OU.DB.participatingGuilds["olympus tick approved"] = "Wrong Approval Display"
OU.DB.participatingGuilds["olympus tick denied"] = "Olympus Tick Denied"
OU.DB.participatingGuilds.olympus = "Wrong Root"
assert(OU.Census._Test.EnsureTick(tickRuntime), "Census should start its bounded periodic tick")
local timerCount = #timers
assert(OU.Census._Test.EnsureTick(tickRuntime) == false and #timers == timerCount,
    "starting Census twice must not create a second periodic chain")
local tick = timers[#timers]
assert(tick.delay == L.CONSTANTS.TICK_INTERVAL, "periodic Census maintenance uses the bounded cadence")
now = now + L.CONSTANTS.LEASE_TIMEOUT + 1
tick.callback()
assert(tickRuntime.census.candidate, "an expired received lease must trigger takeover while the client is idle")
AssertExactGuildMap(OU.DB.participatingGuilds, {
    olympus = "OLYMPUS",
    ["olympus i"] = "Olympus I",
    ["olympus ii"] = "Olympus II",
    ["olympus tick absent"] = "Olympus Tick Absent",
    ["olympus tick approved"] = "Olympus Tick Approved",
}, "the actual scheduled Census tick must project the exact current approved guild set")
for _, guild in ipairs({ "Olympus Tick Orphan", "Olympus Tick Pending", "Olympus Tick Conflict",
    "Olympus Tick Denied", "Olympus Tick Malformed" }) do
    assert(not OU.Util.IsParticipatingGuild(guild, OU.DB),
        "the scheduled tick must remove trust before approval for " .. guild)
end
local nextTick = timers[#timers]
now = tickRuntime.census.summaries["olympus ii"].capturedAt + L.CONSTANTS.FRESH_SECONDS + 1
nextTick.callback()
assert(L.Freshness(tickRuntime.census.summaries["olympus ii"], now) == "stale" and refreshes >= 2,
    "periodic maintenance refreshes the UI when a report becomes stale")
nextTick = timers[#timers]
now = tickRuntime.census.summaries["olympus ii"].capturedAt + L.CONSTANTS.EXPIRE_SECONDS + 1
nextTick.callback()
assert(L.Freshness(tickRuntime.census.summaries["olympus ii"], now) == "expired" and refreshes >= 3,
    "periodic maintenance refreshes the UI when a report expires")
assert(not OU.DB.guildGovernance["olympus tick malformed"]
    and not OU.DB.participatingGuilds["olympus tick conflict"]
    and not OU.DB.participatingGuilds["olympus tick denied"],
    "the production periodic tick must fail closed on malformed and non-approved governance state")

nextTick = timers[#timers]
now = governanceTickBase + OU.GuildTrust.PENDING_TTL - 1
nextTick.callback()
assert(OU.DB.guildGovernance["olympus tick pending"]
    and OU.DB.guildGovernance["olympus tick conflict"],
    "the production periodic tick retains pending and conflict records at TTL-1")
nextTick = timers[#timers]
now = governanceTickBase + OU.GuildTrust.PENDING_TTL
nextTick.callback()
assert(OU.DB.guildGovernance["olympus tick pending"]
    and OU.DB.guildGovernance["olympus tick conflict"],
    "the production periodic tick retains pending and conflict records at the exact TTL")
nextTick = timers[#timers]
now = governanceTickBase + OU.GuildTrust.PENDING_TTL + 1
nextTick.callback()
assert(not OU.DB.guildGovernance["olympus tick pending"]
    and not OU.DB.guildGovernance["olympus tick conflict"]
    and OU.DB.guildGovernance["olympus tick approved"].state == "approved"
    and OU.DB.guildGovernance["olympus tick denied"].state == "denied"
    and OU.DB.participatingGuilds.olympus == "OLYMPUS",
    "the production periodic tick removes expired transient governance and preserves durable decisions/root")
local stableGovernanceCount = OU.Util.Count(OU.DB.guildGovernance)
local stableParticipation = {}
for key, display in pairs(OU.DB.participatingGuilds) do stableParticipation[key] = display end
nextTick = timers[#timers]
nextTick.callback()
assert(OU.Util.Count(OU.DB.guildGovernance) == stableGovernanceCount,
    "repeated scheduled governance maintenance is idempotent and bounded")
AssertExactGuildMap(OU.DB.participatingGuilds, stableParticipation,
    "a second scheduled tick at equal time must leave the projected allowlist stable")

local boundedCensus = OU.State.NewRuntime()
now = 800000
local term = math.floor(now / L.CONSTANTS.ELECTION_WINDOW) + 1
for index = 1, L.CONSTANTS.MAX_CANDIDATES do
    local message = { type = "CCAND", id = "candidate-" .. index, origin = "Candidate" .. index .. "-Forever", hops = 0,
        fields = { "olympus i", "Olympus I", term } }
    assert(OU.Census.ApplyMessage(boundedCensus, message.origin, message, now),
        "candidate insertions should pass through the exact cap")
end
local overflowCandidate = { type = "CCAND", id = "candidate-overflow", origin = "Overflow-Forever", hops = 0,
    fields = { "olympus i", "Olympus I", term } }
assert(OU.Census.ApplyMessage(boundedCensus, overflowCandidate.origin, overflowCandidate, now) == nil,
    "candidate cap+1 must fail closed")
now = now + L.CONSTANTS.CANDIDATE_TTL + 1
OU.Census.Prune(boundedCensus, now, true)
assert(next(boundedCensus.census.candidates) == nil, "candidate saturation should recover after retention pruning")

local routeRuntime = OU.State.NewRuntime()
for index = 1, L.CONSTANTS.MAX_ROUTES do
    local id = "route-cap-" .. index
    assert(OU.Census.AdmitRoute(routeRuntime, id, { requestId = id, expiresAt = now + L.CONSTANTS.ROUTE_TTL }, now),
        "routes should admit through the cap")
end
assert(not OU.Census.AdmitRoute(routeRuntime, "route-overflow",
    { requestId = "route-overflow", expiresAt = now + L.CONSTANTS.ROUTE_TTL }, now), "route cap+1 must fail")
routeRuntime.census.routes["route-cap-1"].expiresAt = now
OU.Census.Prune(routeRuntime, now, true)
assert(OU.Census.AdmitRoute(routeRuntime, "route-recovered",
    { requestId = "route-recovered", expiresAt = now + L.CONSTANTS.ROUTE_TTL }, now),
    "route saturation should recover after expiry")
routeRuntime.census.pageRate["connector|route-recovered"] = {
    requestId = "route-recovered", last = now, lastTouched = now,
}
routeRuntime.census.routes["route-recovered"] = nil
OU.Census.Prune(routeRuntime, now, true)
assert(routeRuntime.census.pageRate["connector|route-recovered"] == nil,
    "page-rate state must die with its correlated route")

local assemblyRuntime = OU.State.NewRuntime()
assemblyRuntime.census.assemblies.loading = {
    state = "loading", expiresAt = now - 1, logic = { pages = { { "SessionOnlyName-Forever" } } },
}
assemblyRuntime.census.assemblies.complete = {
    state = "complete", loadedAt = now - L.CONSTANTS.ASSEMBLY_COMPLETE_TTL - 1,
    expiresAt = now - 1, names = { "SessionOnlyName-Forever" },
}
assemblyRuntime.census.assemblies.failed = {
    state = "error", finishedAt = now - L.CONSTANTS.ASSEMBLY_ERROR_TTL - 1,
    expiresAt = now - 1, names = { "MustDisappear-Forever" },
}
OU.Census.Prune(assemblyRuntime, now, true)
assert(assemblyRuntime.census.assemblies.loading.state == "error"
    and assemblyRuntime.census.assemblies.loading.logic == nil
    and assemblyRuntime.census.assemblies.complete == nil
    and assemblyRuntime.census.assemblies.failed == nil,
    "loading assemblies must transition safely and complete/error assemblies must release names")
now = now + L.CONSTANTS.ASSEMBLY_ERROR_TTL + 1
OU.Census.Prune(assemblyRuntime, now, true)
assert(assemblyRuntime.census.assemblies.loading == nil, "transitioned loading assemblies must expire after the error window")

local oldSummaryRuntime = OU.State.NewRuntime()
oldSummaryRuntime.census.summaries["olympus ii"] = { guildKey = "olympus ii", guildDisplay = "Olympus II",
    receivedAt = now - L.CONSTANTS.SUMMARY_RETENTION - 1, capturedAt = now - L.CONSTANTS.SUMMARY_RETENTION - 1 }
OU.Census.Prune(oldSummaryRuntime, now, true)
assert(oldSummaryRuntime.census.summaries["olympus ii"] == nil,
    "expired summaries must be removed after the bounded diagnostic window")

local savedIdentity = OU.Identity
OU.Identity = { name = "Visitor-Forever", guild = "Not Olympus", role = "guest" }
local unlistedRuntime = OU.State.NewRuntime()
OU.Runtime = unlistedRuntime
assert(not OU.Census.Start() and unlistedRuntime.census.localCapture.reason == "not-participating",
    "an unlisted local guild must never start Census capture or election")
OU.Identity = savedIdentity

local governanceDB = OU.State.EnsureDatabase({})
OU.DB = governanceDB
OU.Identity = { name = "Candidate-Forever", guild = "Olympus Candidate", role = "guest" }
local governanceRuntime = OU.State.NewRuntime()
OU.Runtime = governanceRuntime
governanceRuntime.census.localCapture = { state = "complete", guild = "Olympus Candidate",
    guildKey = "olympus candidate", names = { "SessionOnly-Forever" }, total = 1, online = 1,
    capturedAt = now, snapshotId = "candidate-snapshot", revision = 0 }
assert(OU.GuildTrust.Observe("Olympus Candidate", "local-visible", now, governanceDB)
    and not OU.Census.BeginElection(governanceRuntime, now),
    "a pending discovered guild cannot participate in Census")
local deny = { type = "GDEC", id = "g-census-deny", origin = "RemoteOfficer-Forever", hops = 0,
    fields = { "olympus", "olympus candidate", "Olympus Candidate", "deny", 1, "-", now } }
assert(OU.GuildTrust.ApplyRemote(deny, now, governanceDB)
    and not OU.Census.BeginElection(governanceRuntime, now), "a denied candidate cannot participate in Census")
local approve = { type = "GDEC", id = "g-census-approve", origin = "RemoteOfficer-Forever", hops = 0,
    fields = { "olympus", "olympus candidate", "Olympus Candidate", "approve", 2, "g-census-deny", now + 1 } }
assert(OU.GuildTrust.ApplyRemote(approve, now + 1, governanceDB)
    and OU.Census.BeginElection(governanceRuntime, now + 1),
    "approval enables only future Census election work for the exact guild")
local reconsider = { type = "GDEC", id = "g-census-review", origin = "RemoteOfficer-Forever", hops = 0,
    fields = { "olympus", "olympus candidate", "Olympus Candidate", "review", 3, "g-census-approve", now + 2 } }
assert(OU.GuildTrust.ApplyRemote(reconsider, now + 2, governanceDB)
    and not OU.Census.BeginElection(governanceRuntime, now + 2),
    "reconsideration removes Census participation immediately")
local fork = { type = "GDEC", id = "g-census-fork", origin = "RemoteOfficer-Forever", hops = 0,
    fields = { "olympus", "olympus candidate", "Olympus Candidate", "approve", 5, "g-census-review", now + 3 } }
assert(not OU.GuildTrust.ApplyRemote(fork, now + 3, governanceDB)
    and governanceDB.guildGovernance["olympus candidate"].state == "conflict"
    and not OU.Census.BeginElection(governanceRuntime, now + 3),
    "a governance conflict remains outside Census without disturbing correlation mechanics")

print("Olympus United census logic tests passed")
