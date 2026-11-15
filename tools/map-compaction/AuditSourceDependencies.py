#!/usr/bin/env python3
"""Read-only audit of the frozen Edit source export; emits documentation only."""
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/map-compaction'
PATTERNS = {
    'map_or_semantic_coordinate': r'MapBlockout|Phase5DLayoutPivot|InstalledFootprints|RegionBoundary|SpawnAreaId|SafeCartExterior|SafeCharacterExterior|CartSpawn|PlayerSpawn|BrainrotPlacement|HuntingClearings|Grid[ZX]Edges',
    'spatial_query': r'RaycastParams\.new|OverlapParams\.new|FilterDescendantsInstances|RespectCanCollide|CollisionGroup\s*=|Workspace:(?:Raycast|Blockcast|Spherecast|GetPartBoundsInBox)|workspace:(?:Raycast|Blockcast|Spherecast|GetPartBoundsInBox)',
    'geometry_cache': r'currentIndex|columns\s*=|safeExteriors|spawnRecords|Phase5DLayoutPivot|envelopesByModelRef|mapArtEnvelopesByModelRef|baseRootCFrame|placementById',
}
READERS = {
    'Regions': 'Unchanged logical declarations; rebuild floor index from canonical geometry.',
    'RegionSpawnCatalog': 'Rebuild currentIndex after geometry; exact floors, areas, art masks and existing collision queries.',
    'RegionGateDescriptors': 'Reconstruct copied floor columns/gate safe frames in fresh runtime.',
    'WorldProgressionRuntime': 'Restart complete session; preserve logic and derive descriptors from final owners.',
    'RegionAccessService': 'Unchanged rules; consumes new descriptor instance.',
    'RegionBoundaryGuard': 'Unchanged rules; consumes new descriptor instance.',
    'PlayerBaseSystem': 'Retain base/marker identities; fresh registration with migrated references.',
    'BaseLayoutConfig': 'No change under strict plan; compact-only owner table proposal requires separate authorization if fit fails.',
    'BaseIncomePlaqueSystem': 'Cached Phase5DLayoutPivot and platform owner must share canonical target; no economy changes.',
    'BaseStorageSystem': 'Fresh slot registration/display refresh; marker world frame is authoritative.',
    'BaseStorage': 'Stable logical slots/profile; no cash/individual migration.',
    'BaseSignSystem': 'Retain sign owner/template; moved base owner supplies transform.',
    'MapArtStaticMaterialPolicy': 'Unchanged saved-stud/equivalent-physics policy.',
    'CartService': 'Retain current owner CartSpawn reference; fresh runtime; no actor scaling.',
    'CartSpawnRegistry': 'Rebuild cached spawn Part/CFrame records in new session.',
    'CartResetService': 'Unchanged reset mechanics; refreshed spawn bindings.',
    'CartResetExecutor': 'Unchanged reset/support mechanics; normal collision queries encounter walls.',
    'PlayerSpawnSystem': 'Retain assigned SpawnLocation reference; refresh owner state.',
    'PlayerWorldLifecycle': 'Unchanged lifecycle/profile mechanics.',
    'BaseReturnSystem': 'Unchanged MANUAL_PLACEMENT_REQUIRED behavior.',
    'BrainrotSalePointSystem': 'Retain six service owner/anchor identity and menu behavior.',
    'BrainrotSaleSystem': 'Unchanged sale/economy rules; refreshed service reference.',
    'CartUpgradePointSystem': 'Retain service/anchor identity and current range/price rules.',
    'DevelopmentBrainrotSpawner': 'Rebuild index; retain target/quota and current ground/overlap/drop queries.',
    'DevelopmentBrainrotRoaming': 'New world obstacles enter existing ray/Blockcast checks; verify aperture navigation.',
    'NaturalTerritory': 'Unchanged semantic region IDs and bounded recovery/return steering; runtime memory starts fresh.',
    'SpawnSelection': 'Unchanged eligibility/species/rarity selection.',
    'BrainrotCaptureSystem': 'Unchanged existing authoritative camera/muzzle/depth LOS; walls queryable.',
    'BrainrotInteractionSystem': 'Unchanged manual platform interaction/current LOS and ownership/range.',
    'ThirdPersonAimController': 'Unchanged target identity/current LOS; queryable opaque walls.',
    'CartCameraOcclusion': 'Unchanged Carts-group collision-respecting Spherecast; verify wall pair.',
    'CartTerrainSampler': 'Unchanged collision-respecting ground queries; preserve floor physics.',
    'CartCargoService': 'Unchanged source visual scale/cargo and release checks; used as measured fit input.',
    'BrainrotVisualScale': 'Unchanged canonical scale and visible envelope.',
    'BrainrotDisplayMetadata': 'Unchanged canonical metadata.',
    'CollisionGroups': 'Unchanged existing group declarations.',
    'CollisionService': 'Preserve runtime six-group registration and existing pair settings.',
    'Bootstrap': 'No map generator; verify fresh startup/cache order and existing DEV restrictions.',
    'PlayerProfileSchema': 'No world-coordinate restoration fields; unchanged versions and logical slots.',
    'PlayerProfileStore': 'Unchanged storage/version/migrations; no writes for map compaction.',
    'PlayerDataService': 'Unchanged profile/session resolver.',
    'PlatformIncomeProfileStore': 'Unchanged logical platform IDs and exact retained cash.',
    'BankedBrainrotService': 'Unchanged logical individual/slot records; no profile mutation.',
}

def main():
    manifest = json.loads((OUT/'LiveSourceManifest.json').read_text())
    snapshots = json.loads((OUT/'snapshots/AllLiveSources_Before.json').read_text())
    baseline = json.loads((OUT/'BeforeManifest.json').read_text())
    by_key = {r['key']: r for r in snapshots}
    assert len(by_key) == len(manifest) == baseline['sourcesCount']
    rows, failures = [], []
    for record in manifest:
        path = OUT / record['file']
        raw = path.read_bytes()
        source = raw.decode('utf-8')
        checks = {'sha256': hashlib.sha256(raw).hexdigest() == record['sha256'],
                  'bytes': len(raw) == record['bytes'],
                  'snapshotSource': source == by_key[record['key']]['source']}
        if not all(checks.values()): failures.append({'path': record['path'], 'checks': checks})
        hits = {name: [{'line': i, 'text': line[:360]} for i,line in enumerate(source.splitlines(),1) if re.search(pattern,line)] for name,pattern in PATTERNS.items()}
        hits = {k:v for k,v in hits.items() if v}
        name = record['name']
        is_test = '.Tests.' in record['path'] or 'Test.server.lua' in record['path']
        row = {**record, 'verifiedExport': all(checks.values()), 'isTestOrHarness': is_test,
               'inspectionHits': hits, 'proposedHandling': READERS.get(name, 'Discovery only; no source modification proposed.')}
        rows.append(row)
    spatial = [r['path'] for r in rows if not r['isTestOrHarness'] and 'spatial_query' in r['inspectionHits']]
    semantic = [r['path'] for r in rows if not r['isTestOrHarness'] and 'map_or_semantic_coordinate' in r['inspectionHits']]
    objects = baseline['objects']
    floor_count = sum((r.get('attributes') if isinstance(r.get('attributes'),dict) else {}).get('LayoutRole')=='Floor' for r in objects)
    result = {
        'migrationId':'CompactMap_V1','status':'ReadOnlyFreshSourceAudit',
        'capturedAtUTC':baseline['capturedAtUTC'],'placeId':baseline['placeId'],'universeId':baseline['universeId'],
        'sourceBundleSHA256':baseline['sourceBundleSHA256'],
        'baselineManagedContentSHA256':baseline['baselineManagedContentSHA256'],
        'protectedAssetsContentSHA256':baseline['protectedAssetsContentSHA256'],
        'sourceCount':len(rows),'sourceClasses':dict(Counter(r['class'] for r in rows)),
        'allExportHashesBytesAndSnapshotSourcesVerified':not failures,'failures':failures,
        'managedInstances':len(objects),'protectedAssetInstances':len(baseline['protectedSourceAssets']),
        'actualFloorCount':floor_count,'editCollisionMatrix':baseline['collisionMatrix'],
        'actualReadableMapGeneratorPresent':False,
        'generatorFinding':'All 356 names and complete source text searched; CreateBasicMap/CreateBasicCamp/CreateBasicMapPaths are retained author attributes, not readable current generator sources. Existing local installers are separate future-write entry points.',
        'runtimeCollisionMatrixStatus':'Source registration audited; actual Play matrix not measured by this read-only Edit export.',
        'semanticCoordinateSources':semantic,'spatialQuerySources':spatial,'sources':rows,
        'limitations':['Lexical discovery is not dynamic reachability proof. Exact audited owner behavior is described in DependencyMap.md.',
                       'No require, Script.Source write, Studio operation, profile access or application was performed.',
                       'referenceConsumers=[] does not establish absence of runtime-held references or copied frames.'],
    }
    (OUT/'SourceDependencyAudit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'verifiedSources':len(rows),'failures':len(failures),'semanticSources':len(semantic),'spatialQuerySources':len(spatial),'floorCount':floor_count,'output':'docs/map-compaction/SourceDependencyAudit.json'}))
    assert not failures

if __name__=='__main__':main()
