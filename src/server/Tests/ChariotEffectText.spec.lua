--!strict

return function()
	local Text = require(game:GetService("ReplicatedStorage").Shared.Utility.ChariotEffectText)
	describe("Four-effect team explanations", function()
		it("shows the provider's one whole charge and approved protection description", function()
			expect(Text.Value("Shield", 1)).to.equal("1 charge")
			expect(Text.Description({ effect = "Shield", grant = 1 })).to.equal("Blocks a cargo hit and protects your cargo for 5 seconds. Refills at your base.")
		end)
		it("describes matching contributor grants separately from another primary effect", function()
			local row = { effect = "Speed", amplifierTarget = "Shield", grant = 3 }
			expect(Text.Trait(row)).to.equal("Top 3 Shield trait")
			local text = Text.Description(row)
			expect(string.find(text, "best 3 equipped Shield providers", 1, true) ~= nil).to.equal(true)
			expect(string.find(text, "supplies no Shield charge", 1, true) ~= nil).to.equal(true)
		end)
		it("explains unselected Shield providers without promising multiplied charges", function()
			local detail = { effect = "Shield", status = "below_limit" }
			expect(Text.Member(detail, { limits = { Shield = 1 } })).to.equal("A Shield amplifier is needed")
			expect(Text.Member(detail, { limits = { Shield = 2 } })).to.equal("Shield contribution limit reached")
		end)
		it("full totals include maximum Shield capacity while reserve text remains distinct", function()
			local stats = { hitMultiplier = 2.5, burstCapacity = 1.25, shieldCapacity = 3, limits = { Speed = 2, Hit = 1, Burst = 1, Shield = 3 } }
			local totals = Text.Totals(stats, { percent = { speed = 7.72 }, speed = 38.7792, clipped = { speed = false } })
			expect(string.find(totals, "Speed +7.72%", 1, true) ~= nil).to.equal(true)
			expect(string.find(totals, "Hit Multiplier ×2.5", 1, true) ~= nil).to.equal(true)
			expect(string.find(totals, "Shield capacity 3 charges", 1, true) ~= nil).to.equal(true)
			local reserve = Text.Reserve({ capacity = 3, remaining = 0, protectedUntil = 15 }, 10)
			expect(string.find(reserve, "Current Shield reserve 0/3", 1, true) ~= nil).to.equal(true)
			expect(string.find(reserve, "previews do not promise a refill", 1, true) ~= nil).to.equal(true)
		end)
	end)
end
