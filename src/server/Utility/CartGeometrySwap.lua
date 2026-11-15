--!strict
-- One synchronous, reversible replacement of an existing cart's presentation,
-- collision parts and semantic layout. No identity, inventory or save mutation.
local RS=game:GetService("ReplicatedStorage")
local Geometry=require(RS.Shared.Utility.CartGeometry)
local Swap={}
local PART_FIELDS={"CFrame","Size","PivotOffset","Transparency","Color","Material","MaterialVariant","CanCollide","CanTouch","CanQuery","Massless","RootPriority","CustomPhysicalProperties","CollisionGroup"}
local function snapshot(p: BasePart): any
	local state={}
	for _,key in PART_FIELDS do state[key]=(p :: any)[key] end
	return state
end
local function write(p: BasePart,state: any)
	for _,key in PART_FIELDS do (p :: any)[key]=state[key] end
end
local function semantic(cart: Model): {BasePart}
	local result={}
	for _,name in {"Root","DriverSeat","CameraTarget"}do
		local p=assert(cart:FindFirstChild(name),"Missing "..name)
		assert(p:IsA("BasePart"),"Invalid "..name);table.insert(result,p)
	end
	for _,name in {"CargoSlots","FormationSlots"}do
		local folder=assert(cart:FindFirstChild(name),"Missing "..name)
		for i=1,6 do local p=assert(folder:FindFirstChild("Slot"..i),"Missing semantic Slot"..i);assert(p:IsA("BasePart"));table.insert(result,p)end
	end
	return result
end
local function wheelRecord(profile: any,p: BasePart): any?
	if not profile then return nil end
	for _,wheel in profile.Wheels do if p.Name==wheel.Name then return wheel end end
	return nil
end
function Swap.Prepare(cart: Model,source: Model,target: CFrame): (any?,string?)
	local valid,reason=Geometry.ValidateTemplate(source)
	if not valid then return nil,reason end
	local root=cart:FindFirstChild("Root");local seat=cart:FindFirstChild("DriverSeat")
	if not root or not root:IsA("BasePart")or not seat or not seat:IsA("VehicleSeat")then return nil,"Missing functional rig"end
	if seat.Occupant or seat:FindFirstChild("SeatWeld")then return nil,"Vehicle must be unoccupied"end
	local old=cart:FindFirstChild("Visual");local sourceVisual=source:FindFirstChild("Visual");local sourceRoot=source:FindFirstChild("Root")
	if not old or not old:IsA("Model")or not sourceVisual or not sourceVisual:IsA("Model")or not sourceRoot or not sourceRoot:IsA("BasePart")then return nil,"Missing replacement unit"end
	local ok,currentParts,sourceParts=pcall(function()return semantic(cart),semantic(source)end)
	if not ok then return nil,tostring(currentParts)end
	-- Optional accepted marker geometry is carried only when both units have it.
	local marker,sourceMarker=cart:FindFirstChild("HarpoonOrigin"),source:FindFirstChild("HarpoonOrigin")
	if marker and marker:IsA("BasePart") and sourceMarker and sourceMarker:IsA("BasePart") then
		table.insert(currentParts,marker);table.insert(sourceParts,sourceMarker)
	end
	local visual=sourceVisual:Clone()
	for _,joint in visual:GetDescendants()do if joint:IsA("JointInstance")or joint:IsA("Constraint")or joint:IsA("WeldConstraint")then joint:Destroy()end end
	local sourceProfile=Geometry.Get(source);local originals={};local nextStates={};local attachmentStates={};local moveSet={}
	for i,p in currentParts do
		local from=sourceParts[i];originals[p]=snapshot(p);local state=snapshot(from);state.CFrame=if p==root then target else target*sourceRoot.CFrame:ToObjectSpace(from.CFrame)
		nextStates[p]=state;moveSet[p]=true
		for _,a in p:GetChildren()do if a:IsA("Attachment")then local incoming=from:FindFirstChild(a.Name);if incoming and incoming:IsA("Attachment")then table.insert(attachmentStates,{Part=a,Before=a.CFrame,After=incoming.CFrame})end end end
	end
	for _,p in old:GetDescendants()do if p:IsA("BasePart")then moveSet[p]=true end end
	local previousJoints={}
	for _,j in cart:GetDescendants()do
		if j:IsA("JointInstance")or j:IsA("WeldConstraint")then
			if (j.Part0==root and moveSet[j.Part1])or(j.Part1==root and moveSet[j.Part0])or j:IsDescendantOf(old)then table.insert(previousJoints,{Joint=j,Parent=j.Parent,Enabled=j.Enabled})end
		end
	end
	-- Fix cloned art transforms while it has no connection to a functional rig.
	for _,p in visual:GetDescendants()do if p:IsA("BasePart")then p.CFrame=target*sourceRoot.CFrame:ToObjectSpace(p.CFrame);p.Anchored=false end end
	local beforeId,beforeRevision=cart:GetAttribute("CartGeometryId"),cart:GetAttribute("CartGeometryRevision")
	local newJoints={};local started=false;local finished=false
	local function weld(p: BasePart)
		local w=Instance.new("WeldConstraint");w.Name="CartGeometryWeld";w.Part0=root;w.Part1=p;w.Parent=p;table.insert(newJoints,w)
	end
	local transaction={}
	function transaction.Apply()
		assert(not started and not finished,"Replacement is single-use")
		assert(root.Anchored and not seat.Occupant and not seat:FindFirstChild("SeatWeld"),"Suspend and empty the assembly before geometry mutation")
		started=true
		for _,r in previousJoints do r.Joint.Enabled=false;r.Joint.Parent=nil end
		old.Parent=nil
		-- CargoMount remains attached to its same slot; its rigid subassembly moves
		-- with that semantic anchor, retaining individuals and their local mount.
		for _,p in currentParts do write(p,nextStates[p]);p.Anchored=if p==root then true else false end
		for _,a in attachmentStates do a.Part.CFrame=a.After end
		for _,p in currentParts do if p~=root then weld(p)end end
		for _,p in visual:GetDescendants()do if p:IsA("BasePart")then
			local wheel=wheelRecord(sourceProfile,p)
			if wheel then
				if not p:IsA("UnionOperation")then p.Size=wheel.BindSize end;p.CFrame=target*wheel.Hub*p.PivotOffset:Inverse()
				local motor=Instance.new("Motor6D");motor.Name="CartWheel_"..wheel.Name;motor.Part0=root;motor.Part1=p;motor.C0=wheel.Hub;motor.C1=p.PivotOffset;motor.Parent=p;table.insert(newJoints,motor)
			else weld(p)end
		end end
		visual.Name="Visual";visual.Parent=cart
		cart:SetAttribute("CartGeometryId",source:GetAttribute("CartGeometryId"));cart:SetAttribute("CartGeometryRevision",source:GetAttribute("CartGeometryRevision"))
	end
	function transaction.Rollback()
		if finished then return end
		for _,j in newJoints do j:Destroy()end
		visual:Destroy()
		if started then
			for _,p in currentParts do write(p,originals[p]);p.Anchored=if p==root then true else false end
			for _,a in attachmentStates do a.Part.CFrame=a.Before end
			old.Parent=cart
			for _,r in previousJoints do r.Joint.Parent=r.Parent;r.Joint.Enabled=r.Enabled end
			cart:SetAttribute("CartGeometryId",beforeId);cart:SetAttribute("CartGeometryRevision",beforeRevision)
		end
		finished=true
	end
	function transaction.Commit()
		assert(started and not finished,"Replacement is not applied")
		for _,r in previousJoints do r.Joint:Destroy()end
		old:Destroy();finished=true
	end
	return transaction,nil
end
return table.freeze(Swap)
