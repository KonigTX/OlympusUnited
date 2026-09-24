# Changelog

## 0.5.0 - 2026-09-24

- Added an opt-in chat guard that hides public chat and incoming whispers from players WoW has recently confirmed belong to a non-Olympus guild.
- Kept unknown players visible instead of guessing, and exempted friends and current party or raid members.
- Learned guild membership passively from visible player units, group rosters, existing Who results, and explicitly loaded Olympus Census rosters.
- Avoided automatic Who scans, global API replacement, invite automation, and retroactive chat-history deletion.
- Added the chat-tab checkbox and `/ou mute on|off`, with the setting available only to current Olympus guild members.

## 0.4.0 - 2026-09-24

- Turned Updates into Olympus Chat, an Olympus-wide guild chat restricted to characters currently in an Olympus guild.
- Added 30-second slow mode, configurable from 5 to 300 seconds in the chat view or with `/ou slow`.
- Enforced slow mode on send, receive, and forwarding so one fast sender cannot fill every connected window.
- Kept guest access for the other coordination tools while hiding chat history and controls from guests.
- Added current-member declarations to cross-guild chat traffic and rejected chat that does not come through the guild or configured connectors.

## 0.3.0 - 2026-09-23

- Added a low-traffic distributed Census with one deterministic reporter per guild, fresh/stale/expired totals, and failover.
- Added explicit on-demand, paced member-name lists with bounded routing, cooldowns, progress, and failure states.
- Rebuilt the window with Blizzard-native nine-slice framing, rock fill, compact five-workflow navigation, scrollable ledgers, and title-band help.
- Preserved Updates, Layers, Events, People, connector, recruiting, notification, saved-setting, and protocol-v1 behavior.
- Added fail-closed Forever guild-roster capture that reads names and presence only; ranks and notes are never transmitted.

## 0.2.1 - 2026-09-23

- Replaced the missing stock crest with the supplied Olympus mountain logo.
- Removed the header subtitle and its antagonistic tagline.
- Added an in-addon help guide explaining updates, layers, guild links, and guest access.

## 0.2.0 - 2026-09-23

- Rewrote every player-facing label, instruction, empty state, alert, error, and slash-command response.
- Renamed technical concepts such as transports, relays, and peers to clear player language.
- Added friendlier setup guidance for cross-guild links, layer requests, events, guests, and recruiting tools.
- Expanded the UI smoke test to protect the new approachable copy.

## 0.1.0 - 2026-09-23

- Initial Olympus United release.
- Added same-guild transport and a trusted captain-to-captain whisper bridge for cross-guild traffic.
- Added network feed, layer requests and offers, event board, and peer directory.
- Added recruiting claims, contact cooldowns, and a private do-not-contact list.
- Added protocol validation, deduplication, sanitization, and rate limiting.
