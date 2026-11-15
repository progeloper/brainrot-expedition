--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartGreyboxSectionIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxSectionIds)
	local CartGreyboxPerformanceIds =
		require(ReplicatedStorage.Shared.Constants.CartGreyboxPerformanceIds)

	describe("Phase 1S greybox section identifiers", function()
		it("centralises twenty stable and unique route section IDs", function()
			local seen: { [string]: boolean } = {}
			local count = 0

			for _, sectionId in CartGreyboxSectionIds do
				expect(string.sub(sectionId, 1, 5)).to.equal("GBOX_")
				expect(seen[sectionId]).to.equal(nil)

				seen[sectionId] = true
				count += 1
			end

			expect(count).to.equal(20)
			expect(seen.GBOX_FLAT_ACCEL).to.equal(true)
			expect(seen.GBOX_CAMERA_CORNER).to.equal(true)
			expect(seen.GBOX_MULTIPLAYER).to.equal(true)
		end)

		it("freezes the catalogue against runtime mutation", function()
			expect(table.isfrozen(CartGreyboxSectionIds)).to.equal(true)
		end)

		it("keeps the Phase 1T load-zone identifier stable and separate", function()
			expect(CartGreyboxPerformanceIds.TwelveCartLoadZone).to.equal("GBOX_PERF_12_CART")
			expect(table.isfrozen(CartGreyboxPerformanceIds)).to.equal(true)
		end)
	end)
end
