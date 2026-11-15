--!strict
-- Detached, inert native asset clones only. No runtime CSG, new roots or gameplay parts.
local RS = game:GetService("ReplicatedStorage")
local Geometry = require(RS.Shared.Utility.CartGeometry)
local Rules = require(RS.Shared.Utility.Phase14CosmeticRules)
local TrailFactory = require(RS.Shared.Utility.Phase14TrailFactory)
local Assembly = require(script.Parent.Parent.Services.CartAssemblyValidationService)
local Profiles = require(script.Parent.Parent.Services.PlayerDataService)
local Presenter = {}
local retries = {}
local assetConnection, assetFolder = nil, nil
local baseBindings = setmetatable({}, { __mode = "k" })
local cartBindings = setmetatable({}, { __mode = "k" })
local function templates()
	local assets = RS:FindFirstChild("StudioAssets")
	return assets and assets:FindFirstChild("Cosmetics")
end
function Presenter.Ready(id)
	local row = Rules.Get(id)
	if not row then
		return false
	end
	if row.slot == "Trail" then
		return true
	end
	local folder = templates()
	local asset = folder and folder:FindFirstChild(id)
	return asset ~= nil
		and asset:IsA("Model")
		and asset.PrimaryPart ~= nil
		and asset:GetAttribute("P14NativeValidated") == true
end
-- Outward-rounded native full-art envelopes for all 32 live canonical cargo
-- species, in their model-pivot space. Proof: Native_Cargo_Flag_Bounds.json.
-- Cargo mounts its model pivot directly to each authored CargoAttachment.
local CARGO_LOW = Vector3.new(-5.069, -0.959, -5.641)
local CARGO_HIGH = Vector3.new(3.274, 3.554, 5.219)
local CARGO_FRAME = CFrame.new((CARGO_LOW + CARGO_HIGH) / 2)
local CARGO_SIZE = CARGO_HIGH - CARGO_LOW
-- All three approved flags reach 0.275 studs inboard of their pole pivot.
local FLAG_INBOARD = 0.276
local FLAG_CLEARANCE = 0.25
local function rightEdge(frame, size)
	local half = size / 2
	return frame.Position.X
		+ math.abs(frame.RightVector.X) * half.X
		+ math.abs(frame.UpVector.X) * half.Y
		+ math.abs(frame.LookVector.X) * half.Z
end
function Presenter.FlagFrame(profile)
	local b = profile.CoreBodyBounds
	local right = math.max(
		rightEdge(b.Frame, b.Size),
		rightEdge(profile.VisualBounds.Frame, profile.VisualBounds.Size),
		rightEdge(profile.RiderClearance.Frame, profile.RiderClearance.Size),
		if typeof(profile.HarpoonOrigin) == "CFrame"
			then profile.HarpoonOrigin.Position.X + 0.25
			else rightEdge(b.Frame, b.Size)
	)
	-- Six inexpensive frame projections cover every permitted cargo slot even
	-- when empty. No species models are cloned or measured during presentation.
	for _, slot in profile.CargoSlots do
		right = math.max(right, rightEdge(slot * CARGO_FRAME, CARGO_SIZE))
	end
	local poleX = math.max(rightEdge(b.Frame, b.Size) + 0.60, right + FLAG_INBOARD + FLAG_CLEARANCE)
	-- Retain the approved height, fore/aft position and outward-facing cloth.
	return CFrame.new(poleX, 1.65, b.Frame.Position.Z + b.Size.Z / 2 - 0.65)
end
-- One rigid presentation bracket follows the underside of the fitted floor
-- before rising to the flag foot. Its upper edge meets both surfaces; the thin
-- slope clears the measured low cargo overhang on the smaller fitted carts.
function Presenter.FlagRail(profile, flagFrame)
	local floor
	for _, collider in profile.Colliders do
		if collider.Name == "Floor" then
			floor = collider
			break
		end
	end
	if not floor then
		return nil
	end
	local frame = flagFrame or Presenter.FlagFrame(profile)
	local half = floor.Size / 2
	local floorRight = rightEdge(floor.Frame, floor.Size)
	local floorBottom = floor.Frame.Position.Y
		- math.abs(floor.Frame.RightVector.Y) * half.X
		- math.abs(floor.Frame.UpVector.Y) * half.Y
		- math.abs(floor.Frame.LookVector.Y) * half.Z
	local run = frame.Position.X - floorRight
	if run <= 0 then
		return nil
	end
	local rise = frame.Position.Y - (floorBottom + 0.005)
	local upperStart =
		Vector3.new(floorRight - 0.10, floorBottom + 0.005 - rise / run * 0.10, frame.Position.Z)
	local upperEnd = frame.Position
	local direction = upperEnd - upperStart
	local normal = Vector3.new(-direction.Y, direction.X, 0).Unit
	local center = (upperStart + upperEnd) / 2 - normal * 0.05
	return CFrame.new(center) * CFrame.Angles(0, 0, math.atan2(direction.Y, direction.X)),
		Vector3.new(direction.Magnitude, 0.10, 0.30)
end
function Presenter.BannerFrame(base)
	local f = base:FindFirstChild("Foundation")
	if not f or not f:IsA("BasePart") then
		return nil
	end
	-- Ground-level exterior corner, clear of the central gate, stair aisle and all production slots.
	return f.CFrame * CFrame.new(-f.Size.X / 2 - 3.2, f.Size.Y / 2, -f.Size.Z / 2 + 5)
end
local function clone(id, frame, host, name, owner, profile)
	local folder = templates()
	local asset = folder and folder:FindFirstChild(id)
	if not asset or not Presenter.Ready(id) then
		return nil
	end
	local model = asset:Clone()
	model.Name = name
	model:SetAttribute("P14CosmeticId", id)
	model:SetAttribute("OwnerUserId", owner)
	model:PivotTo(frame)
	if name == "P14CartFlag" then
		model:SetAttribute("P14FlagMountVersion", 2)
		local railFrame, railSize = Presenter.FlagRail(profile, host.CFrame:ToObjectSpace(frame))
		if not railFrame then
			model:Destroy()
			return nil
		end
		local rail = Instance.new("Part")
		rail.Name, rail.Size, rail.CFrame = "P14FlagMountingRail", railSize, host.CFrame * railFrame
		rail.Color = Color3.fromRGB(42, 46, 54)
		-- The retained saved-stud variant uses Glacier as its base material.
		rail.Material, rail.MaterialVariant =
			Enum.Material.Glacier, "Bingus_Saved_Studs_13719188279"
		rail:SetAttribute("StudsPerTile", 0.25)
		rail:SetAttribute("P14MountingRail", true)
		rail.TopSurface, rail.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		rail.Parent = model
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CollisionGroup = host.CollisionGroup
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			local weld = Instance.new("WeldConstraint")
			weld.Name = "P14CosmeticWeld"
			weld.Part0 = host
			weld.Part1 = part
			weld.Parent = part
		end
	end
	return model
end
function Presenter.ReleaseBase(base)
	retries[base] = nil
	local binding = baseBindings[base]
	baseBindings[base] = nil
	if binding then
		for _, c in binding do
			c:Disconnect()
		end
	end
	local banner = base:FindFirstChild("P14BaseBanner")
	if banner then
		banner:Destroy()
	end
	base:SetAttribute("P14BannerPresentationStatus", "None")
end
local function bindBase(base)
	if baseBindings[base] then
		return
	end
	local binding = {}
	baseBindings[base] = binding
	local function invalidate()
		local banner = base:FindFirstChild("P14BaseBanner")
		if
			banner
			and (
				banner:GetAttribute("OwnerUserId") ~= base:GetAttribute("OwnerUserId")
				or banner:GetAttribute("P14AssignmentRevision") ~= base:GetAttribute(
					"BaseOwnershipRevision"
				)
				or banner:GetAttribute("P14BaseDesignId") ~= base:GetAttribute(
					"SelectedBaseDesignId"
				)
				or base:GetAttribute("BasePresentationReady") == false
			)
		then
			banner:Destroy()
			base:SetAttribute("P14BannerPresentationStatus", "Unavailable")
		end
	end
	for _, key in
		{ "OwnerUserId", "BaseOwnershipRevision", "SelectedBaseDesignId", "BasePresentationReady" }
	do
		table.insert(binding, base:GetAttributeChangedSignal(key):Connect(invalidate))
	end
	table.insert(
		binding,
		base.Destroying:Connect(function()
			Presenter.ReleaseBase(base)
		end)
	)
end
local function mutateFlag(cart, action)
	if Assembly:GetState(cart) == nil then
		action()
		return true
	end
	local accepted, revision = Assembly:BeginMutation(cart, "Phase14 flag")
	if not accepted then
		return false
	end
	local ok, failure = pcall(action)
	local valid, _, why = Assembly:CompleteMutation(cart, revision, "Runtime", "Phase14 flag")
	if not ok then
		warn("[P14Cosmetics] Flag construction unavailable: " .. tostring(failure))
	end
	if not valid then
		warn("[P14Cosmetics] Flag validation unavailable: " .. tostring(why))
	end
	return ok and valid
end
function Presenter.ReleaseCart(cart)
	retries[cart] = nil
	local binding = cartBindings[cart]
	cartBindings[cart] = nil
	if binding then
		for _, c in binding.Connections do
			c:Disconnect()
		end
	end
	local old = cart:FindFirstChild("P14CartFlag")
	if old then
		mutateFlag(cart, function()
			old:Destroy()
		end)
	end
	cart:SetAttribute("P14TrailId", "None")
	cart:SetAttribute("P14TrailBinding", nil)
	cart:SetAttribute("P14FlagPresentationStatus", "None")
end
local function stamp(binding, cart)
	binding.Root, binding.Generation = cart.PrimaryPart, cart:GetAttribute("CartGeneration")
	binding.GeometryId, binding.GeometryRevision =
		cart:GetAttribute("CartGeometryId"), cart:GetAttribute("CartGeometryRevision")
	binding.Owner = cart:GetAttribute("OwnerUserId")
end
local function bindCart(player, base, cart)
	local binding = cartBindings[cart]
	if binding and binding.Player ~= player then
		Presenter.ReleaseCart(cart)
		binding = nil
	end
	if binding then
		binding.Base = base
		stamp(binding, cart)
		return
	end
	binding = { Player = player, Base = base, Connections = {} }
	cartBindings[cart] = binding
	stamp(binding, cart)
	local function invalidate()
		if cartBindings[cart] ~= binding then
			return
		end
		-- A deferred old signal must not clear a presentation already rebound by
		-- the current owner/critical callback before that signal was delivered.
		if
			binding.Root == cart.PrimaryPart
			and binding.Generation == cart:GetAttribute("CartGeneration")
			and binding.Owner == cart:GetAttribute("OwnerUserId")
			and binding.GeometryId == cart:GetAttribute("CartGeometryId")
			and binding.GeometryRevision == cart:GetAttribute("CartGeometryRevision")
		then
			return
		end
		stamp(binding, cart)
		local old = cart:FindFirstChild("P14CartFlag")
		if old then
			mutateFlag(cart, function()
				old:Destroy()
			end)
		end
		cart:SetAttribute("P14TrailId", "None")
		cart:SetAttribute("P14TrailBinding", nil)
		cart:SetAttribute("P14FlagPresentationStatus", "Unavailable")
		if cart:GetAttribute("OwnerUserId") ~= player.UserId then
			retries[cart] = nil
			return
		end
		-- Rebind only this still-current model generation, through the existing
		-- bounded presenter loader and confirmed readable profile boundary.
		retries[cart] = {
			Player = player,
			Base = binding.Base,
			Cart = cart,
			Slot = "Flag",
			Id = nil,
			Remaining = 2,
			Next = os.clock() + 0.5,
			Generation = cart:GetAttribute("CartGeneration"),
		}
	end
	for _, key in { "OwnerUserId", "CartGeneration", "CartGeometryId", "CartGeometryRevision" } do
		table.insert(binding.Connections, cart:GetAttributeChangedSignal(key):Connect(invalidate))
	end
	table.insert(
		binding.Connections,
		cart:GetPropertyChangedSignal("PrimaryPart"):Connect(invalidate)
	)
	table.insert(
		binding.Connections,
		cart.Destroying:Connect(function()
			Presenter.ReleaseCart(cart)
		end)
	)
end
function Presenter.Snapshot(data, base, cart)
	local result = Rules.Snapshot(data)
	for _, slot in Rules.Slots do
		for _, row in result.slots[slot].rows do
			local holder = if slot == "Flag" then cart elseif slot == "BaseBanner" then base else nil
			local state = holder
				and holder:GetAttribute(
					if slot == "Flag"
						then "P14FlagPresentationStatus"
						else "P14BannerPresentationStatus"
				)
			row.presentationReady = Presenter.Ready(row.id)
				and not (row.selected and state == "Unavailable")
			row.availableForSelection = row.owned and row.presentationReady
			row.availableForPurchase = row.acquisition == "Cash"
				and not row.owned
				and row.presentationReady
			row.availabilityReason = if not row.presentationReady
				then "PRESENTATION_UNAVAILABLE"
				elseif not row.owned then "NOT_OWNED"
				else nil
		end
	end
	return result
end
local function outcome(holder, player, base, cart, slot, id, owned, rendered)
	local attribute = if slot == "Flag"
		then "P14FlagPresentationStatus"
		else "P14BannerPresentationStatus"
	holder:SetAttribute(
		attribute,
		if id == "None" then "None" elseif rendered then "Ready" else "Unavailable"
	)
	if id == "None" or rendered or not owned then
		retries[holder] = nil
		return
	end
	local row = retries[holder]
	if not row or row.Id ~= id or row.Player ~= player then
		retries[holder] = {
			Player = player,
			Base = base,
			Cart = cart,
			Id = id,
			Slot = slot,
			Remaining = 2,
			Next = os.clock() + 2,
			Generation = cart and cart:GetAttribute("CartGeneration"),
		}
		warn(
			"[P14Cosmetics] "
				.. slot
				.. " presentation unavailable: "
				.. id
				.. "; selection preserved"
		)
	end
end
function Presenter.Reconcile(player, data, base, cart)
	local flag = Rules.Selected(data, "Flag")
	if cart and cart.PrimaryPart and cart:GetAttribute("OwnerUserId") == player.UserId then
		bindCart(player, base, cart)
		local root = cart.PrimaryPart
		local profile = Geometry.Get(cart)
		local old = cart:FindFirstChild("P14CartFlag")
		local owned = cart:GetAttribute("OwnerUserId") == player.UserId
			and Rules.Owns(data, flag)
			and Presenter.Ready(flag)
		cart:SetAttribute(
			"P14FlagPresentationStatus",
			if flag == "None" then "None" elseif owned then "Ready" else "Unavailable"
		)
		if
			old
			and (
				not owned
				or old:GetAttribute("P14CosmeticId") ~= flag
				or old:GetAttribute("OwnerUserId") ~= player.UserId
				or old:GetAttribute("P14FlagMountVersion") ~= 2
				or old:GetAttribute("P14CartGeneration") ~= cart:GetAttribute("CartGeneration")
				or old:GetAttribute("P14GeometryId") ~= cart:GetAttribute("CartGeometryId")
				or old:GetAttribute("P14GeometryRevision") ~= cart:GetAttribute(
					"CartGeometryRevision"
				)
				or not old.PrimaryPart
				or not old.PrimaryPart:FindFirstChild("P14CosmeticWeld")
				or old.PrimaryPart.P14CosmeticWeld.Part0 ~= root
			)
		then
			if mutateFlag(cart, function()
				old:Destroy()
			end) then
				old = nil
			end
		end
		if owned and profile and not old then
			local model = clone(
				flag,
				root.CFrame * Presenter.FlagFrame(profile),
				root,
				"P14CartFlag",
				player.UserId,
				profile
			)
			if model then
				model:SetAttribute("P14CartGeneration", cart:GetAttribute("CartGeneration"))
				model:SetAttribute("P14GeometryId", cart:GetAttribute("CartGeometryId"))
				model:SetAttribute("P14GeometryRevision", cart:GetAttribute("CartGeometryRevision"))
			end
			if model and not mutateFlag(cart, function()
				model.Parent = cart
			end) then
				model:Destroy()
			end
		end
		local visual = cart:FindFirstChild("P14CartFlag")
		outcome(
			cart,
			player,
			base,
			cart,
			"Flag",
			flag,
			Rules.Owns(data, flag),
			owned and visual ~= nil and visual:GetAttribute("P14CosmeticId") == flag
		)
		local trail = Rules.Selected(data, "Trail")
		cart:SetAttribute(
			"P14TrailId",
			if cart:GetAttribute("OwnerUserId") == player.UserId
					and profile
					and Rules.Owns(data, trail)
				then trail
				else "None"
		)
		cart:SetAttribute(
			"P14TrailBinding",
			if profile and Rules.Owns(data, trail) then TrailFactory.Binding(cart, trail) else nil
		)
	end
	if base and base:GetAttribute("OwnerUserId") == player.UserId then
		bindBase(base)
		local id = Rules.Selected(data, "BaseBanner")
		local valid = base:GetAttribute("OwnerUserId") == player.UserId
			and (base:GetAttribute("BasePresentationManaged") ~= true or base:GetAttribute(
				"BasePresentationReady"
			) == true)
			and Rules.Owns(data, id)
			and Presenter.Ready(id)
		base:SetAttribute(
			"P14BannerPresentationStatus",
			if id == "None" then "None" elseif valid then "Ready" else "Unavailable"
		)
		local old = base:FindFirstChild("P14BaseBanner")
		if
			old
			and (
				not valid
				or old:GetAttribute("P14CosmeticId") ~= id
				or old:GetAttribute("OwnerUserId") ~= player.UserId
				or old:GetAttribute("P14AssignmentRevision") ~= base:GetAttribute(
					"BaseOwnershipRevision"
				)
				or old:GetAttribute("P14BaseDesignId")
					~= base:GetAttribute("SelectedBaseDesignId")
			)
		then
			old:Destroy()
			old = nil
		end
		if valid and not old then
			local frame = Presenter.BannerFrame(base)
			local host = base:FindFirstChild("Foundation")
			if frame and host then
				local model = clone(id, frame, host, "P14BaseBanner", player.UserId)
				if model then
					model:SetAttribute(
						"P14AssignmentRevision",
						base:GetAttribute("BaseOwnershipRevision")
					)
					model:SetAttribute("P14BaseDesignId", base:GetAttribute("SelectedBaseDesignId"))
					model.Parent = base
				end
			end
		end
		local visual = base:FindFirstChild("P14BaseBanner")
		outcome(
			base,
			player,
			base,
			cart,
			"BaseBanner",
			id,
			Rules.Owns(data, id),
			valid and visual ~= nil and visual:GetAttribute("P14CosmeticId") == id
		)
	end
end
function Presenter.Step()
	local folder = templates()
	if folder ~= assetFolder then
		if assetConnection then
			assetConnection:Disconnect()
			assetConnection = nil
		end
		assetFolder = folder
		if folder then
			assetConnection = folder.ChildAdded:Connect(function(child)
				for _, row in retries do
					if row.Id == child.Name then
						row.Remaining = 1
						row.Next = os.clock()
					end
				end
			end)
		end
	end
	local now = os.clock()
	for holder, row in retries do
		if
			not holder.Parent
			or not row.Player.Parent
			or (row.Slot == "Flag" and (holder:GetAttribute("OwnerUserId") ~= row.Player.UserId or holder:GetAttribute(
				"CartGeneration"
			) ~= row.Generation))
			or (
				row.Slot == "BaseBanner"
				and holder:GetAttribute("OwnerUserId") ~= row.Player.UserId
			)
		then
			retries[holder] = nil
		elseif row.Remaining > 0 and now >= row.Next then
			row.Remaining -= 1
			row.Next = now + 5
			local data = Profiles:GetReadableData(row.Player)
			if data and Profiles:IsWritable(row.Player) then
				Presenter.Reconcile(row.Player, data, row.Base, row.Cart)
			end
		end
	end
end
-- Read-only ownership counts for bounded lifecycle checks. The runtime service
-- owns scheduling; this presenter adds no task/connection when queried.
function Presenter.GetDiagnostics()
	local result = {
		baseBindingRecords = 0,
		cartBindingRecords = 0,
		baseConnections = 0,
		cartConnections = 0,
		retryEntries = 0,
		assetListener = if assetConnection and assetConnection.Connected then 1 else 0,
		ownedScheduledTasks = 0,
	}
	for _, binding in baseBindings do
		result.baseBindingRecords += 1
		for _, connection in binding do
			if connection.Connected then
				result.baseConnections += 1
			end
		end
	end
	for _, binding in cartBindings do
		result.cartBindingRecords += 1
		for _, connection in binding.Connections do
			if connection.Connected then
				result.cartConnections += 1
			end
		end
	end
	for _ in retries do
		result.retryEntries += 1
	end
	return result
end
return Presenter
