#!/usr/bin/env python3
"""Build source-exact isolated adapters; never writes a live Studio source."""
import hashlib,json,pathlib,re,argparse
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
PATHS={
 'Config':'ReplicatedStorage.Shared.Config.BaseLayoutConfig',
 'Scale':'ReplicatedStorage.Shared.Utility.BrainrotVisualScale',
 'Material':'ReplicatedStorage.Shared.Utility.MapArtStaticMaterialPolicy',
 'Catalog':'ReplicatedStorage.Shared.Config.BrainrotCatalog',
 'Rarities':'ReplicatedStorage.Shared.Config.Rarities',
 'Money':'ReplicatedStorage.Shared.Utility.CurrencyDenomination',
 'Progression':'ReplicatedStorage.Shared.Config.WorldProgression',
 'Income':'ServerScriptService.Server.Systems.BaseIncomePlaqueSystem',
 'Storage':'ServerScriptService.Server.Systems.BaseStorageSystem',
 'Cargo':'ServerScriptService.Server.Services.CartCargoService',
}
def lua_string(s):
 n=0
 while ']'+('='*n)+']' in s:n+=1
 return '['+'='*n+'['+s+']'+'='*n+']'
def extract(s,name):
 pattern=r'^(?:local )?function '+re.escape(name)+r'\b[^\n]*'
 matches=list(re.finditer(pattern,s,re.M))
 if len(matches)!=1:raise ValueError('Expected one function '+name)
 start=matches[0].start();end=re.search(r'^end[ \t]*$',s[matches[0].end():],re.M)
 if end is None:raise ValueError('No column-zero function end '+name)
 return s[start:matches[0].end()+end.end()]
def build(root=ROOT):
 capture=json.loads((root/'docs/map-compaction/snapshots/AllLiveSources_Before.json').read_text())
 by_path={r['path']:r for r in capture};rows={k:by_path[p] for k,p in PATHS.items()}
 for k,row in rows.items():
  assert row['source']==(root/'docs/map-compaction/live-sources'/pathlib.Path(*row['path'].split('.'))).with_suffix('.lua').read_text()
 income_names=['platformIdFromPart','baseRootCFrame','ensureFolder','ensurePart','configureStructuralPart','platformTopLocalY','entranceSign','captureStructuralStyle','legacyWall','removeLegacyWalls','clearManagedPillars','createPillar','createPillarsAlongEdge','createPerimeterPillars','ensureInterior','setMarkerFacing','positionPlatforms']
 fragments=[];sources={k:r['source'] for k,r in rows.items()}
 for key,names in [('Cargo',['getBrainrotTemplate','getCargoVisualRoot','CartCargoService:CreateItemVisual']),('Storage',['placeDisplayAtSlot']),('Income',income_names)]:
  for name in names:
   text=extract(sources[key],name);fragments.append({'owner':PATHS[key],'function':name,'sha256':hashlib.sha256(text.encode()).hexdigest(),'bytes':len(text.encode()),'firstLine':sources[key][:sources[key].index(text)].count('\n')+1})
 income=sources['Income'];start=income.index('local PLAQUE_TAG =');end=income.index('\nlocal BaseIncomePlaqueSystem =')
 constants=income[start:end]
 structural=re.search(r'^type StructuralStyle = \{.*?^\}',income,re.M|re.S).group(0)
 body='local Config, StaticMaterial = deps.Config, deps.Material\n'+constants+'\n'+structural+'\n'+'\n\n'.join(extract(income,n) for n in income_names)
 body+='\nreturn {Apply=function(base,slots) local root=baseRootCFrame(base); local placements,floorY=positionPlatforms(root,slots); local resolved=ensureInterior(base,root,floorY); return root,placements,resolved end}\n'
 storage='local BrainrotVisualScale=deps.Scale\nlocal PLACEMENT_GAP = 0.05\n'+extract(sources['Storage'],'placeDisplayAtSlot')+'\nreturn placeDisplayAtSlot\n'
 assert re.search(r'^local PLACEMENT_GAP = 0.05$',sources['Storage'],re.M)
 cargo='local BrainrotCatalog, BrainrotVisualScale=deps.Catalog,deps.Scale\nlocal ReplicatedStorage=game:GetService("ReplicatedStorage")\nlocal RunService=game:GetService("RunService")\nlocal CollectionService=game:GetService("CollectionService")\nlocal Trace={Emit=function(...) end}\nlocal CartCargoService={}\n'+'\n\n'.join(extract(sources['Cargo'],n) for n in ['getBrainrotTemplate','getCargoVisualRoot','CartCargoService:CreateItemVisual'])+'\nreturn CartCargoService\n'
 evidence=[{'key':k,'path':r['path'],'source':r['source'],'sha256':hashlib.sha256(r['source'].encode()).hexdigest()} for k,r in rows.items()]
 code='-- Generated from the fresh native Edit source capture. No live require cache or Source writes.\nlocal E={}\n'
 for row in evidence:code+='E['+json.dumps(row['key'])+']={path='+json.dumps(row['path'])+',sha256='+json.dumps(row['sha256'])+',source='+lua_string(row['source'])+'}\n'
 code+='''local function resolve(path)
 local node=game
 for segment in string.gmatch(path,"[^.]+") do node=assert(node:FindFirstChild(segment),"Missing source "..path) end
 return node
end
local API={Evidence=E}
function API.CheckSources()
 local checked,editorReadable=0,0
 local SES=game:GetService("ScriptEditorService")
 for _,r in pairs(E) do
  local node=resolve(r.path)
  assert(node:IsA("LuaSourceContainer"),"Wrong source class "..r.path)
  assert(node.Source==r.source,"Captured source changed "..r.path)
  local ok,editor=pcall(function()return SES:GetEditorSource(node)end)
  if ok then editorReadable+=1;assert(editor==r.source,"Editor buffer changed "..r.path)end
  checked+=1
 end
 return {exactSourceBytesPassed=true,checkedSources=checked,editorSourcesReadable=editorReadable}
end
function API.Create()
 API.CheckSources()
 local byInstance,cache={},{}
 for key,r in pairs(E) do byInstance[resolve(r.path)]=key end
 local function loadCaptured(key)
  if cache[key] then return cache[key]end
  assert(key~="Income"and key~="Storage"and key~="Cargo","Gameplay graphs may not be required")
  local chunk=assert(loadstring(E[key].source,"@Captured/"..E[key].path))
  local env=setmetatable({script=resolve(E[key].path),require=function(instance)
   local dependency=assert(byInstance[instance],"Uncaptured dependency")
   return loadCaptured(dependency)
  end},{__index=getfenv(0)})
  setfenv(chunk,env)
  local value=chunk();cache[key]=value;return value
 end
 local deps={Config=loadCaptured("Config"),Scale=loadCaptured("Scale"),Material=loadCaptured("Material"),Catalog=loadCaptured("Catalog")}
'''
 for label,body in [('Layout',body),('Place',storage),('Factory',cargo)]:code+=' deps.'+label+'=assert(loadstring('+lua_string('return function(deps)\n'+body+'\nend')+',"@IsolatedCaptured/'+label+'"))()(deps)\n'
 code+=' return deps\nend\nreturn API\n'
 out=root/'tools/map-compaction/RuntimeBaseFitSourceAdapter.luau';out.write_text(code)
 manifest={'schemaVersion':1,'status':'SourcePreparedNativeExecutionPending','sourceBundleSHA256':json.loads((root/'docs/map-compaction/BeforeManifest.json').read_text())['sourceBundleSHA256'],'sources':[{k:v for k,v in r.items() if k!='source'} for r in evidence],'exactFunctionFragments':fragments,'excludedSideEffects':['Trace.Emit diagnostics replaced by no-op; no geometry/scaling/placement expression changed','No gameplay Init/Start/BuildBase/claim/accrual/profile methods called'],'adapterSHA256':hashlib.sha256(code.encode()).hexdigest()}
 (root/'docs/map-compaction/RuntimeBaseFitSourceManifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 harness=root/'tools/map-compaction/RuntimeBaseFit.luau'
 if harness.exists():
  baseline=json.loads((root/'docs/map-compaction/BeforeManifest.json').read_text())
  prelude='local Baseline=table.clone(assert(shared.CompactMapBeforeManifest,"Fresh native baseline required"))\n'
  for field in ['baselineManagedContentSHA256','protectedAssetsContentSHA256','sourceBundleSHA256']:
   prelude+='Baseline.'+field+'='+json.dumps(baseline[field])+'\n'
  run=prelude+'local Adapter=assert(loadstring('+lua_string(code)+',"@RuntimeBaseFitSourceAdapter"))()\nlocal Audit=assert(loadstring('+lua_string(harness.read_text())+',"@RuntimeBaseFit"))()\nreturn Audit.Audit({Adapter=Adapter,Baseline=Baseline})\n'
  (root/'tools/map-compaction/RuntimeBaseFitCurrent.run.luau').write_text(run)
 print(json.dumps({'sources':len(evidence),'fragments':len(fragments),'adapterBytes':len(code.encode()),'adapterSHA256':manifest['adapterSHA256'],'nativeExecution':'NotRun'}))
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=pathlib.Path,default=ROOT);args=parser.parse_args();build(args.root)
