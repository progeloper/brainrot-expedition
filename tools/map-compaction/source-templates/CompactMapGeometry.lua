--!strict
-- Read-only CompactMap_V1 runtime geometry. Values are final locals, never scaled again.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Geometry = {}
local MIGRATION = "CompactMap_V1"
local MAX_BYTES, MAX_WALLS, CELL_SIZE, MAX_CELLS = 200000, 512, 64, 8192
local SERVICE_SIZES = {AnnouncementStall={56,1,32},BrainrotTrainStall={56,1,32},BuyCartStall={64,1,40},KitStall={56,1,32},SellStall={56,1,32},WeaponHarpoonStall={56,1,32}}
local cache: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local function finite(v: any): boolean
 return type(v)=="number" and v==v and math.abs(v)<math.huge
end
local function number(v: any, label: string): number
 assert(finite(v), "Compact geometry finite number required: "..label)
 return v
end
local function positive(v: any, label: string): number
 local n=number(v,label);assert(n>0,"Compact geometry positive size required: "..label);return n
end
local function array(v: any, maximum: number, label: string): any
 assert(type(v)=="table","Compact geometry array required: "..label)
 local count=0
 for k in v do assert(type(k)=="number" and k%1==0 and k>=1 and k<=maximum,"Compact geometry dense bounded array required: "..label);count+=1 end
 assert(count==#v,"Compact geometry sparse array: "..label)
 for i=1,count do assert(v[i]~=nil,"Compact geometry missing array member: "..label) end
 return v
end
local function freeze(v: any): any
 if type(v)=="table" and not table.isfrozen(v) then for _,child in v do freeze(child) end;table.freeze(v) end
 return v
end
local function copy(v: any): any
 if type(v)~="table" then return v end
 local out={};for k,child in v do out[k]=copy(child) end;return out
end
local function rectangle(v: any, label: string): any
 assert(type(v)=="table","Compact geometry rectangle required: "..label)
 return {centreX=number(v.centreX,label..".centreX"),centreZ=number(v.centreZ,label..".centreZ"),width=positive(v.width,label..".width"),depth=positive(v.depth,label..".depth"),frontSign=v.frontSign}
end
function Geometry.Validate(raw: any): any
 assert(type(raw)=="table" and raw.schemaVersion==1 and raw.migrationId==MIGRATION,"Compact geometry schema mismatch")
 assert(raw.runtimeValidated==true,"Compact geometry must be validated before runtime")
 assert(type(raw.planHash)=="string" and #raw.planHash==64 and raw.planHash:match("^[0-9a-f]+$"),"Compact geometry plan hash required")
 assert(type(raw.bases)=="table","Compact geometry bases required")
 local bases,count={},0
 for id,g in raw.bases do
  count+=1;assert(type(id)=="string" and id:match("^Base_%d%d$"),"Compact geometry base ID invalid")
  assert(type(g)=="table","Compact geometry base row required")
  local z=array(g.zCenters,6,id..".zCenters");assert(#z==6,"Compact geometry needs six row centres")
  for i=1,6 do number(z[i],id..".zCenters");if i>1 then assert(z[i]>z[i-1],"Compact geometry row order invalid") end end
  local stride=z[2]-z[1]
  for i=3,6 do assert(math.abs((z[i]-z[i-1])-stride)<=1e-6,"Compact geometry row spacing must be uniform") end
  local slots=array(g.slots,12,id..".slots");assert(#slots==12,"Compact geometry needs twelve stable slots")
  local row={rowOffsetX=positive(g.rowOffsetX,id..".rowOffsetX"),formationCenterX=number(g.formationCenterX,id..".formationCenterX"),formationCenterZ=number(g.formationCenterZ,id..".formationCenterZ"),padNormalStuds=positive(g.padNormalStuds,id..".padNormalStuds"),padTangentialStuds=positive(g.padTangentialStuds,id..".padTangentialStuds"),support=rectangle(g.support,id..".support"),perimeter=rectangle(g.perimeter,id..".perimeter"),zCenters=copy(z),slots={}}
  assert(math.abs((z[1]+z[6])/2-row.formationCenterZ)<=1e-6,"Compact geometry formation centroid mismatch")
  row.perimeter.postWidth=positive(g.perimeter.postWidth,id..".perimeter.postWidth")
  row.perimeter.postDepth=positive(g.perimeter.postDepth,id..".perimeter.postDepth")
  assert(row.perimeter.width>2*row.perimeter.postWidth and row.perimeter.depth>2*row.perimeter.postDepth,"Compact perimeter is too small for posts")
  assert(row.perimeter.frontSign==nil or row.perimeter.frontSign==1 or row.perimeter.frontSign==-1,"Compact geometry front sign invalid")
  for i,slot in slots do
   local side=if i<=6 then -1 else 1;local station=if i<=6 then i else i-6
   assert(type(slot)=="table" and slot.Index==i and slot.Side==side,"Compact geometry stable slot identity/order changed")
   local x,sz=number(slot.X,id..".slotX"),number(slot.Z,id..".slotZ")
   assert(math.abs(x-(row.formationCenterX+side*row.rowOffsetX))<=1e-6 and math.abs(sz-z[station])<=1e-6,"Compact geometry uniform final slot local mismatch")
   assert(slot.PadNormalStuds==nil or math.abs(slot.PadNormalStuds-row.padNormalStuds)<=1e-6,"Compact geometry slot normal size mismatch")
   assert(slot.PadTangentialStuds==nil or math.abs(slot.PadTangentialStuds-row.padTangentialStuds)<=1e-6,"Compact geometry slot tangential size mismatch")
   assert(math.abs(x-row.support.centreX)+row.padNormalStuds/2<=row.support.width/2+.01 and math.abs(sz-row.support.centreZ)+row.padTangentialStuds/2<=row.support.depth/2+.01,"Compact geometry pad outside its support floor")
   row.slots[i]={Index=i,Side=side,X=x,Z=sz,PadNormalStuds=row.padNormalStuds,PadTangentialStuds=row.padTangentialStuds}
  end
  bases[id]=row
 end
 assert(count==12,"Compact geometry requires twelve bases")
 for i=1,12 do assert(bases[string.format("Base_%02d",i)],"Compact geometry base missing") end
 local services=Geometry.ValidateServices(raw.services)
 local walls=Geometry.ValidateWalls(raw.staticWallObstacles or {})
 return freeze({schemaVersion=1,migrationId=MIGRATION,planHash=raw.planHash,bases=bases,services=services,staticWallObstacles=walls})
end
function Geometry.ValidateServices(raw: any): any
 assert(type(raw)=="table","Compact geometry services required")
 local out,count={},0
 for id,row in raw do
  count+=1;local expected=SERVICE_SIZES[id]
  assert(expected and type(row)=="table","Compact geometry service identity invalid")
  local size=array(row.logicalInteractionEnvelope,3,"service.logicalInteractionEnvelope")
  assert(#size==3,"Compact geometry service interaction envelope needs three dimensions")
  for i=1,3 do assert(positive(size[i],"service.logicalInteractionEnvelope")==expected[i],"Compact service logical interaction envelope changed") end
  out[id]={logicalInteractionEnvelope=copy(size)}
 end
 assert(count==6,"Compact geometry needs six stable services")
 for id in SERVICE_SIZES do assert(out[id],"Compact geometry service missing") end
 return freeze(out)
end
function Geometry.ValidateWalls(raw: any): any
 local rows=array(raw,MAX_WALLS,"staticWallObstacles");local seen,out={},{}
 for _,row in rows do
  assert(type(row)=="table" and type(row.id)=="string" and #row.id>0 and #row.id<=128 and not seen[row.id],"Compact static wall ID invalid/duplicate")
  local r={id=row.id,minX=number(row.minX,"wall.minX"),maxX=number(row.maxX,"wall.maxX"),minY=number(row.minY,"wall.minY"),maxY=number(row.maxY,"wall.maxY"),minZ=number(row.minZ,"wall.minZ"),maxZ=number(row.maxZ,"wall.maxZ")}
  assert(r.minX<r.maxX and r.minY<r.maxY and r.minZ<r.maxZ,"Compact static wall bounds invalid")
  seen[r.id]=true;table.insert(out,r)
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return freeze(out)
end
function Geometry.Read(map: Instance?): any?
 if map==nil then return nil end
 local migration,status,hash=map:GetAttribute("CompactMapMigrationId"),map:GetAttribute("CompactMapStatus"),map:GetAttribute("CompactMapDesiredHash")
 local value=map:FindFirstChild("CompactMapRuntimeGeometry")
 if migration==nil and status==nil and hash==nil and value==nil then return nil end
 assert(migration==MIGRATION and status=="Completed","Compact geometry is incomplete or has an unknown migration")
 assert(value and value:IsA("StringValue") and #value.Value<=MAX_BYTES,"Compact runtime geometry missing/oversize")
 local saved=cache[map]
 if saved then
  assert(saved.value==value and saved.hash==hash and saved.text==value.Value,"Compact runtime geometry changed during session; restart required")
  return saved.data
 end
 local raw=HttpService:JSONDecode(value.Value);local data=Geometry.Validate(raw)
 assert(data.planHash==hash,"Compact runtime geometry desired hash mismatch")
 cache[map]={value=value,hash=hash,text=value.Value,data=data}
 return data
end
function Geometry.ResolveBase(base: Model): any?
 local ancestor: Instance?=base.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(base:GetAttribute("CompactMapMigrationId")==nil,"Compact base has no canonical map owner")
  return nil
 end
 local data=Geometry.Read(ancestor);if data==nil then return nil end
 local id=base:GetAttribute("BaseId");assert(type(id)=="string" and data.bases[id],"Compact base ID has no canonical geometry")
 return data.bases[id]
end
function Geometry.ResolveInteractionSize(part: BasePart): Vector3
 assert(part and part:IsA("BasePart"),"Service interaction requires a BasePart")
 local ancestor: Instance?=part.Parent
 while ancestor and ancestor.Name~="MapBlockout" do ancestor=ancestor.Parent end
 if ancestor==nil then
  assert(part:GetAttribute("CompactMapMigrationId")==nil,"Compact service has no canonical map owner")
  return part.Size
 end
 local data=Geometry.Read(ancestor);if data==nil then return part.Size end
 local patches=ancestor:FindFirstChild("ServiceStallPatches")
 assert(patches and part.Parent==patches and part:GetAttribute("LayoutRole")=="ServiceStall","Compact service identity/owner changed")
 local row=data.services[part.Name];assert(row,"Compact service has no canonical logical envelope")
 local size=part:GetAttribute("LogicalInteractionEnvelope")
 assert(typeof(size)=="Vector3" and finite(size.X) and finite(size.Y) and finite(size.Z),"Compact service logical interaction envelope missing/invalid")
 local expected=row.logicalInteractionEnvelope
 assert(math.abs(size.X-expected[1])<=1e-6 and math.abs(size.Y-expected[2])<=1e-6 and math.abs(size.Z-expected[3])<=1e-6,"Compact service logical interaction envelope drifted")
 return size
end
function Geometry.Current(): any? return Geometry.Read(Workspace:FindFirstChild("MapBlockout")) end
local function key(x: number,z: number): string return tostring(x)..":"..tostring(z) end
function Geometry.BuildWallIndex(raw: any): any
 local rows=Geometry.ValidateWalls(raw);local cells,count={},0
 for _,row in rows do
  local nx=math.floor(row.maxX/CELL_SIZE)-math.floor(row.minX/CELL_SIZE)+1
  local nz=math.floor(row.maxZ/CELL_SIZE)-math.floor(row.minZ/CELL_SIZE)+1
  assert(nx*nz<=MAX_CELLS,"Compact wall mask single row cell budget exceeded")
  for x=math.floor(row.minX/CELL_SIZE),math.floor(row.maxX/CELL_SIZE) do
   for z=math.floor(row.minZ/CELL_SIZE),math.floor(row.maxZ/CELL_SIZE) do
    local k=key(x,z);if cells[k]==nil then cells[k]={};count+=1;assert(count<=MAX_CELLS,"Compact wall mask cell budget exceeded") end
    table.insert(cells[k],row)
   end
  end
 end
 return freeze({rows=rows,cells=cells,cellSize=CELL_SIZE})
end
function Geometry.WallHit(index: any,frame: CFrame,size: Vector3,padding: number?): string?
 assert(type(index)=="table" and index.cellSize==CELL_SIZE,"Compact wall index required")
 assert(typeof(frame)=="CFrame" and typeof(size)=="Vector3","Compact wall envelope types invalid")
 for _,v in {frame:GetComponents()} do assert(finite(v),"Compact wall envelope frame invalid") end
 assert(finite(size.X) and finite(size.Y) and finite(size.Z) and size.X>0 and size.Y>0 and size.Z>0,"Compact wall envelope size invalid")
 local p=padding or 0;assert(finite(p) and p>=0,"Compact wall mask padding invalid")
 local half=size*.5
 local ex=math.abs(frame.RightVector.X)*half.X+math.abs(frame.UpVector.X)*half.Y+math.abs(frame.LookVector.X)*half.Z
 local ey=math.abs(frame.RightVector.Y)*half.X+math.abs(frame.UpVector.Y)*half.Y+math.abs(frame.LookVector.Y)*half.Z
 local ez=math.abs(frame.RightVector.Z)*half.X+math.abs(frame.UpVector.Z)*half.Y+math.abs(frame.LookVector.Z)*half.Z
 local x0,x1,z0,z1=frame.X-ex-p,frame.X+ex+p,frame.Z-ez-p,frame.Z+ez+p
 local y0,y1=frame.Y-ey,frame.Y+ey;local seen={}
 local nx=math.floor(x1/CELL_SIZE)-math.floor(x0/CELL_SIZE)+1
 local nz=math.floor(z1/CELL_SIZE)-math.floor(z0/CELL_SIZE)+1
 assert(finite(nx*nz) and nx*nz<=MAX_CELLS,"Compact wall query cell budget exceeded")
 for x=math.floor(x0/CELL_SIZE),math.floor(x1/CELL_SIZE) do
  for z=math.floor(z0/CELL_SIZE),math.floor(z1/CELL_SIZE) do
   for _,wall in index.cells[key(x,z)] or {} do
    if seen[wall.id] then continue end;seen[wall.id]=true
    if x0<wall.maxX and x1>wall.minX and z0<wall.maxZ and z1>wall.minZ and y0<wall.maxY and y1>wall.minY then return wall.id end
   end
  end
 end
 return nil
end
return table.freeze(Geometry)
