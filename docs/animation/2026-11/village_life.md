# Village life and guard playback (Part D, guards) — 14 Nov 2026

Status: **approved by the owner on 14 Nov 2026 (round 1), verified in Studio Play with the previews on.** The flags
`VillagerAnimationEnabled` and `VillagerLifeEnabled` are still `false`; nothing changes in game until
they are turned on. Studio preview without touching the flags: set `ReplicatedStorage`
attributes `VillagerAnimationPreview` and `VillagerLifePreview` to `true` before Play.

## What was built

| Part | Where | What it does |
|---|---|---|
| Village life (C.6) | `Server/Services/VillageLife.lua`, `Config/VillagerLife.lua`, `Config/VillagerLifePois.lua` | While Idle: walk to a point of interest, do its activity 6–15 s (Plodders/Shouters x1.4, Sprinters x0.7), rest 2–4 s, move on. Wave at a player within 15 studs who hasn't hit a brainrot for 20 s (once a minute per player). Chat: two idle guards within 6 studs, 30% chance, one pair per region. A guard waking from sleep resumes mid-activity at a seeded point. Any "?" cancels it the same tick (`VillageLife.Leave` from `setState`). |
| Guard service hooks | `Server/Services/VillagerGuardService.lua` | Calls VillageLife only for Idle guards with points; records each player's last hit; `Motion` carries the activity. Noticing, chasing, speeds and every VillagerGuards value are untouched. |
| Guard playback (D.2) | `Client/Controllers/VillagerAnimationPlayer.lua`, `VillagerPresentationController.lua` | Guards with an approved skin are built on the one body (`VillagerBodyBuilder`) and play the 24 uploaded animations. One-shots are timed from `MotionAt`; loops start at a seeded offset; walk/run speed follows measured ground speed (0.6–1.6x); Reach overlays the run within 8 studs of the chased cart; a Core-priority Idle underlay fills the gap between a one-shot and the next state. Bubbles and name tags ride the Head bone; the Glitch flicker is kept. Anything unapproved keeps the old template. |
| LOD (D.3, guards) | `VillagerAnimationPlayer.RefreshLod`, every 0.25 s inside the existing RenderStepped | A guard chasing you always animates; idle guards animate on screen within 120 studs; cap 12 (6 at graphics quality <= 3, which also turns Chat and Wave into Idle). Culled guards hold their pose. No new per-frame connections. |

The Suspicious look-around (C.5) is carried by the `Curious` clip's head scan; the server does
not pause, so the approach time is exactly as before.

## Verified in Play (DEV, test profile `anim20261113`, previews on)

| Check | Result |
|---|---|
| Routine | Nonna Pina: Walk → Knead 8.5 s → rest 2.5 s → Walk → Lookout. Pinguino Pattino: Sweep → rest → Walk → Skate in a 1.6-stud circle. |
| Wave | Taglialegna Tito waved for 1 s at a player who had not hunted, then went back to sweeping. |
| Chase, server | hit → `Suspicious/Curious`; load → `WindUp/Shout`, `Chase/Run` 0.78 s later; tag → `GiveUp/Tag` → `Tantrum` → `Return/Walk` → back to the routine with no idle blip. Same timings as flags-off. |
| Chase, client (Plodder) | `Curious` → `Shout` → `RunTrot` (+`Reach` in the last stretch) → `Tag` → `TantrumStomp` → `WalkGrumble` → `Walk` → `Sweep`. |
| Shout timing (R12) | Client `Shout.TimePosition` 0.094 s when 0.091 s had passed since the server's wind-up (error 0.003 s; target ±0.05 s). |
| Body | Every streamed guard used the body with its approved skin; Pina's walk cycle ran at 0.96x to match 2.9 studs/s. |
| LOD | Pina's tracks stopped while she was off screen and resumed when the player came back. |
| Specs | `run-villager-tests.sh`: 42 of 42 pass (33 existing + 9 new `VillageLife.spec`). |

## Points of interest (R15)

Generated in Studio and validated against the map: inside the guard's region and outside Camp;
at least 4 studs from every road triangle (read from the `MapBlockout.Paths` meshes, whose
bounding boxes and collision hulls cover far more than the roads), 6 from gates and aperture
closures, 8 from base patches and burrows; flat; within 3 studs of the home height; unobstructed;
reachable in a straight line from home. Cart spawns sit inside bases and Camp, which are excluded.
The full list with coordinates is `src/shared/Config/VillagerLifePois.lua`.

| Region | Guards and points | Radius raised past idleRadius |
|---|---|---|
| Forest | Tito (Lookout, Chop, Sweep), Pina (Lookout, Knead, Sweep), Gufo (Lookout only), Franco (Lookout, Sweep, Chop), Castagna (Lookout, Knead), Pepe (Lookout, Chop) | none |
| Beach | Bruno (Lookout, Sweep), Sabbia (Lookout, Sweep), Granchio (Lookout, Fiddle), Sara (Lookout, Sweep, Skate), Conchiglia (Lookout, Fish) | none |
| Swamp | Rana (Lookout, Sweep), Pozzo (Lookout, Fish), Rocco (Lookout, Sweep), Palude (Lookout, Fish); **Lumaca has none** | Palude to 12 |
| Jungle | Scimmia (Lookout, Sweep, Chop), Totò (Lookout, Stir), Pazzo (Lookout + Fiddle on the same spot), Sofia (Lookout, Chop, Sweep), Tina (Lookout, Knead) | none |
| Arctic | Pattino (Lookout, Skate, Sweep), Pia (Lookout, Sweep), Brodo (Lookout, Stir), Olga (Lookout, Skate), Foca (Lookout, Fish) | Brodo to 12 |
| Volcano | Lava (Lookout, Sweep, Chop), Magma (Lookout, Stir), Campana (Lookout, Fiddle), Mimmo (Lookout, Chop), Brace (Lookout, Stir) | none |
| Glitch Zone | Pino (Lookout, Sweep, Fiddle), 404 (Lookout, Fiddle), Bip Bop (Lookout, Fiddle), Pixel Pina (Lookout, Sweep), 500 (Lookout, Fiddle) | none |

Activities were chosen to fit each guard's name and job (woodcutter chops, fishermen fish, Orso
Brodo stirs, the Glitch guards fiddle with devices) and keep every skin's existing `Sweep`.

## Findings for the owner

1. **Chat cannot happen with today's homes.** The nearest two guards in a region live 47 studs
   apart (Forest) and most are 110–350 apart, while points stay within 12 studs of home and chat
   needs 6. The chat code is in and tested; it starts working only if some homes are moved closer
   or guards are allowed to visit a shared spot. Homes are untouchable under the brief, so this
   is your call.
2. **Lumaca Lampione has no point of interest.** His home sits inside a road band; nothing within
   12 studs is 4 studs clear of the road. He keeps the plain idle wander (today's behaviour).
3. **9 guard homes are within 4 studs of a road**: Tito, Gufo, Bruno, Lumaca, Palude, Pazzo,
   Brodo, Mimmo and Errore 404. Their points avoid the road; the homes themselves were left alone.
4. Guards in regions the test profile hasn't unlocked are hidden by the existing
   `RegionVisibilityController`, so only Forest guards could be captured; Arctic was verified by
   attribute logs.

## Not done yet

- Brainrot playback (D.1) and brainrot LOD.
- R13 (fairness V1–V11 with the flags on), R16 (clipping), R18 (frame cost), R20 (bandwidth) for
  the guard side.
