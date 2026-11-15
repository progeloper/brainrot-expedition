#!/usr/bin/env python3
import json,hashlib,pathlib,importlib.util,re
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def sh(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def q(s):
 n=0
 while ']'+('='*n)+']'in s:n+=1
 return '['+'='*n+'['+s+']'+'='*n+']'
def extract(s,name):
 m=re.search(r'^local function '+re.escape(name)+r'\b',s,re.M);assert m,name;e=re.search(r'^end[ \t]*$',s[m.end():],re.M);assert e,name;return s[m.start():m.end()+e.end()]
def build():
 t=ROOT/'tools/map-compaction';d=ROOT/'docs/map-compaction';proposal=d/'source-patches/proposals';incp=proposal/'ServerScriptService/Server/Systems/BaseIncomePlaqueSystem.lua';confp=proposal/'ReplicatedStorage/Shared/Config/BaseLayoutConfig.lua';geop=proposal/'ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua'
 inc=incp.read_text();conf=confp.read_text();geo=geop.read_text();evidence={'owner':'Fresh generated source proposals, no live replacements','sources':[{ 'path':str(p),'sha256':sh(p),'bytes':p.stat().st_size}for p in [incp,confp,geop]],'excludedSideEffects':['Full Init/BuildBase/claim/profile/economy require graph excluded','configurePlaque exact geometry prefix only; no claim revision, snapshot, touch binding or tags','Config require line replaced only by isolated validated geometry dependency injection'],'nativeExecution':'PreparedOnly'}
 constants=inc[inc.index('local PLAQUE_TAG ='):inc.index('\nlocal BaseIncomePlaqueSystem =')];structural=re.search(r'^type StructuralStyle = \{.*?^\}',inc,re.M|re.S).group(0)
 names=['platformIdFromPart','baseRootCFrame','ensureFolder','ensurePart','configureStructuralPart','platformTopLocalY','entranceSign','captureStructuralStyle','legacyWall','removeLegacyWalls','clearManagedPillars','createPillar','createPillarsAlongEdge','createPerimeterPillars','ensureInterior','setMarkerFacing','positionPlatforms']
 body='local Config,StaticMaterial=deps.Config,deps.Material\n'+constants+'\n'+structural+'\n'+'\n\n'.join(extract(inc,n)for n in names)
 plaque=extract(inc,'configurePlaque');plaque=plaque[:plaque.index('\n\tif plaque:GetAttribute("ClaimRevision")')]+ '\n return claimSensorCFrame\nend'
 body+='\n'+extract(inc,'getPlaqueName')+'\n'+plaque+'\nreturn {Apply=function(base,slots)local root=baseRootCFrame(base);local geometry=assert(Config.GetGeometry(base));local placements,floorY=positionPlatforms(root,slots,geometry);return root,placements,ensureInterior(base,root,floorY,geometry)end,ConfigurePlaqueGeometry=configurePlaque}\n'
 lines=conf.splitlines();requireline='local CompactMapGeometry = require(game:GetService("ReplicatedStorage").Shared.Utility.CompactMapGeometry)';assert lines.count(requireline)==1;conf=conf.replace(requireline,'local CompactMapGeometry = injectedGeometry')
 code='local P={}\nfunction P.Create(deps)\nlocal geometry=assert(loadstring('+q(geo)+',"@ProposedCompactGeometry"))()\nlocal confChunk=assert(loadstring('+q(conf)+',"@ProposedBaseLayoutConfig"))\nsetfenv(confChunk,setmetatable({injectedGeometry=geometry},{__index=getfenv(0)}))\nlocal config=confChunk();local localDeps={Config=config,Material=deps.Material}\nlocal layout=assert(loadstring('+q('return function(deps)\n'+body+'\nend')+',"@ProposedBaseOwnerGeometry"))()(localDeps)\nreturn{Config=config,Geometry=geometry,Layout=layout,PlaqueDepth=2.25}\nend\nreturn P\n'
 (t/'CompactBaseLayoutProposalAdapter.luau').write_text(code)
 baseline=json.loads((d/'BeforeManifest.json').read_text());pre='local Baseline=table.clone(assert(shared.CompactMapBeforeManifest,"Fresh root baseline required"))\n'
 for field in ['baselineManagedContentSHA256','protectedAssetsContentSHA256','sourceBundleSHA256']:pre+='Baseline.'+field+'='+json.dumps(baseline[field])+'\n'
 pre+='local Http=game:GetService("HttpService")\n'
 for name,path in [('Adapter',t/'RuntimeBaseFitSourceAdapter.luau'),('Guard',t/'CompactBaseLayoutFixtureGuard.luau'),('Proposal',t/'CompactBaseLayoutProposalAdapter.luau'),('Fit',t/'CompactBaseLayoutNativeFit.luau')]:pre+='local '+name+'=assert(loadstring('+q(path.read_text())+',"@'+name+'"))()\n'
 data={name:json.loads(path.read_text())for name,path in [('Candidates',d/'CompactBaseLayoutCandidates.json'),('RuntimeGeometry',d/'CompactBaseLayoutRuntimeGeometry.Prepared.json'),('PartLocals',d/'CompactBaseLayoutPartLocals_085.Prepared.json'),('Cargo',d/'CompactBaseLayoutNativeCargo.json')]}
 for name,value in data.items():pre+='local '+name+'=Http:JSONDecode('+q(json.dumps(value,separators=(',',':')))+')\n'
 pre+='local Evidence=Http:JSONDecode('+q(json.dumps(evidence,separators=(',',':')))+')\nlocal CargoEvidence='+json.dumps(str(d/'CompactBaseLayoutNativeCargo.json'))+'\nreturn Guard.Run({Adapter=Adapter,Baseline=Baseline},function(stage,deps)local chosen;for _,c in Candidates.candidates do if c.b==.85 then chosen=c;break end end;return Fit.Audit(stage,deps,{Candidate=assert(chosen,"Missing .85 candidate"),RuntimeGeometry=RuntimeGeometry,PartLocals=PartLocals,Cargo=Cargo,CargoEvidence=CargoEvidence,Proposed=Proposal.Create(deps),ProposalEvidence=Evidence})end)\n'
 run=t/'CompactBaseLayoutNativeFit.run.luau';run.write_text(pre);evidence['runnerSHA256']=sh(run);evidence['runnerBytes']=run.stat().st_size;evidence['fixtureSHA256']=sh(t/'CompactBaseLayoutNativeFit.luau');(d/'CompactBaseLayoutNativeFit.SourceManifest.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'runner':str(run),'bytes':run.stat().st_size,'sha256':sh(run),'status':'PreparedOnly'}))
if __name__=='__main__':build()
