--!nocheck

return function()
	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")

	local Config = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).DecoySplit
	local Catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local DisplayConfig = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
	local Timing = require(ReplicatedStorage.Shared.Behaviours.DecoySplitTiming)
	local CuePresentation = require(ReplicatedStorage.Shared.Utility.BrainrotDecoyCuePresentation)
	local DecoyVisuals = require(script.Parent.Parent.Utility.DecoyVisuals)
	local DecoySplit = require(script.Parent.Parent.Systems.Behaviours.DecoySplit)
	local Nametags = require(
		game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.BrainrotNametagController
	)

	local function ensureFolder(parent, name)
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing, false
		end
		local value = Instance.new("Folder")
		value.Name, value.Parent = name, parent
		return value, true
	end

	local function makeReal(name)
		local model = Instance.new("Model")
		model.Name = name
		model:SetAttribute("ItemId", name)
		model:SetAttribute("BrainrotId", "BRT_029")
		model:SetAttribute("Captured", false)
		model:SetAttribute(DisplayConfig.Attributes.DisplayState, DisplayConfig.States.Awake)
		local body = Instance.new("Part")
		body.Name, body.Size, body.Anchored = "Body", Vector3.new(2, 3.5, 2), true
		body.Parent, model.PrimaryPart = model, body
		return model
	end

	local function threat(userId, distance)
		local character = Instance.new("Model")
		character.Name, character.Parent = "Threat", workspace
		return {
			UserId = userId,
			Character = character,
			Position = Vector3.new(distance, 0, 0),
		}
	end

	local function createFixtureVisual(_, decoyId, encounterId, localFrame, size)
		local model = Instance.new("Model")
		model.Name = decoyId
		model:SetAttribute("EffectKind", "Decoy")
		model:SetAttribute("DecoyId", decoyId)
		model:SetAttribute("EncounterId", encounterId)
		local visual = Instance.new("Part")
		visual.Name, visual.Size, visual.Anchored = "Visual", Vector3.new(2, 3.5, 2), true
		visual.CanCollide, visual.CanTouch, visual.CanQuery = false, false, false
		visual.Parent = model
		local proxy = Instance.new("Part")
		proxy.Name, proxy.Size, proxy.CFrame = "HitProxy", size, model:GetPivot() * localFrame
		proxy.Transparency, proxy.Anchored = 1, true
		proxy.CanCollide, proxy.CanTouch, proxy.CanQuery = false, false, true
		proxy:SetAttribute("EffectKind", "Decoy")
		proxy:SetAttribute("DecoyId", decoyId)
		proxy:SetAttribute("EncounterId", encounterId)
		proxy.Parent = model
		model.PrimaryPart = visual
		return { Model = model, HitProxy = proxy }
	end

	local function makeContext(real, candidates, overrides)
		local context = {
			Authorized = true,
			LifecycleEligible = true,
			RuntimeId = real:GetAttribute("ItemId"),
			BrainrotId = real:GetAttribute("BrainrotId"),
			Position = real:GetPivot().Position,
			Forward = -Vector3.zAxis,
			CourseDirection = -Vector3.zAxis,
			Candidates = candidates or {},
			Sensing = true,
			CanSeeCandidate = function()
				return true
			end,
			GetHitEnvelope = function()
				return real:GetPivot(), Vector3.new(2, 3.5, 2)
			end,
			ResolvePlacement = function(pivot)
				return pivot
			end,
			ResolveFollowPose = function(_, pivot)
				return pivot
			end,
			LaneChoice = 0,
			CreateVisual = createFixtureVisual,
		}
		for key, value in overrides or {} do
			context[key] = value
		end
		return context
	end

	local function withRuntime(callback)
		local runtime, madeRuntime = ensureFolder(workspace, "Runtime")
		local brainrots, madeBrainrots = ensureFolder(runtime, "Brainrots")
		local owned = {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local ok, failure = xpcall(function()
			callback(brainrots, own)
		end, debug.traceback)
		for index = #owned, 1, -1 do
			if owned[index].Parent ~= nil then
				owned[index]:Destroy()
			end
		end
		if madeBrainrots and brainrots.Parent then
			brainrots:Destroy()
		end
		if madeRuntime and runtime.Parent then
			runtime:Destroy()
		end
		if not ok then
			error(failure, 0)
		end
	end

	describe("Phase 6D-5 Decoy Split timing and assignment", function()
		it("uses the explicit BRT_029 profile without deriving it from Epic rarity", function()
			expect(Catalog.Get("BRT_029").behaviourId).to.equal("DecoySplit")
			for _, id in { "BRT_026", "BRT_027", "BRT_030" } do
				expect(Catalog.Get(id).behaviourId).to.equal("Wanderer")
			end
			expect(Catalog.Get("BRT_028").behaviourId).to.equal("Camouflage")
		end)

		it("encodes complete snapshots and samples the synchronized cue pulse", function()
			local snapshot = {
				runtimeId = "runtime",
				revision = 2,
				active = true,
				encounterId = "encounter",
				startedAt = 100,
				expiresAt = 106,
				decoyCount = 2,
			}
			local decoded = Timing.DecodeSnapshot(Timing.EncodeSnapshot(snapshot))
			expect(decoded.runtimeId).to.equal("runtime")
			expect(Timing.Sample(decoded, 100, Config).active).to.equal(true)
			expect(Timing.Sample(decoded, 100, Config).pulseTransparency).to.equal(1)
			expect(math.abs(Timing.Sample(decoded, 100.1, Config).pulseTransparency - 0.15) < 1e-6).to.equal(
				true
			)
			expect(Timing.Sample(decoded, 100.2, Config).pulseTransparency).to.equal(nil)
			expect(Timing.Sample(decoded, 101.25, Config).pulseTransparency).to.equal(1)
			expect(Timing.Sample(decoded, 106, Config).active).to.equal(false)
			expect(Timing.Sample(decoded, 1000, Config).active).to.equal(false)
			expect(Timing.DecodeSnapshot("bad")).to.equal(nil)
		end)
	end)

	describe("Decoy visual construction and economic isolation", function()
		it("sanitizes a normal source into one inert visual plus one queryable proxy", function()
			local assets, madeAssets = ensureFolder(ReplicatedStorage, "StudioAssets")
			local brainrots, madeBrainrots = ensureFolder(assets, "Brainrots")
			local source = Instance.new("Model")
			source.Name = "SPEC_DECOY_VISUAL_" .. HttpService:GenerateGUID(false)
			source:SetAttribute("SpeciesId", "BRT_029")
			source:SetAttribute("RuntimeId", "real")
			source:SetAttribute("cashPerSecond", 999)
			CollectionService:AddTag(source, DisplayConfig.CollectionTag)
			local body = Instance.new("Part")
			body.Name, body.Size, body.Anchored, body.Parent =
				"Body", Vector3.new(2, 4, 2), true, source
			source.PrimaryPart = body
			for _, name in { "CaptureAttachment", "CargoAttachment" } do
				local attachment = Instance.new("Attachment")
				attachment.Name, attachment.Parent = name, body
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Parent = body
			local scriptObject = Instance.new("Script")
			scriptObject.Parent = source
			local billboard = Instance.new("BillboardGui")
			billboard.Parent = body
			local objectValue = Instance.new("ObjectValue")
			objectValue.Value, objectValue.Parent = workspace, source
			source.Parent = brainrots

			local prepared, reason = DecoyVisuals.Create(
				source.Name,
				"D:test:1",
				"test",
				CFrame.new(),
				Vector3.new(4, 5, 4)
			)
			assert(prepared, reason)
			local queryable = 0
			for _, item in prepared.Model:GetDescendants() do
				expect(item:IsA("LuaSourceContainer")).to.equal(false)
				expect(item:IsA("ProximityPrompt")).to.equal(false)
				expect(item:IsA("BillboardGui")).to.equal(false)
				expect(item:IsA("ObjectValue")).to.equal(false)
				expect(#CollectionService:GetTags(item)).to.equal(0)
				if item:IsA("BasePart") and item.CanQuery then
					queryable += 1
					expect(item).to.equal(prepared.HitProxy)
				end
				if item ~= prepared.HitProxy then
					expect(item:GetAttribute("SpeciesId")).to.equal(nil)
					expect(item:GetAttribute("RuntimeId")).to.equal(nil)
					expect(item:GetAttribute("cashPerSecond")).to.equal(nil)
				end
			end
			expect(queryable).to.equal(1)
			expect(prepared.Model:GetAttribute("ItemId")).to.equal(nil)
			expect(CollectionService:HasTag(prepared.Model, DisplayConfig.CollectionTag)).to.equal(
				false
			)
			expect(source:GetAttribute("RuntimeId")).to.equal("real")
			expect(source:FindFirstChildOfClass("Script")).never.to.equal(nil)
			prepared.Model:Destroy()
			source:Destroy()
			if madeBrainrots then
				brainrots:Destroy()
			end
			if madeAssets then
				assets:Destroy()
			end
		end)
	end)

	describe("Decoy encounter ownership, hit routing, caps, and cleanup", function()
		it("keeps the real identity fixed across left, centre, and right layouts", function()
			withRuntime(function(brainrots, own)
				for _, lane in { -1, 0, 1 } do
					local real = own(makeReal("layout-" .. lane))
					real.Parent = brainrots
					local before = real:GetPivot()
					local candidate = own(threat(lane + 10, 10).Character)
					local candidates = {
						{
							UserId = lane + 10,
							Character = candidate,
							Position = Vector3.new(10, 0, 0),
						},
					}
					local state = DecoySplit.CreateState(0)
					local result = DecoySplit.TryStart(
						real,
						state,
						makeContext(real, candidates, { LaneChoice = lane }),
						100,
						Config
					)
					expect(result.Started).to.equal(true)
					expect(result.DecoyCount).to.equal(2)
					expect(real:GetPivot()).to.equal(before)
					expect(real:GetAttribute("ItemId")).to.equal("layout-" .. lane)
					expect(state.realLane).to.equal(lane)
					DecoySplit.Interrupt(real, state, 101, "Test")
				end
			end)
		end)

		it("removes only a validated decoy and never forwards the hit to its owner", function()
			withRuntime(function(brainrots, own)
				local real = own(makeReal("hit-owner"))
				real.Parent = brainrots
				local candidate = own(threat(1, 10).Character)
				local state = DecoySplit.CreateState(0)
				local result = DecoySplit.TryStart(
					real,
					state,
					makeContext(
						real,
						{ { UserId = 1, Character = candidate, Position = Vector3.new(10, 0, 0) } }
					),
					100,
					Config
				)
				assert(result.Started, result.Reason)
				local decoyId, record = next(state.decoys)
				local proxy = record.HitProxy
				expect(DecoySplit.ResolveHit(proxy)).to.equal("Active")
				local consumed, resolvedId = DecoySplit.OnValidatedDecoyHit(proxy, 101)
				expect(consumed).to.equal(true)
				expect(resolvedId).to.equal(decoyId)
				expect(real:GetAttribute("Captured")).to.equal(false)
				expect(DecoySplit.ResolveHit(proxy)).to.equal("Stale")
				expect(DecoySplit.OnValidatedDecoyHit(proxy, 101)).to.equal(false)
				expect(DecoySplit.GetDiagnostics().ActiveDecoys).to.equal(1)
				DecoySplit.Interrupt(real, state, 102, "Sleeping")
			end)
		end)

		it("preserves expiry cooldown, enforces the two-encounter cap, and cleans once", function()
			withRuntime(function(brainrots, own)
				local active = {}
				for index = 1, 3 do
					local real = own(makeReal("cap-" .. index))
					real.Parent = brainrots
					local character = own(threat(index, 10).Character)
					local state = DecoySplit.CreateState(0)
					local result = DecoySplit.TryStart(
						real,
						state,
						makeContext(real, {
							{
								UserId = index,
								Character = character,
								Position = Vector3.new(10, 0, 0),
							},
						}),
						100,
						Config
					)
					if index <= 2 then
						expect(result.Started).to.equal(true)
						table.insert(active, { Real = real, State = state })
					else
						expect(result.Started).to.equal(nil)
						expect(result.Reason).to.equal("EffectCap")
					end
				end
				expect(DecoySplit.GetDiagnostics().ActiveEncounters).to.equal(2)
				local first = active[1]
				local context = makeContext(first.Real, {})
				context.Sensing = false
				DecoySplit.Step(first.Real, first.State, context, 105.99, 0.05, Config)
				expect(first.State.active).to.equal(true)
				DecoySplit.Step(first.Real, first.State, context, 106, 0.05, Config)
				expect(first.State.active).to.equal(false)
				expect(first.State.nextAllowedAt).to.equal(114)
				expect(DecoySplit.Interrupt(first.Real, first.State, 107, "Again")).to.equal(false)
				DecoySplit.Interrupt(active[2].Real, active[2].State, 107, "Test")
				local diagnostics = DecoySplit.GetDiagnostics()
				expect(diagnostics.ActiveEncounters).to.equal(0)
				expect(diagnostics.ActiveDecoys).to.equal(0)
				expect(diagnostics.HitProxies).to.equal(0)
			end)
		end)

		it("runs repeated start/end cycles without retained registry entries", function()
			withRuntime(function(brainrots, own)
				local real = own(makeReal("stress-owner"))
				real.Parent = brainrots
				local character = own(threat(1, 10).Character)
				local candidate =
					{ UserId = 1, Character = character, Position = Vector3.new(10, 0, 0) }
				for index = 1, 100 do
					local now = index * 20
					local state = DecoySplit.CreateState(now)
					local result = DecoySplit.TryStart(
						real,
						state,
						makeContext(real, { candidate }),
						now,
						Config
					)
					assert(result.Started, result.Reason)
					DecoySplit.Interrupt(real, state, now + 1, "Stress")
				end
				local diagnostics = DecoySplit.GetDiagnostics()
				expect(diagnostics.ActiveEncounters).to.equal(0)
				expect(diagnostics.ActiveDecoys).to.equal(0)
				expect(diagnostics.HitProxies).to.equal(0)
				local root = workspace.Runtime:FindFirstChild("Decoys")
				for _, child in if root then root:GetChildren() else {} do
					expect(string.sub(child.Name, 1, 10)).never.to.equal("Encounter_")
				end
			end)
		end)
	end)

	describe("Decoy real-target cue cleanup", function()
		it("reuses one trail/highlight and removes only effect-owned objects", function()
			local model = makeReal("cue")
			model.Parent = workspace
			local binding = CuePresentation.Bind(
				model,
				Config.TrailLifetimeSeconds,
				Config.TrailMaxLengthStuds,
				Config.TrailWidthStuds
			)
			assert(binding, "Cue fixture could not bind")
			CuePresentation.Update(binding, 0.15)
			expect(binding.Highlight.Enabled).to.equal(true)
			expect(binding.Highlight.DepthMode).to.equal(Enum.HighlightDepthMode.Occluded)
			expect(binding.Trail.Color.Keypoints[1].Value).to.equal(Color3.fromRGB(0, 235, 255))
			CuePresentation.Update(binding, nil)
			expect(binding.Highlight.Enabled).to.equal(false)
			CuePresentation.Unbind(binding)
			CuePresentation.Unbind(binding)
			expect(model:FindFirstChild("DecoyRealTrail", true)).to.equal(nil)
			expect(model:FindFirstChild("DecoyRealPulse", true)).to.equal(nil)
			expect(model:FindFirstChild("Body", true)).never.to.equal(nil)
			model:Destroy()
		end)

		it(
			"suppresses real-only metadata and changes the retained-aim token for one encounter",
			function()
				withRuntime(function(brainrots, own)
					local real = own(makeReal("metadata-owner"))
					real.Parent = brainrots
					local active = {
						runtimeId = "metadata-owner",
						revision = 1,
						active = true,
						encounterId = "encounter-metadata",
						startedAt = 100,
						expiresAt = 106,
						decoyCount = 2,
					}
					real:SetAttribute(
						DisplayConfig.Attributes.DecoySplitSnapshot,
						Timing.EncodeSnapshot(active)
					)
					expect(Nametags.isIdentifyingMetadataPermitted(real, 101)).to.equal(false)
					expect(Nametags.getAimResetToken(real, 101)).to.equal("encounter-metadata")

					local inactive = table.clone(active)
					inactive.revision, inactive.active, inactive.decoyCount = 2, false, 0
					inactive.encounterId, inactive.startedAt, inactive.expiresAt = nil, nil, nil
					real:SetAttribute(
						DisplayConfig.Attributes.DecoySplitSnapshot,
						Timing.EncodeSnapshot(inactive)
					)
					expect(Nametags.isIdentifyingMetadataPermitted(real, 102)).to.equal(true)
					expect(Nametags.getAimResetToken(real, 102)).to.equal("")
				end)
			end
		)
	end)
end
