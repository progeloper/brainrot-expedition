import json,pathlib
p=pathlib.Path('/private/tmp/GateGapAudit')
live=json.loads((p/'Live.json').read_text()); plan=json.loads((p/'GeometryClosureProposal.json').read_text())
data={
 'perimeters':[{k:e[k] for k in ('region','axis','fixed','inward','first','last')} for e in plan['perimeterLines']],
 'gates':[{k:e[k] for k in ('gate','axis','fixed','center','actualStructuralOpening','nativeThresholdCF','closureTop')} for e in plan['paidGates']],
 'free':plan['intentionalFreeForestCornerFaces'],
 'proposals':[{k:e[k] for k in ('id','kind','worldPosition','worldSize')} for key in ('jambProposals','cornerReturnProposals','upperBridgeProposals') for e in plan[key]],
 'existingProxies':[e['path'] for e in live['geometry'] if e['class']=='Part' and e['collide'] and e['query'] and ('EV2_Run_' in e['path'] or '.Gate_' in e['path'] or '.X_Camp_Exterior_' in e['path'])],
 'floorRectangles':[]}
for e in live['geometry']:
 if isinstance(e['attrs'],dict) and e['attrs'].get('LayoutRole')=='Floor' and e['attrs'].get('GeneratedBy')=='CreateBasicMap_v1':
  c=e['cf'];s=e['size'];data['floorRectangles'].append({'region':e['path'].split('.')[2],'x0':c[0]-s[0]/2,'x1':c[0]+s[0]/2,'z0':c[2]-s[2]/2,'z1':c[2]+s[2]/2})
(p/'NativeBoundaryClosureAudit.Input.json').write_text(json.dumps(data,indent=2))
code=(p/'NativeBoundaryClosureAudit.Template.luau').read_text().replace('__BAKED_INPUT_JSON__',json.dumps(data,separators=(',',':')))
(p/'NativeBoundaryClosureAudit.luau').write_text(code)
print('Wrote',len(code),'bytes; existing collision proxies',len(data['existingProxies']),'; perimeter lines',len(data['perimeters']))
