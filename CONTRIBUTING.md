# Contributing to Halo 1: Combat Evolved Achievement Checker

The whole project exists because the game and the Xbox API only report a
percentage. Every contribution that turns a number into a mission name is
worth having.

## What would help most

1. **Confirm the bonus mission ids.** `e10`, `e20` and `e30` are Boarding
   Action, The Most Dangerous Game and Heavy Burden in some order. Finish one
   of them, run `.\halo-1-combat-evolved-achievement-checker.ps1 -Raw`, and see which id gained a completion
   tag. Then set the name and `"verified": true` in `data/missions.json`.
2. **Skull and terminal lists.** The current lists come from a single save. If
   your save shows a `Blam.Skull.*` or `Blam.Terminal.*` tag that is not in
   `docs/SAVE-FORMAT.md`, say so.
3. **Does LASO write its own completion set?** Still open, and the single most
   useful thing anyone can answer. Run `.\Debug-SaveTags.ps1 -Export before.txt`,
   finish one mission on the LASO playlist, then
   `.\Debug-SaveTags.ps1 -Export after.txt -Baseline before.txt` and report which
   tags appeared. "Only Legendary and Remix.Deathless" is just as useful an
   answer as a new set name.
4. **A save from a newer patch.** The completion sets are read from the file
   rather than hardcoded, so if a patch adds one, `.\Debug-SaveTags.ps1` will
   show it under `completion sets`. Report anything beyond the six known ones.
5. **Achievement to requirement mapping.** The end goal is "you still need the
   Bandana skull on The Library" instead of a matrix. That needs all 58
   achievements with the missions and skulls each one depends on.
6. **Unrecognised tags.** If the checker prints an "Unrecognised tags" block after
   a game patch, open an issue with that list.

## Ground rules

- **Read-only on save data.** Nothing in this repo may write to, move or delete
  anything under `wgs\`. A corrupted save is someone's campaign gone.
- **Never commit save files.** `.gitignore` covers `saves/`, `samples/`, `*.sav`
  and `containers.index`. Save blobs contain XUIDs — yours and anyone else's who
  played on that PC.
- **Redact before posting.** XUIDs and gamertags appear in the script's header
  and in the JSON export. Strip them out of issues and PRs.
- **PowerShell 5.1.** That is the version on a stock Windows install. No
  external modules, nothing that needs PowerShell 7.
- **ASCII only in `.ps1` files.** PowerShell 5.1 and UTF-8 without BOM disagree
  about everything else. Markdown files may use whatever they like.
- **Mission data belongs in `data/missions.json`**, not in the script. The table
  inside `halo-1-combat-evolved-achievement-checker.ps1` is only a fallback for when the JSON file is missing;
  if you change one, change both.
- **File-format findings belong in `docs/SAVE-FORMAT.md`**, not in code
  comments.

## Checking a change

There is no automated test suite. The manual check:

```powershell
.\halo-1-combat-evolved-achievement-checker.ps1            # against a save known to be at 100%
```

All six completion columns must read 13/13. Against a partial save, the gaps
must line up with the percentage the game shows — each mission is worth
1/13 = 7.7% of a campaign-wide achievement.

## Reporting a save that will not parse

Open an issue with:

- the output of `.\halo-1-combat-evolved-achievement-checker.ps1 -Raw` with XUID and gamertag removed
- the game version string, which is near the start of the `Progress` blob
  (currently `++Meteorite+Rel-i343-Meteorite-2607-CU4`)
- whether the game was played on this PC, on an Xbox console, or both

Please do not attach the save file itself.
