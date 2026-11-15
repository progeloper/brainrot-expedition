--!nocheck
-- Temporary Development SERVER Script, deliberately absent from Rojo mapping.
-- Run only with the real player already on foot beside their empty cart.
-- Requires existing real ownership; grants no money, upgrades or banked items.
-- This is synthetic capacity evidence, not the natural cart-expedition test.
local EXPECTED_CAPACITY = 4
local OWNER_USER_ID = 10098729613

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio server required"
)
assert(require(RS.Shared.Config.Environment).Name == "Development", "Development only")
local server = game.ServerScriptService.Server
local World = require(server.Systems.DevelopmentBrainrotSpawner)
local Interaction = require(server.Systems.BrainrotInteractionSystem)
local Cargo = require(server.Services.CartCargoService)
local Cart = require(server.Services.CartService)
local Profile = require(server.Services.PlayerDataService)
local Validator = require(RS.Shared.Validation.CartAssetValidator)
local player = assert(game.Players:GetPlayerByUserId(OWNER_USER_ID), "Expected real test player")
local character = assert(player.Character, "Character unavailable")
local root = assert(character:FindFirstChild("HumanoidRootPart"), "Character root unavailable")
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"), "Humanoid unavailable")
local cart = assert(Cart:GetCart(player), "Authoritative owner cart unavailable")
assert(humanoid.SeatPart == nil and humanoid.Health > 0, "Player must be alive and on foot")
assert(not Interaction.IsCarrying(player), "Do not consume an existing carried individual")
assert(Cargo:GetCargoCount(cart) == 0, "Do not disturb existing cargo")
assert(EXPECTED_CAPACITY == 3 or EXPECTED_CAPACITY == 4, "Only approved starter capacities")
local data = assert(Profile:GetReadableData(player), "Profile unavailable")
assert(
	(data.Progression.Upgrades.CARGO_1 == true) == (EXPECTED_CAPACITY == 4),
	"Ownership does not match test mode"
)
assert(Cargo:GetCargoCapacityReadiness(cart).status == "Ready", "Cargo layout not ready")
assert(Cargo:GetCargoCapacity(cart) == EXPECTED_CAPACITY, "Unexpected effective capacity")
for _, slot in assert(Validator.GetCargoSlotMap(cart, EXPECTED_CAPACITY)) do
	assert(
		(slot.Attachment.WorldPosition - root.Position).Magnitude <= 16,
		"Walk nearer all cargo slots first"
	)
end

local minted, preparedTokens, rows = {}, {}, {}
local function acquire(species, index)
	local record =
		assert(World.CreateWorldRecord(species, "SPEC_PRE7F_CAPACITY_" .. index, root.CFrame))
	minted[record.ItemId] = true
	local prepared = assert(World.PrepareWorldRepresentation(record, root.CFrame))
	table.insert(preparedTokens, prepared)
	local pose = World.FindSafeReleasePose(prepared, root.CFrame, {}, false, character)
	assert(pose, "No safe nearby fixture ground; move the player normally and retry")
	prepared.Model:PivotTo(pose) -- Private preparation only, never a published world teleport.
	local model = assert(World.ActivatePreparedWorld(prepared))
	assert(World.TrySleep(model), "World sleep rejected")
	local authoritative, state = World.GetWorldRecord(model)
	assert(
		authoritative.ItemId == record.ItemId and state == "WorldSleeping",
		"Wrong sleep identity"
	)
	local picked, why = Interaction.TryPickupWorld(player, model, record.ItemId)
	assert(picked, "Pickup rejected: " .. tostring(why))
	local carried = assert(Interaction.GetCarriedRecord(player), "No carry after successful pickup")
	assert(
		carried.ItemId == record.ItemId and carried.BrainrotId == species,
		"Carry identity changed"
	)
	assert(World.GetWorldModelById(record.ItemId) == nil, "World duplicate after pickup")
	return carried
end

local ok, failure = xpcall(function()
	local species = { "BRT_007", "BRT_010", "BRT_016", "BRT_028" }
	for index = 1, EXPECTED_CAPACITY do
		local record = acquire(species[index], index)
		local placed, why =
			Interaction.TryPlaceInCargo(player, cart, "Slot" .. index, record.ItemId)
		assert(placed, "Cargo placement rejected: " .. tostring(why))
		local stored = assert(Cargo:GetSlotRecord(cart, "Slot" .. index))
		assert(
			stored.ItemId == record.ItemId and stored.BrainrotId == record.BrainrotId,
			"Cargo identity changed"
		)
		assert(Interaction.GetCarriedRecord(player) == nil, "Carry duplicate after cargo commit")
		assert(Cargo:GetCargoCount(cart) == index, "Wrong cargo count")
		table.insert(
			rows,
			{ slot = index, id = stored.ItemId, species = stored.BrainrotId, result = "LOADED" }
		)
	end
	assert(not Cargo:CanAcceptCargo(cart), "Full cart still accepts cargo")
	local overflow = acquire("BRT_010", EXPECTED_CAPACITY + 1)
	local outOfCapacity, invalidReason = Interaction.TryPlaceInCargo(
		player,
		cart,
		"Slot" .. (EXPECTED_CAPACITY + 1),
		overflow.ItemId
	)
	assert(not outOfCapacity and invalidReason == "INVALID_SLOT", "Unexpected extra-slot result")
	local replaced, occupiedReason =
		Interaction.TryPlaceInCargo(player, cart, "Slot1", overflow.ItemId)
	assert(not replaced and occupiedReason == "OCCUPIED", "Fifth load replaced existing cargo")
	assert(
		Interaction.GetCarriedRecord(player).ItemId == overflow.ItemId,
		"Rejected cargo lost carry"
	)
	assert(Cargo:GetCargoCount(cart) == EXPECTED_CAPACITY, "Overflow changed cargo count")
	table.insert(rows, {
		result = "REJECTED_FULL",
		extraSlotCode = invalidReason,
		occupiedSlotCode = occupiedReason,
		carriedId = overflow.ItemId,
	})
	local visualParts = 0
	for _, part in cart.CargoVisuals:GetDescendants() do
		if part:IsA("BasePart") then
			visualParts += 1
			assert(
				not part.CanCollide
					and not part.CanTouch
					and not part.CanQuery
					and part.Massless
					and not part.Anchored,
				"Cargo visual is physically active"
			)
		end
	end
	assert(visualParts > 0, "No mounted visuals")
	print(
		"[PRE7F_CARGO_CAPACITY] PASS capacity="
			.. EXPECTED_CAPACITY
			.. " visualParts="
			.. visualParts
	)
end, debug.traceback)

-- Always retire only this diagnostic's minted identities. No sale, profile
-- ownership mutation, world drop, cart reset or natural target is involved.
local cleanupErrors = {}
local carried = Interaction.GetCarriedRecord(player)
if carried and minted[carried.ItemId] then
	local removed, why =
		Interaction.ConsumeCarriedBrainrot(player, carried.ItemId, "StudioCapacityFixtureCleanup")
	if not removed then
		table.insert(cleanupErrors, tostring(why))
	end
end
for _, record in Cargo:GetCargoSnapshot(cart) do
	if minted[record.ItemId] then
		local token, why = Cargo:DetachForTransfer(cart, record.ItemId)
		if token then
			local finalized, finalReason = Cargo:FinalizeTransfer(cart, token)
			if not finalized then
				table.insert(cleanupErrors, tostring(finalReason))
			end
		else
			table.insert(cleanupErrors, tostring(why))
		end
	end
end
for id in minted do
	Cargo:CancelPendingReturnForTesting(id)
	World.DestroyWorldForTesting(id)
	assert(
		Profile:GetReadableData(player).Collection.BrainrotInstances[id] == nil,
		"Fixture acquired persistent ownership"
	)
end
for _, prepared in preparedTokens do
	World.DiscardPreparedWorld(prepared)
end
assert(#cleanupErrors == 0, "Exact fixture cleanup failed: " .. table.concat(cleanupErrors, "; "))
assert(
	Cargo:GetCargoCount(cart) == 0 and Interaction.GetCarriedRecord(player) == nil,
	"Fixture custody retained"
)
print("[PRE7F_CARGO_CAPACITY_CLEANUP] PASS")
assert(ok, failure)
return rows
