--!nocheck
return function()
	local Descriptors = require(script.Parent.Parent.Utility.RegionGateDescriptors)
	local function fixture()
		local map = Instance.new("Folder")
		for name, x in {Camp=0,Forest=100,Beach=200} do
			local folder = Instance.new("Folder") folder.Name=name folder.Parent=map
			local floor=Instance.new("Part") floor.Size=Vector3.new(100,4,100) floor.Position=Vector3.new(x,-2,0)
			floor:SetAttribute("LayoutRole","Floor") floor:SetAttribute("GeneratedBy","CreateBasicMap_v1") floor.Parent=folder
		end
		return map, Descriptors.new(map)
	end
	it("resolves real floor columns while airborne and chooses stable shared edges", function()
		local map, descriptors = fixture()
		expect(descriptors:GetRegionAtPosition(Vector3.new(200,100,0))).to.equal("REGION_BEACH")
		expect(descriptors:GetRegionAtPosition(Vector3.new(150,3,0))).to.equal("REGION_FOREST")
		expect(descriptors:GetRegionAtPosition(Vector3.new(151,3,0))).to.equal("REGION_BEACH")
		expect(descriptors:GetRegionAtPosition(Vector3.new(400,3,0))).to.equal(nil)
		map:Destroy()
	end)
	it("ignores unrelated named parts and rejects invalid numeric positions", function()
		local map, descriptors = fixture()
		local fake=Instance.new("Part") fake.Name="Beach" fake.Position=Vector3.new(500,0,0) fake.Parent=map
		expect(descriptors:GetRegionAtPosition(Vector3.new(500,0,0))).to.equal(nil)
		expect(descriptors:GetRegionAtPosition(Vector3.new(math.huge,0,0))).to.equal(nil)
		map:Destroy()
	end)
	it("does not retain membership from removed floor instances", function()
		local map, descriptors = fixture()
		map.Beach:Destroy()
		expect(descriptors:GetRegionAtPosition(Vector3.new(200,3,0))).to.equal(nil)
		map:Destroy()
	end)
	it("requires recognized stable IDs and complete anchored gate descriptors", function()
		local map, descriptors = fixture()
		local gate=Instance.new("Model") gate.Parent=map
		expect(descriptors:BindGate("beach",gate)).to.equal(false)
		gate:SetAttribute("RegionId","REGION_BEACH") gate:SetAttribute("LogicalRegionKey","Beach")
		local ok,code=descriptors:BindGate("REGION_BEACH",gate)
		expect(ok).to.equal(false) expect(code).to.equal("GateDescriptorMissing")
		map:Destroy()
	end)
	it("validates a complete exterior/interior binding and clears a failed descriptor", function()
		local map, descriptors = fixture()
		local gate=Instance.new("Model") gate.Parent=map
		gate:SetAttribute("RegionId","REGION_BEACH") gate:SetAttribute("LogicalRegionKey","Beach")
		gate:SetAttribute("InwardNormal",Vector3.new(1,0,0))
		for _,name in {"InteractionAnchor","Approach","Threshold","SafeCharacterExterior","SafeCartExterior","DoorPresentation"} do
			local part=Instance.new("Part") part.Name=name part.Anchored=true part.CanCollide=false
			part.Position=if name:match("Exterior") then Vector3.new(140,3,0) else Vector3.new(150,3,0)
			part.Parent=gate
		end
		expect(descriptors:BindGate("REGION_BEACH",gate)).to.equal(true)
		expect(descriptors:GetGate("REGION_BEACH").exteriorRegion).to.equal("REGION_FOREST")
		gate.DoorPresentation.CanCollide=true
		local ok,code=descriptors:BindGate("REGION_BEACH",gate)
		expect(ok).to.equal(false) expect(code).to.equal("GateCollisionInvalid")
		expect(descriptors:GetGate("REGION_BEACH")).to.equal(nil)
		map:Destroy()
	end)
	it("rejects an interior safe pad and stale removed gate", function()
		local map, descriptors = fixture()
		local gate=Instance.new("Model") gate.Parent=map
		gate:SetAttribute("RegionId","REGION_BEACH") gate:SetAttribute("LogicalRegionKey","Beach")
		gate:SetAttribute("InwardNormal",Vector3.new(1,0,0))
		for _,name in {"InteractionAnchor","Approach","Threshold","SafeCharacterExterior","SafeCartExterior","DoorPresentation"} do
			local part=Instance.new("Part") part.Name=name part.Anchored=true part.CanCollide=false
			part.Position=if name:match("Exterior") then Vector3.new(160,3,0) else Vector3.new(150,3,0)
			part.Parent=gate
		end
		local ok,code=descriptors:BindGate("REGION_BEACH",gate)
		expect(ok).to.equal(false) expect(code).to.equal("GateExteriorInvalid")
		gate.SafeCharacterExterior.Position=Vector3.new(140,3,0)
		gate.SafeCartExterior.Position=Vector3.new(140,3,0)
		expect(descriptors:BindGate("REGION_BEACH",gate)).to.equal(true)
		gate:Destroy()
		expect(descriptors:GetGate("REGION_BEACH")).to.equal(nil)
		expect(descriptors:GetSafeExterior("REGION_BEACH").exteriorRegion).to.equal("REGION_FOREST")
		map:Destroy()
	end)

	it("does not authorize detached region folders whose child parts still exist",function()
		local map,descriptors=fixture()
		local detached=map.Beach detached.Parent=nil
		expect(descriptors:GetRegionAtPosition(Vector3.new(200,3,0))).to.equal(nil)
		detached:Destroy() map:Destroy()
	end)

end
