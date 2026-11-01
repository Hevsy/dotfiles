---
name: Liftoscript
description: Liftoscript syntax for Liftosaur programs — exercises, sets/reps, weights, RPE, timers, supersets, warmups, lp/dp/sum progressions, templates and reuse, custom progress/update scripts. Use when writing, reviewing or debugging a Liftoscript program.
---

# Liftoscript cheat sheet

## Official sources

The canonical reference is the Liftosaur MCP server:
`liftosaur_get_liftoscript_reference`, `liftosaur_list_exercises`,
`liftosaur_get_liftoscript_examples`, `liftosaur_get_program_design_guide`,
`liftosaur_get_builtin_program`.

This file is a fast offline cheat sheet. `references/liftoscript.md` is a snapshot of the
official docs and may lag behind the MCP reference — prefer MCP when both are available.

Liftoscript is the text syntax for Liftosaur programs. This sheet covers the common 95%.
For advanced features (set variations, exercise variations, advanced descriptions, tags,
`update:` scripts, `state[tag]`, `sets()`, function reference) read
`references/liftoscript.md` in this skill directory.

## Program structure (Full Mode)

```
# Week 1
## Day 1
Squat / 5x5 / progress: lp(5lb)

## Day 2
Bench Press / 3x8
```

`#` = week heading, `##` = day heading. Exercises are one per line. Blank lines separate
days and descriptions. A single day program can omit headings.

## Exercise line anatomy

`Name, Equipment / sets / other sections / progress: ...`

Sections are separated by `/` and may appear in any order after the name. Unknown or
misspelled section names are parse errors, so keep them sane.

## Sets and reps

```
Bench Press / 3x8            // 3 sets of 8
Bench Press / 3x8-12         // rep range
Bench Press / 1x5, 1x3, 1x1, 5x5   // 8 sets total
```

- `4x5, 1x5+` — `+` after reps = AMRAP (user logs actual reps).
- Weight/RPE/rest can be per set or per range: `1x5 @8, 1x3 @9, 5x5 50%`.
- Set labels (8 chars max) in parens: `4x5 (Main), 1x5+ (AMRAP)`.
- Exercise label = word + colon before the name: `main: Squat / 5x5`. Labels separate
  exercises for progression purposes.

## Weight

| Form | Meaning |
| --- | --- |
| nothing | weight empty during workout, user enters it |
| `80%` | 80% of 1RM |
| `60kg` / `100lb` | absolute weight |
| `@8` | weight inferred from RPE table and 1RM |
| `100lb+` | ask the user what weight they used |
| `?+` | ask for weight, no explicit value |
| `70%+` | ask for weight, default 70% |

If neither weight nor RPE is given, the user must type the weight.

## Rest and active set timers

- `90s` — rest timer only.
- `60s|30s` — set timer 60s, rest timer 30s (the `|` is what makes it a set timer).
- `60s|?` — set timer 60s, keep the global default rest.
- `30s+|60s` — `+` after a set timer counts up past the threshold (manual stop).
- Trailing `auto` — auto-advance to next set when the rest timer ends (circuits/EMOM/Tabata).
  `Power Clean / 5x5 135lb 60s|0s auto`
- In scripts: `timers[n]`, `setTime[n]`, `completedSetTime[n]`.

## Full-line sections

```
Squat / 5x5 / warmup: 1x5 45lb, 1x5 135lb, 1x3 80%   // % of first working set, not 1RM
Squat / 5x5 / warmup: none
Squat / 3x8 / superset: A                            // exercises sharing the letter alternate
Squat / 1x10+, 3x10 / 70% / used: none               // template, not part of the program
Squat / 3x8 / id: tags(1, 100)                       // state-var tags
Squat / 3x8 / progress: none                         // disable progression (deload)
Bench Press / ...Squat / 150lb                       // reuse + override
```

## Descriptions

```
// Shown to the user during the workout (Markdown allowed)
/// Not shown to the user — notes for you
Squat / 5x5 / progress: lp(5lb)
```

Descriptions attach to the exercise below them and are reused in later weeks until
overwritten. An empty `//` stops the reuse. Descriptions above `# Week` / `## Day` lines
describe the week/day. `// ...Squat` reuses another exercise's description.
Multiple descriptions separated by a blank line become descriptions 1..n, switched by
`descriptionIndex`; the current one is marked `// !`.

## Progressive overload

One `progress:` per exercise across the whole program (not per day). Only one day needs it.

```
lp(5lb)                       // +5lb after 1 successful session
lp(5lb, 2)                    // after 2 successful sessions
lp(5lb, 2, 1)                 // ...already 1 success counted
lp(5lb, 2, 1, 10lb, 3)        // +5lb after 2 wins, -10lb after 3 fails
lp(5%)                        // percentage increase
dp(5lb, 8, 12)                // double progression: reps 8→12, then +5lb and reset to 8
sum(30, 5lb)                  // +5lb when total reps across sets > 30
```

Same movement with two progressions needs two labels (`lowrep:`, `highrep:`).
Different progressions for the same labelled exercise in different weeks is an error.

## DRY: templates, reuse, repeats

```
# Week 1
## Day 1
t1 / used: none / 1x6, 3x3 / 80%
t2[1-4] / used: none / 3x10+ / 60% / progress: sum(30, 5lb)

Squat[1,1-4] / ...t1
Romanian Deadlift[2,1-4] / ...t2

# Week 2
## Day 1
t1 / 1x7, 3x4 / 80%
```

- `...Exercise` copies sets/reps/weight/RPE/timers, warmups and progress from an exercise
  in the current week (or `...Exercise[day]`, `...Exercise[week:day]`). Anything you write
  after it overrides what was copied.
- `Name[fromWeek-toWeek]` repeats the exercise on the following weeks.
- `Name[order,fromWeek-toWeek]` sets the exercise order for ambiguous cases.
- Reusing an exercise that progresses moves diverged values into overrides automatically.
- Templates (`used: none`) never progress, so reuse never breaks.

## Split long lines

```
Squat / 1x5 @8 75% 120s, 3x8 @9 60s \
  / warmup: 1x5, 1x3, 1x1 \
  / progress: lp(5lb)
```

## Scripts (advanced — see reference for the full list)

```
Bench Press / 3x8 / progress: custom(attempt: 0) {
  if (completedReps >= reps) {
    state.attempt += 1
    if (state.attempt > 3) {
      weights += 5lb
      state.attempt = 0
    }
  }
}
```

- Block delimiters in the program text: `{~ ... ~}`. Reuse another script with
  `custom() { ...Squat }`.
- Read-only: `weights`/`w`, `originalWeights`, `completedWeights`/`cw`, `reps`/`r`,
  `minReps`/`mr`, `completedReps`/`cr`, `completedRepsLeft`, `RPE`, `completedRPE`,
  `timers`, `rm1`, `bodyweight`, `day`, `week`, `dayInWeek`, `programNumberOfSets`,
  `numberOfSets`/`ns`, `completedNumberOfSets`, `setVariationIndex`,
  `exerciseVariationIndex`, `descriptionIndex`, `amraps`, `logrpes`, `askweights`.
- Writable: `weights`, `reps`, `minReps`, `RPE`, `timers`, `amraps`, `logrpes`,
  `askweights`, `rm1`, `numberOfSets`, `setVariationIndex`, `descriptionIndex`.
- Index syntax `weights[week:day:setvariation:set]`; omitted leading parts mean `*`.
  `weights[2]` is the 2nd set everywhere. `weights[2:3:*:*]` is week 2, day 3, all sets.
- Omitted index in a comparison means all: `completedReps >= reps`.
- `state.name` for persistent state vars, `var.name` for temporaries.
- `update: custom() {~ ... ~}` runs during the workout (before sets at `setIndex == 0`,
  then after each completed set); it cannot touch state or other weeks/days, but can change
  `numberOfSets` and use `sets(from, to, minReps, maxReps, isAmrap, weight, timer, rpe, shouldLogRpe)`.
- Functions: `floor`, `ceil`, `round`, `sum`, `min`, `max`, `increment`, `decrement`,
  `rpeMultiplier(reps, rpe)`, `calculate1RM`, `calculateTrainingMax`, `roundWeight`,
  `zeroOrGte`, `print`.
- Types: number, weight (`5lb`, `2.5kg`), percentage (`80%`), boolean. Operators: `+ - * / %`,
  `> < <= >= == !=`, `&& || !`, ternary `cond ? a : b`.

## Common mistakes

- Duplicating `progress:` on several days, or with different arguments.
- Writing `warmup:` percentages as 1RM percentages (they are of the first working set).
- Using `-` instead of a rep range separator or forgetting the closing `}` / `~}`.
- Reusing `...Exercise` that is defined later in a way the lookup can't resolve
  (check the week/day index).
- Leaving `%` weights on an exercise with no 1RM set for that exercise.
