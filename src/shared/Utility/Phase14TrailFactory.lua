--!strict
-- Approved V3 trail recipe, adapted to one shared client scheduler.
local Factory = {}
Factory.Presets = {
	P14_TRAIL_STARFORGE = { Color3.fromRGB(255, 209, 37), Color3.fromRGB(141, 54, 255) },
	P14_TRAIL_COMET = { Color3.fromRGB(189, 254, 255), Color3.fromRGB(22, 119, 255) },
	P14_TRAIL_OBSIDIAN = { Color3.fromRGB(255, 99, 93), Color3.fromRGB(212, 31, 255) },
}
-- Rear body-space anchors follow the fitted profile even when the chassis is
-- displaced/rotated or has no wheels. The lower-body clearance preserves the
-- accepted 1.65-stud anchor height on the current nine fitted templates.
function Factory.MountFrames(profile)
	local b = profile and profile.CoreBodyBounds
	if not b or typeof(b.Frame) ~= "CFrame" or typeof(b.Size) ~= "Vector3" then
		return nil
	end
	local x, y, z = b.Size.X * 0.33, -b.Size.Y / 2 + 0.71, b.Size.Z / 2 + 0.20
	return b.Frame * CFrame.new(-x, y, z), b.Frame * CFrame.new(x, y, z)
end
-- One replicated selection token binds the permitted trail to the owner and
-- fitted cart generation. Separately replicated Owner/Id changes fail closed.
function Factory.Binding(cart, id)
	return table.concat({
		tostring(cart:GetAttribute("OwnerUserId")),
		tostring(cart:GetAttribute("CartGeneration")),
		tostring(cart:GetAttribute("CartGeometryId")),
		tostring(cart:GetAttribute("CartGeometryRevision")),
		tostring(id),
	}, ":")
end
function Factory.HasCurrentBinding(cart)
	local id = cart:GetAttribute("P14TrailId")
	return Factory.Presets[id] ~= nil
		and cart:GetAttribute("P14TrailBinding") == Factory.Binding(cart, id)
end
function Factory.Create(id, root, left, right)
	local colors = Factory.Presets[id]
	if not colors or not root:IsA("BasePart") then
		return nil
	end
	local objects, trails = {}, {}
	for index, frame in { left, right } do
		local pair = {}
		for endpoint = 0, 1 do
			local a = Instance.new("Attachment")
			a.Name = "P14Trail_" .. index .. "_" .. endpoint
			a.CFrame = frame * CFrame.new(0, (endpoint - 0.5) * 0.45, 0)
			a.Parent = root
			pair[endpoint + 1] = a
			table.insert(objects, a)
		end
		local t = Instance.new("Trail")
		t.Name = id .. "_" .. index
		t.Attachment0, t.Attachment1 = pair[1], pair[2]
		t.Color = ColorSequence.new(colors[1], colors[2])
		t.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		t.WidthScale = NumberSequence.new(1, 0)
		t.Lifetime, t.MinLength, t.MaxLength = 0.35, 0.08, 8
		t.LightEmission, t.LightInfluence = 0, 1
		t.FaceCamera, t.Enabled = true, false
		t.Parent = root
		table.insert(objects, t)
		table.insert(trails, t)
	end
	local handle = { Enabled = false, Trails = trails }
	function handle:Clear()
		self.Enabled = false
		for _, t in trails do
			t.Enabled = false
			t:Clear()
		end
	end
	function handle:Update(speed, allowed)
		local nextEnabled = allowed and speed >= (if self.Enabled then 1 else 2)
		if nextEnabled ~= self.Enabled then
			self.Enabled = nextEnabled
			for _, t in trails do
				t.Enabled = nextEnabled
				if not nextEnabled then
					t:Clear()
				end
			end
		end
	end
	function handle:Destroy()
		self:Clear()
		for _, v in objects do
			v:Destroy()
		end
		table.clear(objects)
		table.clear(trails)
	end
	return handle
end
return Factory
