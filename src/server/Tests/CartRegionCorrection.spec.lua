--!nocheck
return function()
	local Executor=require(script.Parent.Parent.Utility.CartResetExecutor)
	local Occupants=require(script.Parent.Parent.Services.CartOccupantService)
	local Assembly=require(script.Parent.Parent.Services.CartAssemblyValidationService)
	local Stability=require(script.Parent.Parent.Services.CartStabilityService)
	local Terrain=require(script.Parent.Parent.Services.CartTerrainService)
	local function fixture(callback)
		local replacements={}
		local function replace(object,key,value)
			table.insert(replacements,{object=object,key=key,value=object[key]}) object[key]=value
		end
		local cart=Instance.new("Model") cart.Name="SPEC_RegionCorrection" cart:SetAttribute("RuntimeCart",true) cart.Parent=workspace
		local root=Instance.new("Part") root.Name="Root" root.Position=Vector3.new(32000,100,32000) root.Parent=cart cart.PrimaryPart=root
		local registered,occupied=true,true
		replace(Assembly,"IsCartValid",function() return true end)
		replace(Assembly,"BeginMutation",function() return true,1 end)
		replace(Assembly,"CompleteMutation",function() return true end)
		replace(Stability,"SuspendCart",function() return true end)
		replace(Stability,"ResumeCart",function() return true end)
		replace(Terrain,"SuspendCart",function() return true end)
		replace(Terrain,"ResumeCart",function() return true end)
		replace(Occupants,"GetDriver",function() return nil end)
		replace(Occupants,"IsCartRegistered",function() return registered end)
		replace(Occupants,"GetOccupants",function() return if occupied then {{UserId=1}} else {} end)
		replace(Occupants,"CanPlayerControlCart",function() error("driverless correction must not invent a driver") end)
		replace(Occupants,"RestoreNetworkOwnership",function() root:SetNetworkOwner(nil) return true end)
		local ok,failure=xpcall(function() callback(cart,root,function() occupied=false end,function() registered=false end) end,debug.traceback)
		for i=#replacements,1,-1 do local r=replacements[i] r.object[r.key]=r.value end
		cart:Destroy()
		assert(ok,failure)
	end
	it("uses existing suspension/mutation recovery for the owner seated during control suspension",function()
		fixture(function(cart,root)
			local exterior=CFrame.lookAt(Vector3.new(32100,100,32000),Vector3.new(32099,100,32000))
			local ok,reason,safe=Executor.CorrectRegionEntry(cart,exterior)
			expect(ok).to.equal(true) expect(reason).to.equal(nil) expect(safe).to.equal(true)
			expect(root.Position).to.equal(exterior.Position)
			expect((root.CFrame.LookVector-exterior.LookVector).Magnitude<1e-6).to.equal(true)
			expect(root.Anchored).to.equal(false) expect(root:GetNetworkOwner()).to.equal(nil)
			expect(type(cart:GetAttribute("LastServerReset"))).to.equal("number")
		end)
	end)
	it("refuses empty or unregistered carts instead of using an absent owner",function()
		fixture(function(cart,root,empty)
			local before=root.CFrame empty()
			expect(Executor.CorrectRegionEntry(cart,CFrame.new(0,10,0))).to.equal(false)
			expect(root.CFrame).to.equal(before)
		end)
		fixture(function(cart,root,_,unregister)
			local before=root.CFrame unregister()
			expect(Executor.CorrectRegionEntry(cart,CFrame.new(0,10,0))).to.equal(false)
			expect(root.CFrame).to.equal(before)
		end)
	end)
	it("does not extend ordinary reset authorization to a missing driver",function()
		fixture(function(cart,root)
			local before=root.CFrame
			expect(Executor.Execute(cart,CFrame.new(0,10,0),nil)).to.equal(false)
			expect(root.CFrame).to.equal(before)
		end)
	end)
	it("marks a trusted reposition only after the resume stage completes",function()
		fixture(function(cart)
			cart:SetAttribute("LastServerReset",123)
			local resumeSeen=false
			local ok=Executor.CorrectRegionEntry(cart,CFrame.new(32100,100,32000),function(stage)
				expect(cart:GetAttribute("LastServerReset")).to.equal(123)
				if stage=="Resume" then resumeSeen=true end
				return true
			end)
			expect(ok).to.equal(true) expect(resumeSeen).to.equal(true)
			expect(cart:GetAttribute("LastServerReset")>123).to.equal(true)
		end)
	end)
	it("retains the previous trusted marker when recovery or resume rejects the return",function()
		for _,rejectedStage in {"Recovery","Resume"} do
			fixture(function(cart)
				cart:SetAttribute("LastServerReset",123)
				local ok=Executor.CorrectRegionEntry(cart,CFrame.new(32100,100,32000),function(stage)
					return stage~=rejectedStage,"fixture rejection"
				end)
				expect(ok).to.equal(false)
				expect(cart:GetAttribute("LastServerReset")).to.equal(123)
			end)
		end
	end)
end
