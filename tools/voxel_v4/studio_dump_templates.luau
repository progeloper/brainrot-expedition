-- Headless Studio (RunScript, Edit mode, disposable Rojo build): runs the Luau
-- VoxelCreatureBuilder for every species data module and prints each built Model's
-- instance properties as JSON. tools/voxel_v4/write_templates.py turns that dump into
-- Rojo .model.json native templates. No place is opened, saved or published.
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Builder = require(RS.Shared.Utility.VoxelCreatureBuilder)
local Registry = require(RS.Shared.Utility.VoxelCreatureRegistry)

local function encodeValue(v: any): any
	local t = typeof(v)
	if t == "Color3" then
		return { Color3 = { v.R, v.G, v.B } }
	elseif t == "Vector3" then
		return { Vector3 = { v.X, v.Y, v.Z } }
	elseif t == "boolean" then
		return { Bool = v }
	elseif t == "number" then
		return { Float64 = v }
	elseif t == "string" then
		return { String = v }
	end
	error("unsupported attribute type " .. t)
end

local function attributes(instance: Instance)
	local out = {}
	for name, value in instance:GetAttributes() do
		out[name] = encodeValue(value)
	end
	return out
end

local function cframe(c: CFrame)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { position = { c.X, c.Y, c.Z }, rotation = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } }
end

-- stable reference keys for joint targets: Root, bone parts by bone name, boxes by VoxelIndex
local function refKey(part: Instance?): string?
	if part == nil then
		return nil
	elseif part:GetAttribute("RigBone") then
		return "B_" .. tostring(part:GetAttribute("RigBone"))
	elseif part:GetAttribute("VoxelIndex") then
		return "V_" .. tostring(part:GetAttribute("VoxelIndex"))
	elseif part.Name == "Root" then
		return "Root"
	end
	error("unreferenceable joint target " .. part:GetFullName())
end

local function encode(instance: Instance)
	local node: any = { className = instance.ClassName, name = instance.Name, attributes = attributes(instance), children = {} }
	if instance:IsA("Motor6D") then
		node.joint = { Part0 = refKey(instance.Part0), Part1 = refKey(instance.Part1), C0 = cframe(instance.C0), C1 = cframe(instance.C1) }
	elseif instance:IsA("WeldConstraint") then
		node.weld = { Part0 = refKey(instance.Part0), Part1 = refKey(instance.Part1) }
	end
	if instance:IsA("BasePart") then
		node.ref = refKey(instance)
		node.part = {
			Size = { instance.Size.X, instance.Size.Y, instance.Size.Z },
			CFrame = cframe(instance.CFrame),
			Color = { instance.Color.R, instance.Color.G, instance.Color.B },
			Material = instance.Material.Name,
			MaterialVariant = instance.MaterialVariant,
			Transparency = instance.Transparency,
			Reflectance = instance.Reflectance,
			Anchored = instance.Anchored,
			Massless = instance.Massless,
			CanCollide = instance.CanCollide,
			CanQuery = instance.CanQuery,
			CanTouch = instance.CanTouch,
			CastShadow = instance.CastShadow,
		}
	elseif instance:IsA("ParticleEmitter") then
		local function nseq(q)
			local k = q.Keypoints
			return { k[1].Value, k[#k].Value }
		end
		local c = instance.Color.Keypoints
		node.emitter = {
			Texture = instance.Texture,
			Rate = instance.Rate,
			Lifetime = { instance.Lifetime.Min, instance.Lifetime.Max },
			Size = nseq(instance.Size),
			Transparency = nseq(instance.Transparency),
			Color = { { c[1].Value.R, c[1].Value.G, c[1].Value.B }, { c[#c].Value.R, c[#c].Value.G, c[#c].Value.B } },
			LightEmission = instance.LightEmission,
			Speed = { instance.Speed.Min, instance.Speed.Max },
			SpreadAngle = { instance.SpreadAngle.X, instance.SpreadAngle.Y },
			EmissionDirection = instance.EmissionDirection.Name,
			Acceleration = { instance.Acceleration.X, instance.Acceleration.Y, instance.Acceleration.Z },
			RotSpeed = { instance.RotSpeed.Min, instance.RotSpeed.Max },
		}
	elseif instance:IsA("Attachment") then
		node.attachment = { CFrame = cframe(instance.CFrame) }
	elseif instance:IsA("Model") then
		node.model = {
			ModelStreamingMode = instance.ModelStreamingMode.Name,
			PrimaryPart = if instance.PrimaryPart then instance.PrimaryPart.Name else nil,
			WorldPivot = cframe(instance.WorldPivot),
		}
	end
	for _, child in instance:GetChildren() do
		table.insert(node.children, encode(child))
	end
	return node
end

for _, id in Registry.ListSpecies() do
	local data = Registry.GetData(id)
	local model = Builder.Build(data)
	local json = Http:JSONEncode({ id = id, signature = model:GetAttribute("VoxelSignature"), tree = encode(model) })
	-- Print in bounded chunks so the Studio log never truncates a line.
	local size = 3000
	local chunks = math.ceil(#json / size)
	for i = 1, chunks do
		print(string.format("[V4DUMP] %s %d/%d %s", id, i, chunks, string.sub(json, (i - 1) * size + 1, i * size)))
	end
	model:Destroy()
end
print("[V4DUMP_DONE]")
