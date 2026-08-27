# Changelog

## 1.1.2

### Fixed

- Boss counts now count only bosses the difficulty lists.

### Documentation

- Screenshots of the General, Raids and Dungeons tabs.

## 1.1.1

### Fixed

- Per-boss lists came up empty; the journal walk now selects each instance
  first. ([#1](https://github.com/JoesphG/BonusRollGate/issues/1), diagnosed by
  @lostmimic)
- World bosses no longer appear on the raid difficulty tabs.
  ([#2](https://github.com/JoesphG/BonusRollGate/issues/2))

### Changed

- Each difficulty lists only the bosses it is offered at.
- Removed the Mythic flexible tab; difficulty 233 obeys Mythic.
- Boss lists cover the current tier only.
  ([#3](https://github.com/JoesphG/BonusRollGate/issues/3))

## 1.1.0

### Options panel

- Difficulties are colour-coded on the item-quality ladder, so the sidebar reads
  as a difficulty ladder at a glance.
- Each raid difficulty in the tree shows what it is doing: a boss count, or
  "(all)" when the whole difficulty is hidden.
- An "At a glance" panel on the General tab lists everything currently filtered
  in one place.
- Settings are grouped into boxed sections rather than separated by bare rules,
  and the per-boss list greys out when the whole difficulty is already hidden.
- Added "Clear every filter", behind a confirmation.

### Commands

- `/brg` now opens the options panel as well as listing the commands.
- Added `/brg hide` to dismiss the prompt on screen without changing settings.
- Added `/brg toggle` to turn filtering on and off.
- Added `/brg status` to print the current filters to chat.

### Under the hood

- Added a test suite: `tests/` stubs the WoW client so the filter can be driven
  and asserted outside the game. 56 assertions covering the decision table,
  the `/brg show` guards, the post-loading-screen re-prompt, and the options
  tree.
- Added CI: luacheck, stylua and the test suite on every push, plus a packaging
  dry run so a broken TOC or .pkgmeta is caught before a release is tagged.
- Added a weekly job that checks the vendored Ace3 copy against the WoWAce SVN
  and opens a pull request when it drifts. Stale vendored libraries are what
  made this addon's predecessor unusable.

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
