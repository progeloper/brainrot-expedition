--!nocheck
return function()
	local Brainrots = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Validator = require(game.ReplicatedStorage.Shared.Validation.BrainrotCatalogValidator)

	local function cloneDefinition(id)
		return table.clone(Brainrots.Get(id or "BRT_007"))
	end

	local function hasIssue(report, severity, code)
		for _, item in report[severity] do
			if item.code == code then
				return true
			end
		end
		return false
	end

	describe("Phase 6B catalogue validation", function()
		it("accepts all static roster values and approved region mappings", function()
			local report = Validator.ValidateDefinitions(Brainrots.GetAll())
			expect(#report.errors).to.equal(0)
			expect(#report.warnings).to.equal(0)
			expect(Validator.HasErrors(report)).to.equal(false)
		end)

		it("validates optional future effect definitions without altering the installed roster", function()
			local definitions=Brainrots.GetAll()
			local fixture=table.clone(definitions[1])
			fixture.chariotEffect={effect="Shield",contribution=.5,contributors=2,amplifierTarget="Shield"}
			definitions[1]=fixture
			local invalid=Validator.ValidateDefinitions(definitions)
			expect(hasIssue(invalid,"errors","SHIELD_CONTRIBUTION_INVALID")).to.equal(true)
			fixture.chariotEffect={effect="Shield",contribution=1,contributors=2,amplifierTarget="Shield"}
			local valid=Validator.ValidateDefinitions(definitions)
			expect(#valid.errors).to.equal(0)
			expect(Brainrots.Get("BRT_001").chariotEffect).to.equal(nil)
		end)

		it("detects duplicate IDs after underscore and hyphen normalization", function()
			local canonical = cloneDefinition()
			local workbook = cloneDefinition()
			workbook.id = "BRT-007"
			local report = Validator.ValidateDefinitions({ canonical, workbook })
			expect(hasIssue(report, "errors", "DUPLICATE_ID")).to.equal(true)
		end)

		it("reports each invalid schema value with its stable issue code", function()
			local cases = {
				{ "MISSING_DISPLAY_NAME", "displayName", "" },
				{ "INVALID_TIER", "tier", "Ultra" },
				{ "MISSING_MODEL_REF", "modelRef", "" },
				{ "INVALID_CASH_PER_SECOND", "cashPerSecond", 0 },
				{ "INVALID_CASH_PER_SECOND", "cashPerSecond", -1 },
				{ "INVALID_CASH_PER_SECOND", "cashPerSecond", 0 / 0 },
				{ "INVALID_CASH_PER_SECOND", "cashPerSecond", math.huge },
				{ "INVALID_SELL_VALUE", "sellValue", 0 },
				{ "INVALID_SELL_VALUE", "sellValue", -1 },
				{ "INVALID_SELL_VALUE", "sellValue", 1.5 },
				{ "INVALID_LAUNCH_STATUS", "launchStatus", "Soon" },
				{ "INVALID_BEHAVIOUR_ID", "behaviourId", "Runner" },
				{ "INVALID_EXPEDITION_ROLE", "expeditionRole", "Runner" },
				{ "INVALID_SPAWN_ENABLED", "spawnEnabled", "yes" },
				{ "INVALID_REGION_ASSIGNMENT_STATUS", "regionAssignmentStatus", "Maybe" },
				{ "INVALID_ALLOWED_REGION_IDS", "allowedRegionIds", "Forest" },
			}
			for _, case in cases do
				local definition = cloneDefinition()
				definition[case[2]] = case[3]
				local report = Validator.ValidateDefinitions({ definition })
				expect(hasIssue(report, "errors", case[1])).to.equal(true)
			end

			local pending = cloneDefinition()
			pending.behaviourId = "Pending"
			pending.spawnEnabled = true
			local pendingReport = Validator.ValidateDefinitions({ pending })
			expect(hasIssue(pendingReport, "errors", "ENABLED_WITH_PENDING_BEHAVIOUR")).to.equal(
				true
			)
		end)

		it("requires approved homes to be canonical, allowed and outside Camp", function()
			local missingHome = cloneDefinition()
			missingHome.regionAssignmentStatus = "Approved"
			missingHome.homeRegionId = nil
			missingHome.allowedRegionIds = { "REGION_FOREST" }
			local missingReport = Validator.ValidateDefinitions({ missingHome })
			expect(hasIssue(missingReport, "errors", "INCOMPLETE_APPROVED_REGION_ASSIGNMENT")).to.equal(
				true
			)

			local absent = cloneDefinition()
			absent.regionAssignmentStatus = "Approved"
			absent.homeRegionId = "REGION_FOREST"
			absent.allowedRegionIds = { "REGION_JUNGLE" }
			local absentReport = Validator.ValidateDefinitions({ absent })
			expect(hasIssue(absentReport, "errors", "HOME_NOT_ALLOWED")).to.equal(true)

			local camp = cloneDefinition()
			camp.regionAssignmentStatus = "Approved"
			camp.homeRegionId = "REGION_CAMP"
			camp.allowedRegionIds = { "REGION_CAMP" }
			local campReport = Validator.ValidateDefinitions({ camp })
			expect(hasIssue(campReport, "errors", "CAMP_NOT_SPAWNABLE")).to.equal(true)

			local legacy = cloneDefinition()
			legacy.regionAssignmentStatus = "Approved"
			legacy.homeRegionId = "Glitchwood"
			legacy.allowedRegionIds = { "Glitchwood" }
			local legacyReport = Validator.ValidateDefinitions({ legacy })
			expect(hasIssue(legacyReport, "errors", "UNKNOWN_REGION")).to.equal(true)
		end)

		it("accepts a usable Model containing a BasePart", function()
			local folder = Instance.new("Folder")
			local model = Instance.new("Model")
			model.Name = "BRT_007"
			model.Parent = folder
			local part = Instance.new("Part")
			part.Parent = model
			local report = Validator.ValidateAssets({ cloneDefinition() }, folder)
			expect(#report.errors).to.equal(0)
			expect(#report.warnings).to.equal(0)
			folder:Destroy()
		end)

		it("uses spawn enablement to classify a missing model", function()
			local folder = Instance.new("Folder")
			local enabled = cloneDefinition()
			enabled.modelRef = "MissingEnabled"
			enabled.spawnEnabled = true
			local enabledReport = Validator.ValidateAssets({ enabled }, folder)
			expect(hasIssue(enabledReport, "errors", "MISSING_MODEL")).to.equal(true)

			local disabled = cloneDefinition()
			disabled.modelRef = "MissingDisabled"
			disabled.spawnEnabled = false
			local disabledReport = Validator.ValidateAssets({ disabled }, folder)
			expect(hasIssue(disabledReport, "warnings", "MISSING_MODEL")).to.equal(true)
			folder:Destroy()
		end)

		it("reports wrong-class and empty-model references", function()
			local folder = Instance.new("Folder")
			local wrongClass = Instance.new("Folder")
			wrongClass.Name = "WrongClass"
			wrongClass.Parent = folder
			local emptyModel = Instance.new("Model")
			emptyModel.Name = "EmptyModel"
			emptyModel.Parent = folder

			local wrongDefinition = cloneDefinition()
			wrongDefinition.modelRef = wrongClass.Name
			wrongDefinition.spawnEnabled = false
			local wrongReport = Validator.ValidateAssets({ wrongDefinition }, folder)
			expect(hasIssue(wrongReport, "warnings", "MODEL_REF_NOT_MODEL")).to.equal(true)

			local emptyDefinition = cloneDefinition()
			emptyDefinition.modelRef = emptyModel.Name
			emptyDefinition.spawnEnabled = true
			local emptyReport = Validator.ValidateAssets({ emptyDefinition }, folder)
			expect(hasIssue(emptyReport, "errors", "MODEL_HAS_NO_BASEPART")).to.equal(true)
			folder:Destroy()
		end)

		it("formats a deterministic report without printing", function()
			local report = Validator.ValidateDefinitions(Brainrots.GetAll())
			local first = Validator.FormatReport(report)
			local second = Validator.FormatReport(report)
			expect(first).to.equal(second)
			expect(string.find(first, "0 error%(s%)", 1, false) ~= nil).to.equal(true)
			expect(string.find(first, "0 warning%(s%)", 1, false) ~= nil).to.equal(true)
			expect(string.find(first, "REGION_ASSIGNMENT_PENDING", 1, true)).to.equal(nil)
		end)
	end)
end
