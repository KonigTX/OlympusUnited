# Olympus United

Olympus United is an opt-in in-game home for participating Olympus guilds in World of Warcraft: Forever. Version 0.5.0 adds an optional, context-aware chat guard alongside member-only Olympus Chat, Layers, Events, Census, and People.

## Download and install

1. Extract `OlympusUnited-0.5.0.zip`.
2. Copy the included `OlympusUnited` folder into the Forever client's `Interface/AddOns` directory.
3. Restart the client or type `/reload` when you are ready.
4. Type `/ou` to open the window.

The addon is built for the Forever beta (`## Interface: 16001, 16000`) and has no dependencies.

## Using it

1. Open Olympus United with `/ou` and choose Olympus Chat, Layers, Events, Census, or People.
2. Use Census to see the combined membership reported by participating guilds, with online counts shown separately when WoW makes them available.
3. Select a guild and press **Load member list** only when you need names. Member lists are never sent automatically.

The `[?]` button in the title bar explains the five workflows in game.

## Olympus Chat

Olympus Chat is an Olympus-wide guild chat for characters currently in an Olympus guild. Characters using guest mode cannot read or send it. Same-guild membership is established by WoW's guild channel; cross-guild messages travel only through configured guild connectors and include the sender's current Olympus-member declaration.

Slow mode defaults to 30 seconds per speaker and can be set from 5 to 300 seconds beside the chat box or with `/ou slow SECONDS`. The sender enforces the wait before sending, and every receiving copy enforces its own delay before displaying or forwarding another message from that speaker. This keeps an altered or outdated sender from filling everyone else's chat window.

Connector trust is still important: World of Warcraft addons do not provide cryptographic guild identity across guilds. A deliberately modified connector could lie, so only add the agreed Olympus coordinators under **People**.

## Optional chat guard

Enable **Mute non-Olympus chat** on the Olympus Chat tab—or use `/ou mute on`—to hide public chat and incoming whispers from players WoW has recently confirmed belong to another guild.

The guard learns passively when WoW exposes a player's guild through a target, mouseover, nameplate, group roster, an existing Who result, or an Olympus member list you explicitly load in Census. Census names are used only for the current session. The guard does not launch Who searches, replace Blizzard functions, delete existing chat lines, decline invitations, or send anything over the Olympus network.

Unknown players remain visible. Friends and current party or raid members are always exempt, and guild, officer, party, raid, and instance chat are never filtered. Observations expire after 24 hours so a player who changes guild is not muted indefinitely. The option works only while the current character is in an Olympus guild.

## How Census works

One current addon member reports for each guild so automatic traffic stays small: one short update per minute and one combined summary about every 15 minutes. If that person leaves, another addon member takes over automatically.

Fresh and stale reports contribute to the network total for up to 45 minutes. Expired reports remain visible but are excluded. Missing counts are shown as unavailable, never as zero. A valid reported zero remains zero.

Full member names move only after someone presses **Load member list**. The reporter sends the names back in small pieces so the game stays responsive. Only character names are included—never guild ranks, member notes, officer notes, achievements, professions, or public-chat messages. Requested lists remain in memory for the current session and are not saved or exported.

The census is a practical snapshot from participating addon users, not an authoritative Blizzard-wide count and not a cryptographic identity system.

## Guild links

Guildmates with Olympus United connect automatically for same-guild activity. To connect participating guilds, coordinators add one another under **People** using full `Character-Realm` names and press **Start linking**. Those trusted online connectors carry Olympus Chat and census traffic between guilds. No public chat is generated.

Remote Census traffic is opt-in at each receiving character. An ordinary member who wants remote guild totals or member-list requests adds their own guild's linking coordinator as a trusted connector under **People**. A Census reporter can remain an ordinary member with linking off, but must also trust that local coordinator before accepting relayed cross-guild roster requests. Unconfigured members continue to receive same-guild Census only.

Guest mode is explicit (`/ou guest on`) and requires a willing online connector. It does not impersonate an Olympus guild member.

## Commands

- `/ou` — open or close Olympus United.
- `/ou census` — open Census.
- `/ou census status` — summarize current census totals in chat.
- `/ou census help` — explain Census in player language.
- `/ou chat MESSAGE` — send to Olympus Chat (`/ou say` still works).
- `/ou slow SECONDS` — set per-speaker slow mode from 5 to 300 seconds.
- `/ou mute on|off` — toggle the known non-Olympus chat guard.
- `/ou layer NOTE` — request layer help for ten minutes.
- `/ou event MINUTES TITLE` — share an event.
- `/ou bridge on|off` — start or stop linking guilds.
- `/ou bridge add NAME-REALM` — add a guild connector.
- `/ou bridge remove NAME-REALM` — remove a guild connector.
- `/ou bridge list` — show guild links.
- `/ou guest on|off` — toggle explicit guest access.
- `/ou notify on|off` — toggle event and layer-offer notifications.
- `/ou claim NAME` — reserve a recruiting contact for five minutes.
- `/ou release NAME` — release a recruiting claim.
- `/ou dnc add|remove|list NAME` — manage the private do-not-contact list.
- `/ou status` — show connection and runtime counts.
- `/ou help` — show all command help.

## Privacy and safety

`OlympusUnitedDB` stores settings, the chat slow-mode delay, the chat-guard toggle, a bounded local cache of recently observed character names and guilds, trusted connectors, recruiting cooldown timestamps, the private do-not-contact list, and the window position. Chat history, Census reports, requested member lists, election state, routes, and transfers are session-only. Version 0.5.0 adds its settings without resetting existing ones.

Incoming addon messages are length-bounded, validated, deduplicated, rate-limited, and accepted only through guild traffic or configured connectors. Unknown message types remain isolated under protocol version 1, so older clients keep their existing workflows and ignore the new Census types safely.

Olympus United never automates recruitment messages, guild invites, public chat, Who searches, or external data collection. Chat-guard observations stay on your computer and are never sent through Olympus United.

## License

MIT.
