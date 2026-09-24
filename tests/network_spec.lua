local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")

local currentTime = 200000
local currentGuild = "Olympus I"
local sent = {}

function GetServerTime() return currentTime end
function GetTime() return currentTime end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
function UnitFullName() return "Zeus", "Forever" end
function UnitLevel() return 60 end
function UnitClass() return "Warrior", "WARRIOR" end
function GetGuildInfo() return currentGuild end
function GetRealZoneText() return "Stormwind City" end
function IsInGuild() return true end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        assert(prefix == "OLYUNITED", "protocol prefix should remain stable")
        return true
    end,
    SendAddonMessage = function(prefix, payload, distribution, target)
        sent[#sent + 1] = { prefix = prefix, payload = payload, distribution = distribution, target = target }
        return true
    end,
}
local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local controller
function CreateFrame()
    controller = { events = {}, scripts = {} }
    function controller:RegisterEvent(event) self.events[event] = true end
    function controller:UnregisterEvent(event) self.events[event] = nil end
    function controller:SetScript(name, callback) self.scripts[name] = callback end
    return controller
end

local OU = {}
assert(loadfile(root .. "/addon/OlympusUnited/Util.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/CensusLogic.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Strings.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Protocol.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/State.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/GuildTrust.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Network.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Census.lua"))("OlympusUnited", OU)
assert(loadfile(root .. "/addon/OlympusUnited/Core.lua"))("OlympusUnited", OU)

local function ApprovedGuilds(names)
    local result = {}
    for index, name in ipairs(names) do
        local key = OU.Util.NormalizeGuild(name)
        result[key] = { displayName = name, state = "approved", firstSeenAt = currentTime - 10,
            lastSeenAt = currentTime, evidenceMask = 2, observations = 1, deniedEvidenceMask = 0,
            generation = 1, decisionId = "g-fixture-" .. index .. "-" .. key:gsub(" ", "-"),
            decidedAt = currentTime, sourceClass = "configured-connector" }
    end
    return result
end

OU.DB = OU.State.EnsureDatabase({ guildGovernance = ApprovedGuilds({ "Olympus I", "Olympus II" }) })
OU.Runtime = OU.State.NewRuntime()
OU.Identity = OU.Util.PlayerIdentity()

assert(OU.Network.RegisterPrefix(), "addon-message prefix should register")
assert(OU.Network.Post("Meet at the flight path"), "member should be able to post")
assert(#sent == 1 and sent[1].distribution == "GUILD", "default transport should be guild only")
assert(#OU.Runtime.feed == 1, "local post should appear immediately")

assert(OU.Network.AddBridge("Athena-Forever"), "bridge captain should be configurable")
OU.DB.bridgeMode = true
currentTime = currentTime + 30
assert(OU.Network.Post("Across every guild"), "bridged post should send")
assert(#sent == 3, "bridged post should use guild and trusted-whisper transports")
assert(sent[3].distribution == "WHISPER" and sent[3].target == "Athena-Forever",
    "bridge transport should target its configured captain")
local trafficBeforeLocalSlowMode = #sent
local fastLocalSent, fastLocalError = OU.Network.Post("This should wait")
assert(not fastLocalSent and fastLocalError == OU.L.ERROR_CHAT_SLOW_MODE:format(30) and #sent == trafficBeforeLocalSlowMode,
    "sender-side slow mode should stop a fast repeat before network traffic")

local remoteType, remoteID, remoteFields = OU.Protocol.Post("Olympus II checking in",
    { role = "member", guild = "Olympus II" })
local remotePayload = assert(OU.Protocol.Encode(remoteType, remoteID, remoteFields, "Hera-Forever", 1))
currentTime = currentTime + 2
OU.Network.OnAddonMessage("OLYUNITED", remotePayload, "WHISPER", "Athena-Forever")
assert(#OU.Runtime.feed == 3, "remote post should appear in the feed")
assert(OU.Runtime.feed[1].sender == "Hera-Forever", "forwarded post should retain its original author")
assert(sent[#sent].distribution == "GUILD", "incoming bridge traffic should be relayed to the local guild")

OU.Network.OnAddonMessage("OLYUNITED", remotePayload, "WHISPER", "Athena-Forever")
assert(#OU.Runtime.feed == 3, "duplicate remote post should be dropped")

local fastType, fastID, fastFields = OU.Protocol.Post("A second message too soon",
    { role = "member", guild = "Olympus II" })
local fastPayload = assert(OU.Protocol.Encode(fastType, fastID, fastFields, "Hera-Forever", 1))
local trafficBeforeFastPost = #sent
currentTime = currentTime + 2
OU.Network.OnAddonMessage("OLYUNITED", fastPayload, "WHISPER", "Athena-Forever")
assert(#OU.Runtime.feed == 3 and #sent == trafficBeforeFastPost,
    "receiver-side slow mode should drop and not relay a fast repeat post")

local guestType, guestID, guestFields = OU.Protocol.Post("Let me into guild chat",
    { role = "guest", guild = "" })
local guestPayload = assert(OU.Protocol.Encode(guestType, guestID, guestFields, "Visitor-Forever", 0))
currentTime = currentTime + 30
OU.Network.OnAddonMessage("OLYUNITED", guestPayload, "WHISPER", "Athena-Forever")
assert(#OU.Runtime.feed == 3, "guest posts should be rejected even through a configured connector")

currentGuild = ""
OU.Identity = OU.Util.PlayerIdentity()
local trafficBeforeGuestSend = #sent
local guestSent, guestError = OU.Network.Post("I am outside the guild")
assert(not guestSent and guestError == OU.L.ERROR_CHAT_MEMBERS_ONLY and #sent == trafficBeforeGuestSend,
    "characters outside Olympus must not send Olympus Chat traffic")
local lockedType, lockedID, lockedFields = OU.Protocol.Post("Members should see this",
    { role = "member", guild = "Olympus II" })
local lockedPayload = assert(OU.Protocol.Encode(lockedType, lockedID, lockedFields, "Apollo-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", lockedPayload, "WHISPER", "Athena-Forever")
assert(#OU.Runtime.feed == 3, "characters outside Olympus must not receive Olympus Chat traffic")
currentGuild = "Olympus I"
OU.Identity = OU.Util.PlayerIdentity()

local unknownType, unknownID, unknownFields = OU.Protocol.Post("Do not trust this")
local unknownPayload = assert(OU.Protocol.Encode(unknownType, unknownID, unknownFields, "Unknown-Forever", 1))
currentTime = currentTime + 2
OU.Network.OnAddonMessage("OLYUNITED", unknownPayload, "WHISPER", "Unknown-Forever")
assert(#OU.Runtime.feed == 3, "unconfigured addon whispers should be rejected")

local function node(name, guild, bridges, bridgeMode)
    return {
        identity = { name = name, guild = guild, role = "member" },
        db = OU.State.EnsureDatabase({ bridges = bridges or {}, bridgeMode = bridgeMode and true or false,
            guildGovernance = ApprovedGuilds({ "Olympus A", "Olympus B", "Olympus Direct" }),
        }),
        runtime = OU.State.NewRuntime(),
    }
end
local requester = node("RequesterA-Forever", "Olympus A", {
    ["connectora-forever"] = "ConnectorA-Forever",
    ["otherconnector-forever"] = "OtherConnector-Forever",
})
local connectorA = node("ConnectorA-Forever", "Olympus A", { ["connectorb-forever"] = "ConnectorB-Forever" }, true)
local connectorB = node("ConnectorB-Forever", "Olympus B", { ["connectora-forever"] = "ConnectorA-Forever" }, true)
local reporter = node("ReporterB-Forever", "Olympus B", { ["connectorb-forever"] = "ConnectorB-Forever" })
reporter.runtime.census.leases["olympus b"] = { guildKey = "olympus b", term = 10, leaseStartedAt = currentTime - 20,
    leaseSeq = 1, reporter = "ReporterB-Forever", receivedAt = currentTime }
reporter.runtime.census.localCapture = { state = "complete", guild = "Olympus B", guildKey = "olympus b",
    snapshotId = "snap-b", capturedAt = currentTime, total = 2, online = 1,
    names = { "Hera-Forever", "ReporterB-Forever" } }

local function useNode(value)
    OU.Identity, OU.DB, OU.Runtime = value.identity, value.db, value.runtime
    currentGuild = value.identity.guild
end
local function lastSent()
    return sent[#sent], assert(OU.Protocol.Decode(sent[#sent].payload))
end

assert(not reporter.db.bridgeMode, "an ordinary reporter may trust its local connector without becoming a connector")

local forgedSummary = assert(OU.Protocol.Encode("CSUM", "s-forged", {
    "olympus fake", "Olympus Fake", 1, 1, "snap-forged", currentTime, 777, 7,
}, "OrdinaryGuildmate-Forever", 0))
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", forgedSummary, "GUILD", "OrdinaryGuildmate-Forever")
assert(requester.runtime.census.summaries["olympus fake"] == nil,
    "an ordinary guild sender cannot inject a hop-zero summary for an arbitrary remote guild")
local trustedWrongHopSummary = assert(OU.Protocol.Encode("CSUM", "s-trusted-wrong-hop", {
    "olympus fake", "Olympus Fake", 1, 2, "snap-trusted", currentTime, 888, 8,
}, "ConnectorA-Forever", 0))
OU.Network.OnAddonMessage("OLYUNITED", trustedWrongHopSummary, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.summaries["olympus fake"] == nil,
    "even a configured connector cannot inject a remote summary at guild hop zero")
local localWrongHopSummary = assert(OU.Protocol.Encode("CSUM", "s-local-wrong-hop", {
    "olympus a", "Olympus A", 1, 1, "snap-local-wrong", currentTime, 999, 9,
}, "RemoteReporter-Forever", 2))
OU.Network.OnAddonMessage("OLYUNITED", localWrongHopSummary, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.summaries["olympus a"] == nil,
    "a forwarded summary can never claim the receiving member's local guild")

connectorB.runtime.census.leases["olympus b"] = { guildKey = "olympus b", term = 10,
    leaseStartedAt = currentTime - 20, leaseSeq = 1, reporter = "ReporterB-Forever", receivedAt = currentTime }
local validSummary = assert(OU.Protocol.Encode("CSUM", "s-valid-route", {
    "olympus b", "Olympus B", 10, 1, "snap-b", currentTime, 2, 1,
}, "ReporterB-Forever", 0))
useNode(connectorB)
OU.Network.OnAddonMessage("OLYUNITED", validSummary, "GUILD", "ReporterB-Forever")
local summaryWhisper, summaryWhisperMessage = lastSent()
assert(summaryWhisper.distribution == "WHISPER" and summaryWhisper.target == "ConnectorA-Forever"
    and summaryWhisperMessage.hops == 1 and summaryWhisperMessage.origin == "ReporterB-Forever",
    "a valid local reporter summary enters the trusted connector path")
useNode(connectorA)
connectorA.db.bridges["connectorc-forever"] = "ConnectorC-Forever"
local summarySendCount = #sent
OU.Network.OnAddonMessage("OLYUNITED", summaryWhisper.payload, "WHISPER", "ConnectorB-Forever")
local summaryGuild, summaryGuildMessage = lastSent()
assert(summaryGuild.distribution == "GUILD" and summaryGuildMessage.hops == 2,
    "a trusted second connector forwards the remote summary into its guild at the legal hop")
assert(#sent == summarySendCount + 1,
    "a hop-one summary emits only its final guild leg and never an invalid hop-two whisper")
connectorA.db.bridges["connectorc-forever"] = nil
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", summaryGuild.payload, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.summaries["olympus b"].total == 2,
    "an ordinary member accepts a remote summary only from its configured local connector")

currentTime = currentTime + 6
local directSummary = assert(OU.Protocol.Encode("CSUM", "s-direct-route", {
    "olympus direct", "Olympus Direct", 11, 1, "snap-direct", currentTime, 12, 3,
}, "ConnectorB-Forever", 0))
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", directSummary, "WHISPER", "ConnectorA-Forever")
assert(requester.runtime.census.summaries["olympus direct"] == nil,
    "an ordinary configured member cannot consume an intermediate summary whisper")
useNode(connectorA)
OU.Network.OnAddonMessage("OLYUNITED", directSummary, "WHISPER", "ConnectorB-Forever")
local directGuild, directGuildMessage = lastSent()
assert(directGuild.distribution == "GUILD" and directGuildMessage.hops == 1,
    "a bridge-mode reporter's trusted direct whisper becomes the legal guild hop-one summary")
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", directGuild.payload, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.summaries["olympus direct"].total == 12,
    "an ordinary configured member accepts the legal direct-bridge summary shape")
local whisperHopTwo = assert(OU.Protocol.Encode("CSUM", "s-whisper-hop-two", {
    "olympus rejected", "Olympus Rejected", 1, 1, "snap-rejected", currentTime, 55, 5,
}, "RemoteReporter-Forever", 2))
useNode(connectorA)
OU.Network.OnAddonMessage("OLYUNITED", whisperHopTwo, "WHISPER", "ConnectorB-Forever")
assert(connectorA.runtime.census.summaries["olympus rejected"] == nil,
    "trusted summary whispers at hop two are outside the bounded route and are rejected")

local localRequestId = "same-guild"
local localRequestType, localRequestEnvelope, localRequestFields = OU.Protocol.RosterRequest(
    localRequestId, "olympus b", "snap-b", "ReporterB-Forever")
local localRequestPayload = assert(OU.Protocol.Encode(localRequestType, localRequestEnvelope, localRequestFields,
    "GuildmateB-Forever", 0))
useNode(reporter)
OU.Network.OnAddonMessage("OLYUNITED", localRequestPayload, "GUILD", "GuildmateB-Forever")
assert(reporter.runtime.census.activeTransfer and reporter.runtime.census.activeTransfer.requestId == localRequestId,
    "an ordinary same-guild requester remains a valid hop-zero endpoint")
timers[#timers].callback()
assert(reporter.runtime.census.activeTransfer == nil, "same-guild fixture completes before the routed request")

currentTime = currentTime + 2
local forgedRequestType, forgedRequestEnvelope, forgedRequestFields = OU.Protocol.RosterRequest(
    "forged-route", "olympus b", "snap-b", "ReporterB-Forever")
local forgedRequestPayload = assert(OU.Protocol.Encode(forgedRequestType, forgedRequestEnvelope, forgedRequestFields,
    "RemoteRequester-Forever", 2))
OU.Network.OnAddonMessage("OLYUNITED", forgedRequestPayload, "GUILD", "OrdinaryGuildmate-Forever")
assert(reporter.runtime.census.activeTransfer == nil and reporter.runtime.census.routes["forged-route"] == nil,
    "an unconfigured guild sender cannot inject a forwarded request and trigger roster traffic")

local whisperedRequestType, whisperedRequestEnvelope, whisperedRequestFields = OU.Protocol.RosterRequest(
    "wrong-whisper-leg", "olympus b", "snap-b", "ReporterB-Forever")
local whisperedRequestPayload = assert(OU.Protocol.Encode(whisperedRequestType, whisperedRequestEnvelope,
    whisperedRequestFields, "RequesterA-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", whisperedRequestPayload, "WHISPER", "ConnectorB-Forever")
assert(reporter.runtime.census.activeTransfer == nil and reporter.runtime.census.routes["wrong-whisper-leg"] == nil,
    "an ordinary reporter rejects the connector-to-connector whisper leg before roster disclosure")

local requestId = "route-1"
local requestType, requestEnvelope, requestFields = OU.Protocol.RosterRequest(requestId, "olympus b", "snap-b", "ReporterB-Forever")
local requestPayload = assert(OU.Protocol.Encode(requestType, requestEnvelope, requestFields, "RequesterA-Forever", 0))
requester.runtime.census.routes[requestId] = { role = "requester", requestId = requestId, guildKey = "olympus b",
    requester = "RequesterA-Forever", reporter = "ReporterB-Forever", snapshotId = "snap-b", expiresAt = currentTime + 360 }
requester.runtime.census.assemblies[requestId] = { state = "loading", requestId = requestId, reporter = "ReporterB-Forever",
    guildKey = "olympus b", snapshotId = "snap-b", expiresAt = currentTime + 360 }

useNode(connectorA)
OU.Network.OnAddonMessage("OLYUNITED", requestPayload, "GUILD", "RequesterA-Forever")
local aOut, aMessage = lastSent()
assert(aOut.distribution == "WHISPER" and aOut.target == "ConnectorB-Forever" and aMessage.hops == 1,
    "connector A forwards the guild request to connector B once")
assert(next(connectorA.runtime.census.assemblies) == nil, "connector A never applies endpoint state")

useNode(connectorB)
OU.Network.OnAddonMessage("OLYUNITED", aOut.payload, "WHISPER", "ConnectorA-Forever")
local bOut, bMessage = lastSent()
assert(bOut.distribution == "GUILD" and bMessage.hops == 2, "connector B forwards the request into reporter B's guild")
assert(next(connectorB.runtime.census.assemblies) == nil, "connector B never applies endpoint state")

useNode(reporter)
local callbackOK, callbackError = pcall(OU.Network.OnAddonMessage, "OLYUNITED", bOut.payload, "GUILD", "ConnectorB-Forever")
assert(callbackOK, "valid reporter CREQ must return a structured change to the real Core callback: " .. tostring(callbackError))
assert(reporter.runtime.census.activeTransfer, "the named reporter accepts one active transfer")
local transferTimer = timers[#timers]
assert(transferTimer.delay == 0.25, "roster pages are paced at four per second")
transferTimer.callback()
local pageOut, pageMessage = lastSent()
assert(pageOut.distribution == "GUILD" and pageMessage.type == "CPAGE" and pageMessage.hops == 0,
    "reporter starts every page reply with a fresh hop budget")

useNode(connectorB)
OU.Network.OnAddonMessage("OLYUNITED", pageOut.payload, "GUILD", "ReporterB-Forever")
local pageB, pageBMessage = lastSent()
assert(pageB.distribution == "WHISPER" and pageB.target == "ConnectorA-Forever" and pageBMessage.hops == 1,
    "connector B returns the page on its stored whisper leg")
useNode(connectorA)
OU.Network.OnAddonMessage("OLYUNITED", pageB.payload, "WHISPER", "ConnectorB-Forever")
local pageA, pageAMessage = lastSent()
assert(pageA.distribution == "GUILD" and pageAMessage.hops == 2,
    "connector A returns the page on its stored guild leg")
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", pageA.payload, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.assemblies[requestId].state == "complete",
    "only requester A assembles and applies the completed page")

local busyId = "route-busy"
currentTime = currentTime + 2
local busyType, busyEnvelope, busyFields = OU.Protocol.RosterRequest(busyId, "olympus b", "snap-b", "ReporterB-Forever")
local busyPayload = assert(OU.Protocol.Encode(busyType, busyEnvelope, busyFields, "RequesterA-Forever", 0))
requester.runtime.census.routes[busyId] = { role = "requester", requestId = busyId, guildKey = "olympus b",
    requester = "RequesterA-Forever", reporter = "ReporterB-Forever", snapshotId = "snap-b", expiresAt = currentTime + 360 }
requester.runtime.census.assemblies[busyId] = { state = "loading", requestId = busyId, reporter = "ReporterB-Forever",
    guildKey = "olympus b", snapshotId = "snap-b", expiresAt = currentTime + 360 }
useNode(connectorA); OU.Network.OnAddonMessage("OLYUNITED", busyPayload, "GUILD", "RequesterA-Forever"); local busyA = sent[#sent]
useNode(connectorB); OU.Network.OnAddonMessage("OLYUNITED", busyA.payload, "WHISPER", "ConnectorA-Forever"); local busyB = sent[#sent]
useNode(reporter); reporter.runtime.census.activeTransfer = { requestId = "already-active" }
OU.Network.OnAddonMessage("OLYUNITED", busyB.payload, "GUILD", "ConnectorB-Forever")
local failOut, failMessage = lastSent()
assert(failMessage.type == "CFAIL" and failMessage.fields[2] == "busy" and failMessage.hops == 0,
    "concurrent request receives a routed busy failure and is not queued")
useNode(connectorB); OU.Network.OnAddonMessage("OLYUNITED", failOut.payload, "GUILD", "ReporterB-Forever"); local failB, failBMessage = lastSent()
assert(failBMessage.hops == 1 and failB.distribution == "WHISPER", "failure returns through connector B")
useNode(connectorA); OU.Network.OnAddonMessage("OLYUNITED", failB.payload, "WHISPER", "ConnectorB-Forever"); local failA, failAMessage = lastSent()
assert(failAMessage.hops == 2 and failA.distribution == "GUILD", "failure returns through connector A")
useNode(requester); OU.Network.OnAddonMessage("OLYUNITED", failA.payload, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.assemblies[busyId].reason == "busy", "only requester applies the routed failure")
assert(requester.runtime.census.cooldowns["olympus b|requester"] == nil,
    "routed busy failures clear the requester cooldown for an actionable retry")

local oneRequester = node("RequesterOne-Forever", "Olympus A", {
    ["connectoraone-forever"] = "ConnectorAOne-Forever",
})
local oneConnector = node("ConnectorAOne-Forever", "Olympus A", {
    ["connectorreporterb-forever"] = "ConnectorReporterB-Forever",
}, true)
local connectorReporter = node("ConnectorReporterB-Forever", "Olympus B", {
    ["connectoraone-forever"] = "ConnectorAOne-Forever",
}, true)
connectorReporter.runtime.census.leases["olympus b"] = { guildKey = "olympus b", term = 12,
    leaseStartedAt = currentTime - 20, leaseSeq = 1, reporter = "ConnectorReporterB-Forever", receivedAt = currentTime }
connectorReporter.runtime.census.localCapture = { state = "complete", guild = "Olympus B", guildKey = "olympus b",
    snapshotId = "snap-connector", capturedAt = currentTime, total = 1, online = 1,
    names = { "ConnectorReporterB-Forever" } }

local oneId = "route-one-connector"
local oneType, oneEnvelope, oneFields = OU.Protocol.RosterRequest(
    oneId, "olympus b", "snap-connector", "ConnectorReporterB-Forever")
local onePayload = assert(OU.Protocol.Encode(oneType, oneEnvelope, oneFields, "RequesterOne-Forever", 0))
oneRequester.runtime.census.routes[oneId] = { role = "requester", requestId = oneId, guildKey = "olympus b",
    requester = "RequesterOne-Forever", reporter = "ConnectorReporterB-Forever",
    snapshotId = "snap-connector", expiresAt = currentTime + 360 }
oneRequester.runtime.census.assemblies[oneId] = { state = "loading", requestId = oneId,
    reporter = "ConnectorReporterB-Forever", guildKey = "olympus b", snapshotId = "snap-connector",
    expiresAt = currentTime + 360 }
useNode(oneConnector)
OU.Network.OnAddonMessage("OLYUNITED", onePayload, "GUILD", "RequesterOne-Forever")
local oneRequestOut, oneRequestMessage = lastSent()
assert(oneRequestOut.distribution == "WHISPER" and oneRequestOut.target == "ConnectorReporterB-Forever"
    and oneRequestMessage.hops == 1, "one-intermediary request reaches the elected reporter-connector at whisper hop one")
useNode(connectorReporter)
OU.Network.OnAddonMessage("OLYUNITED", oneRequestOut.payload, "WHISPER", "ConnectorAOne-Forever")
assert(connectorReporter.runtime.census.activeTransfer
    and connectorReporter.runtime.census.activeTransfer.requestId == oneId,
    "a linking-mode reporter accepts its legal trusted whisper endpoint")
timers[#timers].callback()
local onePageOut, onePageMessage = lastSent()
assert(onePageOut.distribution == "WHISPER" and onePageOut.target == "ConnectorAOne-Forever"
    and onePageMessage.type == "CPAGE" and onePageMessage.hops == 0,
    "reporter-connector replies on the stored upstream whisper with a fresh hop budget")
useNode(oneConnector)
OU.Network.OnAddonMessage("OLYUNITED", onePageOut.payload, "WHISPER", "ConnectorReporterB-Forever")
local onePageGuild, onePageGuildMessage = lastSent()
assert(onePageGuild.distribution == "GUILD" and onePageGuildMessage.hops == 1,
    "the sole intermediary returns the page to the requester guild at hop one")
useNode(oneRequester)
OU.Network.OnAddonMessage("OLYUNITED", onePageGuild.payload, "GUILD", "Untrusted-Forever")
assert((oneRequester.runtime.census.assemblies[oneId].received or 0) == 0,
    "one-intermediary page rejects an unconfigured guild sender")
local onePageWrongHop = assert(OU.Protocol.Encode(onePageGuildMessage.type, onePageGuildMessage.id,
    onePageGuildMessage.fields, onePageGuildMessage.origin, 0))
OU.Network.OnAddonMessage("OLYUNITED", onePageWrongHop, "GUILD", "ConnectorAOne-Forever")
assert((oneRequester.runtime.census.assemblies[oneId].received or 0) == 0,
    "one-intermediary page rejects a non-final hop")
OU.Network.OnAddonMessage("OLYUNITED", onePageGuild.payload, "GUILD", "ConnectorAOne-Forever")
assert(oneRequester.runtime.census.assemblies[oneId].state == "complete",
    "the configured local connector completes the reporter-as-connector page at hop one")

currentTime = currentTime + 2
local oneBusyId = "route-one-busy"
local oneBusyType, oneBusyEnvelope, oneBusyFields = OU.Protocol.RosterRequest(
    oneBusyId, "olympus b", "snap-connector", "ConnectorReporterB-Forever")
local oneBusyPayload = assert(OU.Protocol.Encode(
    oneBusyType, oneBusyEnvelope, oneBusyFields, "RequesterOne-Forever", 0))
oneRequester.runtime.census.routes[oneBusyId] = { role = "requester", requestId = oneBusyId, guildKey = "olympus b",
    requester = "RequesterOne-Forever", reporter = "ConnectorReporterB-Forever",
    snapshotId = "snap-connector", expiresAt = currentTime + 360 }
oneRequester.runtime.census.assemblies[oneBusyId] = { state = "loading", requestId = oneBusyId,
    reporter = "ConnectorReporterB-Forever", guildKey = "olympus b", snapshotId = "snap-connector",
    expiresAt = currentTime + 360 }
oneRequester.runtime.census.cooldowns["olympus b|requester"] = currentTime + 300
useNode(oneConnector); OU.Network.OnAddonMessage("OLYUNITED", oneBusyPayload, "GUILD", "RequesterOne-Forever")
local oneBusyRequest = sent[#sent]
useNode(connectorReporter); connectorReporter.runtime.census.activeTransfer = { requestId = "already-active" }
OU.Network.OnAddonMessage("OLYUNITED", oneBusyRequest.payload, "WHISPER", "ConnectorAOne-Forever")
local oneFailOut, oneFailMessage = lastSent()
assert(oneFailOut.distribution == "WHISPER" and oneFailOut.target == "ConnectorAOne-Forever"
    and oneFailMessage.type == "CFAIL" and oneFailMessage.fields[2] == "busy" and oneFailMessage.hops == 0,
    "reporter-connector returns a failure on the stored upstream whisper")
useNode(oneConnector)
OU.Network.OnAddonMessage("OLYUNITED", oneFailOut.payload, "WHISPER", "ConnectorReporterB-Forever")
local oneFailGuild, oneFailGuildMessage = lastSent()
assert(oneFailGuild.distribution == "GUILD" and oneFailGuildMessage.hops == 1,
    "the sole intermediary returns the failure to the requester guild at hop one")
useNode(oneRequester)
OU.Network.OnAddonMessage("OLYUNITED", oneFailGuild.payload, "GUILD", "Untrusted-Forever")
assert(oneRequester.runtime.census.assemblies[oneBusyId].state == "loading",
    "one-intermediary failure rejects an unconfigured guild sender")
local oneFailWrongHop = assert(OU.Protocol.Encode(oneFailGuildMessage.type, oneFailGuildMessage.id,
    oneFailGuildMessage.fields, oneFailGuildMessage.origin, 0))
OU.Network.OnAddonMessage("OLYUNITED", oneFailWrongHop, "GUILD", "ConnectorAOne-Forever")
assert(oneRequester.runtime.census.assemblies[oneBusyId].state == "loading",
    "one-intermediary failure rejects a non-final hop")
OU.Network.OnAddonMessage("OLYUNITED", oneFailGuild.payload, "GUILD", "ConnectorAOne-Forever")
assert(oneRequester.runtime.census.assemblies[oneBusyId].reason == "busy"
    and oneRequester.runtime.census.cooldowns["olympus b|requester"] == nil,
    "the configured local connector delivers the actionable reporter-as-connector failure at hop one")

local guarded, guardError = pcall(OU.OnNetworkChange, true)
assert(guarded, "Core must ignore malformed non-table network changes defensively: " .. tostring(guardError))

local lockedId = "route-locked"
requester.runtime.census.routes[lockedId] = { role = "requester", requestId = lockedId, guildKey = "olympus b",
    requester = "RequesterA-Forever", reporter = "ReporterB-Forever", snapshotId = "snap-b", expiresAt = currentTime + 360 }
requester.runtime.census.assemblies[lockedId] = { state = "loading", requestId = lockedId, reporter = "ReporterB-Forever",
    guildKey = "olympus b", snapshotId = "snap-b", expiresAt = currentTime + 360 }
local pageOne = assert(OU.Protocol.Encode("CPAGE", "p-route-locked-1", {
    lockedId, 1, 2, 2, "Hera-Forever",
}, "ReporterB-Forever", 0))
useNode(requester)
OU.Network.OnAddonMessage("OLYUNITED", pageOne, "GUILD", "ConnectorA-Forever")
assert((requester.runtime.census.assemblies[lockedId].received or 0) == 0,
    "remote requester rejects a reply below either legal final hop before assembly")
pageOne = assert(OU.Protocol.Encode("CPAGE", "p-route-locked-1", {
    lockedId, 1, 2, 2, "Hera-Forever",
}, "ReporterB-Forever", 2))
OU.Network.OnAddonMessage("OLYUNITED", pageOne, "GUILD", "Untrusted-Forever")
assert((requester.runtime.census.assemblies[lockedId].received or 0) == 0,
    "remote requester rejects an unconfigured guild sender")
OU.Network.OnAddonMessage("OLYUNITED", pageOne, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.assemblies[lockedId].received == 1,
    "remote requester accepts hop two from a configured local connector")
local pageTwo = assert(OU.Protocol.Encode("CPAGE", "p-route-locked-2", {
    lockedId, 2, 2, 2, "ReporterB-Forever",
}, "ReporterB-Forever", 2))
OU.Network.OnAddonMessage("OLYUNITED", pageTwo, "GUILD", "OtherConnector-Forever")
assert(requester.runtime.census.assemblies[lockedId].received == 1,
    "remote requester locks the first valid guild sender for subsequent pages")
OU.Network.OnAddonMessage("OLYUNITED", pageTwo, "GUILD", "ConnectorA-Forever")
assert(requester.runtime.census.assemblies[lockedId].state == "complete",
    "the locked connector can complete the remote reply")

local localId = "route-local"
requester.runtime.census.routes[localId] = { role = "requester", requestId = localId, guildKey = "olympus a",
    requester = "RequesterA-Forever", reporter = "LocalReporter-Forever", snapshotId = "snap-local", expiresAt = currentTime + 360 }
requester.runtime.census.assemblies[localId] = { state = "loading", requestId = localId, reporter = "LocalReporter-Forever",
    guildKey = "olympus a", snapshotId = "snap-local", expiresAt = currentTime + 360 }
local localWrong = assert(OU.Protocol.Encode("CPAGE", "p-route-local-1", {
    localId, 1, 1, 1, "LocalReporter-Forever",
}, "LocalReporter-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", localWrong, "GUILD", "LocalReporter-Forever")
assert((requester.runtime.census.assemblies[localId].received or 0) == 0,
    "same-guild requester rejects any reply that is not hop zero")
local localRight = assert(OU.Protocol.Encode("CPAGE", "p-route-local-1b", {
    localId, 1, 1, 1, "LocalReporter-Forever",
}, "LocalReporter-Forever", 0))
OU.Network.OnAddonMessage("OLYUNITED", localRight, "GUILD", "WrongReporter-Forever")
assert((requester.runtime.census.assemblies[localId].received or 0) == 0,
    "same-guild requester rejects a guild sender other than the bound reporter")
OU.Network.OnAddonMessage("OLYUNITED", localRight, "GUILD", "LocalReporter-Forever")
assert(requester.runtime.census.assemblies[localId].state == "complete",
    "same-guild requester accepts hop zero from the bound reporter")

local whisperedCandidate = assert(OU.Protocol.Encode("CCAND", "candidate-bad", { "olympus a", "Olympus A", 1 }, "RequesterA-Forever", 0))
useNode(connectorA)
local priorCandidates = OU.Util.Count(connectorA.runtime.census.candidates)
OU.Network.OnAddonMessage("OLYUNITED", whisperedCandidate, "WHISPER", "RequesterA-Forever")
assert(OU.Util.Count(connectorA.runtime.census.candidates) == priorCandidates, "election messages are guild-only and never forwarded")

local function fieldsFor(messageType, stamp)
    if messageType == "HELLO" then return { "member", "Olympus B", "Stormwind", 60, "WARRIOR" } end
    if messageType == "POST" then return { "Message " .. stamp, "member", "Olympus B" } end
    if messageType == "LREQ" then return { "Stormwind", "Need layer", currentTime + 600 } end
    if messageType == "LOFFER" then return { "missing-request", "Invite sent" } end
    if messageType == "EVENT" then return { currentTime + 900, "Event " .. stamp, "Details" } end
    if messageType == "CLAIM" then return { "Target" .. stamp .. "-Forever", currentTime + 300 } end
    return { "Target" .. stamp .. "-Forever" }
end

for _, messageType in ipairs({ "HELLO", "POST", "LREQ", "LOFFER", "EVENT", "CLAIM", "RELEASE" }) do
    local receiver = node("Receiver-Forever", "Olympus A", {
        ["connector-forever"] = "Connector-Forever",
        ["secondconnector-forever"] = "SecondConnector-Forever",
    }, true)
    useNode(receiver)
    currentTime = currentTime + 30
    local changes = 0
    OU.OnNetworkChange = function() changes = changes + 1 end

    local direct = assert(OU.Protocol.Encode(messageType, "direct-" .. messageType,
        fieldsFor(messageType, "direct"), "Direct-Forever", 0))
    local before = #sent
    OU.Network.OnAddonMessage("OLYUNITED", direct, "GUILD", "Direct-Forever")
    assert(changes == 1 and #sent > before, messageType .. " direct guild traffic should mutate and forward")

    local relayed = assert(OU.Protocol.Encode(messageType, "relay-" .. messageType,
        fieldsFor(messageType, "relay"), "Remote-Forever", 1))
    before = #sent
    OU.Network.OnAddonMessage("OLYUNITED", relayed, "GUILD", "Connector-Forever")
    assert(changes == 2 and #sent > before, messageType .. " configured guild relay should mutate and forward")

    local unconfigured = assert(OU.Protocol.Encode(messageType, "unconfigured-" .. messageType,
        fieldsFor(messageType, "unconfigured"), "Remote2-Forever", 1))
    before = #sent
    OU.Network.OnAddonMessage("OLYUNITED", unconfigured, "GUILD", "Untrusted-Forever")
    OU.Network.OnAddonMessage("OLYUNITED", unconfigured, "WHISPER", "Untrusted-Forever")
    assert(changes == 2 and #sent == before, messageType .. " must reject unconfigured guild and whisper relays")

    local forged = assert(OU.Protocol.Encode(messageType, "forged-" .. messageType,
        fieldsFor(messageType, "forged"), "Forged-Forever", 0))
    OU.Network.OnAddonMessage("OLYUNITED", forged, "GUILD", "Ordinary-Forever")
    assert(changes == 2, messageType .. " hop-zero origin must match the observed guild sender")
end

local duplicateReceiver = node("Receiver-Forever", "Olympus A", {
    ["connector-forever"] = "Connector-Forever", ["secondconnector-forever"] = "SecondConnector-Forever",
}, true)
useNode(duplicateReceiver)
currentTime = currentTime + 30
local duplicateChanges = 0
OU.OnNetworkChange = function() duplicateChanges = duplicateChanges + 1 end
local duplicatePost = assert(OU.Protocol.Encode("POST", "canonical-duplicate",
    { "One displayed message", "member", "Olympus B" }, "DisplayedAuthor-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", duplicatePost, "GUILD", "Connector-Forever")
OU.Network.OnAddonMessage("OLYUNITED", duplicatePost, "GUILD", "SecondConnector-Forever")
assert(duplicateChanges == 1 and #duplicateReceiver.runtime.feed == 1,
    "the origin plus message-id key must converge duplicate paths")
assert(duplicateReceiver.runtime.feed[1].sender == "DisplayedAuthor-Forever"
    and duplicateReceiver.runtime.feed[1].transportSender == "Connector-Forever",
    "origin remains the displayed author while transport remains diagnostic admission identity")

local rotated = node("Receiver-Forever", "Olympus A", { ["connector-forever"] = "Connector-Forever" }, false)
useNode(rotated)
currentTime = currentTime + 30
local rotatedChanges = 0
OU.OnNetworkChange = function() rotatedChanges = rotatedChanges + 1 end
for index = 1, 25 do
    local payload = assert(OU.Protocol.Encode("POST", "rotated-id-" .. index,
        { "Rotated " .. index, "member", "Olympus B" }, "Rotated" .. index .. "-Forever", 1))
    OU.Network.OnAddonMessage("OLYUNITED", payload, "GUILD", "Connector-Forever")
end
assert(rotatedChanges == 20 and #rotated.runtime.feed == 20,
    "rotating origins and ids through one connector must stop at the POST type budget")
currentTime = currentTime + 11
local recoveredPost = assert(OU.Protocol.Encode("POST", "rotated-recovered",
    { "Recovered", "member", "Olympus B" }, "Recovered-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", recoveredPost, "GUILD", "Connector-Forever")
assert(rotatedChanges == 21, "fixed receiver budgets must recover after the ten-second window")

local originRotationRuntime = OU.State.NewRuntime()
for index = 1, 100 do
    local messageType = index <= 20 and "POST" or (index <= 60 and "HELLO" or "LREQ")
    local message = { type = messageType, id = "transport-" .. index, origin = "Origin" .. index .. "-Forever",
        hops = 1, fields = fieldsFor(messageType, "transport" .. index) }
    OU.State.AdmitInbound(originRotationRuntime,
        { transportSender = "OneConnector-Forever", distribution = "GUILD", hops = 1 }, message, currentTime)
end
assert(originRotationRuntime.transportRate["oneconnector-forever"].count == 80,
    "one observed transport must have an 80-per-window ceiling despite rotated origins")

local fanout = node("Receiver-Forever", "Olympus A", {}, true)
for index = 1, OU.State.LIMITS.BRIDGES do
    fanout.db.bridges["fanout" .. index .. "-forever"] = "Fanout" .. index .. "-Forever"
end
useNode(fanout)
currentTime = currentTime + 30
local fanoutChanges, fanoutBefore = 0, #sent
OU.OnNetworkChange = function() fanoutChanges = fanoutChanges + 1 end
for index = 1, 11 do
    local origin = "Guildmate" .. index .. "-Forever"
    local payload = assert(OU.Protocol.Encode("LREQ", "fanout-message-" .. index,
        { "Stormwind", "Need layer", currentTime + 600 }, origin, 0))
    OU.Network.OnAddonMessage("OLYUNITED", payload, "GUILD", origin)
end
assert(fanoutChanges == 11 and #sent - fanoutBefore == 160,
    "connector fan-out must share one 160-delivery forwarding budget")

local governanceReceiver = node("Receiver-Forever", "Olympus A", {
    ["connector-forever"] = "Connector-Forever", ["secondconnector-forever"] = "SecondConnector-Forever",
}, true)
useNode(governanceReceiver)
currentTime = currentTime + 30
local candidatePost = assert(OU.Protocol.Encode("POST", "candidate-post",
    { "This must not appear", "member", "Olympus Newcomers" }, "Candidate-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", candidatePost, "GUILD", "Connector-Forever")
assert(governanceReceiver.db.guildGovernance["olympus newcomers"].state == "pending"
    and not governanceReceiver.db.participatingGuilds["olympus newcomers"]
    and #governanceReceiver.runtime.feed == 0,
    "a configured declaration creates only an untrusted candidate and the triggering POST stays rejected")
local untrustedCandidate = assert(OU.Protocol.Encode("HELLO", "candidate-untrusted",
    { "member", "Olympus Untrusted", "Stormwind", 60, "WARRIOR" }, "Candidate2-Forever", 1))
OU.Network.OnAddonMessage("OLYUNITED", untrustedCandidate, "GUILD", "Untrusted-Forever")
assert(not governanceReceiver.db.guildGovernance["olympus untrusted"],
    "an unconfigured sender cannot create even a side-band candidate")

local function governancePayload(id, target, display, action, generation, previous, decidedAt, hops, origin)
    return assert(OU.Protocol.Encode("GDEC", id,
        { "olympus", target, display, action, generation, previous, decidedAt },
        origin or "RemoteOfficer-Forever", hops or 1))
end
local illegalGuildZero = governancePayload("g-illegal-zero", "olympus zero", "Olympus Zero",
    "approve", 1, "-", currentTime, 0)
OU.Network.OnAddonMessage("OLYUNITED", illegalGuildZero, "GUILD", "Connector-Forever")
assert(not governanceReceiver.db.guildGovernance["olympus zero"], "guild hop-zero governance is always rejected")
local illegalWhisper = governancePayload("g-illegal-whisper", "olympus whisper", "Olympus Whisper",
    "approve", 1, "-", currentTime, 0)
OU.Network.OnAddonMessage("OLYUNITED", illegalWhisper, "WHISPER", "Untrusted-Forever")
assert(not governanceReceiver.db.guildGovernance["olympus whisper"], "unconfigured governance whispers are rejected")

local decisionTraffic = #sent
local approvedDecision = governancePayload("g-network-1", "olympus governed", "Olympus Governed",
    "approve", 1, "-", currentTime, 1, "DisplayedOfficer-Forever")
OU.Network.OnAddonMessage("OLYUNITED", approvedDecision, "GUILD", "Connector-Forever")
local governed = governanceReceiver.db.guildGovernance["olympus governed"]
assert(governed and governed.state == "approved" and governanceReceiver.db.participatingGuilds["olympus governed"]
    and governed.origin == nil and governed.transportSender == nil and #sent > decisionTraffic,
    "configured governance preserves origin only in transit/diagnostics and persists no actor or connector identity")
OU.Network.OnAddonMessage("OLYUNITED", approvedDecision, "GUILD", "SecondConnector-Forever")
assert(governanceReceiver.db.guildGovernance["olympus governed"].decisionId == "g-network-1",
    "canonical origin plus decision-id dedupe converges replay through another connector")

governanceReceiver.runtime.census.summaries["olympus governed"] = { guildKey = "olympus governed",
    guildDisplay = "Olympus Governed", capturedAt = currentTime, receivedAt = currentTime }
local guardTrustPrunes = 0
OU.ChatGuard = { OnGuildTrustChanged = function(database, at)
    assert(database == governanceReceiver.db and at == currentTime,
        "trust-change cache pruning should receive the current database and decision time")
    guardTrustPrunes = guardTrustPrunes + 1
end }
currentTime = currentTime + 1
local wrongPrevious = governancePayload("g-network-fork", "olympus governed", "Olympus Governed",
    "deny", 2, "g-wrong", currentTime, 1)
OU.Network.OnAddonMessage("OLYUNITED", wrongPrevious, "GUILD", "Connector-Forever")
assert(governanceReceiver.db.guildGovernance["olympus governed"].state == "conflict"
    and not governanceReceiver.db.participatingGuilds["olympus governed"]
    and not governanceReceiver.runtime.census.summaries["olympus governed"] and guardTrustPrunes == 1,
    "a predecessor fork fails closed and immediately prunes former participation state")
OU.ChatGuard = nil
local staleDecision = governancePayload("g-network-stale", "olympus stale", "Olympus Stale",
    "approve", 1, "-", currentTime - 601, 1)
OU.Network.OnAddonMessage("OLYUNITED", staleDecision, "GUILD", "Connector-Forever")
assert(not governanceReceiver.db.guildGovernance["olympus stale"], "stale governance traffic cannot mutate trust")
local futureDecision = governancePayload("g-network-future", "olympus future", "Olympus Future",
    "approve", 1, "-", currentTime + 61, 1)
OU.Network.OnAddonMessage("OLYUNITED", futureDecision, "GUILD", "Connector-Forever")
assert(not governanceReceiver.db.guildGovernance["olympus future"], "future governance traffic cannot mutate trust")

local governanceBudget = node("Receiver-Forever", "Olympus A", {
    ["connector-forever"] = "Connector-Forever", ["secondconnector-forever"] = "SecondConnector-Forever",
}, false)
useNode(governanceBudget)
currentTime = currentTime + 30
local governanceBaseline = OU.Util.Count(governanceBudget.db.guildGovernance)
for index = 1, 25 do
    local payload = governancePayload("g-budget-" .. index, "olympus govern " .. index,
        "Olympus Govern " .. index, "approve", 1, "-", currentTime, 1, "Origin" .. index .. "-Forever")
    OU.Network.OnAddonMessage("OLYUNITED", payload, "GUILD",
        index % 2 == 0 and "Connector-Forever" or "SecondConnector-Forever")
end
assert(OU.Util.Count(governanceBudget.db.guildGovernance) == governanceBaseline + 20,
    "rotated origins and ids share the dedicated 20-per-window governance budget")
currentTime = currentTime + 11
local recoveredDecision = governancePayload("g-budget-recovered", "olympus recovered", "Olympus Recovered",
    "approve", 1, "-", currentTime, 1)
OU.Network.OnAddonMessage("OLYUNITED", recoveredDecision, "GUILD", "Connector-Forever")
assert(governanceBudget.db.guildGovernance["olympus recovered"],
    "governance admission recovers after the fixed ten-second window")

local joining = node("Joining-Forever", "Olympus Joining", { ["connector-forever"] = "Connector-Forever" }, false)
joining.identity.role, joining.db.guestMode = "guest", true
useNode(joining)
currentTime = currentTime + 30
local censusChanges, originalGuildChange = 0, OU.Census.OnGuildChanged
OU.Census.OnGuildChanged = function() censusChanges = censusChanges + 1 end
local joiningDecision = governancePayload("g-joining", "olympus joining", "Olympus Joining",
    "approve", 1, "-", currentTime, 1)
OU.Network.OnAddonMessage("OLYUNITED", joiningDecision, "GUILD", "Connector-Forever")
OU.Census.OnGuildChanged = originalGuildChange
assert(joining.db.participatingGuilds["olympus joining"] and OU.Identity.role == "member" and censusChanges == 1,
    "approval of the current exact guild starts only future membership and Census work")

local originBudget = OU.State.NewRuntime()
local acceptedOrigin = 0
for index = 1, 21 do
    local allowed = OU.State.AdmitInbound(originBudget,
        { transportSender = "Connector-Forever", distribution = "WHISPER", hops = 1 },
        { type = "CPAGE", id = "origin-budget-" .. index, origin = "OneOrigin-Forever", hops = 1, fields = {} }, currentTime)
    if allowed then acceptedOrigin = acceptedOrigin + 1 end
end
assert(acceptedOrigin == 20 and originBudget.rate["oneorigin-forever"].count == 20,
    "same-origin rotated ids stop at the independent 20-per-window origin ceiling")
currentTime = currentTime + 11
assert(OU.State.AdmitInbound(originBudget,
    { transportSender = "Connector-Forever", distribution = "WHISPER", hops = 1 },
    { type = "CPAGE", id = "origin-recovered", origin = "OneOrigin-Forever", hops = 1, fields = {} }, currentTime),
    "the origin ceiling recovers after its ten-second window")

local globalBudget = OU.State.NewRuntime()
local admittedGlobal = 0
local function admitGroup(messageType, count, offset)
    for index = 1, count do
        local serial = offset + index
        local allowed = OU.State.AdmitInbound(globalBudget,
            { transportSender = "Connector" .. ((serial - 1) % 4 + 1) .. "-Forever", distribution = "GUILD", hops = 1 },
            { type = messageType, id = "global-" .. serial, origin = "Origin" .. serial .. "-Forever", hops = 1,
                fields = fieldsFor(messageType, "global" .. serial) }, currentTime)
        if allowed then admittedGlobal = admittedGlobal + 1 end
    end
end
admitGroup("HELLO", 40, 0)
admitGroup("LREQ", 40, 40)
admitGroup("CFAIL", 80, 80)
assert(admittedGlobal == 160 and globalBudget.receive.global.count == 160,
    "mixed traffic across several transports shares the 160-message receiver-global ceiling")
local globalAllowed, globalReason = OU.State.AdmitInbound(globalBudget,
    { transportSender = "Connector5-Forever", distribution = "GUILD", hops = 1 },
    { type = "CPAGE", id = "global-overflow", origin = "Overflow-Forever", hops = 1, fields = {} }, currentTime)
assert(not globalAllowed and globalReason == "receiver rate limit",
    "receiver-global saturation rejects another otherwise independent type and connector")

local memoryBudget = OU.State.NewRuntime()
memoryBudget.feed[1] = { text = string.rep("x", OU.State.LIMITS.DYNAMIC_BYTES) }
local memoryAllowed, memoryReason = OU.State._Test.CapacityAllowed(memoryBudget,
    { type = "HELLO", id = "memory-overflow", origin = "Origin-Forever", fields = {} }, currentTime)
assert(not memoryAllowed and memoryReason == "memory capacity",
    "the aggregate dynamic-memory ceiling fails closed independently of count limits")

useNode(governanceReceiver)
local sendBefore = #sent
local sentDecision = OU.Network.SendGuildDecision({ id = "g-local-send", origin = "Zeus-Forever",
    fields = { "olympus", "olympus manual", "Olympus Manual", "approve", 1, "-", currentTime } })
assert(sentDecision and #sent - sendBefore == 2
    and sent[#sent].distribution == "WHISPER" and sent[#sent - 1].distribution == "WHISPER",
    "local decisions are sent only as whispers to the explicitly configured connectors")

local modernChat = C_ChatInfo
C_ChatInfo = nil
assert(not OU.Network.RegisterPrefix(), "missing modern prefix API must fail safely")
local fallbackSent, fallbackError = OU.Network._Test.SendRaw("payload", "GUILD")
assert(not fallbackSent and fallbackError == OU.L.ERROR_ADDON_CHAT,
    "missing modern send API must fail safely without a legacy global")
C_ChatInfo = modernChat

print("Olympus United network tests passed")
