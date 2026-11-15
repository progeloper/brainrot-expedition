--!nocheck
return function()
	local Guard=require(script.Parent.Parent.Services.RegionBoundaryGuard)
	local function fixture()
		local player={UserId=1}
		local entity={id={},cart={},members={player},ready=true,alive=true,position=Vector3.new(14,0,0),
			velocity=Vector3.new(-30,0,4),forward=Vector3.new(-1,0,0),extent=11,lateralExtent=8}
		local gate={regionId="REGION_BEACH",normal=Vector3.new(-1,0,0),threshold=Vector3.zero,
			approach={CFrame=CFrame.new(12,0,0)*CFrame.Angles(0,math.pi/2,0),Size=Vector3.new(24,18,24)},
			crossing={Size=Vector3.new(24,18,4)}}
		local allowed,time=false,0
		local entities={entity}
		local targets={}
		local stops,corrections,notices,admissions,changes=0,0,0,0,{}
		local access={}
		function access:GetEffectiveAccess() return allowed end
		function access:GetCartEntryAccess() return {allowed=allowed,code="RegionAccessRequired"} end
		local descriptors={}
		function descriptors:GetGate(id) return if id=="REGION_BEACH" then gate else nil end
		function descriptors:GetRegionAtPosition(p) return if p.X<0 then "REGION_BEACH" else "REGION_FOREST" end
		local guard=Guard.new({Access=access,Descriptors=descriptors,GetEntities=function() return entities end,
			Now=function() return time end,Correct=function() corrections+=1 end,
			SetDenied=function(target,normal)
				target.cart.WorldGateDeniedNormal=normal
				table.insert(targets,target) table.insert(changes,normal or "clear")
			end,
			StopInward=function() stops+=1 entity.velocity=Vector3.new(0,0,4) end,
			Notice=function() notices+=1 end})
		return {guard=guard,entity=entity,setEntities=function(value) entities=value end,targets=targets,allow=function() allowed=true end,
			advance=function(n) time+=n end,counts=function() return stops,corrections,notices,admissions,changes end}
	end
	it("retains denial while holding forward without repeated state changes",function()
		local f=fixture() f.guard:Step() f.guard:Step()
		local stops,_,notices,_,changes=f.counts()
		expect(stops).to.equal(2) expect(notices).to.equal(1) expect(#changes).to.equal(1)
		f.advance(2) f.guard:Step() local _,_,n=f.counts() expect(n).to.equal(2)
	end)
	it("clears denial immediately on confirmed personal access",function()
		local f=fixture() f.guard:Step() f.allow() f.entity.velocity=Vector3.new(-30,0,0) f.guard:Step()
		local _,_,_,admissions,changes=f.counts()
		expect(admissions).to.equal(0) expect(changes[2]).to.equal("clear")
	end)
	it("allows steering away from the stopped gate",function()
		local f=fixture() f.guard:Step() f.entity.forward=Vector3.new(0,0,1) f.guard:Step()
		local stops,_,_,_,changes=f.counts() expect(stops).to.equal(1) expect(changes[2]).to.equal("clear")
	end)
	it("corrects side entry using physical region regardless of gate approach",function()
		local f=fixture() f.entity.position=Vector3.new(-100,100,200) f.guard:Step()
		local _,corrections=f.counts() expect(corrections).to.equal(1)
	end)
	it("retries unauthorized recovery without waiting for a retired guest lease",function()
		local f=fixture() f.entity.position=Vector3.new(-100,0,200)
		f.guard:Step() f.guard:Step()
		local _,corrections=f.counts() expect(corrections).to.equal(2)
	end)

	it("does not correct an authorized traveler from an outdated denied state",function()
		local f=fixture() f.guard:Step() f.allow() f.entity.position=Vector3.new(-100,0,200) f.guard:Step()
		local _,corrections,_,_,changes=f.counts() expect(corrections).to.equal(0) expect(changes[2]).to.equal("clear")
	end)
	it("releases a lost cart once and remounts away without stale movement denial",function()
		local f=fixture() f.guard:Step()
		expect(f.entity.cart.WorldGateDeniedNormal).to.equal(Vector3.new(-1,0,0))
		f.setEntities({}) f.guard:Step() f.guard:Step()
		expect(f.entity.cart.WorldGateDeniedNormal).to.equal(nil)
		local _,_,_,_,changes=f.counts() expect(#changes).to.equal(2)
		f.entity.position=Vector3.new(100,0,100) f.entity.velocity=Vector3.zero
		f.setEntities({f.entity}) f.guard:Step()
		expect(f.entity.cart.WorldGateDeniedNormal).to.equal(nil) expect(#changes).to.equal(2)
		-- Reentering the real denied approach must still stop the same cart.
		f.entity.position=Vector3.new(14,0,0) f.entity.velocity=Vector3.new(-30,0,4)
		f.guard:Step() f.guard:Step()
		expect(f.entity.cart.WorldGateDeniedNormal).to.equal(Vector3.new(-1,0,0))
		expect(#changes).to.equal(3)
		f.guard:Destroy()
	end)
	it("rebinds a reused identity without clearing unchanged snapshot targets",function()
		local f=fixture() f.guard:Step()
		local snapshot=table.clone(f.entity)
		f.setEntities({snapshot}) f.guard:Step()
		local _,_,_,_,changes=f.counts() expect(#changes).to.equal(1)
		local replacement=table.clone(snapshot) replacement.cart={}
		f.setEntities({replacement}) f.guard:Step()
		expect(snapshot.cart.WorldGateDeniedNormal).to.equal(nil)
		expect(replacement.cart.WorldGateDeniedNormal).to.equal(Vector3.new(-1,0,0))
		expect(f.targets[2]).to.equal(snapshot) expect(f.targets[3]).to.equal(replacement)
		f.guard:Step() expect(#changes).to.equal(3)
		f.guard:Destroy()
	end)
	it("releases each owned denied target on Destroy without repeated clears",function()
		local f=fixture() f.guard:Step()
		f.guard:Destroy() f.guard:Destroy()
		local _,_,_,_,changes=f.counts()
		expect(#changes).to.equal(2) expect(changes[2]).to.equal("clear")
		expect(f.entity.cart.WorldGateDeniedNormal).to.equal(nil)
	end)

end
