# Marksmanship Rotation Helper

Marksmanship Rotation Helper is a lightweight, shot-priority PvE advisor for
**Marksmanship Hunters** in World of Warcraft: The Burning Crusade
Anniversary.

Auto Shot fires on its own - the addon focuses on the part you actually
control: keeping Serpent Sting up and firing your instant/cast shots in the
right order.

**Serpent Sting upkeep -> Arcane Shot -> Aimed Shot -> Multi-Shot -> Steady
Shot filler**

The addon only recommends actions. It never casts abilities, changes
equipment, targets enemies, or automates player input.

## Features

- Clean icon-first combat display with a large primary recommendation.
- Full ability reason, mana, target mode, and Serpent Sting details
  available by hovering the primary icon.
- Serpent Sting maintenance that reads the real live debuff duration and
  refreshes a few seconds early instead of only after it has already
  lapsed.
- Arcane Shot, Aimed Shot, and Multi-Shot cooldown priority, with Steady
  Shot as the filler in between.
- Cast-time shots (Steady Shot, Aimed Shot) are correctly skipped while
  moving, since they would just fail to cast; the instant Arcane Shot and
  Multi-Shot remain available.
- Automatic single-target and multi-target profiles, plus manual
  overrides (`/mrh mode auto|single|aoe`).
- Action-button highlighting for Blizzard bars, Bartender4, and Dominos.
- Compact cooldown icons for Rapid Fire and trinkets.
- In-game settings under `Escape -> Options -> AddOns`, or `/mrh`.
- Built-in deterministic priority self-test.
- Privacy-safe 60-second diagnostic report for useful bug reports.

## Single-target priority

1. Maintain Serpent Sting if it's missing, wrong, or about to lapse.
2. Arcane Shot.
3. Aimed Shot (skipped while moving - it has a cast time).
4. Multi-Shot.
5. Steady Shot filler (also skipped while moving).

## AoE priority

1. Maintain Serpent Sting.
2. Multi-Shot.
3. Arcane Shot.
4. Aimed Shot.
5. Steady Shot filler.

Automatic enemy counting uses recent combat-log interactions. If it cannot
see an unengaged nearby enemy, force the profile with `/mrh mode aoe`.

## Commands and testing

- `/mrh` — open settings.
- `/mrh sim check` — run the deterministic priority checks.
- `/mrh mode auto|single|aoe` — select target-count behavior.
- `/mrh record` — record up to 60 seconds of anonymous decision data.
- `/mrh report` — open the selected, copyable diagnostic report.

If a recommendation looks wrong, please include the complete `/mrh report`
text in a CurseForge comment. It contains no account, character, realm, or
target names; no chat, GUIDs, or item links.

## Scope

Hunter's Mark and Aspect maintenance are intentionally out of scope - those
are a "set it and forget it, yourself" concern, not something a combat
rotation advisor needs to weigh in on every global cooldown. This addon also
does not attempt to model or avoid auto-shot "clipping" from instant shots -
that interaction is not well-established enough to build a rule around
without being able to test it live.

The rotation is based on TBC Marksmanship Hunter mechanics and has been
validated with a deterministic self-check suite, since the author does not
currently have a max-level Marksmanship Hunter. Player feedback from mid-level
and level-70 content will drive the next updates.
