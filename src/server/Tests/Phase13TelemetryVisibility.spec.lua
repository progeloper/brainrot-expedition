--!nocheck
-- Pure report validation and disposable native context fixtures. These tests do
-- not stand in for two connected clients, streaming or measured device frames.
return function()
	local Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13TelemetryRules)
	local Visibility = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.RegionVisibilityController)
	local function valid()
		return {
			windowSeconds = 60,
			sampleCount = 4,
			p50Ms = 20,
			p90Ms = 60,
			bands = { 1, 1, 1, 1 },
			graphicsTier = 0,
			visibility = {
				visible = 4,
				detailed = 3,
				reduced = 1,
				hidden = 8,
				interestSubscriptions = 1,
				renderDistance = 180,
			},
		}
	end
	describe("Phase13 bounded untrusted client observations", function()
		it("samples exact nearest rank percentiles and conserves all frame bands", function()
			local sample = Rules.Summarize({ 10, 20, 40, 60 })
			expect(sample.p50Ms).to.equal(20)
			expect(sample.p90Ms).to.equal(60)
			local sum = 0
			for _, count in sample.bands do
				sum += count
			end
			expect(sum).to.equal(4)
			expect(Rules.Summarize({ 0 })).to.equal(nil)
			expect(Rules.Summarize({ math.huge })).to.equal(nil)
		end)
		it("keeps unavailable measurements absent and validates known zero pause/Auto graphics", function()
			local source = valid()
			source.streamPauseSeconds = 0
			local clean = assert(Rules.Validate(source))
			expect(clean.memoryMB).to.equal(nil)
			expect(clean.streamPauseSeconds).to.equal(0)
			expect(clean.graphicsTier).to.equal(0)
		end)
		it(
			"separates optional proxy/template counts from visible full and reduced art without inventing missing measurements",
			function()
				local source = valid()
				local missing = assert(Rules.Validate(source))
				expect(missing.visibility.authorityProxies).to.equal(nil)
				source.visibility.interestEntries, source.visibility.interestExits = 3, 2
				source.visibility.authorityProxies = 42
				source.visibility.localFullModels, source.visibility.localReducedModels = 3, 1
				source.visibility.cacheParts = 740
				local clean = assert(Rules.Validate(source))
				expect(clean.visibility.visible).to.equal(4)
				expect(clean.visibility.authorityProxies).to.equal(42)
				expect(clean.visibility.cacheParts).to.equal(740)
				source.visibility.cacheParts = 65537
				expect(Rules.Validate(source)).to.equal(nil)
			end
		)
		it(
			"records one approved-rift failure per client session with no gameplay readiness dependency or duplicate outcome",
			function()
				local Adapter = require(script.Parent.Parent.Services.Phase13AnalyticsService)
				local Receiver = require(script.Parent.Parent.Services.Phase13ClientTelemetryService)
				Receiver:Stop()
				Adapter:_ResetForTests()
				local player = { Parent = game:GetService("Players") }
				expect(Receiver:Accept(player, { kind = "CinematicAsset", category = "UNBOUNDED" })).to.equal(false)
				expect(Receiver:Accept(player, { kind = "CinematicAsset", category = "RIFT_NOT_RESIDENT" })).to.equal(
					true
				)
				expect(Receiver:Accept(player, { kind = "CinematicAsset", category = "RIFT_NOT_RESIDENT" })).to.equal(
					false
				)
				expect(Receiver:Accept(player, { kind = "CinematicAsset", category = "RIFT_FETCH_FAILED" })).to.equal(
					false
				)
				Adapter:Step(0)
				local recorded = Adapter:GetRecorder()
				expect(#recorded).to.equal(1)
				expect(recorded[1].name).to.equal("CinematicOutcome")
				expect(recorded[1].fields.CustomField02).to.equal("RIFT_NOT_RESIDENT")
				expect(recorded[1].fields.CustomField03).to.equal("Unavailable")
				Receiver:Stop()
				Adapter:_ResetForTests()
			end
		)
		it("preserves initially unknown focus instead of claiming a focused sample window", function()
			local source = valid()
			local unknown = assert(Rules.Validate(source))
			expect(unknown.focusKnown).to.equal(false)
			expect(unknown.focused).to.equal(nil)
			source.focusKnown, source.focused = true, true
			expect(Rules.Validate(source).focused).to.equal(true)
			source.focusKnown = false
			expect(Rules.Validate(source)).to.equal(nil)
		end)
		it("maps actual pickup rejection reasons into stable bounded diagnostic categories", function()
			for reason, category in
				{
					OUT_OF_REACH = "PickupOutOfRange",
					OBSTRUCTED = "PickupOutOfRange",
					NOT_SLEEPING_WORLD = "PickupNotSleeping",
					BANK_SAVE_PENDING = "PickupBusy",
					Saving = "PickupBusy",
					DAZED = "PickupBusy",
					BANKED_PROTECTED = "PickupProtected",
					ProtectionOptOutRequired = "PickupProtected",
					STALE_ID = "PickupStale",
					OWNERSHIP_CHANGED = "PickupStale",
				}
			do
				expect(Rules.PickupCategory(reason)).to.equal(category)
			end
			expect(Rules.PickupCategory("untrusted arbitrary ID")).to.equal("PickupOther")
			expect(Rules.PickupCategory(nil)).to.equal("PickupOther")
		end)
		it("validates only the bounded approved-rift failure reasons", function()
			for _, category in
				{ "RIFT_NOT_RESIDENT", "RIFT_FETCH_FAILED", "RIFT_REFERENCE_INVALID", "RIFT_PRELOAD_TIMEOUT" }
			do
				expect(Rules.ValidateAssetFailure({ kind = "CinematicAsset", category = category })).to.equal(category)
			end
			expect(Rules.ValidateAssetFailure({ kind = "CinematicAsset", category = "arbitrary" })).to.equal(nil)
			expect(Rules.ValidateAssetFailure({
				kind = "CinematicAsset",
				category = "RIFT_NOT_RESIDENT",
				value = math.huge,
			})).to.equal(nil)
		end)
		it("rejects tampered windows, nonfinite values, oversized counts and mismatched totals", function()
			local invalid = valid()
			invalid.sampleCount = 601
			expect(Rules.Validate(invalid)).to.equal(nil)
			invalid = valid()
			invalid.p90Ms = 0 / 0
			expect(Rules.Validate(invalid)).to.equal(nil)
			invalid = valid()
			invalid.visibility.interestSubscriptions = 999
			expect(Rules.Validate(invalid)).to.equal(nil)
			invalid = valid()
			invalid.bands = { 1, 1, 1, 2 }
			expect(Rules.Validate(invalid)).to.equal(nil)
			invalid = valid()
			invalid.visibility.detailed = 4
			expect(Rules.Validate(invalid)).to.equal(nil)
			invalid = valid()
			invalid.arbitraryPlayerId = "not accepted"
			expect(Rules.Validate(invalid)).to.equal(nil)
		end)
	end)
	describe("Phase13 canonical regional presentation eligibility", function()
		it("separates cached visibility values from live listeners and releases each listener on Stop", function()
			Visibility.Stop()
			local model = Instance.new("Model")
			model:SetAttribute("RegionId", "REGION_FOREST")
			model.Parent = workspace
			local part = Instance.new("Part")
			part.Parent = model
			local ok, reason = xpcall(function()
				for _ = 1, 20 do
					Visibility._CacheRegionForTesting(part)
				end
				local observed = Visibility.GetDiagnostics()
				expect(observed.cachedRecords).to.equal(1)
				expect(observed.modelConnectionGroups).to.equal(1)
				expect(observed.activeModelConnections).to.equal(4)
				expect(observed.activeGlobalConnections).to.equal(0)
				expect(observed.activeAvatarConnections).to.equal(0)
				expect(observed.activeHeartbeatSchedules).to.equal(0)
				Visibility.Stop()
				local stopped = Visibility.GetDiagnostics()
				expect(stopped.cachedRecords).to.equal(0)
				expect(stopped.modelConnectionGroups).to.equal(0)
				expect(stopped.activeModelConnections).to.equal(0)
				expect(stopped.activeGlobalConnections).to.equal(0)
				expect(stopped.activeHeartbeatSchedules).to.equal(0)
			end, debug.traceback)
			Visibility.Stop()
			model:Destroy()
			assert(ok, reason)
		end)
		it("does not create a second base LOD representation for protocol authority proxies", function()
			Visibility.Stop()
			local model = Instance.new("Model")
			model.Name = "Stored_PROTOCOL_ONLY"
			model:SetAttribute("CreatureProxy", true)
			model:SetAttribute("RegionId", "REGION_CAMP")
			model.Parent = workspace
			local part = Instance.new("Part")
			part.Parent = model
			Visibility._CacheRegionForTesting(part)
			expect(Visibility.GetDiagnostics().storedLODModels).to.equal(0)
			Visibility.Stop()
			model:Destroy()
		end)
		it(
			"reapplies hidden native properties after external writes and restores their latest observed values",
			function()
				Visibility.Stop()
				local root = Instance.new("Part")
				root.Parent = workspace
				local gui = Instance.new("SurfaceGui")
				gui.Enabled = false
				gui.Parent = root
				local light = Instance.new("PointLight")
				light.Enabled = true
				light.Parent = root
				local sound = Instance.new("Sound")
				sound.Volume = 0.35
				sound.Parent = root
				local decal = Instance.new("Decal")
				decal.Transparency = 0.2
				decal.Parent = root
				local ok, why = xpcall(function()
					for _, object in { gui, light, sound, decal } do
						Visibility._ApplyHiddenForTesting(object, true)
					end
					Visibility._ApplyHiddenForTesting(gui, false)
					expect(gui.Enabled).to.equal(false) -- Native false is never blanket-restored true.
					Visibility._ApplyHiddenForTesting(gui, true)
					gui.Enabled = true
					light.Enabled = true
					sound.Volume = 0.6
					decal.Transparency = 0.7
					Visibility._EnforceHiddenForTesting()
					expect(gui.Enabled).to.equal(false)
					expect(light.Enabled).to.equal(false)
					expect(sound.Volume).to.equal(0)
					expect(decal.Transparency).to.equal(1)
					for _, object in { gui, light, sound, decal } do
						Visibility._ApplyHiddenForTesting(object, false)
					end
					expect(gui.Enabled).to.equal(true)
					expect(light.Enabled).to.equal(true)
					expect(math.abs(sound.Volume - 0.6) < 0.0001).to.equal(true)
					expect(math.abs(decal.Transparency - 0.7) < 0.0001).to.equal(true)
				end, debug.traceback)
				Visibility.Stop()
				root:Destroy()
				assert(ok, why)
			end
		)
		it("caches static region ownership until a model attribute or ancestry changes", function()
			Visibility.Stop()
			local a = Instance.new("Model")
			a:SetAttribute("RegionId", "REGION_FOREST")
			a.Parent = workspace
			local b = Instance.new("Model")
			b:SetAttribute("RegionId", "REGION_BEACH")
			b.Parent = workspace
			local part = Instance.new("Part")
			part.Parent = a
			local ok, reason = xpcall(function()
				expect(Visibility._CacheRegionForTesting(part)).to.equal("REGION_FOREST")
				local lookups = Visibility.GetDiagnostics().regionLookups
				for _ = 1, 20 do
					expect(Visibility._CacheRegionForTesting(part)).to.equal("REGION_FOREST")
				end
				expect(Visibility.GetDiagnostics().regionLookups).to.equal(lookups)
				a:SetAttribute("RegionId", "REGION_JUNGLE")
				task.wait()
				expect(Visibility._CacheRegionForTesting(part)).to.equal("REGION_JUNGLE")
				part.Parent = b
				expect(Visibility._CacheRegionForTesting(part)).to.equal("REGION_BEACH")
			end, debug.traceback)
			Visibility.Stop()
			a:Destroy()
			b:Destroy()
			assert(ok, reason)
		end)

		it(
			"uses distinct region contexts, rejects duplicate/stale revisions and fails locked regions closed",
			function()
				Visibility.Stop()
				local a = Instance.new("Model")
				a:SetAttribute("RegionId", "REGION_FOREST")
				a.Parent = workspace
				local b = Instance.new("Model")
				b:SetAttribute("RegionId", "REGION_BEACH")
				b.Parent = workspace
				local facade = Instance.new("Model")
				facade:SetAttribute("RegionId", "REGION_CAMP")
				facade:SetAttribute("GlobalNavigationFacade", true)
				facade.Parent = workspace
				local ok, reason = xpcall(function()
					expect(Visibility._AcceptContextForTesting({
						kind = "Context",
						sequence = 1,
						regionId = "REGION_FOREST",
						unlocked = { REGION_FOREST = true, REGION_BEACH = true },
					})).to.equal(true)
					expect(Visibility.IsVisible(a)).to.equal(true)
					expect(Visibility.IsVisible(b)).to.equal(false)
					expect(Visibility.IsVisible(facade)).to.equal(true)
					expect(Visibility._AcceptContextForTesting({
						kind = "Context",
						sequence = 1,
						regionId = "REGION_BEACH",
						unlocked = { REGION_BEACH = true },
					})).to.equal(false)
					expect(Visibility._AcceptContextForTesting({
						kind = "Context",
						sequence = 2,
						regionId = "REGION_BEACH",
						unlocked = { REGION_FOREST = true },
					})).to.equal(true)
					expect(Visibility.IsVisible(a)).to.equal(false)
					expect(Visibility.IsVisible(b)).to.equal(false)
					expect(Visibility._AcceptContextForTesting({
						kind = "Context",
						sequence = 3,
						regionId = "REGION_BEACH",
						unlocked = { REGION_BEACH = true },
					})).to.equal(true)
					expect(Visibility.IsVisible(b)).to.equal(true)
					expect(Visibility.IsVisible(a)).to.equal(false)
				end, debug.traceback)
				Visibility.Stop()
				a:Destroy()
				b:Destroy()
				facade:Destroy()
				assert(ok, reason)
			end
		)
	end)
end
