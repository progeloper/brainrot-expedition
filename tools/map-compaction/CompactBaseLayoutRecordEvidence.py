#!/usr/bin/env python3
"""Promote only actual recorded native interior fit evidence; preserve other pending gates."""
import json,pathlib,hashlib
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition');DOC=ROOT/'docs/map-compaction'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
def main():
 p=DOC/'CompactBaseLayoutNativeFit_085_FinalOwner.json';p=p if p.exists()else DOC/'CompactBaseLayoutNativeFit_085.json';native=json.loads(p.read_text())
 assert native['nativeExecutionPassed']and native['nativeProposalFitPassed']and native['b']==.85
 assert native['nativeDisplayPlacementCalls']==768 and native['logicalSpeciesSlotCases']==4608 and len(native['bases'])==12 and native['releasedSpeciesCount']==32
 assert native['cleanup']=={'originalInstancesUnchanged':2718,'stageRemoved':True,'originalSourcesUnchanged':True}
 assert native['sourceWrites']==native['originalObjectWrites']==native['workspaceWrites']==0
 current=json.loads((DOC/'CompactBaseLayoutPartLocals_085.Prepared.json').read_text());by_id={row['id']:row for row in current['bases']}
 for b in native['bases']:
  row=by_id[b['id']];slots={r['stableSlotIndex']:r for r in row['parts']if'stableSlotIndex'in r}
  for i,cf in enumerate(b['nativePadCFrames'],1):assert max(abs(a-c)for a,c in zip(cf,slots[i]['localCFrame']))<1e-4
  pad=next(r for r in row['parts']if r['name']=='CartDisplay');assert max(abs(a-c)for a,c in zip(b['loadedCartSupport']['cartDisplaySize'],pad['size']))<1e-4
  assert max(abs(a-c)for a,c in zip(b['loadedCartSupport']['cartDisplayLocal'],pad['localCFrame']))<1e-4
 for source in native['proposalEvidence']['sources']:assert sha(pathlib.Path(source['path']))==source['sha256']
 # Complete source report retains a private owner only; its prepared parser flag is not production acceptance.
 evidence={'scope':'Actual native isolated owner/interior fit; no gameplay/full-site/native-import pass inferred','file':str(p),'sha256':sha(p),'nativeDisplayPlacements':768,'logicalSpeciesSlotCases':4608,'eligibleSpecies':32,'bases':12,'elapsedSeconds':native['elapsedSeconds'],'minimumDisplayGap':native['minimumVisibleGap'],'minimumPadGap':native['minimumPadGap'],'minimumFullSupportMargin':native['minimumFullSupportMargin'],'minimumClaimFaceAisle':native['minimumClaimFaceAisle'],'temporaryStageRemoved':True,'originalObjectsPreserved':2718,'checkedLiveSourcesPreserved':10,'allFunctionalRampDimensionsPreserved':True,'nativeLoadedCartSupportPassed':True,'allTwelveOriginalFoundationColourFlagsAndEffectivePhysicsPreserved':all(b.get('foundationOriginalColourFlagsEffectivePhysicsPreserved') is True for b in native['bases']),'loadedCartDrivingTurningPassed':False,'fullSiteGeometryPassed':False,'nativeShellImportPassed':False,'gameplayPassed':False}
 cpath=DOC/'CompactBaseLayoutCandidates.json';candidates=json.loads(cpath.read_text());selected=next(c for c in candidates['candidates']if c['b']==.85);selected['status']='NativeOwnerInteriorFitPassedFullAcceptancePending';selected['acceptance']['nativeFixturePassed']=True;selected['nativeFitEvidence']=evidence;candidates['status']='NativeOwnerInteriorFitPassedFullAcceptancePending';candidates['selectedNativeInteriorCandidate']=.85;write(cpath,candidates)
 raw=json.loads((DOC/'CompactBaseLayoutRuntimeGeometry.Prepared.json').read_text());assert raw['runtimeValidated']is False;validated=dict(raw);validated['runtimeValidated']=True;validated['nativeInteriorValidationEvidence']=evidence;write(DOC/'CompactBaseLayoutRuntimeGeometry.NativeValidated.json',validated)
 write(DOC/'CompactBaseLayoutValidationStatus.json',{'schemaVersion':1,'status':'NativeInteriorPassedFullAcceptancePending','selectedB':.85,'nativeEvidence':evidence,'productionPreparedGeometryChanged':False,'newNativeValidatedGeometryFile':str(DOC/'CompactBaseLayoutRuntimeGeometry.NativeValidated.json'),'approvalScope':'User authorized uniform six-by-two presentation/support/functionally necessary owner correction; original actors and economy unchanged','remaining':['actual imported fitted shell every-corner/IDs/material proof','complete site footprint/neighbor/floors/scripts readback','actual loaded-cart lateral approach/turning','ordinary interactions/rejoin/multiplayer/mobile/performance','root transaction application/save/cold reopen']})
 plan=DOC/'CompactBaseLayoutPlan.md';text=plan.read_text().split('\nThe current native .85 owner fixture has now passed:')[0];text+='\nThe current native .85 owner fixture has now passed: 768 actual placements, 4,608 rigid-equivalent slot cases and 12 bases. Minimum measured display gap is 4.844932251, pad gap 2.02, full-support margin 1.000810585 and claim-face aisle 6.019989014 studs. Both original functional ramp dimensions and native .2-stud support joins passed; the loaded projection remained supported at every base. The stage was removed and all 2,718 guarded original nodes plus ten checked live sources stayed unchanged. `'+p.name+'` is the actual evidence for the current service-aware, Foundation-preserving owner sources. The separate NativeValidated runtime geometry reflects this interior owner test only; full site/import/loaded driving and gameplay gates remain pending.\n';plan.write_text(text)
 print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
