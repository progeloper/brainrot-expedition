--!strict
local RS = game:GetService("ReplicatedStorage")
local MaterialPolicy = require(RS.Shared.Utility.MapArtStaticMaterialPolicy)
local Templates = require(RS.Shared.Utility.CreatureTemplateProvider)
local CartGeometry = require(RS.Shared.Utility.CartGeometry)
local Presentation = {}
function Presentation.SweepMotion(
	velocity: Vector3,
	forward: Vector3,
	seconds: number,
	targetSpeed: number?,
	burstActive: boolean
): Vector3
	local swept = velocity
	if
		burstActive
		and type(targetSpeed) == "number"
		and targetSpeed == targetSpeed
		and targetSpeed > velocity.Magnitude
	then
		swept = (if velocity.Magnitude > 0.01 then velocity.Unit else forward) * targetSpeed
	end
	return swept * seconds
end
function Presentation.Adapter(cart: any): any?
	local geometry = CartGeometry.Get(cart)
	if geometry then return geometry.FormationAdapter end
	local root = cart.PrimaryPart
	local chassis = cart:FindFirstChild("Chassis", true)
	if not root or not chassis or not chassis:IsA("BasePart") then
		return nil
	end
	local cf = root.CFrame:ToObjectSpace(chassis.CFrame)
	local w, d = chassis.Size.X, chassis.Size.Z
	if w <= 0 or d <= 0 then
		return nil
	end
	local lane = math.min(1.6, 0.24 * w)
	local width = math.min(2.2, (w - lane - 0.12 * w) / 2)
	local depth = math.min(2.2, 1.25 * width)
	local x = lane / 2 + width / 2
	local front = cf.Z - d / 2
	local row = front - (0.75 + depth / 2)
	local supportY = cf.Y - chassis.Size.Y / 2
	local wheels = cart:FindFirstChild("Wheels", true)
	if wheels then
		for _, part in wheels:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 0.95 then
				local relative = root.CFrame:ToObjectSpace(part.CFrame)
				local extent = math.abs(relative.RightVector.Y) * part.Size.X / 2
					+ math.abs(relative.UpVector.Y) * part.Size.Y / 2
					+ math.abs(relative.LookVector.Y) * part.Size.Z / 2
				supportY = math.min(supportY, relative.Y - extent)
			end
		end
	end
	-- Two narrow pockets on the forward chassis deck.
	local dockWidth = math.min(width, 1.05)
	local dockDepth = 0.72
	local dockX = lane / 2 + dockWidth / 2 + 0.10
	return {
		width = width,
		depth = depth,
		height = math.min(3, 1.5 * width),
		x = x,
		front = front,
		row = row,
		spacing = depth + 0.4,
		supportY = supportY,
		dockWidth = dockWidth,
		dockDepth = dockDepth,
		dockHeight = 1.35,
		dockX = dockX,
		dockY = cf.Y + chassis.Size.Y / 2 + 0.06,
		dockRow = front + 0.48,
		dockSpacing = 0.84,
		chassisWidth = w,
	}
end
function Presentation.Position(adapter: any, index: number, docked: boolean): CFrame
	local left = index % 2 == 1
	local row = math.floor((index - 1) / 2)
	return CFrame.new(
		(if left then -1 else 1) * (if docked then adapter.dockX else adapter.x),
		if docked then adapter.dockY else adapter.supportY,
		if docked then adapter.dockRow + row * adapter.dockSpacing else adapter.row - row * adapter.spacing
	)
end
function Presentation.Clone(species: string, lod: string): Model
	local template = Templates.Get(species, lod)
	local model = Instance.new("Model")
	model.Name = "TeamPresentation"
	if template then
		for _, part in template:GetDescendants() do
			if part:IsA("BasePart") then
				local copy = part:Clone()
				copy:ClearAllChildren()
				for name in copy:GetAttributes() do
					if name ~= "CreatureSurfaceRole" and not copy:GetAttribute("VoxelV4") then
						copy:SetAttribute(name, nil)
					end
				end
				for _, tag in game.CollectionService:GetTags(copy) do
					game.CollectionService:RemoveTag(copy, tag)
				end
				copy.Anchored = true
				copy.CanCollide = false
				copy.CanTouch = false
				copy.CanQuery = false
				copy.CastShadow = false
				MaterialPolicy.Apply(copy)
				copy.Parent = model
			end
		end
		model.WorldPivot = template:GetPivot()
		if template:GetAttribute("VoxelCreatureVersion") == 4 then
			for name, value in template:GetAttributes() do
				if string.sub(name, 1, 5) == "Voxel" then
					model:SetAttribute(name, value)
				end
			end
			local presets = template:FindFirstChild("Mutations")
			if presets then
				presets:Clone().Parent = model
			end
		end
	else
		model:SetAttribute("CreatureTemplatePending", true)
		local p = Instance.new("Part")
		p.Name = "AppearanceUnavailable"
		p.Size = Vector3.new(0.8, 0.8, 0.8)
		p.Color = Color3.fromRGB(242, 196, 90)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.CFrame = CFrame.new(0, 0.4, 0)
		MaterialPolicy.Apply(p, Enum.Material.Plastic)
		p.Parent = model
		model.WorldPivot = CFrame.identity
	end
	return model
end
function Presentation.Fit(model: Model, width: number, height: number, depth: number): number
	local _, bounds = model:GetBoundingBox()
	local scale = math.min(width / bounds.X, height / bounds.Y, depth / bounds.Z)
	model:ScaleTo(model:GetScale() * scale)
	return scale
end
-- Conservative oriented presentation-envelope intersection with the existing
-- semantic gate door (which is intentionally non-queryable/non-colliding).
function Presentation.IntersectsGate(frame: CFrame, size: Vector3, motion: Vector3, door: BasePart): boolean
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local world = frame:PointToWorldSpace(size * Vector3.new(x, y, z) / 2)
				for _, point in { world, world + motion } do
					local p = door.CFrame:PointToObjectSpace(point)
					low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
					high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
				end
			end
		end
	end
	local half = door.Size / 2 + Vector3.new(0.1, 0.1, 0.1)
	return low.X <= half.X
		and high.X >= -half.X
		and low.Y <= half.Y
		and high.Y >= -half.Y
		and low.Z <= half.Z
		and high.Z >= -half.Z
end
return table.freeze(Presentation)
