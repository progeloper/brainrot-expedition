--!nocheck
-- Actual native UI adornments. These are isolated fixtures, not player rewards.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Expression = require(RS.Shared.Utility.RetentionExpressionPresentation)
	local View = require(RS.Shared.Utility.RetentionPresentation)
	describe("Phase14 usable collection expression", function()
		it("renders a selected title, nameplate and actual in-game badge together", function()
			local head = Instance.new("Part")
			local identity = Expression.Identity(
				head,
				{ title = "Collector", nameplate = "Field Research", badge = "Anomaly Found" }
			)
			expect(identity.Adornee).to.equal(head)
			expect(identity.Identity.Text).to.equal("Collector · Field Research")
			expect(identity.CollectionBadge.Text).to.equal("◆ Anomaly Found")
			expect(identity.CollectionBadge.Visible).to.equal(true)
			expect(identity.CollectionBadge.TextSize >= 14).to.equal(true)
			expect(identity.CollectionBadge.RichText).to.equal(false)
			head:Destroy()
		end)
		it(
			"changes only the one selected title and permits badge None without losing other expression",
			function()
				local head = Instance.new("Part")
				local identity = Expression.Identity(
					head,
					{ vip = true, title = "Rift Patron", badge = "Anomaly Found" }
				)
				local same = Expression.Identity(head, {
					vip = true,
					title = "Expedition Expert",
					nameplate = "Field Research",
					badge = "",
				})
				expect(same).to.equal(identity)
				expect(same.Identity.Text).to.equal("VIP · Expedition Expert · Field Research")
				expect(same.CollectionBadge.Text).to.equal("")
				expect(same.CollectionBadge.Visible).to.equal(false)
				expect(#head:GetChildren()).to.equal(1)
				head:Destroy()
			end
		)
		it(
			"unequips the last adornment and safely upgrades an already-rendered earlier identity",
			function()
				local head = Instance.new("Part")
				local earlier = Instance.new("BillboardGui")
				earlier.Name, earlier.Parent = "Phase13VIPIdentity", head
				local label = Instance.new("TextLabel")
				label.Name, label.Parent = "Identity", earlier
				expect(Expression.Identity(head, { badge = "Anomaly Found" })).to.equal(earlier)
				expect(earlier.CollectionBadge.Visible).to.equal(true)
				expect(Expression.Identity(head, {})).to.equal(nil)
				expect(#head:GetChildren()).to.equal(0)
				head:Destroy()
			end
		)
		it(
			"renders a separate base plaque without adding a production part, slot or reward mutation",
			function()
				local gui = Instance.new("BillboardGui")
				local background = Instance.new("Frame")
				background.Parent = gui
				local plaque = Expression.Plaque(background, "Master Collector")
				expect(plaque:IsA("Frame")).to.equal(true)
				expect(plaque.Visible).to.equal(true)
				expect(plaque.Reward.Text).to.equal("Master Collector")
				expect(plaque:FindFirstChildOfClass("UIStroke") ~= nil).to.equal(true)
				for _, child in gui:GetDescendants() do
					expect(child:IsA("BasePart")).to.equal(false)
				end
				local count = #gui:GetDescendants()
				for _ = 1, 20 do
					expect(Expression.Plaque(background, "")).to.equal(plaque)
					expect(plaque.Visible).to.equal(false)
					expect(Expression.Plaque(background, "Master Collector")).to.equal(plaque)
				end
				expect(#gui:GetDescendants()).to.equal(count)
				gui:Destroy()
				expect(plaque.Parent).to.equal(nil)
			end
		)
		it("uses only the current shoot/pick-up/bank route in the long-absence fallback", function()
			local lines = View.ReturnLines({
				returnRows = {
					{ kind = "Refresher" },
					{ kind = "Supply", supplies = { nextLifetimeClaim = 2 } },
				},
			})
			expect(#lines).to.equal(2)
			expect(lines[1]).to.equal(
				"Shoot to sleep → pick up → bank → collect platform earnings."
			)
			expect(lines[1]:find("reel", 1, true)).to.equal(nil)
		end)
	end)
end
