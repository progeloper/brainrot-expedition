--!nocheck
-- Actual client receiver state machine in an inactive disposable native fixture.
-- This is not evidence of multiplayer replication, rendering or network bytes.
return function()
	local RS = game.ReplicatedStorage
	local Rules = require(RS.Shared.Utility.CreatureProtocolRules)
	local Receiver = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CreaturePresentationController)
	local function context(epoch, sequence)
		return { kind = "Context", epoch = epoch, sequence = sequence, regionId = "REGION_FOREST" }
	end
	local function row(revision, generation, state)
		return {
			id = "same-identity",
			speciesId = "BRT_001",
			revision = revision,
			generation = generation,
			state = state or "Awake",
			regionId = "REGION_FOREST",
			scale = 1,
			pose = CFrame.identity,
			attributes = { BrainrotId = "BRT_001", Captured = false },
		}
	end
	local function delta(epoch, sequence, rows, removals)
		return { kind = "Delta", epoch = epoch, sequence = sequence, upserts = rows or {}, removals = removals or {} }
	end
	local function fixture(callback)
		Receiver._ClearForTesting()
		local ok, reason = xpcall(callback, debug.traceback)
		Receiver._ClearForTesting()
		assert(ok, reason)
	end
	describe("Interest creature protocol ordering", function()
		it(
			"uses publication generation across world to held to cargo and pending bank even when source clocks disappear",
			function()
				fixture(function()
					Receiver._AcceptForTesting(context(1, 1))
					for index, state in { "Awake", "Sleeping", "Carried", "Cart", "Deposited" } do
						local incoming = row(index, 0, state)
						incoming.sourceGeneration = if index <= 2 then 73 else nil
						Rules.StampRepresentation(incoming, index + 100)
						Receiver._AcceptForTesting(delta(1, index + 1, { incoming }))
						local current = Receiver.GetSnapshot()[1]
						expect(current.state).to.equal(state)
						expect(current.generation).to.equal(index + 100)
					end
				end)
			end
		)
		it(
			"retains the same cargo through a reset source generation and rejects its stale older representation",
			function()
				fixture(function()
					Receiver._AcceptForTesting(context(1, 1))
					local before = Rules.StampRepresentation(row(1, 0, "Cart"), 200)
					before.sourceGeneration = 4
					Receiver._AcceptForTesting(delta(1, 2, { before }))
					local after = Rules.StampRepresentation(row(2, 0, "Cart"), 201)
					after.sourceGeneration = 5
					Receiver._AcceptForTesting(delta(1, 3, { after }))
					Receiver._AcceptForTesting(delta(1, 4, { before }))
					expect(Receiver.GetSnapshot()[1].id).to.equal("same-identity")
					expect(Receiver.GetSnapshot()[1].revision).to.equal(201)
					expect(Receiver.GetDiagnostics().entries).to.equal(1)
				end)
			end
		)
		it("preserves the 180 stud exit and 160 stud return hysteresis", function()
			expect(Rules.ShouldHideBase(180, false)).to.equal(false)
			expect(Rules.ShouldHideBase(180.01, false)).to.equal(true)
			expect(Rules.ShouldHideBase(179, true)).to.equal(true)
			expect(Rules.ShouldHideBase(160.01, true)).to.equal(true)
			expect(Rules.ShouldHideBase(160, true)).to.equal(false)
		end)
		it("releases receiver representations and its owned resources on Stop", function()
			fixture(function()
				Receiver._AcceptForTesting(context(1, 1))
				Receiver._AcceptForTesting(delta(1, 2, { row(1, 1) }))
				Receiver.Stop()
				local state = Receiver.GetDiagnostics()
				expect(state.entries).to.equal(0)
				expect(state.connections).to.equal(0)
				expect(state.cache.templates).to.equal(0)
				expect(state.cache.connections).to.equal(0)
			end)
		end)
		it("does not admit entities before their confirmed context", function()
			fixture(function()
				expect(Receiver._AcceptForTesting(delta(1, 2, { row(1, 1) }))).to.equal(false)
				expect(Receiver.GetDiagnostics().entries).to.equal(0)
				expect(Receiver._AcceptForTesting(context(1, 3))).to.equal(true)
				expect(Receiver._AcceptForTesting(delta(1, 4, { row(1, 1) }))).to.equal(true)
				expect(Receiver.GetDiagnostics().entries).to.equal(1)
			end)
		end)
		it("clears entries on exit and rejects delayed previous-region snapshots", function()
			fixture(function()
				Receiver._AcceptForTesting(context(1, 1))
				Receiver._AcceptForTesting(delta(1, 2, { row(1, 1) }))
				Receiver._AcceptForTesting(context(2, 3))
				expect(Receiver.GetDiagnostics().entries).to.equal(0)
				expect(Receiver._AcceptForTesting(delta(1, 4, { row(99, 99) }))).to.equal(false)
				expect(Receiver.GetDiagnostics().entries).to.equal(0)
			end)
		end)
		it("retains exactly one identity across sleep, held, cargo and bank publication", function()
			fixture(function()
				Receiver._AcceptForTesting(context(1, 1))
				for index, state in { "Awake", "Sleeping", "Carried", "Cart", "Deposited" } do
					Receiver._AcceptForTesting(delta(1, index + 1, { row(index, 1, state) }))
					expect(Receiver.GetDiagnostics().entries).to.equal(1)
				end
			end)
		end)
		it("prevents a reset-retired representation from returning in a later packet", function()
			fixture(function()
				Receiver._AcceptForTesting(context(1, 1))
				Receiver._AcceptForTesting(delta(1, 2, { row(10, 2) }))
				Receiver._AcceptForTesting(delta(1, 3, {}, { { id = "same-identity", revision = 11, generation = 2 } }))
				Receiver._AcceptForTesting(delta(1, 4, { row(10, 2) }))
				expect(Receiver.GetDiagnostics().entries).to.equal(0)
				Receiver._AcceptForTesting(delta(1, 5, { row(12, 3) }))
				expect(Receiver.GetDiagnostics().entries).to.equal(1)
			end)
		end)
		it("rejects a duplicated or out-of-order packet without regressing state", function()
			fixture(function()
				Receiver._AcceptForTesting(context(1, 1))
				expect(Receiver._AcceptForTesting(delta(1, 3, { row(8, 1) }))).to.equal(true)
				expect(Receiver._AcceptForTesting(delta(1, 2, {}, { row(9, 1) }))).to.equal(false)
				expect(Receiver._AcceptForTesting(delta(1, 3, {}, { row(9, 1) }))).to.equal(false)
				expect(Receiver.GetDiagnostics().entries).to.equal(1)
			end)
		end)
		it("selects the pending platform over retained source mirrors without changing gameplay identity", function()
			expect(Rules.RepresentationPriority("Deposited", true) > Rules.RepresentationPriority("Carried", false)).to.equal(
				true
			)
			expect(Rules.RepresentationPriority("Deposited", true) > Rules.RepresentationPriority("Cart", false)).to.equal(
				true
			)
			expect(Rules.ValidTemplate("BRT_001", "Full")).to.equal(true)
			expect(Rules.ValidTemplate("../private", "Full")).to.equal(false)
			expect(Rules.ValidTemplate("BRT_001", "Arbitrary")).to.equal(false)
		end)
		it("interpolates poses only inside the bounded interpolation window", function()
			local from, to = CFrame.new(0, 0, 0), CFrame.new(10, 0, 0)
			expect(Rules.Interpolate(from, to, -1, 0.1).X).to.equal(0)
			expect(Rules.Interpolate(from, to, 0.05, 0.1).X).to.equal(5)
			expect(Rules.Interpolate(from, to, 1, 0.1).X).to.equal(10)
		end)
	end)
end
