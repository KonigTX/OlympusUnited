local _, OU = ...

local Roster = { pending = nil }
OU.GuildRoster = Roster

local REQUIRED = {
    { "C_GuildInfo", "GuildRoster" },
    { "C_Club", "GetGuildClubId" },
    { "C_Club", "GetClubInfo" },
    { "C_Club", "GetClubMembers" },
    { "C_Club", "GetMemberInfo" },
}

local function Namespace(name)
    if name == "C_GuildInfo" then return C_GuildInfo end
    if name == "C_Club" then return C_Club end
end

function Roster.Capabilities()
    for _, path in ipairs(REQUIRED) do
        local owner = Namespace(path[1])
        if type(owner) ~= "table" or type(owner[path[2]]) ~= "function" then
            return false, "missing-api", path[1] .. "." .. path[2]
        end
    end
    return true
end

local function Call(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok then return nil, "api-error" end
    return value
end

local function IsPlainTable(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "table"
end

local function PresenceKind(value)
    if issecretvalue and issecretvalue(value) then return nil, "secret" end
    local presence = Enum and Enum.ClubMemberPresence
    if type(presence) ~= "table" then return nil, "unknown" end
    if value == presence.Online or value == presence.OnlineMobile or value == presence.Away or value == presence.Busy then return true end
    if value == presence.Offline then return false end
    if value == presence.Unknown then return nil, "unknown" end
    return nil, "unknown"
end

function Roster.ReadComplete()
    local capable, reason = Roster.Capabilities()
    if not capable then return { ok = false, reason = reason } end

    local clubId, callErr = Call(C_Club.GetGuildClubId)
    if callErr or clubId == nil or (issecretvalue and issecretvalue(clubId)) then return { ok = false, reason = "clubs-unavailable" } end
    local clubInfo
    clubInfo, callErr = Call(C_Club.GetClubInfo, clubId)
    if callErr or not IsPlainTable(clubInfo) then return { ok = false, reason = "club-info" } end
    local guildName = clubInfo.name
    local memberCount = clubInfo.memberCount
    if not OU.Util.IsPlainString(guildName)
        or (memberCount ~= nil and ((issecretvalue and issecretvalue(memberCount))
            or type(memberCount) ~= "number" or memberCount < 0 or memberCount > 1000)) then
        return { ok = false, reason = "club-shape" }
    end
    local memberIds
    memberIds, callErr = Call(C_Club.GetClubMembers, clubId, nil)
    if callErr or not IsPlainTable(memberIds) or #memberIds > 1000 then return { ok = false, reason = "member-list" } end

    local names, seen, online, onlineKnown = {}, {}, 0, true
    for _, memberId in ipairs(memberIds) do
        if issecretvalue and issecretvalue(memberId) then return { ok = false, reason = "secret-member" } end
        local info
        info, callErr = Call(C_Club.GetMemberInfo, clubId, memberId)
        if callErr or not IsPlainTable(info) then return { ok = false, reason = "member-info" } end
        local name = info.name
        local presence = info.presence
        local key = OU.Util.NormalizeRosterName(name)
        if not key or seen[key] then return { ok = false, reason = key and "duplicate-name" or "secret-name" } end
        if #OU.Protocol._Test.Escape(name) > 48 then return { ok = false, reason = "name-too-long" } end
        seen[key] = true
        names[#names + 1] = OU.Util.Trim(name)
        local isOnline, presenceReason = PresenceKind(presence)
        if presenceReason then onlineKnown = false elseif isOnline then online = online + 1 end
    end
    if memberCount ~= nil and memberCount ~= #names then return { ok = false, reason = "count-mismatch" } end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return { ok = true, guild = guildName, guildKey = OU.Util.NormalizeGuild(guildName), names = names,
        total = #names, online = onlineKnown and online or nil, capturedAt = OU.Util.Now() }
end

local function Finish(token, result)
    if not Roster.pending or Roster.pending.token ~= token then return end
    local callback = Roster.pending.callback
    Roster.pending = nil
    callback(result)
end

function Roster.Request(callback)
    if type(callback) ~= "function" then return false, "callback-required" end
    if Roster.pending then return false, "busy" end
    local capable, reason = Roster.Capabilities()
    if not capable then callback({ ok = false, reason = reason }); return false, reason end
    local token = OU.Util.MakeID("roster")
    Roster.pending = { token = token, callback = callback, startedAt = OU.Util.Uptime() }
    local ok = pcall(C_GuildInfo.GuildRoster)
    if not ok then Finish(token, { ok = false, reason = "request-failed" }); return false, "request-failed" end
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function() Finish(token, { ok = false, reason = "timeout" }) end)
    end
    return true
end

function Roster.OnEvent(event)
    if event ~= "GUILD_ROSTER_UPDATE" or not Roster.pending then return false end
    local token = Roster.pending.token
    Finish(token, Roster.ReadComplete())
    return true
end

Roster._Test = { PresenceKind = PresenceKind, Finish = Finish }
