#!/usr/bin/env python3
"""Serialize labelled candidate evidence. Geometry is produced by actual Luau.
No Studio access and no existing gameplay-source writes.
"""
import argparse,hashlib,json
from pathlib import Path
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
HERE=Path(__file__).parent
parser=argparse.ArgumentParser();parser.add_argument('--output-directory',type=Path,default=ROOT/'docs/map-compaction');args=parser.parse_args()
def read(path):
 raw=path.read_bytes();return json.loads(raw),hashlib.sha256(raw).hexdigest()
plan,raw_sha=read(HERE/'CompactDraftPlan.json');baseline,_=read(HERE/'CompactBaselineInput.json');tests,_=read(HERE/'CompactTestResults.json')
fit,fit_sha=read(ROOT/'docs/map-compaction/RuntimeBaseFitResultSummary.json')
assert plan['baselineManagedContentSHA256']==baseline['baselineManagedContentSHA256']
assert fit['sourceBundleSHA256']==plan['sourceBundleSHA256']
assert tests['failed']==0 and tests['inputPreserved']
plan['selectedCandidate']=None
plan['candidateStatus']='DraftOnly_NotSelected'
plan['applyEligible']=False
plan['applicationBlocked']=True
plan['applicationBlockEvidence']={'path':'docs/map-compaction/RuntimeBaseFitResultSummary.json','sha256':fit_sha,'allInteriorRowsFail':fit['allInteriorRowsFail'],'fullCandidateAcceptance':fit['fullCandidateAcceptance'],'policy':'Parent owns candidate selection and authorized exceptions; this numeric draft cannot bypass native fit.'}
plan['actualRoadBindings']=baseline['actualRoads']
plan['pureTestEvidence']={'path':'tools/map-compaction/CompactTestResults.json','passed':tests['passed'],'failed':tests['failed'],'runtime':tests['runtime'],'inputPreserved':tests['inputPreserved']}
plan['numericDraftSHA256']=raw_sha
common={k:plan[k] for k in ['schemaVersion','migrationId','candidate','selectedCandidate','candidateStatus','applyEligible','applicationBlocked','applicationBlockEvidence','baselineManagedContentSHA256','beforeManifestSHA256','sourceBundleSHA256','sourceLayoutVersion','routePointsCanonicalSHA256','actualRoadBindingsSHA256']}
gate_owner={x['id']:x for x in plan['gateAprons']}
for row in plan['crossings']:
 cuts=[x for x in plan['wallCuts'] if x['crossingId']==('Gate_'+row['owningGate'] if row.get('owningGate') else row['id'])]
 row['allWallThicknessCuts']=cuts
 row['cornerReliefCuts']=[x for x in cuts if x['runId']!=row['runId']]
 row['nativePassageTest']='NotRun'
crossings={**common,'crossings':plan['crossings'],'openingPolygons':plan['approvedOpeningPolygons'],'gateAprons':plan['gateAprons'],'counts':{'semanticCrossings':len(plan['crossings']),'paidGateOpenings':sum(bool(x.get('owningGate')) for x in plan['crossings']),'freeCampForestOpenings':sum(x['accessPolicy']=='ExistingFreeCampForestRoad' for x in plan['crossings']),'unframedOpenings':sum(x['accessPolicy']=='ExistingUnframedRoadWithServerRegionPermission' for x in plan['crossings']),'retainedExistingClosedCrossings':sum(x['accessPolicy']=='ExistingEquivalentRestriction' for x in plan['crossings']),'documentedOnFootConnectors':0},'limitations':['Numeric aperture exclusion is proven; driving/jamb/neighbor-access permissions and native passage are not tested.','No on-foot connector or opening is inferred from broad decorative surface overlap.']}
walls={**common,'sharedRuns':plan['sharedRuns'],'cuts':plan['wallCuts'],'junctions':plan['junctions'],'junctionConflicts':plan['junctionConflicts'],'newInterRegionWalls':plan['walls'],'flags':plan['wallFlags'],'existingSeparatorClassification':plan['existingSeparatorClassification'],'retainedOuterContainment':plan['retainedOuterContainment'],'budget':plan['wallBudget'],'assetStatus':plan['wallAssetStatus'],'counts':{'sourcePhysicalSeparators':41,'sourceInterRegionPortions':sum(p['kind']=='InterRegion' for x in plan['existingSeparatorClassification'] for p in x['portions']),'capturedRetainedOuterPortions':len(plan['retainedOuterContainment']),'newWallSegments':len(plan['walls']),'draftTotalPhysicalSeparators':len(plan['walls'])+len(plan['retainedOuterContainment'])},'installed':False,'limitations':['Do not retain old shared-region separators over the new unique wall set; parent must preserve/rebind captured identities before removal.','Outer containment keeps its original four-stud thickness, inward local offset, Y and height; it is not included in new six-stud wall count.','Material IDs are genuine captured saved-stud IDs; shared closed-cuboid mesh ID is unbound and cannot be fabricated.','54 source cuboids imply648 source triangles. Native asset renderer totals are not measured.']}
args.output_directory.mkdir(parents=True,exist_ok=True)
for filename,value in [('RouteBoundaryDraft.json',plan),('CrossingManifest.json',crossings),('WallManifest.json',walls)]:
 p=args.output_directory/filename;p.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n');print(filename,hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size)
