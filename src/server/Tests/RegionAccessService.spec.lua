--!nocheck
return function()
	local Service = require(script.Parent.Parent.Services.RegionAccessService)
	local function fixture()
		local a,b = {UserId=30},{UserId=20}
		local cart,otherCart = {},{}
		local states,grants = {},{}
		for _,player in {a,b} do
			states[player]={alive=true,ready=true,regionId="REGION_FOREST",characterToken=1}
			grants[player]={REGION_CAMP=true,REGION_FOREST=true}
		end
		grants[b].REGION_BEACH=true
		local drivers,owners,control={[cart]=a,[otherCart]=b},{[cart]=a.UserId,[otherCart]=b.UserId},true
		local progression={}
		function progression:GetPersonalAccess(player,region) return grants[player] and grants[player][region]==true end
		local occupants={}
		function occupants:GetDriver(model) return drivers[model] end
		function occupants:GetOwnerUserId(model) return owners[model] end
		function occupants:CanPlayerControlCart(player,model) return control and drivers[model]==player and owners[model]==player.UserId end
		local descriptors={GetGate=function(_,region) return if region=="REGION_BEACH" then {} else nil end}
		function descriptors:GetRegionAtPosition(position)
			return if position.X >= 150 then "REGION_BEACH" elseif position.X < 50 then "REGION_CAMP" else "REGION_FOREST"
		end
		function descriptors:IsInTransition(position) return math.abs(position.X-150)<=2 end
		local service=Service.new({Progression=progression,Occupants=occupants,Descriptors=descriptors,
			GetPlayerState=function(player) return states[player] end})
		service:SetOperational("REGION_BEACH",true)
		return {a=a,b=b,cart=cart,otherCart=otherCart,states=states,grants=grants,service=service,
			drivers=drivers,owners=owners,setControl=function(value) control=value end}
	end
	it("uses only each actual owner's confirmed permanent access",function()
		local f=fixture()
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").allowed).to.equal(false)
		expect(f.service:GetCartEntryAccess(f.otherCart,"REGION_BEACH").allowed).to.equal(true)
		expect(f.service:GetEffectiveAccess(f.a,"REGION_BEACH")).to.equal(false)
		expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(true)
	end)
	it("does not let a qualified stranger drive an unqualified owner's cart",function()
		local f=fixture() f.drivers[f.cart]=f.b
		local access=f.service:GetCartEntryAccess(f.cart,"REGION_BEACH")
		expect(access.allowed).to.equal(false) expect(access.code).to.equal("OwnerDriverRequired")
		expect(f.service:GetPersonalAccess(f.a,"REGION_BEACH")).to.equal(false)
	end)
	it("does not permit remote control by an absent qualified owner",function()
		local f=fixture() f.grants[f.a].REGION_BEACH=true f.drivers[f.cart]=nil
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").allowed).to.equal(false)
	end)
	it("rejects unregistered and replacement carts without inferring ownership",function()
		local f=fixture() f.grants[f.a].REGION_BEACH=true f.owners[f.cart]=nil
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").allowed).to.equal(false)
		expect(f.service:GetCartEntryAccess({},"REGION_BEACH").allowed).to.equal(false)
	end)
	it("rejects denied authority while preserving personal on-foot permission",function()
		local f=fixture() f.setControl(false)
		expect(f.service:GetCartEntryAccess(f.otherCart,"REGION_BEACH").allowed).to.equal(false)
		expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(true)
	end)
	it("requires a ready, living driver and personal visitor",function()
		for _,field in {"ready","alive"} do
			local f=fixture() f.states[f.b][field]=false
			expect(f.service:GetCartEntryAccess(f.otherCart,"REGION_BEACH").allowed).to.equal(false)
			expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(false)
		end
	end)
	it("keeps personal permission through dismount and reseat",function()
		local f=fixture() f.states[f.b].regionId="REGION_BEACH"
		f.drivers[f.otherCart]=nil
		expect(f.service:CanBoard(f.b)).to.equal(true)
		expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(true)
		f.drivers[f.otherCart]=f.b
		expect(f.service:GetCartEntryAccess(f.otherCart,"REGION_BEACH").allowed).to.equal(true)
	end)
	it("does not retroactively authorize an unqualified owner boarding inside a region",function()
		local f=fixture() f.states[f.a].regionId="REGION_BEACH"
		expect(f.service:CanBoard(f.a)).to.equal(false)
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").code).to.equal("RegionAccessRequired")
	end)
	it("does not expose guest admission or leases",function()
		local f=fixture()
		expect(f.service.AdmitCart).to.equal(nil) expect(f.service.GetGuestStatus).to.equal(nil)
		expect(f.service.visits).to.equal(nil) expect(f.service.guests).to.equal(nil)
		expect(f.service.membership).to.equal(nil) expect(f.service.cartVisits).to.equal(nil)
	end)
	it("ignores injected historical lease data without changing permanent grants",function()
		local f=fixture()
		f.service.guests={[f.a]={regionId="REGION_BEACH",status="Active",sponsor=f.b}}
		expect(f.service:GetEffectiveAccess(f.a,"REGION_BEACH")).to.equal(false)
		expect(f.service:GetPersonalAccess(f.a,"REGION_BEACH")).to.equal(false)
	end)
	it("honors only confirmed personal grants as they change",function()
		local f=fixture()
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").allowed).to.equal(false)
		f.grants[f.a].REGION_BEACH=true
		expect(f.service:GetCartEntryAccess(f.cart,"REGION_BEACH").allowed).to.equal(true)
		expect(f.service:GetPersonalAccess(f.b,"REGION_BEACH")).to.equal(true)
	end)
	it("fails closed for unavailable gates without erasing personal ownership",function()
		local f=fixture() f.service:SetOperational("REGION_BEACH",false)
		expect(f.service:GetCartEntryAccess(f.otherCart,"REGION_BEACH").code).to.equal("RegionUnavailable")
		expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(false)
		expect(f.service:GetPersonalAccess(f.b,"REGION_BEACH")).to.equal(true)
		f.service:SetOperational("REGION_BEACH",true)
		expect(f.service:GetEffectiveAccess(f.b,"REGION_BEACH")).to.equal(true)
	end)
	it("rejects an unauthorized selected wild target without substituting another",function()
		local f=fixture()
		local allowed,code=f.service:CanInteractWild(f.a,Vector3.new(200,3,0))
		expect(allowed).to.equal(false) expect(code).to.equal("RegionAccessRequired")
		expect(f.service:CanInteractWild(f.a,Vector3.new(100,3,0))).to.equal(true)
	end)
	it("requires matching physical hunting regions or a verified transition overlap",function()
		local f=fixture()
		local allowed,code=f.service:CanInteractWild(f.b,Vector3.new(200,3,0))
		expect(allowed).to.equal(false) expect(code).to.equal("DifferentHuntingRegion")
		f.states[f.b].transitionRegionId="REGION_BEACH"
		expect(f.service:CanInteractWild(f.b,Vector3.new(151,3,0))).to.equal(true)
		expect(f.service:CanInteractWild(f.b,Vector3.new(200,3,0))).to.equal(false)
	end)
	it("checks a public Camp drop by current location without a species-home restriction",function()
		local f=fixture() f.states[f.a].regionId="REGION_CAMP"
		expect(f.service:CanInteractWild(f.a,Vector3.zero)).to.equal(true)
	end)
	it("rejects unknown regions and unavailable character state",function()
		local f=fixture()
		expect(f.service:GetCartEntryAccess(f.cart,"FORGED").code).to.equal("UnknownRegion")
		f.states[f.a]=nil
		expect(f.service:CanBoard(f.a)).to.equal(false)
		expect(f.service:CanInteractWild(f.a,Vector3.zero)).to.equal(false)
	end)
end
