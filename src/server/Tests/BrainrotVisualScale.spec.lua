--!nocheck

return function()
	local VisualScale =
		require(game:GetService("ReplicatedStorage").Shared.Utility.BrainrotVisualScale)

	describe("canonical brainrot visual scale", function()
		it("uses exactly 64 percent of the verified player reference height", function()
			expect(VisualScale.BRAINROT_PLAYER_HEIGHT_RATIO).to.equal(0.64)
			expect(VisualScale.TARGET_HEIGHT_STUDS).to.equal(
				VisualScale.PLAYER_REFERENCE_HEIGHT_STUDS * 0.64
			)
		end)

		it("uses visible bounds, ignores helper geometry and remains idempotent", function()
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Name = "Body"
			body.Size = Vector3.new(2, 2, 1)
			body.CFrame = CFrame.new(0, 1, 0)
			body.Parent = model
			model.PrimaryPart = body

			local hitbox = Instance.new("Part")
			hitbox.Name = "HuntHitbox"
			hitbox.Size = Vector3.new(60, 60, 60)
			hitbox.Transparency = 0.5
			hitbox.Parent = model

			local helper = Instance.new("Part")
			helper.Name = "CarryHelper"
			helper.Size = Vector3.new(1, 100, 1)
			helper.Parent = model

			local ok, height = VisualScale.ApplyCanonicalScale(model, "SpecFirst")
			expect(ok).to.equal(true)
			expect(
				math.abs(height - VisualScale.TARGET_HEIGHT_STUDS) <= VisualScale.TOLERANCE_STUDS
			).to.equal(true)
			local scale = model:GetScale()
			local second, secondHeight = VisualScale.ApplyCanonicalScale(model, "SpecSecond")
			expect(second).to.equal(true)
			expect(math.abs(model:GetScale() - scale) < 0.0001).to.equal(true)
			expect(math.abs(secondHeight - height) < 0.0001).to.equal(true)
			model:Destroy()
		end)

		it("returns a concise failure for models without visible parts", function()
			local model = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "InvisibleRoot"
			root.Transparency = 1
			root.Parent = model
			expect(VisualScale.ApplyCanonicalScale(model)).to.equal(false)
			expect(select(3, VisualScale.ApplyCanonicalScale(model))).to.equal("NO_VISIBLE_PARTS")
			model:Destroy()
		end)
	end)
end
