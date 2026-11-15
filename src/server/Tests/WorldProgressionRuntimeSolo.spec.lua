--!nocheck
return function()
	local Runtime=require(script.Parent.Parent.Services.WorldProgressionRuntime)
	local Reset=require(script.Parent.Parent.Utility.CartResetExecutor)
	local function fixture(callback)
		local folder=Instance.new("Folder") folder.Name="SPEC_SoloRegionRuntime" folder.Parent=workspace
		local function model(name,position,character)
			local object=Instance.new("Model") object.Name=name object.Parent=folder
			local root=Instance.new("Part") root.Name=if character then "HumanoidRootPart" else "Root"
			root.Anchored=true root.Position=position root.Parent=object object.PrimaryPart=root
			if character then local h=Instance.new("Humanoid") h.RequiresNeck=false h.Parent=object end
			return object
		end
		local a={UserId=-62001,Character=model("OwnerA",Vector3.new(26000,100,26000),true)}
		local b={UserId=-62002,Character=model("OwnerB",Vector3.new(26100,100,26000),true)}
		local cart=model("CartA",a.Character.PrimaryPart.Position,false)
		local otherCart=model("CartB",b.Character.PrimaryPart.Position,false)
		local records={{Model=cart,OwnerUserId=a.UserId},{Model=otherCart,OwnerUserId=b.UserId}}
		local seated={[cart]={a},[otherCart]={b}}
		local owners={[cart]=a.UserId,[otherCart]=b.UserId}
		local grants={[a]=false,[b]=true}
		local exterior=CFrame.new(25900,100,26000)
		local occupants={}
		function occupants:GetOccupants(value) return seated[value] or {} end
		function occupants:GetOwnerUserId(value) return owners[value] end
		local runtime=setmetatable({options={Occupants=occupants,
			Carts={GetCartRecords=function() return records end},Profile={IsWritable=function() return true end}},
			playerCarts={},cache={},correcting={},descriptors={GetRegionAtPosition=function() return "REGION_FOREST" end,
			IsInTransition=function() return false end,GetSafeExterior=function() return {safeCart=exterior,safeCharacter=exterior} end},
			access={GetEffectiveAccess=function(_,player) return grants[player]==true end}},Runtime)
		runtime.GetPlayerState=function(self,player)
			if player~=a and player~=b then return nil end
			return Runtime.GetPlayerState(self,player)
		end
		local original=Reset.CorrectRegionEntry
		local corrections=0
		Reset.CorrectRegionEntry=function(target,destination,validate)
			corrections+=1
			expect(target).to.equal(cart) expect(destination).to.equal(exterior)
			return validate("Suspension") and validate("Reposition")
		end
		local ok,failure=xpcall(function() callback({runtime=runtime,a=a,b=b,cart=cart,otherCart=otherCart,
			seated=seated,owners=owners,grants=grants,records=records,exterior=exterior,
			corrections=function() return corrections end}) end,debug.traceback)
		Reset.CorrectRegionEntry=original folder:Destroy()
		assert(ok,failure)
	end
	it("tracks only each canonical owner and preserves independent cart entities",function()
		fixture(function(f)
			f.seated[f.cart]={f.a,f.b}
			f.runtime:RefreshEntities()
			expect(#f.runtime.entities).to.equal(2)
			expect(f.runtime.playerCarts[f.a]).to.equal(f.cart)
			expect(f.runtime.playerCarts[f.b]).to.equal(f.otherCart)
			for _,entity in f.runtime.entities do
				expect(#entity.members).to.equal(1)
				expect(entity.members[1].UserId).to.equal(f.owners[entity.cart])
			end
		end)
	end)
	it("never promotes a stranger occupant to the absent owner's cart entity",function()
		fixture(function(f)
			f.seated[f.cart]={f.b}
			f.runtime:RefreshEntities()
			expect(#f.runtime.entities).to.equal(1)
			expect(f.runtime.playerCarts[f.a]).to.equal(nil)
			expect(f.runtime.playerCarts[f.b]).to.equal(f.otherCart)
		end)
	end)
	it("clears cart caches and owner mappings after replacement or dismount",function()
		fixture(function(f)
			f.runtime:RefreshEntities()
			f.seated[f.cart]={}
			expect(f.runtime:GetPlayerState(f.a).cart).to.equal(nil)
			table.remove(f.records,1) f.runtime:RefreshEntities()
			expect(f.runtime.playerCarts[f.a]).to.equal(nil)
			expect(f.runtime.cache[f.cart]).to.equal(nil)
			expect(f.runtime.playerCarts[f.b]).to.equal(f.otherCart)
		end)
	end)
	it("does not correct an owner's cart for a stranger or authorized owner",function()
		fixture(function(f)
			f.seated[f.cart]={f.b}
			expect(f.runtime:CorrectCart(f.cart,"REGION_BEACH")).to.equal(false)
			f.seated[f.cart]={f.a} f.grants[f.a]=true
			expect(f.runtime:CorrectCart(f.cart,"REGION_BEACH")).to.equal(false)
			expect(f.corrections()).to.equal(0)
		end)
	end)
	it("uses the local region exterior for an unauthorized physically seated owner",function()
		fixture(function(f)
			f.runtime:RefreshEntities()
			expect(f.runtime:CorrectPlayer(f.a,"REGION_BEACH",f.a.Character)).to.equal(true)
			expect(f.corrections()).to.equal(1)
			expect(next(f.runtime.correcting)).to.equal(nil)
		end)
	end)
	it("rechecks permanent access before repositioning the occupied cart",function()
		fixture(function(f)
			f.runtime:RefreshEntities()
			Reset.CorrectRegionEntry=function(_,_,validate)
				expect(validate("Suspension")).to.equal(true)
				f.grants[f.a]=true
				return validate("Reposition")
			end
			expect(f.runtime:CorrectCart(f.cart,"REGION_BEACH")).to.equal(false)
			expect(next(f.runtime.correcting)).to.equal(nil)
		end)
	end)
	it("does not let a pending cart correction affect a replacement character",function()
		fixture(function(f)
			f.runtime:RefreshEntities()
			Reset.CorrectRegionEntry=function(_,_,validate)
				expect(validate("Suspension")).to.equal(true)
				f.runtime.GetPlayerState=function()
					return {characterToken={},ready=true,alive=true}
				end
				return validate("Reposition")
			end
			expect(f.runtime:CorrectCart(f.cart,"REGION_BEACH")).to.equal(false)
		end)
	end)
	it("rejects stale character correction tokens without moving the current owner",function()
		fixture(function(f)
			f.runtime:RefreshEntities()
			local before=f.a.Character:GetPivot()
			expect(f.runtime:CorrectPlayer(f.a,"REGION_BEACH",{})).to.equal(false)
			expect(f.a.Character:GetPivot()).to.equal(before)
			expect(f.corrections()).to.equal(0)
		end)
	end)
	it("publishes only personal progression without consulting retired leases",function()
		fixture(function(f)
			local personal={ready=true,personalUnlocks={Forest=true},gates={}}
			f.runtime.progression={GetSummary=function() return personal end}
			f.runtime.access.GetGuestStatus=function() error("retired guest status must not be read") end
			expect(f.runtime:Summary(f.a)).to.equal(personal)
			expect(f.runtime:Summary(f.a).guest).to.equal(nil)
		end)
	end)
end
