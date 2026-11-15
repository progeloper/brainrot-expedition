--!nocheck

return function()
	local CollectionService = game:GetService("CollectionService")
	local PointSystem = require(script.Parent.Parent.Systems.CartUpgradePointSystem)

	local function managedPrompts(stall)
		local result = {}
		for _, child in stall:GetChildren() do
			if
				child:IsA("ProximityPrompt")
				and child.Name == "CartUpgradePrompt"
				and child:GetAttribute("ManagedBy") == "CartUpgradePointSystem"
			then
				table.insert(result, child)
			end
		end
		return result
	end

	-- The shipped map now authors its one tagged stall. Each case needs a world
	-- with no other tagged stall, so the authored tag is lifted for the case and
	-- always restored.
	local function withoutAuthoredStalls(callback)
		PointSystem:Stop()
		local authored = CollectionService:GetTagged("CartUpgradeStall")
		for _, instance in authored do
			CollectionService:RemoveTag(instance, "CartUpgradeStall")
		end
		local ok, why = xpcall(callback, debug.traceback)
		PointSystem:Stop()
		for _, instance in authored do
			CollectionService:AddTag(instance, "CartUpgradeStall")
		end
		if not ok then
			error(why, 0)
		end
	end

	describe("Phase 7B-2 authored cart-upgrade point", function()
		it("does not repurpose an untagged map part", function()
			withoutAuthoredStalls(function()
			PointSystem:Stop()
			local untagged = Instance.new("Part")
			untagged.Name = "LooksLikeAnUpgradeStall"
			untagged.Parent = workspace
			expect(PointSystem:EnsurePoint()).to.equal(false)
			expect(#managedPrompts(untagged)).to.equal(0)
			untagged:Destroy()
			end)
		end)

		it("updates one managed prompt on exactly one explicitly tagged existing stall", function()
			withoutAuthoredStalls(function()
			PointSystem:Stop()
			local stall = Instance.new("Part")
			stall.Name = "AuthoredUpgradeStall"
			stall.Parent = workspace
			CollectionService:AddTag(stall, "CartUpgradeStall")
			expect(PointSystem:EnsurePoint()).to.equal(true)
			expect(PointSystem:EnsurePoint()).to.equal(true)
			local prompts = managedPrompts(stall)
			expect(#prompts).to.equal(1)
			expect(prompts[1].ActionText).to.equal("Upgrade Cart")
			expect(prompts[1].ObjectText).to.equal("Cart Upgrades")
			expect(prompts[1].MaxActivationDistance).to.equal(14)
			PointSystem:Stop()
			expect(#managedPrompts(stall)).to.equal(0)
			CollectionService:RemoveTag(stall, "CartUpgradeStall")
			stall:Destroy()
			end)
		end)

		it("fails closed when authoring contains conflicting tagged stalls", function()
			withoutAuthoredStalls(function()
			PointSystem:Stop()
			local first = Instance.new("Part")
			local second = Instance.new("Part")
			first.Parent, second.Parent = workspace, workspace
			CollectionService:AddTag(first, "CartUpgradeStall")
			CollectionService:AddTag(second, "CartUpgradeStall")
			expect(PointSystem:EnsurePoint()).to.equal(false)
			expect(#managedPrompts(first)).to.equal(0)
			expect(#managedPrompts(second)).to.equal(0)
			CollectionService:RemoveTag(first, "CartUpgradeStall")
			CollectionService:RemoveTag(second, "CartUpgradeStall")
			first:Destroy()
			second:Destroy()
			end)
		end)
	end)
end
