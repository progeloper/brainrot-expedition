--!strict
-- One bounded client update for the optional wheel list. This never drives a cart.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Quality = require(RS.Shared.Utility.ResolvedPresentationQuality)
local Movement = require(script.Parent.CartMovementController)
local Geometry = require(RS.Shared.Utility.CartGeometry)
local WheelMath = require(RS.Shared.Utility.CartWheelMath)
local Visibility = require(script.Parent.RegionVisibilityController)

local Controller = {}
local UPDATE_DISTANCE = 180
local DISCOVERY_SECONDS = 0.2
local started = false
local connection: RBXScriptConnection? = nil
local discoveryElapsed = 0
local records: { [Model]: any } = {}
local totalUpdates = 0
local lastVisibleWheels = 0
local discontinuities = 0
local invalidBindings = 0

local function runtimeCarts(): Instance?
	local runtime = Workspace:FindFirstChild("Runtime")
	return runtime and runtime:FindFirstChild("Carts")
end

local function release(cart: Model)
	local record = records[cart]
	if record and record.Sound and record.Sound.Parent then record.Sound.PlaybackSpeed=record.SoundPitch;record.Sound.Volume=record.SoundVolume end
	if record and record.Feedback then record.Feedback:Destroy() end
	if record and record.FeedbackAttachments then for _,a in ipairs(record.FeedbackAttachments)do a:Destroy()end end
	if not record then
		return
	end
	for _, wheel in record.Wheels do
		local joint = wheel.Joint
		if joint.Parent and joint:IsDescendantOf(cart) then
			joint.Transform = CFrame.identity
		end
	end
	records[cart] = nil
end

local function liveBinding(cart: Model, root: BasePart, spec: any): Motor6D?
	local joint = cart:FindFirstChild("CartWheel_" .. spec.Name, true)
	if
		not joint
		or not joint:IsA("Motor6D")
		or joint.Part0 ~= root
		or not joint.Part1
		or not joint.Part1:IsDescendantOf(cart)
		or joint.Part1:GetAttribute("CartWheelName") ~= spec.Name
		or (joint.Part1.Size - (if joint.Part1:IsA("UnionOperation")then spec.NativeCSGBindSize else spec.BindSize)).Magnitude > 0.01
	then
		return nil
	end
	return joint
end

local function intact(cart: Model, record: any): boolean
	if
		cart.PrimaryPart ~= record.Root
		or cart:GetAttribute("CartGeometryId") ~= record.Profile.Id
		or cart:GetAttribute("CartGeometryRevision") ~= record.Profile.Revision
	then
		return false
	end
	for _, wheel in record.Wheels do
		local joint = wheel.Joint
		if not joint.Parent or joint.Part0 ~= record.Root or joint.Part1 ~= wheel.Part or not wheel.Part:IsDescendantOf(cart) then
			return false
		end
	end
	return true
end

-- Shared discovery follows the existing Runtime.Carts owner. Templates and
-- ViewportFrames never register, and no connection is allocated per wheel/cart.
function Controller.Refresh()
	local folder = runtimeCarts()
	for cart, record in records do
		if not folder or cart.Parent ~= folder or not intact(cart, record) then
			release(cart)
		end
	end
	if not folder then
		return
	end
	for _, cart in folder:GetChildren() do
		if not cart:IsA("Model") or records[cart] then
			continue
		end
		local profile = Geometry.Get(cart)
		local root = cart.PrimaryPart
		if not profile or not root or #profile.Wheels == 0 then
			continue -- Wheel-free profiles create no record or division by a radius.
		end
		local wheels = {}
		local valid = true
		for _, spec in profile.Wheels do
			local joint = liveBinding(cart, root, spec)
			if not joint then
				valid = false
				break
			end
			table.insert(wheels, { Joint = joint, Part = joint.Part1, Spec = spec, Angle = 0 })
		end
		if valid then
			records[cart] = { Root = root, Profile = profile, Wheels = wheels, Previous = nil, Visible = false }
		else
			invalidBindings += 1
		end
	end
end

-- Two short, non-entitlement speed streaks. No particles, assets or second
-- physical writer. Updated at 10 Hz within this existing shared callback.
local function feedback(cart,record,dt)
    record.FeedbackElapsed=(record.FeedbackElapsed or 0)+dt
    if record.FeedbackElapsed<.1 then return end
    record.FeedbackElapsed=0
    local player=Players.LocalPlayer
    local diag=Movement.GetDiagnostics()
    local speed=Vector3.new(record.Root.AssemblyLinearVelocity.X,0,record.Root.AssemblyLinearVelocity.Z).Magnitude
    local enabled=cart:GetAttribute("ActiveDriverUserId")==player.UserId and diag.Grounded==true
        and speed>12 and player:GetAttribute("ReducedMotion")~=true and Quality.GetTier(player:GetAttribute("VFXQuality"))~="Low"
    if enabled and not record.Feedback then
        local folder=Instance.new("Folder");folder.Name="LocalSpeedFeedback";folder.Parent=cart
        record.Feedback,record.FeedbackAttachments=folder,{}
        for _,side in ipairs({-1,1})do
            local a=Instance.new("Attachment");a.Name="SpeedStreakStart";a.Parent=record.Root
            local b=Instance.new("Attachment");b.Name="SpeedStreakEnd";b.Parent=record.Root
            table.insert(record.FeedbackAttachments,a);table.insert(record.FeedbackAttachments,b)
            local beam=Instance.new("Beam");beam.Name="TravelStreak";beam.Attachment0=a;beam.Attachment1=b
            beam.Width0,beam.Width1=.12,.02;beam.FaceCamera=true;beam.Segments=1
            beam.Color=ColorSequence.new(Color3.fromRGB(222,215,192));beam.Transparency=NumberSequence.new(.72,1)
            beam.LightEmission=0;beam:SetAttribute("Side",side);beam.Parent=folder
        end
    end
    if record.Feedback then for _,beam in ipairs(record.Feedback:GetChildren())do
        local side=beam:GetAttribute("Side");local x=side*record.Profile.RootSize.X*.38
        local z=record.Profile.RootSize.Z/2;local y=record.Profile.Ground.BottomY+.4
        beam.Attachment0.Position=Vector3.new(x,y,z)
        beam.Attachment1.Position=Vector3.new(x,y,z+math.clamp(speed*.06,0,5))
        beam.Enabled=enabled
    end end
    if not record.SoundChecked then
        record.SoundChecked=true;record.Sound=cart:FindFirstChildWhichIsA("Sound",true)
        if record.Sound then record.SoundPitch=record.Sound.PlaybackSpeed;record.SoundVolume=record.Sound.Volume end
    end
    local sound=record.Sound
    if sound and sound.Parent and sound.SoundId~=""then
        sound.PlaybackSpeed=record.SoundPitch*(1+math.clamp(speed/110,0,1)*.25)
        sound.Volume=record.SoundVolume*(.7+math.clamp(speed/110,0,1)*.3)
    end
end
function Controller.Step(deltaTime: number)
	discoveryElapsed += math.max(deltaTime, 0)
	if discoveryElapsed >= DISCOVERY_SECONDS then
		discoveryElapsed = 0
		Controller.Refresh()
	end
	lastVisibleWheels = 0
	local camera = Workspace.CurrentCamera
	for cart, record in records do
		if not cart:IsDescendantOf(Workspace) or not intact(cart, record) then
			release(cart)
			continue
		end
		feedback(cart,record,deltaTime)
		local frame = record.Root.CFrame
		local visible = camera ~= nil
			and Visibility.IsVisible(cart)
			and (camera.CFrame.Position - frame.Position).Magnitude <= UPDATE_DISTANCE
		if not visible then
			record.Previous = nil
			record.Visible = false
			continue
		end
		local previous = if record.Visible then record.Previous else nil
		for _, wheel in record.Wheels do
			local spec = wheel.Spec
			local delta, reset = WheelMath.Delta(previous, frame, spec.Hub, spec.SpinAxis, spec.Radius, deltaTime)
			if reset then
				discontinuities += 1
			elseif delta ~= 0 then
				wheel.Angle = WheelMath.Wrap(wheel.Angle + delta)
				-- Transform contains rotation only. C0/C1, mesh pivots and Size stay bound.
				wheel.Joint.Transform = CFrame.fromAxisAngle(spec.SpinAxis.Unit, wheel.Angle)
				totalUpdates += 1
			end
			lastVisibleWheels += 1
		end
		record.Previous = frame
		record.Visible = true
	end
end

function Controller.Start(): boolean
	if started then
		return false
	end
	started = true
	Controller.Refresh()
	-- Motor6D.Transform is applied in the engine's batch after PreSimulation.
	connection = RunService.PreSimulation:Connect(Controller.Step)
	return true
end

function Controller.Stop()
	started = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for cart in records do
		release(cart)
	end
	discoveryElapsed = 0
	lastVisibleWheels = 0
end

function Controller.GetDiagnostics(): any
	local cartCount, wheelCount = 0, 0
	for _, record in records do
		cartCount += 1
		wheelCount += #record.Wheels
	end
	return {
		Started = started,
		UpdateConnections = if connection then 1 else 0,
		RegisteredCarts = cartCount,
		RegisteredWheels = wheelCount,
		VisibleWheels = lastVisibleWheels,
		RotationWrites = totalUpdates,
		DiscontinuityResets = discontinuities,
		InvalidBindingObservations = invalidBindings,
	}
end

return Controller
