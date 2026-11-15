--!nocheck
-- First-session visual checkpoint: odds text, income, facade clipping, declutter,
-- and the idempotent world-art build. No profile, reward or economy writes.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.FirstSessionVisualRules)
	local Config = require(RS.Shared.Config.FirstSessionVisuals)
	local Phase12 = require(RS.Shared.Config.Phase12)
	local MutationCatalog = require(RS.Shared.Config.MutationCatalog)
	local WorldArt = require(game.ServerScriptService.Server.Utility.FirstSessionWorldArt)
	local function near(a, b, t)
		assert(math.abs(a - b) < (t or 1e-6), tostring(a) .. " differs from " .. tostring(b))
	end

	it("formats configured mutation odds without changing them", function()
		assert(
			Phase12.MutationChance == 0.04,
			"Audit odds assume the configured 4% mutation chance"
		)
		local expected = {
			Shiny = "1 in 56",
			Golden = "1 in 100",
			Glitched = "1 in 167",
			Radioactive = "1 in 286",
			Astral = "1 in 400",
		}
		for id, text in pairs(expected) do
			assert(
				Rules.FormatOdds(Rules.MutationProbability(id)) == text,
				id .. " -> " .. tostring(Rules.FormatOdds(Rules.MutationProbability(id)))
			)
			near(
				Rules.MutationProbability(id),
				Phase12.MutationChance * MutationCatalog.ById[id].share
			)
		end
		assert(Rules.MutationProbability("None") == nil, "Normal catches show no mutation odds")
	end)

	it("formats tier odds from region weights and rejects invalid input", function()
		assert(
			Rules.FormatOdds(
				Rules.TierProbability({ Common = 60, Uncommon = 26, Rare = 6 }, "Uncommon")
			) == "1 in 3.5",
			"Sub-10 odds keep one decimal"
		)
		assert(
			Rules.FormatOdds(Rules.TierProbability({ Common = 1, Rare = 1 }, "Rare")) == "1 in 2",
			"Whole sub-10 odds drop the decimal"
		)
		assert(Rules.TierProbability({ Common = 1 }, "Epic") == nil, "Unweighted tier has no odds")
		assert(
			Rules.FormatOdds(0) == nil
				and Rules.FormatOdds(nil) == nil
				and Rules.FormatOdds(2) == nil,
			"Invalid probabilities have no odds text"
		)
	end)

	it("computes the same effective income as the name tag", function()
		near(
			Rules.EffectiveIncome(4, "Radioactive"),
			4 * MutationCatalog.ById.Radioactive.multiplier
		)
		near(Rules.EffectiveIncome(4, "None"), 4)
		near(Rules.EffectiveIncome(4, nil), 4)
		assert(Rules.EffectiveIncome(nil, "None") == nil, "Missing catalogue rate shows no income")
	end)

	it("clips only the top of upright facade boxes", function()
		local frame, size = Rules.ClipBoxTop(
			CFrame.new(10, 60, 5) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(8, 124, 40),
			30
		)
		near(size.Y, 32) -- bottom at -2 stays, top becomes 30
		near(frame.Position.Y, 14)
		near(frame.Position.X, 10)
		near(math.abs(frame.LookVector:Dot(Vector3.xAxis)), 1, 1e-4) -- yaw preserved
		local same, sameSize = Rules.ClipBoxTop(CFrame.new(0, 5, 0), Vector3.new(4, 10, 4), 30)
		assert(
			same == CFrame.new(0, 5, 0) and sameSize == Vector3.new(4, 10, 4),
			"Short pieces are untouched"
		)
		assert(
			Rules.ClipBoxTop(CFrame.new(0, 60, 0), Vector3.new(4, 20, 4), 30) == nil,
			"Pieces wholly above the cap drop"
		)
	end)

	it("declutters overlapping plates in priority order", function()
		local a = { MinX = 0, MaxX = 100, MinY = 0, MaxY = 40 }
		local b = { MinX = 50, MaxX = 150, MinY = 10, MaxY = 50 }
		local c = { MinX = 300, MaxX = 400, MinY = 0, MaxY = 40 }
		local keep = Rules.Declutter({ a, b, c }, Config.Nametag.OverlapFraction)
		assert(
			keep[1] and not keep[2] and keep[3],
			"Second plate overlaps the first and is withheld"
		)
		near(Rules.OverlapFraction(a, c), 0)
	end)

	it("places a screen-edge arrow inside the margin", function()
		local point = Rules.EdgePoint(Vector2.new(2000, 195), Vector2.new(844, 390), 56)
		near(point.X, 844 - 56, 1e-3)
		assert(point.Y > 0 and point.Y < 390, "Arrow stays on screen vertically")
	end)

	it("builds skyline markers and prop clusters once, without collision on markers", function()
		local map = Instance.new("Folder")
		map.Name = "MapBlockout"
		map.Parent = script.Parent
		local art = Instance.new("Folder")
		art.Name = "EnvironmentArt_V2"
		art.Parent = map
		for _, name in pairs(Config.ClusterPrototypes) do
			local model = Instance.new("Model")
			model.Name = name
			model:SetAttribute("PrototypeId", "Shrub")
			local p = Instance.new("Part")
			p.Size = Vector3.new(4, 4, 4)
			p.CFrame = CFrame.new(0, 2, 0)
			p.Anchored = true
			p.Parent = model
			model.Parent = art
		end
		local ok, why = xpcall(function()
			local first = WorldArt.Apply(map)
			assert(
				not first.skipped and first.markers == #Config.Skyline.Markers,
				"One marker per region"
			)
			assert(first.props > 0, "Clusters placed")
			local markers = map.FirstSessionArt.SkylineMarkers
			for _, model in ipairs(markers:GetChildren()) do
				assert(
					model.ModelStreamingMode == Enum.ModelStreamingMode.Persistent,
					"Markers render from afar"
				)
				local top = -math.huge
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						assert(
							not d.CanCollide and not d.CanQuery,
							"Markers never block or catch rays"
						)
						assert(
							d:GetAttribute("PresentationClass") == "CriticalBoundary",
							"Markers stay visible from other regions"
						)
						top = math.max(top, d.Position.Y + d.Size.Y / 2)
					end
				end
				assert(
					top >= Config.Skyline.TopHeight - 6,
					model.Name .. " clears the skyline height"
				)
			end
			local clone = map.FirstSessionArt.PropClusters:GetChildren()[1]:GetChildren()[1]
			assert(
				clone:GetAttribute("PrototypeId") == nil,
				"Cluster clones are not authoring prototypes"
			)
			near(
				select(1, clone:GetBoundingBox()).Position.Y
					- select(2, clone:GetBoundingBox()).Y / 2,
				0,
				1e-3
			)
			local again = WorldArt.Apply(map)
			assert(again.skipped, "Second apply is a no-op")
		end, debug.traceback)
		map:Destroy()
		assert(ok, why)
	end)
end
