--!nocheck
-- Identity-preserving, baseline-driven Edit transaction. No gameplay bootstrap/data calls.
local API={};local H=game:GetService('HttpService');local SS=game:GetService('ServerStorage');local CS=game:GetService('CollectionService')
local MIGRATION='CompactMap_V1';local BASELINE='3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310'
local function decode(v)
 if type(v)~='table' or not v.type then return v end
 if v.type=='CFrame'then return CFrame.new(table.unpack(v.value))end
 if v.type=='Vector3' then return Vector3.new(table.unpack(v.value))end
 if v.type=='Vector2' then return Vector2.new(table.unpack(v.value))end
 error('Unsupported attribute kind '..tostring(v.type))
end
local function persistJSON(journal,name,text,hash)
 -- Exact review inputs survive save/reopen; no shared-table cache is needed to recover them.
 local folder=Instance.new('Folder');folder.Name=name;folder:SetAttribute('MigrationId',MIGRATION);folder:SetAttribute('DesiredHash',hash);folder:SetAttribute('Bytes',#text);folder.Parent=journal
 local cursor,count=1,0
 while cursor<=#text do
  local last=math.min(cursor+59999,#text)
  -- Keep each StringValue valid UTF-8 without changing the concatenated JSON bytes.
  while last<#text and string.byte(text,last+1)>=128 and string.byte(text,last+1)<192 do last-=1 end
  assert(last>=cursor,'Invalid JSON chunk boundary')
  count+=1;local value=Instance.new('StringValue');value.Name=string.format('Chunk_%04d',count);value.Value=string.sub(text,cursor,last);value.Parent=folder;cursor=last+1
 end
 folder:SetAttribute('ChunkCount',count)
 local readback={};for i=1,count do local value=assert(folder:FindFirstChild(string.format('Chunk_%04d',i)));assert(value:IsA('StringValue'),'Journal JSON chunk class mismatch');readback[i]=value.Value end
 assert(table.concat(readback)==text,'Persistent journal JSON readback mismatch')
end
function API.Apply(options)
 assert(game:GetService('RunService'):IsStudio() and not game:GetService('RunService'):IsRunning(),'Apply requires Edit')
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,'Wrong DEV')
 local plan=assert(options.plan,"Required options.plan missing");local map=assert(workspace:FindFirstChild('MapBlockout'));local hash=assert(plan.planHash,"Required plan.planHash missing")
 assert(plan.migrationId==MIGRATION and plan.baselineManagedContentSHA256==BASELINE and plan.status=='ReadyForNativeApply','Unreviewed geometry plan')
 assert(type(hash)=='string'and #hash==64,'Missing final desired hash')
 local verify=assert(options.verify,"Required options.verify missing");local sourceAPI=assert(options.sourceAPI,"Required options.sourceAPI missing");local rollback=assert(options.rollbackAPI,"Required options.rollbackAPI missing")
 if map:GetAttribute('CompactMapMigrationId')==MIGRATION then
  assert(map:GetAttribute('CompactMapStatus')=='Completed'and map:GetAttribute('CompactMapDesiredHash')==hash,'Active migration differs')
  local proof=verify.Verify(options)
  assert(proof.passed,'Existing compact map drifted: '..tostring(proof.failureSummary))
  sourceAPI.Verify()
  return {status='Retained',geometryWrites=0,sourceWrites=0,newWalls=0,proof=proof}
 end
 assert(map:GetAttribute('CompactMapMigrationId')==nil,'Unknown map migration')
 assert(shared.CompactMapBaselineProof and shared.CompactMapBaselineProof.passed,'Fresh actual baseline proof required')
 assert(shared.CompactCorrectedFitReport and shared.CompactCorrectedFitReport.nativeProposalFitPassed and shared.CompactCorrectedFitReport.b==plan.candidate.b,'Actual native fitted owner proof required')
 assert(options.nativeAssetsProof and options.nativeAssetsProof.passed,'Actual native mesh corner proof required')
 local originals=assert(shared.CompactMapManagedOriginals,"Required shared.CompactMapManagedOriginals missing");local native=assert(shared.CompactMapOriginalNativeValues,"Required shared.CompactMapOriginalNativeValues missing")
 local roads=assert(SS:FindFirstChild('CompactMapRoadTemplates'));local shell=assert(SS:FindFirstChild('CompactMapShellTemplate'));local cube=assert(SS:FindFirstChild('CompactMapWallCubeTemplate'))
 assert(cube:IsA('MeshPart') and cube.CollisionFidelity==Enum.CollisionFidelity.Box,'Genuine closed cube must use actual Box collision')
 assert(options.runtimeJSON and #options.runtimeJSON<200000,'Bounded canonical runtime JSON required')
 local raw=H:JSONDecode(options.runtimeJSON);assert(raw.runtimeValidated==true and raw.planHash==hash,'Unvalidated runtime geometry')
 local planJSON=H:JSONEncode(plan);local metadataJSON=H:JSONEncode(assert(options.metadata,'Canonical metadata missing'))
 -- Preflight all reference-bearing originals and every prepared native template before mutation.
 for _,row in plan.ownership do local node=assert(originals[row.key],"Required originals[row.key] missing");assert(node:GetFullName()==row.path,'Original identity/parent drift '..row.path)end
 for _,op in plan.operations do
  local node=assert(originals[op.key],"Required originals[op.key] missing");assert(node.Parent and node:GetFullName()==op.path,'Original missing')
  if op.category=='RebuiltRoadSurface'then assert(roads:FindFirstChild(op.meshPrototype)and roads[op.meshPrototype]:IsA('MeshPart'),'Road template missing '..op.meshPrototype)end
  if op.category=='FittedBaseShell'then for _,p in node:GetChildren()do if p:IsA('MeshPart')then assert(shell:FindFirstChild(p.Name),'Shell group missing '..p.Name)end end end
 end
 local txn=Instance.new('Folder');txn.Name='CompactMapV1_WorldJournal_'..hash:sub(1,12);txn:SetAttribute('MigrationId',MIGRATION);txn:SetAttribute('BaselineSHA256',BASELINE);txn:SetAttribute('DesiredHash',hash);txn:SetAttribute('Status','InProgress');txn.Parent=SS
 persistJSON(txn,'PlanManifest_JSON_Chunks',planJSON,hash)
 persistJSON(txn,'RuntimeGeometry_JSON_Chunks',options.runtimeJSON,hash)
 persistJSON(txn,'MetadataPatch_JSON_Chunks',metadataJSON,hash)
 persistJSON(txn,'NativeAssets_JSON_Chunks',H:JSONEncode(options.nativeAssetsProof),hash)
 persistJSON(txn,'OriginalSources_JSON_Chunks',H:JSONEncode(assert(shared.CompactMapSources,'Original source records missing')),hash)
 persistJSON(txn,'RouteDraft_JSON_Chunks',H:JSONEncode(assert(options.routeDraft,'Classified route draft required')),hash)
 local refs=Instance.new('Folder');refs.Name='OriginalRefs';refs.Parent=txn
 local meshes=Instance.new('Folder');meshes.Name='MeshBackups';meshes.Parent=txn
 local created=Instance.new('Folder');created.Name='CreatedRefs';created.Parent=txn
 local retired=Instance.new('Folder');retired.Name='RetiredSharedSeparators';retired.Parent=txn
 local refCount=0
 for _,rows in {shared.CompactMapBeforeManifest.objects,shared.CompactMapBeforeManifest.externalStaticObjects}do for _,r in rows do
  refCount+=1;local v=Instance.new('ObjectValue');v.Name=string.format('Ref_%04d',refCount);v:SetAttribute('OriginalKey',r.key);v.Value=originals[r.key];v.Parent=refs
 end end
 local function persistRefs(name,rows)
  local folder=Instance.new('Folder');folder.Name=name;folder.Parent=txn
  for i,row in rows do
   local node=assert(originals[row.key],'Persistent original reference missing '..row.path)
   local ref=Instance.new('ObjectValue');ref.Name=string.format('Ref_%04d',i);ref:SetAttribute('OriginalKey',row.key);ref.Value=node;ref.Parent=folder
  end
 end
 persistRefs('ProtectedRefs',shared.CompactMapBeforeManifest.protectedSourceAssets)
 persistRefs('SourceRefs',shared.CompactMapSources)
 persistRefs('EnvironmentRefs',shared.CompactMapBeforeManifest.effects)
 local function track(node)
  node:SetAttribute('CompactMapMigrationId',MIGRATION);node:SetAttribute('CompactMapDesiredHash',hash)
  local v=Instance.new('ObjectValue');v.Name='Created_'..tostring(#created:GetChildren()+1);v.Value=node;v.Parent=created
  return node
 end
 local meshIndex=0
 local function applyMesh(node,template,key,frame)
  meshIndex+=1;local clone=node:Clone();clone.Name='Mesh_'..meshIndex
  for _,tag in CS:GetTags(clone)do CS:RemoveTag(clone,tag)end;clone.Parent=meshes
  local ref=Instance.new('ObjectValue');ref.Name='MeshRef_'..meshIndex;ref:SetAttribute('OriginalKey',key);ref:SetAttribute('CloneName',clone.Name);ref.Value=node;ref.Parent=meshes
  local before=native[key];node:ApplyMesh(template)
  for name,value in before.properties do if name~='CFrame'and name~='Size'then node[name]=value end end
  node.CustomPhysicalProperties=if before.customPhysicsWasNil then nil else before.customPhysics
  node.CFrame=frame or template.CFrame;node.Size=template.Size
  assert(node.MeshId==template.MeshId and node.MeshId~='','Native asset identity readback failed')
 end
 local result={migrationId=MIGRATION,planHash=hash,status='Applying',geometryWrites=0,sourceWrites=0,newWalls=0,retiredSeparators=0,retainedOuterSeparators=0,originalInstancesPreserved=refCount,protectedTemplateWrites=0,playerDataWrites=0}
 local sourceJournal
 local ok,reason=xpcall(function()
  local sourceResult;sourceResult,sourceJournal=sourceAPI.Apply({baselineVerified=true,nativeOwnerFitVerified=true,verifiedPlanHash=hash})
  result.sourceWrites=sourceResult.sourceWrites
  if sourceJournal then local v=Instance.new('ObjectValue');v.Name='SourceJournal';v.Value=sourceJournal;v.Parent=txn end
  for _,op in plan.operations do
   local node=originals[op.key]
   if op.retire then node.Parent=retired;result.retiredSeparators+=1
   elseif op.category=='RebuiltRoadSurface'then applyMesh(node,roads[op.meshPrototype],op.key)
   elseif op.category=='FittedBaseShell'then
    local frame=CFrame.new(table.unpack(op.pivot));node:PivotTo(frame)
    for _,p in node:GetChildren()do if p:IsA('MeshPart')then
     local key;for k,row in native do if row.instance==p then key=k;break end end
     local template=shell[p.Name];applyMesh(p,template,assert(key,"Required key missing"),frame*template.CFrame)
    end end
    if node.PrimaryPart==nil then node.WorldPivot=frame end
   else
    if op.scale then node:ScaleTo(op.scale)end
    if op.pivot then node:PivotTo(CFrame.new(table.unpack(op.pivot)))end
    if op.cframe then node.CFrame=CFrame.new(table.unpack(op.cframe))end
    if op.size then node.Size=Vector3.new(table.unpack(op.size))end
    if op.gateGround and node.PrimaryPart==nil then node.WorldPivot=CFrame.new(table.unpack(op.gateGround))end
   end
   if op.attributes then for name,value in op.attributes do node:SetAttribute(name,decode(value))end end
   if op.category=='RetainedOuterContainment'then result.retainedOuterSeparators+=1 end
   result.geometryWrites+=1
  end
  for _,u in options.metadata.updates do
   local node=assert(originals[u.key],"Required originals[u.key] missing");for _,name in u.remove do node:SetAttribute(name,nil)end
   for name,value in u.after do node:SetAttribute(name,decode(value))end
  end
  map.MapArt.InstalledFootprints.Value=H:JSONEncode(plan.artFootprints)
  map.MapArt:SetAttribute('CompactMapGeometryHash',plan.geometryPlanHash)
  map.Paths.StyledSurfaces:SetAttribute('CompactMapGeometryHash',options.roadGeometryHash)
  local wallFolder=track(Instance.new('Folder'));wallFolder.Name='RegionWalls';wallFolder.Parent=map
  for _,w in plan.walls do
   local part=track(cube:Clone());part.Name=w.id;part.Size=Vector3.new(table.unpack(w.size));part.CFrame=CFrame.new(table.unpack(w.cframe));part.Anchored=true;part.CanCollide=true;part.CanQuery=true;part.CanTouch=false;part.CastShadow=true;part.Transparency=0;part.Reflectance=0;part.CollisionGroup='Default';part.Color=Color3.fromRGB(table.unpack(w.tintRGB));part.Material=Enum.Material.Glacier;part.MaterialVariant='Bingus_Saved_Studs_13719188279';part:SetAttribute('StudsPerTile',.25);part:SetAttribute('StudMaterialAssetId',13719188279);part:SetAttribute('RunId',w.runId);part:SetAttribute('RegionPair',table.concat(w.regionPair,'|'));part.Parent=wallFolder
   assert(part.CollisionFidelity==Enum.CollisionFidelity.Box and part.MeshId==cube.MeshId,'Wall collider or mesh readback invalid');result.newWalls+=1
  end
  local service=map.ServiceStallPatches.SellStall
  local plinth=track(Instance.new('Part'));plinth.Name='SellSignSupport';plinth.Size=Vector3.new(6,service.Size.Y,5);plinth.CFrame=service.CFrame*CFrame.new(-20,0,20.477256774902344);plinth.Anchored=true;plinth.CanCollide=service.CanCollide;plinth.CanQuery=service.CanQuery;plinth.CanTouch=service.CanTouch;plinth.Color=service.Color;plinth.Material=service.Material;plinth.MaterialVariant=service.MaterialVariant;plinth.CustomPhysicalProperties=service.CustomPhysicalProperties;plinth:SetAttribute('StudsPerTile',.25);plinth:SetAttribute('StudMaterialAssetId',13719188279);plinth.Parent=map.ServiceStallPatches
  local value=track(Instance.new('StringValue'));value.Name='CompactMapRuntimeGeometry';value.Value=options.runtimeJSON;value.Parent=map
  map:SetAttribute('LayoutVersion',shared.CompactMapBeforeManifest.objects[1].attributes.LayoutVersion+1)
  local proof=verify.Verify(options);assert(proof.passed,'Static native verification failed')
  sourceAPI.Verify()
  map:SetAttribute('CompactMapMigrationId',MIGRATION);map:SetAttribute('CompactMapDesiredHash',hash);map:SetAttribute('CompactMapStatus','Completed')
  txn:SetAttribute('Status','Completed');result.status='Completed';result.staticProof=proof
 end,debug.traceback)
 if not ok then
  local pass,restore=pcall(rollback.Rollback,txn,sourceAPI)
  txn:SetAttribute('Failure',tostring(reason):sub(1,2000))
  assert(pass,'Apply failed and rollback requires attention: '..tostring(reason)..' / '..tostring(restore))
  error('Compact apply rolled back: '..tostring(reason),0)
 end
 shared.CompactMapWorldJournal=txn;shared.CompactMapApplyResult=result
 return result
end
return API
