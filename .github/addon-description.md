<!--
Source for the CurseForge and Wago project descriptions. Neither store has an
API for the description, so both are pasted by hand: CurseForge's Description
editor with the format set to Markdown not WYSIWYG, and Wago's About tab.

Image URLs are permalinks into this repo, pinned to a commit so they cannot
break. If CurseForge strips them, re-upload the PNGs on the project's Images tab
and swap in the CDN URLs it gives back.
-->

**Spend your Voidcores where you meant to.**

BonusRollGate hides the bonus roll prompt for the bosses, difficulties and
content types you have already decided against, so the only prompts you see are
ones worth reading. Nothing is lost — a hidden roll is only hidden, and
`/brg show` brings it back while the timer is still running.

## Features

- **Per-boss filtering for raids.** Looking For Raid, Normal, Heroic, Mythic,
  Story and World each get their own boss list plus a "hide everything at this
  difficulty" switch.
- **Boss lists build themselves.** Encounters come from the Encounter Journal at
  runtime, not a hardcoded table, so a new raid tier needs no addon update. The
  lists cover the current tier, and each difficulty holds only the bosses it is
  actually offered at.
- **Mythic+ keystone threshold.** Hide every Mythic+ roll, or only those below a
  keystone level you pick.
- **Delves, dungeons and world bosses** each get their own switch.
- **Nothing is lost.** `/brg show` reopens a hidden roll.

## The General tab

The master switch, the chat announcement toggle, and an "At a glance" panel that
lists every filter currently in force — whole difficulties and boss counts
together — so you never have to open each tab to find out what is being hidden.
"Clear every filter" resets the lot behind a confirmation.

![The General tab](https://raw.githubusercontent.com/JoesphG/BonusRollGate/cb499841b3907a3a9dabd15f43724903ca3f067f/images/General.png)

## The Raids tab

Each raid difficulty is its own page. The sidebar doubles as a summary: `(all)`
means every roll at that difficulty is hidden, a number means that many
individual bosses are. Each list holds only the bosses that difficulty is
actually offered at, so a one-boss instance run at World, Normal, Heroic and
Mythic stays off the Looking For Raid list.

![The Raids tab](https://raw.githubusercontent.com/JoesphG/BonusRollGate/cb499841b3907a3a9dabd15f43724903ca3f067f/images/raids.png)

## The Dungeons tab

Mythic+ can be hidden outright or only below a keystone level you pick, so the
+2 you ran for the weekly stops prompting while your real keys still do. Normal,
Heroic and Mythic dungeons get plain switches underneath.

![The Dungeons tab](https://raw.githubusercontent.com/JoesphG/BonusRollGate/cb499841b3907a3a9dabd15f43724903ca3f067f/images/dungeons.png)

## Bringing a roll back

A hidden roll is hidden, not declined. BonusRollGate says so in chat, with the
command to reopen it:

![The chat announcement when a roll is hidden](https://raw.githubusercontent.com/JoesphG/BonusRollGate/cb499841b3907a3a9dabd15f43724903ca3f067f/images/enable%20roll%20window.png)

`/brg show` puts the prompt back on screen, and you can still spend the Voidcore
as long as the roll timer has not run out. So a filter you set months ago and
forgot about costs you nothing: you see the line, you type six characters, the
window is back.

The announcement is a toggle on the General tab. Turn it off once the filters
settle down and hidden rolls pass in silence.

## Commands

| Command | Effect |
| --- | --- |
| `/brg` | Open the options panel and list the commands |
| `/brg config` | Open the options panel |
| `/brg show` | Bring back the roll that was just hidden |
| `/brg hide` | Dismiss the prompt on screen, without changing settings |
| `/brg toggle` | Turn filtering on and off |
| `/brg status` | Print the current filters to chat |
| `/brg last` | Describe the last roll the addon saw |

## Support

Bugs, questions and ideas all go to Discord: **[discord.gg/zHT3bGEQ52](https://discord.gg/zHT3bGEQ52)**

`#support` for bugs and help, `#ideas` for feature requests, `#announcements`
for release notes.

A bug report gets fixed faster with:

```
Addon version:      (from /brg status)
Game version:       (bottom of the character select screen)
What I expected:
What happened:
Steps to reproduce:
Lua error (if any):
```

`/brg status` prints the version and every filter currently in force, which is
usually the whole diagnosis. If there is a Lua error, paste the full text from
BugSack rather than the first line.

Source: [github.com/JoesphG/BonusRollGate](https://github.com/JoesphG/BonusRollGate) — MIT licensed.
Descended from BonusRollFilter by Chawan (public domain).
