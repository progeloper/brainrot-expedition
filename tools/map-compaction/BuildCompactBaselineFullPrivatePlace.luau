-- Local Lune preparation only. Native test execution is a separate explicit operation.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local roblox=require('@lune/roblox')
local process=require('@lune/process')
local root=assert(process.args[1],'Correct repository root required')
local doc=root..'/docs/map-compaction'
local input=doc..'/snapshots/LiveDEV_Preimplementation_2026_10_11.rbxl'
local output=doc..'/private-tests/baseline'
local originalBinary=fs.readFile(input)
local originalSHA=serde.hash('sha256',originalBinary)
local manifest=serde.decode('json',fs.readFile(doc..'/LiveSourceManifest.json'))
local patches=serde.decode('json',fs.readFile(doc..'/source-patches/SourcePatchPayload.json'))
local sourceAuthority='b6c37961e3f9cfbbdb1d894299228068f5be2a8441f812b728426fd5046494b8'
local original=roblox.deserializePlace(originalBinary)
original.PlaceId=0
original.GameId=0
local function indexSources(gameObj)
 local sources={}
 for _,v in gameObj:GetDescendants() do
  if v:IsA('LuaSourceContainer') then
   local path=v:GetFullName();assert(sources[path]==nil,'Ambiguous captured source '..path);sources[path]=v
  end
 end
 return sources
end
local originals=indexSources(original)
local sourceCount=0;for _ in originals do sourceCount+=1 end;assert(sourceCount==356,'Actual saved source count drift')
local expected={};local changes={}
for _,row in manifest do
 local node=assert(originals[row.path],'Captured source missing '..row.path)
 local text=fs.readFile(doc..'/'..row.file)
 assert(node.ClassName==row.class and node.Name==row.name and node.Source==text and serde.hash('sha256',node.Source)==row.sha256,'Actual saved source differs from fresh capture '..row.path)
 expected[row.path]={path=row.path,class=row.class,name=row.name,source=text,sha256=row.sha256,kind='CapturedOriginal'}
end
assert(#manifest==356,'Captured source manifest incomplete')
-- Baseline comparison retains every captured source byte; no proposal substitutions.
local assets=assert(original:GetService('ReplicatedStorage'):FindFirstChild('StudioAssets'),'Actual source asset library missing')
local assetsBytes=roblox.serializeModel({assets})
local assetSHA=serde.hash('sha256',assetsBytes)
local assetCount=#assets:GetDescendants()+1
-- Only this deserialized owned copy is cleared; the original file is never rewritten.
original:GetService('Workspace'):ClearAllChildren()
original:GetService('ServerStorage'):ClearAllChildren()
original:GetService('Players'):ClearAllChildren()
local disabled={}
for _,v in original:GetDescendants() do
 if v:IsA('Script') or v:IsA('LocalScript') then v.Disabled=true;v.Enabled=false;table.insert(disabled,v:GetFullName()) end
end
table.sort(disabled);assert(#disabled==7,'Original Script/LocalScript count drift')
assert(serde.hash('sha256',roblox.serializeModel({assets}))==assetSHA,'StudioAssets mutated in preparation')
original:SetAttribute('CompactMapTestCopyOwner','CompactMap_V1')
original:SetAttribute('CompactMapTestSourceBundleSHA256',sourceAuthority)
original:SetAttribute('CompactMapTestCurrentOwnerSourcesVerified',false)
original:SetAttribute('BrainrotTestDiagnosticsDisabled',true)
original:SetAttribute('CompactMapTestOriginalRBXLSHA256',originalSHA)
local proof=roblox.Instance.new('Folder');proof.Name='CompactMapV1_PrivateSourceProof';proof.Parent=original:GetService('ServerStorage')
proof:SetAttribute('Owner','CompactMap_V1');proof:SetAttribute('OriginalSourceBundleSHA256',sourceAuthority)
proof:SetAttribute('OriginalRBXLSHA256',originalSHA);proof:SetAttribute('ExpectedSourceCount',356)
proof:SetAttribute('RetainedStudioAssetsSerializedSHA256',assetSHA)
local rows={};for _,row in expected do table.insert(rows,row) end;table.sort(rows,function(a,b)return a.path<b.path end)
local expectedJSON=serde.encode('json',{schemaVersion=1,owner='CompactMap_V1',originalSourceBundleSHA256=sourceAuthority,expectedSources=rows})
local folder=roblox.Instance.new('Folder');folder.Name='ExpectedSources_JSON_Chunks';folder.Parent=proof
local cursor,count=1,0
while cursor<=#expectedJSON do
 local last=math.min(cursor+59999,#expectedJSON)
 while last<#expectedJSON and string.byte(expectedJSON,last+1)>=128 and string.byte(expectedJSON,last+1)<192 do last-=1 end
 count+=1;local v=roblox.Instance.new('StringValue');v.Name=string.format('Chunk_%04d',count);v.Value=expectedJSON:sub(cursor,last);v.Parent=folder;cursor=last+1
end
folder:SetAttribute('Bytes',#expectedJSON);folder:SetAttribute('ChunkCount',count);folder:SetAttribute('SHA256',serde.hash('sha256',expectedJSON))
local function verifyCopy(gameObj,scope)
 local ownerProof=gameObj:GetService('ServerStorage'):FindFirstChild('CompactMapV1_PrivateSourceProof')
 assert(ownerProof and ownerProof:GetAttribute('Owner')=='CompactMap_V1' and ownerProof:GetAttribute('SpecScope')==scope,'Private persisted guard state drift')
 assert(#gameObj:GetService('Workspace'):GetChildren()==0 and #gameObj:GetService('Players'):GetChildren()==0,'Private test world is not blank')
 local sources=indexSources(gameObj);local n=0
 for path,row in expected do local node=assert(sources[path],'Roundtrip source lost '..path);assert(node.Source==row.source and node.ClassName==row.class and node.Name==row.name,'Roundtrip source drift '..path);n+=1 end
 local actual=0;for _ in sources do actual+=1 end;assert(n==356 and actual==356,'Roundtrip source count mismatch')
 for _,v in gameObj:GetDescendants() do if v:IsA('Script')or v:IsA('LocalScript')then assert(v.Disabled==true,'Automatic script enabled') end end
 local a=gameObj:GetService('ReplicatedStorage').StudioAssets
 assert(#a:GetDescendants()+1==assetCount and serde.hash('sha256',roblox.serializeModel({a}))==assetSHA,'StudioAssets serialized content drift after roundtrip')
 local f=gameObj:GetService('ServerStorage').CompactMapV1_PrivateSourceProof.ExpectedSources_JSON_Chunks
 local text={};for i=1,count do text[i]=f:FindFirstChild(string.format('Chunk_%04d',i)).Value end
 assert(table.concat(text)==expectedJSON,'Persisted expected source proof drift')
 return {exactSources=n,disabledAutomaticScripts=#disabled,retainedStudioAssetsInstances=assetCount,assetSerializedSHA256=assetSHA,expectedProofBytes=#expectedJSON,expectedProofChunks=count}
end
fs.writeDir(output)
local results={schemaVersion=1,status='PrivateBaselineNativeCopyPrepared',originalFile=input,originalFileSHA256=originalSHA,originalFileUnchanged=true,originalSourceCount=356,substitutions=changes,newUtilityCount=0,sourceAuthority=sourceAuthority,scope='Local serialization/roundtrip validation only; native tests not executed',nativeTestExecution='NotRun',studioCalls=0,originalWorldOrSourceWrites=0,removedFromOwnedCopy={'All original Workspace children including terrain/map/baseplate/camera','ServerStorage runtime/history/backups/templates','Players children'},disabledAutomaticSources=disabled,retainedStudioAssetsSerializedSHA256=assetSHA,serializer='Official Lune0.10.5 @lune/roblox',identifierGuard='DataModel PlaceId/GameId and root attributes are not serialized by Lune; native entrypoint must prove actual PlaceId0 before setting private test attrs from persisted proof.',serializerLimitation='Deserializer warns on unsupported original Terrain.VoxelGridAssetContentMap. Original terrain is deliberately excluded from blank private world; no native terrain preservation claim.',copies={}}
for _,scope in {'Full'} do
 original:SetAttribute('CompactMapTestSpecScope',scope);proof:SetAttribute('SpecScope',scope)
 local bytes=roblox.serializePlace(original)
 local copy=roblox.deserializePlace(bytes);local validation=verifyCopy(copy,scope)
 local path=output..'/CompactMap_Private_Baseline_'..scope..'.rbxl';fs.writeFile(path,bytes)
 results.copies[scope]={file=path,sha256=serde.hash('sha256',bytes),bytes=#bytes,roundtrip=validation}
end
assert(fs.readFile(input)==originalBinary,'Original saved place changed')
fs.writeFile(output..'/PrivateBaselineFullPreparation.json',serde.encode('json',results,true))
print(serde.encode('json',{status=results.status,copies=results.copies},true))
