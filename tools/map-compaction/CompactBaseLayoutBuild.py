#!/usr/bin/env python3
"""Build owned compaction native fixtures from frozen source adapters; no live source edits."""
import argparse,pathlib,json,hashlib,importlib.util
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def quote(s):
 n=0
 while ']'+('='*n)+']'in s:n+=1
 return '['+'='*n+'['+s+']'+'='*n+']'
def function(s,name):
 import re
 m=re.search(r'^local function '+re.escape(name)+r'\b',s,re.M);assert m,name
 e=re.search(r'^end[ \t]*$',s[m.end():],re.M);assert e,name
 return s[m.start():m.end()+e.end()]
def build(root):
 tool=root/'tools/map-compaction';doc=root/'docs/map-compaction';baseline=json.loads((doc/'BeforeManifest.json').read_text())
 old=(tool/'RuntimeBaseFit.luau').read_text();start=old.index('local BASE_PROPERTIES =');end=old.index('\nlocal function near',start);constants=old[start:end]
 guard='local Run=game:GetService("RunService")\nlocal CS=game:GetService("CollectionService")\nlocal Http=game:GetService("HttpService")\nlocal SS=game:GetService("ServerStorage")\n'+constants+'\n'
 guard+='\n\n'.join(function(old,name)for name in ['near','encoded','indexedKeys','snapshot','assertPreserved','guardBaseline'])
 guard+='''
local G={}
function G.Run(options,operation)
 assert(Run:IsStudio()and not Run:IsRunning(),"Native compact fixture requires Edit")
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,"Wrong DEV")
 local adapter=assert(options.Adapter,"Fresh adapter required");adapter.CheckSources()
 local roots={assert(workspace:FindFirstChild("MapBlockout")),assert(game.ReplicatedStorage:FindFirstChild("StudioAssets"))}
 local checked=guardBaseline(assert(options.Baseline,"Fresh baseline required"),roots)
 local before=snapshot(roots)
 local stage=Instance.new("Folder");stage.Name="CompactMapV1_BaseFixture_"..Http:GenerateGUID(false);stage:SetAttribute("Owner","CompactMap_V1_BaseFixture");stage.Parent=SS
 local start=os.clock()
 local ok,result=xpcall(function()return operation(stage,adapter.Create())end,debug.traceback)
 stage:Destroy()
 local unchanged=assertPreserved(before,roots);adapter.CheckSources()
 assert(ok,"Native fixture failed; owned stage removed and originals unchanged: "..tostring(result))
 result.cleanup={stageRemoved=stage.Parent==nil,originalInstancesUnchanged=unchanged,originalSourcesUnchanged=true};result.baselineNodesChecked=checked;result.elapsedSeconds=os.clock()-start;result.nativeExecutionPassed=true
 return result
end
return G
'''
 (tool/'CompactBaseLayoutFixtureGuard.luau').write_text(guard)
 prelude='local Baseline=table.clone(assert(shared.CompactMapBeforeManifest,"Fresh root baseline required"))\n'
 for field in ['baselineManagedContentSHA256','protectedAssetsContentSHA256','sourceBundleSHA256']:prelude+='Baseline.'+field+'='+json.dumps(baseline[field])+'\n'
 prelude+='local Adapter=assert(loadstring('+quote((tool/'RuntimeBaseFitSourceAdapter.luau').read_text())+',"@FreshCapturedSources"))()\nlocal Guard=assert(loadstring('+quote(guard)+',"@CompactBaseFixtureGuard"))()\n'
 cargo=(tool/'CompactBaseLayoutNativeCargo.luau').read_text();run=prelude+'local Cargo=assert(loadstring('+quote(cargo)+',"@CompactBaseNativeCargo"))()\nreturn Guard.Run({Adapter=Adapter,Baseline=Baseline},Cargo.Measure)\n'
 (tool/'CompactBaseLayoutNativeCargo.run.luau').write_text(run)
 print(json.dumps({'cargoRunnerBytes':len(run.encode()),'cargoRunnerSHA256':hashlib.sha256(run.encode()).hexdigest(),'nativeExecution':'PreparedOnly'}))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,default=ROOT);args=p.parse_args();build(args.root)
