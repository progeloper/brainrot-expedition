--!nocheck
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local StarterPlayer = game:GetService("StarterPlayer")

	local Config = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).Camouflage
	local DisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
	local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Timing = require(ReplicatedStorage.Shared.Behaviours.CamouflageTiming)
	local Presentation = require(ReplicatedStorage.Shared.Utility.BrainrotCamouflagePresentation)
	local Camouflage = require(script.Parent.Parent.Systems.Behaviours.Camouflage)
	local Nametags =
		require(StarterPlayer.StarterPlayerScripts.Client.Controllers.BrainrotNametagController)

	local function close(actual, expected, tolerance)
		expect(math.abs(actual - expected) <= (tolerance or 0.0001)).to.equal(true)
	end

	local function threat(userId, distance)
		return {
			UserId = userId,
			Character = { Generation = userId },
			Position = Vector3.new(distance, 0, 0),
		}
	end

	local function context(candidates, overrides)
		overrides = overrides or {}
		return {
			Authorized = if overrides.Authorized == nil then true else overrides.Authorized,
			LifecycleEligible = if overrides.LifecycleEligible == nil
				then true
				else overrides.LifecycleEligible,
			Position = overrides.Position or Vector3.zero,
			Candidates = candidates or {},
			Sensing = if overrides.Sensing == nil then true else overrides.Sensing,
			CanSeeCandidate = overrides.CanSeeCandidate or function()
				return true
			end,
		}
	end

	describe("Phase 6D-4 Camouflage timing and engagement", function()
		it("keeps the complete initial tuning in one shared profile", function()
			local expected = {
				AwarenessRadius = 42,
				DisengageRadius = 50,
				DisengageGraceSeconds = 0.75,
				SenseIntervalSeconds = 0.10,
				RevealPeriodSeconds = 3.00,
				FullRevealSeconds = 0.90,
				ConcealFadeSeconds = 0.15,
				RevealFadeSeconds = 0.15,
				ConcealAmount = 0.88,
				RevealCueSeconds = 0.30,
				RevealCueOutlineTransparency = 0.15,
			}
			for key, value in expected do
				expect(Config[key]).to.equal(value)
			end
		end)

		it("samples the exact three-second reveal schedule", function()
			local snapshot = { runtimeId = "one", revision = 1, active = true, cycleStart = 100 }
			local samples = {
				{ 100.000, "Revealed", 0, true },
				{ 100.450, "Revealed", 0, true },
				{ 100.899, "Revealed", 0, true },
				{ 100.900, "Concealing", 0, false },
				{ 100.975, "Concealing", 0.44, false },
				{ 101.050, "Hidden", 0.88, false },
				{ 102.000, "Hidden", 0.88, false },
				{ 102.850, "Revealing", 0.88, false },
				{ 102.925, "Revealing", 0.44, false },
				{ 103.000, "Revealed", 0, true },
				{ 106.000, "Revealed", 0, true },
			}
			for _, row in samples do
				local sampled = Timing.Sample(snapshot, row[1], Config)
				expect(sampled.phase).to.equal(row[2])
				close(sampled.camouflageAmount, row[3], 0.0002)
				expect(sampled.fullReveal).to.equal(row[4])
			end
		end)

		it("samples late observers directly without replaying missed cycles", function()
			local snapshot = { runtimeId = "one", revision = 4, active = true, cycleStart = 100 }
			local first = Timing.Sample(snapshot, 111.2, Config)
			local second = Timing.Sample(snapshot, 111.2, Config)
			expect(first.phase).to.equal("Hidden")
			expect(first.cycleIndex).to.equal(3)
			expect(first.phase).to.equal(second.phase)
			close(first.phaseTime, second.phaseTime)
			close(first.camouflageAmount, second.camouflageAmount)
		end)

		it("round-trips complete snapshots and rejects stale or malformed replacements", function()
			local current = assert(Timing.DecodeSnapshot(Timing.EncodeSnapshot({
				runtimeId = "same-individual",
				revision = 8,
				active = true,
				cycleStart = 1234.5,
			})))
			expect(current.runtimeId).to.equal("same-individual")
			expect(current.cycleStart).to.equal(1234.5)
			local stale = assert(Timing.DecodeSnapshot(Timing.EncodeSnapshot({
				runtimeId = "same-individual",
				revision = 7,
				active = false,
				cycleStart = nil,
			})))
			expect(Timing.AcceptNewerSnapshot(current, stale)).to.equal(current)
			expect(Timing.AcceptNewerSnapshot(current, current)).to.equal(current)
			expect(Timing.DecodeSnapshot("not-json")).to.equal(nil)
			expect(Timing.Sample(nil, 100, Config).phase).to.equal("Unresolved")
			expect(Timing.Sample(nil, 100, Config).fullReveal).to.equal(false)
		end)

		it("activates inclusively at 42 studs and not at 42.01", function()
			local state = Camouflage.CreateState(0)
			local result = Camouflage.Step(state, context({ threat(1, 42.01) }), 10, Config)
			expect(result.Activated).to.equal(nil)
			expect(state.active).to.equal(false)
			result = Camouflage.Step(state, context({ threat(1, 42) }), 10.1, Config)
			expect(result.Activated).to.equal(true)
			expect(state.active).to.equal(true)
			expect(state.cycleStart).to.equal(10.1)
			expect(state.revision).to.equal(1)
		end)

		it("keeps one schedule while qualifying observers hand off", function()
			local state = Camouflage.CreateState(0)
			Camouflage.Step(state, context({ threat(1, 10) }), 20, Config)
			local cycleStart, revision = state.cycleStart, state.revision
			Camouflage.Step(state, context({ threat(2, 45) }), 21, Config)
			expect(state.active).to.equal(true)
			expect(state.cycleStart).to.equal(cycleStart)
			expect(state.revision).to.equal(revision)
		end)

		it("uses one disengagement grace and lifecycle interruption is idempotent", function()
			local state = Camouflage.CreateState(0)
			Camouflage.Step(state, context({ threat(1, 10) }), 1, Config)
			Camouflage.Step(state, context({}), 2, Config)
			expect(state.active).to.equal(true)
			Camouflage.Step(state, context({}), 2.749, Config)
			expect(state.active).to.equal(true)
			local result = Camouflage.Step(state, context({}), 2.75, Config)
			expect(result.Deactivated).to.equal(true)
			expect(state.active).to.equal(false)
			expect(state.revision).to.equal(2)
			expect(Camouflage.Interrupt(state, 3, "Sleeping")).to.equal(false)
			expect(state.revision).to.equal(2)

			Camouflage.Step(state, context({ threat(1, 10) }), 4, Config)
			result = Camouflage.Step(state, context({}, { LifecycleEligible = false }), 4.1, Config)
			expect(result.Deactivated).to.equal(true)
			expect(result.Reason).to.equal("Lifecycle")
			expect(state.cycleStart).to.equal(nil)
		end)

		it("keeps independent schedules and uses only the explicit BRT_028 assignment", function()
			local first, second = Camouflage.CreateState(0), Camouflage.CreateState(0)
			Camouflage.Step(first, context({ threat(1, 10) }), 5, Config)
			Camouflage.Step(second, context({ threat(2, 10) }), 7, Config)
			expect(first.cycleStart).to.equal(5)
			expect(second.cycleStart).to.equal(7)
			expect(Catalog.Get("BRT_028").behaviourId).to.equal("Camouflage")
			for _, id in { "BRT_026", "BRT_027", "BRT_030" } do
				expect(Catalog.Get(id).behaviourId).to.equal("Wanderer")
			end
			expect(Catalog.Get("BRT_029").behaviourId).to.equal("DecoySplit")
		end)
	end)

	describe("Camouflage reversible presentation", function()
		it(
			"skips steady visual walks but refreshes fades, external modifiers and late descendants",
			function()
				local model = Instance.new("Model")
				local body = Instance.new("Part")
				body.Parent = model
				local binding = Presentation.Bind(model)
				expect(Presentation.Apply(binding, 0.88, false, nil)).to.equal(true)
				for _ = 1, 120 do
					expect(Presentation.Apply(binding, 0.88, false, nil)).to.equal(false)
				end
				body.LocalTransparencyModifier = 0.25
				expect(Presentation.Apply(binding, 0.88, false, nil)).to.equal(true)
				close(body.LocalTransparencyModifier, 0.91)
				local late = Instance.new("Part")
				late.Parent = model
				close(late.LocalTransparencyModifier, 0.88)
				expect(Presentation.Apply(binding, 0.44, false, nil)).to.equal(true)
				close(body.LocalTransparencyModifier, 0.58)
				local connection = binding.VisualConnections[late]
				late.Parent = nil
				expect(connection.Connected).to.equal(false)
				close(late.LocalTransparencyModifier, 0)
				Presentation.RestoreNormal(binding)
				close(body.LocalTransparencyModifier, 0.25)
				Presentation.Unbind(binding)
				expect(next(binding.VisualConnections)).to.equal(nil)
				late:Destroy()
				model:Destroy()
			end
		)
		it(
			"composes concealment and restores authored visibility without changing queries",
			function()
				local model = Instance.new("Model")
				model.Name = "SPEC_CAMOUFLAGE_PRESENTATION"
				local body = Instance.new("Part")
				body.Name, body.Transparency, body.LocalTransparencyModifier = "Body", 0.4, 0
				body.CanQuery, body.CastShadow, body.Parent = true, true, model
				model.PrimaryPart = body
				local root = Instance.new("Part")
				root.Name, root.Transparency, root.LocalTransparencyModifier = "InvisibleRoot", 1, 0
				root.Parent = model
				local decal = Instance.new("Decal")
				decal.Transparency, decal.Parent = 0.3, body
				local trail = Instance.new("Trail")
				trail.Enabled, trail.Parent = true, body
				local emitter = Instance.new("ParticleEmitter")
				emitter.Enabled, emitter.Parent = false, body

				local binding = Presentation.Bind(model)
				Presentation.Apply(binding, 0.88, false, nil)
				close(body.LocalTransparencyModifier, 0.88)
				close(body.Transparency, 0.4)
				expect(body.CanQuery).to.equal(true)
				expect(body.CastShadow).to.equal(false)
				expect(root.Transparency).to.equal(1)
				close(decal.Transparency, 0.916)
				expect(trail.Enabled).to.equal(false)
				expect(emitter.Enabled).to.equal(false)

				local late = Instance.new("Part")
				late.LocalTransparencyModifier, late.Parent = 0.25, model
				close(late.LocalTransparencyModifier, 0.91)

				Presentation.RestoreNormal(binding)
				expect(body.LocalTransparencyModifier).to.equal(0)
				close(body.Transparency, 0.4)
				expect(body.CastShadow).to.equal(true)
				expect(root.Transparency).to.equal(1)
				close(decal.Transparency, 0.3)
				expect(trail.Enabled).to.equal(true)
				expect(emitter.Enabled).to.equal(false)
				close(late.LocalTransparencyModifier, 0.25)

				Presentation.Apply(binding, 0, true, 0.15)
				expect(binding.Cue.DepthMode).to.equal(Enum.HighlightDepthMode.Occluded)
				expect(binding.Cue.FillTransparency).to.equal(1)
				expect(binding.Cue.Enabled).to.equal(true)
				Presentation.Apply(binding, 0, true, nil)
				expect(binding.Cue.Enabled).to.equal(false)
				Presentation.Unbind(binding)
				expect(model:FindFirstChild("CamouflageRevealCue")).to.equal(nil)

				local rebound = Presentation.Bind(model)
				expect(#model:GetChildren()).to.equal(4)
				Presentation.Unbind(rebound)
				model:Destroy()
			end
		)

		it("keeps two same-species visual bindings independent", function()
			local models, bindings = {}, {}
			for _ = 1, 2 do
				local model = Instance.new("Model")
				local body = Instance.new("Part")
				body.Name, body.Parent = "Body", model
				model.PrimaryPart = body
				table.insert(models, model)
				table.insert(bindings, Presentation.Bind(model))
			end
			Presentation.Apply(bindings[1], 0.88, false, nil)
			close(models[1].Body.LocalTransparencyModifier, 0.88)
			expect(models[2].Body.LocalTransparencyModifier).to.equal(0)
			for index, binding in bindings do
				Presentation.Unbind(binding)
				models[index]:Destroy()
			end
		end)
	end)

	describe("Camouflage nametag and assistance metadata", function()
		it("suppresses only awake-world identifying metadata outside full reveal", function()
			local runtime = workspace:FindFirstChild("Runtime") or Instance.new("Folder")
			runtime.Name, runtime.Parent = "Runtime", workspace
			local folder = runtime:FindFirstChild("Brainrots") or Instance.new("Folder")
			folder.Name, folder.Parent = "Brainrots", runtime
			local model = Instance.new("Model")
			model.Name = "SPEC_CAMOUFLAGE_METADATA"
			model:SetAttribute("ItemId", "camouflage-individual")
			model:SetAttribute(DisplayConfig.Attributes.BrainrotId, "BRT_028")
			model:SetAttribute(DisplayConfig.Attributes.DisplayState, DisplayConfig.States.Awake)
			model:SetAttribute("Captured", false)
			model:SetAttribute(
				DisplayConfig.Attributes.CamouflageSnapshot,
				Timing.EncodeSnapshot({
					runtimeId = "camouflage-individual",
					revision = 2,
					active = true,
					cycleStart = 100,
				})
			)
			model.Parent = folder

			expect(Nametags.isIdentifyingMetadataPermitted(model, 100.5)).to.equal(true)
			expect(Nametags.isAimAssistEligible(model, 101.5)).to.equal(false)
			model:SetAttribute(
				DisplayConfig.Attributes.CamouflageSnapshot,
				Timing.EncodeSnapshot({
					runtimeId = "camouflage-individual",
					revision = 1,
					active = false,
					cycleStart = nil,
				})
			)
			expect(Nametags.isAimAssistEligible(model, 101.5)).to.equal(false)

			model:SetAttribute("Captured", true)
			expect(Nametags.isIdentifyingMetadataPermitted(model, 101.5)).to.equal(true)
			model:SetAttribute("Captured", false)
			model:SetAttribute(
				DisplayConfig.Attributes.CamouflageSnapshot,
				Timing.EncodeSnapshot({
					runtimeId = "camouflage-individual",
					revision = 3,
					active = false,
					cycleStart = nil,
				})
			)
			expect(Nametags.isAimAssistEligible(model, 101.5)).to.equal(true)
			model:Destroy()
		end)
	end)
end
