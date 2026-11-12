# Camp Rework (12 Nov 2026) — note for the offline GLB road pipeline

The owner-approved Camp Rework removed the inner camp road network from the live place:

- `Workspace.MapBlockout.Paths.StyledSurfaces.Path_Camp_1_1` (inner ring + cross + base driveways, one
  MeshPart) was deleted (backup: `ServerStorage._Backups_CampRework_20261112`).
- Its two outside-the-ring corner-road pieces were rebuilt as flat wedges in
  `Path_Camp_1_1_CornerRoads` (south-west corner road up to `Path_Camp_1_2` at z = 167; north-west stub
  up to `Path_Camp_1_0` at z = -211). All other `Path_Camp_*` surfaces are unchanged.
- The camp floor inside the ring of bases is now continuous `Floor_R3_C3` grass.

The GLB pipeline and its manifests in this folder were **not** changed: they are hash-pinned
(`CompactNativePackageHashes.json`). Re-importing this pipeline's camp road group would bring the inner
ring back; drop group `Path_Camp_1_1` (keep the corner pieces) before any future re-import.
