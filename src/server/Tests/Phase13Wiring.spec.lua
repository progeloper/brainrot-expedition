return function()
	local RS = game:GetService("ReplicatedStorage")
	describe("Phase13 active dependency wiring", function()
		it("loads the authoritative entry services without a second store or dispatcher", function()
			for _, name in
				{
					"Phase13RuntimeService",
					"Phase13Service",
					"Phase13CommerceService",
					"Phase13AnalyticsService",
					"Phase13InterestService",
					"Phase13MetricsService",
					"Phase13ClientTelemetryService",
				}
			do
				local service = require(script.Parent.Parent.Services[name])
				expect(type(service.Start)).to.equal("function")
			end
		end)
		it("resolves every cart preview and weapon profile from stable server catalogue IDs", function()
			local config = require(RS.Shared.Config.Phase13)
			local carts = require(RS.Shared.Config.Carts)
			local stats = require(RS.Shared.Utility.WeaponStats)
			local weapons = require(RS.Shared.Config.Weapons)
			for _, row in config.CartRows do
				expect(carts[row.id].AssetName).to.equal(row.assetName)
			end
			for _, row in weapons.GetAll() do
				expect(stats.Resolve(row.id).status).to.equal("Ready")
			end
		end)
	end)
end
