--!strict

local CartModelUtility = {}

function CartModelUtility.SetAnchored(cartModel: Model, anchored: boolean)
	for _, descendant in cartModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
end

function CartModelUtility.SetRootAnchoredOnly(cartModel: Model, rootAnchored: boolean)
	local root = cartModel:FindFirstChild("Root")

	assert(root ~= nil and root:IsA("BasePart"), "Cart model requires Root BasePart")

	for _, descendant in cartModel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.Anchored = descendant == root and rootAnchored
	end
end

function CartModelUtility.GetRoot(cartModel: Model): BasePart
	local root = cartModel:FindFirstChild("Root")

	assert(root ~= nil and root:IsA("BasePart"), "Cart model requires Root BasePart")

	return root
end

function CartModelUtility.GetDriverSeat(cartModel: Model): VehicleSeat
	local seat = cartModel:FindFirstChild("DriverSeat")

	assert(seat ~= nil and seat:IsA("VehicleSeat"), "Cart model requires DriverSeat")

	return seat
end

function CartModelUtility.ZeroVelocities(cartModel: Model)
	for _, descendant in cartModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero

			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

return CartModelUtility
