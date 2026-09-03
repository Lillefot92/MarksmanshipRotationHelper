# Marksmanship Rotation Helper

Marksmanship Rotation Helper is a lightweight, shot-priority PvE advisor for
**Marksmanship Hunters** in World of Warcraft: The Burning Crusade
Anniversary.

Auto Shot fires on its own timer, just like a melee weapon swing - the
addon's job is protecting that timer and firing your instant/cast shots in
the right order around it.

**Multi-Shot -> Arcane Shot -> Steady Shot (if it won't clip your next Auto
Shot) -> Serpent Sting filler. Aimed Shot before the pull.**

The addon only recommends actions. It never casts abilities, changes
equipment, targets enemies, or automates player input.

## Features

- Clean icon-first combat display with a large primary recommendation.
- Auto Shot swing bar and an intentional-wait indicator, so you can see at
  a glance when the addon is deliberately holding back to protect your
  next shot.
- Full ability reason, mana, target mode, and Serpent Sting details
  available by hovering the primary icon.
- Multi-Shot / Arcane Shot / Steady Shot cooldown priority, with real Auto
  Shot clip-avoidance gating Steady Shot.
- Serpent Sting offered only as a safe filler when it isn't already ticking
  on your target - not proactively refreshed like a maintained DoT.
- Cast-time shots (Steady Shot, Aimed Shot) are correctly skipped while
  moving, since they would just fail to cast; the instant Multi-Shot,
  Arcane Shot, and Serpent Sting remain available.
- Automatic single-target and multi-target profiles, plus manual
  overrides (`/mrh mode auto|single|aoe`).
- Action-button highlighting for Blizzard bars, Bartender4, and Dominos.
- Compact cooldown icons for Rapid Fire and trinkets.
- In-game settings under `Escape -> Options -> AddOns`, or `/mrh`.
- Built-in deterministic priority self-test.
- Privacy-safe 60-second diagnostic report for useful bug reports.

## Shot priority

Same order in single-target and AoE - every guide checked agrees
Multi-Shot's per-cast damage beats Steady Shot's regardless of target
count:

1. Multi-Shot.
2. Arcane Shot.
3. Steady Shot, but only if it will finish before your next Auto Shot is
   due - otherwise the addon tells you to wait instead.
4. Serpent Sting, if it isn't already active on your target.

Before combat starts: Aimed Shot. Its cast time is too long to weave in
mid-fight without disrupting your Auto Shot timing.

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
rotation advisor needs to weigh in on every global cooldown.

This rotation was checked against Wowhead, Icy Veins, and Warcraft Tavern's
TBC Hunter guides, and validated with a 23-scenario deterministic
self-check suite, since the author does not currently have a max-level
Marksmanship Hunter. Player feedback from mid-level and level-70 content
will drive the next updates.
