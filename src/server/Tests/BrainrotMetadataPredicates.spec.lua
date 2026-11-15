--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local StarterPlayer = game:GetService("StarterPlayer")
	local Config = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
	local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Behaviour = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours)
	local Camouflage = require(ReplicatedStorage.Shared.Behaviours.CamouflageTiming)
	local Decoy = require(ReplicatedStorage.Shared.Behaviours.DecoySplitTiming)
	local Nametags = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.BrainrotNametagController)

	-- The previous predicates, expressed through the unchanged public sampling
	-- API, are an equivalence oracle across real catalog/lifecycle/timing inputs.
	local function reference(model: Model, at: number): (boolean, boolean, string)
		local camouflage, isCamouflage = Nametags.getCamouflageSample(model, at)
		local decoy, isDecoy = Nametags.getDecoySplitSample(model, at)
		return not isCamouflage or camouflage.fullReveal,
			(not isCamouflage or camouflage.fullReveal) and (not isDecoy or not decoy.active),
			if isDecoy and decoy.active then decoy.encounterId or "" else ""
	end

	local function withModel(callback: (Model) -> ())
		local runtime = workspace:FindFirstChild("Runtime")
		local ownRuntime = runtime == nil
		if not runtime then
			runtime = Instance.new("Folder")
			runtime.Name, runtime.Parent = "Runtime", workspace
		end
		local folder = runtime:FindFirstChild("Brainrots")
		local ownFolder = folder == nil
		if not folder then
			folder = Instance.new("Folder")
			folder.Name, folder.Parent = "Brainrots", runtime
		end
		local model = Instance.new("Model")
		model.Name, model.Parent = "SPEC_METADATA_PREDICATES", folder
		model:SetAttribute("ItemId", "predicate-fixture")
		model:SetAttribute("Captured", false)
		model:SetAttribute(
			Config.Attributes.CamouflageSnapshot,
			Camouflage.EncodeSnapshot({
				runtimeId = "predicate-fixture",
				revision = 1,
				active = true,
				cycleStart = 100,
			})
		)
		model:SetAttribute(
			Config.Attributes.DecoySplitSnapshot,
			Decoy.EncodeSnapshot({
				runtimeId = "predicate-fixture",
				revision = 1,
				active = true,
				encounterId = "predicate-encounter",
				startedAt = 100,
				expiresAt = 106,
				decoyCount = 2,
			})
		)
		local ok, reason = pcall(callback, model)
		model:Destroy()
		if ownFolder then
			folder:Destroy()
		end
		if ownRuntime then
			runtime:Destroy()
		end
		if not ok then
			error(reason, 0)
		end
	end

	local function compare(model: Model, at: number)
		local aim, metadata, token = reference(model, at)
		expect(Nametags.isAimAssistEligible(model, at)).to.equal(aim)
		expect(Nametags.isIdentifyingMetadataPermitted(model, at)).to.equal(metadata)
		expect(Nametags.getAimResetToken(model, at)).to.equal(token)
		-- Phase12 needs only concealment, so the existing eligibility predicate
		-- supplies its exact complement without allocating an inactive sample.
		local camouflage, isCamouflage = Nametags.getCamouflageSample(model, at)
		expect(not Nametags.isAimAssistEligible(model, at)).to.equal(isCamouflage and not camouflage.fullReveal)
	end

	describe("Brainrot metadata predicate work", function()
		it("preserves every roster species across wild, sleeping, carried, cargo and deposited states", function()
			withModel(function(model)
				local checked = 0
				local times = { 99, 100, 100.5, 100.9, 101.05, 102.85, 103, 105.999, 106 }
				for index = 1, 35 do
					local id = string.format("BRT_%03d", index)
					expect(Catalog.Get(id) ~= nil).to.equal(true)
					model:SetAttribute(Config.Attributes.BrainrotId, id)
					for _, state in
						{
							Config.States.Awake,
							Config.States.Sleeping,
							Config.States.Carried,
							Config.States.Cart,
							Config.States.Deposited,
						}
					do
						model:SetAttribute(Config.Attributes.DisplayState, state)
						model:SetAttribute("Captured", state == Config.States.Sleeping)
						for _, at in times do
							compare(model, at)
							checked += 1
						end
					end
				end
				expect(checked).to.equal(1575)
			end)
		end)

		it("keeps current species metadata authoritative after changes, unknown IDs and missing IDs", function()
			withModel(function(model)
				model:SetAttribute(Config.Attributes.DisplayState, Config.States.Awake)
				for _, id in { "BRT_028", "BRT_001", "BRT_029", "unknown-brainrot", "BRT_028" } do
					model:SetAttribute(Config.Attributes.BrainrotId, id)
					compare(model, 101.5)
				end
				model:SetAttribute(Config.Attributes.BrainrotId, nil)
				compare(model, 101.5)
			end)
		end)

		it("preserves active conceal/reveal and decoy expiry boundaries", function()
			withModel(function(model)
				model:SetAttribute(Config.Attributes.DisplayState, Config.States.Awake)
				model:SetAttribute(Config.Attributes.BrainrotId, "BRT_028")
				expect(Catalog.Get("BRT_028").behaviourId).to.equal("Camouflage")
				expect(Nametags.isAimAssistEligible(model, 100.5)).to.equal(true)
				expect(Nametags.isIdentifyingMetadataPermitted(model, 100.5)).to.equal(true)
				expect(Nametags.isAimAssistEligible(model, 100 + Behaviour.Camouflage.FullRevealSeconds)).to.equal(
					false
				)
				expect(Nametags.isIdentifyingMetadataPermitted(model, 101.5)).to.equal(false)
				expect(Nametags.isAimAssistEligible(model, 103)).to.equal(true)
				model:SetAttribute(Config.Attributes.BrainrotId, "BRT_029")
				expect(Catalog.Get("BRT_029").behaviourId).to.equal("DecoySplit")
				expect(Nametags.isAimAssistEligible(model, 101)).to.equal(true)
				expect(Nametags.isIdentifyingMetadataPermitted(model, 105.999)).to.equal(false)
				expect(Nametags.getAimResetToken(model, 105.999)).to.equal("predicate-encounter")
				expect(Nametags.isIdentifyingMetadataPermitted(model, 106)).to.equal(true)
				expect(Nametags.getAimResetToken(model, 106)).to.equal("")
			end)
		end)

		it("does not construct irrelevant timing samples for ordinary predicates", function()
			withModel(function(model)
				local originalCamouflage, originalDecoy = Nametags.getCamouflageSample, Nametags.getDecoySplitSample
				local camouflageCalls, decoyCalls = 0, 0
				Nametags.getCamouflageSample = function(...)
					camouflageCalls += 1
					return originalCamouflage(...)
				end
				Nametags.getDecoySplitSample = function(...)
					decoyCalls += 1
					return originalDecoy(...)
				end
				local ok, reason = pcall(function()
					model:SetAttribute(Config.Attributes.BrainrotId, "BRT_001")
					model:SetAttribute(Config.Attributes.DisplayState, Config.States.Awake)
					for _ = 1, 600 do
						expect(Nametags.isAimAssistEligible(model, 101)).to.equal(true)
						expect(Nametags.isIdentifyingMetadataPermitted(model, 101)).to.equal(true)
						expect(Nametags.getAimResetToken(model, 101)).to.equal("")
					end
					expect(camouflageCalls).to.equal(0)
					expect(decoyCalls).to.equal(0)
					-- Public sampling APIs still return the same complete structs.
					local sample, isCamouflage = Nametags.getCamouflageSample(model, 101)
					expect(isCamouflage).to.equal(false)
					expect(sample.phase).to.equal("Inactive")
					local decoy, isDecoy = Nametags.getDecoySplitSample(model, 101)
					expect(isDecoy).to.equal(false)
					expect(decoy.active).to.equal(false)
				end)
				Nametags.getCamouflageSample, Nametags.getDecoySplitSample = originalCamouflage, originalDecoy
				if not ok then
					error(reason, 0)
				end
			end)
		end)
	end)
end
