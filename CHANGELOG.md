# Changelog

## 1.0.0

First release under the BonusRollGate name, for World of Warcraft: Midnight 12.1
(Interface 120100). Descended from BonusRollFilter 8.3.0.2, which last worked in
Battle for Azeroth.

### Rebuilt for the Voidforge

- Filtering is organised around the content that actually offers bonus rolls in
  Midnight: raid bosses, Mythic+ dungeons, Bountiful Delves and Nightmare Prey.
  The old Mists-through-Battle-for-Azeroth boss tables are gone.
- Boss lists are built from the Encounter Journal at runtime instead of being
  hardcoded, so a new raid tier no longer needs an addon update. Any encounter or
  difficulty the addon is offered a roll on is remembered and added to the
  options, so nothing can fall off the list.
- Every raid difficulty — LFR, Normal, Heroic, Mythic, Mythic flexible, Story and
  World — gets a "hide everything" switch plus a per-boss list. Dungeons, Delves
  and world bosses get their own switches.
- Added a master on/off switch and a toggle for the chat message.

### Fixes carried over from BonusRollFilter

- Loads at all. The previous version declared Interface 80300.
- `/brg config` works. The old `/brf config` called
  `InterfaceOptionsFrame_OpenToCategory`, removed in Dragonflight 10.0.
- The version print works. It called the global `GetAddOnMetadata`, since moved
  to `C_AddOns`.
- The Mythic+ keystone threshold works, and is now a slider. It read the
  keystone level through `C_ChallengeMode.GetCompletionInfo`, which Blizzard
  replaced with `GetChallengeCompletionInfo`.
- No more errors on difficulties the addon didn't know about. The old filter
  indexed its settings table by difficulty ID directly, so Delves (208), Story
  (220) and World Raid (250) each threw "attempt to index a nil value".
- A bonus roll prompt re-issued after a loading screen no longer loses its
  difficulty and encounter; that data is now cached per spell ID.
- Dropped the ElvUI timer-bar workaround. Blizzard's own `BonusRollFrame` OnShow
  sets those frame levels now.
- Refreshed the bundled Ace3 libraries: AceConfigDialog 78 to 92, AceGUI 39 to
  41, AceDB 27 to 33, and the rest.
