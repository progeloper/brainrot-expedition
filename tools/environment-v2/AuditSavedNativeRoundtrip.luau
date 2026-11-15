-- Offline native-file audit only. No serialization, Studio call, or original-file rewrite.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local roblox=require('@lune/roblox')
local process=require('@lune/process')
local root=assert(process.args[1],'Pass exact selected repository root')
local doc=root..'/docs/environment-v2'
local file=doc..'/snapshots/'..assert(process.args[2],'Pass saved snapshot basename')
local originalBytes=fs.readFile(file)
local fileSHA=serde.hash('sha256',originalBytes)
local expectedFileSHA=assert(process.args[3],'Pass independently recorded saved native fileSHA256')
local expectedBytes=assert(tonumber(process.args[4]),'Pass independently recorded saved native bytes')
local expectedFrozenSHA=assert(process.args[5],'Pass independently frozen exact manifestSHA256')
local report={schemaVersion=2,status='Running',scope='Offline native RBXL deserialization and persisted reference/source inspection; not a Studio cold reopen, render, physics, runtime, or mesh-content query',inputFile=file,inputBytes=#originalBytes,inputSHA256=fileSHA,deserializer='Lune0.10.5 @lune/roblox',originalFileWrites=0,studioCalls=0,sourceWrites=0,checks=0,failures={},unsupportedFields={'Terrain.VoxelGridAssetContentMap is unsupported by Lune; no terrain preservation or resave claimed','Native triangles are counted by verified persistent MeshId bindings and corner-proof counts; no EditableMesh readback in offline Lune','CurrentPhysicalProperties, renderer, jump/cart reach, active game state, saved native UI/render appearance are not assessed offline','DataModel PlaceId/GameId and live editor buffers are not independently verified by Lune'},coldStudioReopen='NotRunByThisAudit'}
local function check(condition,message)
 report.checks+=1
 if not condition then table.insert(report.failures,message)end
 return condition
end
local function child(parent,name,class)
 local n=assert(parent:FindFirstChild(name),'Missing '..name)
 assert(not class or n.ClassName==class,'Wrong class '..name)
 return n
end
local function readChunks(parent,name)
 local folder=child(parent,name,'Folder');local nodes=folder:GetChildren()
 table.sort(nodes,function(a,b)return a.Name<b.Name end)
 local chunks={}
 for i,n in nodes do assert(n.ClassName=='StringValue'and n.Name==string.format('Chunk_%04d',i)and#n.Value<=60000,'Invalid chunks '..name);chunks[i]=n.Value end
 local text=table.concat(chunks)
 check(#nodes==folder:GetAttribute('ChunkCount')and#text==folder:GetAttribute('Bytes'),'Complete persisted '..name..' chunk/byte population')
 return text,serde.decode('json',text),{chunks=#nodes,bytes=#text,sha256=serde.hash('sha256',text)}
end
local meshReadModes={legacyMeshId=0,serializedMeshContentUri=0}
local function meshId(node)
 local ok,id=pcall(function()return node.MeshId end)
 if ok and type(id)=='string'and#id>0 then meshReadModes.legacyMeshId+=1;return id end
 local content=node.MeshContent;assert(typeof(content)=='Content'and type(content.Uri)=='string'and content.Uri:match('^rbxassetid://%d+$'),'Persistent native URI unavailable')
 meshReadModes.serializedMeshContentUri+=1;return content.Uri
end
local function eq(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='table'then for k,v in a do if not eq(v,b[k])then return false end end;for k in b do if a[k]==nil then return false end end;return true end
 return a==b
end
local ok,errorText=xpcall(function()
 check(fileSHA==expectedFileSHA and#originalBytes==expectedBytes,'Exact parent-saved native file hash/bytes')
 local gameObj=roblox.deserializePlace(originalBytes)
 local WS=gameObj:GetService('Workspace');local SS=gameObj:GetService('ServerStorage');local RS=gameObj:GetService('ReplicatedStorage')
 local map=child(WS,'MapBlockout');local layer=child(map,'EnvironmentArt_V2','Folder')
 local frozenText=fs.readFile(doc..'/FrozenApplyManifest.json');local frozen=serde.decode('json',frozenText);local frozenSHA=serde.hash('sha256',frozenText)
 check(frozenSHA==expectedFrozenSHA,'Exact frozen desired JSON hash')
 check(layer:GetAttribute('ArtOwner')=='BR_EnvironmentArt_V2'and layer:GetAttribute('EnvironmentV2Status')=='Completed'and layer:GetAttribute('EnvironmentV2Hash')==frozenSHA,'Saved layer ownership/completion/frozen hash')
 local journal=child(SS,'EnvironmentV2_Journal_'..frozenSHA:sub(1,12),'Folder')
 local savedManifest,_,manifestReceipt=readChunks(journal,'Manifest');check(savedManifest==frozenText,'Journal preserves byte-exact frozen manifest')
 local _,nativeProof,nativeReceipt=readChunks(journal,'NativeProof');local _,expectedNative,expectedReceipt=readChunks(journal,'ExpectedNative')
 check(nativeProof.passed==true and nativeProof.completeBatch==true and#nativeProof.groups==34 and nativeProof.sourceSHA256==frozen.assetSourceSHA256,'Saved complete native proof/current source')
 local byMesh={};for _,g in nativeProof.groups do check(g.passed and g.complete and not byMesh[g.meshId],'Unique complete persistent mesh proof '..g.prototypeId..'/'..g.exportGroup);byMesh[g.meshId]=g end
 local counts={models=0,BaseParts=0,visible=0,visibleMeshParts=0,signFaceParts=0,colliders=0,uniqueMeshIds=0,instances=#layer:GetDescendants()+1,triangles=0,boundaries=0}
 local seen={};local models={}
 for _,m in layer:GetChildren()do check(m:IsA('Model'),'Layer direct child is a model');if m:IsA('Model')then counts.models+=1;local id=m:GetAttribute('EnvironmentId');check(not models[id]and id~=nil,'Unique installed row identity');models[id]=m;if m:GetAttribute('EnvironmentRole')=='Boundary'or m:GetAttribute('ArtRole')=='Boundary'then counts.boundaries+=1 end end end
 for _,v in layer:GetDescendants()do
  check(not v:IsA('LuaSourceContainer'),'Installed layer contains no runtime Source')
  if v:IsA('BasePart')then
   counts.BaseParts+=1;local role=v:GetAttribute('EnvironmentRole')
   if role=='Collider'then counts.colliders+=1;check(v.Transparency==1 and v.CanCollide and v.CanQuery and not v.CanTouch,'Saved collider flags '..v:GetFullName())
   elseif role=='Visible'or role=='VisibleSignFace'then
    counts.visible+=1;check(v.Material==roblox.Enum.Material.Glacier and v.MaterialVariant=='Bingus_Saved_Studs_13719188279'and v:GetAttribute('StudsPerTile')==.25,'Saved visible uniform studs '..v:GetFullName())
    check(v.Anchored and v.Transparency==0 and not v.CanCollide and not v.CanQuery and not v.CanTouch,'Saved visible render/physics flags '..v:GetFullName())
    if role=='VisibleSignFace'then counts.signFaceParts+=1;counts.triangles+=12;check(v.ClassName=='Part'and v:GetAttribute('SourceTriangles')==12,'Saved primitive sign face')
    else counts.visibleMeshParts+=1;check(v.ClassName=='MeshPart','Visible actual native MeshPart');local actualId=meshId(v);local g=byMesh[actualId];check(g~=nil and v:GetAttribute('SourceTriangles')==(g and g.actualTriangles),'Saved mesh ID/native triangle evidence '..v:GetFullName());if g then counts.triangles+=g.actualTriangles end;seen[actualId]=true;check(v:GetAttribute('ImportedMeshId')==actualId,'Saved ImportedMeshId equals actual serialized MeshContent URI') end
   else check(false,'Unclassified installed BasePart '..v:GetFullName())end
   check(v:GetAttribute('ArtOwner')=='BR_EnvironmentArt_V2','Installed BasePart ownership')
  elseif v:IsA('SurfaceAppearance')then check(false,'No static custom SurfaceAppearance')end
 end
 for _ in seen do counts.uniqueMeshIds+=1 end
 counts.boundaries=0;for _,r in frozen.objects do if r.role=='Boundary'then counts.boundaries+=1 end;check(models[r.id]~=nil,'Saved every frozen row '..r.id)end
 for k,n in {models=147,BaseParts=582,visible=277,visibleMeshParts=271,signFaceParts=6,colliders=305,uniqueMeshIds=34,instances=786,triangles=43558,boundaries=70}do check(counts[k]==n,'Saved native installed count '..k..' expected'..n..' got'..counts[k])end
 report.installed=counts;report.nativeAssetReadMode=meshReadModes;report.nativeAssetReadPolicy='Read actual serialized MeshContent.Uri when legacy MeshId is not stored; no metadata-only asset-ID substitution.'
 local checkpoint=child(SS,'EnvironmentV2_Checkpoint_f396b10caf4d','Folder')
 check(checkpoint:GetAttribute('Completed')and checkpoint:GetAttribute('NoRuntimeUse')and checkpoint:GetAttribute('ArtOwner')=='BR_EnvironmentArt_V2','Saved checkpoint owned/completed')
 local beforeText,before,manifestBeforeReceipt=readChunks(checkpoint,'BeforeManifest');local sourcesText,sources,sourcesReceipt=readChunks(checkpoint,'BeforeSources')
 check(beforeText==fs.readFile(doc..'/BeforeManifest.json')and manifestBeforeReceipt.sha256==frozen.baselineSceneSHA256,'Checkpoint exact complete before manifest')
 check(sourcesText==fs.readFile(doc..'/LiveSources.json')and sourcesReceipt.sha256=='ee0fac1b3cbbfa848181ecfa6997d0ba1dc0ab7091a6e778513b24ce41a55846','Checkpoint exact357-source JSON bytes')
 local refs={};local targets={};local refCount=0
 for _,v in child(checkpoint,'OriginalRefs','Folder'):GetChildren()do
  refCount+=1;local key=v:GetAttribute('OriginalKey');local target=v.Value
  check(v.ClassName=='ObjectValue'and target~=nil,'Persisted original ObjectValue target nonnil')
  if target then check(type(key)=='string'and not refs[key]and not targets[target],'Unique explicit persistent original key/target');check(target.Name==v:GetAttribute('OriginalName')and target.ClassName==v:GetAttribute('OriginalClass'),'Exact persisted reference name/class '..tostring(key));refs[key]=target;targets[target]=key end
 end
 check(refCount==3142,'Checkpoint exactly3142 explicit original references')
 for _,r in before.records do local target=refs[r.key];check(target and target.Name==r.name and target.ClassName==r.class,'Saved original typed record identity '..r.path)end
 local exactSources=0;local sourceSet={}
 for _,r in sources do
  local v=refs[r.key];check(v and v:IsA('LuaSourceContainer')and v.Name==r.name and v.ClassName==r.class,'Saved exact source reference '..r.path)
  if v then check(v.Source==r.source,'Byte-exact saved source '..r.path);if v.Source==r.source then exactSources+=1 end;sourceSet[v]=true end
 end
 local actualSources=0;for _,v in gameObj:GetDescendants()do if v:IsA('LuaSourceContainer')then actualSources+=1;check(sourceSet[v]==true,'No new/uncaptured native Source '..v:GetFullName())end end
 check(exactSources==357 and actualSources==357,'All357 originals preserved and no extra Sources')
 local copies=child(checkpoint,'GeometryCopies','Folder');local cloneRows={};local copySources=0
 for _,c in copies:GetChildren()do local n=#c:GetDescendants()+1;cloneRows[c.Name]=n;check(not c:IsDescendantOf(WS),'Checkpoint clone outside Workspace');for _,v in c:GetDescendants()do if v:IsA('LuaSourceContainer')then copySources+=1 end end end
 check(#copies:GetChildren()==3 and cloneRows.Map_Before==1581 and cloneRows.ProtectedAssets_Before==1163 and cloneRows.External_Before==2 and copySources==0,'Three complete source-free off-world original geometry copies')
 report.checkpoint={OriginalRefs=refCount,beforeRecords=#before.records,exactOriginalSources=exactSources,actualSourceContainers=actualSources,beforeManifest=manifestBeforeReceipt,beforeSources=sourcesReceipt,geometryCopies=cloneRows,geometryCopySources=copySources}
 local brainrots=child(child(RS,'StudioAssets'),'Brainrots');local br={models=0,BaseParts=0,visibleStuds=0,bodies=0,CaptureAttachments=0,CargoAttachments=0,rows={}}
 for _,m in brainrots:GetChildren()do
  check(m:IsA('Model')and m.Name:match('^BRT_%d%d%d$')~=nil,'Canonical brainrot model '..m.Name);br.models+=1
  local row={id=m.Name,BaseParts=0,visibleStuds=0,bodies=0,CaptureAttachments=0,CargoAttachments=0}
  for _,v in m:GetDescendants()do
   if v:IsA('BasePart')then row.BaseParts+=1;br.BaseParts+=1;if v.Transparency<1 then row.visibleStuds+=1;br.visibleStuds+=1;check(v.Material==roblox.Enum.Material.Glacier and v.MaterialVariant=='Bingus_Saved_Studs_13719188279','Saved brainrot uniform visible studs '..v:GetFullName())end
    if v.Name=='Body'then row.bodies+=1;br.bodies+=1;check(v.CanQuery and v.Transparency<1,'Exactly visible/queryable actual Body '..m.Name)end
   elseif(v:IsA('Model')or v:IsA('Folder'))and v.Name=='Body'then check(false,'No Body grouping alias '..m.Name)
   elseif v:IsA('Attachment')and(v.Name=='CaptureAttachment'or v.Name=='CargoAttachment')then row[v.Name..'s']+=1;br[v.Name..'s']+=1;check(v.Parent and v.Parent:IsA('BasePart')and v.Parent.Name=='Body','Body owns capture/cargo attachment '..m.Name)end
  end
  check(row.bodies==1 and row.CaptureAttachments==1 and row.CargoAttachments==1,'OneBody/two attachments '..m.Name);table.insert(br.rows,row)
 end
 table.sort(br.rows,function(a,b)return a.id<b.id end)
 check(br.models==35 and br.BaseParts==890 and br.bodies==35 and br.CaptureAttachments==35 and br.CargoAttachments==35,'All35/890/35Body/70body attachments saved')
 report.brainrots=br
 local signs={}
 local function sameFrame(actual,expected)
  local values={actual:GetComponents()};if #values~=#expected then return false end
  for i,n in expected do if math.abs(values[i]-n)>.01 then return false end end;return true
 end
 for _,r in frozen.objects do if r.signFaceProxy then
  local p=r.signFaceProxy;local gui=refs[p.originalGuiKey];local sign=refs[p.originalSignKey];local header=models[r.id];local proxy=header and header:FindFirstChild(p.id)
  check(gui and gui:IsA('SurfaceGui')and gui.Parent==sign and gui.Adornee==proxy and proxy and proxy.Parent==header,'Saved original GUI points at exact owned header child '..p.id)
  check(gui.Face==roblox.Enum.NormalId.Back and gui.AlwaysOnTop==false,'Saved original FaceBack/AlwaysOnTopfalse '..p.id)
  check(proxy and proxy:GetAttribute('EnvironmentRole')=='VisibleSignFace'and proxy:GetAttribute('EnvironmentId')==r.id,'Saved proxy owned parent/ref '..p.id)
  check(proxy and sameFrame(proxy.CFrame,p.cframe),'Exact amended saved proxy world pose '..p.id)
  check(proxy and math.abs(proxy.Size.X-16)<1e-6 and math.abs(proxy.Size.Y-5)<1e-6 and math.abs(proxy.Size.Z-.1)<1e-6,'Exact saved16x5x.1 signface dimensions '..p.id)
  table.insert(signs,{originalGuiKey=p.originalGuiKey,originalGuiPath=gui:GetFullName(),adorneePath=proxy:GetFullName(),headerEnvironmentId=r.id,expectedCFrame=p.cframe,actualCFrame={proxy.CFrame:GetComponents()},presentationOverride=p.presentationOverride,exactApprovedPose=sameFrame(proxy.CFrame,p.cframe),persistedAdorneeExactOwnedChild=gui.Adornee==proxy,guiParentOriginalSign=gui.Parent==sign})
 end end
 check(#signs==6,'Six persisted owned-header sign bindings');report.signs=signs
 report.finalFrozenManifestSHA256=frozenSHA;report.presentationAmendment=frozen.presentationAmendment;report.previousEvidencePath='docs/environment-v2/revisions/v1/ActualSavedNativeRoundtrip.json'
 report.journal={path=journal:GetFullName(),status=journal:GetAttribute('Status'),manifest=manifestReceipt,nativeProof=nativeReceipt,expectedNative=expectedReceipt,manifestByteExact=true}
 check(journal:GetAttribute('Status')=='Completed','Saved journal completed')
 check(fs.readFile(file)==originalBytes,'Input native saved file remains byte-exact unchanged')
end,function(e)return tostring(e)end)
if not ok then table.insert(report.failures,'Offline audit terminated: '..tostring(errorText))end
report.status=if #report.failures==0 then'PassedOfflineNativeSavedRoundtrip'else'FailedOfflineNativeSavedRoundtrip'
report.passed=#report.failures==0
fs.writeFile(doc..'/ActualSavedNativeRoundtrip.json',serde.encode('json',report,true))
print(serde.encode('json',{status=report.status,checks=report.checks,failures=report.failures,installed=report.installed,brainrotCounts=report.brainrots and{models=report.brainrots.models,BaseParts=report.brainrots.BaseParts,bodies=report.brainrots.bodies,CaptureAttachments=report.brainrots.CaptureAttachments,CargoAttachments=report.brainrots.CargoAttachments,visibleStuds=report.brainrots.visibleStuds},checkpoint=report.checkpoint,output=doc..'/ActualSavedNativeRoundtrip.json'},true))
