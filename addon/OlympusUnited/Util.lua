local ADDON_NAME, OU = ...

OU = OU or {}
OU.NAME = ADDON_NAME or "OlympusUnited"
OU.VERSION = "0.5.0"

local Util = {}
OU.Util = Util

local function Trim(value)
    value = tostring(value or "")
    return value:match("^%s*(.-)%s*$") or ""
end

function Util.Trim(value)
    return Trim(value)
end

function Util.SanitizeText(value, maxBytes)
    value = Trim(value)
    value = value:gsub("[%c]", " ")
    value = value:gsub("|", "/")
    value = value:gsub("%s+", " ")

    maxBytes = tonumber(maxBytes) or 120
    if #value <= maxBytes then return value end

    local cut = value:sub(1, maxBytes)
    while #cut > 0 and cut:byte(#cut) >= 128 and cut:byte(#cut) < 192 do
        cut = cut:sub(1, -2)
    end
    return Trim(cut)
end

function Util.NormalizeName(name, realm)
    if not Util.IsPlainString(name) or (realm ~= nil and not Util.IsPlainString(realm)) then return nil end
    name = Trim(name)
    if name == "" then return nil end

    if not name:find("-", 1, true) then
        realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName())
        if realm and realm ~= "" then name = name .. "-" .. realm end
    end

    return name:lower()
end

function Util.IsPlain(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "string" or type(value) == "number" or type(value) == "boolean"
end

function Util.IsPlainString(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

function Util.NormalizeGuild(guild)
    if not Util.IsPlainString(guild) then return nil end
    guild = (guild:match("^ *(.-) *$") or ""):gsub(" +", " ")
    if guild == "" then return nil end
    return guild:lower()
end

function Util.NormalizeRosterName(name)
    if not Util.IsPlainString(name) then return nil end
    name = Trim(name):gsub("%s+", " ")
    if name == "" then return nil end
    return name:lower()
end

function Util.ShortName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^[^-]+") or name
end

function Util.IsParticipatingGuild(guild, database)
    local key = Util.NormalizeGuild(guild)
    database = database or OU.DB
    return key ~= nil and type(database) == "table" and type(database.participatingGuilds) == "table"
        and database.participatingGuilds[key] ~= nil
end

-- Kept as the compatibility name used by the shipped modules. This is an
-- exact configured lookup; it no longer performs substring classification.
function Util.IsOlympusGuild(guild, database)
    return Util.IsParticipatingGuild(guild, database)
end

function Util.Count(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

function Util.CopyDefaults(target, defaults)
    target = type(target) == "table" and target or {}
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = Util.CopyDefaults({}, value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            Util.CopyDefaults(target[key], value)
        end
    end
    return target
end

function Util.Now()
    if GetServerTime then return GetServerTime() end
    if time then return time() end
    return os and os.time and os.time() or 0
end

function Util.Uptime()
    return GetTime and GetTime() or 0
end

function Util.MakeID(kind)
    OU._idCounter = (OU._idCounter or 0) + 1
    local player = UnitName and UnitName("player") or "player"
    player = Util.ShortName(player):lower():gsub("[^%w]", "")
    if player == "" then player = "player" end
    local stamp = Util.Now()
    local uptime = math.floor(Util.Uptime() * 1000) % 1000000
    return ("%s-%s-%d-%d-%d"):format(kind or "msg", player, stamp, uptime, OU._idCounter)
end

function Util.FormatAge(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%d min"):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return ("%d hr"):format(math.floor(seconds / 3600)) end
    return ("%d days"):format(math.floor(seconds / 86400))
end

function Util.FormatStart(timestamp)
    timestamp = tonumber(timestamp) or 0
    local remaining = timestamp - Util.Now()
    if remaining <= 0 then return "starting now" end
    if remaining < 3600 then return ("in %d min"):format(math.max(1, math.floor(remaining / 60))) end
    if remaining < 86400 then return ("in %d hr %d min"):format(math.floor(remaining / 3600), math.floor((remaining % 3600) / 60)) end
    return date and date("%b %d %H:%M", timestamp) or tostring(timestamp)
end

function Util.TableRemoveValue(array, value)
    for index = #array, 1, -1 do
        if array[index] == value then table.remove(array, index) end
    end
end

function Util.SortedValues(map, comparator)
    local values = {}
    for _, value in pairs(map or {}) do values[#values + 1] = value end
    table.sort(values, comparator)
    return values
end

function Util.PlayerIdentity()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if not name and UnitName then name = UnitName("player") end
    if realm and realm ~= "" then name = name .. "-" .. realm end

    local guild = ""
    if type(GetGuildInfo) == "function" then
        local ok, value = pcall(GetGuildInfo, "player")
        if ok and Util.IsPlainString(value) then guild = value end
    end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local level = UnitLevel and UnitLevel("player") or 0
    local className, classFile = UnitClass and UnitClass("player") or nil, nil
    if UnitClass then className, classFile = UnitClass("player") end

    return {
        name = name or "Unknown",
        guild = guild or "",
        zone = zone or "",
        level = level or 0,
        className = className or "",
        classFile = classFile or "",
        role = Util.IsParticipatingGuild(guild) and "member" or "guest",
    }
end
