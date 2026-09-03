# Marksmanship Rotation Helper

A shot-priority PvE rotation advisor for Marksmanship Hunters, built as a
companion to Arms Rotation Helper and Retribution Rotation Helper for TBC
Anniversary.

Like its Warrior and Paladin counterparts, this addon is strictly an
**advisor**: it never casts a spell or presses a protected action for you.
It shows an icon, an optional action-bar glow, and a settings panel.

## Commands

- `/mrh` or `/mmhelper` - open the settings panel
- `/mrh mode auto|single|aoe` - target-count behavior
- `/mrh lock` / `/mrh unlock` - lock or drag the display
- `/mrh sim [scenario]`, `/mrh sim next|stop|check` - run the deterministic
  self-check scenarios described below
- `/mrh swing` / `/mrh wait` - toggle the Auto Shot swing bar and the
  intentional-wait indicator
- `/mrh record` / `/mrh record stop` - capture up to 60 seconds of live
  recommendations for review
- `/mrh report` - open the copyable report window
- `/mrh record clear` - erase the in-memory report
- `/mrh debug` - live diagnostic panel
- `/mrh reset` - reset display position/scale

## Rotation design

This priority was checked against Wowhead, Icy Veins, and Warcraft Tavern's
TBC Hunter guides before being written, since the author has no max-level
Hunter to test it on directly.

- **Auto Shot fires on its own timer, just like a melee weapon swing.**
  Steady Shot has a real cast time, so casting it carelessly delays
  ("clips") the next Auto Shot and costs real damage - this is described
  as the single most important Hunter DPS skill in TBC. This addon tracks
  your Auto Shot timer and will only ever suggest Steady Shot when it can
  finish before the next shot is due; otherwise it tells you to wait.
- **Multi-Shot and Arcane Shot outrank Steady Shot** whenever they're off
  cooldown, in both single-target and AoE alike - every guide checked
  agrees Multi-Shot's per-cast damage beats Steady Shot's regardless of
  target count.
- **Aimed Shot is a pre-pull tool, not a filler.** Its cast time is too
  long to weave in without badly disrupting the Auto Shot timing above, so
  this addon only ever suggests it before combat starts.
- **Serpent Sting is a safe instant, not a debuff to maintain.** It's only
  suggested when it isn't already ticking on your target - not proactively
  refreshed early like a maintained DoT.
- **Steady Shot and Aimed Shot both require standing still.** Arcane Shot,
  Multi-Shot, and Serpent Sting are instant and usable while moving. This
  addon skips the two cast-time shots entirely while you're moving, rather
  than recommending something that would just fail to cast.

Shot priority (same order in single-target and AoE): Multi-Shot -> Arcane
Shot -> Steady Shot (if it won't clip the next Auto Shot) -> Serpent Sting
(if it's not already active). Before the pull: Aimed Shot.

**Hunter's Mark and Aspect of the Hawk are intentionally out of scope** -
same reasoning as dropping Aura/Blessing maintenance from Retribution
Rotation Helper: those are "set it and forget it, yourself" concerns, not
something a combat rotation advisor needs to weigh in on every global
cooldown, and every buff-upkeep feature added to these addons so far has
turned out to be more distraction than help.

## Why abilities are matched by name, not ID

Numeric spell IDs drift between ranks and can be easy to get wrong from
memory. Every ability in `Core.lua` is identified primarily by its
**literal English spell name**, matched live against your own
spellbook - the numeric `id` field is only a best-effort fallback used
for a moment before the spellbook has been scanned once. This means
the addon stays correct even if a specific rank id is off, as long as
the name is right, and it automatically tracks whatever rank you've
actually trained.

## Live diagnostic recorder

`/mrh record` captures up to 60 seconds of what the addon actually
recommended during real combat: which ability, why, your mana, target
HP/TTD, Serpent Sting time remaining, and target-mode state, sampled
whenever something changes (plus your actual ability casts, matched
from the combat log). `/mrh report` opens a selectable text window -
Ctrl+C to copy it.

This is the main way to get real playtest data back to the author
without needing a max-level character on the other end: fight for a
bit, open the report, and paste it along with any pulls that felt
wrong. The report is privacy-safe by construction - it never reads or
stores player, realm, account, or target names, chat text, GUIDs, or
item links, only the addon's own internal ability keys and numbers.

## How this was verified without a level-70 Hunter

The author does not have a max-level Marksmanship Hunter to test this
against, so `Simulator.lua` doubles as an offline self-check: it feeds
the real `Rotation.lua` decision logic a set of deterministic combat
snapshots (Serpent Sting state, cooldowns, target health, enemy counts,
movement) and asserts the expected ability comes out. Run `/mrh sim check`
in game at any time to re-verify all scenarios pass, or watch them play
out live with `/mrh sim`.

Before shipping, this suite was also run **outside the game** against the
exact `Rotation.lua`/`Simulator.lua` files in this folder, using a
standalone Lua interpreter with the game API stubbed out - the same
technique `/mrh sim check` uses in-game, and the same technique that
caught real bugs before the Warrior, Paladin, and an earlier draft of this
Hunter addon were ever loaded into WoW. All 23 scenarios pass, covering
the core shot priority, Auto Shot clip avoidance, movement, the pre-pull
Aimed Shot window, and AoE mode.

This is strong evidence the *priority logic* is internally consistent and
matches the intended design - it cannot verify spell IDs, exact mana
costs, or anything that only the live game API knows. Please run
`/mrh debug` in your first few pulls and sanity-check the recommended
abilities against what you'd expect.
