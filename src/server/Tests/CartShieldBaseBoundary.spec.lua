--!nocheck
return function()
	local Boundary = require(script.Parent.Parent.Utility.CartShieldBaseBoundary)
	it("recognizes the authored owner spawn ramp and loaded-cart return zone without generic Camp",function()
		local base = Instance.new("Model") base.Name = "FIXTURE_OWN_BASE"
		local function part(name,position,size)
			local p = Instance.new("Part") p.Name = name p.Anchored = true p.Position = position p.Size = size p.Parent = base return p
		end
		local zone = part("DepositReturnZone",Vector3.new(-132.4,6.55,-204.73),Vector3.new(36,13,28))
		zone.CFrame *= CFrame.Angles(0,math.pi,0) zone:SetAttribute("BaseId","FIXTURE_BASE")
		part("Foundation",Vector3.new(-95.27,.55,-226.46),Vector3.new(46.66,1,79.46))
		part("CartDisplay",Vector3.new(-132.4,.55,-204.73),Vector3.new(27.2,1,36))
		part("CartRamp",Vector3.new(-132.4,.55,-180.93),Vector3.new(24,1,12))
		part("HouseRamp",Vector3.new(-95.27,.55,-180.93),Vector3.new(20,1,12))
		local ownerSpawn,cartSpawn = Vector3.new(-132.4,3,-177.53),Vector3.new(-132.4,1.5,-204.73)
		local ok,failure = xpcall(function()
			expect(Boundary.Contains(zone,ownerSpawn)).to.equal(false)
			expect(Boundary.Qualifies(base,"FIXTURE_BASE",ownerSpawn,cartSpawn)).to.equal(true)
			expect(Boundary.Qualifies(base,"OTHER_BASE",ownerSpawn,cartSpawn)).to.equal(false)
			expect(Boundary.Qualifies(base,"FIXTURE_BASE",Vector3.new(0,3,0),cartSpawn)).to.equal(false)
			expect(Boundary.Qualifies(base,"FIXTURE_BASE",ownerSpawn,Vector3.new(0,3,0))).to.equal(false)
			expect(Boundary.Qualifies(base,"FIXTURE_BASE",ownerSpawn+Vector3.yAxis*100,cartSpawn)).to.equal(false)
			expect(Boundary.Contains(zone,Vector3.new(0/0,3,0))).to.equal(false)
		end,debug.traceback)
		base:Destroy() assert(ok,failure)
	end)
end
