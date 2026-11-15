--!nocheck
-- Native disposable rendering instances. This does not verify image residency,
-- aesthetics, a running player's camera, or device input.
return function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local Renderer = require(StarterPlayer.StarterPlayerScripts.Client.Utility.SpaceRiftRenderer)
	local asset = require(game.ReplicatedStorage.Shared.Config.SpaceRift)
	describe("Phase 13 shared approved rift variant", function()
		it("tints the existing pooled primary for VIP and restores the default on reuse", function()
			local owner = Instance.new("Folder")
			owner.Name = "SPEC_RIFT_VARIANT"
			owner.Parent = workspace
			local anchor = Instance.new("Part")
			anchor.Anchored = true
			anchor.Parent = owner
			local api = Renderer.Create(owner, asset, anchor)
			local ok, reason = xpcall(function()
				local gold = Color3.fromRGB(255, 200, 70)
				local vip = assert(
					api.Start(
						{
							eventId = "SPEC_VIP",
							mode = "Spawn",
							startTime = 0,
							deadline = 7,
							position = Vector3.new(0, 20, 0),
							height = 17,
							requestedRifts = 1,
							tint = gold,
						},
						0,
						"High",
						false
					)
				)
				api.Step(1, Vector3.zero, "High", false)
				local image = owner:FindFirstChildWhichIsA("ImageLabel", true)
				expect(image.ImageColor3).to.equal(gold)
				expect(image.Image).to.equal(asset.PrimaryImage)
				expect(api.GetDiagnostics().poolSlots).to.equal(1)
				api.Stop(vip)
				assert(
					api.Start(
						{
							eventId = "SPEC_DEFAULT",
							mode = "Spawn",
							startTime = 8,
							deadline = 15,
							position = Vector3.new(0, 20, 0),
							height = 17,
							requestedRifts = 1,
						},
						8,
						"High",
						false
					)
				)
				api.Step(9, Vector3.zero, "High", false)
				expect(image.ImageColor3).to.equal(Color3.new(1, 1, 1))
				expect(api.GetDiagnostics().poolSlots).to.equal(1)
				expect(owner:FindFirstChildWhichIsA("Light", true)).to.equal(nil)
			end, debug.traceback)
			api.Destroy()
			owner:Destroy()
			assert(ok, reason)
		end)
	end)
end
