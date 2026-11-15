--!nocheck
-- Playtest Fixes Part C: shot-effect ladder, budgets, authoring and the effects pool.

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Lib = require(RS.Shared.Utility.WeaponFxLibrary)
	local Config = require(RS.Shared.Config.PlaytestFixes).WeaponFx

	describe("WeaponFx tier ladder", function()
		it("keeps every tier inside the per-shot particle budget on High and Low", function()
			for tier = 1, 8 do
				local high = Lib.Counts(tier, "High")
				local low = Lib.Counts(tier, "Low")
				expect(high.total <= Config.MaxBurstParticlesPerShot.High).to.equal(true)
				expect(low.total <= Config.MaxBurstParticlesPerShot.Low).to.equal(true)
				expect(high.muzzle <= Config.Counts.MuzzleFlash.High).to.equal(true)
				expect(high.impact <= Config.Counts.ImpactBurst.High).to.equal(true)
				expect(high.puff <= Config.Counts.SleepPuff.High).to.equal(true)
				-- Low keeps every beat: flash, a hit, one Z
				expect(low.flash >= 1).to.equal(true)
				expect(low.impact >= 1).to.equal(true)
				expect(low.puff >= 1).to.equal(true)
				expect(low.total < high.total).to.equal(true)
			end
		end)
		it(
			"grows by tier: T5+ get a beam core and ground ring, T8 rainbow with two ghosts",
			function()
				expect(Config.Tiers[4].core == true).to.equal(false)
				expect(Config.Tiers[5].core).to.equal(true)
				expect(Lib.Counts(5, "High").ground).to.equal(1)
				expect(Config.Tiers[7].dark).to.equal(true)
				expect(Config.Tiers[8].ghosts).to.equal(2)
				expect(Lib.Style("WPN_B08").rainbow).to.equal(true)
			end
		)
		it("colours by tier and maps specials to their power tier", function()
			expect(Lib.Tier("HRP_001")).to.equal(1)
			expect(Lib.Tier("WPN_G05")).to.equal(5)
			expect(Lib.Tier("WPN_SP_RIFTBLASTER")).to.equal(5)
			expect(Lib.Style("WPN_C06").colour).to.equal(Color3.fromHex("#6DEBFF"))
			expect(Lib.Style("WPN_G07").halo ~= nil).to.equal(true)
		end)
	end)

	describe("WeaponFx authoring", function()
		it("fills the empty weapons and keeps every held weapon inside its budget", function()
			local weapons = RS.CodeAssets.Weapons
			for _, template in weapons:GetChildren() do
				local id = template.Name
				local app = template:FindFirstChild("Phase13Appearance")
				if app then
					local art = app:Clone()
					Lib.Author(art, id, nil)
					local emitters, rate = Lib.Budget(art)
					local budget = Lib.BudgetFor(id)
					if budget then
						expect(emitters <= budget.maxEmitters).to.equal(true)
						expect(rate <= budget.maxRate).to.equal(true)
					end
					if Config.Authored[id] then
						local added = 0
						for _, d in art:GetDescendants() do
							if string.sub(d.Name, 1, 4) == "PTF_" or d.Name == "AnimRotor_PTF" then
								added += 1
							end
						end
						expect(added >= 1).to.equal(true)
					end
					art:Destroy()
				end
			end
		end)
		it("is idempotent", function()
			local art = RS.CodeAssets.Weapons.WPN_B06.Phase13Appearance:Clone()
			expect(Lib.Author(art, "WPN_B06", nil) >= 1).to.equal(true)
			expect(Lib.Author(art, "WPN_B06", nil)).to.equal(0)
			art:Destroy()
		end)
	end)

	describe("WeaponFx pool", function()
		it("creates nothing per shot after warm-up", function()
			local origin, dir = Vector3.new(0, 500, 0), Vector3.new(0, 0, -1)
			Lib.Muzzle(origin, dir, "WPN_B08", "High")
			Lib.Bolt("WPN_B08", "High").release()
			Lib.Impact(origin, dir, "WPN_B08", "High", true)
			local before = #workspace.Terrain:GetDescendants()
			local stats = Lib.PoolStats()
			for i = 1, 25 do
				local id = if i % 2 == 0 then "HRP_001" else "WPN_G07"
				Lib.Muzzle(origin, dir, id, "High")
				local rig = Lib.Bolt(id, "Low")
				rig.move(origin, origin + dir * 5, dir)
				rig.release()
				Lib.Impact(origin + dir * 5, dir, id, "Low", i % 3 == 0)
			end
			expect(#workspace.Terrain:GetDescendants()).to.equal(before)
			expect(Lib.PoolStats().instances).to.equal(stats.instances)
		end)
	end)
end
