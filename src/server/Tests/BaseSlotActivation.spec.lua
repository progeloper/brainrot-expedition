--!nocheck
-- Native Instance fixtures. These results do not certify network ordering or real clients.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config.Phase13)
	local Presentation = require(RS.Shared.Utility.BaseSlotPresentation)
	local Geometry = require(script.Parent.Parent.Utility.Phase13BaseGeometry)
	local Storage = require(script.Parent.Parent.Classes.BaseStorage)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local capacities = { 12, 18, 24, 30, 36, 42, 48 }
	local function fixture(callback)
		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "BaseActivationSpec")
		base:SetAttribute("OwnerUserId", 8101)
		base:SetAttribute("BaseOwnershipRevision", 1)
		local foundation = Instance.new("Part")
		foundation.Name, foundation.Size, foundation.Anchored = "Foundation", Vector3.new(46.66, 1, 79.4625), true
		foundation.Parent = base
		for index = 1, 12 do
			local slot = Instance.new("Part")
			slot.Name, slot.Size, slot.Anchored = string.format("Slot_%02d", index), Vector3.new(10.16, 0.75, 13.92), true
			slot.CFrame = CFrame.new(if index <= 6 then -12.77 else 12.77, 1, -28 + ((index - 1) % 6) * 12.18)
			slot.Parent = base
			local marker = Instance.new("Attachment")
			marker.Name, marker.Parent = "BrainrotPlacement", slot
		end
		Geometry.Build(base)
		local slots = {}
		for index = 1, 48 do
			local slot = base:FindFirstChild(string.format("Slot_%02d", index))
			slots[index] = { Index = index, Platform = slot, Marker = slot.BrainrotPlacement }
			local decor = Instance.new("Part")
			decor.Name, decor.Transparency, decor.CanCollide, decor.CanTouch, decor.CanQuery = "TranslucentDecor", 0.35, false, false, false
			decor.Parent = slot
			local hidden = Instance.new("Part")
			hidden.Name, hidden.Transparency, hidden.CanCollide, hidden.CanTouch, hidden.CanQuery = "InvisibleMarker", 1, false, false, false
			hidden.Parent = slot
			local decal = Instance.new("Decal")
			decal.Transparency, decal.Parent = 0.25, decor
			local gui = Instance.new("SurfaceGui")
			gui.Enabled, gui.Parent = true, decor
			local selection = Instance.new("SelectionBox")
			selection.Visible, selection.Parent = true, slot
			local highlight = Instance.new("Highlight")
			highlight.Enabled, highlight.Parent = false, slot
			for _, class in { "ParticleEmitter", "Beam", "Trail", "PointLight", "ProximityPrompt" } do
				local item = Instance.new(class)
				item.Enabled, item.Parent = true, decor
			end
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance, click.Parent = 14, decor
			Presentation.CaptureGroup(slot)
		end
		local context = { OwnerUserId = 8101, AssignmentRevision = 1, ProfileReady = true }
		local ok, why = xpcall(function() callback(base, slots, context) end, debug.traceback)
		base:Destroy()
		assert(ok, why)
	end
	local function assertGroup(root, active)
		expect(Presentation.IsActive(root)).to.equal(active)
		local items = { root }
		for _, item in root:GetDescendants() do table.insert(items, item) end
		for _, item in items do
			if item:IsA("BasePart") then
				for _, property in { "Transparency", "CanCollide", "CanTouch", "CanQuery" } do
					local expected = if active then Presentation.GetAuthoredProperty(item, property) elseif property == "Transparency" then 1 else false
					expect(item[property]).to.equal(expected)
				end
			elseif item:IsA("GuiBase3d") then
				expect(item.Visible).to.equal(active)
			elseif item:IsA("Decal") then
				expect(item.Transparency).to.equal(if active then 0.25 else 1)
			elseif item:IsA("LayerCollector") or item:IsA("Highlight") or item:IsA("ParticleEmitter")
				or item:IsA("Beam") or item:IsA("Trail") or item:IsA("Light") or item:IsA("ProximityPrompt") then
				expect(item.Enabled).to.equal(active and Presentation.GetAuthoredProperty(item, "Enabled"))
			elseif item:IsA("ClickDetector") then expect(item.MaxActivationDistance).to.equal(if active then 14 else 0) end
		end
	end
	describe("B01 exact owner capacity across all eight native designs", function()
		for _, design in Config.DesignRows do
			for _, capacity in capacities do
				it(design.id .. " capacity " .. capacity, function()
					fixture(function(base, slots, context)
						assert(Geometry.Apply(base, capacity, design.id, false, context))
						local count = 0
						for index, slot in slots do
							assertGroup(slot.Platform, index <= capacity)
							expect(slot.Marker.Parent).to.equal(slot.Platform)
							if Presentation.IsActive(slot.Platform) then count += 1 end
						end
						expect(count).to.equal(capacity)
						for _, part in base.Phase13Architecture:GetDescendants() do
							if part:IsA("BasePart") then
								local active = part:GetAttribute("Phase13Floor") <= Presentation.StageByCapacity[capacity]
								expect(Presentation.IsActive(part)).to.equal(active)
								if part:GetAttribute("Phase13Role") == "StairRamp" then
									expect(part.Transparency).to.equal(1)
									expect(part.CanCollide).to.equal(active)
								elseif part:GetAttribute("Phase13Role") == "Tread" then expect(part.CanCollide).to.equal(false) end
							end
						end
						expect(base.Foundation.CanCollide).to.equal(true)
					end)
				end)
			end
		end
	end)
	describe("B02–B06 readiness, revisions, restoration and inventory boundaries", function()
		it("reveals exactly six slots after committed expansion and rejects a forged48 before publication", function()
			fixture(function(base, slots, context)
				assert(Geometry.Apply(base, 12, "BDS_001", false, context))
				local committed = base:GetAttribute("BasePresentationState")
				expect(Presentation.CanUseSlot(base, 48, 8101, 1)).to.equal(false)
				expect(Presentation.CanUseSlot(base, 13, 8101, 1)).to.equal(false)
				-- A cancelled/failed operation has no presentation call or publication.
				expect(base:GetAttribute("BasePresentationState")).to.equal(committed)
				assert(Geometry.Apply(base, 18, "BDS_001", false, context))
				for index = 13, 48 do expect(Presentation.IsActive(slots[index].Platform)).to.equal(index <= 18) end
				expect(Presentation.CanUseSlot(base, 18, 8101, 1)).to.equal(true)
				expect(Presentation.CanUseSlot(base, 19, 8101, 1)).to.equal(false)
			end)
		end)
		it("fails closed on reassignment, missing profile and stale callbacks without changing anchors", function()
			fixture(function(base, slots, context)
				assert(Geometry.Apply(base, 48, "BDS_008", false, context))
				local anchor = slots[48].Marker
				-- Simulate the owner attribute arriving before the invalidation token.
				base:SetAttribute("OwnerUserId", 8102)
				expect(Presentation.IsActive(slots[48].Platform)).to.equal(false)
				Presentation.Invalidate(base, 8102, 2)
				base:SetAttribute("OwnerUserId", 8102)
				base:SetAttribute("BaseOwnershipRevision", 2)
				for _, slot in slots do assertGroup(slot.Platform, false) end
				expect(Geometry.Apply(base, 48, "BDS_008", false, context)).to.equal(false)
				expect(Geometry.Apply(base, 48, "BDS_008", false, {OwnerUserId=8102,AssignmentRevision=2,ProfileReady=false})).to.equal(false)
				context = {OwnerUserId=8102,AssignmentRevision=2,ProfileReady=true}
				assert(Geometry.Apply(base, 12, "BDS_001", false, context))
				expect(Presentation.CanUseSlot(base, 1, 8101, 1)).to.equal(false)
				expect(Presentation.CanUseSlot(base, 1, 8102, 2)).to.equal(true)
				expect(slots[48].Marker).to.equal(anchor)
				assertGroup(slots[48].Platform, false)
			end)
		end)
		it("restores stable authored defaults through20 re-entry clones and a deferred atomic snapshot", function()
			fixture(function(base, slots, context)
				for _ = 1, 20 do
					assert(Geometry.Apply(base, 12, "BDS_002", false, context))
					local rebound = base:Clone()
					local pad = rebound.Slot_13
					expect(math.abs(Presentation.GetAuthoredProperty(pad.TranslucentDecor, "Transparency") - 0.35) < 1e-6).to.equal(true)
					expect(Presentation.IsActive(pad)).to.equal(false)
					assert(Geometry.Apply(rebound, 18, "BDS_002", false, context))
					assertGroup(pad, true)
					expect(pad.InvisibleMarker.Transparency).to.equal(1)
					expect(pad.TranslucentDecor.CanCollide).to.equal(false)
					rebound:Destroy()
				end
				local old = base:GetAttribute("BasePresentationState")
				local token = assert(Presentation.Begin(base, 18, context))
				Presentation.BindSlot(slots[13].Platform, base, 13, token)
				expect(Presentation.IsActive(slots[13].Platform)).to.equal(false)
				Presentation.Publish(base, token, 18)
				expect(Presentation.IsActive(slots[13].Platform)).to.equal(true)
				slots[13].Platform:SetAttribute("BaseSlotState", old)
				expect(Presentation.IsActive(slots[13].Platform)).to.equal(false)
			end)
		end)
		it("preserves a legacy locked individual and its exact platform earnings without binding or payout", function()
			fixture(function(base, slots, context)
				local data = Schema.CreateDefault()
				local saved = {speciesId="BRT_001",metadata={}}
				local record = {brainrotId="legacy_locked",accumulatedCash=123.375}
				data.Collection.BrainrotInstances.legacy_locked = saved
				data.Base.Slots["48"] = record
				local storage = Storage.new(base, 8101, slots, data)
				assert(Geometry.Apply(base, 12, "BDS_001", false, context))
				expect(storage:BindRestoredRecord(48, {ItemId="legacy_locked",BrainrotId="BRT_001",Metadata={}}, nil)).to.equal(false)
				expect(storage:GetPlatformRecord(48)).to.equal(nil)
				expect(#storage:GetPlatformIds()).to.equal(12)
				expect(data.Base.Slots["48"]).to.equal(record)
				expect(record.brainrotId).to.equal("legacy_locked")
				expect(record.accumulatedCash).to.equal(123.375)
				expect(data.Collection.BrainrotInstances.legacy_locked).to.equal(saved)
				storage:Destroy()
			end)
		end)
	end)
end
