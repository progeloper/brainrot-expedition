# Compact route and region-boundary planner

These pure numerical Luau modules consume the immutable complete capture. They do not access Studio, Instances, Services, profiles or gameplay state. This package is a **candidate draft**, not a selected or applied layout. Root PlanManifest owns selection; all six measured base interior candidates currently fail.

Files and contracts:

- `CompactTransform.luau`: `Candidate(b, outer)`, `MapAxis`, `InverseAxis`, `Point`, `InversePoint`, `RigidFrame`, `Rectangle`, `Floor`, `SubdivideSegment`, `Polyline`, `Polygon`. XYZ is an array of three numbers; CFrame is Roblox's 12 component order. Floor rectangles retain Y/thickness and derive X/Z dimensions from transformed edges. Rigid frames retain rotations. Source knots are 136/313/420/432; the final 12-stud band is full size. Every segment is subdivided at all crossed X/Z knot planes before transformation.
- `CompactBoundary.luau`: `Extract(rectangles)`, `MapRuns`, `PrismInterval`, `Subtract`, `Junctions`, `Chunk`, `ClassifyExisting`. A rectangle has `{id, regionId, x0, x1, z0, z1}`. A run has `{id, axis, fixed, first, last, regionPair}`; X means X-directed and Z means Z-directed. Full six-stud strip clipping is used for every approved convex protected polygon against every incident run. Global perpendicular junctions use the lowest run ID once; higher runs abut its three-stud extension, which is rejected if it intersects an aperture. Chunking starts at the lexicographically smaller endpoint. Exact topology is preserved; verification/classification tolerance is .01, and small intended gaps are not rounded away.
- `CompactRoute.luau`: `Build(routes, candidate, Transform, caps)`, `GateAprons(gates, routePlan, gateRouteOwners, candidate, Transform)`, `Crossings(sourceRoutes, sourceRuns, targetRuns, aprons, legacyRows, candidate, Transform)`, `ConnectedComponents(primitives)`. Route IDs, original segment indices and complete controls survive. Widths remain physical 28/36/24/20/44/64 studs as specified. Old diagonal raster slice depth is not interpreted as width. Every authored diagonal station is retained; the constant-width corridor follows those stations, including band subdivisions. The existing 26 contacts are reconstructed without adding logical edges. Paid gate-local return/prompt offsets stay 24/10 studs via rigid translation. Gate throats remain 24 wide for 32 studs each side and taper over 16; the surface union also retains the independently transformed route offset.
- `CompactCaptureInput.py`: flattens the fresh complete BeforeManifest bindings and verified complete original route source. All 27 native road mesh IDs/attrs/frames/sizes are included in `actualRoadBindingsSHA256`.
- `CompactBuildPlan.luau`: Lune CLI calling the actual pure modules. `CompactRouteTests.luau` is a native-compatible test factory accepting the three modules and input table; `CompactRunTests.luau` runs it locally. Tests include independent literal Appendix endpoints/areas, 61,104 interior samples, independent SAT aperture/duplicate-collider tests, 0.5-stud boundary-coverage probes, existing closure evidence and input preservation.
- `CompactExportDraft.py`: labels and exports the actual numerical output as `docs/map-compaction/RouteBoundaryDraft.json`, `CrossingManifest.json`, `WallManifest.json`. It records native base-fit blocking evidence; it never makes a fit selection.

Reproduce from the actual repository with official Lune 0.10.5 available:

```sh
cd tools/map-compaction
python3 CompactCaptureInput.py
lune run CompactBuildPlan.luau
lune run CompactRunTests.luau
python3 CompactExportDraft.py
```

Local official runtime used for this capture is `/private/tmp/map-compaction-lune/lune`. The binary is a temporary tool dependency, not a committed project artifact. Selene uses the actual repository config. No Studio test is claimed by the pure test report.

The b=.75/outer=.75 numerical draft has 1408×1168 floor bounds and 448×448 Camp; 18 shared runs; 12 route crossings comprising six paid openings, one 40-stud free Camp/Forest exit and five already-closed alternate crossings. It yields 54 new wall segments at≤128 studs, 10 captured outer containment portions, and 465 route primitives in one numerical surface component. One original separator spans both a shared and an outer portion, so 41 physical rows classify into 32 shared plus 10 outer portions. Closed alternate crossings keep their existing restriction rather than creating new openings.

Actual Volcano G uses Z=-462, not the historical rounded appendix -466: its draft is (205,.05,-256.3551401869159), while its route crossing remainsZ=-248.13084112149534. Corner relief is recorded under Gate_Volcano for R01/R03/R09/R12. Numerical full-thickness clearance does not prove driving, neighboring-region permissions or the gate-jamb closure.

All visible new walls use the user-directed saved Glacier/Bingus studs at .25 with genuine captured asset 13719188279. This supersedes the reference's no-stud grayscale atlas. A shared closed-cuboid mesh ID is **unbound**; no existing road mesh is substituted and no asset ID is invented. 54 cuboids imply 648 source triangles; actual native wall render triangles remain unmeasured. Existing outer containment retains its old four-stud thickness/inward offset/Y/height; only inter-region walls use the new six-stud foundation contract.

The package does not apply an exception to the failed base interior fit. Cart/service/spawn/landmark fits, source updates, final route union/native mesh readback, old-wall rebinding/removal, physical passage/access tests, fresh cache sessions, matched performance, idempotence and rollback remain parent-owned implementation work after candidate acceptance. Every output has selectedCandidate=null and applyEligible=false. No current map or existing source was changed by this package.
