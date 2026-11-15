from pathlib import Path
import json, math
root=Path('/private/tmp/GateGapAudit')
ns={}
exec((root/'measure_geometry.py').read_text(),ns)
data=ns['data']; geo=ns['geo']; structural=ns['structural']; gateparts=ns['gateparts']; bounds=ns['bounds']; coverage=ns['linecoverage']; gaps=ns['gaps']; perimeter=ns['perimeters']; attrs=ns['attrs']
out=json.loads((root/'GeometryCoverage.json').read_text())
out.pop('proposedJambEnvelopes',None)
jambs=[]; bridges=[]
for gate in out['paidGates']:
 center,axis,fixed=gate['center'],gate['axis'],gate['fixed']; cut=gate['actualStructuralOpening']; ap=gate['desiredAperture']
 idx=0 if axis=='X' else 2; normalidx=2 if axis=='X' else 0
 adjacent=[]
 for p in structural:
  b=bounds(p)
  if b[normalidx]-.001<=fixed<=b[normalidx+3]+.001 and b[1]<5<b[4] and (abs(b[idx+3]-cut[0])<.001 or abs(b[idx]-cut[1])<.001):
   adjacent.append({'path':p['path'],'top':b[4],'bounds':b})
 header=[p for p in geo if f'.Gate_{gate["gate"]}_Header_' in p['path'] and p['collide']]
 top=max([a['top'] for a in adjacent]+[bounds(p)[4] for p in header])
 gate['adjacentColliderTops']=adjacent;gate['closureTop']=top;gate['headerColliderBounds']=[bounds(p) for p in header]
 bottom=-1.0;height=top-bottom
 for side,(first,last) in [('Negative',(cut[0]-.25,ap[0])),('Positive',(ap[1],cut[1]+.25))]:
  xyz=[(first+last)/2,(bottom+top)/2,fixed] if axis=='X' else [fixed,(bottom+top)/2,(first+last)/2]
  size=[last-first,height,4] if axis=='X' else [4,height,last-first]
  jambs.append({'id':gate['gate']+'_Jamb_'+side,'gate':gate['gate'],'side':side,'kind':'GateJamb','worldPosition':xyz,'worldSize':size,'nativeCFrame':xyz+[1,0,0,0,1,0,0,0,1],'alongInterval':[first,last],'wallDepth':4,'bottom':bottom,'top':top,'groundY':.05,'desiredAperture':ap})
 # Guaranteed full-height continuation above the existing 18-stud clear aperture, face outside gate model.
 # Same 4-stud normal-depth bridge as gate lintel; redundant with existing lintel/header where overlapping.
 lower=.05+18
 xyz=[center,(lower+top)/2,fixed] if axis=='X' else [fixed,(lower+top)/2,center]
 size=[24,top-lower,4] if axis=='X' else [4,top-lower,24]
 bridges.append({'id':gate['gate']+'_UpperBridge','gate':gate['gate'],'kind':'UpperBridge','worldPosition':xyz,'worldSize':size,'nativeCFrame':xyz+[1,0,0,0,1,0,0,0,1],'bottom':lower,'top':top,'groundY':.05,'clearHeight':18,'wallDepth':4,'clearWidth':24,'existingLintelAlreadyOverlapsLower2Studs':True})
returns=[]
# Two Volcano corner side openings are separated by existing plane and new negative jamb.
v=next(p for p in out['paidGates'] if p['gate']=='Volcano')
vzmax=v['desiredAperture'][0]; vtop=v['closureTop']
for label,a,b in [('CampForest',181,227),('ArcticVolcano',231,277)]:
 lo,hi=a-.25,b+.25; zlo=-296; zhi=vzmax
 xyz=[(lo+hi)/2,(-1+vtop)/2,(zlo+zhi)/2];size=[hi-lo,vtop+1,zhi-zlo]
 returns.append({'id':'VolcanoCornerReturn_'+label,'gate':'Volcano','kind':'OrthogonalReturn','unintendedOpening':{'axis':'X','fixed':-294,'first':a,'last':b},'worldPosition':xyz,'worldSize':size,'nativeCFrame':xyz+[1,0,0,0,1,0,0,0,1],'bounds':[lo,-1,zlo,hi,vtop,zhi],'bottom':-1,'top':vtop,'gateApertureBoundaryPositiveZ':vzmax})
j=next(p for p in out['paidGates'] if p['gate']=='Jungle')
jxmax=j['desiredAperture'][0]; jtop=j['closureTop']
for label,a,b in [('CampForest',154,182),('SwampJungle',234.95560121536255,250)]:
 zlo,zhi=a-.25,b+.25;xlo=-283;xhi=jxmax
 xyz=[(xlo+xhi)/2,(-1+jtop)/2,(zlo+zhi)/2];size=[xhi-xlo,jtop+1,zhi-zlo]
 returns.append({'id':'JungleCornerReturn_'+label,'gate':'Jungle','kind':'OrthogonalReturn','unintendedOpening':{'axis':'Z','fixed':-267,'first':a,'last':b},'worldPosition':xyz,'worldSize':size,'nativeCFrame':xyz+[1,0,0,0,1,0,0,0,1],'bounds':[xlo,-1,zlo,xhi,jtop,zhi],'bottom':-1,'top':jtop,'gateApertureBoundaryPositiveX':jxmax})
candidates=jambs+returns+bridges
synthetic=[{'path':q['id'],'class':'Part','cf':q['nativeCFrame'],'size':q['worldSize'],'collide':True,'query':True} for q in candidates]
newperim=[];unexpected=[]
free=[('Z',-267,-291.2336437702179,-251.233642578125),('X',-294,-251,-219)]
def subtract_allowed(gap,allowed):
 pending=[gap]
 for a,b in allowed:
  tmp=[]
  for l,h in pending:
   if a>l+.0001:tmp.append([l,min(a,h)])
   if b<h-.0001:tmp.append([max(b,l),h])
  pending=[[l,h] for l,h in tmp if h>l+.0001]
 return pending
for e in out['perimeterLines']:
 cov,_=coverage(structural+gateparts+synthetic,e['axis'],e['fixed'],5,e['first'],e['last'])
 missing=gaps(cov,e['first'],e['last']);allowed=[]
 for p in out['paidGates']:
  if p['axis']==e['axis'] and abs(p['fixed']-e['fixed'])<.001:allowed.append(p['desiredAperture'])
 for ax,fi,a,b in free:
  if ax==e['axis'] and abs(fi-e['fixed'])<.001:allowed.append([a,b])
 extras=[r for g in missing for r in subtract_allowed(g,allowed)]
 newperim.append({'region':e['region'],'axis':e['axis'],'fixed':e['fixed'],'first':e['first'],'last':e['last'],'remainingOpenings':missing,'allowedOpenings':allowed,'unexpectedRemainingOpenings':extras})
 if extras:unexpected.append(newperim[-1])
out.update({'jambProposals':jambs,'cornerReturnProposals':returns,'upperBridgeProposals':bridges,'postProposalPerimeterCoverage':newperim,'postProposalUnexpectedGaps':unexpected,'proposalPrimitiveEnvelopes':len(candidates),'proposalHasZeroUnintendedPerimeterOpeningsAtY5':not unexpected,'intentionalFreeForestCornerFaces':free,'prototypeNotes':'These are envelope specifications for contiguous studded multi-brick construction, not commands to create giant single Parts. The joins overlap adjacent source walls 0.25 along the boundary; no brick face may exceed the desired 24-wide,18-high gate lane. Gate jamb/upper bridge normal depth4 preserves SafeCartExterior24 studs normal away. Orthogonal return faces end exactly at the aperture negative edge.'})
(root/'GeometryClosureProposal.json').write_text(json.dumps(out,indent=2))
print('Unexpected',len(unexpected))
for q in candidates:print(q['id'],'pos',q['worldPosition'],'size',q['worldSize'])
