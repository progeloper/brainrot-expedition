# Review package: the last nine brainrots, one batch (round 2)

14 November 2026. Drafts only: nothing uploaded, nothing live, not committed.

Covers BRT_023, 024, 025 (Jungle), 029 (Arctic), 031 (Volcano), 032 (Glitch) and the teased BRT_033, 034, 035: 99 animations.

## What changed since round 1

Round 1 feedback: "use initiative, and other games in the niche to tweak each of those brainrots to make them game ready, more dopamine overall."

The weak spot in round 1 was the shared clips: Walk, Run, Alert, Hit, Carried, Sleep and Celebrate were the older, calmer base motions. Round 2 replaces them with a new **high-energy base set** (`AnimationAuthoring/Archetypes/BipedHype.lua`). It is written for the look of brainrot collection games, worked from my general knowledge of the genre. I did not study specific games for this pass.

- **Never still.** The idle bops on every beat with a knee dip, sways, turns and looks about, with the tail wagging and arms loose.
- **Every move has a wind-up and a landing.** Alert is a crouch, a jump with arms and tail flung out, and a squash. Celebrate is a crouch, a big spinning jump with arms up and legs tucked, a squash, then a second little hop. Squash is always a joint dip; no part is ever rescaled.
- **Walk bounces.** There is a little hop on every step, the body rocks, the head bobs against it, and the arms swing wide.
- **Run bounds.** Hard lean, knees high, arms pumping, airborne between footfalls with the feet down at full stride.
- **Hit** is a hard recoil to one side with a wobble. **Carried** is a frantic tantrum: kicking, windmilling arms, wriggling.
- **IdleWild2** is an excited look-around: two hops, a big glance left then right, arms up, then a happy wiggle.
- **Sleep** is a doze on its feet: every two seconds the head droops lower and jerks back up with a snore.

How each brainrot uses it:

| Brainrot | Base clips | Their own clips | Limits kept so parts do not sink into the body |
|---|---|---|---|
| BRT_023 Giraffa Celeste | High-energy base | IdleDisplay **stargazing** (now with a bigger bounce); Signature **the space walk** | Half-size head turns (the helmet sits inside the melon) |
| BRT_024 Nooo My Hotspot | High-energy base; the phone is held up to suit each clip: up high when running "for signal", thrown up in fright, raised twice in Celebrate "got signal!" | IdleDisplay **searching for signal**; Signature **the NOOO** | Both arms always turn together so the phone stays in both hands |
| BRT_025 Salamino Penguino | High-energy base, flippers taking the arm moves | IdleDisplay **the grump**; Walk **the waddle**; Run **the flipper sprint**; Signature **the belly slide** | Smaller flipper raises and head turns, stub tail at half |
| BRT_029 Cocofanto Elefanto | **Written for him** in the same style: a bouncing idle, a happy-hop look-around, a bounce trot, a bounding sprint, a startle hop, a recoil, a paddling tantrum, a double spin-jump. Sleep stays the approved base clip | IdleDisplay **holiday sway** (bigger); Signature **the trumpet stomp** | Head turns at 60% (the face sits in the coconut) |
| BRT_031 Odin Din Din Dun | High-energy base, the flex set for each clip (he squeezes his biceps on every bop; flexes on both hops in IdleWild2) | IdleDisplay **the pump** (bigger bounce); Signature **the posing routine** | none |
| BRT_032 La Vaca Saturno Saturnita | High-energy base (no knees or arms, so the planet bounces on straight legs) | IdleDisplay **the strut** (bigger); Signature **the cosmic stomp** | none |
| BRT_033 Dragon Cannelloni | High-energy base with wing beats | IdleDisplay **the hero stance** (bigger bounce and wing breaths); Signature **the inferno roar** | Smaller arm raises, tail lifts, head drops, leg swings and body tilt (the armour is bulky) |
| BRT_034 Orcalero Orcala | Still Tralalero's approved set (BRT_027), but every hop and bounce now goes **half as high again** | Signature **the breach** | Rear legs swing less (their tops sit inside the body) |
| BRT_035 La Secret Combinasion | High-energy base; the base's neck and head motion drives the phone rider | IdleDisplay **showing off the sign** (bigger bounce); Signature **the 9 reveal** | Arms only twist; shorter stride and less body tilt (the hips sit inside the bowl) |

Rigs are unchanged from round 1: BRT_034 gained a head joint and four knees, BRT_024's phone rides on the hand. Every model is exactly as installed (scripted comparison: zero difference).

## Sheets

Six moments of each clip, the camera turning from front to side across the row. Sheet 1 rows: IdleDisplay, IdleWild, IdleWild2, Walk, Run, Alert. Sheet 2 rows: Hit, Carried, Sleep, Celebrate, Signature. Bounces are easier to judge in the review pen than on a still sheet.

| Brainrot | Sheet 1 | Sheet 2 |
|---|---|---|
| BRT_023 | ![](BRT_023_sheet_1.jpg) | ![](BRT_023_sheet_2.jpg) |
| BRT_024 | ![](BRT_024_sheet_1.jpg) | ![](BRT_024_sheet_2.jpg) |
| BRT_025 | ![](BRT_025_sheet_1.jpg) | ![](BRT_025_sheet_2.jpg) |
| BRT_029 | ![](BRT_029_sheet_1.jpg) | ![](BRT_029_sheet_2.jpg) |
| BRT_031 | ![](BRT_031_sheet_1.jpg) | ![](BRT_031_sheet_2.jpg) |
| BRT_032 | ![](BRT_032_sheet_1.jpg) | ![](BRT_032_sheet_2.jpg) |
| BRT_033 | ![](BRT_033_sheet_1.jpg) | ![](BRT_033_sheet_2.jpg) |
| BRT_034 | ![](BRT_034_sheet_1.jpg) | ![](BRT_034_sheet_2.jpg) |
| BRT_035 | ![](BRT_035_sheet_1.jpg) | ![](BRT_035_sheet_2.jpg) |

## Review pen

Set `AnimationReviewPen = true` on `ReplicatedStorage`, press Play, and cross the bridge behind the villager demo; the pen takes about fifteen seconds to fill.

Checked in Play: all nine appear, 15 models each, every one with its full set of joints, no errors. At the moment I counted, 12 to 14 of each 15 had a track playing (the rest were between one-shot clips). I did not watch each animation play.

## Self-check (measured on every clip)

| Check | Result |
|---|---|
| Loops seamless, nothing under the floor | Pass, all 99 clips |
| Ground contact | Every ground clip touches the floor. My first high-energy Run never touched it (airborne the whole cycle); fixed so the feet land at full stride. Jumps leave the floor on purpose: Alert about 0.5, IdleWild2 0.4, Celebrate up to about 1.3, the space walk 2.9, the breach 3.1. |
| Parts sinking into the body | Every pair of body parts compared against how far they already overlap at rest; everything more than 0.12 studs deeper was fixed with the limits in the table above. |
| Still slightly past that line | The toilet's Run (legs 0.13 deeper than at rest), Odin's IdleDisplay (a fist touching the body, 0.12) and Orcalero's IdleWild2 (as on the approved Tralalero) |
| Face rigid | Pass |
| Foot sliding | Not measured |

## Concerns

1. **The high-energy base is shared by seven brainrots.** Each has its own IdleDisplay and Signature and its own limits, but their Walk, Run, Alert, Hit, Carried, Sleep and Celebrate move the same way. Cocofanto has his own versions; Orcalero keeps Tralalero's. Say if any one should get fully custom clips.
2. **La Secret Combinasion moves least.** Its shoulders and hips sit inside the toilet, so its arms only twist and its stride and lean are kept small; the bounce, the phone rider and the sign carry its energy.
3. **Sleep on the bipeds is a standing doze** with a snore nod, not lying down.
4. **Salamino's belly slide** goes 1.2 studs forward and hops back, since his position never moves.
5. **Speeds (my assumption):** Rare Walk 6.6 and Run 11; Epic and above 6 and 10; Odin 10.8 as a Sprinter (Salamino, also a Sprinter, left at 11).
6. **BRT_033, 034 and 035 stay teased.** Their animations are assets only; spawning, release status and the catalogue are unchanged.
7. **Rojo is still disconnected.** Every changed file was put into Studio by hand and confirmed byte-identical to disk.
8. **Uploads are still blocked.** The folder to approve is `assets/animations`.
9. None of the nine has its V4 data and build committed yet; they will be on approval, with the regenerated templates.
