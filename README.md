# BonusRollGate

Hides the World of Warcraft bonus roll prompt for the bosses, difficulties and
content types you don't want to spend Voidcores on.

Midnight's Voidforge gives you a limited number of Nebulous Voidcores each week,
and a roll prompt pops for raid bosses, Mythic+ dungeons, Bountiful Delves and
Nightmare Prey alike. BonusRollGate keeps the prompt out of your way for the
content you've decided not to spend on, so the only prompts you see are ones
you might actually take.

## Features

- **Per-boss filtering for raids.** Every raid difficulty — LFR, Normal, Heroic,
  Mythic, Mythic flexible, Story and World — gets its own boss list plus a
  "hide everything at this difficulty" switch.
- **Boss lists build themselves.** Encounters come from the Encounter Journal at
  runtime instead of a hardcoded table, so a new raid tier needs no addon update.
  Anything the addon is actually offered a roll on is remembered and added to the
  options too, so nothing falls off the list.
- **Mythic+ keystone threshold.** Hide rolls in all Mythic+ dungeons, or only
  below a keystone level you pick.
- **Delves, dungeons and world bosses** each get their own switch.
- **Nothing is lost.** A hidden roll is only hidden — `/brg show` brings it back
  as long as the timer hasn't run out.

## Commands

| Command | Effect |
| --- | --- |
| `/brg` | List the available commands |
| `/brg show` | Re-open a roll that was hidden |
| `/brg config` | Open the settings panel |

`/bonusrollgate` works anywhere `/brg` does.

## Installation

Download from CurseForge, or clone this repository directly into
`World of Warcraft/_retail_/Interface/AddOns/BonusRollGate`. The Ace3 libraries
are vendored in `Libs/`, so a clone works as-is with no build step.

## Credits

BonusRollGate is descended from [BonusRollFilter](https://github.com/chawan/BonusRollFilter)
by Chawan, which was released into the public domain and last updated in January
2020. The filtering logic and options UI have since been rewritten for Midnight
12.1; the debt is to the original idea and to six years of it working well.

## License

MIT — see [LICENSE](LICENSE).
