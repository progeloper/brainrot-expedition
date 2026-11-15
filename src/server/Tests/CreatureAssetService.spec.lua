--!nocheck
-- Native authority-proxy geometry tests; no connected/client performance claim.
return function()
	local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
	local Collection = game:GetService("CollectionService")
	local Assets = require(script.Parent.Parent.Utility.CreatureAssetService)
	local Scale = require(RS.Shared.Utility.BrainrotVisualScale)
	local function near(a, b)
		return (a - b).Magnitude < 0.0001
	end
	local function fixture(callback)
		local oldAssets, oldPrivate = RS:FindFirstChild("StudioAssets"), SS:FindFirstChild("Phase13CreatureAssets")
		local oldLegacy = workspace:GetAttribute("Phase13LegacyCreatureReplication")
		if oldAssets then
			oldAssets.Parent = nil
		end
		if oldPrivate then
			oldPrivate.Parent = nil
		end
		workspace:SetAttribute("Phase13LegacyCreatureReplication", nil)
		local assets = Instance.new("Folder")
		assets.Name, assets.Parent = "StudioAssets", RS
		local brainrots = Instance.new("Folder")
		brainrots.Name, brainrots.Parent = "Brainrots", assets
		local formation = Instance.new("Folder")
		formation.Name, formation.Parent = "ChariotFormation", assets
		local source = Instance.new("Model")
		source.Name, source.Parent = "SPEC_PROXY_GEOMETRY", brainrots
		local root = Instance.new("Part")
		root.Name, root.Size, root.Transparency = "Root", Vector3.new(0.5, 0.5, 0.5), 1
		root.Anchored, root.CanCollide, root.CanQuery, root.CFrame, root.Parent =
			true, false, false, CFrame.new(0, 0, 0), source
		source.PrimaryPart = root
		local body = Instance.new("WedgePart")
		body.Name, body.Size = "Body", Vector3.new(2, 4, 3)
		body.Anchored, body.CFrame, body.Parent = true, CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.2, 0), source
		for _, name in { "CaptureAttachment", "CargoAttachment" } do
			local attachment = Instance.new("Attachment")
			attachment.Name, attachment.Parent = name, body
			attachment.CFrame =
				body.CFrame:ToObjectSpace(if name == "CargoAttachment" then CFrame.new() else CFrame.new(0, 3, 0.1))
		end
		local art = Instance.new("Part")
		art.Name, art.Size, art.CFrame = "AcceptedArt", Vector3.new(7, 2, 2), CFrame.new(1, 4, -1)
		art.Anchored, art.CanQuery, art.Parent = true, false, source
		Collection:AddTag(source, "AcceptedTemplateTag")
		Collection:AddTag(body, "AcceptedPartTag")
		source:ScaleTo(2.25)
		local lodSpecies = Instance.new("Folder")
		lodSpecies.Name, lodSpecies.Parent = source.Name, formation
		local lod = source:Clone()
		lod.Name, lod.Parent = "Detailed", lodSpecies
		local ok, why = xpcall(function()
			callback(source, body, art, assets, brainrots, formation, lod)
		end, debug.traceback)
		local private = SS:FindFirstChild("Phase13CreatureAssets")
		if private then
			private:Destroy()
		end
		assets:Destroy()
		if oldAssets then
			oldAssets.Parent = RS
		end
		if oldPrivate then
			oldPrivate.Parent = SS
		end
		workspace:SetAttribute("Phase13LegacyCreatureReplication", oldLegacy)
		assert(ok, why)
	end
	describe("Private canonical art and authority proxies", function()
		it(
			"moves exact canonical folders once, preserves art and rejects conflicting replicated copies atomically",
			function()
				fixture(function(source, body, art, assets, brainrots, formation, lod)
					local bodyFrame, artFrame, count = body.CFrame, art.CFrame, #source:GetDescendants()
					expect(Assets.Prepare()).to.equal(true)
					expect(brainrots.Parent).to.equal(SS.Phase13CreatureAssets)
					expect(formation.Parent).to.equal(SS.Phase13CreatureAssets)
					expect(Assets.GetTemplate(source.Name, "Full")).to.equal(source)
					expect(Assets.GetTemplate(source.Name, "Detailed")).to.equal(lod)
					expect(Assets.Prepare()).to.equal(true)
					expect(source:GetDescendants()[1] ~= nil).to.equal(true)
					expect(#source:GetDescendants()).to.equal(count)
					expect(body.CFrame).to.equal(bodyFrame)
					expect(art.CFrame).to.equal(artFrame)
					expect(Collection:HasTag(source, "AcceptedTemplateTag")).to.equal(true)
					local conflict = Instance.new("Folder")
					conflict.Name, conflict.Parent = "Brainrots", assets
					local ok, reason = Assets.Prepare()
					expect(ok).to.equal(false)
					expect(reason).to.equal("ASSET_FOLDER_CONFLICT_Brainrots")
					expect(conflict.Parent).to.equal(assets)
					expect(brainrots.Parent).to.equal(SS.Phase13CreatureAssets)
				end)
			end
		)
		it(
			"retains native Body shape, attachment frames, native scale, visual/hunt/full bounds without replicating art",
			function()
				fixture(function(source, body, art)
					assert(Assets.Prepare(), "Fixture private assets must prepare")
					local originalScale, originalPivot = source:GetScale(), source:GetPivot()
					local visualFrame, visualSize = Scale.GetVisualBounds(source)
					local fullFrame, fullSize = source:GetBoundingBox()
					local proxy, reason = Assets.CreateProxy(source.Name)
					assert(proxy, reason)
					expect(proxy:GetAttribute("CreatureProxy")).to.equal(true)
					expect(proxy:GetScale()).to.equal(originalScale)
					expect(proxy:GetPivot()).to.equal(originalPivot)
					expect(proxy:FindFirstChild("AcceptedArt", true)).to.equal(nil)
					local cloneBody = proxy:FindFirstChild("Body", true)
					expect(cloneBody.ClassName).to.equal(body.ClassName)
					expect(cloneBody.Size).to.equal(body.Size)
					expect(cloneBody.CFrame).to.equal(body.CFrame)
					expect(cloneBody.CaptureAttachment.CFrame).to.equal(body.CaptureAttachment.CFrame)
					expect(cloneBody.CargoAttachment.CFrame).to.equal(body.CargoAttachment.CFrame)
					expect(cloneBody.CanQuery).to.equal(true)
					expect(cloneBody.Transparency).to.equal(1)
					local measuredFrame, measuredSize = Scale.GetVisualBounds(proxy)
					expect(near(measuredFrame.Position, visualFrame.Position)).to.equal(true)
					expect(near(measuredSize, visualSize)).to.equal(true)
					local proxyFullFrame, proxyFullSize = proxy:GetBoundingBox()
					expect(near(proxyFullFrame.Position, fullFrame.Position)).to.equal(true)
					expect(near(proxyFullSize, fullSize)).to.equal(true)
					local parts = 0
					for _, item in proxy:GetDescendants() do
						expect(#Collection:GetTags(item)).to.equal(0)
						if item:IsA("BasePart") then
							parts += 1
						end
					end
					expect(parts).to.equal(3)
					expect(#Collection:GetTags(proxy)).to.equal(0)
					proxy:ScaleTo(originalScale * 1.6)
					local scaledFrame, scaledSize = Scale.GetVisualBounds(proxy)
					expect(near(scaledSize, visualSize * 1.6)).to.equal(true)
					expect(near(scaledFrame.Position, visualFrame.Position * 1.6)).to.equal(true)
					expect(Scale.ApplyCanonicalScale(proxy, "ProxyFixture")).to.equal(true)
					expect(Scale.ApplyCanonicalScale(proxy, "ProxyFixtureAgain")).to.equal(true)
					expect(math.abs(Scale.GetVisualHeight(proxy) - Scale.TARGET_HEIGHT_STUDS) < 0.001).to.equal(true)
					expect(source:GetScale()).to.equal(originalScale)
					expect(art.Parent).to.equal(source)
					proxy:Destroy()
				end)
			end
		)
		it("creates current body/cargo proxies with absent or malformed obsolete markers", function()
			fixture(function(source, body)
				body.CaptureAttachment:Destroy()
				assert(Assets.Prepare())
				for _, malformed in { false, true } do
					local marker
					if malformed then
						marker = Instance.new("Folder")
						marker.Name, marker.Parent = "CaptureAttachment", body
					end
					local scale, pivot, bodyFrame = source:GetScale(), source:GetPivot(), body.CFrame
					local proxy, reason = Assets.CreateProxy(source.Name)
					assert(proxy, reason)
					expect(proxy:FindFirstChild("Body", true).CanQuery).to.equal(true)
					expect(proxy:FindFirstChild("CargoAttachment", true) ~= nil).to.equal(true)
					expect(proxy:FindFirstChild("CaptureAttachment", true)).to.equal(nil)
					expect(source:GetScale()).to.equal(scale)
					expect(source:GetPivot()).to.equal(pivot)
					expect(body.CFrame).to.equal(bodyFrame)
					if marker then
						expect(marker.Parent).to.equal(body)
					end
					proxy:Destroy()
				end
			end)
		end)
		it("keeps explicit Studio legacy comparison full and rejects missing assets", function()
			fixture(function(source, _, art, assets, brainrots)
				workspace:SetAttribute("Phase13LegacyCreatureReplication", true)
				expect(Assets.IsEnabled()).to.equal(false)
				expect(Assets.Prepare()).to.equal(true)
				expect(brainrots.Parent).to.equal(assets)
				local legacy = Assets.CreateProxy(source.Name)
				assert(legacy, "Legacy fixture must clone")
				expect(legacy:FindFirstChild(art.Name, true) ~= nil).to.equal(true)
				expect(legacy:GetAttribute("CreatureProxy")).to.equal(nil)
				expect(Assets.CreateProxy("SPEC_MISSING_PROXY")).to.equal(nil)
				legacy:Destroy()
			end)
		end)
	end)
end
