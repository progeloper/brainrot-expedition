--!nocheck
return function()
	local R = require(game.ReplicatedStorage.Shared.Utility.Phase12Rules)
	local C = require(game.ReplicatedStorage.Shared.Config.Phase12)
	local M = require(game.ReplicatedStorage.Shared.Config.MutationCatalog)
	local E = require(script.Parent.Parent.Utility.Phase12EscapeRuntime)
	describe("Phase 12 exact probabilities and HP", function()
		it("uses the approved HP ladder with Celestial below Secret", function()
			local order = require(game.ReplicatedStorage.Shared.Config.Rarities).DisplayOrder
			expect(table.concat(order, ",")).to.equal("Common,Uncommon,Rare,Epic,Legendary,Mythic,Celestial,Secret")
			local expected = { 1, 1, 2, 3, 4, 6, 8, 10 }
			for i, id in order do
				expect(C.HpByRarity[id]).to.equal(expected[i])
			end
		end)
		it("derives conditional baseline and weather absolute probabilities once", function()
			for _, chance in { 0.04, 0.06 } do
				local dist = R.MutationDistribution(chance)
				local total, mutated = 0, 0
				for _, entry in dist do
					total += entry.weight
					if entry.id ~= "None" then
						mutated += entry.weight
					end
				end
				assert(
					math.abs(total - 1) < 1e-12 and math.abs(mutated - chance) < 1e-12,
					"Probability totals must conserve mass"
				)
				expect(dist[1].weight).to.equal(1 - chance)
				for i = 2, #dist do
					expect(dist[i].weight).to.equal(chance * M.Order[i].share)
				end
			end
		end)
		it("resolves every exact cumulative boundary to the next positive interval", function()
			local entries = {
				{ id = "first", weight = 2 },
				{ id = "zero", weight = 0 },
				{ id = "second", weight = 3 },
				{
					id = "trailing",
					weight = 0,
				},
			}
			for _, row in
				{
					{ 0, "first" },
					{ 0.4 - 1e-9, "first" },
					{ 0.4, "second" },
					{ 0.4 + 1e-9, "second" },
					{ 1, "second" },
				}
			do
				expect(R.SelectWeighted(entries, function()
					return row[1]
				end).id).to.equal(row[2])
			end
			expect(R.SelectWeighted({ { id = "zero", weight = 0 } }, function()
				error("must not roll")
			end).status).to.equal("Unavailable")
		end)
		it("rejects duplicate unknown negative and nonfinite inputs", function()
			for _, entries in
				{
					{ { id = "a", weight = -1 } },
					{ { id = "a", weight = math.huge } },
					{ { id = "a", weight = 0 / 0 } },
					{ { id = "a", weight = 1 }, { id = "a", weight = 0 } },
				}
			do
				expect(function()
					R.SelectWeighted(entries, function()
						return 0
					end)
				end).to.throw()
			end
			for _, chance in { -1, 1.1, math.huge, 0 / 0 } do
				expect(function()
					R.MutationDistribution(chance)
				end).to.throw()
			end
			expect(function()
				R.MutationDistribution(0.04, { { id = "Unknown", share = 1 } })
			end).to.throw()
			expect(function()
				R.MutationDistribution(0.04, { { id = "Golden", share = 0.99 } })
			end).to.throw()
			expect(function()
				R.MutationDistribution(0.04, { { id = "Golden", share = 1 }, { id = "Golden", share = 0 } })
			end).to.throw()
		end)
		it("zero total chance is Normal without drawing", function()
			expect(R.RollMutation(function()
				error("not needed")
			end, 0)).to.equal("None")
		end)
		it("preserves fractional HP and the explicit threshold examples", function()
			for _, row in { { 2, 1, 2 }, { 3, 1.5, 2 }, { 4, 2.5, 2 }, { 10, 5, 2 } } do
				local remaining, hits = row[1], 0
				repeat
					remaining = R.Damage(remaining, row[1], row[2])
					hits += 1
				until remaining == 0
				expect(hits).to.equal(row[3])
			end
			expect(R.Damage(4, 4, 2.5)).to.equal(1.5)
		end)
		it("migration keeps Normal sentinel and distinct Celestial rarity", function()
			expect(R.NormalizeMutation(nil)).to.equal("None")
			expect(R.NormalizeMutation("Normal")).to.equal("None")
			expect(R.NormalizeMutation("Celestial")).to.equal("Astral")
			expect(require(game.ReplicatedStorage.Shared.Config.Rarities).Normalize("Celestial")).to.equal("Celestial")
		end)
		it("samples 100000 pure draws within six-sigma binomial bounds", function()
			local random = Random.new(12102026)
			local counts = {}
			local expected = R.MutationDistribution(0.04)
			for i = 1, 100000 do
				local id = R.RollMutation(random)
				counts[id] = (counts[id] or 0) + 1
				if i % 10000 == 0 then
					task.wait()
				end
			end
			for _, row in expected do
				local mean = row.weight * 100000
				local deviation = math.sqrt(100000 * row.weight * (1 - row.weight))
				assert(
					math.abs((counts[row.id] or 0) - mean) <= 6 * deviation + 2,
					row.id .. " distribution out of statistical bounds"
				)
			end
		end)
	end)
	describe("Phase 12 finite unavoidable transport attempts", function()
		local function fresh()
			return {
				MaxHp = 4,
				RemainingHp = 0,
				CapturedOnce = true,
				EscapeAttemptsUsed = 0,
				EscapeMaxAttempts = 2,
				EscapeGeneration = 0,
			}
		end
		local config = C.EscapeByRarity.Legendary
		it("first pickup arms a fractional server interval", function()
			local state = E.Pickup(fresh(), config, 100, function()
				return 0.625
			end)
			expect(state.EscapeDeadline).to.equal(103.25)
			expect(state.EscapeRolledDelay).to.equal(3.25)
			expect(state.EscapeGeneration).to.equal(1)
		end)
		it("carry cargo and slot transfers preserve one attempt", function()
			local state = E.Pickup(fresh(), config, 100, function()
				return 0.625
			end)
			local transfer = E.Pickup(state, config, 101, function()
				error("transfer cannot reroll")
			end)
			expect(transfer.EscapeDeadline).to.equal(103.25)
			expect(transfer.EscapeGeneration).to.equal(1)
		end)
		it("manual forced release pauses and resumes the same remaining time", function()
			local state = E.Pause(
				E.Pickup(fresh(), config, 100, function()
					return 0.625
				end),
				101
			)
			expect(state.EscapeRemainingSeconds).to.equal(2.25)
			expect(state.EscapeAttemptsUsed).to.equal(0)
			local resumed = E.Pickup(state, config, 120, function()
				error("drop cannot reroll")
			end)
			expect(resumed.EscapeDeadline).to.equal(122.25)
			expect(resumed.EscapeGeneration).to.equal(1)
		end)
		it("overdue drop pickup cannot buy another interval", function()
			local state = E.Pause(
				E.Pickup(fresh(), config, 100, function()
					return 0.625
				end),
				104
			)
			expect(E.Pickup(state, config, 120, function()
				error("not allowed")
			end).EscapeDeadline).to.equal(120)
		end)
		it("only a committed selfjump consumes allowance and restores full MaxHp", function()
			local state = E.Pickup(fresh(), config, 100, function()
				return 0.625
			end)
			expect(E.CommitJump(state, 102, 1)).to.equal(nil)
			local jumped = E.CommitJump(state, 104, 1)
			expect(jumped.EscapeAttemptsUsed).to.equal(1)
			expect(jumped.RemainingHp).to.equal(4)
			expect(E.CommitJump(jumped, 105, 1)).to.equal(nil)
			local nextAttempt = E.Pickup(jumped, config, 110, function()
				return 0.25
			end)
			expect(nextAttempt.EscapeDeadline).to.equal(112.5)
		end)
		it("exhausted allowance and Common never arm timers", function()
			local state = fresh()
			state.EscapeAttemptsUsed = 2
			expect(E.Pickup(state, config, 100, function()
				error("no jump remaining")
			end).EscapeDeadline).to.equal(nil)
			expect(E.Pickup(fresh(), C.EscapeByRarity.Common, 100, function()
				error("Common stable")
			end).EscapeDeadline).to.equal(nil)
		end)
		it("each independent deadline remains unextended", function()
			local a = E.Pickup(fresh(), config, 100, function()
				return 0
			end)
			local b = E.Pickup(fresh(), config, 100, function()
				return 1
			end)
			expect(a.EscapeDeadline).to.equal(102)
			expect(b.EscapeDeadline).to.equal(104)
		end)
	end)
end
