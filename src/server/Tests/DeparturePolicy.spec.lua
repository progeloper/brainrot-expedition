--!nocheck

return function()
	local Policy = require(script.Parent.Parent.Services.DeparturePolicy)
	local E, A = Policy.Events, Policy.AssetClasses

	describe("Phase 7A-3 departure policy contract", function()
		it("keeps only still-unapproved ownership consequences fail-closed", function()
			for _, row in
				{
					{ E.OccupiedSlotReplacement, A.Banked },
					{ E.ReturnToSlot, A.Banked },
				}
			do
				local result = Policy.Resolve(row[1], row[2])
				expect(result.ok).to.equal(false)
				expect(result.code).to.equal("POLICY_REQUIRED")
				expect(result.action).to.equal(nil)
			end
		end)

		it("encodes the approved death and logout matrix by durable state and location", function()
			expect(Policy.Resolve(E.RejoinUnassigned, A.Banked).action).to.equal(
				"ReturnToAvailableSlotOrRetainOwned"
			)
			expect(Policy.Resolve(E.CharacterDeath, A.FreshUnbanked, "Carried").action).to.equal(
				"PublishExistingWorldDrop"
			)
			expect(Policy.Resolve(E.CharacterReset, A.Banked, "Carried").action).to.equal(
				"ReturnToAvailableSlotOrSecuredDrop"
			)
			expect(Policy.Resolve(E.PlayerLogout, A.FreshUnbanked, "Carried").action).to.equal(
				"PublishExistingWorldDrop"
			)
			expect(Policy.Resolve(E.PlayerLogout, A.FreshUnbanked, "CartCargo").action).to.equal(
				"PublishExistingWorldDrop"
			)
			expect(Policy.Resolve(E.PlayerLogout, A.Banked, "Carried").action).to.equal(
				"ReturnToAvailableSlotOrRetainOwned"
			)
			expect(Policy.Resolve(E.PlayerLogout, A.Banked, "CartCargo").action).to.equal(
				"ReturnToAvailableSlotOrRetainOwned"
			)
			expect(Policy.Resolve(E.PlayerLogout, A.Banked).code).to.equal(
				"POLICY_CONTEXT_REQUIRED"
			)
		end)

		it("preserves only the explicitly approved runtime reconstruction outcomes", function()
			expect(Policy.Resolve(E.DeliberateWorldDrop, A.FreshUnbanked).action).to.equal(
				"PublishExistingWorldDrop"
			)
			expect(Policy.Resolve(E.CartReplacement, A.Banked).action).to.equal(
				"ReturnToAvailableSlotOrRetainOwned"
			)
			expect(Policy.Resolve(E.BaseReassignment, A.StoredDisplay).action).to.equal(
				"RebindSavedState"
			)
			expect(Policy.Resolve(E.RuntimeTeardown, A.StoredDisplay).action).to.equal(
				"RemoveRuntimeVisual"
			)
			expect(Policy.Resolve(E.CharacterDeath, A.StoredDisplay).action).to.equal(
				"PreserveSavedState"
			)
		end)

		it("does not classify a carried banked individual as fresh", function()
			local result = Policy.BuildPlan({
				{
					individualId = "durable-a",
					event = E.CharacterDeath,
					assetClass = A.Banked,
					location = "Carried",
				},
			})
			expect(result.ok).to.equal(true)
			expect(result.actions[1].assetClass).to.equal(A.Banked)
			expect(result.actions[1].action).to.equal("ReturnToAvailableSlotOrSecuredDrop")
		end)

		it("keeps banked deliberate drops secured without ownership relinquishment", function()
			expect(Policy.Resolve(E.DeliberateWorldDrop, A.Banked, "World").action).to.equal(
				"PublishSecuredOwnedDrop"
			)
		end)

		it("deduplicates identical rows and rejects contradictory outcomes", function()
			local row = {
				individualId = "durable-a",
				event = E.CartReplacement,
				assetClass = A.Banked,
				location = "Cargo",
			}
			local same = Policy.BuildPlan({ row, table.clone(row) })
			expect(same.ok).to.equal(true)
			expect(#same.actions).to.equal(1)

			local conflict = Policy.BuildPlan({
				row,
				{
					individualId = "durable-a",
					event = E.DeliberateWorldDrop,
					assetClass = A.Banked,
					location = "World",
				},
			})
			expect(conflict.ok).to.equal(false)
			expect(conflict.code).to.equal("CONTRADICTORY_OUTCOMES")
		end)

		it("never supplies a default for invalid values", function()
			expect(Policy.Resolve("Unknown", A.Banked).code).to.equal("INVALID_EVENT")
			expect(Policy.Resolve(E.PlayerLogout, "Unknown").code).to.equal("INVALID_ASSET_CLASS")
		end)
	end)
end
