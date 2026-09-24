local _, OU = ...

local Census = { generation = 0, tickRuntime = nil }
OU.Census = Census

local C = OU.CensusLogic.CONSTANTS

local function Identity()
    return OU.Identity or OU.Util.PlayerIdentity()
end

local function LocalGuildKey()
    return OU.Util.NormalizeGuild(Identity().guild)
end

local function SelfKey()
    return OU.Util.NormalizeName(Identity().name)
end

local function UInt(value, maximum)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < 0 or number > maximum then return nil end
    return number
end

local function SendGuild(messageType, id, fields, origin, hops)
    return OU.Network and OU.Network.SendGuildOnly and OU.Network.SendGuildOnly(messageType, id, fields, origin, hops)
end

local function Notify()
    if OU.RefreshUI then OU.RefreshUI() end
end

local function Schedule(delay, callback)
    if C_Timer and C_Timer.After then C_Timer.After(delay, callback) end
end

function Census.IsReporter(runtime, now)
    local key = LocalGuildKey()
    local lease = key and runtime.census.leases[key]
    local capture = runtime.census.localCapture
    return lease and capture and capture.state == "complete" and OU.CensusLogic.LeaseActive(lease, now)
        and OU.Util.NormalizeName(lease.reporter) == SelfKey(), lease
end

local function SendLease(runtime, lease, now)
    local messageType, id, fields = OU.Protocol.Lease(lease.guildKey, lease.term, lease.leaseStartedAt, lease.leaseSeq)
    local sent = SendGuild(messageType, id, fields, lease.reporter, 0)
    if sent then
        lease.receivedAt = now
        runtime.census.leases[lease.guildKey] = lease
    end
    return sent
end

local function PublishSummary(runtime, now)
    local reporter, lease = Census.IsReporter(runtime, now)
    local snapshot = runtime.census.localCapture
    if not reporter or type(snapshot) ~= "table" or snapshot.state ~= "complete" then return false end
    snapshot.revision = (snapshot.revision or 0) + 1
    local messageType, id, fields = OU.Protocol.Summary(snapshot.guildKey, snapshot.guild, lease.term,
        snapshot.revision, snapshot.snapshotId, snapshot.capturedAt, snapshot.total, snapshot.online)
    local sent = OU.Network.Send(messageType, id, fields)
    if sent then
        local message = { type = messageType, id = id, fields = fields, origin = lease.reporter, hops = 0 }
        Census.ApplyMessage(runtime, lease.reporter, message, now)
    end
    return sent
end

local function ScheduleSummary(runtime, lineage)
    Schedule(C.SUMMARY_REFRESH, function()
        local active, current = Census.IsReporter(runtime, OU.Util.Now())
        if not active or current.reporter .. "|" .. current.leaseStartedAt ~= lineage then return end
        Census.RefreshReporterSnapshot(runtime, function(ok)
            if ok then ScheduleSummary(runtime, lineage) end
        end)
    end)
end

local function ScheduleLeaseRenewal(runtime, lineage)
    Schedule(C.LEASE_RENEW, function()
        local active, current = Census.IsReporter(runtime, OU.Util.Now())
        if not active or current.reporter .. "|" .. current.leaseStartedAt ~= lineage then return end
        current.leaseSeq = math.min(999999, (current.leaseSeq or 0) + 1)
        SendLease(runtime, current, OU.Util.Now())
        ScheduleLeaseRenewal(runtime, lineage)
    end)
end

local function BecomeReporter(runtime, proposal, now)
    local lease = {
        guildKey = proposal.guildKey,
        term = proposal.term,
        leaseStartedAt = proposal.leaseStartedAt,
        leaseSeq = proposal.leaseSeq or 1,
        reporter = Identity().name,
        receivedAt = now,
    }
    runtime.census.candidate = nil
    if SendLease(runtime, lease, now) then
        PublishSummary(runtime, now)
        local lineage = lease.reporter .. "|" .. lease.leaseStartedAt
        ScheduleLeaseRenewal(runtime, lineage)
        ScheduleSummary(runtime, lineage)
        Notify()
        return true
    end
    return false
end

local function Reassert(runtime, candidateTerm, now)
    local active, lease = Census.IsReporter(runtime, now)
    if not active or now - (lease.lastReassertAt or 0) < 2 then return false end
    lease.term = math.max(lease.term, candidateTerm or 0)
    lease.leaseSeq = math.min(999999, (lease.leaseSeq or 0) + 1)
    lease.lastReassertAt = now
    return SendLease(runtime, lease, now)
end

function Census.BeginElection(runtime, now)
    now = now or OU.Util.Now()
    local capture = runtime.census.localCapture
    local guildKey = capture and capture.guildKey
    if not guildKey or capture.state ~= "complete" then return false, "roster-unavailable" end
    local current = runtime.census.leases[guildKey]
    if OU.CensusLogic.LeaseActive(current, now) then return false, "lease-active" end
    local term = math.floor(now / C.ELECTION_WINDOW) + 1
    local closeAt = term * C.ELECTION_WINDOW
    local proposal = { guildKey = guildKey, guildDisplay = capture.guild, term = term,
        leaseStartedAt = closeAt, leaseSeq = 1, reporter = Identity().name, closesAt = closeAt }
    runtime.census.candidate = proposal
    runtime.census.candidates[guildKey] = runtime.census.candidates[guildKey] or {}
    runtime.census.candidates[guildKey][SelfKey()] = proposal
    local messageType, id, fields = OU.Protocol.Candidate(guildKey, capture.guild, term)
    SendGuild(messageType, id, fields, Identity().name, 0)
    Census.generation = Census.generation + 1
    local generation = Census.generation
    Schedule(math.max(0, closeAt - now), function()
        if generation ~= Census.generation then return end
        local candidate = runtime.census.candidate
        if not candidate or candidate.cancelled then return end
        local winner = candidate
        for _, other in pairs(runtime.census.candidates[guildKey] or {}) do
            if OU.CensusLogic.CompareLease(other, winner) > 0 then winner = other end
        end
        if OU.Util.NormalizeName(winner.reporter) == SelfKey() then BecomeReporter(runtime, winner, OU.Util.Now()) end
    end)
    return true
end

function Census.Capture(runtime)
    runtime.census.localCapture = { state = "loading", startedAt = OU.Util.Now() }
    Notify()
    return OU.GuildRoster.Request(function(result)
        if result.ok then
            local snapshotId = ("snap-%d-%d"):format(result.capturedAt % 10000000000, (#result.names % 1000))
            result.state = "complete"
            result.snapshotId = snapshotId
            result.revision = 0
            runtime.census.localCapture = result
            if OU.ChatGuard then OU.ChatGuard.ImportRoster(result.names, result.guild, result.capturedAt) end
            Census.BeginElection(runtime, OU.Util.Now())
        else
            runtime.census.localCapture = { state = "unavailable", reason = result.reason, failedAt = OU.Util.Now() }
        end
        Notify()
    end)
end

function Census.RefreshReporterSnapshot(runtime, callback)
    callback = callback or function() end
    return OU.GuildRoster.Request(function(result)
        if not result.ok then
            runtime.census.localCapture = { state = "unavailable", reason = result.reason, failedAt = OU.Util.Now() }
            runtime.census.activeTransfer = nil
            Notify()
            callback(false)
            return
        end
        result.state = "complete"
        result.snapshotId = ("snap-%d-%d"):format(result.capturedAt % 10000000000, (#result.names % 1000))
        result.revision = (runtime.census.localCapture.revision or 0)
        runtime.census.localCapture = result
        if OU.ChatGuard then OU.ChatGuard.ImportRoster(result.names, result.guild, result.capturedAt) end
        PublishSummary(runtime, OU.Util.Now())
        Notify()
        callback(true)
    end)
end

function Census.Start()
    if not OU.Runtime or not OU.Runtime.census then return false end
    Census._Test.EnsureTick(OU.Runtime)
    return Census.Capture(OU.Runtime)
end

function Census.OnGuildChanged()
    Census.generation = Census.generation + 1
    if OU.Runtime and OU.Runtime.census then
        OU.Runtime.census.candidate = nil
        Census.Capture(OU.Runtime)
    end
end

local function ApplyCandidate(runtime, message, now)
    local fields = message.fields
    local guildKey = OU.Util.NormalizeGuild(fields[1])
    local displayKey = OU.Util.NormalizeGuild(fields[2])
    local term = UInt(fields[3], 9999999999)
    if not guildKey or guildKey ~= displayKey or guildKey ~= LocalGuildKey() or not term then return nil, "invalid candidate" end
    local reporter = OU.Util.NormalizeName(message.origin)
    if not reporter then return nil, "invalid reporter" end
    local closeAt = term * C.ELECTION_WINDOW
    local item = { guildKey = guildKey, guildDisplay = fields[2], term = term, leaseStartedAt = closeAt,
        leaseSeq = 1, reporter = message.origin, receivedAt = now, closesAt = closeAt }
    runtime.census.candidates[guildKey] = runtime.census.candidates[guildKey] or {}
    runtime.census.candidates[guildKey][reporter] = item
    Reassert(runtime, term, now)
    return { kind = "census-candidate", value = item }
end

local function ApplyLease(runtime, message, now)
    local fields = message.fields
    local guildKey = OU.Util.NormalizeGuild(fields[1])
    local term = UInt(fields[2], 9999999999)
    local started = UInt(fields[3], 9999999999)
    local seq = UInt(fields[4], 999999)
    if not guildKey or guildKey ~= LocalGuildKey() or not term or not started or not seq then return nil, "invalid lease" end
    local incoming = { guildKey = guildKey, term = term, leaseStartedAt = started, leaseSeq = seq,
        reporter = message.origin, receivedAt = now }
    local current = runtime.census.leases[guildKey]
    if current and OU.CensusLogic.LeaseActive(current, now) and OU.CensusLogic.CompareLease(incoming, current) <= 0 then
        return nil, "stale lease"
    end
    runtime.census.leases[guildKey] = incoming
    local proposal = runtime.census.candidate
    if proposal and OU.CensusLogic.CompareLease(incoming, proposal) > 0 then
        proposal.cancelled = true
        runtime.census.candidate = nil
        Census.generation = Census.generation + 1
    end
    Notify()
    return { kind = "census-lease", value = incoming }
end

local function ApplySummary(runtime, message, now)
    local f = message.fields
    local guildKey = OU.Util.NormalizeGuild(f[1])
    if not guildKey or guildKey ~= OU.Util.NormalizeGuild(f[2]) then return nil, "guild mismatch" end
    local term, revision = UInt(f[3], 9999999999), UInt(f[4], 999999)
    local capturedAt, total = UInt(f[6], 9999999999), UInt(f[7], 1000)
    local online = f[8] == "U" and nil or UInt(f[8], 1000)
    if not term or revision == nil or not capturedAt or total == nil or (f[8] ~= "U" and online == nil) or capturedAt > now + 60 then
        return nil, "invalid summary"
    end
    local lease = runtime.census.leases[guildKey]
    if lease and (OU.Util.NormalizeName(lease.reporter) ~= OU.Util.NormalizeName(message.origin) or lease.term ~= term) then
        return nil, "reporter mismatch"
    end
    if guildKey == LocalGuildKey() and not lease then return nil, "missing local lease" end
    local summary = { guildKey = guildKey, guildDisplay = f[2], term = term, revision = revision,
        snapshotId = f[5], capturedAt = capturedAt, total = total, online = online,
        reporter = message.origin, receivedAt = now }
    local current = runtime.census.summaries[guildKey]
    if current and OU.CensusLogic.CompareSummary(summary, current) <= 0 then return nil, "stale summary" end
    runtime.census.summaries[guildKey] = summary
    Notify()
    return { kind = "census-summary", value = summary }
end

function Census.ApplyMessage(runtime, sender, message, now)
    if message.type == "CCAND" then return ApplyCandidate(runtime, message, now) end
    if message.type == "CLEASE" then return ApplyLease(runtime, message, now) end
    if message.type == "CSUM" then return ApplySummary(runtime, message, now) end
    return nil, "not census state"
end

local function CooldownKey(guildKey, requester)
    return guildKey .. "|" .. (OU.Util.NormalizeName(requester) or tostring(requester):lower())
end

local function FailRequest(route, requestId, reason)
    local messageType, id, fields = OU.Protocol.Failure(requestId, reason)
    local sent, err = OU.Network.SendDirectedReply(route, messageType, id, fields, Identity().name)
    if not sent then return nil, err end
    return { kind = "census-request-failure", value = { requestId = requestId, reason = reason, route = route } }
end

local function SendTransferPage(runtime, transfer)
    if runtime.census.activeTransfer ~= transfer then return end
    transfer.index = transfer.index + 1
    local page = transfer.pages[transfer.index]
    if not page then runtime.census.activeTransfer = nil; return end
    local messageType, id, fields = OU.Protocol.Page(transfer.requestId, transfer.index, #transfer.pages, transfer.total, page)
    OU.Network.SendDirectedReply(transfer.route, messageType, id, fields, Identity().name)
    if transfer.index < #transfer.pages then
        Schedule(C.PAGE_INTERVAL, function() SendTransferPage(runtime, transfer) end)
    else
        runtime.census.activeTransfer = nil
    end
end

function Census.HandleRequest(runtime, route, message, now)
    local requestId, guildKey, snapshotId, target = message.fields[1], OU.Util.NormalizeGuild(message.fields[2]), message.fields[3], message.fields[4]
    local reporter, lease = Census.IsReporter(runtime, now)
    local capture = runtime.census.localCapture
    if not reporter or OU.Util.NormalizeName(target) ~= SelfKey() or guildKey ~= LocalGuildKey() then
        return FailRequest(route, requestId, "unavailable")
    end
    if runtime.census.activeTransfer then return FailRequest(route, requestId, "busy") end
    local cooldownKey = CooldownKey(guildKey, message.origin)
    if (runtime.census.cooldowns[cooldownKey] or 0) > now then return FailRequest(route, requestId, "cooldown") end
    if not capture or capture.state ~= "complete" or capture.snapshotId ~= snapshotId then return FailRequest(route, requestId, "snapshot") end
    local pages, err = OU.CensusLogic.BuildPages(requestId, capture.names, Identity().name)
    if not pages then return FailRequest(route, requestId, err == "invalid names" and "unavailable" or "snapshot") end
    runtime.census.cooldowns[cooldownKey] = now + C.REQUEST_COOLDOWN
    local transfer = { requestId = requestId, pages = pages, total = #capture.names, route = route, index = 0,
        reporter = lease.reporter, startedAt = now }
    runtime.census.activeTransfer = transfer
    Schedule(C.PAGE_INTERVAL, function() SendTransferPage(runtime, transfer) end)
    return { kind = "census-request", value = transfer }
end

function Census.RequestRoster(guildKey)
    local runtime, now = OU.Runtime, OU.Util.Now()
    guildKey = OU.Util.NormalizeGuild(guildKey)
    local summary = guildKey and runtime.census.summaries[guildKey]
    if not summary then return false, "unavailable" end
    local state = OU.CensusLogic.Freshness(summary, now)
    if state == "expired" then return false, "expired" end
    local cooldown = runtime.census.cooldowns[guildKey .. "|requester"] or 0
    if cooldown > now then return false, "cooldown", cooldown - now end
    OU._censusRequestID = (OU._censusRequestID or 0) + 1
    local requestId = OU.CensusLogic.RequestID(Identity().name, now, OU._censusRequestID)
    local route = { role = "requester", requestId = requestId, guildKey = guildKey, snapshotId = summary.snapshotId,
        requester = Identity().name, reporter = summary.reporter, expiresAt = now + C.ROUTE_TTL }
    runtime.census.routes[requestId] = route
    runtime.census.cooldowns[guildKey .. "|requester"] = now + C.REQUEST_COOLDOWN
    local messageType, id, fields = OU.Protocol.RosterRequest(requestId, guildKey, summary.snapshotId, summary.reporter)
    local sent, err = OU.Network.Send(messageType, id, fields)
    if not sent then
        runtime.census.routes[requestId] = nil
        runtime.census.cooldowns[guildKey .. "|requester"] = nil
        return false, err
    end
    runtime.census.assemblies[requestId] = { state = "loading", requestId = requestId, received = 0, reporter = summary.reporter,
        guildKey = guildKey, snapshotId = summary.snapshotId, startedAt = now, expiresAt = now + C.ROUTE_TTL }
    Notify()
    return true, requestId
end

function Census.ReceivePage(runtime, message, now)
    local requestId = message.fields[1]
    local holder = runtime.census.assemblies[requestId]
    if not holder then return nil, "no assembly" end
    local pageIndex, pageCount, totalNames = tonumber(message.fields[2]), tonumber(message.fields[3]), tonumber(message.fields[4])
    local names = {}
    for index = 5, #message.fields do names[#names + 1] = message.fields[index] end
    if not holder.logic then
        local logic, err = OU.CensusLogic.NewAssembly(requestId, message.origin, totalNames, pageCount, now)
        if not logic then holder.state = "error"; holder.reason = err; return nil, err end
        holder.logic = logic
    end
    local status, result = OU.CensusLogic.ApplyPage(holder.logic, pageIndex, pageCount, totalNames, names, now)
    if not status then holder.state = "error"; holder.reason = result; return nil, result end
    holder.received, holder.pageCount = holder.logic.received, holder.logic.pageCount
    if status == "complete" then
        holder.state = "complete"
        holder.names = result
        holder.loadedAt = now
        local summary = runtime.census.summaries[holder.guildKey]
        if OU.ChatGuard and summary then OU.ChatGuard.ImportRoster(result, summary.guildDisplay, now) end
    end
    Notify()
    return { kind = "census-page", value = holder, status = status }
end

function Census.ReceiveFailure(runtime, message, now)
    local requestId, reason = message.fields[1], message.fields[2]
    local holder = runtime.census.assemblies[requestId]
    if not holder then return nil, "no assembly" end
    holder.state, holder.reason, holder.finishedAt = "error", reason, now
    if reason == "busy" or reason == "unavailable" or reason == "snapshot" then
        runtime.census.cooldowns[holder.guildKey .. "|requester"] = nil
    end
    Notify()
    return { kind = "census-failure", value = holder }
end

function Census.Prune(runtime, now)
    local census = runtime.census
    for requestId, route in pairs(census.routes) do if (route.expiresAt or 0) <= now then census.routes[requestId] = nil end end
    for requestId, assembly in pairs(census.assemblies) do
        if (assembly.expiresAt or 0) <= now and assembly.state == "loading" then assembly.state, assembly.reason = "error", "expired" end
    end
    for key, untilTime in pairs(census.cooldowns) do if untilTime <= now then census.cooldowns[key] = nil end end
    local key = LocalGuildKey()
    local lease = key and census.leases[key]
    if lease and not OU.CensusLogic.LeaseActive(lease, now) and census.localCapture.state == "complete" and not census.candidate then
        Census.BeginElection(runtime, now)
    end
end

local function EnsureTick(runtime)
    if Census.tickRuntime == runtime then return false end
    Census.tickRuntime = runtime
    local function Tick()
        if Census.tickRuntime ~= runtime then return end
        OU.State.Prune(runtime, OU.Util.Now())
        Notify()
        Schedule(C.TICK_INTERVAL, Tick)
    end
    Schedule(C.TICK_INTERVAL, Tick)
    return true
end

Census._Test = { LocalGuildKey = LocalGuildKey, SelfKey = SelfKey, BecomeReporter = BecomeReporter,
    Reassert = Reassert, PublishSummary = PublishSummary, SendTransferPage = SendTransferPage,
    EnsureTick = EnsureTick }
