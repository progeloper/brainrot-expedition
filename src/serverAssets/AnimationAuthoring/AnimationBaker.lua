--!strict
-- Edit-mode tool: turns authored pose functions into KeyframeSequences and poses rigs for
-- contact sheets. Never required by the running game.
local ServerStorage = game:GetService("ServerStorage")

local Baker = {}

local FPS = 20

type Bone = { name: string, parent: string, at: { number } }

local function sampleTimes(length: number): { number }
	local times = {}
	local steps = math.max(1, math.ceil(length * FPS - 1e-6))
	for index = 0, steps do
		table.insert(times, math.min(length, index / FPS))
	end
	times[#times] = length
	return times
end

-- Bones an animation ever poses, plus every ancestor (ancestors get weight 0 poses).
local function usedBones(
	definition: any,
	bones: { Bone }
): ({ [string]: boolean }, { [string]: boolean })
	local posed: { [string]: boolean } = {}
	for _, t in sampleTimes(definition.length) do
		for bone in definition.pose(t) do
			posed[bone] = true
		end
	end
	local parentOf: { [string]: string } = {}
	for _, bone in bones do
		parentOf[bone.name] = bone.parent
	end
	local needed: { [string]: boolean } = {}
	for bone in posed do
		local current: string? = bone
		while current and current ~= "Root" do
			needed[current] = true
			current = parentOf[current]
		end
	end
	return posed, needed
end

function Baker.Bake(definition: any, bones: { Bone }): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = definition.name
	sequence.Loop = definition.loop
	sequence.Priority = (Enum.AnimationPriority :: any)[definition.priority]
	sequence:SetAttribute("Length", definition.length)
	sequence:SetAttribute("AuthoredSpeed", definition.speed)
	local posed, needed = usedBones(definition, bones)
	for _, t in sampleTimes(definition.length) do
		local poses = definition.pose(t)
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = t
		local nodes: { [string]: Pose } = {}
		local rootPose = Instance.new("Pose")
		rootPose.Name = "Root"
		rootPose.Weight = 0
		rootPose.Parent = keyframe
		nodes.Root = rootPose
		for _, bone in bones do
			if needed[bone.name] then
				local pose = Instance.new("Pose")
				pose.Name = bone.name
				pose.EasingStyle = Enum.PoseEasingStyle.Linear
				pose.CFrame = poses[bone.name] or CFrame.identity
				pose.Weight = if posed[bone.name] then 1 else 0
				pose.Parent = nodes[bone.parent]
				nodes[bone.name] = pose
			end
		end
		keyframe.Parent = sequence
	end
	return sequence
end

function Baker.BakeSet(set: { any }, bones: { Bone }, folderName: string): Folder
	local sources = ServerStorage:FindFirstChild("AnimationSources")
	if not sources then
		sources = Instance.new("Folder")
		sources.Name = "AnimationSources"
		sources.Parent = ServerStorage
	end
	local old = sources:FindFirstChild(folderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	for _, definition in set do
		Baker.Bake(definition, bones).Parent = folder
	end
	folder.Parent = sources
	return folder
end

-- Pose a rig at time t by writing C0 (works in Edit mode, no Animator needed).
function Baker.PoseModel(model: Model, definition: any, t: number)
	local poses = definition.pose(t)
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") then
			local bind = motor:GetAttribute("BindC0")
			if typeof(bind) ~= "CFrame" then
				bind = motor.C0
				motor:SetAttribute("BindC0", bind)
			end
			motor.C0 = (bind :: CFrame) * (poses[motor.Name] or CFrame.identity)
		end
	end
end

-- Lowest and highest point of any visible part (for the self-check: nothing underground).
function Baker.VerticalExtent(model: Model): (number, number)
	local low, high = math.huge, -math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, size = part.CFrame, part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local y = (cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)).Y
						low, high = math.min(low, y), math.max(high, y)
					end
				end
			end
		end
	end
	return low, high
end

-- Contact-sheet stage: one shelf per animation, `frames` evenly spaced poses per template.
-- templates: { Model } already built (bind pose). Returns the stage folder.
function Baker.BuildSheet(
	parent: Instance,
	origin: Vector3,
	definitions: { any },
	templates: { Model },
	frames: number
): Folder
	local old = parent:FindFirstChild("ContactSheet")
	if old then
		old:Destroy()
	end
	local stage = Instance.new("Folder")
	stage.Name = "ContactSheet"
	local spacing, rowHeight = 3.3, 7.6
	local columns = frames * #templates
	local width = columns * spacing + 14
	local backdrop = Instance.new("Part")
	backdrop.Name = "Backdrop"
	backdrop.Anchored = true
	backdrop.Size = Vector3.new(width + 4, #definitions * rowHeight + 2, 0.5)
	backdrop.Position = origin + Vector3.new(0, #definitions * rowHeight / 2, 4)
	backdrop.Color = Color3.fromRGB(58, 64, 92)
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Parent = stage
	for row, definition in definitions do
		local y = (#definitions - row) * rowHeight + 0.6
		local shelf = Instance.new("Part")
		shelf.Name = "Shelf_" .. definition.name
		shelf.Anchored = true
		shelf.Size = Vector3.new(width, 0.4, 5)
		shelf.Position = origin + Vector3.new(0, y - 0.2, 1.4)
		shelf.Color = Color3.fromRGB(150, 196, 132)
		shelf.Material = Enum.Material.SmoothPlastic
		shelf.Parent = stage
		local label = Instance.new("Part")
		label.Name = "Label_" .. definition.name
		label.Anchored = true
		label.Size = Vector3.new(8, 2.2, 0.2)
		label.Position = origin + Vector3.new(width / 2 - 5, y + 3, 3.6)
		label.Color = Color3.fromRGB(20, 22, 34)
		label.Parent = stage
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(400, 110)
		gui.Parent = label
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Text = string.format(
			"%s  %.2fs %s",
			definition.name,
			definition.length,
			if definition.loop then "loop" else "once"
		)
		text.Parent = gui
		local column = 0
		for _, template in templates do
			for frame = 0, frames - 1 do
				-- Loops are sampled over one period without repeating the first frame.
				local t = if definition.loop
					then definition.length * frame / frames
					else definition.length * frame / (frames - 1)
				local figure = template:Clone()
				figure.Name = string.format("%s_%s_%d", definition.name, template.Name, frame)
				-- Seen from a -Z camera the row reads left to right; turned for a three-quarter-right view.
				local x = width / 2 - 13 - column * spacing
				figure:PivotTo(
					CFrame.new(origin + Vector3.new(x, y, 0)) * CFrame.Angles(0, math.rad(35), 0)
				)
				figure.Parent = stage
				Baker.PoseModel(figure, definition, t)
				column += 1
			end
		end
	end
	stage.Parent = parent
	return stage
end

return table.freeze(Baker)
