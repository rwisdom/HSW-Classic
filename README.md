# HSW-Classic

HSW-Classic (Healer Stat Weights — Classic) is a WoW Classic Era addon that automatically calculates stat weights for healers in real-time. It intercepts healing events from the combat log, decomposes each heal into per-stat derivative contributions, and displays live stat priority rankings so you know exactly how your current gear and playstyle value each stat.

## Supported Specs

| Spec | Crit note |
| ---- | --------- |
| Holy Paladin | Illumination mana refund modelled |
| Restoration Shaman | Pure throughput crit |
| Restoration Druid | HoT-crit suppression (HoTs don't crit in 1.12) |
| Holy Priest | Spiritual Guidance + Meditation Spirit dual-path |

## Stats Tracked

- **+Healing** — reference stat (always 1.00)
- **Crit** — spell critical strike
- **Intellect** — mana pool value + crit-from-int (spec-dependent)
- **MP5** — mana per 5 seconds (fight-length dependent)
- **Spirit** — Druid and Holy Priest only (regen path for both; throughput path for Priest via Spiritual Guidance)

Haste, Versatility, Mastery, and Leech do not exist in Classic Era and are not tracked.

## Installation

Copy the `HealerStatWeights` folder into your `{WoW_Directory}/Interface/AddOns/` directory.

Requires **WoW Classic Era** (patch 1.12, Interface 11200). Does not work on retail or WoW Classic (Wrath/Cata).

## Usage

Type `/hsw` in-game to open the options panel. Configure which content types to track (raids, dungeons, PvP), then play normally. Stat weights update live after each heal event.

| Command | Effect |
| ------- | ------ |
| `/hsw` | Open options panel |
| `/hsw show` / `/hsw hide` | Toggle display frame |
| `/hsw lock` / `/hsw unlock` | Lock/unlock frame position |
| `/hsw debug` | Dump current segment stats (testing) |

## Reading the Output

Weights are normalised to +Healing = 1.00. A Crit weight of 0.72 means one point of spell crit provides 72% as much effective healing as one point of +Healing, based on your actual combat data from the current segment.

MP5 and Spirit weights are fight-length dependent — they increase the longer a fight runs, reflecting the compounding value of mana sustain over time.

The Spirit row is only shown for Druid and Holy Priest. Paladin and Shaman have no meaningful Spirit contribution and the row is hidden for those specs.

## Druid-Specific Notes

- **Reflection setting**: The Restoration Druid Spirit weight depends on your Reflection talent rank. Default assumes Reflection 3/3 (15% in-combat regen). If you have the Stormrage T2 3-piece set bonus, enable the 30% setting in the options panel.
- **Innervate**: Self-cast Innervate mana returns are included in the Spirit weight automatically.

## Paladin-Specific Notes

- **Int per 1% Crit**: The Intellect weight includes a crit-from-Int component. The default conversion (53.77 Int per 1% crit) can be adjusted in options if you know your actual value from in-game testing.

## Pawn Export

The display panel includes a Pawn export button. The Pawn string uses `HealingPower`, `SpellCrit`, `Intellect`, `Mp5`, and (for Druid/Priest) `Spirit` identifiers — verify these match your version of Pawn Classic.
