#!/usr/bin/env python3
"""Summarize actual native Audit output. Never converts prepared checks to native passes."""
import argparse,hashlib,json,pathlib
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def summarize(data):
 assert data['nativeExecutionPassed'] is True
 assert data['sourceWrites']==0 and data['originalObjectWrites']==0 and data['workspaceWrites']==0
 assert data['cleanup']['stageRemoved'] and data['cleanup']['originalSourcesUnchanged']
 assert len(data['bases'])==12 and len(data['candidateSummary'])==6
 first=data['bases'][0];species=first['measuredSpecies'];assert len(species)==data['eligibleSpeciesCount']
 measured=[(base['id'],entry)for base in data['bases']for entry in base['measuredSpecies']]
 maxima={}
 def record(name,value,id):
  if name not in maxima or value>maxima[name]['value']:maxima[name]={'value':value,'species':id}
 for base_id,entry in measured:
  sides=entry['bySide'];sides=sides.values() if isinstance(sides,dict)else sides
  for side in sides:
   if side is None:continue
   box=side['platformBounds'];low,high=box['min'],box['max']
   record('nativeVisibleTangentialSpan',high[0]-low[0],entry['id'])
   record('nativeVisibleTransverseSpan',high[2]-low[2],entry['id'])
   record('centredFullSupportTangentialPad',max(10,2*(max(abs(low[0]),abs(high[0]))+1)),entry['id'])
   record('centredFullSupportTransversePad',max(10,2*(max(abs(low[2]),abs(high[2]))+1)),entry['id'])
 pad_t=maxima['centredFullSupportTangentialPad']['value'];pad_w=maxima['centredFullSupportTransversePad']['value']
 stride=max(pad_t+2,maxima['nativeVisibleTangentialSpan']['value']+2)
 aisle_centre=(pad_w+6)/2
 needed_depth=5*stride+pad_t;needed_width=2*pad_w+6
 correction={
  'status':'Measured necessary envelope lower bounds only; source/presentation correction not authorized by this audit',
  'allSpeciesTangentialStrideAtLeast':stride,'rowCentreAbsoluteXAtLeast':aisle_centre,
  'sixRowsOccupiedDepthAtLeast':needed_depth,'twoColumnsOccupiedWidthAtLeast':needed_width,
  'centredSixRowZ':[(i-2.5)*stride for i in range(6)],
  'atPreferredFactor075PreContractionStrideAtLeast':stride/.75,
  'atPreferredFactor075PreContractionRowCentreXAtLeast':aisle_centre/.75,
  'preferredVisiblePlot':{'width':72,'depth':82.5},
  'hypotheticalDimensionOnlyFits':needed_width<=72 and needed_depth<=82.5,
  'actualPreferredBaseFitPassed':False,
  'dimensionComparisonScope':'Width/depth only; cannot establish anchored plot/slab/cart/plaque fit',
  'existingRuntimeFloorContracted075':{'width':27,'depth':24},
  'existingRuntimeFloorSupportsNecessaryFormation':needed_width<=27 and needed_depth<=24,
  'unassessed':['actual plaque/casing/wall/pillar clearance','foundation residual offsets','cart return/deposit/swept approaches','service/routes','source specialization permission','true rotated native mesh separation instead of conservative extent boxes'],
 }
 return {'schemaVersion':1,'nativeAuditPassed':True,'fullCandidateAcceptance':False,'currentOwnerInteriorFit':data['candidateSummary'],'releasedSpeciesCount':len(species),'excludedSpecies':data['excludedSpecies'],'sourceBundleSHA256':data['sourceBundleSHA256'],'originalInstancesUnchanged':data['cleanup']['originalInstancesUnchanged'],'maxima':maxima,'compactOwnerCorrectionNecessaryBounds':correction,'allInteriorRowsFail':all(not c['interiorPassing']for c in data['candidateSummary']),'outerFallbackPermitted':False}
def baseline_local_bounds(baseline,base_path):
 base=next(r for r in baseline['objects']if r['path']==base_path)
 pivot=base['pivot']['value'];rotation=[pivot[3:6],pivot[6:9],pivot[9:12]]
 def envelope(row):
  cf=row['properties']['CFrame']['value'];size=row['properties']['Size']['value'];r=[cf[3:6],cf[6:9],cf[9:12]];points=[]
  for sx in [-1,1]:
   for sy in [-1,1]:
    for sz in [-1,1]:
     corner=[sx*size[0]/2,sy*size[1]/2,sz*size[2]/2]
     world=[cf[i]+sum(r[i][j]*corner[j]for j in range(3))for i in range(3)]
     points.append([sum(rotation[i][j]*(world[i]-pivot[i])for i in range(3))for j in range(3)])
  return {'min':[min(p[i]for p in points)for i in range(3)],'max':[max(p[i]for p in points)for i in range(3)]}
 visible=[];parts={}
 for row in baseline['objects']:
  if row['path'].startswith(base_path+'.')and 'properties'in row and 'CFrame'in row['properties']:
   parts[row['name']]=envelope(row)
   if row['properties'].get('Transparency',1)<1:visible.append(parts[row['name']])
 low=[min(v['min'][i]for v in visible)for i in range(3)];high=[max(v['max'][i]for v in visible)for i in range(3)]
 return {'basePath':base_path,'structuralAnchor':pivot,'visiblePlotBounds':{'min':low,'max':high},'visiblePlotResidualCentre':[(low[i]+high[i])/2 for i in range(3)],'parts':parts}
def enrich_anchor_limits(result,baseline):
 correction=result['compactOwnerCorrectionNecessaryBounds'];depth=correction['sixRowsOccupiedDepthAtLeast'];width=correction['twoColumnsOccupiedWidthAtLeast']
 checks=[]
 for base in [r for r in baseline['objects']if r['class']=='Model'and r['name'].startswith('Base_')]:
  info=baseline_local_bounds(baseline,base['path']);plot=info['visiblePlotBounds'];foundation=info['parts']['Foundation'];rows=[]
  for b in [.75,.8,.85,.9,.95,1]:
   available_centre_z=[plot['min'][2]*b+depth/2,plot['max'][2]*b-depth/2]
   rows.append({'b':b,'plotBoundsXZ':[plot['min'][0]*b,plot['max'][0]*b,plot['min'][2]*b,plot['max'][2]*b],'contractedFoundationSizeXZ':[(foundation['max'][0]-foundation['min'][0])*b,(foundation['max'][2]-foundation['min'][2])*b],'formationCentredAtRuntimeZ0FitsVisiblePlot':plot['min'][0]*b<=-width/2 and width/2<=plot['max'][0]*b and plot['min'][2]*b<=-depth/2 and depth/2<=plot['max'][2]*b,'formationFitsContractedFoundation':(foundation['max'][0]-foundation['min'][0])*b>=width and (foundation['max'][2]-foundation['min'][2])*b>=depth,'allowableUniformFormationCentreZIfShiftWereExplicitlyAuthorized':available_centre_z,'uniformShiftFeasibleIgnoringOtherGeometry':available_centre_z[0]<=available_centre_z[1],'originalCartDisplayBounds':info['parts'].get('CartDisplay'),'cartOverlapAndLoadedSweep':'NotAssessed; current full-size actors cannot be squeezed to fit'})
  checks.append({'baseId':base['name'],'structuralAnchor':info['structuralAnchor'],'visiblePlotResidualCentre':info['visiblePlotResidualCentre'],'originalVisiblePlotBounds':plot,'originalFoundationBounds':foundation,'candidates':rows})
 result['capturedStructuralAnchorChecks']=checks
 result['compactOwnerCorrectionNecessaryBounds']['additionalScopeRequired']='A common centroid shift and supporting slab revision would need explicit authorization and all functional geometry checks; dimensions alone are insufficient'
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('input',type=pathlib.Path);p.add_argument('--root',type=pathlib.Path,default=ROOT);a=p.parse_args()
 d=json.loads(a.input.read_text());r=enrich_anchor_limits(summarize(d),json.loads((a.root/'docs/map-compaction/BeforeManifest.json').read_text()));r['evidenceFile']=str(a.input.resolve());r['evidenceSHA256']=hashlib.sha256(a.input.read_bytes()).hexdigest()
 out=a.root/'docs/map-compaction/RuntimeBaseFitResultSummary.json';out.write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps(r,indent=2))
if __name__=='__main__':main()
