
assert(game.PlaceId==91958083796436 and game.GameId==10548905405 and not game.RunService:IsRunning(),"DEV Edit only")
local B=assert(shared.DevBaseMigrationBaseline)
local targets=workspace.MapBlockout.PlayerBasePatches
assert(not game.ServerStorage:FindFirstChild("AuthoredBaseMigration_Backup_v1"),"Migration backup already exists")
local backup=Instance.new("Folder");backup.Name="AuthoredBaseMigration_Backup_v1";backup:SetAttribute("NoRuntimeUse",true);backup:SetAttribute("MigrationVersion",1);backup:SetAttribute("CreatedAt",B.createdAt);backup.Parent=game.ServerStorage
local source=Instance.new("StringValue");source.Name="BaseIncomePlaqueSystem_Before";source.Value=game.ServerScriptService.Server.Systems.BaseIncomePlaqueSystem.Source;source.Parent=backup
local summaries={}
for i=1,12 do
 local id=string.format("Base_%02d",i)
 local old=assert(B.old[id]);local new=assert(B.new[id])
 assert(old.model.Parent==targets and new.model.Parent==workspace.MapBlockout.MapArt.BaseShells,"Base changed during planning")
 assert(new.model.Name=="Showhouse_"..id and #new.model:GetChildren()==3 and #old.model:GetChildren()==19,"Schema changed")
 local copy=old.model:Clone();copy.Name="Before_"..id;copy:SetAttribute("NoRuntimeUse",true)
 for _,n in copy:GetDescendants()do for _,tag in game.CollectionService:GetTags(n)do game.CollectionService:RemoveTag(n,tag)end end
 copy.Parent=backup
 local artAttrs=Instance.new("StringValue");artAttrs.Name="ShowhouseAttributes_"..id;artAttrs.Value=game.HttpService:JSONEncode(new.attrs);artAttrs.Parent=backup
end
local CH=game.ChangeHistoryService
local recording=CH:TryBeginRecording("PromoteShowhousesToFunctionalBases")
for i=1,12 do
 local id=string.format("Base_%02d",i)
 local old=B.old[id];local new=B.new[id];local model=new.model
 for key,value in old.attrs do model:SetAttribute(key,value)end
 model:SetAttribute("AuthoredBaseLayout",true)
 model:SetAttribute("FunctionalBaseRevision",1)
 model:SetAttribute("OriginalArtModelName","Showhouse_"..id)
 model:SetAttribute("BaseId",id)
 model:SetAttribute("BaseOrigin",old.pivot)
 model:SetAttribute("Phase5DLayoutPivot",old.pivot)
 model.WorldPivot=old.pivot
 for _,child in old.model:GetChildren()do child.Parent=model end
 assert(#old.model:GetChildren()==0,"Old base retained children")
 old.model.Parent=nil
 model.Name=id
 model.Parent=targets
 old.model:Destroy()
 table.insert(summaries,{baseId=id,partsTransferred=19,placementAttachmentsTransferred=12,acceptedMeshesRetained=3,newModel=model:GetFullName(),oldLiveModelDeleted=true})
 if i%3==0 then task.wait()end
end
if recording then CH:FinishRecording(recording,Enum.FinishRecordingOperation.Commit)end
B.backup=backup
local preserved=B.guard.Verify(B.protected);assert(preserved.passed,"Brainrot preservation failed")
return {basesMigrated=12,oldLiveContainersDeleted=12,partsTransferred=228,placementAttachmentsTransferred=144,acceptedArtMeshes=36,backup=backup:GetFullName(),rows=summaries,protected=preserved}
