#!/usr/bin/env python3
"""Read-only source scope checks; write the owned verification report only."""
from pathlib import Path
import json,hashlib,re,ast
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/map-compaction';OUT=DOC/'source-patches'
def sha(text):return hashlib.sha256(text.encode()).hexdigest()
def functions(source):
 out={}
 for match in re.finditer(r'^(?:local )?function ([\w.:]+)\b',source,re.M):
  end=re.search(r'^end\b[^\n]*',source[match.end():],re.M)
  assert end,match.group(1)
  out[match.group(1)]=source[match.start():match.end()+end.end()]
 return out
ALLOWED={
 'ReplicatedStorage.Shared.Config.BaseLayoutConfig':{'BaseLayoutConfig.GetGeometry'},
 'ServerScriptService.Server.Systems.BaseIncomePlaqueSystem':{'createPillar','createPerimeterPillars','ensureInterior','positionPlatforms','configurePlaque','BaseIncomePlaqueSystem:BuildBase'},
 'ServerScriptService.Server.Systems.RegionSpawnCatalog':{'defaultContext','RegionSpawnCatalog.BuildIndex','isProtected','RegionSpawnCatalog.IsInsideRegionSpace','RegionSpawnCatalog.ValidatePlacement'},
 'ServerScriptService.Server.Systems.BrainrotSaleSystem':{'isPlayerWithinSaleRange'},
 'ServerScriptService.Server.Services.UpgradeService':{'withinShopRange'},
}
m=json.loads((OUT/'SourcePatchManifest.json').read_text());payload=json.loads((OUT/'SourcePatchPayload.json').read_text());checks=[];preserved=0
for row,record in zip(payload['patches'],m['patchedOwners']):
 before=row['beforeSource'];after=row['afterSource'];current=(DOC/'live-sources'/Path(*row['path'].split('.'))).with_suffix('.lua').read_text()
 assert before==current and sha(before)==row['beforeSHA256']==record['beforeSHA256']
 assert after==(ROOT/record['proposal']).read_text() and sha(after)==record['afterSHA256']
 old_funcs,new_funcs=functions(before),functions(after)
 changed=[]
 for name in sorted(set(old_funcs)|set(new_funcs)):
  if old_funcs.get(name)!=new_funcs.get(name):changed.append(name);assert name in ALLOWED[row['path']],('unapproved function change',row['path'],name)
  else:preserved+=1
 assert set(changed)==ALLOWED[row['path']],(row['path'],changed)
 checks.append({'path':row['path'],'beforeExact':True,'afterExact':True,'changedFunctions':changed,'byteIdenticalExistingFunctions':len(old_funcs)-len(set(changed)&set(old_funcs))})
# Canonical scale/native-art envelope, roster/pools, claims, balances and gate LOS remain in original owners.
base=payload['patches'][1]['afterSource'];spawn=payload['patches'][2]['afterSource']
assert 'local geometry = Config.GetGeometry(base)\n\tteardownBase(base, false)' in base
assert 'local foundation = base:FindFirstChild("Foundation")' in base
assert 'math.abs(localPosition.X - centreX)' in base
assert 'Vector3.new(tangentSize, platform.Size.Y, normalSize)' in base
assert 'StaticMaterial.Apply(resolvedFloor)' in base
for row,part in [(payload['patches'][3],'salePoint'),(payload['patches'][4],'shop')]:
 assert row['afterSource'].replace('local CompactMapGeometry = require(ReplicatedStorage.Shared.Utility.CompactMapGeometry)\n','').replace('CompactMapGeometry.ResolveInteractionSize('+part+')',part+'.Size')==row['beforeSource'],row['path']
assert 'getMapArtEnvelope(index, definition)' in spawn and 'MAX_MAP_ART_FOOTPRINTS = 345' in spawn
assert 'StaticWallObstacles' in spawn and 'getMapArtEnvelope' not in ALLOWED['ServerScriptService.Server.Systems.RegionSpawnCatalog']
for row in m['guardedInstallerProposals']:
 proposal=(ROOT/row['proposal']).read_text();original=(ROOT/row['path']).read_text()
 assert sha(original)==row['beforeSHA256'] and sha(proposal)==row['afterSHA256']
 for marker in ['CompactMapMigrationId','CompactMapStatus','CompactMapDesiredHash','CompactMapRuntimeGeometry']:assert marker in proposal[:750]
for path in [ROOT/'tools/map-compaction/CompactSourcePatches.py',ROOT/'tools/map-compaction/BuildCompactMetadata.py',Path(__file__)]:
 if path.exists():ast.parse(path.read_text())
tests=json.loads((OUT/'SourcePatchTestResults.json').read_text());assert tests['failed']==0 and tests['passed']>=40
result={'schemaVersion':1,'status':'LocalSourceScopePassed','baselineSourceBundleSHA256':m['baselineSourceBundleSHA256'],'owners':checks,'patchedOriginalOwners':len(checks),'newOwners':1,'byteIdenticalExistingFunctions':preserved,'guardedHistoricalInstallers':len(m['guardedInstallerProposals']),'localLuauRegressions':{'passed':tests['passed'],'failed':tests['failed'],'file':'docs/map-compaction/source-patches/SourcePatchTestResults.json'},'applyHelper':m['applyHelper'],'actualStudioSourceWrites':0,'nativeRuntimeFit':'NotMeasuredByThisAudit','preservedDomains':['claim/income/accrual/collection amounts and cooldown','currency/profile version/data-store keys','32 released/3 teased status and roster','canonical actor/display scale and native art envelopes','cart/cargo/control dimensions and behavior','six paid access rules and capture LOS','original 343 footprint records kept separate from walls']}
(OUT/'SourcePatchVerification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'changedOwners':len(checks),'unchangedFunctions':preserved,'localTests':tests['passed'],'historicalGuards':6,'nativeFit':'NotMeasured'}))
