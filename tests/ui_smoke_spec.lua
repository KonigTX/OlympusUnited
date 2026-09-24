local root = assert(os.getenv("OLYMPUS_UNITED_ROOT"), "OLYMPUS_UNITED_ROOT is required")
local now, frames, timers, sent = 300000, {}, {}, {}
local currentGuild, leaderValue, officerValue = "OLYMPUS", false, false
local leaderUnavailable, secretRoles = false, false
unpack = unpack or table.unpack

local function NewWidget(kind, parent, template)
    local widget = { kind = kind or "Frame", parent = parent, template = template, scripts = {}, events = {}, shown = true,
        text = "", width = 640, height = 400, points = {}, children = {}, enabled = true, focused = false }
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:RegisterEvent(name) self.events[name] = true end
    function widget:UnregisterEvent(name) self.events[name] = nil end
    function widget:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value and true or false end
    function widget:IsShown() return self.shown end
    function widget:SetText(value) self.text = tostring(value or "") end
    function widget:GetText() return self.text end
    function widget:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
    function widget:SetSize(width, height) self.width, self.height = width, height end
    function widget:SetWidth(width) self.width = width end
    function widget:SetHeight(height) self.height = height end
    function widget:GetWidth() return self.width end
    function widget:GetHeight() return self.height end
    function widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function widget:GetPoint(index) local p = self.points[index or 1] or { "CENTER", UIParent, "CENTER", 0, 0 }; return table.unpack(p) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints() self.points = { { "ALL" } } end
    function widget:SetColorTexture(...) self.color = { ... } end
    function widget:SetTexture(path) self.texture = path; return path ~= nil and path ~= "" end
    function widget:SetHorizTile(value) self.horizTile = value end
    function widget:SetVertTile(value) self.vertTile = value end
    function widget:SetTextColor(...) self.textColor = { ... } end
    function widget:SetJustifyH(value) self.justify = value end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetClampedToScreen(value) self.clamped = value end
    function widget:EnableMouse(value) self.mouse = value end
    function widget:SetMovable(value) self.movable = value end
    function widget:RegisterForDrag(...) self.dragButtons = { ... } end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetScrollChild(child) self.scrollChild = child end
    function widget:SetAutoFocus(value) self.autoFocus = value end
    function widget:ClearFocus() self.focused = false end
    function widget:SetFocus() self.focused = true end
    function widget:HasFocus() return self.focused end
    function widget:SetFont(path, size, flags) self.font = { path, size, flags } end
    function widget:GetFont() local f = self.font or { "Fonts/FRIZQT__.TTF", 12, "" }; return f[1], f[2], f[3] end
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function widget:AddLine(value) self.lines = self.lines or {}; self.lines[#self.lines + 1] = value end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:CreateFontString(name, layer, font) local child = NewWidget("FontString", self, font); self.children[#self.children + 1] = child; return child end
    function widget:CreateTexture(name, layer, templateName, subLevel) local child = NewWidget("Texture", self, templateName); self.children[#self.children + 1] = child; return child end
    return widget
end

UIParent = NewWidget("Frame")
GameTooltip = NewWidget("GameTooltip")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = NewWidget("ChatFrame")
SlashCmdList = {}
NineSliceUtil = { ApplyLayoutByName = function(frame, name) frame.nineSlice = name end }
C_Texture = { GetAtlasInfo = function() return nil end }
ChatFrameUtil = { AddMessageEventFilter = function() return true end }

function CreateFrame(kind, name, parent, template)
    local frame = NewWidget(kind, parent, template)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function GetServerTime() return now end
function GetTime() return now end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Zeus" end
function UnitFullName() return "Zeus", "Forever" end
function UnitLevel() return 60 end
function UnitClass() return "Warrior", "WARRIOR" end
function GetGuildInfo() return currentGuild end
function IsGuildLeader() if leaderUnavailable then error("unavailable") end return leaderValue end
C_GuildInfo = { IsGuildOfficer = function() return officerValue end }
function issecretvalue(value) return secretRoles and type(value) == "boolean" end
function GetRealZoneText() return "Stormwind City" end
function IsInGuild() return true end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, payload, distribution, target)
        sent[#sent + 1] = { prefix = prefix, payload = payload, distribution = distribution, target = target }
        return true
    end,
}
C_PartyInfo = { InviteUnit = function() return true end }
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }

local OU = {}
for _, file in ipairs({ "Util.lua", "CensusLogic.lua", "Strings.lua", "Protocol.lua", "State.lua", "ChatGuard.lua",
    "GuildTrust.lua", "Network.lua", "GuildRoster.lua", "Census.lua", "Core.lua", "UIPrimitives.lua", "UI.lua", "Commands.lua" }) do
    assert(loadfile(root .. "/addon/OlympusUnited/" .. file))("OlympusUnited", OU)
end

OlympusUnitedDB = { window = { point = "BROKEN", x = 0/0, y = math.huge }, guildGovernance = {} }
for index, name in ipairs({ "Olympus I", "Olympus II", "Olympus III", "Olympus IV" }) do
    local key = OU.Util.NormalizeGuild(name)
    OlympusUnitedDB.guildGovernance[key] = { displayName = name, state = "approved",
        firstSeenAt = now - 10, lastSeenAt = now, evidenceMask = 1, observations = 1, deniedEvidenceMask = 0,
        generation = 1, decisionId = "g-ui-" .. index, decidedAt = now, sourceClass = "local-officer" }
end

local controller = assert(OU._Test.Controller)
controller.scripts.OnEvent(controller, "ADDON_LOADED", "OlympusUnited")
controller.scripts.OnEvent(controller, "PLAYER_LOGIN")
assert(OU.UI.frame and OU.UI.frame.nineSlice == "ButtonFrameTemplateNoPortrait", "window uses Blizzard's native nine-slice")
assert(OU.UI.frame.ouTitle.text == "Olympus United" and OU.UI.frame.ouTitle.points[1][5] == -6,
    "title sits at y=-6 inside the native title band")
assert(OU.UI.frame.ouClose.template == "UIPanelCloseButtonDefaultAnchors", "close X uses Blizzard's default anchors")
assert(OU.UI.crest.texture == "Interface\\AddOns\\OlympusUnited\\Media\\OlympusLogo", "bundled Olympus logo is retained")
assert(#UISpecialFrames == 1 and UISpecialFrames[1] == "OlympusUnitedFrame", "Escape closes the window")
assert(not OU.UI.frame:IsShown(), "window starts hidden")
local safePoint, _, _, safeX, safeY = OU.UI.frame:GetPoint(1)
assert(safePoint == "CENTER" and safeX == 0 and safeY == 0,
    "window construction consumes only the repaired safe anchor and coordinates")

OU.Open()
assert(OU.UI.frame:IsShown() and OU.UI.status.text:find("OLYMPUS", 1, true), "opening shows member status")
assert(OU.UI.tabs.FEED:GetText() == "Olympus Chat" and OU.UI.tabs.CENSUS:GetText() == "Census", "all five tabs use player language")
assert(not OU.UI.tabs.FEED:IsEnabled() and OU.UI.tabs.LAYERS:IsEnabled(),
    "the active tab uses Blizzard's disabled-button state instead of a custom highlight")
OU.UI.helpButton.scripts.OnEnter(OU.UI.helpButton)
assert(GameTooltip:IsShown() and GameTooltip.text == "How to use Olympus United" and #GameTooltip.lines == 5,
    "[?] hover provides the concise guide without a modal")
assert(GameTooltip.lines[1]:find("only for current Olympus guild members", 1, true)
    and GameTooltip.lines[2]:find("Exact approved guilds", 1, true)
    and GameTooltip.lines[3]:find("linking coordinator", 1, true),
    "[?] guide explains chat membership, automatic local features, and remote setup in player language")
OU.UI.helpButton.scripts.OnLeave()
assert(not GameTooltip:IsShown(), "help tooltip hides on leave")

OU.UI.input:SetText("World boss in 15 — meet at the gate.")
OU.UI.composeButton.scripts.OnClick()
assert(#OU.Runtime.feed == 1, "Olympus Chat composer remains usable")
OU.UI.chatDelayInput:SetText("45")
OU.UI.chatDelayInput.scripts.OnEnterPressed(OU.UI.chatDelayInput)
assert(OU.DB.chat.delaySeconds == 45 and OU.UI.chatDelayInput:GetText() == "45",
    "Olympus Chat slow mode is configurable in the main window")
OU.UI.chatMuteCheck:SetChecked(true)
OU.UI.chatMuteCheck.scripts.OnClick(OU.UI.chatMuteCheck)
assert(OU.DB.chat.muteNonOlympus == true and OU.UI.chatMuteCheck:IsShown(),
    "known non-Olympus chat muting is an opt-in control in Olympus Chat")
local memberIdentity = OU.Identity
OU.Identity = { name = "Visitor-Forever", guild = "", role = "guest" }
OU.RefreshUI()
assert(OU.UI.rows[1].heading.text == "Olympus Chat is for guild members"
    and not OU.UI.input:IsShown() and not OU.UI.composeButton:IsShown() and not OU.UI.chatDelayInput:IsShown()
    and not OU.UI.chatMuteCheck:IsShown(),
    "guest mode shows a clear member-only state and no chat controls")
OU.Identity = memberIdentity
OU.RefreshUI()
OU.UI.tabs.LAYERS.scripts.OnClick()
assert(OU.UI.tabs.FEED:IsEnabled() and not OU.UI.tabs.LAYERS:IsEnabled(),
    "changing tabs moves the native disabled-button state")
OU.UI.input:SetText("Need the event layer")
OU.UI.composeButton.scripts.OnClick()
assert(next(OU.Runtime.layers), "Layers composer remains usable")
OU.UI.tabs.EVENTS.scripts.OnClick()
OU.UI.input:SetText("15 World boss :: Meet at the gate")
OU.UI.composeButton.scripts.OnClick()
assert(next(OU.Runtime.events), "Events composer remains usable")
OU.UI.tabs.MEMBERS.scripts.OnClick()
assert(OU.UI.rows[1].body.text:find("agreed", 1, true)
    and OU.UI.rows[1].body.text:find("configured", 1, true)
    and OU.UI.rows[1].body.text:find("not because", 1, true),
    "People explains the bounded manual connector-trust boundary without claiming verified identity")
assert(OU.UI.composeButton.text == "Add connector", "People uses an action-specific connector label")
OU.UI.input:SetText("Athena-Forever")
OU.UI.composeButton.scripts.OnClick()
assert(OU.DB.bridges["athena-forever"], "People connector composer remains usable")
assert(OU.UI.status.text:find("1 link", 1, true) and not OU.UI.status.text:find("1 links", 1, true)
    and OU.UI.rows[1].meta.text:find("1 link", 1, true), "one guild connector uses singular player-facing copy")
assert(OU.UI.rows[1].action:IsShown(), "People linking control remains visible")
OU.UI.rows[1].action.scripts.OnClick()
assert(OU.DB.bridgeMode, "People linking control remains clickable")

local function VisibleRow(text)
    for _, row in ipairs(OU.UI.rows) do
        if row:IsShown() and row.heading.text == text then return row end
    end
end
OU.GuildTrust.Observe("Olympus Review", "local-visible", now, OU.DB)
leaderValue = true
OU.RefreshUI()
local reviewSection, pendingRow = VisibleRow("Guild review"), VisibleRow("Olympus Review")
assert(reviewSection and pendingRow and pendingRow.action:IsShown() and pendingRow.secondaryAction:IsShown()
    and pendingRow.action.text == "Approve" and pendingRow.secondaryAction.text == "Deny",
    "a verified root leader sees exactly Approve and Deny on each pending review row")
pendingRow.secondaryAction.scripts.OnClick()
local deniedRow = VisibleRow("Olympus Review")
assert(OU.DB.guildGovernance["olympus review"].state == "denied" and deniedRow.action.text == "Reconsider",
    "a denied decision remains untrusted and exposes Reconsider in the status list")
OU.GuildTrust.Observe("Olympus Command", "local-visible", now, OU.DB)
SlashCmdList.OLYMPUSUNITED("guild approve Olympus Command")
assert(OU.DB.guildGovernance["olympus command"].state == "approved"
    and OU.DB.participatingGuilds["olympus command"], "slash and UI actions share the same governance mutator")

OU.GuildTrust.Observe("Olympus Hidden", "local-visible", now, OU.DB)
leaderValue, officerValue = false, false
OU.RefreshUI()
assert(not VisibleRow("Guild review") and not VisibleRow("Olympus Hidden"),
    "ordinary root members see neither candidate identities nor governance actions")
currentGuild, leaderValue = "Other Guild", true
OU.RefreshUI()
assert(not VisibleRow("Guild review") and not VisibleRow("Olympus Hidden"),
    "a leader flag outside exact OLYMPUS does not reveal governance actions")
currentGuild = "Olympus Local Discovery"
controller.scripts.OnEvent(controller, "PLAYER_GUILD_UPDATE")
assert(OU.DB.guildGovernance["olympus local discovery"].state == "pending"
    and not OU.DB.participatingGuilds["olympus local discovery"] and OU.Identity.role == "guest"
    and not VisibleRow("Guild review"),
    "a guild-change event discovers a local Olympus-like name without granting status or review authority")
currentGuild, leaderValue, leaderUnavailable = "OLYMPUS", false, true
controller.scripts.OnEvent(controller, "PLAYER_GUILD_UPDATE")
assert(not VisibleRow("Guild review") and not VisibleRow("Olympus Hidden"),
    "unavailable exact-build authority evidence hides governance actions")
leaderUnavailable, secretRoles = false, true
OU.RefreshUI()
assert(not VisibleRow("Guild review") and not VisibleRow("Olympus Hidden"),
    "secret role results hide governance actions")
secretRoles, leaderValue, officerValue = false, false, true
OU.RefreshUI()
assert(VisibleRow("Guild review") and VisibleRow("Olympus Hidden"),
    "a fresh valid officer result independently restores the bounded review surface")
leaderValue, officerValue = true, false
OU.RefreshUI()
assert(VisibleRow("Guild review") and VisibleRow("Olympus Hidden"),
    "a fresh valid leader result restores the bounded review surface")

OU.UI.tabs.CENSUS.scripts.OnClick()
assert(not OU.UI.input:IsShown() and not OU.UI.composeButton:IsShown(), "Census reclaims composer space")
assert(OU.UI.rows[1].heading.text == "Guild roster unavailable" and OU.UI.rows[1].action.text == "Retry roster",
    "local roster failure is retryable and never shown as zero")
OU.Runtime.census.localCapture = { state = "loading" }
OU.RefreshUI()
assert(OU.UI.rows[1].heading.text == "Loading your guild roster…", "local loading state is distinct")
OU.Runtime.census.localCapture = { state = "complete", guildKey = "olympus i", guild = "Olympus I" }
OU.Runtime.census.summaries = {}
OU.RefreshUI()
assert(OU.UI.rows[1].heading.text == "No guild reports yet."
    and OU.UI.rows[1].body.text:find("Your guild works automatically", 1, true)
    and OU.UI.rows[1].body.text:find("People", 1, true),
    "empty Census gives the exact local-versus-remote setup action and no false total")

OU.Runtime.census.summaries = {
    ["olympus i"] = { guildKey = "olympus i", guildDisplay = "Olympus I", term = 1, revision = 1,
        snapshotId = "snap-i", capturedAt = now - 60, total = 100, online = 10, reporter = "Athena-Forever" },
    ["olympus ii"] = { guildKey = "olympus ii", guildDisplay = "Olympus II", term = 1, revision = 1,
        snapshotId = "snap-ii", capturedAt = now - 1300, total = 50, online = nil, reporter = "Hera-Forever" },
    ["olympus iii"] = { guildKey = "olympus iii", guildDisplay = "Olympus III", term = 1, revision = 1,
        snapshotId = "snap-iii", capturedAt = now - 2800, total = 70, online = 7, reporter = "Apollo-Forever" },
    ["olympus iv"] = { guildKey = "olympus iv", guildDisplay = "Olympus IV", term = 1, revision = 1,
        snapshotId = "snap-iv", capturedAt = now - 30, total = 0, online = 0, reporter = "Zero-Forever" },
}
local beforeOpenTraffic = #sent
OU.RefreshUI()
assert(OU.UI.rows[1].body.text == "150 members" and OU.UI.rows[1].count.text == "— online",
    "total-first header excludes expired reports and keeps online unavailable distinct")
assert(OU.UI.rows[3].heading.text == "Olympus I" and OU.UI.rows[4].heading.text == "Olympus II"
    and OU.UI.rows[5].heading.text == "Olympus III" and OU.UI.rows[6].heading.text == "Olympus IV",
    "guild ledger uses hierarchy order")
assert(OU.UI.rows[3].chevron.text == "+", "Census uses a plain-text expand marker without emoji glyphs")
assert(OU.UI.rows[3].body.text:find("Fresh", 1, true) and OU.UI.rows[4].body.text:find("Stale", 1, true)
    and OU.UI.rows[5].body.text:find("Expired", 1, true), "fresh, stale, and expired states are explicit")
assert(OU.UI.rows[4].count.text:find("— online", 1, true) and OU.UI.rows[6].count.text == "0 members • 0 online",
    "unavailable online and valid numeric zero are not conflated")
OU.UI.rows[3].scripts.OnMouseDown()
assert(#sent == beforeOpenTraffic and OU.UI.rows[3].action.text == "Load member list",
    "expanding a guild never fetches automatically and exposes one explicit action")
assert(OU.UI.rows[3].chevron.text == "-", "expanded Census rows use a plain-text collapse marker")
OU.UI.rows[3].action.scripts.OnClick()
assert(#sent == beforeOpenTraffic + 1, "Load member list emits exactly one request")
local requestId
for id, assembly in pairs(OU.Runtime.census.assemblies) do if assembly.guildKey == "olympus i" then requestId = id end end
assert(requestId, "explicit request creates visible assembly state")
local assembly = OU.Runtime.census.assemblies[requestId]
assembly.pageCount, assembly.received = 18, 6
OU.RefreshUI()
assert(OU.UI.rows[3].action.text == "Loading 6 of 18 pages" and not OU.UI.rows[3].action:IsEnabled(),
    "loading progress is visible and repeat clicks are disabled")
assembly.state, assembly.names, assembly.loadedAt = "complete", {}, now
for index = 1, 1000 do assembly.names[index] = ("Member%04d-Forever"):format(index) end
OU.RefreshUI()
assert(#OU.UI.rows[3].memberLabels == 1000 and OU.UI.content.height > 20000,
    "the single Census scroll child exposes every name without clamping")
OU.Runtime.census.cooldowns["olympus i|requester"] = nil
OU.Runtime.census.summaries["olympus i"].snapshotId = "snap-i-new"
OU.RefreshUI()
local visibleOldNames = 0
for _, label in ipairs(OU.UI.rows[3].memberLabels or {}) do if label:IsShown() then visibleOldNames = visibleOldNames + 1 end end
assert(visibleOldNames == 0 and OU.UI.rows[3].hint.text:find("report changed", 1, true),
    "a newer summary hides completed names from the old snapshot and explains the change; visible="
        .. tostring(visibleOldNames) .. " hint=" .. tostring(OU.UI.rows[3].hint.text))
OU.Runtime.census.summaries["olympus i"].snapshotId = "snap-i"
assembly.state, assembly.reason = "error", "busy"
OU.Runtime.census.cooldowns["olympus i|requester"] = now + OU.CensusLogic.CONSTANTS.REQUEST_COOLDOWN
OU.Census.ReceiveFailure(OU.Runtime, { fields = { requestId, "busy" } }, now)
OU.RefreshUI()
assert(OU.UI.rows[3].hint.text == "Reporter is busy. Try again shortly." and OU.UI.rows[3].action:IsEnabled(),
    "busy is a player-facing retry state with an enabled action")
assembly.reason = "snapshot"
OU.RefreshUI()
assert(OU.UI.rows[3].hint.text:find("report changed", 1, true), "snapshot changes are explained without protocol language")

SlashCmdList.OLYMPUSUNITED("census status")
SlashCmdList.OLYMPUSUNITED("census help")
SlashCmdList.OLYMPUSUNITED("census")
assert(OU.UI.activeTab == "CENSUS", "/ou census opens the Census workflow")
SlashCmdList.OLYMPUSUNITED("status")
assert(DEFAULT_CHAT_FRAME.text ~= nil, "existing slash status remains callable")

print("Olympus United UI smoke test passed")
