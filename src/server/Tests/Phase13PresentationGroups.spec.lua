--!nocheck
-- Pure bounded descriptor scheduling. Connected rendering and frame cost require Play/device QA.
return function()
	local Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13PresentationRules)
	describe("Phase 13 sequential cinematic copy windows", function()
		for tier, cap in { High = 12, Medium = 6, Low = 3 } do
			it("visits all 48 descriptors once with the " .. tier .. " concurrent budget", function()
				local seen = {}
				local groups = 48 / cap
				for group = 0, groups - 1 do
					local window = Rules.CopyWindow(1 + (group + 0.5) * 3.5 / groups, 48, tier, false)
					expect(window.group).to.equal(group)
					expect(window.count).to.equal(cap)
					expect(window.cap).to.equal(cap)
					for id = window.first, window.last do
						expect(seen[id]).to.equal(nil)
						seen[id] = true
					end
				end
				for id = 1, 48 do
					expect(seen[id]).to.equal(true)
				end
				expect(seen[49]).to.equal(nil)
			end)
		end
		it("has a short final group without creating phantom descriptors", function()
			local first = Rules.CopyWindow(1, 13, "High", false)
			local last = Rules.CopyWindow(4.5, 13, "High", false)
			expect(first.first).to.equal(1)
			expect(first.last).to.equal(12)
			expect(last.first).to.equal(13)
			expect(last.last).to.equal(13)
			expect(last.count).to.equal(1)
			expect(Rules.CopyWindow(7, 100, "High", false).last).to.equal(48)
			expect(Rules.CopyWindow(2, 0, "Low", false).count).to.equal(0)
		end)
		it(
			"switches on intake boundaries and finishes before contraction without changing the seven-second timeline",
			function()
				expect(Rules.CopyWindow(1.874999, 48, "High", false).group).to.equal(0)
				expect(Rules.CopyWindow(1.875, 48, "High", false).group).to.equal(1)
				expect(Rules.CopyWindow(1, 48, "High", false).progress).to.equal(0)
				expect(Rules.CopyWindow(4.5, 48, "High", false).progress).to.equal(1)
				expect(Rules.CopyWindow(6.9, 48, "High", false).last).to.equal(48)
				expect(Rules.Rebirth(6.999).done).to.equal(false)
				expect(Rules.Rebirth(7).done).to.equal(true)
			end
		)
		it("staggers each bounded group while every copy completes before replacement", function()
			expect(Rules.CopyProgress(0.1, 1, 12) > Rules.CopyProgress(0.1, 12, 12)).to.equal(true)
			for ordinal = 1, 12 do
				expect(Rules.CopyProgress(0, ordinal, 12)).to.equal(0)
				expect(Rules.CopyProgress(1, ordinal, 12)).to.equal(1)
			end
		end)
		it("keeps cash icons in one constant bounded group for all qualities", function()
			for tier, cap in { High = 12, Medium = 6, Low = 3 } do
				for _, age in { 0, 1, 2, 3, 4.5, 6.9 } do
					local window = Rules.CopyWindow(age, 48, tier, true)
					expect(window.groups).to.equal(1)
					expect(window.group).to.equal(0)
					expect(window.count).to.equal(cap)
					expect(window.first).to.equal(1)
				end
			end
		end)
	end)
end
