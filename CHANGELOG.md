# Changelog

## 1.2.3

### Added

- Prey hunts get a switch of their own, covering all three hunt difficulties.
- `/brg last` describes the last roll the addon saw.

## 1.2.2

### Fixed

- World bosses were filtered off their own page; all of them now list.

### Changed

- Delves is a sidebar item of its own, and Seen in play is a page rather
  than a section riding on it.

## 1.2.1

### Fixed

- World bosses have their own per-boss page; the World page used to list the
  whole raid tier over again.
- Boss lists read in Encounter Journal order instead of alphabetically.

### Removed

- The World Boss switch under Content types, now that the page covers it.

## 1.2.0

### Changed

- Rewritten options window: a standalone panel with a sidebar, replacing the
  Ace3 config dialog.
- Profiles are managed in the window rather than by AceDBOptions.
- Blizzard's AddOns list now holds a button that opens the window.

### Removed

- AceConfig-3.0, AceGUI-3.0 and AceDBOptions-3.0 are no longer shipped.

## 1.1.3

### Added

- Discord server for support: https://discord.gg/zHT3bGEQ52

### Documentation

- CurseForge description in Markdown, with permalinked screenshots.

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

- Difficulties are colour-coded on the item-quality ladder.
- The tree shows each difficulty's boss count, or "(all)".
- An "At a glance" panel lists everything currently filtered.
- Settings are grouped into boxed sections.
- Added "Clear every filter", behind a confirmation.

### Commands

- `/brg` opens the options panel as well as listing the commands.
- Added `/brg hide`, `/brg toggle` and `/brg status`.

### Under the hood

- Added a test suite: `tests/` stubs the WoW client so the filter runs outside
  the game.
- Added CI: luacheck, stylua, tests and a packaging dry run.
- Added a weekly job that checks the vendored Ace3 against WoWAce.

## 1.0.0

First release under the BonusRollGate name, for Midnight 12.1 (Interface
120100). Descended from BonusRollFilter 8.3.0.2.

### Rebuilt for the Voidforge

- Filtering covers what actually offers rolls in Midnight: raid bosses, Mythic+,
  Bountiful Delves and Nightmare Prey.
- Boss lists are built from the Encounter Journal at runtime. Anything the addon
  is offered a roll on is remembered and added to the options.
- Every raid difficulty gets a "hide everything" switch plus a per-boss list.
  Dungeons, Delves and world bosses get their own switches.
- Added a master on/off switch and a toggle for the chat message.

### Fixes carried over from BonusRollFilter

- Loads at all; the previous version declared Interface 80300.
- `/brg config` works; `InterfaceOptionsFrame_OpenToCategory` is gone.
- The version print works; `GetAddOnMetadata` moved to `C_AddOns`.
- The Mythic+ threshold works, and is now a slider;
  `GetCompletionInfo` became `GetChallengeCompletionInfo`.
- No more errors on unknown difficulties — Delves (208), Story (220) and World
  Raid (250) each threw on a nil index.
- A prompt re-issued after a loading screen keeps its difficulty and encounter,
  cached per spell ID.
- Dropped the ElvUI timer-bar workaround; Blizzard sets those frame levels now.
- Refreshed the bundled Ace3 libraries.
