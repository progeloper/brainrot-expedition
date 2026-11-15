--!nocheck
-- Playtest Fixes Part E: the size ladder by role, the base fit cap and the 6.706 floor (pure parts).

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
	local Ladder = require(RS.Shared.Config.PlaytestFixes).SizeLadder
	local Flags = require(RS.Shared.Config.PlaytestFixesFlags)

	local function near(a, b, tolerance)
		return math.abs(a - b) <= (tolerance or 0.01)
	end

	describe("size ladder heights", function()
		it("matches the rarity table (x reference body)", function()
			local expected = {
				Common = 8.0,
				Uncommon = 8.51,
				Rare = 9.03,
				Epic = 9.80,
				Legendary = 10.57,
				Mythic = 11.35,
				Secret = 12.38,
			}
			for rarity, studs in expected do
				expect(near(Scale.LadderHeight(rarity), studs, 0.02)).to.equal(true)
			end
			expect(Scale.LadderHeight("Rare") > Scale.LadderHeight("Common") + 0.9).to.equal(true)
			expect(near(Scale.LadderHeight(nil), Scale.LadderHeight("Common"))).to.equal(true)
		end)
	end)

	describe("roles", function()
		it("maps the existing contexts to roles", function()
			expect(Scale.Role("CreaturePresentation:Awake")).to.equal("Wild")
			expect(Scale.Role("CreaturePresentation:Sleeping")).to.equal("Wild")
			expect(Scale.Role("WorldPrepared")).to.equal("Wild")
			expect(Scale.Role("FrontTeam")).to.equal("Wild")
			expect(Scale.Role("CreaturePresentation:Deposited")).to.equal("Base")
			expect(Scale.Role("CreaturePresentation:Carried")).to.equal("Carry")
			expect(Scale.Role("CreaturePresentation:Cart")).to.equal("Carry")
			expect(Scale.Role("LightweightVisual")).to.equal("Carry")
			expect(Scale.Role("SomethingElse")).to.equal(nil)
		end)
		it("keeps carry and cargo at today's height", function()
			local model = Instance.new("Model")
			local height = Scale.TargetHeightFor(model, "Carry")
			expect(near(height, Scale.TARGET_HEIGHT_STUDS, 1e-6)).to.equal(true)
			expect(near(Scale.TargetHeightFor(model, nil), Scale.TARGET_HEIGHT_STUDS, 1e-6)).to.equal(
				true
			)
			model:Destroy()
		end)
		it("is off unless the flag is on", function()
			expect(Flags.Part("SizeLadder")).to.equal(false)
			expect(near(Scale.HeightForSpecies("BRT_035", "Wild"), Scale.TARGET_HEIGHT_STUDS, 1e-6)).to.equal(
				true
			)
		end)
	end)

	describe("base display fit", function()
		it("uses the ladder when the model fits 92% of the slot", function()
			local h, reason = Scale.BaseHeight(9.0, 0.5, 0.8)
			expect(near(h, 9.0)).to.equal(true)
			expect(reason).to.equal("ladder")
		end)
		it("caps a long body by depth and a wide body by width", function()
			local h, reason = Scale.BaseHeight(9.8, 0.5, 1.8)
			expect(reason).to.equal("depth")
			expect(near(h * 1.8, Ladder.SlotFootprint.Depth * Ladder.SlotMargin)).to.equal(true)
			local w, why = Scale.BaseHeight(9.8, 1.2, 0.5)
			expect(why).to.equal("width")
			expect(near(w * 1.2, Ladder.SlotFootprint.Width * Ladder.SlotMargin)).to.equal(true)
		end)
		it("never goes below today's height", function()
			local h, reason = Scale.BaseHeight(8.0, 0.5, 2.6)
			expect(reason).to.equal("floor")
			expect(near(h, Ladder.FloorHeight, 1e-6)).to.equal(true)
		end)
	end)
end
