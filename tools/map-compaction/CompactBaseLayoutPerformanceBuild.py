#!/usr/bin/env python3
import json,hashlib,pathlib
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def q(s):
 n=0
 while ']'+('='*n)+']'in s:n+=1
 return '['+'='*n+'['+s+']'+'='*n+']'
def sh(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 t=ROOT/'tools/map-compaction';d=ROOT/'docs/map-compaction';proposal=d/'source-patches/proposals';conf=proposal/'ReplicatedStorage/Shared/Config/BaseLayoutConfig.lua';income=proposal/'ServerScriptService/Server/Systems/BaseIncomePlaqueSystem.lua';guard=(t/'CompactBaseLayoutFixtureGuard.luau').read_text().replace('return G\n','G.Snapshot=snapshot\nG.AssertPreserved=assertPreserved\nreturn G\n');adapter=(t/'RuntimeBaseFitSourceAdapter.luau').read_text()
 helper=(t/'CompactBaseLayoutPerformance.luau').read_text();proposed=(t/'CompactBaseLayoutProposalAdapter.luau').read_text();raw=(d/'CompactBaseLayoutRuntimeGeometry.NativeValidated.json').read_text()
 outputs=[]
 for mode in ['Before','After']:
  a=adapter
  if mode=='After':
   expected={'Config':conf.read_text(),'Income':income.read_text()};prefix='local ExpectedCurrent={'+','.join(k+'='+q(v)for k,v in expected.items())+'}\n';a=prefix+a
   a=a.replace('for _,r in pairs(E) do','for key,r in pairs(E) do').replace('node.Source==r.source','node.Source==(ExpectedCurrent[key]or r.source)').replace('editor==r.source','editor==(ExpectedCurrent[key]or r.source)')
  pre='local Http=game:GetService("HttpService")\n'
  for name,code in [('Adapter',a),('Guard',guard),('Performance',helper),('Proposed',proposed)]:pre+='local '+name+'=assert(loadstring('+q(code)+',"@'+name+'"))()\n'
  if mode=='After':
   geop=proposal/'ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua'
   pre+='local OriginalCheck=Adapter.CheckSources\nfunction Adapter.CheckSources()local result=OriginalCheck();local node=assert(game.ReplicatedStorage.Shared.Utility:FindFirstChild("CompactMapGeometry"),"Installed geometry owner missing");assert(node.Source=='+q(geop.read_text())+',"Installed geometry owner source changed");return result end\n'
  evidence={'mode':mode,'capturedOriginalAdapterSHA256':sh(t/'RuntimeBaseFitSourceAdapter.luau'),'canonicalScaleAndFactory':'Exact immutable captured factory/scale/place sources; live byte guards before and after clones','ownerGeometry':'Captured exact current old owner'if mode=='Before'else'Exact reviewed proposal owner after live-source byte guard','proposals':[{'path':str(p),'sha256':sh(p)}for p in [conf,income,proposal/'ReplicatedStorage/Shared/Utility/CompactMapGeometry.lua']],'fixtureHelperSHA256':sh(t/'CompactBaseLayoutPerformance.luau'),'preparationOnly':True}
  pre+='return Performance.Capture({Mode='+json.dumps(mode)+',Adapter=Adapter,Guard=Guard,Proposed=Proposed,RuntimeGeometryText='+q(raw)+',SourceEvidence=Http:JSONDecode('+q(json.dumps(evidence,separators=(',',':')))+'),WarmSeconds=2,SampleIntervalSeconds=1/60})\n';p=t/f'CompactBaseLayoutPerformance{mode}.run.luau';p.write_text(pre);outputs.append({'mode':mode,'path':str(p),'sha256':sh(p),'bytes':p.stat().st_size})
 (d/'CompactBaseLayoutPerformance.Prepared.json').write_text(json.dumps({'schemaVersion':1,'status':'PreparedOnlyNoNativePerformanceClaim','fixture':'12 controlled base clones, 144 canonical released displays, old owner before/final proposal after','warmSeconds':2,'samplesPerView':120,'views':5,'StatsDoc':'https://create.roblox.com/docs/reference/engine/classes/Stats','availableMetricsRequired':['FrameTime','RenderCPUFrameTime','RenderGPUFrameTime','PhysicsStepTime','TotalMemoryMb'],'rows':outputs,'ordinaryGameplayMobileMultiplayer':'Unverified','samplingLimitation':'Wall-clock yielded native Stats samples, not unique native scope frames'},indent=2)+'\n');print(json.dumps(outputs))
if __name__=='__main__':main()
