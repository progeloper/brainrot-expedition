--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
	local PerformanceIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxPerformanceIds)
	local CartGreyboxConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartGreyboxConfigValidator)

	local function cloneConfig(): any
		local config = table.clone(CartGreybox) :: any
		local sections = {}

		for index, section in CartGreybox.Sections do
			sections[index] = table.clone(section)

			if section.SpawnOffsets ~= nil then
				sections[index].SpawnOffsets = table.clone(section.SpawnOffsets)
			end
		end

		config.Sections = sections

		return config
	end

	local function expectInvalid(config: any)
		expect(CartGreyboxConfigValidator.Validate(config).IsValid).to.equal(false)
	end

	local function findSection(config: any, sectionId: string): any
		for _, section in config.Sections do
			if section.Id == sectionId then
				return section
			end
		end

		error(string.format("missing section %s", sectionId))
	end

	describe("CartGreybox configuration", function()
		it("accepts the deterministic greybox route and adjacent performance zone", function()
			local result = CartGreyboxConfigValidator.Validate(CartGreybox)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
			expect(#CartGreybox.Sections).to.equal(21)
			expect(CartGreybox.CanonicalSpawnId).to.equal("CSP_001")
			expect(CartGreybox.RouteFolderName).to.equal("Phase1SGreybox")
		end)

		it("freezes route metadata and every section definition", function()
			expect(table.isfrozen(CartGreybox)).to.equal(true)
			expect(table.isfrozen(CartGreybox.Sections)).to.equal(true)

			for _, section in CartGreybox.Sections do
				expect(table.isfrozen(section)).to.equal(true)
			end
		end)

		it("defines only the approved nonoverlapping multi-lane sections", function()
			for _, section in CartGreybox.Sections do
				if section.Kind == "Multiplayer" then
					local spawnOffsets = section.SpawnOffsets :: { Vector3 }

					expect(#spawnOffsets).to.equal(3)
					expect(table.isfrozen(spawnOffsets)).to.equal(true)

					for laneIndex = 2, #spawnOffsets do
						expect(
							(spawnOffsets[laneIndex] - spawnOffsets[laneIndex - 1]).Magnitude > 24
						).to.equal(true)
					end
				elseif section.Id == PerformanceIds.TwelveCartLoadZone then
					local spawnOffsets = section.SpawnOffsets :: { Vector3 }

					expect(section.Kind).to.equal("Performance")
					expect(#spawnOffsets).to.equal(12)
					expect(table.isfrozen(spawnOffsets)).to.equal(true)

					for laneIndex = 2, #spawnOffsets do
						expect(
							(spawnOffsets[laneIndex] - spawnOffsets[laneIndex - 1]).Magnitude > 24
						).to.equal(true)
					end
				else
					expect(section.SpawnOffsets).to.equal(nil)
				end
			end
		end)

		it("rejects missing and unsupported top-level fields", function()
			expectInvalid(nil)
			expectInvalid({})

			local missing = cloneConfig()

			missing.RouteFolderName = nil
			expectInvalid(missing)

			local unknown = cloneConfig()

			unknown.ProductionEnabled = true
			expectInvalid(unknown)
		end)

		it("rejects non-finite and invalid route dimensions", function()
			for _, invalidOffset in
				{
					Vector3.new(0 / 0, 0, 0),
					Vector3.new(math.huge, 0, 0),
				}
			do
				local config = cloneConfig()

				config.RouteOffset = invalidOffset
				expectInvalid(config)
			end

			local invalidSpacing = cloneConfig()

			invalidSpacing.GridSpacing = Vector2.new(0, 90)
			expectInvalid(invalidSpacing)

			local invalidThickness = cloneConfig()

			invalidThickness.FloorThickness = -1
			expectInvalid(invalidThickness)
		end)

		it("requires each central section ID exactly once", function()
			local duplicate = cloneConfig()

			duplicate.Sections[2].Id = duplicate.Sections[1].Id
			expectInvalid(duplicate)

			local missing = cloneConfig()

			table.remove(missing.Sections, #missing.Sections)
			expectInvalid(missing)

			local unknown = cloneConfig()

			unknown.Sections[1].Id = "GBOX_UNAPPROVED"
			expectInvalid(unknown)
		end)

		it("rejects invalid section geometry and unsupported kinds", function()
			local invalidKind = cloneConfig()

			invalidKind.Sections[1].Kind = "LoopTheLoop"
			expectInvalid(invalidKind)

			local invalidGrid = cloneConfig()

			invalidGrid.Sections[1].GridColumn = 0.5
			expectInvalid(invalidGrid)

			local duplicateGridCell = cloneConfig()

			duplicateGridCell.Sections[2].GridColumn = duplicateGridCell.Sections[1].GridColumn
			duplicateGridCell.Sections[2].GridRow = duplicateGridCell.Sections[1].GridRow
			expectInvalid(duplicateGridCell)

			local invalidFootprint = cloneConfig()

			invalidFootprint.Sections[1].Footprint = Vector2.new(-1, 64)
			expectInvalid(invalidFootprint)

			local unknownField = cloneConfig()

			unknownField.Sections[1].ProductionMechanic = true
			expectInvalid(unknownField)
		end)

		it("rejects overlapping or non-multiplayer spawn lanes", function()
			local overlapping = cloneConfig()
			local multiplayer = findSection(overlapping, "GBOX_MULTIPLAYER")

			multiplayer.SpawnOffsets[2] = multiplayer.SpawnOffsets[1]
			expectInvalid(overlapping)

			local invalidPerformanceCount = cloneConfig()
			local performance =
				findSection(invalidPerformanceCount, PerformanceIds.TwelveCartLoadZone)

			table.remove(performance.SpawnOffsets)
			expectInvalid(invalidPerformanceCount)

			local invalidPerformanceKind = cloneConfig()

			findSection(invalidPerformanceKind, PerformanceIds.TwelveCartLoadZone).Kind = "Flat"
			expectInvalid(invalidPerformanceKind)

			local misplaced = cloneConfig()

			misplaced.Sections[1].SpawnOffsets = {
				Vector3.new(-30, 0, 22),
				Vector3.new(0, 0, 22),
				Vector3.new(30, 0, 22),
			}
			expectInvalid(misplaced)
		end)
	end)
end
