assert(game:GetService('RunService'):IsStudio() and not game:GetService('RunService'):IsRunning(),'Edit DEV required')
assert(game.PlaceId==91958083796436 and game.GameId==10548905405,'Wrong DEV')
local baseline=assert(shared.CompactMapBeforeManifest,"Required shared.CompactMapBeforeManifest missing")
local originals=assert(shared.CompactMapManagedOriginals,"Required shared.CompactMapManagedOriginals missing")
local sources=assert(shared.CompactMapSources,"Required shared.CompactMapSources missing")
local CS=game:GetService('CollectionService')
local backup=assert(game.ServerStorage:FindFirstChild('MapCompactionBackups')):FindFirstChild('CompactMap_V1_3fb9d9e8a543')
assert(backup and backup:GetAttribute('BaselineManagedSHA256')=='3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310','Reviewed backup missing')
assert(1+#backup.MapBlockout_Before:GetDescendants()==#baseline.objects,'Incomplete map backup')
assert(#backup.LiveSources_Before:GetChildren()==#sources,'Incomplete source backup')
local byPath={};for _,v in backup.LiveSources_Before:GetChildren()do byPath[v:GetAttribute('OriginalPath')]=v.Value end
for _,r in sources do assert(byPath[r.path]==r.source,'Backup source mismatch '..r.path);assert(originals[r.key].Source==r.source,'Live source changed '..r.path)end
assert(not workspace.MapBlockout:GetAttribute('CompactMapMigrationId'),'Compact map already marked; refusing new baseline')
local journal={};local mapCount,protectedCount,externalCount=0,0,0
local function capture(rows,kind)
 for _,r in rows do
  local o=assert(originals[r.key],'Missing original '..r.path)
  local row={instance=o,parent=o.Parent,name=o.Name,archivable=o.Archivable,attributes=o:GetAttributes(),tags=CS:GetTags(o),properties={},kind=kind,key=r.key}
  if o:IsA('BasePart')then
   for _,n in {'CFrame','Size','PivotOffset','Anchored','CanCollide','CanQuery','CanTouch','CollisionGroup','Transparency','Reflectance','CastShadow','Material','MaterialVariant','Color','TopSurface','BottomSurface','LeftSurface','RightSurface','FrontSurface','BackSurface'}do row.properties[n]=o[n]end
   row.customPhysics=o.CustomPhysicalProperties;row.customPhysicsWasNil=o.CustomPhysicalProperties==nil
  end
  if o:IsA('Model')then row.pivot=o:GetPivot();row.scale=o:GetScale();row.primaryPart=o.PrimaryPart;row.streamingMode=o.ModelStreamingMode end
  if o:IsA('Attachment')then row.attachmentCFrame=o.CFrame end
  if o:IsA('ObjectValue')then row.reference=o.Value end
  if o:IsA('StringValue')then row.value=o.Value end
  journal[r.key]=row
 end
end
capture(baseline.objects,'Managed');mapCount=#baseline.objects
capture(baseline.protectedSourceAssets,'Protected');protectedCount=#baseline.protectedSourceAssets
capture(baseline.externalStaticObjects,'External');externalCount=#baseline.externalStaticObjects
shared.CompactMapBackup=backup
shared.CompactMapOriginalNativeValues=journal
shared.CompactMapTransaction={created={},retired={},meshBackups={},sourceChanges={},status='Prepared',baselineSHA='3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310'}
return {bound=true,managed=mapCount,protected=protectedCount,external=externalCount,sourceRecords=#sources,originalWrites=0,backupPath=backup:GetFullName()}
