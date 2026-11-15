# Completed-map cold verification

Load the reviewed local `Verify.luau`, `ApplyCompactSourcePatches.luau`, `RebindCompleted.luau` and, for an idempotent Apply check, `Rollback.luau`/`Apply.luau` as temporary Lua APIs. Loading the source-owner API does not apply patches; `Verify` compares exact saved Sources. Do not substitute old `src/` scripts or recapture the applied world as a baseline.

The current completed journal is selected from the map's saved desired hash:

`ServerStorage.CompactMapV1_WorldJournal_<first 12 desired-hash characters>`

It must have `MigrationId = CompactMap_V1`, `DesiredHash` matching the map, `BaselineSHA256 = 3fb9d9e8…`, and `Status = Completed`. The immutable checkpoint is `ServerStorage.MapCompactionBackups.CompactMap_V1_3fb9d9e8a543`.

Required completed-journal chunk folders:

- `PlanManifest_JSON_Chunks`
- `RuntimeGeometry_JSON_Chunks`
- `MetadataPatch_JSON_Chunks`
- `NativeAssets_JSON_Chunks`: complete actual 31-group native corner proof, with `passed = true` only after all actual group proofs passed.
- `OriginalSources_JSON_Chunks`: JSON of the original `shared.CompactMapSources` capture; all 356 records, including original key, path, class, Source, Enabled and RunContext where recorded.
- `RouteDraft_JSON_Chunks`: the classified selected `.85` route/boundary draft passed to Apply.

Each folder has `MigrationId`, `DesiredHash`, `Bytes` and `ChunkCount` attributes, and contiguous `StringValue` children `Chunk_0001`, `Chunk_0002`, etc. Concatenation must preserve exact bytes; split UTF-8 at valid character boundaries. Apply now persists all seven folders on a future initial transaction. The already completed transaction needs the final three JSON folders and `ProtectedRefs` (1,163), `SourceRefs` (356) and `EnvironmentRefs` (6) added from the still-live original capture before saving/reopening. These three reference folders contain ObjectValues named `Ref_####`, each with `OriginalKey` and the exact captured instance as Value. Future initial Apply transactions persist them.

```luau
local report, desired = rebindAPI.Verify({
    verify = verifyAPI,
    sourceAPI = exactSourceAPI,
    rollbackAPI = rollbackAPI,
})
assert(report.passed, report.staticProof.failureSummary)
-- Separate optional idempotent check: rejects a Failed verification proof.
local retained = applyAPI.Apply(desired)
assert(retained.status == "Retained")
assert(retained.geometryWrites == 0 and retained.sourceWrites == 0)
```

`Rebind` alone returns `desired, report` and proves complete input reconstruction, not the current applied geometry. `Verify` additionally invokes the static verifier. Both require the original DEV place/universe in Edit; neither changes original properties, Sources, tags or parents, creates Instances, performs HTTP or requires gameplay modules. They publish only ephemeral Lua `shared` references after complete rebind preflight.

Managed/external identity uses 1,557 saved `OriginalRefs` ObjectValues. The 1,163 protected assets use saved `ProtectedRefs` ObjectValues, all 356 original Sources use `SourceRefs`, and the six original lighting effects use `EnvironmentRefs`. Every reference has an `OriginalKey` attribute. Full path/class alone cannot identify the historical duplicate Parts inside Sell Sign; dotted Script/ModuleScript names are also retained literally. Native baseline properties, original parents and pivots are decoded from the immutable before manifest, never from current geometry. The complete source JSON is also checked against the checkpoint's 356 original Source strings.

The static proof covers the intended original geometry, native persistent IDs, 54 new/10 retained walls, 31 archived original separators, 64 physical wall masks, seven full-thickness aperture owners, eight region floor unions, effective physics, environment and sources. It does not establish loaded cart turning, gameplay or performance acceptance.
