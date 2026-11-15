--!nocheck
-- Deterministic rules and boundary tests. Native transport tests exercise the
-- same state transitions with disposable models; device input is separate QA.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Weapons = require(RS.Shared.Config.Weapons)
	local Stats = require(RS.Shared.Utility.WeaponStats)
	local Cadence = require(RS.Shared.Utility.WeaponCadence)
	local Rules = require(RS.Shared.Utility.Phase12Rules)
	local Config = require(RS.Shared.Config.Phase12)
	local Ui = require(RS.Shared.Utility.Phase13CombatUiRules)
	local Presentation = require(RS.Shared.Utility.Phase13PresentationRules)
	local Escape = require(script.Parent.Parent.Utility.Phase12EscapeRuntime)
	local Reset = require(script.Parent.Parent.Utility.Phase13ResetPolicy)
	describe("Phase 13 approved weapon and capture contract", function()
		it("contains exactly eight weapons of each family and one free starter", function()
			local families = { Bow = 0, Crossbow = 0, Gun = 0 }
			local free = 0
			for _, definition in Weapons.GetAll() do
				families[definition.family] += 1
				if definition.price == 0 then
					free += 1
					expect(definition.id).to.equal("HRP_001")
				end
			end
			expect(families.Bow).to.equal(8)
			expect(families.Crossbow).to.equal(8)
			expect(families.Gun).to.equal(8)
			expect(free).to.equal(1)
		end)
		local expected = {
			B1 = { 1, 0.75, 100 },
			B2 = { 1, 0.65, 90 },
			B3 = { 1, 0.85, 115 },
			B4 = { 2, 1.4, 95 },
			C1 = { 2, 1.4, 110 },
			C2 = { 2, 1.2, 95 },
			C3 = { 2, 1.5, 125 },
			C4 = { 2, 1.3, 110 },
			G1 = { 1, 0.45, 70 },
			G2 = { 1, 0.35, 55 },
			G3 = { 1, 0.55, 90 },
			G4 = { 1, 0.4, 75 },
		}
		for _, definition in Weapons.GetAll() do
			it("resolves normative damage/cadence/range for " .. definition.id, function()
				local profile = Stats.Resolve(definition.id)
				local row = expected[definition.profileId]
				expect(profile.damage).to.equal(row[1])
				expect(profile.fireIntervalSeconds).to.equal(row[2])
				expect(profile.rangeStuds).to.equal(row[3])
				expect(profile.projectileSpeedAuthority).to.equal("PresentationOnly")
				expect(profile.projectileSpeedStudsPerSecond).to.equal(500)
			end)
		end
		it("uses only server owned selection and never grants an unowned gun", function()
			expect(
				Stats.GetSelected({ Phase13 = { SelectedWeaponId = "WPN_G01", OwnedWeaponIds = { HRP_001 = true } } }).status
			).to.equal("Unavailable")
			local ready = Stats.GetSelected({
				Phase13 = { SelectedWeaponId = "WPN_G01", OwnedWeaponIds = { HRP_001 = true, WPN_G01 = true } },
			})
			expect(ready.weaponId).to.equal("WPN_G01")
			expect(ready.damage).to.equal(1)
		end)
		it("preserves fractional damage and restores the full Secret threshold after escape", function()
			expect(Rules.Damage(4, 4, 1.25, 2)).to.equal(1.5)
			expect(Rules.Damage(10, 10, 5, 2)).to.equal(0)
			local state = {
				MaxHp = 10,
				RemainingHp = 0,
				CapturedOnce = true,
				EscapeAttemptsUsed = 0,
				EscapeMaxAttempts = 3,
				EscapeDeadline = 1,
				EscapeGeneration = 1,
			}
			local jumped = Escape.CommitJump(state, 1, 1)
			expect(jumped.RemainingHp).to.equal(10)
			expect(jumped.EscapeAttemptsUsed).to.equal(1)
		end)
		it("admits the immediate first shot and prevents fast/slow selection cadence bypass", function()
			expect(Cadence.CanAccept(nil, 10, 0.35)).to.equal(true)
			local slow = Cadence.Accept(10, 1.5)
			expect(Cadence.CanAccept(slow, 10.35, 0.35)).to.equal(false)
			expect(Cadence.CanAccept(slow, 11.5, 0.35)).to.equal(true)
			local fast = Cadence.Accept(12, 0.35)
			expect(Cadence.CanAccept(fast, 12.35, 1.5)).to.equal(false)
			expect(Cadence.CanAccept(fast, 13.5, 1.5)).to.equal(true)
		end)
		it("matches every damage2 HP threshold and the exact2.1875 mounted Legendary example", function()
			for _, row in { { 1, 1 }, { 1, 1 }, { 2, 1 }, { 3, 2 }, { 4, 2 }, { 6, 3 }, { 8, 4 }, { 10, 5 } } do
				local remaining, hits = row[1], 0
				repeat
					remaining = Rules.Damage(remaining, row[1], 1, 2)
					hits += 1
				until remaining == 0
				expect(hits).to.equal(row[2])
			end
			expect(Rules.Damage(4, 4, 2.1875, 2)).to.equal(0)
		end)

		it("uses exact 12/10/8 second rarity sleep deadlines", function()
			for _, id in { "Common", "Uncommon" } do
				expect(Rules.GroundSleepForRarity(id)).to.equal(12)
			end
			for _, id in { "Rare", "Epic" } do
				expect(Rules.GroundSleepForRarity(id)).to.equal(10)
			end
			for _, id in { "Legendary", "Mythic", "Celestial", "Astral", "Secret" } do
				expect(Rules.GroundSleepForRarity(id)).to.equal(8)
			end
		end)
	end)
	describe("Phase 13 reset and bounded local presentation", function()
		it("preserves exact escape remaining time, attempts and generation without a random draw", function()
			local state = {
				MaxHp = 4,
				RemainingHp = 0,
				CapturedOnce = true,
				EscapeAttemptsUsed = 1,
				EscapeMaxAttempts = 2,
				EscapeDeadline = 10.25,
				EscapeGeneration = 7,
			}
			local paused = Escape.PauseForReset(state, 9.5, 44)
			expect(paused.EscapeRemainingSeconds).to.equal(0.75)
			expect(paused.EscapeDeadline).to.equal(nil)
			expect(Escape.CommitJump(paused, 100, 1)).to.equal(nil)
			local transfer = Escape.Pickup(paused, Config.EscapeByRarity.Legendary, 100, function()
				error("Reset cannot reroll")
			end)
			expect(transfer.EscapeRemainingSeconds).to.equal(0.75)
			expect(Escape.ResumeAfterReset(transfer, 100, 43)).to.equal(nil)
			local resumed = Escape.ResumeAfterReset(transfer, 100, 44)
			expect(resumed.EscapeDeadline).to.equal(100.75)
			expect(resumed.EscapeAttemptsUsed).to.equal(1)
			expect(resumed.EscapeGeneration).to.equal(7)
		end)
		it("retires fresh held in every ready Camp split and preserves committed cargo", function()
			for _, inside in { true, false } do
				for _, cartInside in { true, false } do
					local result = Reset.Classify(inside, true, cartInside, true)
					expect(result.ForfeitHeld).to.equal(true)
					expect(result.ForfeitCargo).to.equal(false)
					expect(result.KillCharacter).to.equal(not inside)
				end
			end
		end)
		it("keeps the HP bar thresholds exact while limiting readable fractional text", function()
			expect(Ui.Sample(2.5, 4, nil, 0).color).to.equal("Green")
			expect(Ui.Sample(2, 4, nil, 0).color).to.equal("Amber")
			expect(Ui.Sample(1, 4, nil, 0).color).to.equal("Red")
			expect(Ui.Sample(1.23456, 4, nil, 0).text).to.equal("1.23 / 4")
			expect(Ui.Sample(0, 4, 10, 7).countdown).to.equal("WAKING 3.0s")
			expect(Ui.Sample(0, 4, 10, 6.99).waking).to.equal(false)
		end)
		it("finishes every reset substitute within one second and suppresses reduced motion pop", function()
			expect(Presentation.Reset(0.1, false).scale > 1).to.equal(true)
			expect(Presentation.Reset(0.1, true).scale).to.equal(1)
			expect(Presentation.Reset(0.8, false).done).to.equal(true)
			expect(Presentation.Reset(1, false).transparency).to.equal(1)
		end)
		it("enforces the seven second cinematic, one second skip and quality copy budgets", function()
			expect(Presentation.Rebirth(0.999).canSkip).to.equal(false)
			expect(Presentation.Rebirth(1).canSkip).to.equal(true)
			expect(Presentation.Rebirth(4.5).phase).to.equal("Contract")
			expect(Presentation.Rebirth(5.5).phase).to.equal("Reveal")
			expect(Presentation.Rebirth(7).done).to.equal(true)
			expect(Presentation.CopyCount(48, "High")).to.equal(12)
			expect(Presentation.CopyCount(48, "Medium")).to.equal(6)
			expect(Presentation.CopyCount(48, "Low")).to.equal(3)
		end)
	end)
end
