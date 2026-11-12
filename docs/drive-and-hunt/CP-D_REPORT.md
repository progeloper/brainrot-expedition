# Drive-and-Hunt — CP-D report (12 Nov 2026)

Owner instruction: "build cp-d". Scope: flag on, save, publish to the private DEV place (PlaceId 91958083796436).

## Status

| Step | Result |
|---|---|
| Flag on | **Done.** `FeatureFlags.DriveAndHuntV1Enabled = true` in `src/` and in Studio. |
| Play check with the real flag | **Done.** No preview attribute, test profile. Remotes created, no QA hook, walking out of camp seated the player at `North_04`, switch button read HOP OUT, reticle and aim line present. |
| Save | **Done. Roblox place version 1271**, saved 12 Nov 2026 23:37 UTC with the note "Drive-and-Hunt CP-D: flag on". |
| Publish | **Confirmed by the owner** on 12 Nov 2026 ("It's published"). I did not observe it myself and have no published version number; the last version I saved is 1271. |

## Publish: sent, not confirmed

The Studio save tool never publishes, and the Open Cloud publish endpoint needs a binary place upload that the tools here cannot send. I therefore pressed **File → Publish** in Studio twice through the app's menu bar.

I cannot show that either press took effect:
- no dialog or toast was visible, but Studio was on another desktop Space (or the screen was locked), so the window captures were stale;
- the place's "last updated" time stayed at the save time (23:37:24 UTC), though Studio may cache that value;
- there is no Open Cloud endpoint for reading the published version.

**Update:** the owner confirmed the place is published. The section below records why I could not confirm it from the tools.

To confirm or finish:
1. In Studio, choose File → Publish (Option+P). A "published" toast should appear.
2. Or open Creator Hub → Brainrot Expedition [DEV] → Version History and check that version 1271 (or later) is marked as published.

## What version 1271 contains

- All Drive-and-Hunt work from CP-A to the post-CP-C changes, with the flag on.
- Whatever else was unsaved in Studio at the time, including your own work since version 1250.
- No test attributes: `DriveAndHuntV1Preview`, the QA hooks and the test profile namespace were removed before the save. Your own preview attributes (`CampReworkV1Preview`, `TrainingV1Preview`, `RebirthUiV2Preview`, `WeaponTiersV2Preview`, `VoxelCreaturesV4Preview`) were left as they were.

## Known gaps going live

- No test on a phone, with touch input, or with a physical controller.
- Frame time never measured.
- Six moved Jungle and Volcano launch lanes not launch-tested.
- HOP OUT → shoot → LOAD & GO → chase → "ESCAPED!" not run end to end.
- Camera ease, hop animation and turret art not built. Hints are session-only.
- Specs: 207 of 211; the four failures predate this work.

## Rollback

Set `DriveAndHuntV1Enabled = false` in `src/shared/Config/FeatureFlags.lua` and save/publish; every part of the feature is behind that flag. Earlier state: Roblox place version 1250 and `.checkpoints/drive_and_hunt_cpA_20261112/`.

## Not done

Nothing is committed to git. The work is uncommitted on `feature/camp-rework` alongside your own changes.
