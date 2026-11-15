assert(not game:GetService("RunService"):IsRunning())
assert(game.PlaceId==91958083796436 and game.GameId==10548905405)
assert(shared.CompactMapBeforeManifest and shared.CompactMapManagedOriginals)
local SS=game:GetService("ServerStorage")
local CS=game:GetService("CollectionService")
local folder=SS:FindFirstChild("MapCompactionBackups")
if not folder then folder=Instance.new("Folder");folder.Name="MapCompactionBackups";folder.Parent=SS end
local name="CompactMap_V1_3fb9d9e8a543"
local existing=folder:FindFirstChild(name)
if existing then assert(existing:GetAttribute("BaselineManagedSHA256")=="3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310");return {existing=true,path=existing:GetFullName()}end
local backup=Instance.new("Folder");backup.Name=name
backup:SetAttribute("MigrationId","CompactMap_V1")
backup:SetAttribute("BaselineManagedSHA256","3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310")
backup:SetAttribute("NoRuntimeUse",true)
local snapshot=workspace.MapBlockout:Clone()
assert(snapshot and #snapshot:GetDescendants()==#workspace.MapBlockout:GetDescendants(),"Incomplete clone")
snapshot.Name="MapBlockout_Before"
local removed=0
for _,o in {snapshot,table.unpack(snapshot:GetDescendants())}do for _,tag in CS:GetTags(o)do CS:RemoveTag(o,tag);removed+=1 end end
snapshot.Parent=backup
local sourceFolder=Instance.new("Folder");sourceFolder.Name="LiveSources_Before";sourceFolder.Parent=backup
for i,row in shared.CompactMapSources do local v=Instance.new("StringValue");v.Name=string.format("Source_%04d",i);v:SetAttribute("OriginalPath",row.path);v:SetAttribute("OriginalClass",row.class);v.Value=row.source;v.Parent=sourceFolder end
local records=Instance.new("Folder");records.Name="BeforeManifest_JSON_Chunks";records.Parent=backup
for i,chunk in shared.CompactMapTransfer.Manifest do local record=Instance.new("StringValue");record.Name=string.format("Chunk_%04d",i);record.Value=chunk;record.Parent=records end
backup.Parent=folder
shared.CompactMapBackup=backup
shared.CompactMapOriginalNativeValues={}
for k,o in pairs(shared.CompactMapManagedOriginals)do
 local row={instance=o,parent=o.Parent,attributes=o:GetAttributes(),tags=CS:GetTags(o)}
 if o:IsA("BasePart")then row.cframe=o.CFrame;row.size=o.Size;row.pivotOffset=o.PivotOffset;row.material=o.Material;row.variant=o.MaterialVariant;row.customPhysics=o.CustomPhysicalProperties;row.customPhysicsWasNil=o.CustomPhysicalProperties==nil end
 if o:IsA("Model")then row.pivot=o:GetPivot();row.scale=o:GetScale();row.primaryPart=o.PrimaryPart end
 if o:IsA("Attachment")then row.attachmentCFrame=o.CFrame end
 if o:IsA("ObjectValue")then row.reference=o.Value end
 shared.CompactMapOriginalNativeValues[k]=row
end
return {backupPath=backup:GetFullName(),mapInstances=1+#snapshot:GetDescendants(),sourceRecords=#sourceFolder:GetChildren(),tagsRemovedFromBackupOnly=removed,workspaceWrites=0,originalSourceWrites=0,liveOriginalsCaptured=true}
