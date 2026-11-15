#!/usr/bin/env python3
"""Compose native source-byte preflight + the reviewed private-only test runner. No Studio calls."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/map-compaction';OUT=DOC/'private-tests'
runner=ROOT/'tools/map-compaction/CompactBaseLayoutRunPrivateTests.luau'
source=runner.read_text();runner_sha=hashlib.sha256(source.encode()).hexdigest()
assert runner_sha=='973c79a621d14034cd56a7325986baafc5b614f944cd94e51292f34f9220508b','Reviewed private runner drift'
guard='''-- Exact native byte preflight for an owned, blank, local test-copy place only.
do
 local run=game:GetService('RunService')
 assert(run:IsStudio() and not run:IsRunning() and game.PlaceId==0,'Private source guard requires actual native unsaved PlaceId 0 Edit')
 assert(#game:GetService('Players'):GetPlayers()==0 and workspace:FindFirstChild('MapBlockout')==nil and workspace:FindFirstChild('Runtime')==nil,'Private blank world required')
 local storage=game:GetService('ServerStorage')
 local proof=assert(storage:FindFirstChild('CompactMapV1_PrivateSourceProof'),'Private source proof missing')
 assert(proof:IsA('Folder') and proof:GetAttribute('Owner')=='CompactMap_V1' and proof:GetAttribute('OriginalSourceBundleSHA256')=='b6c37961e3f9cfbbdb1d894299228068f5be2a8441f812b728426fd5046494b8','Private copy owner/source authority mismatch')
 local scope=proof:GetAttribute('SpecScope');assert(scope=='Relevant' or scope=='Full','Private scope missing')
 local folder=assert(proof:FindFirstChild('ExpectedSources_JSON_Chunks'));local count=folder:GetAttribute('ChunkCount');local bytes=folder:GetAttribute('Bytes')
 assert(folder:IsA('Folder') and type(count)=='number' and count%1==0 and count>0 and count<=128 and type(bytes)=='number' and bytes>0 and bytes<=8000000,'Bounded persisted source proof required')
 local chunks={};assert(#folder:GetChildren()==count,'Source-proof chunk count mismatch')
 for i=1,count do local value=assert(folder:FindFirstChild(string.format('Chunk_%04d',i)));assert(value:IsA('StringValue') and #value.Value<=60000,'Source-proof chunk invalid');chunks[i]=value.Value end
 local text=table.concat(chunks);assert(#text==bytes,'Source-proof byte length mismatch')
 local raw=game:GetService('HttpService'):JSONDecode(text)
 assert(raw.schemaVersion==1 and raw.owner=='CompactMap_V1' and raw.originalSourceBundleSHA256==proof:GetAttribute('OriginalSourceBundleSHA256'),'Source-proof schema mismatch')
 assert(#raw.expectedSources==357 and proof:GetAttribute('ExpectedSourceCount')==357,'All 357 source records required')
 local actual={};local actualCount,disabled=0,0
 for _,node in game:GetDescendants() do
  if node:IsA('LuaSourceContainer') then local path=node:GetFullName();assert(actual[path]==nil,'Ambiguous private source path');actual[path]=node;actualCount+=1 end
  if node:IsA('Script') or node:IsA('LocalScript') then assert(not node.Enabled,'Automatic private source enabled '..node:GetFullName());disabled+=1 end
 end
 assert(actualCount==357 and disabled==7,'Private source topology changed')
 local seen,changed={},0;local sourceHashes={}
 for _,row in raw.expectedSources do
  assert(type(row.path)=='string' and not seen[row.path] and type(row.sha256)=='string' and #row.sha256==64 and row.sha256:match('^[0-9a-f]+$'),'Source record identity invalid');seen[row.path]=true
  local node=assert(actual[row.path],'Native private source missing '..row.path)
  assert(node.ClassName==row.class and node.Name==row.name,'Native private source class/name drift '..row.path)
  local readable,current=pcall(function()return node.Source end)
  assert(readable,'Native task cannot read exact Source; source proof remains unverified: '..row.path)
  assert(current==row.source,'Native private source bytes drifted '..row.path)
  if row.kind=='ReviewedProposal' then changed+=1 end
  table.insert(sourceHashes,{path=row.path,sha256=row.sha256,bytes=#current,kind=row.kind,exactNativeBytesPassed=true})
 end
 assert(changed==5,'Exact five native proposal substitutions required')
 game:SetAttribute('CompactMapTestCopyOwner','CompactMap_V1')
 game:SetAttribute('CompactMapTestSourceBundleSHA256',raw.originalSourceBundleSHA256)
 game:SetAttribute('CompactMapTestCurrentOwnerSourcesVerified',true)
 game:SetAttribute('BrainrotTestDiagnosticsDisabled',true)
 game:SetAttribute('CompactMapTestSpecScope',scope)
 local output=Instance.new('StringValue');output.Name='CompactMapV1_PrivateNativeSourceProof';output:SetAttribute('Owner','CompactMap_V1')
 output.Value=game:GetService('HttpService'):JSONEncode({schemaVersion=1,status='NativeExactSourceBytesPassed',originalSourceBundleSHA256=raw.originalSourceBundleSHA256,scope=scope,exactSources=actualCount,approvedSubstitutions=changed,newUtilityCount=1,disabledAutomaticSources=disabled,sourceHashes=sourceHashes,hashMethod='Recorded official Lune SHA256 and exact native byte comparison; no fabricated runtime SHA calculation',privatePlaceId=game.PlaceId,ordinaryDEVWrites=0})
 output.Parent=storage
 print('[COMPACT_PRIVATE_SOURCE_GUARD] passed 357 originals/proposals; scope='..scope)
end
'''
OUT.mkdir(parents=True,exist_ok=True)
p=OUT/'RunCompactPrivateTests.native.luau';p.write_text(guard+'\n'+source)
manifest={'schemaVersion':1,'status':'NativeEntrypointPrepared','entrypoint':str(p.relative_to(ROOT)),'entrypointSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'runner':str(runner.relative_to(ROOT)),'runnerSHA256':runner_sha,'guard':'Actual native PlaceId 0/Edit/blank world; all 357 exact native Source byte checks; seven automatic sources disabled; set private attrs only after pass.','hashProvenance':'Persisted SHA256 from official Lune, proven by full native exact byte comparison','nativeExecution':'NotRun','studioCalls':0}
(OUT/'NativeEntrypointManifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
