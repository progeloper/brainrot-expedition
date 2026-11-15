--!strict
-- Edit-only source subtransaction. The canonical world transaction owns final Completed status.
-- Embedded exact current/proposed contents are reviewable; no original game source is required/evaluated.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local PAYLOAD = HttpService:JSONDecode(__PAYLOAD_JSON_LUA__)
local MIGRATION = "CompactMap_V1"
local BASELINE = "3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310"
local API = {}
local function context()
 assert(RunService:IsStudio() and not RunService:IsRunning(), "Compact source patch requires DEV Edit")
 assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Compact source patch wrong place/universe")
end
local function child(parent: Instance, name: string): Instance?
 local found: Instance? = nil
 for _,candidate in parent:GetChildren() do
  if candidate.Name == name then assert(found == nil, "Ambiguous source path: "..name);found=candidate end
 end
 return found
end
local function resolve(path: string): Instance
 local current: Instance = game
 for name in path:gmatch("[^%.]+") do current=assert(child(current,name), "Missing current source path: "..path) end
 return current
end
local function newOwner(): (Instance, Instance?)
 local path=PAYLOAD.newModule.path
 local parentPath,name=path:match("^(.*)%.([^%.]+)$")
 local parent=resolve(parentPath);local existing=child(parent,name)
 if existing then
  assert(existing:IsA("ModuleScript") and existing.Source == PAYLOAD.newModule.source, "New compact owner conflicts with existing source")
  assert(existing:GetAttribute("CompactMapMigrationId")==MIGRATION and existing:GetAttribute("CompactMapSourceSHA256")==PAYLOAD.newModule.afterSHA256, "New compact owner provenance mismatch")
 end
 return parent,existing
end
local function existingRows(): {any}
 local rows={}
 for _,patch in PAYLOAD.patches do
  local owner=resolve(patch.path)
  assert(owner:IsA("ModuleScript"), "Current source class changed: "..patch.path)
  local current=owner.Source
  assert(current==patch.beforeSource or current==patch.afterSource, "Current source contents drifted: "..patch.path)
  table.insert(rows,{owner=owner,patch=patch,current=current,changed=current~=patch.afterSource})
 end
 return rows
end
function API.Verify(): any
 context()
 local count=0
 for _,patch in PAYLOAD.patches do
  local owner=resolve(patch.path)
  assert(owner:IsA("ModuleScript") and owner.Source==patch.afterSource, "Compact source verification failed: "..patch.path)
  count+=1
 end
 local _,existing=newOwner();assert(existing,"New compact owner missing")
 return {passed=true,exactPatchedOwners=count,newOwnerCount=1,sourceWrites=0,gameplayRequires=0}
end
local function journalRecord(journal: Folder, row: any, i: number)
 local record=Instance.new("Folder");record.Name=string.format("Source_%02d",i);record.Parent=journal
 local ref=Instance.new("ObjectValue");ref.Name="Original";ref.Value=row.owner;ref.Parent=record
 local before=Instance.new("StringValue");before.Name="CapturedSource";before.Value=row.current;before.Parent=record
 local after=Instance.new("StringValue");after.Name="ProposedSource";after.Value=row.patch.afterSource;after.Parent=record
 record:SetAttribute("Path",row.patch.path)
end
local function rollbackRows(journal: Folder): ({any}, ModuleScript?)
 context()
 assert(journal:IsA("Folder") and journal.Parent==ServerStorage and journal:GetAttribute("MigrationId")==MIGRATION, "Not an owned source journal")
 assert(journal:GetAttribute("BaselineManagedSHA256")==BASELINE, "Source journal baseline mismatch")
 local rows={};local created: ModuleScript? = nil
 local expected,seen={},{}
 for _,patch in PAYLOAD.patches do expected[patch.path]=patch end
 for _,record in journal:GetChildren() do
  if record:IsA("Folder") then
   local path=record:GetAttribute("Path");local patch=expected[path]
   assert(patch and not seen[path], "Source rollback row is unknown/duplicate");seen[path]=true
   local ref=record:FindFirstChild("Original") :: ObjectValue
   local before=record:FindFirstChild("CapturedSource") :: StringValue
   local after=record:FindFirstChild("ProposedSource") :: StringValue
   assert(ref and ref:IsA("ObjectValue") and ref.Value and ref.Value:IsA("ModuleScript"), "Rollback source identity missing")
   assert(before and before:IsA("StringValue") and after and after:IsA("StringValue"), "Rollback source content missing")
   local source=ref.Value :: ModuleScript
   assert(source==resolve(path) and before.Value==patch.beforeSource and after.Value==patch.afterSource, "Source rollback identity/content scope mismatch")
   assert(source.Source==before.Value or source.Source==after.Value, "Unrelated source drift blocks rollback: "..tostring(record:GetAttribute("Path")))
   table.insert(rows,{source=source,before=before.Value})
  elseif record.Name=="CreatedOwner" then
   assert(record:IsA("ObjectValue"), "Rollback new-owner reference invalid")
   local owner=(record :: ObjectValue).Value
   if owner then
    assert(owner:IsA("ModuleScript") and owner.Source==PAYLOAD.newModule.source and owner:GetAttribute("CompactMapMigrationId")==MIGRATION and owner:GetAttribute("CompactMapSourceSHA256")==PAYLOAD.newModule.afterSHA256,"Unrelated new-owner drift blocks rollback")
    assert(owner:GetFullName()==PAYLOAD.newModule.path, "New compact source owner was relocated")
    created=owner :: ModuleScript
   end
  end
 end
 return rows,created
end
function API.ValidateRollback(journal: Folder): any
 local rows,created=rollbackRows(journal)
 return {passed=true,checkedOriginalSources=#rows,checkedNewOwners=if created then 1 else 0,sourceWrites=0,worldWrites=0}
end
function API.Rollback(journal: Folder): any
 local rows,created=rollbackRows(journal)
 local restored=0
 for _,row in rows do if row.source.Source~=row.before then row.source.Source=row.before;restored+=1 end end
 if created then
  local ref=journal:FindFirstChild("CreatedOwner") :: ObjectValue
  if ref then ref.Value=nil end
  created:Destroy()
 end
 for _,row in rows do assert(row.source.Source==row.before,"Rollback source readback mismatch") end
 journal:SetAttribute("Status","RolledBack")
 return {passed=true,restoredOriginalSources=restored,removedNewOwners=if created then 1 else 0,worldWrites=0,gameplayRequires=0}
end
function API.Apply(options: any): (any, Folder?)
 context()
 assert(type(options)=="table" and options.baselineVerified==true and options.nativeOwnerFitVerified==true,"Reviewed baseline and actual compact owner-fit proof required")
 local hash=options.verifiedPlanHash
 assert(type(hash)=="string" and #hash==64 and hash:match("^[0-9a-f]+$"),"Final verified plan hash required")
 local backupRoot=ServerStorage:FindFirstChild("MapCompactionBackups")
 local backup=backupRoot and backupRoot:FindFirstChild("CompactMap_V1_3fb9d9e8a543")
 assert(backup and backup:GetAttribute("BaselineManagedSHA256")==BASELINE,"Recoverable original map/source backup required")
 local map=workspace:FindFirstChild("MapBlockout");assert(map,"Canonical map missing")
 local mark=map:GetAttribute("CompactMapMigrationId");local desired=map:GetAttribute("CompactMapDesiredHash")
 assert(mark==nil or mark==MIGRATION,"Unknown active migration")
 assert(desired==nil or desired==hash,"Source patch plan differs from active map")
 local rows=existingRows();local parent,existing=newOwner();local changed=0
 for _,row in rows do if row.changed then changed+=1 end end
 if changed==0 and existing then
  API.Verify()
  return {created=0,updated=0,removed=0,retained=#PAYLOAD.patches+1,sourceWrites=0,worldWrites=0,status="Retained",gameplayRequires=0},nil
 end
 local fault=options.faultAfterSourceWrites
 assert(fault==nil or (type(fault)=="number" and fault%1==0 and fault>=1 and fault<=#PAYLOAD.patches+1),"Invalid rollback-test write count")
 local journal=Instance.new("Folder");journal.Name="CompactMapV1_SourceJournal_"..HttpService:GenerateGUID(false)
 journal:SetAttribute("MigrationId",MIGRATION);journal:SetAttribute("PlanHash",hash)
 journal:SetAttribute("BaselineManagedSHA256",BASELINE);journal:SetAttribute("Status","InProgress")
 for i,row in rows do if row.changed then journalRecord(journal,row,i) end end
 journal.Parent=ServerStorage
 local created: ModuleScript?=nil;local writes=0
 local function afterWrite()
  writes+=1
  if fault==writes then error("Injected owned source rollback check") end
 end
 local ok,reason=xpcall(function()
  if not existing then
   created=Instance.new("ModuleScript");created.Name="CompactMapGeometry"
   local ref=Instance.new("ObjectValue");ref.Name="CreatedOwner";ref.Value=created;ref.Parent=journal
   created.Source=PAYLOAD.newModule.source
   created:SetAttribute("CompactMapMigrationId",MIGRATION)
   created:SetAttribute("CompactMapSourceSHA256",PAYLOAD.newModule.afterSHA256)
   created.Parent=parent;afterWrite()
  end
  for _,row in rows do if row.changed then row.owner.Source=row.patch.afterSource;afterWrite() end end
  API.Verify()
 end,debug.traceback)
 if not ok then
  -- This reference is exclusively a newly allocated owner; remove even a partial creation.
  if created then
   local ref=journal:FindFirstChild("CreatedOwner") :: ObjectValue
   if ref then ref.Value=nil end
   created:Destroy();created=nil
  end
  local rollbackOK,rollbackResult=pcall(API.Rollback,journal)
  assert(rollbackOK,"Source transaction failed and rollback requires attention: "..tostring(reason).." / "..tostring(rollbackResult))
  journal:SetAttribute("Failure",tostring(reason):sub(1,2000))
  error("Compact source transaction rolled back: "..tostring(reason))
 end
 journal:SetAttribute("Status","SourcePrepared")
 return {created=if created then 1 else 0,updated=changed,removed=0,retained=#PAYLOAD.patches-changed+(if existing then 1 else 0),sourceWrites=writes,worldWrites=0,gameplayRequires=0,status="SourcePrepared",journalPath=journal:GetFullName(),exactSourceReadback=API.Verify()},journal
end
return table.freeze(API)
