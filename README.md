# Olympus United

Olympus United is an opt-in in-game home for participating Olympus guilds in World of Warcraft: Forever. Version 0.6.0 brings guild review, safer cross-guild connections, a more reliable Census, and a clearer native interface alongside member-only Olympus Chat, Layers, Events, and People.

## Download and install

1. Extract `OlympusUnited-0.6.0.zip`.
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

Olympus Chat is an Olympus-wide guild chat for characters whose exact normalized guild name is locally approved. `OLYMPUS` is the one fixed trust root. Normalization folds case and repeated ASCII spaces only; prefixes, suffixes, substrings, and Unicode lookalikes do not grant membership. Characters using guest mode cannot read or send member chat.

Olympus-like guild names noticed through information WoW already shows, or declared through an already configured connector, can appear as untrusted review candidates. Discovery never grants chat, member status, chat-guard classification, or Census participation. Only a guild leader or officer in exact `OLYMPUS`, verified at the moment of the action through the Forever client APIs, can Approve, Deny, or Reconsider a candidate on that character.

Slow mode defaults to 30 seconds per speaker and can be set from 5 to 300 seconds beside the chat box or with `/ou slow SECONDS`. The sender enforces the wait before sending, and every receiving copy enforces its own delay before displaying or forwarding another message from that speaker. This keeps an altered or outdated sender from filling everyone else's chat window.

Connector trust is still important: World of Warcraft addons do not provide cryptographic guild identity across guilds. Trust decisions carried by a configured connector are accepted as a manual connector-trust choice, not proof that the remote origin is an officer. A deliberately modified connector could lie, so only add the agreed Olympus coordinators under **People**.

## Optional chat guard

Enable **Mute non-Olympus chat** on the Olympus Chat tab—or use `/ou mute on`—to hide public chat and incoming whispers from players WoW has recently confirmed belong to a guild outside the local exact approved list.

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

Configured connectors can carry bounded Approve, Deny, and Reconsider decisions. Each receiver still enforces its own exact local state. Replayed, stale, forked, or out-of-order decisions fail closed; a conflict removes the affected non-root guild from participation until a locally verified `OLYMPUS` leader or officer resolves it.

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
- `/ou guild review` — list untrusted guild names awaiting review (verified `OLYMPUS` leaders and officers only).
- `/ou guild approve EXACT NAME` — approve one exact reviewed name.
- `/ou guild deny EXACT NAME` — deny one exact reviewed name and suppress repeat evidence.
- `/ou guild reconsider EXACT NAME` — remove approval or denial and return the exact name to review.
- `/ou guild status EXACT NAME` — show the local trust state for one exact name.
- `/ou guest on|off` — toggle explicit guest access.
- `/ou notify on|off` — toggle event and layer-offer notifications.
- `/ou claim NAME` — reserve a recruiting contact for five minutes.
- `/ou release NAME` — release a recruiting claim.
- `/ou dnc add|remove|list NAME` — manage the private do-not-contact list.
- `/ou status` — show connection and runtime counts.
- `/ou help` — show all command help.

## Privacy and safety

`OlympusUnitedDB` stores typed settings, the exact participating-guild state, privacy-minimal guild-review records, the chat slow-mode delay, the chat-guard toggle, a bounded local cache of recently observed character names and guilds, trusted connectors, recruiting cooldown timestamps, the private do-not-contact list, and a repaired safe window position. Guild-review records contain only the guild display/key state, bounded timestamps and counters, evidence bits, and current decision metadata; they never contain chat text, roster names, player names, GUIDs, origins, connectors, raw messages, or decision history. Chat history, Census reports, requested member lists, election state, and routes are session-only.

The 0.6.0 state migration rebuilds SavedVariables from supported typed fields, drops unknown or malformed data, pins exact `OLYMPUS`, and preserves a non-root guild only when it has a valid current approved governance record. Saved and runtime collections have hard caps and expiry rules; saturation rejects new work without evicting a live safety or trust decision.

Incoming addon messages are length-bounded, strictly validated, deduplicated, and admitted through layered per-origin, per-connector, per-type, receiver-wide, forwarding, and memory limits. Relayed traffic is bound to the actual configured transport identity while the original author remains the displayed author. Protocol version 1 remains unchanged; the additive guild-decision message is rejected safely by older copies that do not know it.

Olympus United never automates recruitment messages, guild invites, public chat, Who searches, or external data collection. Chat-guard observations stay on your computer and are never sent through Olympus United.

## License

MIT.
