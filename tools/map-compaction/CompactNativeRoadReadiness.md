The selected `.85` source geometry is ready for native import. The main import file is `generated/selected-b085/CompactAssetsStudioImport.glb` (SHA256 `bdd81be39782c1649694deecaf3264e5e82db25d9bb7ed7f783f05c1ab6fbd4e`). It contains 27 roads (1,047 triangles), the three fitted showhouse groups (1,600 triangles), and one closed unit wall cube (12 triangles): 31 groups, 2,659 triangles and 7,977 corners in total. These are source triangle counts; actual native corner readback is still required. No original map-art assets, Studio state or original world instances were changed by these tools.

The canonical source file is `CompactAssetsCanonical.glb`, SHA256 `078a93ed83234709bec5799997d7ee41a8dd28cb39bc5fdd8ef18992d3353005`. The import variant applies the previously measured native Y180 inverse to positions, normals and node translations, keeping indices and UVs unchanged. It embeds no images. Each shell/cube triangle retains its own authored hard normal; roads use flat +Y normals. `CompactAssetsBinaryVerification.json` independently parses both saved GLBs and compares every indexed float32 position/normal/UV/pivot tuple against the source values. The shell ground root remains zero; its group nodes sit at their own bounding centres. Owner placement uses the final common local centre and raised foundation floor, separately from mesh centring.

Import through the supported Studio Import3D pipeline with Upload to Roblox enabled, Import Only as Model enabled, Scene Origin pivot, and Insert Scene Position disabled. These settings and compensation reproduce the earlier proven road import; actual native geometry checks must catch a changed importer convention. This creates model-art assets and does not publish the game. Move the imported main model into ServerStorage and name it `CompactMap_ImportedAssets`. Preserve its child roots `CompactMapRoads`, `CompactShowhouseShell_A`, and `CompactWallCube`.

The native scripts are functions returned by their source. Root controls their execution in DEV Edit:

```luau
local importRoot = game.ServerStorage.CompactMap_ImportedAssets
local VerifyAll = loadstring(fullVerifierSource)()
local fullProof = VerifyAll(importRoot)
assert(fullProof.status == "Passed" and fullProof.completeBatch)
assert(fullProof.checkedGroups == 31 and fullProof.checkedTriangleCorners == 7977)

local roadRoot = importRoot.CompactMapRoads
local VerifyRoads = loadstring(roadVerifierSource)()
local roadProof = VerifyRoads(roadRoot)
assert(roadProof.status == "Passed" and roadProof.completeBatch)
assert(roadProof.checkedGroups == 27 and roadProof.checkedTriangleCorners == 3141)

local PrepareRoads = loadstring(roadPreparerSource)()
local prepared = PrepareRoads(roadRoot, roadProof)
-- A rerun must retain all27 and change0.
```

The sources are `CompactVerifyNativeAssets.luau`, `CompactVerifyNativeRoadGeometry.luau`, and `CompactPrepareImportedRoads.luau` beside the GLB. Individual chunks are under `qa/` (all-object checks) and `road-qa/` (strict +Y road checks); pass `{GroupId=exactName}` for partial diagnostics, which are not complete-batch evidence. The full checker uses the previous bounded native normal quantization policy (vector error≤.002, angle≤.12°, length error≤.001, within-face spread≤1e−6); the road checker also retains the previously proven strict +Y error≤1e−5. Position tolerance remains .01stud and UV tolerance1e−5. Both require exact face counts, every oriented corner, no unreferenced vertices, real MeshIds, native identity rotations and exact local bounds. They destroy detached EditableMeshes on every success/failure. Imported bounding Y can be the actual .001 planar clamp or .05; preparation sets Size.Y=.05 while the rendered road remains flat at authored topY .07999995164573193. Asset QA records CFrames but does not substitute for installed world-frame/material checks.

Preparation accepts either that nested road root or an isolated `ServerStorage.CompactMap_ImportedRoads`. It requires the full actual proof and exact combined import hash, validates the saved Glacier/Bingus material and all27 source groups before cloning, and writes only its owned `ServerStorage.CompactMapRoadTemplates`. It leaves the original `MapArtRoadTemplates` and imports untouched. Exact reruns retain the same templates; changing candidate geometry requires the explicit prior owned geometry hash. Commit and rollback are protected. Prepared roads have no SurfaceAppearance/TextureID, use regional road RGB and the saved `Bingus_Saved_Studs_13719188279` at .25, and remain anchored/noncolliding/nonquery/nontouch/no shadow.

For identity-preserving application, root may use the supported [`MeshPart:ApplyMesh`](https://create.roblox.com/docs/reference/engine/classes/MeshPart#ApplyMesh) API with each verified template. Capture a rollback clone and exact original properties/attributes first; apply mesh, then set the exact target Size/CFrame/material/flags/attributes and verify actual MeshId. Rollback applies the original clone and restores original properties/attributes. This belongs inside the parent whole-map transaction and does not replace its source/placement guards.

The road union has one component and covers 384,021.4695977783 square studs. All85 source routes/IDs/control-point mappings and current constant widths,26 contact caps, six24-wide gate aprons, fixed44junction/64pad semantics and all27 original group names remain bound to the frozen source. Group splitting uses transformed original chunk boundaries and true region floor clipping; it does not warp the old27 mesh unions. Maximum float32 boundary error is .0000096254stud. Full centred20×36 gate footprints have zero source floor/road exterior area and zero new-wall intersection for all six gates. This is source planar support, not native driving/permission proof.

`CompactSeparatorMigration.json` lists the exact ten retained outer original instance CF/Size/flags and31 shared-only originals to archive before enabling54 new shared-wall colliders. There are18 true union seams, seven opening owners and five existing closed alternate crossings. `CompactArtWallIntersections.json` accounts for343 captured envelopes:14 potential scenery wall intersections,13 at retained outer barriers and one new Volcano contact. `CompactVolcanoWallSolidContact.json` clips the actual IceCluster source mesh (captured native MeshId98115189755017) against that wall: .2625stud lateral intrusion, contact Y−.1225..4.545, so it is not wholly buried. Root owns staged visual acceptance or a permitted correction. Full cart turns, all final site geometry, runtime cache initialization, native world readback and performance remain separate acceptance work.

Nine actual Python tests exercise both coordinate variants, damaged position/UV/normal/header rejection, inverse axes/translation, input preservation and the cube's closed opposite-edge topology/unit volume. Selene reports zero errors/warnings/parse errors across the three generated full native helpers. Source exporter tests and native-readback status are distinct in every report.

## Camp Rework note (12 Nov 2026)
`Path_Camp_1_1` (inner camp ring + cross) was removed from the live place by the owner-approved Camp
Rework; its outside-the-ring corner-road pieces live on as `Path_Camp_1_1_CornerRoads`. The offline GLB
pipeline is unchanged — see `generated/selected-b085/CAMP_REWORK_20261112_NOTES.md` before re-importing.
