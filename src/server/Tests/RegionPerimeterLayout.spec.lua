--!nocheck
return function()
	local Layout=require(script.Parent.Parent.Utility.RegionPerimeterLayout)
	local rectangle={x0=-100,x1=100,z0=-80,z1=80}
	it("closes the full perimeter while leaving only the exact cart opening",function()
		local walls=Layout.Build({rectangle},{x=-100,z=0,width=24,axis="Z"})
		expect(#walls).to.equal(5)
		local total=0
		for _,w in walls do total+=w.last-w.first end
		expect(total).to.equal(720-24)
		for _,w in walls do if w.axis=="Z" and w.fixed==-100 then expect(w.last<=-12 or w.first>=12).to.equal(true) end end
	end)
	it("removes internal floor seams and preserves the actual concave footprint",function()
		local r={{x0=-1091,x1=-771,z0=-958,z1=386},{x0=-771,x1=-451,z0=-958,z1=-718}}
		local walls=Layout.Build(r,{x=-771,z=-598,width=24,axis="Z"})
		expect(#walls).to.equal(7)
		local length=0 for _,w in walls do length+=w.last-w.first end
		expect(length).to.equal(3968-24)
		for _,w in walls do if w.axis=="Z" and w.fixed==-771 then expect(w.first>=-718).to.equal(true) end end
	end)
	it("is independent of duplicated or reordered saved floor references",function()
		local a=Layout.Build({rectangle},{x=0,z=-80,width=24,axis="X"})
		local b=Layout.Build({rectangle,rectangle},{x=0,z=-80,width=24,axis="X"})
		expect(#a).to.equal(#b)
		for i,w in a do expect(w.axis..w.fixed..w.first..w.last).to.equal(b[i].axis..b[i].fixed..b[i].first..b[i].last) end
	end)
	it("rejects a gate inside the biome, undersized opening or invalid geometry",function()
		expect(function() Layout.Build({rectangle},{x=0,z=0,width=24,axis="X"}) end).to.throw()
		expect(function() Layout.Build({rectangle},{x=0,z=-80,width=20,axis="X"}) end).to.throw()
		expect(function() Layout.Build({{x0=0,x1=math.huge,z0=0,z1=1}},{x=0,z=0,width=24,axis="X"}) end).to.throw()
	end)
	it("keeps the corrected Volcano opening clear of its actual Arctic corner",function()
		local walls=Layout.Build({{x0=413,x1=1053,z0=-478,z1=386},{x0=733,x1=1053,z0=-718,z1=-478}},
			{x=413,z=-462,width=24,axis="Z"})
		expect(#walls).to.equal(7)
		for _,w in walls do
			expect(w.last>w.first).to.equal(true)
			expect(w.inward==1 or w.inward==-1).to.equal(true)
			if w.axis=="Z" and w.fixed==413 then expect(w.last<=-474 or w.first>=-450).to.equal(true) end
		end
	end)

	it("rejects the former Volcano placement that lets a corner wall narrow the opening",function()
		expect(function() Layout.Build({{x0=413,x1=1053,z0=-478,z1=386},{x0=733,x1=1053,z0=-718,z1=-478}},
			{x=413,z=-466,width=24,axis="Z"}) end).to.throw()
	end)

	it("opens both sides of the actual Jungle-to-Glitch shared boundary",function()
		local jungle={{x0=-451,x1=413,z0=386,z1=866},{x0=-771,x1=-451,z0=626,z1=866}}
		local entrance={x=-415,z=386,width=24,axis="X"}
		local glitch={x=413,z=506,width=24,axis="Z"}
		local walls=Layout.Build(jungle,entrance,{entrance,glitch,glitch})
		expect(#walls).to.equal(8)
		for _,w in walls do if w.axis=="Z" and w.fixed==413 then expect(w.last<=494 or w.first>=518).to.equal(true) end end
	end)

end
