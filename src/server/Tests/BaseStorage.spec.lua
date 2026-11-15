--!nocheck

return function()
	local BaseStorage = require(script.Parent.Parent.Classes.BaseStorage)
	local function fixture(count, savedData)
		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "SPEC_BASE")
		local slots = {}
		for index = 1, count do
			local platform = Instance.new("Part")
			platform.Parent = base
			local marker = Instance.new("Attachment")
			marker.Parent = platform
			slots[index] = { Index = index, Platform = platform, Marker = marker }
		end
		return BaseStorage.new(base, 1, slots, savedData), base
	end
	local function item(id)
		return {
			ItemId = id,
			BrainrotId = "SPEC_SPECIES",
			Metadata = { Rarity = "Authored", Mutation = { Name = "Original", Quality = 3 } },
		}
	end
	describe("Phase 5C-1 BaseStorage", function()
		it(
			"reserves exactly the requested platform and never falls back from occupied or reserved slots",
			function()
				local s, base = fixture(3)
				local token = assert(s:TryReserveSlot("A", 3))
				expect(s:GetReservedSlot(token, "A").Index).to.equal(3)
				expect(select(2, s:TryReserveSlot("B", 3))).to.equal("BUSY")
				assert(s:CommitReservation(token, item("A"), Instance.new("Model")))
				expect(select(2, s:TryReserveSlot("B", 3))).to.equal("OCCUPIED")
				expect(select(2, s:TryReserveSlot("B", 4))).to.equal("INVALID_PLATFORM")
				expect(s:GetPlatformRecord(1)).to.equal(nil)
				local snapshot = s:GetPlatformRecord(3)
				snapshot.Metadata.Mutation.Name = "Changed"
				expect(s:GetPlatformRecord(3).Metadata.Mutation.Name).to.equal("Original")
				s:Destroy()
				base:Destroy()
			end
		)
		it(
			"reserves lowest slot without committing counts/revision and distinguishes BUSY",
			function()
				local s, base = fixture(2)
				local a = s:TryReserveSlot("A")
				local b = s:TryReserveSlot("B")
				expect(s:GetReservedSlot(a, "A").Index).to.equal(1)
				expect(s:GetReservedSlot(b, "B").Index).to.equal(2)
				expect(s:GetOccupiedCount()).to.equal(0)
				expect(s:GetRevision()).to.equal(0)
				local _, reason = s:TryReserveSlot("C")
				expect(reason).to.equal("BUSY")
				s:CancelReservation(a)
				s:CancelReservation(a)
				expect(s:GetAvailableSlotCount()).to.equal(1)
				s:Destroy()
				base:Destroy()
			end
		)
		it("commits once; cancellation cannot remove committed content", function()
			local s, base = fixture(1)
			local token = s:TryReserveSlot("A")
			local display = Instance.new("Model")
			expect(s:CommitReservation(token, item("A"), display)).to.equal(true)
			expect(s:CommitReservation(token, item("A"), display)).to.equal(false)
			s:CancelReservation(token)
			expect(s:GetOccupiedCount()).to.equal(1)
			expect(s:GetRevision()).to.equal(1)
			local _, full = s:TryReserveSlot("B")
			expect(full).to.equal("NO_SPACE")
			local _, duplicate = s:TryReserveSlot("A")
			expect(duplicate).to.equal("ALREADY_STORED")
			s:Destroy()
			base:Destroy()
		end)
		it("rejects foreign tokens and wrong-item commits", function()
			local a, ab = fixture(1)
			local b, bb = fixture(1)
			local ta = a:TryReserveSlot("A")
			local tb = b:TryReserveSlot("A")
			local display = Instance.new("Model")
			expect(a:CommitReservation(tb, item("A"), display)).to.equal(false)
			expect(a:CommitReservation(ta, item("B"), display)).to.equal(false)
			expect(a:GetAvailableSlotCount()).to.equal(0)
			a:Destroy()
			b:Destroy()
			display:Destroy()
			ab:Destroy()
			bb:Destroy()
		end)
		it("returns deep metadata copies in slot order without Instances/container data", function()
			local s, base = fixture(2)
			local a = s:TryReserveSlot("A")
			local b = s:TryReserveSlot("B")
			local data = item("A")
			data.AttachmentIndex = 3
			data.Visual = base
			data.Metadata.Bad = base
			s:CommitReservation(b, item("B"), Instance.new("Model"))
			s:CommitReservation(a, data, Instance.new("Model"))
			data.Metadata.Mutation.Name = "Changed"
			local snap = s:GetSnapshot()
			expect(snap[1].ItemId).to.equal("A")
			expect(snap[1].SlotIndex).to.equal(1)
			expect(snap[1].Metadata.Mutation.Name).to.equal("Original")
			expect(snap[1].AttachmentIndex).to.equal(nil)
			expect(snap[1].Metadata.Bad).to.equal(nil)
			snap[1].Metadata.Mutation.Name = "Changed again"
			expect(s:GetSnapshot()[1].Metadata.Mutation.Name).to.equal("Original")
			s:Destroy()
			base:Destroy()
		end)
		it("destroy invalidates reservations and destroys only owned displays", function()
			local s, base = fixture(2)
			local display = Instance.new("Model")
			display.Parent = base
			s:CommitReservation(s:TryReserveSlot("A"), item("A"), display)
			local pending = s:TryReserveSlot("B")
			s:Destroy()
			s:Destroy()
			expect(display.Parent).to.equal(nil)
			expect(#base:GetChildren()).to.equal(2)
			expect(s:IsActive()).to.equal(false)
			expect(s:GetAvailableSlotCount()).to.equal(0)
			expect(s:GetReservedSlot(pending, "B")).to.equal(nil)
			base:Destroy()
		end)
		it("keeps a finite exact income ledger on each stable platform", function()
			local s, base = fixture(2, {
				PlatformIncome = {
					["1"] = { UnclaimedCashExact = 4.75 },
					["2"] = { UnclaimedCashExact = -10 },
				},
			})
			expect(s:GetUnclaimedCashExact(1)).to.equal(4.75)
			expect(s:GetUnclaimedCashExact(2)).to.equal(0)
			expect(s:AddUnclaimedCashExact(1, 0.5)).to.equal(true)
			expect(s:GetPersistentData().PlatformIncome["1"].UnclaimedCashExact).to.equal(5.25)
			expect(s:SetUnclaimedCashExact(1, 0 / 0)).to.equal(false)
			expect(s:GetUnclaimedCashExact(1)).to.equal(5.25)
			s:Destroy()
			base:Destroy()
		end)
		it("serializes mutations per platform without blocking other platforms", function()
			local s, base = fixture(2)
			local first = assert(s:TryBeginPlatformMutation(1))
			expect(select(2, s:TryBeginPlatformMutation(1))).to.equal("BUSY")
			local second = assert(s:TryBeginPlatformMutation(2))
			expect(s:EndPlatformMutation(1, second)).to.equal(false)
			expect(s:EndPlatformMutation(1, first)).to.equal(true)
			expect(s:EndPlatformMutation(2, second)).to.equal(true)
			expect(s:TryBeginPlatformMutation(1) ~= nil).to.equal(true)
			s:Destroy()
			base:Destroy()
		end)
		it("removes only the exact occupant and retains the platform's uncollected cash", function()
			local s, base = fixture(2)
			local display = Instance.new("Model")
			assert(s:CommitReservation(s:TryReserveSlot("A", 2), item("A"), display))
			assert(s:SetUnclaimedCashExact(2, 80))
			expect(select(3, s:RemovePlatformRecord(2, "wrong"))).to.equal("STALE_ID")
			expect(s:GetPlatformRecord(2).ItemId).to.equal("A")
			expect(s:GetUnclaimedCashExact(2)).to.equal(80)
			local removed, ownedDisplay = s:RemovePlatformRecord(2, "A")
			expect(removed.ItemId).to.equal("A")
			expect(ownedDisplay).to.equal(display)
			expect(s:GetPlatformRecord(2)).to.equal(nil)
			expect(s:GetUnclaimedCashExact(2)).to.equal(80)
			expect(s:GetOccupiedCount()).to.equal(0)
			expect(s:GetRevision()).to.equal(2)
			display:Destroy()
			s:Destroy()
			base:Destroy()
		end)
		it("restores persisted ledgers once before live accrual", function()
			local s, base = fixture(2)
			expect(s:RestorePersistentData({
				PlatformIncome = { ["2"] = { UnclaimedCashExact = 3.5 } },
			})).to.equal(true)
			expect(s:GetUnclaimedCashExact(2)).to.equal(3.5)
			expect(s:AddUnclaimedCashExact(2, 1)).to.equal(true)
			expect(s:RestorePersistentData({
				PlatformIncome = { ["2"] = { UnclaimedCashExact = 99 } },
			})).to.equal(true)
			expect(s:GetUnclaimedCashExact(2)).to.equal(4.5)
			s:Destroy()
			base:Destroy()
		end)
	end)
end
