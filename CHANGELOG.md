# Changelog

## 1.1.0 - 2026-09-03

### Rotation priority corrected against real guides

The 1.0.0 shot priority was written from memory and got the core mechanics
wrong. Checked against Wowhead, Icy Veins, and Warcraft Tavern's TBC
Hunter guides and reworked:

- Added real Auto Shot swing tracking and a clip-avoidance check before
  ever suggesting Steady Shot - missing this was the biggest mistake in
  1.0.0, since avoiding Auto Shot clipping is the single most important
  Hunter DPS mechanic in TBC.
- Corrected the priority order to Multi-Shot -> Arcane Shot -> Steady
  Shot -> Serpent Sting, in both single-target and AoE. 1.0.0 had this
  backwards and ranked Serpent Sting as a maintained top-priority DoT.
- Aimed Shot is now pre-pull only. 1.0.0 offered it as a mid-fight filler,
  which its cast time makes far too disruptive to Auto Shot timing.
- Serpent Sting is now a low-priority safe filler, only suggested while
  it isn't already active, instead of a proactively refreshed DoT.
- Added an Auto Shot swing bar and an intentional-wait indicator to the
  display, matching how Arms Rotation Helper visualizes its own
  swing-timing mechanic.
- Simulator self-check suite rebuilt around the corrected priority: 23
  scenarios covering core priority, clip avoidance, movement, the
  pre-pull Aimed Shot window, and AoE mode.

## 1.0.0 - 2026-09-03

### Initial release

- Shot-priority PvE advisor for Marksmanship Hunters: single-target and
  AoE priority lists built around TBC Marksmanship mechanics (Serpent
  Sting as a live-tracked DoT, Arcane/Aimed/Multi-Shot cooldown priority,
  cast-time shots gated while moving).
- Auto/forced-single-target/forced-AoE target modes.
- In-game icon overlay with action-bar glow and a compact cooldown row
  (Rapid Fire, trinkets).
- Full in-game settings panel (`/mrh`), matching the layout and
  conventions established by Arms Rotation Helper and Retribution
  Rotation Helper.
- Deterministic scenario simulator (`/mrh sim`, `/mrh sim check`)
  doubling as an offline self-check suite, since the author does not
  have a max-level Marksmanship Hunter to test against directly.
- Privacy-safe 60-second live diagnostic recorder (`/mrh record`,
  `/mrh report`).
- Abilities identified primarily by literal English spell name (matched
  live against the player's own spellbook) rather than numeric spell
  ID, so the addon stays correct even if a specific rank ID is wrong.
- Hunter's Mark and Aspect maintenance intentionally left out of scope,
  following the lesson learned from Retribution Rotation Helper's aura/
  blessing removal: buff-upkeep reminders turned out to be more
  distraction than help.
