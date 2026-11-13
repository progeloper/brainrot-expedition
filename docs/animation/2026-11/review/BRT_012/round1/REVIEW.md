# Review package: BRT_012 Frigo Camelo (round 1)

13 November 2026. Drafts only: nothing uploaded, nothing live, not committed.

## Rig

- **Archetype: Quadruped with a neck, knees and a signature prop.**
- **13 Motor6D joints** (was 7): Root→Torso (the fridge), Torso→Neck→Head, Torso→four thighs, each thigh→lower leg, Torso→Tail, Torso→FridgeDoor.
- **Neck (new):** the bowed neck and throat have their own joint at the base of the neck, and the head now pivots at the top of the neck. Before, the neck was part of the fridge and the head pivoted in mid-air.
- **Knees (new):** I added these without being asked, because you asked for them on the chimp and the mole and his legs are built with a knobbly knee. Each lower leg carries the lower tube and the boot; the knee box stays on the thigh and hides the bend. Say if you would rather he had straight legs.
- **FridgeDoor (new, signature prop):** the front door on his right flank, with its handle, hinges on its rear edge and swings outward. Its glowing cyan seal stays on the fridge, so an open door shows a lit rectangle inside.
- **Bind pose:** all 148 boxes are exactly where they are in the installed template, with the same colours (scripted comparison, zero difference). Only the `rig` list and 42 `bone` tags changed in `Config/VoxelCreatures/BRT_012.lua`.
- **Face:** eyes, brows, muzzle, lip, ears and chin tuft move as one rigid group on the head.

## Animations (11)

| Sheet | Rows, top to bottom |
|---|---|
| ![1](sheet_1_idles_walk_run_alert.jpg) | IdleDisplay (door open in the middle frames), IdleWild, IdleWild2, Walk, Run, Alert |
| ![2](sheet_2_hit_carried_sleep_celebrate_signature.jpg) | Hit, Carried, Sleep, Celebrate, Signature |
| ![close](closeup_sleep_celebrate_signature.jpg) | Close-up: Sleep, Celebrate, Signature |

The idea: a camel who is also a fridge. Lofty and unbothered, with a long swaying neck; now and then the door swings open and he has to deal with it.

How this set is built: the shared quadruped base supplies the gaits and the simple reactions, as it did for the crocodile. Every one of those clips then gets neck, knee and door motion written for him, and **Sleep and Signature are entirely his own**.

- **Walk and Run:** each knee lifts as its leg swings forward. In Walk the neck pumps forward and back like a camel's; in Run it stretches out low and the door rattles.
- **IdleDisplay:** on show. Once a loop the door swings open and closes again, like a showroom fridge.
- **Sleep:** kneeling, the way camels rest. All four legs fold under the fridge, the neck lies forward and the head hangs low.
- **Celebrate:** the base hop and spin, with the knees tucked and the door flying open in the air.
- **Hit, Alert, Carried:** the door pops or flaps with each.
- **Signature:** the door. It swings wide open on its own; he stops, cranes his neck round to stare at it, shivers at the cold, then bumps it shut with a hop of his back end.

## Review pen

Set `AnimationReviewPen = true` on `ReplicatedStorage`, press Play, and cross the bridge behind the villager demo. He is the fifteenth creature row.

Checked in Play: 15 models, all with the neck, door and knee bones, no errors. 13 of the 15 had a track playing when sampled; the others are one-shot clips waiting to replay. I did not watch each animation play.

## Self-check

| Check | Result |
|---|---|
| Loops seamless | Pass |
| Nothing under the floor | Pass (3 clips needed the floor clamp) |
| Sleep rests on the floor | Pass: lowest point is exactly at floor height, with the fridge 0.8 studs lower than standing |
| Door opens outward | Pass: the handle moves 0.9 studs out from the flank at full swing |
| Face rigid | Pass |
| Clipping | Not checked animation by animation. Watch the open door against the front right leg, the folded legs against each other and the fridge in Sleep, and the neck against the front of the fridge when it reaches forward. |
| Gaps at the knees | Not measured. Sleep folds the knees about 140 degrees, far more than any other clip; look there first. |
| Foot sliding | Not measured |

## Concerns

1. **Sleep folds the legs very tightly.** A 140-degree knee on box legs will show the lower leg crossing the thigh. It reads as kneeling on the sheet, but it is the pose most likely to look wrong close up.
2. **The gaits are the shared base, not rewritten.** Walk is a 0.7 s trot and Run a 0.34 s one, the same timing as the other quadrupeds. A real camel paces (both legs on one side together) and he is tall, so a slower pacing walk would suit him better. I can write that if you want it.
3. **Only one of his four doors opens.** The other three are fixed.
4. **In the Signature he looks over his right shoulder at the door.** The neck turns 22 degrees and the head 42 more. I kept it to that and did not test whether a wider turn would clip the hump.
5. **Rojo is still disconnected.** I put this species' two changed files into Studio by hand and confirmed both are byte-identical to disk.
6. **The installed template is out of date** until approval.
7. **Run is authored for 11 studs/s and Walk for 6.6**, the same figures used for the other Uncommon, BRT_013.
