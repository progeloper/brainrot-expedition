--!nocheck
-- Scoped rollback uses captured original identity, never replaces the map or player data.
local API={}
local H=game:GetService('HttpService');local CS=game:GetService('CollectionService')
local function context()
 assert(game:GetService('RunService'):IsStudio() and not game:GetService('RunService'):IsRunning(),'Edit rollback only')
 assert(game.PlaceId==91958083796436 and game.GameId==10548905405,'Wrong DEV')
end
local function decode(v)
 if type(v)~='table' or not v.type then return v end
 local a=v.value
 if v.type=='CFrame'then return CFrame.new(table.unpack(a))end
 if v.type=='Vector3' then return Vector3.new(table.unpack(a))end
 if v.type=='Vector2' then return Vector2.new(table.unpack(a))end
 if v.type=='Color3' then return Color3.new(table.unpack(a))end
 if v.type=='PhysicalProperties'then return PhysicalProperties.new(table.unpack(a))end
 if v.type=='EnumItem'then local group,name=a:match('^Enum%.([^%.]+)%.([^%.]+)$');return Enum[group][name]end
 error('Unsupported rollback value type '..tostring(v.type))
end
function API.Rollback(transaction,sourceAPI)
 context()
 assert(transaction and transaction:IsA('Folder') and transaction:GetAttribute('MigrationId')=='CompactMap_V1','Owned journal required')
 assert(transaction:GetAttribute('BaselineSHA256')=='3fb9d9e8a543cb80a034cf3fb96fbd118136a003ba829b14a13b2c3720894310','Original baseline mismatch')
 local backup=assert(game.ServerStorage.MapCompactionBackups:FindFirstChild('CompactMap_V1_3fb9d9e8a543'))
 local chunks=backup.BeforeManifest_JSON_Chunks:GetChildren();table.sort(chunks,function(a,b)return a.Name<b.Name end);local texts={};for _,c in chunks do table.insert(texts,c.Value)end
 local baseline=H:JSONDecode(table.concat(texts));local rows={}
 for _,group in {baseline.objects,baseline.externalStaticObjects}do for _,row in group do rows[row.key]=row end end
 local refs={};for _,ref in transaction.OriginalRefs:GetChildren()do
  assert(ref:IsA('ObjectValue') and ref.Value,'Rollback original identity missing');local key=ref:GetAttribute('OriginalKey');assert(type(key)=='string' and rows[key] and not refs[key],'Unknown or duplicate original reference');refs[key]=ref.Value
 end
 -- Preflight the complete captured topology before restoring sources or geometry.
 local parents={}
 for key,row in rows do
  local node=assert(refs[key],'Rollback baseline reference missing '..row.path)
  assert(node.Name==row.name and node.ClassName==row.class,'Rollback identity drift '..row.path)
  if rows[row.parent] then
   parents[key]=assert(refs[row.parent],'Rollback internal parent missing '..row.path)
  else
   assert(row.parent=='game/Workspace:Workspace[1]','Unknown captured external rollback parent '..row.path)
   parents[key]=game:GetService('Workspace')
  end
 end
 for _,record in transaction.MeshBackups:GetChildren()do if record:IsA('ObjectValue')then local original=record.Value;local clone=transaction.MeshBackups:FindFirstChild(record:GetAttribute('CloneName'));assert(original and original:IsA('MeshPart')and clone and clone:IsA('MeshPart'),'Rollback native mesh missing');assert(refs[record:GetAttribute('OriginalKey')]==original,'Rollback mesh is not an original owned identity')end end
 local created=transaction:FindFirstChild('CreatedRefs');if created then for _,ref in created:GetChildren()do assert(ref:IsA('ObjectValue'),'Created journal row invalid');if ref.Value then assert(ref.Value:GetAttribute('CompactMapMigrationId')=='CompactMap_V1','Unowned object in removal journal')end end end
 local sourceRef=transaction:FindFirstChild('SourceJournal');local sourceJournal=sourceRef and sourceRef.Value
 -- Check all managed source drift before restoring any geometry.
 if sourceJournal then assert(sourceAPI and sourceAPI.ValidateRollback,'Exact source rollback helper required');sourceAPI.ValidateRollback(sourceJournal);sourceAPI.Rollback(sourceJournal)end
 local restored=0
 for key,node in refs do
  local row=assert(rows[key],'Unrecognized rollback key')
  assert(node.Name==row.name and node.ClassName==row.class,'Rollback identity drift '..row.path)
  node.Parent=parents[key]
 end
 for key,node in refs do
  local row=rows[key]
  if node:IsA('Model') then
   node:ScaleTo(row.scale);node:PivotTo(decode(row.pivot))
  end
 end
 for _,record in transaction.MeshBackups:GetChildren()do
  if record:IsA('ObjectValue')then
   local original=assert(record.Value,"Required record.Value missing");local clone=assert(transaction.MeshBackups:FindFirstChild(record:GetAttribute('CloneName')))
   assert(original:IsA('MeshPart')and clone:IsA('MeshPart'),'Rollback native mesh identity invalid');original:ApplyMesh(clone)
  end
 end
 for key,node in refs do
  local row=rows[key]
  if row.properties then
   for _,name in {'CFrame','Size','PivotOffset','Anchored','CanCollide','CanQuery','CanTouch','CollisionGroup','Transparency','Reflectance','CastShadow','Material','MaterialVariant','Color','TopSurface','BottomSurface','LeftSurface','RightSurface','FrontSurface','BackSurface'}do
    local value=row.properties[name];if value~=nil and not(type(value)=='table'and value.unavailable)then node[name]=decode(value)end
   end
   node.CustomPhysicalProperties=if row.properties.CustomPhysicalProperties then decode(row.properties.CustomPhysicalProperties)else nil
  end
  if row.attachment and node:IsA('Attachment')then node.CFrame=decode(row.attachment.CFrame)end
  if row.value and node:IsA('StringValue')then node.Value=row.value.Value end
  for name in node:GetAttributes()do if row.attributes[name]==nil then node:SetAttribute(name,nil)end end
  for name,value in row.attributes do node:SetAttribute(name,decode(value))end
  for _,tag in CS:GetTags(node)do CS:RemoveTag(node,tag)end
  for _,tag in row.tags do CS:AddTag(node,tag)end
  node.Archivable=row.archivable;restored+=1
 end
 if created then for _,ref in created:GetChildren()do if ref:IsA('ObjectValue')and ref.Value then ref.Value:Destroy()end end end
 transaction:SetAttribute('Status','RolledBack')
 return {passed=true,restoredOriginalObjects=restored,ownedJournal=transaction:GetFullName(),playerDataWrites=0,protectedTemplateWrites=0}
end
return API
