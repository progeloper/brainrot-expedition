--!nocheck
-- A development-only example of the accepted-attack handoff. These actors,
-- attack acceptance and ejection are isolated adapters for the service tests.
local Run = game:GetService("RunService")
local Environment = require(game.ReplicatedStorage.Shared.Config.Environment)
local Shield = require(script.Parent.Parent.Parent.Services.CartShieldService)
local Fixture = {}

function Fixture.new()
	assert(Run:IsStudio() and not Environment.IsProduction, "Shield handoff fixture is Development Studio only")
	local folder = Instance.new("Folder") folder.Name = "FIXTURE_SHIELD_HANDOFF" folder.Parent = workspace
	local owner, attacker, second = { UserId = -501 }, { UserId = -502 }, { UserId = -503 }
	local actors = { [owner] = true, [attacker] = true, [second] = true }
	local at, capacity, ownBase, protectedArea, enabled, ready = 0, 2, true, false, true, true
	local generations = { [owner] = 1, [attacker] = 2, [second] = 3 }
	local function cart(generation)
		local model = Instance.new("Model") model.Name = "FIXTURE_CART_" .. generation model.Parent = folder
		local root = Instance.new("Part") root.Anchored = true root.Parent = model model.PrimaryPart = root
		model:SetAttribute("OwnerUserId", owner.UserId) model:SetAttribute("CartGeneration", generation) model:SetAttribute("RuntimeCart", true)
		return { Model = model, OwnerUserId = owner.UserId, Generation = generation }
	end
	local record = cart(1)
	local cargo, cargoRevision = { Slot1 = { ItemId = "FIXTURE_CARGO_A", BrainrotId = "FIXTURE_PROVIDER", AttachmentIndex = 1 }, Slot2 = { ItemId = "FIXTURE_CARGO_B", BrainrotId = "FIXTURE_PROVIDER", AttachmentIndex = 2 } }, 0
	local commits, messages = 0, {}
	local service = Shield.new({
		Now = function() return at end, Enabled = function() return enabled end,
		IsPlayer = function(player) return actors[player] == true end,
		Session = function(player) return if actors[player] then { Generation = generations[player] } else nil end,
		OwnerReady = function(player) return player == owner and ready end,
		Capacity = function() return capacity end,
		Cart = function(player) return if player == owner then record else nil end,
		Player = function(userId) return if userId == owner.UserId then owner else nil end,
		CargoRecord = function(model, slot) return if model == record.Model then cargo[slot] else nil end,
		CargoRevision = function() return cargoRevision end,
		OwnBase = function() return if ownBase then "FIXTURE_BASE:" .. record.Generation else nil end,
		ProtectedArea = function() return protectedArea end,
		Feedback = function(player, value) table.insert(messages, { player = player, payload = value }) end,
	})
	service:Start() service:Reconcile(owner)
	local f = { service = service, owner = owner, attacker = attacker, second = second, messages = messages }
	function f.snapshot() return service:GetSnapshot(owner) end
	function f.setTime(value) at = value end
	function f.setBase(value) ownBase = value service:Reconcile(owner) end
	function f.setCapacity(value) capacity = value service:Reconcile(owner) end
	function f.setProtectedArea(value) protectedArea = value end
	function f.setEnabled(value) enabled = value service:Reconcile(owner) end
	function f.setReady(value) ready = value end
	function f.setGeneration(player, generation) generations[player] = generation end
	function f.context(sequence, player, item, slot)
		player = player or attacker slot = slot or "Slot1"
		return { subject = "CartCargo", attackId = "FIXTURE_ATTACK:" .. player.UserId .. ":" .. sequence,
			attackSequence = sequence, attacker = player, attackerGeneration = generations[player],
			cart = record.Model, cartGeneration = record.Generation, cargoItemId = item or (cargo[slot] and cargo[slot].ItemId),
			cargoSlotId = slot, cargoRevision = cargoRevision }
	end
	function f.valid(context) return context.subject == "CartCargo" and cargo[context.cargoSlotId] ~= nil end
	function f.knockoff(context)
		-- Exact same entry is removed only at this final accepted commit. Real
		-- The real Phase 10 caller retains its drop/placement/ownership/population policy.
		if not cargo[context.cargoSlotId] or cargo[context.cargoSlotId].ItemId ~= context.cargoItemId then return false end
		cargo[context.cargoSlotId] = nil cargoRevision += 1 commits += 1 return true
	end
	function f.attack(context, validate, commit) return service:ResolveValidatedCargoAttack(context, validate or f.valid, commit or f.knockoff) end
	function f.commits() return commits end
	function f.cargo() return cargo end
	function f.replaceCart() record = cart(record.Generation + 1) service:Reconcile(owner) return record.Model end
	function f.clearCargo() table.clear(cargo) cargoRevision += 1 end
	function f.removeCargo(slot) cargo[slot] = nil cargoRevision += 1 end
	function f.bumpCargoRevision() cargoRevision += 1 end
	function f.addCargo(slot, item) cargo[slot] = { ItemId = item, BrainrotId = "FIXTURE_PROVIDER", AttachmentIndex = tonumber(slot:match("%d+$")) } cargoRevision += 1 end
	function f.destroy() service:Stop() folder:Destroy() end
	return f
end

function Fixture.Run()
	local f = Fixture.new()
	local result = {}
	local ok, failure = xpcall(function()
		f.setBase(false)
		for sequence, at in { 10, 10.1, 14.999, 15, 19.999, 20 } do
			f.setTime(at)
			local decision = f.attack(f.context(sequence))
			table.insert(result, { at = at, decision = decision, state = f.snapshot(), commits = f.commits() })
		end
	end, debug.traceback)
	f.destroy()
	assert(ok, failure)
	return result
end

return Fixture
