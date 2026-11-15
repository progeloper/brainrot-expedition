--!strict

return function()
	local CurrencyFormatter =
		require(game:GetService("ReplicatedStorage").Shared.Utility.CurrencyFormatter)

	describe("CurrencyFormatter", function()
		it("formats only whole non-negative cash with separators", function()
			expect(CurrencyFormatter.FormatWholeCash(0)).to.equal("$0")
			expect(CurrencyFormatter.FormatWholeCash(37.99)).to.equal("$37")
			expect(CurrencyFormatter.FormatWholeCash(1284)).to.equal("$1,284")
			expect(CurrencyFormatter.FormatWholeCash(123456789)).to.equal("$123,456,789")
		end)

		it("clamps malformed display values to zero", function()
			expect(CurrencyFormatter.FormatWholeCash(-1)).to.equal("$0")
			expect(CurrencyFormatter.FormatWholeCash(0 / 0)).to.equal("$0")
			expect(CurrencyFormatter.FormatWholeCash(math.huge)).to.equal("$0")
			expect(CurrencyFormatter.FormatWholeCash("100")).to.equal("$0")
		end)

		it("formats compact cash with at most one useful decimal", function()
			expect(CurrencyFormatter.FormatCompactCash(1)).to.equal("$1")
			expect(CurrencyFormatter.FormatCompactCash(950)).to.equal("$950")
			expect(CurrencyFormatter.FormatCompactCash(1200)).to.equal("$1.2K")
			expect(CurrencyFormatter.FormatCompactCash(25000)).to.equal("$25K")
			expect(CurrencyFormatter.FormatCompactCash(2500000)).to.equal("$2.5M")
		end)

		it("preserves useful wallet fractions for exact offer and shortfall text", function()
			expect(CurrencyFormatter.FormatExactCash(0.25)).to.equal("$0.25")
			expect(CurrencyFormatter.FormatExactCash(0.005)).to.equal("$0.005")
			expect(CurrencyFormatter.FormatExactCash(499.75)).to.equal("$499.75")
			expect(CurrencyFormatter.FormatExactCash(1234567)).to.equal("$1,234,567")
		end)
	end)
	it("does not round a below-price wallet into the exact gate price", function()
		local amount = 25000000 - 0.0000001
		local label = CurrencyFormatter.FormatExactCash(amount)
		expect(label == "$25,000,000").to.equal(false)
		local numeric = label:gsub("[$,]", "")
		expect(tonumber(numeric)).to.equal(amount)
		expect(CurrencyFormatter.FormatExactCash(10000000000.125)).to.equal("$10,000,000,000.125")
		expect(CurrencyFormatter.FormatExactCash(0.00000001)).to.equal("$0.00000001")
	end)

end
