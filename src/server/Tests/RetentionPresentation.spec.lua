--!strict
return function()
	local View = require(game:GetService("ReplicatedStorage").Shared.Utility.RetentionPresentation)
	describe("Retention confirmed presentation", function()
		it("rejects a late read after a newer committed snapshot", function()
			local current = { revision = 12, retentionRevision = 3, serverTime = 100 }
			expect(
				View.AcceptSnapshot(
					current,
					{ revision = 11, retentionRevision = 9, serverTime = 101 }
				)
			).to.equal(false)
			expect(
				View.AcceptSnapshot(
					current,
					{ revision = 12, retentionRevision = 2, serverTime = 101 }
				)
			).to.equal(false)
			expect(
				View.AcceptSnapshot(
					current,
					{ revision = 12, retentionRevision = 3, serverTime = 99 }
				)
			).to.equal(false)
			expect(
				View.AcceptSnapshot(
					current,
					{ revision = 13, retentionRevision = 3, serverTime = 101 }
				)
			).to.equal(true)
			expect(View.AcceptSnapshot(current, { available = true })).to.equal(false)
		end)

		it("cannot display a paid checkmark from threshold progress alone", function()
			local snapshot = { available = true, status = "Ready" }
			local pending =
				View.Row(snapshot, { count = 3, target = 3, paid = false, state = "InProgress" })
			expect(pending.state).to.equal("Saving")
			expect(pending.paid).to.equal(false)
			local confirmed =
				View.Row(snapshot, { count = 3, target = 3, paid = true, state = "Completed" })
			expect(confirmed.paid).to.equal(true)
			expect(
				View.Row(
					{ available = false },
					{ count = 3, target = 3, paid = true, state = "Completed" }
				).state
			).to.equal("Unavailable")
		end)

		it("counts confirmed rows instead of a client's optimistic summary", function()
			local snapshot = {
				available = true,
				status = "Ready",
				completedCount = 3,
				daily = {
					bring_them_home = { count = 3, target = 3, state = "Completed", paid = true },
					field_research = { count = 2, target = 2, state = "Saving", paid = false },
				},
			}
			expect(View.Completed(snapshot)).to.equal(1)
		end)

		it("shows a pending covering save without treating the service as unavailable", function()
			local snapshot = { available = true, status = "Saving" }
			local row = { count = 3, target = 3, paid = false, state = "Saving" }
			local view = View.Row(snapshot, row)
			expect(view.state).to.equal("Saving")
			expect(view.paid).to.equal(false)
			row.paid, row.state = true, "Completed"
			expect(View.Row(snapshot, row).paid).to.equal(false)
		end)

		it("rejects stale Saving observations after Ready in the same server second", function()
			local ready = {
				revision = 12,
				retentionRevision = 3,
				serverTime = 100,
				snapshotSequence = 5,
				status = "Ready",
			}
			local saving = {
				revision = 12,
				retentionRevision = 3,
				serverTime = 100,
				snapshotSequence = 4,
				status = "Saving",
			}
			expect(View.AcceptSnapshot(ready, saving)).to.equal(false)
			expect(View.AcceptSnapshot(ready, ready)).to.equal(false)
			expect(View.AcceptSnapshot(saving, ready)).to.equal(true)
			expect(
				View.AcceptSnapshot(
					ready,
					{ revision = 12, retentionRevision = 3, serverTime = 101 }
				)
			).to.equal(false)
		end)

		it("uses the last server time plus local elapsed time, with no invented reset", function()
			expect(View.Remaining(86400, 86398, 1)).to.equal("00:00:01")
			expect(View.Remaining(86400, 86398, 5)).to.equal("00:00:00")
			expect(View.Remaining(nil, 86398, 1)).to.equal("--:--:--")
		end)

		it("places the opener below the measured stack and preserves safe edges", function()
			local desktop = View.Layout(1440, 900, 60, false)
			expect(desktop.entryTop).to.equal(68)
			expect(desktop.entryWidth).to.equal(132)
			expect(desktop.panelLeft + desktop.panelWidth).to.equal(1424)
			expect(desktop.panelTop + desktop.panelHeight <= 884).to.equal(true)
			local phone = View.Layout(390, 780, 82, true)
			expect(phone.entryTop).to.equal(90)
			expect(phone.entryWidth).to.equal(112)
			expect(phone.panelLeft >= 12).to.equal(true)
			expect(phone.panelTop + phone.panelHeight <= 780 - phone.reservedBottom - 12).to.equal(
				true
			)
			local short = View.Layout(667, 160, 60, true)
			expect(short.usable).to.equal(false)
		end)

		it("fits a full 44px supply control below the recorded reset band on smallest landscape viewports", function()
			-- Actual native A06/iPhone7 sizes. The clock bottom 40 in Core inset
			-- coordinates is 98 in Retention's DeviceSafe origin(-58), plus 8 gap.
			local coreClockBottom, retentionOriginY = 40, -58
			local safeTop = coreClockBottom - retentionOriginY + 8
			for _, size in { { 705, 338 }, { 666, 374 } } do
				local phone = View.Layout(size[1], size[2], 104, true, safeTop)
				expect(phone.usable).to.equal(true)
				expect(phone.panelTop).to.equal(106)
				expect(phone.reservedBottom).to.equal(16)
				expect(phone.panelHeight - 128 >= 44).to.equal(true)
				expect(phone.panelTop + phone.panelHeight <= size[2] - 28).to.equal(true)
				expect(phone.entryTop).to.equal(112)
			end
			expect(View.Layout(705, 300, 104, true, safeTop).usable).to.equal(false)
			local ready = { available = true, status = "Ready", supplies = { claimable = true } }
			expect(View.OpenTab(ready, "Collection")).to.equal("Supplies")
		end)
	end)
end
