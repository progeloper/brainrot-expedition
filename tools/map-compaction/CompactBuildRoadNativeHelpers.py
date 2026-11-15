#!/usr/bin/env python3
"""Generate every-corner native asset QA and proof-gated template preparation.
Original map-art helper assets are read only. Never changes Studio.
"""
import argparse,hashlib,json
from pathlib import Path
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
HERE=Path(__file__).parent
p=argparse.ArgumentParser();p.add_argument('--geometry-directory',type=Path,required=True);p.add_argument('--native-batch-directory',type=Path);args=p.parse_args();directory=args.geometry_directory
manifest=json.loads((directory/'CompactRouteMeshManifest.json').read_text());expected=json.loads((directory/'CompactRoadExpectedGeometry.json').read_text())
sourcehash=hashlib.sha256((directory/'CompactRoadsCanonical.glb').read_bytes()).hexdigest();importhash=hashlib.sha256((directory/'CompactRoadsStudioImport.glb').read_bytes()).hexdigest()
assert sourcehash==manifest['canonicalGLB']['sha256'] and importhash==manifest['studioImportGLB']['sha256']
if args.native_batch_directory:
 batch=json.loads((args.native_batch_directory/'CompactNativeAssetManifest.json').read_text())
 assert batch['roadCanonicalSourceSHA256']==sourcehash and batch['roadGeometryHash']==manifest['routeGeometryHash']
 importhash=hashlib.sha256((args.native_batch_directory/batch['studioImportFile']).read_bytes()).hexdigest();assert importhash==batch['studioImportSHA256']
assert len(expected)==27 and sum(len(g['triangles']) for g in expected)==manifest['triangles']
template=(ROOT/'assets/map-art/VerifyNativeRoadGeometry.template.luau').read_text()
template=template.replace('MapArt_ImportedRoads','CompactMap_ImportedRoads').replace('UVAndPhasePassed','sourceUVValuesPassed').replace('__SOURCE_HASH__',sourcehash).replace('__IMPORT_HASH__',importhash)
template=template.replace('importRoot.Name=="CompactMap_ImportedRoads" and importRoot:IsDescendantOf(game:GetService("ServerStorage"))', '(importRoot.Name=="CompactMap_ImportedRoads" or importRoot.Name=="CompactMapRoads" and importRoot.Parent.Name=="CompactMap_ImportedAssets") and importRoot:IsDescendantOf(game:GetService("ServerStorage"))')
template=template.replace('preserving source s/u phase and per-corner UV seams.', 'preserving exact authored source UV values and per-corner UV seams.').replace('geometry+UV phase', 'geometry+source UV')
template=template.replace('sourceRoutePointSHA256="7c0411ac82bd863df409dcf71ebc49f6649564dcb30aa2a6a9e6e59408dd20a5",','sourceRoutePointSHA256="'+manifest['sourceRoutePointSHA256']+'",\n        routeGeometryHash="'+manifest['routeGeometryHash']+'",')
(directory/'CompactVerifyNativeRoadGeometry.luau').write_text(template.replace('__EXPECTED_JSON__',json.dumps(expected,separators=(',',':'))))
qa=directory/'road-qa';qa.mkdir(exist_ok=True)
for row in expected:(qa/(row['id']+'.verify.luau')).write_text(template.replace('__EXPECTED_JSON__',json.dumps([row],separators=(',',':'))))
rows=[{k:v for k,v in g.items() if k!='triangles'}|{'triangles':len(g['triangles'])} for g in expected]
prepare=(HERE/'CompactPrepareRoads.template.luau').read_text().replace('importRoot.Name == "CompactMap_ImportedRoads"', '(importRoot.Name == "CompactMap_ImportedRoads" or importRoot.Name == "CompactMapRoads" and importRoot.Parent.Name == "CompactMap_ImportedAssets")').replace('__SOURCE_HASH__',sourcehash).replace('__IMPORT_HASH__',importhash).replace('__GEOMETRY_HASH__',manifest['routeGeometryHash']).replace('__ROUTE_HASH__',manifest['sourceRoutePointSHA256']).replace('__ROWS_JSON__',json.dumps(rows,separators=(',',':')))
(directory/'CompactPrepareImportedRoads.luau').write_text(prepare)
report={'status':'Prepared; actual native invocation NotRun','migrationId':'CompactMap_V1','candidate':manifest['candidate'],'sourceSHA256':sourcehash,'studioImportSHA256':importhash,'routeGeometryHash':manifest['routeGeometryHash'],'groups':len(expected),'triangles':manifest['triangles'],'corners':manifest['corners'],'verifier':'CompactVerifyNativeRoadGeometry.luau','preparer':'CompactPrepareImportedRoads.luau','expectedNativeImportRoot':'ServerStorage.CompactMap_ImportedRoads','preparedTemplateRoot':'ServerStorage.CompactMapRoadTemplates','actualStudioMutationByAuthoring':0,'requiredProof':['Real native MeshIds','Exact triangle count and every oriented corner/UV/+Y normal','No unreferenced vertices; native axes/local bounds and XZ sizes','Every expected group, no extras; canonical/import/geometry hashes','Native planar bounding clamp.001/.05; prepared Size.Y=.05 rendered plane remains canonicaltopY'],'worldPlacementValidatedByAssetQA':False,'materialStyle':'Saved Glacier/Bingus studs.25; no static TextureID or SurfaceAppearance'}
(directory/'CompactNativeRoadReadiness.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
