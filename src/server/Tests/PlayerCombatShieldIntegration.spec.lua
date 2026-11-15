--!nocheck
-- Actual PlayerCombatService + actual Shield runtime. Characters/carts are real
-- instances; isolated sessions and cargo/world adapters expose transaction order.
return function()
	local Combat = require(script.Parent.Parent.Services.PlayerCombatService)
	local Fixture = require(script.Parent.Support.ShieldHandoffFixture)
	local Analytics = require(script.Parent.Parent.Services.Phase13AnalyticsService)
	local function fixture(callback)
		Analytics:_ResetForTests()
		local f = Fixture.new()
		local instances = {}
		local actors = { f.owner, f.attacker, f.second }
		local function own(instance)
			table.insert(instances, instance)
			return instance
		end
		for _, actor in actors do
			local character = own(Instance.new("Model"))
			character.Name = "FIXTURE_SHIELD_COMBAT_CHARACTER"
			character.Parent = workspace
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = true
			root.CanCollide = false
			root.Position = Vector3.new(10000, 100, 10000)
			root.Parent = character
			local humanoid = Instance.new("Humanoid")
			humanoid.RequiresNeck = false
			humanoid.Parent = character
			character.PrimaryPart = root
			character:SetAttribute("Phase10CharacterGeneration", 1)
			actor.Character, actor.Root, actor.Ready, actor.Playtime, actor.Attributes = character, root, true, 900, {}
			function actor:GetAttribute(key)
				return self.Attributes[key]
			end
			function actor:SetAttribute(key, value)
				self.Attributes[key] = value
			end
		end
		local cart = f.context(1).cart
		cart.PrimaryPart.Position = Vector3.new(10000, 100, 10000)
		cart:SetAttribute("CartId", "CRT_001")
		local container = Instance.new("Folder")
		container.Name = "CargoVisuals"
		container.Parent = cart
		local visual = Instance.new("Model")
		visual.Name = "FIXTURE_SHIELD_CARGO_VISUAL"
		visual.Parent = container
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Anchored = true
		body.CanCollide = false
		body.Position = Vector3.new(10000, 102, 9995)
		body.Parent = visual
		visual.PrimaryPart = body
		for _, name in { "CaptureAttachment", "CargoAttachment" } do
			local attachment = Instance.new("Attachment")
			attachment.Name = name
			attachment.Parent = body
		end
		local counts = { prepare = 0, discard = 0, worldCommit = 0, detach = 0, finalize = 0, population = 0 }
		local prepared, fresh, onPrepare = {}, true, nil
		local cargo = {}
		function cargo:ResolveHit(part)
			local record = f.cargo().Slot1
			if part ~= body or not record or not visual.Parent then
				return nil
			end
			return {
				Cart = cart,
				Record = record,
				Visual = visual,
				Revision = f.context(1).cargoRevision,
				Fresh = fresh,
			}
		end
		function cargo:CanAcceptCargo()
			return true
		end
		function cargo:DetachSlotForTransfer(model, slot, item)
			expect(model).to.equal(cart)
			expect(slot).to.equal("Slot1")
			local record = f.cargo()[slot]
			if not record or record.ItemId ~= item then
				return nil
			end
			counts.detach += 1
			f.removeCargo(slot)
			return { Record = record, Slot = slot }
		end
		function cargo:RestoreTransfer(_, token)
			f.cargo()[token.Slot] = token.Record
			f.bumpCargoRevision()
			return true
		end
		function cargo:FinalizeTransfer(_, token)
			expect(token ~= nil).to.equal(true)
			counts.finalize += 1
			visual:Destroy()
			return true
		end
		local world = {}
		function world.PrepareFreshRelease(record)
			counts.prepare += 1
			local model = own(visual:Clone())
			model.Parent = nil
			local token = { Record = record, Model = model }
			prepared[token] = true
			if onPrepare then
				onPrepare()
			end
			return token
		end
		function world.CommitFreshRelease(token, commit)
			counts.worldCommit += 1
			if not prepared[token] or not commit() then
				return nil, "SOURCE_CHANGED"
			end
			prepared[token] = nil
			token.Model.Parent = workspace
			counts.population += 1
			return token.Model
		end
		function world.DiscardFreshRelease(token)
			if not prepared[token] then
				return false
			end
			prepared[token] = nil
			counts.discard += 1
			token.Model:Destroy()
			return true
		end
		Combat:_ConfigureForTests({
			Now = f.service.D.Now,
			Ready = function(actor)
				return actor.Ready
			end,
			Camp = function(position)
				return position.X == 0
			end,
			Playtime = function(actor)
				return actor.Playtime
			end,
			Players = function()
				return actors
			end,
			PlayerByUserId = function(userId)
				for _, actor in actors do
					if actor.UserId == userId then
						return actor
					end
				end
			end,
			PlayerFromCharacter = function(character)
				for _, actor in actors do
					if actor.Character == character then
						return actor
					end
				end
			end,
		})
		Combat:ConfigureTransactions({
			Cargo = cargo,
			World = world,
			Shield = f.service,
			Carry = {
				GetCarriedRecord = function()
					return nil
				end,
			},
			Banked = {
				ClassifyRecord = function()
					return "FreshUnbanked"
				end,
			},
			ValidateContext = function(actor, context)
				return context.Character == actor.Character
			end,
			Name = function()
				return "FIXTURE_CATCH"
			end,
		})
		f.setBase(false)
		f.counts, f.cart, f.visual, f.body = counts, cart, visual, body
		function f.setFresh(value)
			fresh = value
		end
		function f.onPrepare(value)
			onPrepare = value
		end
		function f.impact(sequence, actor, overrides)
			actor = actor or f.attacker
			local intent = { RequestId = sequence, TargetItemId = "FIXTURE_CARGO_A", TargetCartId = "CRT_001" }
			for key, value in overrides or {} do
				intent[key] = value
			end
			local context = { Character = actor.Character, AcceptedRequestId = sequence }
			local hit = { Instance = body, Position = body.Position }
			return Combat:ResolveImpact(actor, context, hit, hit, intent)
		end
		local ok, failure = xpcall(function()
			callback(f)
		end, debug.traceback)
		Combat:ConfigureTransactions(nil)
		Combat:_ConfigureForTests(nil)
		f.destroy()
		for _, instance in instances do
			instance:Destroy()
		end
		assert(ok, failure)
	end

	describe("Installed Phase 10 cargo-hit Shield integration", function()
		it("blocks before world activation, detach, player immunity or population changes", function()
			fixture(function(f)
				f.setTime(10)
				local original = f.cargo().Slot1
				local handled, outcome = f.impact(1)
				expect(handled).to.equal(true)
				expect(outcome).to.equal("CargoShieldBlocked")
				expect(f.snapshot().remaining).to.equal(1)
				expect(f.snapshot().protectedUntil).to.equal(15)
				expect(f.cargo().Slot1).to.equal(original)
				expect(f.counts.worldCommit).to.equal(0)
				expect(f.counts.detach).to.equal(0)
				expect(f.counts.finalize).to.equal(0)
				expect(f.counts.population).to.equal(0)
				expect(f.counts.discard).to.equal(1)
				expect(f.owner:GetAttribute("Phase10ProtectionEnd")).to.equal(nil)
				expect(f.owner:GetAttribute("Phase10DazeEnd")).to.equal(nil)
				expect(Combat:CanAttack(f.second, f.owner)).to.equal(true)
				expect(Combat:CanAttack(f.owner, f.attacker)).to.equal(true)
			end)
		end)
		it("keeps the exact window table, then performs the original knockoff and finalization once", function()
			fixture(function(f)
				for sequence, at in { 10, 10.1, 14.999, 15, 19.999 } do
					f.setTime(at)
					expect(select(2, f.impact(sequence))).to.equal("CargoShieldBlocked")
					expect(f.snapshot().remaining).to.equal(if sequence <= 3 then 1 else 0)
					expect(f.snapshot().protectedUntil).to.equal(if sequence <= 3 then 15 else 20)
					expect(f.counts.worldCommit).to.equal(0)
				end
				f.setTime(20)
				expect(select(2, f.impact(6))).to.equal("CargoKnockedLoose")
				expect(f.cargo().Slot1).to.equal(nil)
				expect(f.cargo().Slot2 ~= nil).to.equal(true)
				expect(f.counts.worldCommit).to.equal(1)
				expect(f.counts.detach).to.equal(1)
				expect(f.counts.finalize).to.equal(1)
				for _ = 1, 20 do
					Analytics:Step(0)
				end
				local steps = 0
				for _, event in Analytics:GetRecorder() do
					if event.kind == "Funnel" and event.name == "TheftBranch" then
						steps += 1
					end
				end
				expect(steps).to.equal(2)
				expect(f.counts.population).to.equal(1)
				expect(f.owner:GetAttribute("Phase10ProtectionEnd")).to.equal(25)
				expect(f.owner:GetAttribute("Phase10DazeEnd")).to.equal(0)
			end)
		end)
		it("rejects beginner, Camp, banked cargo and stale target rules before Shield spending", function()
			fixture(function(f)
				f.setTime(10)
				f.attacker.Playtime = 899
				expect(select(2, f.impact(1))).to.equal("ProtectionOptOutRequired")
				f.attacker.Playtime = 900
				f.owner.Root.Position = Vector3.new(0, 1000, 9000)
				expect(select(2, f.impact(2))).to.equal("ProtectedTarget")
				f.owner.Root.Position = Vector3.new(10000, 100, 10000)
				f.setFresh(false)
				expect(select(2, f.impact(3))).to.equal("ProtectedTarget")
				f.setFresh(true)
				expect(select(2, f.impact(4, nil, { TargetItemId = "FIXTURE_STALE" }))).to.equal("StaleTarget")
				expect(f.snapshot().remaining).to.equal(2)
				expect(f.snapshot().protectedUntil).to.equal(0)
				expect(f.counts.prepare).to.equal(0)
				expect(f.counts.detach).to.equal(0)
				for _ = 1, 20 do
					Analytics:Step(0)
				end
				for _, event in Analytics:GetRecorder() do
					expect(event.kind == "Funnel" and event.name == "TheftBranch").to.equal(false)
				end
			end)
		end)
		it("does not accept an intent identity that differs from the server-accepted context", function()
			fixture(function(f)
				f.setTime(10)
				expect(select(2, f.impact(1, nil, { RequestId = 2 }))).to.equal("StaleTarget")
				expect(f.snapshot().remaining).to.equal(2)
				expect(f.counts.discard).to.equal(1)
				expect(f.counts.worldCommit).to.equal(0)
			end)
		end)
		it("rejects revision changes during safe-drop staging and discards the unpublished preparation", function()
			fixture(function(f)
				f.setTime(10)
				f.onPrepare(function()
					f.bumpCargoRevision()
				end)
				expect(select(2, f.impact(1))).to.equal("StaleTarget")
				expect(f.snapshot().remaining).to.equal(2)
				expect(f.snapshot().protectedUntil).to.equal(0)
				expect(f.counts.discard).to.equal(1)
				expect(f.counts.worldCommit).to.equal(0)
				expect(f.counts.detach).to.equal(0)
				expect(f.counts.population).to.equal(0)
			end)
		end)
		it("retains normal Phase 10 knockoff when Shield is disabled", function()
			fixture(function(f)
				f.setTime(10)
				f.impact(1)
				f.setTime(11)
				f.setEnabled(false)
				expect(select(2, f.impact(2))).to.equal("CargoKnockedLoose")
				expect(f.snapshot().remaining).to.equal(1)
				expect(f.snapshot().protectedUntil).to.equal(0)
				expect(f.counts.worldCommit).to.equal(1)
				expect(f.counts.finalize).to.equal(1)
			end)
		end)
	end)
end
