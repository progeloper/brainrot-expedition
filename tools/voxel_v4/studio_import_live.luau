-- One-off live import (owner, 7 Nov 2026): rebuilds the rigged Voxel V4 templates in the open DEV place from the
-- headless builder dump (tools/voxel_v4/studio_dump_templates.luau output, split per species and served on
-- http://127.0.0.1:8765 from the scratchpad). The owner approved switching HttpService.HttpEnabled on only for the
-- import; it is restored to its original value even if the import fails. Nothing is saved or published.
-- Target: ReplicatedStorage.CodeAssets.CreaturesV4 (the same path the Rojo project uses). Existing models are never
-- overwritten: a species that already exists there is skipped and reported.
local Http = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local BASE = "http://127.0.0.1:8765/"

local function decodeAttr(v)
	local kind, value = next(v)
	if kind == "Color3" then
		return Color3.new(value[1], value[2], value[3])
	elseif kind == "Vector3" then
		return Vector3.new(value[1], value[2], value[3])
	end
	return value
end

local function cf(c)
	local p, r = c.position, c.rotation
	return CFrame.new(p[1], p[2], p[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

local function build(node, refs, joints, models)
	local inst = Instance.new(node.className)
	inst.Name = node.name
	for name, v in node.attributes or {} do
		inst:SetAttribute(name, decodeAttr(v))
	end
	if node.part then
		local p = node.part
		inst.Size = Vector3.new(p.Size[1], p.Size[2], p.Size[3])
		inst.CFrame = cf(p.CFrame)
		inst.Color = Color3.new(p.Color[1], p.Color[2], p.Color[3])
		inst.Material = Enum.Material[p.Material]
		inst.MaterialVariant = p.MaterialVariant
		inst.Transparency = p.Transparency
		inst.Reflectance = p.Reflectance
		inst.Anchored = p.Anchored
		inst.Massless = p.Massless
		inst.CanCollide = p.CanCollide
		inst.CanQuery = p.CanQuery
		inst.CanTouch = p.CanTouch
		inst.CastShadow = p.CastShadow
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
		if node.ref then
			refs[node.ref] = inst
		end
	elseif node.emitter then
		local e = node.emitter
		inst.Texture = e.Texture
		inst.Rate = e.Rate
		inst.Lifetime = NumberRange.new(e.Lifetime[1], e.Lifetime[2])
		inst.Size = NumberSequence.new(e.Size[1], e.Size[2])
		inst.Transparency = NumberSequence.new(e.Transparency[1], e.Transparency[2])
		inst.Color = ColorSequence.new(
			Color3.new(e.Color[1][1], e.Color[1][2], e.Color[1][3]),
			Color3.new(e.Color[2][1], e.Color[2][2], e.Color[2][3])
		)
		inst.LightEmission = e.LightEmission
		inst.Speed = NumberRange.new(e.Speed[1], e.Speed[2])
		inst.SpreadAngle = Vector2.new(e.SpreadAngle[1], e.SpreadAngle[2])
		inst.EmissionDirection = Enum.NormalId[e.EmissionDirection]
		inst.Acceleration = Vector3.new(e.Acceleration[1], e.Acceleration[2], e.Acceleration[3])
		inst.RotSpeed = NumberRange.new(e.RotSpeed[1], e.RotSpeed[2])
	elseif node.attachment then
		inst.CFrame = cf(node.attachment.CFrame)
	elseif node.joint then
		inst.C0 = cf(node.joint.C0)
		inst.C1 = cf(node.joint.C1)
		table.insert(joints, { inst, node.joint.Part0, node.joint.Part1 })
	elseif node.weld then
		table.insert(joints, { inst, node.weld.Part0, node.weld.Part1 })
	elseif node.model then
		inst.ModelStreamingMode = Enum.ModelStreamingMode[node.model.ModelStreamingMode]
		table.insert(models, { inst, node.model })
	end
	for _, child in node.children do
		build(child, refs, joints, models).Parent = inst
	end
	return inst
end

local function importSpecies(id, folder)
	if folder:FindFirstChild(id .. "_V4") then
		return "skipped (already present)"
	end
	local dump = Http:JSONDecode(Http:GetAsync(BASE .. id .. ".json"))
	local refs, joints, models = {}, {}, {}
	local model = build(dump.tree, refs, joints, models)
	refs.Root = model:FindFirstChild("Root")
	for _, j in joints do
		j[1].Part0 = assert(refs[j[2]], "missing ref " .. tostring(j[2]))
		j[1].Part1 = assert(refs[j[3]], "missing ref " .. tostring(j[3]))
	end
	for _, m in models do
		m[1].PrimaryPart = m[1]:FindFirstChild(m[2].PrimaryPart)
		m[1].WorldPivot = cf(m[2].WorldPivot)
	end
	assert(model:GetAttribute("VoxelSignature") == dump.signature, "signature mismatch " .. id)
	model.Parent = folder
	return "imported " .. dump.signature
end

local original = Http.HttpEnabled
local report = {}
local ok, err = pcall(function()
	Http.HttpEnabled = true
	local index = Http:JSONDecode(Http:GetAsync(BASE .. "index.json"))
	local codeAssets = RS:WaitForChild("CodeAssets")
	local folder = codeAssets:FindFirstChild("CreaturesV4")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CreaturesV4"
		folder.Parent = codeAssets
	end
	for _, entry in index do
		local okOne, result = pcall(importSpecies, entry.id, folder)
		table.insert(report, entry.id .. ": " .. (if okOne then result else "FAILED " .. tostring(result)))
		task.wait()
	end
end)
Http.HttpEnabled = original
table.insert(report, "HttpEnabled restored to " .. tostring(Http.HttpEnabled))
if not ok then
	table.insert(report, "IMPORT ERROR: " .. tostring(err))
end
return table.concat(report, "\n")
