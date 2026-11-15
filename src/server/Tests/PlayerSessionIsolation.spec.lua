--!nocheck

-- Synthetic players and clocks. Only the durable backend is shared between
-- independently required production service instances (no shared session maps).
return function()
	local Players = game:GetService("Players")
	local Source = script.Parent.Parent.Services.PlayerDataService
	local FakeBackend = require(script.Parent.Support.FakePlayerProfileBackend)

	local function player(id)
		local subject =
			{ UserId = id, Name = "SessionIsolationFixture", Parent = Players, Attributes = {} }
		function subject:SetAttribute(name, value)
			self.Attributes[name] = value
		end
		function subject:Kick(message)
			self.Kicked = message
		end
		return subject
	end

	local function run(callback)
		local now, modules, services = 1000, {}, {}
		local backend = FakeBackend.new({
			Now = function()
				return now
			end,
		})
		local function server(name)
			local module = Source:Clone()
			module.Name = "SPEC_ISOLATED_" .. name
			module.Parent = Source.Parent
			table.insert(modules, module)
			local service, sequence = require(module), 0
			service:Init({
				Backend = backend,
				UnixNow = function()
					return now
				end,
				MonotonicNow = function()
					return now
				end,
				Wait = function(seconds)
					now += seconds
					task.wait()
				end,
				Random = function()
					return 0
				end,
				GenerateOperationId = function(prefix)
					sequence += 1
					return name .. ":" .. prefix .. ":" .. sequence
				end,
				KickOnFailure = false,
			})
			table.insert(services, service)
			return service
		end
		local function waitFor(predicate)
			local deadline = os.clock() + 3
			repeat
				task.wait()
			until predicate() or os.clock() >= deadline
			assert(predicate(), "explicit fixture barrier did not complete")
		end
		local ok, failure = xpcall(function()
			callback({
				Backend = backend,
				Server = server,
				Advance = function(seconds)
					now += seconds
				end,
				WaitFor = waitFor,
			})
		end, debug.traceback)
		for _, service in services do
			service:_ResetForTests()
		end
		for _, module in modules do
			module:Destroy()
		end
		assert(ok, failure)
	end

	local function credit(service, subject, amount)
		return service:CommitMutation(subject, function(data)
			data.Economy.Balance += amount
			return true, { ok = true }
		end)
	end

	describe("7F isolated production session owners", function()
		it(
			"publishes a banked release only after a covering real profile acknowledgement",
			function()
				run(function(f)
					local service = f.Server("Release")
					local subject = player(89704)
					expect(service:LoadPlayerAsync(subject).ok).to.equal(true)
					expect(service:CommitMutation(subject, function(data)
						data.Collection.BrainrotInstances.releaseA = { speciesId = "BRT_007" }
						return true, { ok = true }
					end).ok).to.equal(true)
					local bankedModule = script.Parent.Parent.Services.BankedBrainrotService:Clone()
					bankedModule.Parent = Source.Parent
					local banked = require(bankedModule)
					banked:Init({ Profile = service })
					banked:Start()
					local ok, failure = xpcall(function()
						local firstAck, resumeFirst, releaseAck, resumeRelease, saved =
							false, false, false, false, nil
						local publications = 0
						f.Backend.BeforeSaveReturn = function(_, _, revision)
							if revision == 1 then
								firstAck = true
								f.WaitFor(function()
									return resumeFirst
								end)
							elseif revision == 2 then
								releaseAck = true
								f.WaitFor(function()
									return resumeRelease
								end)
							end
						end
						task.spawn(function()
							saved = service:SaveNowAsync(subject, "BeforeRelinquishment")
						end)
						f.WaitFor(function()
							return firstAck
						end)
						local record = { ItemId = "releaseA", BrainrotId = "BRT_007" }
						local function publish()
							publications += 1
							return true
						end
						local released = banked:BeginConfirmedRelease(subject, record, publish)
						expect(released.revision).to.equal(2)
						expect(released.saveRequestCode).to.equal("COALESCED")
						expect(banked:BeginConfirmedRelease(subject, record, publish).code).to.equal(
							"RELEASE_ALREADY_PENDING"
						)
						expect(publications).to.equal(0)
						resumeFirst = true
						f.WaitFor(function()
							return releaseAck
						end)
						expect(service:GetDiagnostics(subject).lastConfirmedSavedRevision).to.equal(
							1
						)
						expect(
							f.Backend:GetRecord("player_89704").Data.Collection.BrainrotInstances.releaseA
						).to.equal(nil)
						expect(publications).to.equal(0)
						-- Durable removal is real, but the first response is lost. The same
						-- operation retry confirms it; no ownership rollback or replay occurs.
						f.Backend.CommitThenFailSaveCount = 1
						resumeRelease = true
						f.WaitFor(function()
							return saved ~= nil
						end)
						expect(saved.ok).to.equal(true)
						expect(publications).to.equal(1)
						banked:ProcessConfirmedReleases()
						expect(publications).to.equal(1)
						expect(banked:IsReleasePending(subject, "releaseA")).to.equal(false)
						expect(
							service:GetReadableData(subject).Collection.BrainrotInstances.releaseA
						).to.equal(nil)
						expect(service:ClosePlayerAsync(subject, "FixtureCleanup").ok).to.equal(
							true
						)
					end, debug.traceback)
					banked:_ResetForTests()
					bankedModule:Destroy()
					assert(ok, failure)
				end)
			end
		)

		it("blocks a reconnect until the delayed final snapshot is released", function()
			run(function(f)
				local a, b = f.Server("A"), f.Server("B")
				local first, second = player(89701), player(89701)
				expect(a:LoadPlayerAsync(first).ok).to.equal(true)
				expect(credit(a, first, 10.75).ok).to.equal(true)
				local original, entered, resume, closed = f.Backend.Release, false, false, nil
				f.Backend.Release = function(self, ...)
					entered = true
					f.WaitFor(function()
						return resume
					end)
					return original(self, ...)
				end
				task.spawn(function()
					closed = a:ClosePlayerAsync(first, "PlayerRemoving")
				end)
				f.WaitFor(function()
					return entered
				end)
				expect(b:LoadPlayerAsync(second).code).to.equal("SESSION_LOCKED")
				expect(b:IsWritable(second)).to.equal(false)
				-- A rejected join leaves through the normal coordinator before the
				-- same server accepts a different Player instance for this key.
				expect(b:ClosePlayerAsync(second, "RejectedJoin").ok).to.equal(true)
				second.Parent = nil
				expect(credit(a, first, 100).ok).to.equal(false)
				resume = true
				f.WaitFor(function()
					return closed ~= nil
				end)
				expect(closed.ok).to.equal(true)
				local returning = player(89701)
				expect(b:LoadPlayerAsync(returning).ok).to.equal(true)
				expect(b:GetReadableData(returning).Economy.Balance).to.equal(10.75)
				expect(a:GetDiagnostics(first)).to.equal(nil)
				expect(b:ClosePlayerAsync(returning, "FixtureCleanup").ok).to.equal(true)
			end)
		end)

		it(
			"rejects an old in-flight write after takeover and after the new owner releases",
			function()
				run(function(f)
					local a, b = f.Server("A"), f.Server("B")
					local first, second = player(89702), player(89702)
					expect(a:LoadPlayerAsync(first).ok).to.equal(true)
					expect(credit(a, first, 10.5).ok).to.equal(true)
					expect(a:SaveNowAsync(first, "ConfirmedBoundary").ok).to.equal(true)
					expect(credit(a, first, 99).ok).to.equal(true)
					local original, arguments, resume, result = f.Backend.Save, nil, false, nil
					f.Backend.Save = function(self, ...)
						if arguments == nil then
							arguments = table.pack(...)
							f.WaitFor(function()
								return resume
							end)
						end
						return original(self, ...)
					end
					task.spawn(function()
						result = a:SaveNowAsync(first, "DelayedOldWrite")
					end)
					f.WaitFor(function()
						return arguments ~= nil
					end)
					f.Advance(181)
					expect(b:LoadPlayerAsync(second).ok).to.equal(true)
					expect(b:GetReadableData(second).Economy.Balance).to.equal(10.5)
					expect(credit(b, second, 3.25).ok).to.equal(true)
					expect(b:SaveNowAsync(second, "NewOwnerWrite").ok).to.equal(true)
					resume = true
					f.WaitFor(function()
						return result ~= nil
					end)
					expect(result.code).to.equal("OWNER_MISMATCH")
					expect(a:IsWritable(first)).to.equal(false)
					expect(a:ClosePlayerAsync(first, "LateCleanup").ok).to.equal(false)
					expect(b:IsWritable(second)).to.equal(true)
					expect(b:ClosePlayerAsync(second, "NewOwnerClose").ok).to.equal(true)
					expect(original(f.Backend, table.unpack(arguments, 1, arguments.n)).code).to.equal(
						"OWNER_MISMATCH"
					)
					local durable = f.Backend:GetRecord("player_89702")
					expect(durable.Data.Economy.Balance).to.equal(13.75)
					expect(durable.OwnerToken).to.equal(nil)
				end)
			end
		)

		it("abandoned late acquisition cannot release the succeeding server's lock", function()
			run(function(f)
				local a, b = f.Server("A"), f.Server("B")
				local first, second = player(89703), player(89703)
				local entered, resume, loaded = false, false, nil
				f.Backend.BeforeAcquireReturn = function()
					if not entered then
						entered = true
						f.WaitFor(function()
							return resume
						end)
					end
				end
				task.spawn(function()
					loaded = a:LoadPlayerAsync(first)
				end)
				f.WaitFor(function()
					return entered
				end)
				expect(a:ClosePlayerAsync(first, "LeftDuringLoad").code).to.equal("LOAD_CANCELLED")
				first.Parent = nil
				f.Advance(181)
				expect(b:LoadPlayerAsync(second).ok).to.equal(true)
				local owner = f.Backend:GetRecord("player_89703").OwnerToken
				resume = true
				f.WaitFor(function()
					return loaded ~= nil
				end)
				expect(loaded.code).to.equal("LOAD_CANCELLED")
				expect(f.Backend:GetRecord("player_89703").OwnerToken).to.equal(owner)
				expect(b:IsWritable(second)).to.equal(true)
				expect(a:GetDiagnostics(first)).to.equal(nil)
				expect(b:ClosePlayerAsync(second, "FixtureCleanup").ok).to.equal(true)
			end)
		end)

		it("does not serialize other profiles behind one delayed shutdown release", function()
			run(function(f)
				local service = f.Server("Shutdown")
				local subjects, finalizers = {}, {}
				service:RegisterCloseFinalizer(function(subject)
					finalizers[subject] = (finalizers[subject] or 0) + 1
				end)
				for index = 1, 12 do
					local subject = player(89800 + index)
					table.insert(subjects, subject)
					expect(service:LoadPlayerAsync(subject).ok).to.equal(true)
					expect(credit(service, subject, index + 0.25).ok).to.equal(true)
				end
				local original, entered, resume, shutdown, duplicateClose =
					f.Backend.Release, false, false, nil, nil
				f.Backend.Release = function(self, key, ...)
					if key == "player_89801" then
						entered = true
						f.WaitFor(function()
							return resume
						end)
					end
					return original(self, key, ...)
				end
				task.spawn(function()
					shutdown = service:ShutdownAsync()
				end)
				f.WaitFor(function()
					return entered
				end)
				task.spawn(function()
					duplicateClose = service:ClosePlayerAsync(subjects[1], "PlayerRemoving")
				end)
				for index = 2, 12 do
					f.WaitFor(function()
						return service:GetDiagnostics(subjects[index]) == nil
					end)
				end
				expect(shutdown).to.equal(nil)
				resume = true
				f.WaitFor(function()
					return shutdown ~= nil and duplicateClose ~= nil
				end)
				expect(shutdown.ok).to.equal(true)
				expect(duplicateClose.ok).to.equal(true)
				for index, subject in subjects do
					expect(finalizers[subject]).to.equal(1)
					local durable = f.Backend:GetRecord("player_" .. subject.UserId)
					expect(durable.Data.Economy.Balance).to.equal(index + 0.25)
					expect(durable.OwnerToken).to.equal(nil)
				end
			end)
		end)
	end)
end
