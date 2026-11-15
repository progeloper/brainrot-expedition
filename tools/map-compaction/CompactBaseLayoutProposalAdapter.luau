local P={}
function P.Create(deps)
local geometry=assert(loadstring([[--!strict
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
]],"@ProposedCompactGeometry"))()
local confChunk=assert(loadstring([[--!strict

local CompactMapGeometry = injectedGeometry

-- The 36-by-32-stud footprint is a project visual estimate derived from the
-- compact reference layout, not an official published dimension.
local BaseLayoutConfig = {
	STANDARD_ROBLOX_PLAYER_HEIGHT_STUDS = 5.0,
	BRAINROT_TARGET_VISIBLE_HEIGHT_STUDS = 3.5,
	PLATFORM_DIAGONAL_STUDS = 3.0,
	PLATFORM_SIDE_STUDS = 3 / math.sqrt(2),

	BASE_FOOTPRINT_WIDTH_STUDS = 36,
	BASE_FOOTPRINT_DEPTH_STUDS = 32,
	BASE_WALL_HEIGHT_STUDS = 10,
	BASE_WALL_THICKNESS_STUDS = 1,
	PLATFORM_COUNT = 12,
	PLATFORMS_PER_SIDE = 6,
	PLATFORM_ROW_OFFSET_X = 7.25,
	PLATFORM_Z_CENTERS = table.freeze({ -11.25, -6.75, -2.25, 2.25, 6.75, 11.25 }),

	PLAQUE_INWARD_DEPTH_STUDS = 1.75,
	PLAQUE_TANGENTIAL_WIDTH_STUDS = 3.0,
	PLAQUE_HEIGHT_STUDS = 0.20,
	PLAQUE_PLATFORM_GAP_STUDS = 0.25,
	PLAQUE_VISIBLE_RISE_STUDS = 0.03,
	-- The visible plaque remains flush and non-colliding. This invisible vertical
	-- contact envelope reaches ordinary avatar feet, which rest above the floor.
	PLAQUE_TOUCH_HEIGHT_STUDS = 1.0,
	PLAQUE_TOUCH_COOLDOWN_SECONDS = 0.5,
}

-- Compact values are final evaluated locals; all original scale/economy constants remain unchanged.
function BaseLayoutConfig.GetGeometry(base: Model): any?
	return CompactMapGeometry.ResolveBase(base)
end

return table.freeze(BaseLayoutConfig)
]],"@ProposedBaseLayoutConfig"))
setfenv(confChunk,setmetatable({injectedGeometry=geometry},{__index=getfenv(0)}))
local config=confChunk();local localDeps={Config=config,Material=deps.Material}
local layout=assert(loadstring([[return function(deps)
local Config,StaticMaterial=deps.Config,deps.Material
local PLAQUE_TAG = "BrainrotIncomePlaque"
local LAYOUT_CONTAINER_NAME = "Phase5DInterior"
local PLAQUE_CONTAINER_NAME = "IncomePlaques"
local TOUCH_SENSOR_NAME = "TouchSensor"
local AMOUNT_SURFACE_NAME = "AmountSurfaceGui"
local AMOUNT_LABEL_NAME = "AmountLabel"
local AMOUNT_STROKE_NAME = "AmountStroke"
local PLAQUE_WIDTH_STUDS = 3.5
local PLAQUE_THICKNESS_STUDS = 0.18
local PLAQUE_DEPTH_STUDS = 2.25
local PLAQUE_PLATFORM_GAP_STUDS = 0.55
local PLAQUE_FLOOR_CLEARANCE_STUDS = 0.02
local PLAQUE_SNAPSHOT_REFRESH_SECONDS = 1
local PILLAR_MANAGED_BY = "BaseIncomePlaqueSystem"
local PILLAR_ORIGINAL_WIDTH_STUDS = 1.25
local PILLAR_ORIGINAL_DEPTH_STUDS = 1.25
local PILLAR_WIDTH_STUDS = PILLAR_ORIGINAL_WIDTH_STUDS * 0.5
local PILLAR_DEPTH_STUDS = PILLAR_ORIGINAL_DEPTH_STUDS * 0.5
local PILLAR_MAX_SPACING_STUDS = 6
local ENTRANCE_CLEAR_WIDTH_STUDS = 10
local LEGACY_WALL_NAMES = table.freeze({ "LeftWall", "RightWall", "BackWall" })

type StructuralStyle = {
	PostWidth: number?,
	PostDepth: number?,
	Color: Color3,
	Material: Enum.Material,
	MaterialVariant: string,
	EffectivePhysicalProperties: PhysicalProperties,
	CollisionGroup: string,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}
local function platformIdFromPart(platform: BasePart): number?
	local attribute = platform:GetAttribute("SlotIndex")
	if type(attribute) == "number" and attribute % 1 == 0 then
		return attribute
	end
	return tonumber(platform.Name:match("^Slot_(%d+)$"))
end

local function baseRootCFrame(base: Model): CFrame
	local saved = base:GetAttribute("Phase5DLayoutPivot")
	if typeof(saved) == "CFrame" then
		return saved
	end
	local root = base:GetPivot()
	base:SetAttribute("Phase5DLayoutPivot", root)
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePart(base: Model, container: Folder, name: string): (BasePart, boolean)
	local existing = base:FindFirstChild(name) or container:FindFirstChild(name)
	if existing then
		assert(existing:IsA("BasePart"), name .. " must be a BasePart")
		return existing, false
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = container
	return part, true
end

local function configureStructuralPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	StaticMaterial.Apply(part, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(91, 98, 104)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function platformTopLocalY(root: CFrame, platform: BasePart): number
	return root:PointToObjectSpace(platform.Position).Y + platform.Size.Y / 2
end

local function entranceSign(base: Model, root: CFrame): number
	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local marker = base:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then
			local localZ = root:PointToObjectSpace(marker.Position).Z
			if math.abs(localZ) > 0.01 then
				return if localZ > 0 then 1 else -1
			end
		end
	end
	return -1
end

local function captureStructuralStyle(part: BasePart): StructuralStyle
	return {
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
		EffectivePhysicalProperties = part.CurrentPhysicalProperties,
		CollisionGroup = part.CollisionGroup,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
	}
end

local function legacyWall(base: Model, container: Folder, name: string): BasePart?
	local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function removeLegacyWalls(base: Model, container: Folder)
	for _, name in LEGACY_WALL_NAMES do
		local direct = base:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			direct:Destroy()
		end
		local generated = container:FindFirstChild(name)
		if generated and generated:IsA("BasePart") then
			generated:Destroy()
		end
	end
end

local function clearManagedPillars(container: Folder)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ManagedBy") == PILLAR_MANAGED_BY then
			child:Destroy()
		end
	end
end

local function createPillar(
	container: Folder,
	root: CFrame,
	name: string,
	localPosition: Vector3,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle
)
	local pillar = Instance.new("Part")
	pillar.Name = name
	pillar:SetAttribute("ManagedBy", PILLAR_MANAGED_BY)
	configureStructuralPart(pillar)
	pillar.Size = Vector3.new(style.PostWidth or PILLAR_WIDTH_STUDS, pillarHeight, style.PostDepth or PILLAR_DEPTH_STUDS)
	pillar.CFrame = root
		* CFrame.new(localPosition.X, floorTopY + pillarHeight / 2, localPosition.Z)
	pillar.Color = style.Color
	pillar.Material = style.Material
	pillar.MaterialVariant = style.MaterialVariant
	pillar.CustomPhysicalProperties = style.EffectivePhysicalProperties
	pillar.CollisionGroup = style.CollisionGroup
	pillar.CanCollide = style.CanCollide
	pillar.CanTouch = style.CanTouch
	pillar.CanQuery = style.CanQuery
	StaticMaterial.Apply(pillar)
	pillar.Parent = container
end

local function createPillarsAlongEdge(
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	edgeName: string,
	startLocalPosition: Vector3,
	endLocalPosition: Vector3,
	shouldSkip: ((Vector3) -> boolean)?
)
	local edgeLength = (endLocalPosition - startLocalPosition).Magnitude
	local intervalCount = math.max(1, math.ceil(edgeLength / PILLAR_MAX_SPACING_STUDS))
	local placedIndex = 0
	for interval = 1, intervalCount - 1 do
		local localPosition = startLocalPosition:Lerp(endLocalPosition, interval / intervalCount)
		if not shouldSkip or not shouldSkip(localPosition) then
			placedIndex += 1
			createPillar(
				container,
				root,
				string.format("BasePillar_%s_%02d", edgeName, placedIndex),
				localPosition,
				floorTopY,
				pillarHeight,
				style
			)
		end
	end
end

local function createPerimeterPillars(
	base: Model,
	container: Folder,
	root: CFrame,
	floorTopY: number,
	pillarHeight: number,
	style: StructuralStyle,
	geometry: any?
)
	clearManagedPillars(container)
	-- Preserve the established perimeter centreline while reducing only each
	-- pillar's horizontal cross-section.
	local perimeter = if geometry then geometry.perimeter else nil
	local width = if perimeter then perimeter.width else Config.BASE_FOOTPRINT_WIDTH_STUDS
	local depth = if perimeter then perimeter.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	local centreX = if perimeter then perimeter.centreX else 0
	local centreZ = if perimeter then perimeter.centreZ else 0
	local postWidth = if perimeter then perimeter.postWidth else PILLAR_WIDTH_STUDS
	local postDepth = if perimeter then perimeter.postDepth else PILLAR_DEPTH_STUDS
	style = table.clone(style)
	style.PostWidth = postWidth
	style.PostDepth = postDepth
	local halfWidth = (width - (if perimeter then postWidth * 2 else PILLAR_ORIGINAL_WIDTH_STUDS)) / 2
	local halfDepth = (depth - (if perimeter then postDepth * 2 else PILLAR_ORIGINAL_DEPTH_STUDS)) / 2
	local frontSign = if perimeter and perimeter.frontSign then perimeter.frontSign else entranceSign(base, root)
	local frontZ = centreZ + frontSign * halfDepth
	local backZ = centreZ - frontSign * halfDepth
	local frontLeft = Vector3.new(centreX - halfWidth, 0, frontZ)
	local frontRight = Vector3.new(centreX + halfWidth, 0, frontZ)
	local backLeft = Vector3.new(centreX - halfWidth, 0, backZ)
	local backRight = Vector3.new(centreX + halfWidth, 0, backZ)

	for name, localPosition in
		{
			BasePillar_Corner_FL = frontLeft,
			BasePillar_Corner_FR = frontRight,
			BasePillar_Corner_BL = backLeft,
			BasePillar_Corner_BR = backRight,
		}
	do
		createPillar(container, root, name, localPosition, floorTopY, pillarHeight, style)
	end

	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Front",
		frontLeft,
		frontRight,
		function(localPosition)
			return math.abs(localPosition.X - centreX) < ENTRANCE_CLEAR_WIDTH_STUDS / 2
		end
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Back",
		backLeft,
		backRight,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Left",
		frontLeft,
		backLeft,
		nil
	)
	createPillarsAlongEdge(
		container,
		root,
		floorTopY,
		pillarHeight,
		style,
		"Right",
		frontRight,
		backRight,
		nil
	)
end

local function ensureInterior(base: Model, root: CFrame, platformFloorY: number, geometry: any?): number
	local container = ensureFolder(base, LAYOUT_CONTAINER_NAME)
	local floor: BasePart? = nil
	if geometry then
		-- Compact support reuses the migrated authoritative Foundation. No coplanar runtime floor.
		local foundation = base:FindFirstChild("Foundation")
		assert(foundation and foundation:IsA("BasePart") and foundation:GetAttribute("LayoutRole") == "Foundation", "Compact base Foundation is missing or has changed identity")
		floor = foundation :: BasePart
	else
		for _, name in { "BaseFloor", "Floor", "InteriorFloor", "GroundFloor" } do
			local candidate = base:FindFirstChild(name) or container:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") then
				floor = candidate
				break
			end
		end
	end
	local createdFloor = false
	if not floor then
		floor, createdFloor = ensurePart(base, container, "BaseFloor")
	end
	local resolvedFloor = floor :: BasePart
	local floorThickness = if createdFloor then 1 else math.max(resolvedFloor.Size.Y, 0.2)
	local floorTopY = if createdFloor
		then platformFloorY
		else platformTopLocalY(root, resolvedFloor)
	if geometry then
		-- Retain the authoritative Foundation colour, flags and effective physics.
		StaticMaterial.Apply(resolvedFloor)
	else
		configureStructuralPart(resolvedFloor)
	end
	local support = if geometry then geometry.support else nil
	resolvedFloor.Size = Vector3.new(
		if support then support.width else Config.BASE_FOOTPRINT_WIDTH_STUDS,
		floorThickness,
		if support then support.depth else Config.BASE_FOOTPRINT_DEPTH_STUDS
	)
	resolvedFloor.CFrame = root * CFrame.new(
		if support then support.centreX else 0, floorTopY - floorThickness / 2,
		if support then support.centreZ else 0
	)

	local pillarStyle = captureStructuralStyle(resolvedFloor)
	local pillarHeight = Config.BASE_WALL_HEIGHT_STUDS
	for _, wallName in LEGACY_WALL_NAMES do
		local wall = legacyWall(base, container, wallName)
		if wall then
			pillarStyle = captureStructuralStyle(wall)
			pillarHeight = wall.Size.Y
			break
		end
	end
	removeLegacyWalls(base, container)
	createPerimeterPillars(base, container, root, floorTopY, pillarHeight, pillarStyle, geometry)
	return floorTopY
end

local function setMarkerFacing(slot: any, platformCFrame: CFrame, markerOffset: CFrame)
	if slot.Marker:IsA("Attachment") then
		slot.Marker.CFrame = CFrame.new(markerOffset.Position)
	else
		local marker = slot.Marker :: BasePart
		marker.CFrame = platformCFrame * CFrame.new(markerOffset.Position)
	end
end

local function positionPlatforms(root: CFrame, slots: { any }, geometry: any?): (any, number)
	local ordered = table.clone(slots)
	table.sort(ordered, function(left, right)
		return left.Index < right.Index
	end)
	assert(#ordered == Config.PLATFORM_COUNT, "Phase 5D requires exactly 12 platforms")
	local placementById = {}
	local floorY = math.huge
	for order, slot in ordered do
		local platform = slot.Platform :: BasePart
		local platformId = platformIdFromPart(platform)
		assert(platformId == slot.Index, "Platform stable ID changed during layout")
		local topY = platformTopLocalY(root, platform)
		floorY = math.min(floorY, topY - platform.Size.Y)
		local side = if order <= Config.PLATFORMS_PER_SIDE then -1 else 1
		local row = if side < 0 then order else order - Config.PLATFORMS_PER_SIDE
		local canonical = if geometry then geometry.slots[slot.Index] else nil
		assert(not canonical or (canonical.Index == slot.Index and canonical.Side == side), "Compact stable slot identity changed")
		local x = if canonical then canonical.X else side * Config.PLATFORM_ROW_OFFSET_X
		local z = if canonical then canonical.Z else Config.PLATFORM_Z_CENTERS[row]
		local normalSize = if canonical then canonical.PadNormalStuds else Config.PLATFORM_SIDE_STUDS
		local tangentSize = if canonical then canonical.PadTangentialStuds else Config.PLATFORM_SIDE_STUDS
		local aisleX = if geometry then geometry.formationCenterX else 0
		local localPosition = Vector3.new(x, topY - platform.Size.Y / 2, z)
		local localFacing = CFrame.lookAt(
			localPosition,
			Vector3.new(aisleX, localPosition.Y, localPosition.Z),
			Vector3.yAxis
		)
		local markerOffset = if slot.Marker:IsA("Attachment")
			then slot.Marker.CFrame
			else platform.CFrame:ToObjectSpace((slot.Marker :: BasePart).CFrame)
		platform.Size =
			Vector3.new(tangentSize, platform.Size.Y, normalSize)
		platform.CFrame = root * localFacing
		platform.Anchored = true
		setMarkerFacing(slot, platform.CFrame, markerOffset)
		placementById[slot.Index] = {
			Side = side,
			XCenter = x,
			ZCenter = z,
			PlatformNormalStuds = normalSize,
			PlatformTopY = topY,
		}
	end
	assert(floorY < math.huge, "Phase 5D platforms have no usable floor datum")
	return placementById, floorY
end
local function getPlaqueName(platformId: number): string
	return "IncomePlaque_" .. tostring(platformId)
end
local function configurePlaque(
	state: any,
	plaque: BasePart,
	platformId: number,
	placement: any,
	floorTopY: number
)
	plaque.Name = getPlaqueName(platformId)
	plaque.Size = Vector3.new(PLAQUE_WIDTH_STUDS, PLAQUE_THICKNESS_STUDS, PLAQUE_DEPTH_STUDS)
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.CanTouch = false
	plaque.CanQuery = true
	plaque.Massless = true
	plaque.Color = Color3.fromRGB(60, 255, 90)
	plaque.Transparency = 0
	StaticMaterial.Apply(plaque, Enum.Material.SmoothPlastic)
	plaque.TopSurface = Enum.SurfaceType.Smooth
	plaque.BottomSurface = Enum.SurfaceType.Smooth
	local inward = placement.PlatformNormalStuds / 2
		+ PLAQUE_PLATFORM_GAP_STUDS
		+ PLAQUE_DEPTH_STUDS / 2
	local plaqueX = placement.XCenter - placement.Side * inward
	local plaqueY = floorTopY + PLAQUE_FLOOR_CLEARANCE_STUDS + PLAQUE_THICKNESS_STUDS / 2
	local plaquePosition =
		state.Root:PointToWorldSpace(Vector3.new(plaqueX, plaqueY, placement.ZCenter))
	local inwardDirection = state.Root:VectorToWorldSpace(Vector3.new(-placement.Side, 0, 0))
	local levelInward = Vector3.new(inwardDirection.X, 0, inwardDirection.Z).Unit
	plaque.CFrame = CFrame.lookAt(plaquePosition, plaquePosition + levelInward, Vector3.yAxis)

	-- The contact envelope follows this pad, not a second offset layout.
	local claimSensorCFrame = plaque.CFrame
		* CFrame.new(0, PLAQUE_THICKNESS_STUDS / 2 + Config.PLAQUE_TOUCH_HEIGHT_STUDS / 2, 0)
 return claimSensorCFrame
end
return {Apply=function(base,slots)local root=baseRootCFrame(base);local geometry=assert(Config.GetGeometry(base));local placements,floorY=positionPlatforms(root,slots,geometry);return root,placements,ensureInterior(base,root,floorY,geometry)end,ConfigurePlaqueGeometry=configurePlaque}

end]],"@ProposedBaseOwnerGeometry"))()(localDeps)
return{Config=config,Geometry=geometry,Layout=layout,PlaqueDepth=2.25}
end
return P
