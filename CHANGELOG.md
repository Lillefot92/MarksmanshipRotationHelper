# Changelog

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
