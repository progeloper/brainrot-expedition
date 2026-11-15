--!nocheck
-- Playtest Fixes Part A: map stud eligibility, apply and exact revert; plus the master flag gate.

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Policy = require(RS.Shared.Utility.MapStudPolicy)
	local Config = require(RS.Shared.Config.PlaytestFixes)
	local Flags = require(RS.Shared.Config.PlaytestFixesFlags)
	local FeatureFlags = require(RS.Shared.Config.FeatureFlags)

	local function part(props)
		local p = Instance.new("Part")
		p.Size = props.Size or Vector3.new(4, 4, 4)
		p.Material = props.Material or Enum.Material.SmoothPlastic
		p.Transparency = props.Transparency or 0
		p.Color = Color3.fromRGB(46, 160, 67)
		return p
	end
	local function stud(p, face)
		local t = Instance.new("Texture")
		t.Name = "Studs_" .. face
		t.Texture = Config.MapStuds.LegacyTextureAsset
		t.Face = Enum.NormalId[face]
		t.StudsPerTileU, t.StudsPerTileV, t.Transparency = 0.5, 0.5, 0.8
		t.Parent = p
		return t
	end

	describe("MapStudPolicy eligibility", function()
		it("studs plain props and skips Neon, glass, see-through, text and trim", function()
			expect(Policy.SkipReason(part({}))).to.equal(nil)
			expect(Policy.SkipReason(part({ Material = Enum.Material.Neon }))).to.equal(
				"Material:Neon"
			)
			expect(Policy.SkipReason(part({ Material = Enum.Material.Glass }))).to.equal(
				"Material:Glass"
			)
			expect(Policy.SkipReason(part({ Transparency = 0.5 }))).to.equal("Transparent")
			local sign = part({})
			Instance.new("SurfaceGui").Parent = sign
			expect(Policy.SkipReason(sign)).to.equal("TextOrDecal")
			expect(Policy.SkipReason(part({ Size = Vector3.new(0.4, 0.5, 6) }))).to.equal("Trim")
			expect(Policy.SkipReason(part({ Size = Vector3.new(0.4, 2, 6) }))).to.equal(nil)
		end)
		it("keeps the glow kits untouched", function()
			local model = Instance.new("Model")
			model:SetAttribute("Kit", "Lane_GlowTiles")
			local p = part({})
			p.Parent = model
			expect(Policy.SkipReason(p)).to.equal("GlowKit")
		end)
	end)

	describe("MapStudPolicy apply/revert", function()
		it("applies the variant, keeps colour and physics, removes overlay textures", function()
			local p = part({})
			stud(p, "Top")
			stud(p, "Front")
			local colour = p.Color
			local before = p.CurrentPhysicalProperties
			local changed, removed = Policy.Apply(p)
			expect(changed).to.equal(true)
			expect(removed).to.equal(2)
			expect(p.Material).to.equal(Enum.Material.Glacier)
			expect(p.MaterialVariant).to.equal(Config.MapStuds.Variant)
			expect(p.Color).to.equal(colour)
			expect(#p:GetChildren()).to.equal(0)
			local after = p.CurrentPhysicalProperties
			expect(math.abs(after.Friction - before.Friction) < 1e-4).to.equal(true)
			expect(math.abs(after.Density - before.Density) < 1e-4).to.equal(true)
			expect(math.abs(after.Elasticity - before.Elasticity) < 1e-4).to.equal(true)
			-- idempotent
			expect((Policy.Apply(p))).to.equal(false)
		end)
		it("reverts exactly", function()
			local p = part({})
			stud(p, "Top")
			Policy.Apply(p)
			expect(Policy.Revert(p)).to.equal(true)
			expect(p.Material).to.equal(Enum.Material.SmoothPlastic)
			expect(p.MaterialVariant).to.equal("")
			expect(p.CustomPhysicalProperties).to.equal(nil)
			local t = p:FindFirstChild("Studs_Top")
			expect(t ~= nil).to.equal(true)
			expect(math.abs(t.Transparency - 0.8) < 1e-6).to.equal(true)
			expect(t.StudsPerTileU).to.equal(0.5)
			expect(p:GetAttribute("StudMigrationOriginalMaterial")).to.equal(nil)
		end)
	end)

	describe("PlaytestFixes flags", function()
		it("resolves the live flag and stays off in Studio without the opt-in preview", function()
			expect(type(FeatureFlags.PlaytestFixesV1Enabled)).to.equal("boolean") -- true since the 14 Nov release
			expect(Flags.Resolve(false, false, true)).to.equal(false)
			expect(Flags.Resolve(false, true, nil)).to.equal(false)
			expect(Flags.Resolve(false, true, true)).to.equal(true)
			expect(Flags.Resolve(true, false, nil)).to.equal(true)
		end)
	end)
end
