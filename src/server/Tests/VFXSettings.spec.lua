--!nocheck
return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local Players = game:GetService("Players")
	local Protocol = require(game.ReplicatedStorage.Shared.Utility.VFXSettingsProtocol)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Service = require(script.Parent.Parent.Services.PlayerDataService)
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)
	local nextId = 972000
	local function equal(actual, expected)
		assert(type(actual) == type(expected), "Type changed")
		if type(expected) ~= "table" then
			assert(actual == expected, "Value changed")
			return
		end
		for key, value in expected do
			equal(actual[key], value)
		end
		for key in actual do
			assert(expected[key] ~= nil, "Unexpected field " .. tostring(key))
		end
	end
	local function run(callback, options)
		local now = 1000
		local operation = 0
		local backend = FakeBackend.new(options)
		Service:_ResetForTests()
		Service:Init({
			Backend = backend,
			UnixNow = function()
				return now
			end,
			MonotonicNow = function()
				return now
			end,
			Wait = function(seconds)
				now += seconds
			end,
			Random = function()
				return 0
			end,
			GenerateOperationId = function(prefix)
				operation += 1
				return prefix .. ":vfx-fixture:" .. operation
			end,
			KickOnFailure = false,
		})
		local function player(userId)
			nextId += 1
			local value =
				{ Name = "SyntheticVFXPreferences", UserId = userId or nextId, Parent = Players, Attributes = {} }
			function value:SetAttribute(key, setting)
				self.Attributes[key] = setting
			end
			function value:Kick(message)
				self.Kicked = message
			end
			return value
		end
		local ok, failure = xpcall(function()
			callback({
				Backend = backend,
				Player = player,
				Advance = function(seconds)
					now += seconds
				end,
			})
		end, debug.traceback)
		Service:_ResetForTests()
		assert(ok, failure)
	end
	describe("Persisted cosmetic VFX preferences / isolated profiles", function()
		it("creates independent Auto and reduced-motion defaults", function()
			local a, b = Schema.CreateDefault(), Schema.CreateDefault()
			expect(a.Settings.VFXQuality).to.equal("Auto")
			expect(a.Settings.ReducedMotion).to.equal(false)
			a.Settings.ReducedMotion = true
			expect(b.Settings.ReducedMotion).to.equal(false)
		end)
		it("backfills absent preferences once while preserving every other profile field", function()
			local source = Schema.CreateDefault()
			source.Settings = { Music = false, Volume = 0.375, Input = { AimAssist = true } }
			source.Economy.Balance = 81.375
			source.Base.Slots["2"].accumulatedCash = 6.25
			local before = assert(Schema.CreateSaveSnapshot(source))
			local migrated, reason, changed = Schema.Migrate(source)
			expect(reason).to.equal(nil)
			expect(changed).to.equal(true)
			equal(source, before)
			local expected = assert(Schema.CreateSaveSnapshot(before))
			expected.Settings.VFXQuality, expected.Settings.ReducedMotion = "Auto", false
			equal(migrated, expected)
			local restored, _, changedAgain = Schema.Migrate(migrated)
			expect(changedAgain).to.equal(false)
			equal(restored, expected)
		end)
		it("preserves all four existing valid modes and explicit reduced motion", function()
			for _, selected in { "Auto", "Low", "Medium", "High" } do
				local profile = Schema.CreateDefault()
				profile.Settings = { VFXQuality = selected, ReducedMotion = true, Music = false }
				local migrated, reason, changed = Schema.Migrate(profile)
				expect(reason).to.equal(nil)
				expect(changed).to.equal(false)
				equal(migrated.Settings, profile.Settings)
			end
		end)
		it("normalizes malformed cosmetic values without rejecting gameplay data", function()
			local profile = Schema.CreateDefault()
			profile.Settings = { VFXQuality = "Ultra", ReducedMotion = "yes", Music = false }
			profile.Economy.Balance = 29.125
			local migrated = assert(Schema.Migrate(profile))
			expect(migrated.Settings.VFXQuality).to.equal("Auto")
			expect(migrated.Settings.ReducedMotion).to.equal(false)
			expect(migrated.Settings.Music).to.equal(false)
			expect(migrated.Economy.Balance).to.equal(29.125)
			expect(profile.Settings.VFXQuality).to.equal("Ultra")
		end)
		it("rejects malformed payloads, unknown fields, forged owners and extra arguments", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				for _, payload in
					{
						false,
						1,
						"Set",
						{},
						{ action = "Delete" },
						{ action = "Set" },
						{ action = "Get", VFXQuality = "Low" },
						{ action = "Set", VFXQuality = "Low", UserId = p.UserId },
						{ action = "Set", ReducedMotion = true, Economy = { Balance = 1 } },
					}
				do
					expect(Service:HandleVFXSettingsRequest(p, payload).ok).to.equal(false)
				end
				expect(Service:HandleVFXSettingsRequest(p, { action = "Get" }, "extra").ok).to.equal(false)
				expect(Service:GetDiagnostics(p).currentRevision).to.equal(0)
			end)
		end)
		it("rejects unknown modes and non-boolean reduced motion with no dirty revision", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				for _, value in { "auto", "HIGH", "Medium ", "Ultra", "", 0, false, {} } do
					expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = value }).code).to.equal(
						"INVALID_VFX_QUALITY"
					)
				end
				for _, value in { "true", 0, 1, {} } do
					expect(Service:HandleVFXSettingsRequest(p, { action = "Set", ReducedMotion = value }).code).to.equal(
						"INVALID_REDUCED_MOTION"
					)
				end
				expect(Service:GetDiagnostics(p).dirty).to.equal(false)
			end)
		end)
		it("returns not-ready immediately without acquisition or fabricated defaults", function()
			run(function(f)
				local p = f.Player()
				expect(Service:HandleVFXSettingsRequest(p, { action = "Get" }).code).to.equal("PROFILE_NOT_READY")
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High" }).code).to.equal(
					"PROFILE_NOT_READY"
				)
				expect(#f.Backend.Events).to.equal(0)
				expect(p.Attributes.VFXQuality).to.equal(nil)
			end)
		end)
		it("publishes loaded owner preferences before the ready listener", function()
			run(function(f)
				local p = f.Player()
				local observed = false
				Service:SubscribeReady(function(subject)
					expect(subject.Attributes.VFXQuality).to.equal("Auto")
					expect(subject.Attributes.ReducedMotion).to.equal(false)
					observed = true
				end)
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				expect(observed).to.equal(true)
			end)
		end)
		it("changes only preferences, leaves gameplay fields equal and marks one normal revision", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				local data = assert(Service:GetReadableData(p))
				local before = assert(Schema.CreateSaveSnapshot(data))
				local result =
					Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "Medium", ReducedMotion = true })
				expect(result.ok).to.equal(true)
				expect(result.revision).to.equal(1)
				expect(result.persistence).to.equal("ProfileAutosave")
				expect(result.saved).to.equal(nil)
				before.Settings.VFXQuality, before.Settings.ReducedMotion = "Medium", true
				equal(data, before)
				expect(p.Attributes.VFXQuality).to.equal("Medium")
				expect(p.Attributes.ReducedMotion).to.equal(true)
				expect(#f.Backend.Events).to.equal(1) -- Acquisition only, no extra save owner.
			end)
		end)
		it("treats repeated identical requests as idempotent without extra revisions", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				local payload = { action = "Set", VFXQuality = "Low" }
				expect(Service:HandleVFXSettingsRequest(p, payload).ok).to.equal(true)
				expect(Service:HandleVFXSettingsRequest(p, payload).code).to.equal("Unchanged")
				expect(Service:GetDiagnostics(p).currentRevision).to.equal(1)
			end)
		end)
		it("bounds changed requests and allows the next accepted selection after cooldown", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "Low" }).ok).to.equal(true)
				local limited = Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High" })
				expect(limited.code).to.equal("RATE_LIMITED")
				expect(limited.retryAfterSeconds > 0).to.equal(true)
				expect(p.Attributes.VFXQuality).to.equal("Low")
				f.Advance(0.21)
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High" }).ok).to.equal(true)
				expect(p.Attributes.VFXQuality).to.equal("High")
			end)
		end)
		it("preserves the other preference when applying a partial patch", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", ReducedMotion = true }).ok).to.equal(true)
				f.Advance(1)
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High" }).ok).to.equal(true)
				local result = Service:HandleVFXSettingsRequest(p, { action = "Get" })
				expect(result.VFXQuality).to.equal("High")
				expect(result.ReducedMotion).to.equal(true)
			end)
		end)
		it("saves, closes and restores preferences with the existing fake profile backend", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				expect(
					Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High", ReducedMotion = true }).ok
				).to.equal(true)
				expect(Service:SaveNowAsync(p, "SyntheticVFXPreferences").ok).to.equal(true)
				expect(Service:ClosePlayerAsync(p, "SyntheticVFXPreferences").ok).to.equal(true)
				p.Parent = nil
				local fresh = f.Player(p.UserId)
				expect(Service:LoadPlayerAsync(fresh).ok).to.equal(true)
				local result = Service:HandleVFXSettingsRequest(fresh, { action = "Get" })
				expect(result.VFXQuality).to.equal("High")
				expect(result.ReducedMotion).to.equal(true)
				expect(fresh.Attributes.ReducedMotion).to.equal(true)
			end)
		end)
		it("rejects stale or disconnected players and cannot alter another owner", function()
			run(function(f)
				local a, b = f.Player(), f.Player()
				expect(Service:LoadPlayerAsync(a).ok and Service:LoadPlayerAsync(b).ok).to.equal(true)
				a.Parent = nil
				expect(Service:HandleVFXSettingsRequest(a, { action = "Set", VFXQuality = "High" }).code).to.equal(
					"PLAYER_NOT_CONNECTED"
				)
				expect(Service:HandleVFXSettingsRequest(b, { action = "Get" }).VFXQuality).to.equal("Auto")
			end)
		end)
		it("declines writes to historical non-table settings without resetting it or failing load", function()
			run(function(f)
				local p = f.Player()
				local raw = Schema.CreateDefault()
				raw.Settings = "preserved unknown historical extension"
				-- The surrounding Studio runner may configure an isolated profile-key
				-- namespace. Seed only this fake response, never assume a live key.
				f.Backend.BeforeAcquireReturn = function(_, _, response)
					response.data.Settings = raw.Settings
				end
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				expect(p.Attributes.VFXQuality).to.equal("Auto")
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", VFXQuality = "High" }).code).to.equal(
					"PREFERENCES_UNAVAILABLE"
				)
				expect(Service:GetReadableData(p).Settings).to.equal(raw.Settings)
			end)
		end)
		it("declines changes after the lease safety deadline without creating a save", function()
			run(function(f)
				local p = f.Player()
				expect(Service:LoadPlayerAsync(p).ok).to.equal(true)
				f.Advance(166)
				expect(Service:HandleVFXSettingsRequest(p, { action = "Set", ReducedMotion = true }).code).to.equal(
					"SESSION_OWNERSHIP_UNSAFE"
				)
				expect(#f.Backend.Events).to.equal(1)
			end)
		end)
		it("validates the pure protocol without accepting client metatables", function()
			local request = Protocol.ValidateRequest(setmetatable({ action = "Get" }, {}))
			expect(request).to.equal(nil)
			local a, b = Protocol.Read(nil), Protocol.Read(nil)
			a.ReducedMotion = true
			expect(b.ReducedMotion).to.equal(false)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
