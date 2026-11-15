-- One-time Studio Command Bar builder. Run in Edit mode; never install as a runtime Script.
-- Expands the existing five-by-five layout and adds the authored twelve-player Camp.
local CAMP_SIZE, FLOOR_THICKNESS = 864, 4
local MAIN_WIDTH, SECONDARY_WIDTH, CAMP_ROAD_WIDTH, SPINE_WIDTH = 48, 32, 64, 40
local BORDER, OVERLAY_THICKNESS, OVERLAY_RISE = 2, 0.05, 0.03
local FLOOR_OWNER, PATH_OWNER, CAMP_OWNER = "CreateBasicMap_v1", "CreateBasicMapPaths_v1", "CreateBasicCamp_v1"
local Http = game:GetService("HttpService")
assert(not game:GetService("RunService"):IsRunning(), "Run this builder in Studio Edit mode.")
local root = assert(workspace:FindFirstChild("MapBlockout"), "Existing MapBlockout is required.")
local camp = root.Camp.Floor_R3_C3
assert(camp.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999999, "Camp must be horizontal.")
FLOOR_THICKNESS = camp.Size.Y
local frame = camp.CFrame * CFrame.new(0, FLOOR_THICKNESS / 2, 0)
local groundGroup = camp.CollisionGroup

-- Outer bands begin at 1.25x the original 256x192 cells. The middle row/column
-- must accommodate Camp, preserving the exact existing region adjacency.
-- Do not derive another 1.25x scale from already-expanded floors on subsequent runs.
local xEdges = {-1072, -752, -432, 432, 752, 1072}
local zEdges = {-912, -672, -432, 432, 672, 912}
local layout = {
	{"Beach", "Beach", "Forest", "Arctic", "Arctic"},
	{"Beach", "Forest", "Forest", "Arctic", "Volcano"},
	{"Beach", "Forest", "Camp", "Volcano", "Volcano"},
	{"Swamp", "Swamp", "Jungle", "Glitch Zone", "Glitch Zone"},
	{"Swamp", "Jungle", "Jungle", "Glitch Zone", "Glitch Zone"},
}
local palette = {
	Beach = "FFD166", Forest = "78D84B", Swamp = "3B8076", Jungle = "16A05D",
	Arctic = "C5F6FF", Volcano = "B34732", ["Glitch Zone"] = "9955EE", Camp = "BE8956",
}
local originalBounds = {
	Beach = {512,576}, Forest = {512,576}, Swamp = {512,384}, Jungle = {512,384},
	Arctic = {512,384}, Volcano = {512,384}, ["Glitch Zone"] = {512,384}, Camp = {256,192},
}
local specs, models, roads, reservations, regions = {}, {}, {}, {}, {}
local function part(parent, name, size, cf, colour, material, role, owner, class, attributes)
	table.insert(specs, {parent=parent, name=name, size=size, cf=cf, colour=colour,
		material=material or Enum.Material.SmoothPlastic, role=role, owner=owner,
		class=class or "Part", attributes=attributes or {}})
end
local function pathRect(x1,z1,x2,z2,category)
	assert(x2>x1 and z2>z1, "Empty path rectangle.")
	table.insert(roads,{x1=x1,z1=z1,x2=x2,z2=z2,category=category})
end
local function square(x,z,size,category)
	pathRect(x-size/2,z-size/2,x+size/2,z+size/2,category)
end
local function route(points,width,category)
	for i=1,#points-1 do
		local a,b=points[i],points[i+1]
		assert(a[1]==b[1] or a[2]==b[2], "Use authored right-angle segments.")
		if a[1]==b[1] then
			pathRect(a[1]-width/2,math.min(a[2],b[2]),a[1]+width/2,math.max(a[2],b[2]),category)
		else
			pathRect(math.min(a[1],b[1]),a[2]-width/2,math.max(a[1],b[1]),a[2]+width/2,category)
		end
	end
	for _,p in ipairs(points) do square(p[1],p[2],width,category) end
end
local function localRect(base,x1,z1,x2,z2)
	local loX,loZ,hiX,hiZ=math.huge,math.huge,-math.huge,-math.huge
	for _,x in ipairs({x1,x2}) do for _,z in ipairs({z1,z2}) do
		local p=base:PointToWorldSpace(Vector3.new(x,0,z))
		loX,loZ,hiX,hiZ=math.min(loX,p.X),math.min(loZ,p.Z),math.max(hiX,p.X),math.max(hiZ,p.Z)
	end end
	-- Cardinal rotations should not introduce tiny sliver Parts.
	return math.round(loX*1000)/1000,math.round(loZ*1000)/1000,math.round(hiX*1000)/1000,math.round(hiZ*1000)/1000
end
for row,cells in ipairs(layout) do for col,name in ipairs(cells) do
	local x1,x2,z1,z2=xEdges[col],xEdges[col+1],zEdges[row],zEdges[row+1]
	part(name,string.format("Floor_R%d_C%d",row,col),Vector3.new(x2-x1,FLOOR_THICKNESS,z2-z1),
		frame*CFrame.new((x1+x2)/2,-FLOOR_THICKNESS/2,(z1+z2)/2),palette[name],nil,"Floor",FLOOR_OWNER,
		nil,{CellId=string.format("Floor_R%d_C%d",row,col)})
	local r=regions[name] or {x1=x1,x2=x2,z1=z1,z2=z2,area=0}
	r.x1,r.x2,r.z1,r.z2=math.min(r.x1,x1),math.max(r.x2,x2),math.min(r.z1,z1),math.max(r.z2,z2)
	r.area+=(x2-x1)*(z2-z1);regions[name]=r
end end

-- Existing regional loop, with its destinations retained in the expanded grid.
local loop={{-592,-552},{-912,-552},{-912,552},{-592,552},{-592,792},{0,792},
	{0,552},{752,552},{752,0},{912,0},{912,-792},{0,-792},{0,-552}}
local closed=table.clone(loop);table.insert(closed,loop[1])
route(closed,MAIN_WIDTH,"Regional")
for _,p in ipairs(loop) do square(p[1],p[2],72,"Regional") end

-- Four-sided Camp circulation: outer edge 224, inner edge 160.
route({{-192,-192},{192,-192},{192,192},{-192,192},{-192,-192}},CAMP_ROAD_WIDTH,"Circulation")
pathRect(-SPINE_WIDTH/2,-160,SPINE_WIDTH/2,160,"Spine")
-- Small rectilinear steps follow the diagonal corner corridors. Their swept
-- diagonal width is at least 2*sqrt(2)*(28-4) = 67.88 studs, exceeding 64.
-- All exposed edges, including these corners, are joined by the overlay union below.
for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
	for d=192,392,8 do square(sx*d,sz*d,56,"Circulation") end
	square(sx*396,sz*396,64,"Circulation")
end end
route({{-396,-396},{-592,-396},{-592,-552}},64,"Circulation")
route({{396,-396},{912,-396}},64,"Circulation")
route({{396,396},{752,396}},64,"Circulation")
route({{-396,396},{-396,552},{0,552}},64,"Circulation")

-- Shared hunting spaces: flat path-colour clearings, with no encounter systems.
local clearings = {
	Beach={{-912,-256},{-912,144}},
	Forest={{-592,160},{-160,-552},{160,-792}},
	Swamp={{-912,552},{-592,552}},
	Jungle={{-592,792},{0,792},{0,552}},
	Arctic={{560,-792},{912,-792},{592,-552}},
	Volcano={{912,-320},{752,0},{752,288}},
	["Glitch Zone"]={{560,552},{928,552},{752,784}},
}
for _,list in pairs(clearings) do for _,p in ipairs(list) do square(p[1],p[2],120,"Regional") end end
route({{-592,-552},{-592,552}},MAIN_WIDTH,"Regional")
route({{592,-792},{592,-552}},MAIN_WIDTH,"Regional")
route({{752,552},{928,552}},MAIN_WIDTH,"Regional")
route({{752,552},{752,784}},MAIN_WIDTH,"Regional")
local bypasses = {
	{{-912,-256},{-1008,-256},{-1008,144},{-912,144}},
	{{-160,-552},{-160,-792},{160,-792}},
	{{-592,-396},{-688,-396},{-688,160},{-592,160}},
	{{-912,552},{-912,792},{-816,792},{-816,648},{-592,648},{-592,552}},
	{{-592,792},{-336,792},{-336,552},{0,552}},
	{{592,-552},{688,-552},{688,-792}},
	{{912,-320},{1008,-320},{1008,288},{752,288}},
	{{928,552},{928,784},{752,784}},
}
for _,points in ipairs(bypasses) do route(points,SECONDARY_WIDTH,"Regional") end

-- One authored base definition, instantiated twelve times.
local bases={
	{-136,-336,180,"South"},{0,-336,180,"South"},{136,-336,180,"South"},
	{336,-136,90,"West"},{336,0,90,"West"},{336,136,90,"West"},
	{136,336,0,"North"},{0,336,0,"North"},{-136,336,0,"North"},
	{-336,136,-90,"East"},{-336,0,-90,"East"},{-336,-136,-90,"East"},
}
local function buildBase(index,placement)
	local name=string.format("Base_%02d",index)
	local base=CFrame.new(placement[1],0,placement[2])*CFrame.Angles(0,math.rad(placement[3]),0)
	local world=frame*base
	local parent="PlayerBasePatches/"..name
	table.insert(models,{path=parent,cf=world,attributes={BaseId=name,BaseOrigin=world,
		Facing=placement[4],Yaw=placement[3],ReservationMin=Vector3.new(-56,0,-84),ReservationMax=Vector3.new(56,0,36)}})
	local x1,z1,x2,z2=localRect(base,-56,-84,56,36)
	table.insert(reservations,{x1=x1,z1=z1,x2=x2,z2=z2,kind="Lot",name=name})
	local function piece(n,size,x,y,z,colour,role,class,attrs)
		part(parent,n,size,world*CFrame.new(x,y,z),colour,Enum.Material.Marble,role,CAMP_OWNER,class,attrs)
	end
	piece("Foundation",Vector3.new(96,1,64),0,0.5,0,"EEF6FF","Foundation")
	local xs={-35,-21,-7,7,21,35}
	for row,z in ipairs({-14,14}) do for column,x in ipairs(xs) do
		local slot=(row-1)*6+column
		piece(string.format("Slot_%02d",slot),Vector3.new(10,0.75,10),x,1.375,z,"DCEBFF","Pedestal",nil,
			{SlotId=string.format("Slot_%02d",slot),Row=row,Column=column,AssumedDisplayFootprint=Vector2.new(8,8)})
	end end
	piece("CartDisplay",Vector3.new(32,1,24),28,0.5,-54,"CFE8FF","CartDisplay")
	piece("HouseRamp",Vector3.new(20,1,12),-24,0.5,-38,"EEF6FF","HouseRamp","WedgePart")
	piece("CartRamp",Vector3.new(24,1,12),28,0.5,-72,"CFE8FF","CartRamp","WedgePart")
	for _,r in ipairs({{-34,-112,-14,-44},{16,-112,40,-78}}) do
		local a,b,c,d=localRect(base,r[1],r[2],r[3],r[4]);pathRect(a,b,c,d,"Approach")
	end
end
for i,base in ipairs(bases) do buildBase(i,base) end

-- Names and metadata only, as requested. No SurfaceGuis or interaction scripts.
local stalls={
	{"SellStall","SELL",-92,-100,-90,56,32,"FF4F65"},
	{"BrainrotTrainStall","TRAIN BRAINROTS",-92,0,-90,56,32,"3785FF"},
	{"BuyCartStall","BUY CARTS",-92,100,-90,64,40,"FFD43B"},
	{"AnnouncementStall","ANNOUNCEMENTS",92,-100,90,56,32,"B567FF"},
	{"WeaponHarpoonStall","WEAPONS / HARPOONS",92,0,90,56,32,"FF8A3D"},
	{"KitStall","KITS",92,100,90,56,32,"37D99B"},
}
for _,s in ipairs(stalls) do
	local cf=CFrame.new(s[3],0,s[4])*CFrame.Angles(0,math.rad(s[5]),0)
	local queueX=s[3]<0 and -44 or 44
	part("ServiceStallPatches",s[1],Vector3.new(s[6],1,s[7]),frame*cf*CFrame.new(0,0.5,0),
		s[8],nil,"ServiceStall",CAMP_OWNER,nil,{DisplayLabel=s[2],Facing=s[3]<0 and "East" or "West",
			WaitingAreaCentre=Vector3.new(queueX,0,s[4]),WaitingAreaSize=Vector2.new(32,56)})
	local a,b,c,d=localRect(cf,-s[6]/2,-s[7]/2,s[6]/2,s[7]/2)
	table.insert(reservations,{x1=a,z1=b,x2=c,z2=d,kind="Stall",name=s[1]})
	table.insert(reservations,{x1=queueX-16,z1=s[4]-28,x2=queueX+16,z2=s[4]+28,kind="Queue",name=s[1]})
	local front=s[3]+(s[3]<0 and s[7]/2 or -s[7]/2)
	pathRect(math.min(front,0),s[4]-10,math.max(front,0),s[4]+10,"ServiceAccess")
end

-- Check full rectangle footprints, not just path centrelines.
local function overlaps(a,b,pad)
	pad=pad or 0
	return math.min(a.x2+pad,b.x2)-math.max(a.x1-pad,b.x1)>0.001
		and math.min(a.z2+pad,b.z2)-math.max(a.z1-pad,b.z1)>0.001
end
for _,road in ipairs(roads) do
	assert(road.x1-BORDER>=xEdges[1] and road.x2+BORDER<=xEdges[6]
		and road.z1-BORDER>=zEdges[1] and road.z2+BORDER<=zEdges[6],"Path leaves supported floor.")
	if road.category=="Circulation" or road.category=="Spine" or road.category=="Regional" then
		for _,r in ipairs(reservations) do assert(not overlaps(road,r,BORDER),"Route overlaps "..r.kind.." "..r.name) end
	end
end
for i,a in ipairs(reservations) do for j=i+1,#reservations do
	local b=reservations[j]
	assert(not overlaps(a,b),"Reservations overlap: "..a.name.." / "..b.name)
end end

-- Partition the union of these authored rectangular paths into disjoint Parts.
-- The same partition forms the exposed 2-stud border; entrances stay open.
local xs,zs,xSeen,zSeen={},{},{},{}
local function coordinate(list,seen,value)
	value=math.round(value*1000)/1000
	if not seen[value] then seen[value]=true;table.insert(list,value) end
end
for _,r in ipairs(roads) do
	for _,v in ipairs({r.x1-BORDER,r.x1,r.x2,r.x2+BORDER}) do coordinate(xs,xSeen,v) end
	for _,v in ipairs({r.z1-BORDER,r.z1,r.z2,r.z2+BORDER}) do coordinate(zs,zSeen,v) end
end
table.sort(xs);table.sort(zs)
local xi,zi,grid={},{},{}
for i,v in ipairs(xs) do xi[v]=i end
for i,v in ipairs(zs) do zi[v]=i;grid[i]={} end
local function paint(r,grow,value)
	for z=zi[r.z1-grow],zi[r.z2+grow]-1 do
		local row=grid[z]
		for x=xi[r.x1-grow],xi[r.x2+grow]-1 do
			if value==2 or not row[x] then row[x]=value end
		end
	end
end
for _,r in ipairs(roads) do paint(r,BORDER,1);paint(r,0,2) end
local active,merged={},{}
for z=1,#zs-1 do
	local nextActive={};local x=1
	while x<#xs do
		local value=grid[z][x]
		if value then
			local start=x
			repeat x+=1 until x==#xs or grid[z][x]~=value
			local key=value..":"..start..":"..x
			local rect=active[key] or {x1=xs[start],x2=xs[x],z1=zs[z],z2=zs[z+1],value=value}
			rect.z2=zs[z+1];nextActive[key]=rect
		else x+=1 end
	end
	for key,r in pairs(active) do if not nextActive[key] then table.insert(merged,r) end end
	active=nextActive
end
for _,r in pairs(active) do table.insert(merged,r) end
table.sort(merged,function(a,b)
	if a.value~=b.value then return a.value<b.value end
	if a.z1~=b.z1 then return a.z1<b.z1 end
	if a.x1~=b.x1 then return a.x1<b.x1 end
	if a.z2~=b.z2 then return a.z2<b.z2 end
	return a.x2<b.x2
end)
local pathCounts={Border=0,Surface=0}
for _,r in ipairs(merged) do
	local kind=r.value==2 and "Surface" or "Border";pathCounts[kind]+=1
	part("Paths",string.format("%s_%04d",kind,pathCounts[kind]),
		Vector3.new(r.x2-r.x1,OVERLAY_THICKNESS,r.z2-r.z1),
		frame*CFrame.new((r.x1+r.x2)/2,OVERLAY_RISE-OVERLAY_THICKNESS/2,(r.z1+r.z2)/2),
		kind=="Surface" and "FFE7A3" or "51345C",nil,"Path",PATH_OWNER,nil,{PathKind=kind})
end

-- APPLY GENERATED LAYOUT
local folderNames={Paths=true,PlayerBasePatches=true,ServiceStallPatches=true}
for name in pairs(regions) do folderNames[name]=true end
for name in pairs(folderNames) do
	local existing=root:FindFirstChild(name)
	assert(not existing or existing:IsA("Folder"),"Folder conflict: "..name)
end
local function resolve(path)
	local o=root
	for name in path:gmatch("[^/]+") do o=o and o:FindFirstChild(name) end
	return o
end
for _,m in ipairs(models) do
	local o=resolve(m.path)
	assert(not o or (o:IsA("Model") and o:GetAttribute("GeneratedBy")==CAMP_OWNER),"Unrelated base model: "..m.path)
end
for _,s in ipairs(specs) do
	local parent=resolve(s.parent);local o=parent and parent:FindFirstChild(s.name)
	assert(not o or (o.ClassName==s.class and o:GetAttribute("GeneratedBy")==s.owner),"Unrelated object: "..s.parent.."/"..s.name)
end
local history=game:GetService("ChangeHistoryService");history:SetWaypoint("Before twelve-player camp")
for name in pairs(folderNames) do
	if not root:FindFirstChild(name) then local o=Instance.new("Folder");o.Name=name;o.Parent=root end
end
local kept={}
for _,m in ipairs(models) do
	local parentName,name=m.path:match("(.+)/([^/]+)$")
	local o=resolve(m.path)
	if not o then o=Instance.new("Model");o.Name=name;o.Parent=resolve(parentName) end
	o:SetAttribute("GeneratedBy",CAMP_OWNER)
	for key,value in pairs(m.attributes) do o:SetAttribute(key,value) end
	o.WorldPivot=m.cf;kept[o]=true
end
local created,updated,removed=0,0,0
local counts={}
for _,s in ipairs(specs) do
	local parent=resolve(s.parent)
	local o=parent:FindFirstChild(s.name)
	if o then updated+=1 else o=Instance.new(s.class);o.Name=s.name;created+=1 end
	o.Size,o.CFrame,o.Color=s.size,s.cf,Color3.fromHex(s.colour)
	o.Material,o.MaterialVariant=s.material,""
	o.Anchored,o.CanTouch,o.Transparency,o.Reflectance=true,false,0,0
	local physical=s.role~="Path"
	o.CanCollide,o.CanQuery,o.CastShadow=physical,physical,physical
	o.CollisionGroup=groundGroup
	o.TopSurface,o.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
	o:SetAttribute("GeneratedBy",s.owner);o:SetAttribute("LayoutRole",s.role)
	for key,value in pairs(s.attributes) do o:SetAttribute(key,value) end
	o.Parent=parent;kept[o]=true;counts[s.role]=(counts[s.role] or 0)+1
end
for _,o in ipairs(root:GetDescendants()) do
	local owner=o:GetAttribute("GeneratedBy")
	if (owner==FLOOR_OWNER or owner==PATH_OWNER or owner==CAMP_OWNER) and not kept[o]
		and o:IsA("BasePart") and #o:GetChildren()==0 then o:Destroy();removed+=1 end
end
for name,r in pairs(regions) do
	local folder=root[name]
	folder:SetAttribute("BoundsMin",Vector3.new(r.x1,0,r.z1))
	folder:SetAttribute("BoundsMax",Vector3.new(r.x2,0,r.z2))
	folder:SetAttribute("NavigableFloorArea",r.area)
	folder:SetAttribute("OriginalFootprint",Vector2.new(originalBounds[name][1],originalBounds[name][2]))
	if clearings[name] then
		folder:SetAttribute("HuntingClearings",Http:JSONEncode(clearings[name]))
		folder:SetAttribute("ClearingSize",120)
	end
end
root:SetAttribute("LayoutVersion",3)
root:SetAttribute("CellWidth",nil);root:SetAttribute("CellDepth",nil)
root:SetAttribute("OriginalCellWidth",256);root:SetAttribute("OriginalCellDepth",192)
root:SetAttribute("CampWidth",CAMP_SIZE);root:SetAttribute("CampDepth",CAMP_SIZE)
root:SetAttribute("GridXEdges",Http:JSONEncode(xEdges));root:SetAttribute("GridZEdges",Http:JSONEncode(zEdges))
root:SetAttribute("GroundSurfaceY",frame.Y);root:SetAttribute("OriginX",frame.X);root:SetAttribute("OriginZ",frame.Z)
root:SetAttribute("FloorThickness",FLOOR_THICKNESS)
for key,value in pairs({PathWidth=MAIN_WIDTH,SecondaryWidth=SECONDARY_WIDTH,CampLoopWidth=CAMP_ROAD_WIDTH,
	SpineWidth=SPINE_WIDTH,BorderWidth=BORDER,Thickness=OVERLAY_THICKNESS,SurfaceRise=OVERLAY_RISE}) do root.Paths:SetAttribute(key,value) end
root.Paths:SetAttribute("CampSize",nil);root.Paths:SetAttribute("JunctionSize",72)

-- The old player spawn clips the central spine. Relocate only if it conflicts.
-- Leave all live cart markers, orientations, identifiers and bindings intact.
local playerSpawn=workspace:FindFirstChild("SpawnLocation")
local spawnMoved=false
if playerSpawn and playerSpawn:IsA("SpawnLocation") then
	local p=frame:PointToObjectSpace(playerSpawn.Position)
	local box={x1=p.X-playerSpawn.Size.X/2,x2=p.X+playerSpawn.Size.X/2,z1=p.Z-playerSpawn.Size.Z/2,z2=p.Z+playerSpawn.Size.Z/2}
	local conflict=overlaps(box,{x1=-20,x2=20,z1=-160,z2=160})
	for _,r in ipairs(reservations) do if overlaps(box,r) then conflict=true end end
	if conflict then
		local target=frame:PointToWorldSpace(Vector3.new(-44,playerSpawn.Size.Y/2,46))
		playerSpawn.CFrame=CFrame.new(target)*playerSpawn.CFrame.Rotation;spawnMoved=true
	end
end
-- The 25 contiguous collidable region floors support the full enlarged footprint.
-- Preserve the original baseplate; no extra underlay or terrain is needed.
history:SetWaypoint("Twelve-player camp and enlarged regions")
local dimensions={}
for name,r in pairs(regions) do dimensions[name]={before=originalBounds[name],after={r.x2-r.x1,r.z2-r.z1},area=r.area} end
return Http:JSONEncode({created=created,updated=updated,removed=removed,counts=counts,pathParts=pathCounts,
	baseGroups=#models,playerSpawnMoved=spawnMoved,groundY=frame.Y,regions=dimensions})
