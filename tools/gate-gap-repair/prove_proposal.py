import json,math
from pathlib import Path
p=Path('/private/tmp/GateGapAudit/GeometryClosureProposal.json')
x=json.loads(p.read_text())
ns={}
exec(Path('/private/tmp/GateGapAudit/measure_geometry.py').read_text(),ns)
gaps,coverage,bounds=ns['gaps'],ns['linecoverage'],ns['bounds']; structural=ns['structural'];gateparts=ns['gateparts'];geo=ns['geo']
synthetic=[{'path':q['id'],'class':'Part','cf':q['nativeCFrame'],'size':q['worldSize'],'collide':True,'query':True}for q in x['jambProposals']+x['cornerReturnProposals']+x['upperBridgeProposals']]
heights=[.10,1,5,10,17.99,19,21,35,70]
def subtract(gap,allowed):
 pending=[gap]
 for a,b in allowed:
  tmp=[]
  for l,h in pending:
   if a>l+.0001:tmp.append([l,min(a,h)])
   if b<h-.0001:tmp.append([max(b,l),h])
  pending=[[l,h]for l,h in tmp if h>l+.0001]
 return pending
allheights=[]
for h in heights:
 for e in x['perimeterLines']:
  cov,_=coverage(structural+gateparts+synthetic,e['axis'],e['fixed'],h,e['first'],e['last'])
  missing=gaps(cov,e['first'],e['last']);allowed=[]
  if h<18.05:
   allowed +=[q['desiredAperture']for q in x['paidGates']if q['axis']==e['axis']and abs(q['fixed']-e['fixed'])<.001]
  if h<20.05:
   allowed +=[[a,b]for ax,fi,a,b in x['intentionalFreeForestCornerFaces']if ax==e['axis']and abs(fi-e['fixed'])<.001]
  extras=[r for g in missing for r in subtract(g,allowed)]
  allheights.append({'height':h,'region':e['region'],'axis':e['axis'],'fixed':e['fixed'],'first':e['first'],'last':e['last'],'remainingOpenings':missing,'expectedOpenings':allowed,'unexpected':extras})
historical=json.loads(Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition/docs/environment-v2/CurrentGeometry.json').read_text())
closed=[]
for alt in historical['closedAlternates']:
 xx,yy,zz=alt['intersection'];axis='Z'if alt['id']=='X_Camp_Exterior_ES_R12_0'else'X';fixed=xx if axis=='Z'else zz;center=zz if axis=='Z'else xx
 tests=[]
 for h in [1,5,17.99,35,70]:
  cov,owners=coverage(structural+gateparts,axis,fixed,h,center-alt['width']/2,center+alt['width']/2)
  tests.append({'height':h,'gaps':gaps(cov,center-alt['width']/2,center+alt['width']/2),'owners':owners})
 closed.append({'id':alt['id'],'intersection':alt['intersection'],'axis':axis,'fixed':fixed,'center':center,'width':alt['width'],'geometryChecks':tests,'alreadyClosed':all(not t['gaps']for t in tests),'routeMetadataProvenance':'Historical frozen environment CurrentGeometry closedAlternates IDs; collider coverage independently checked against fresh Live.json.'})
# For each actual gate, test every proposed envelope against the full 24-wide18-high travel corridor +/-24normal.
corridors=[]
for gate in x['paidGates']:
 axis,fixed,center=gate['axis'],gate['fixed'],gate['center']
 if axis=='X':box=[center-12,.05,fixed-24,center+12,18.05,fixed+24]
 else:box=[fixed-24,.05,center-12,fixed+24,18.05,center+12]
 hit=[]
 for q in synthetic:
  b=bounds(q);over=[min(box[i+3],b[i+3])-max(box[i],b[i])for i in range(3)]
  if all(v>.0001for v in over):hit.append({'id':q['path'],'positiveOverlap':over})
 corridors.append({'gate':gate['gate'],'groundedLoadedEnvelopeWidth':24,'groundedLoadedEnvelopeHeight':18,'normalTravelEachSide':24,'corridorBounds':box,'proposalPositiveIntersections':hit})
x.update({'multiHeightPerimeterChecks':allheights,'multiHeightPerimeterCheckCount':len(allheights),'multiHeightUnexpectedGaps':[r for r in allheights if r['unexpected']],'closedAlternateCrossings':closed,'paidLoadedCartCorridors':corridors,'proposalHasZeroPositiveIntersectionsWith24x18Corridors':all(not c['proposalPositiveIntersections']for c in corridors)})
p.write_text(json.dumps(x,indent=2))
print('perimeter lines',len(x['perimeterLines']),'multiheight',len(allheights),'Unexpected',len(x['multiHeightUnexpectedGaps']))
print('closed alternates',[(c['id'],c['alreadyClosed'])for c in closed])
print('corridors',[(c['gate'],len(c['proposalPositiveIntersections']))for c in corridors])
