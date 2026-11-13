--!strict
-- Keeps a villager's held prop upright while the hand moves (owner, 13 Nov 2026: Zio
-- Sabbia's beach umbrella stays in his hand). Several body animations turn the hand right
-- over (Shout, Tag, the tantrums); a tall prop would swing through the floor with it. A
-- skin opts in with `uprightProp = true`; the builder marks the model with the UprightProp
-- attribute, and the client calls Bind on it. Client only: servers have no Animator.
--
-- Each frame, after the Animator has written this frame's joint transforms, the Prop joint
-- is given the transform that cancels every rotation above it, so the prop keeps the
-- model's facing and stands vertical at the hand's position. Nothing else is changed.
local RunService = game:GetService("RunService")

local UprightProp = {}

-- The Prop joint transform that stands the prop upright. `handWorld` is the world CFrame of
-- the hand bone, `c0` the Prop joint's C0, `facing` the model root's CFrame.
function UprightProp.Solve(handWorld: CFrame, c0: CFrame, facing: CFrame): CFrame
	local base = handWorld * c0
	return base:Inverse() * (CFrame.new(base.Position) * facing.Rotation)
end

-- World CFrame of a bone from the joint chain, exact for the transforms set this frame (the
-- parts themselves only move later in the frame).
local function worldOf(part: BasePart, root: BasePart, joints: { [BasePart]: Motor6D }): CFrame
	local chain: { Motor6D } = {}
	local current = part
	while current ~= root do
		local joint = joints[current]
		if not joint or not joint.Part0 then
			return part.CFrame
		end
		table.insert(chain, joint)
		current = joint.Part0 :: BasePart
	end
	local cf = root.CFrame
	for index = #chain, 1, -1 do
		local joint = chain[index]
		cf = cf * joint.C0 * joint.Transform * joint.C1:Inverse()
	end
	return cf
end

-- Starts keeping `model`'s prop upright. Returns the connection, or nil when the model has
-- no Prop joint. The connection ends itself when the model leaves the DataModel.
function UprightProp.Bind(model: Model): RBXScriptConnection?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local joints: { [BasePart]: Motor6D } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Part1 then
			joints[item.Part1 :: BasePart] = item
		end
	end
	local prop = model:FindFirstChild("Prop")
	local propJoint = if prop and prop:IsA("BasePart") then joints[prop] else nil
	if not propJoint or not propJoint.Part0 then
		return nil
	end
	local hand = propJoint.Part0 :: BasePart
	local connection: RBXScriptConnection
	connection = RunService.PreSimulation:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end
		propJoint.Transform =
			UprightProp.Solve(worldOf(hand, root, joints), propJoint.C0, root.CFrame)
	end)
	return connection
end

return table.freeze(UprightProp)
