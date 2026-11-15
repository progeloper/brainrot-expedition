--!nocheck
return function()
	local RS=game:GetService("ReplicatedStorage")
	local Sampler=require(RS.Shared.Utility.CartTerrainSampler)
	local Profiles=require(RS.Shared.Config.CartGeometry)
	local TerrainProfiles=require(RS.Shared.Utility.CartTerrainProfileResolver)
	local function near(actual,expected,tolerance)assert(actual~=nil,"Missing analytic gap");expect(math.abs(actual-expected)<(tolerance or 1e-4)).to.equal(true)end
	local function gap(hub,axis,r,h,n)return Sampler.CylinderPlaneGap(hub,axis,r,h,Vector3.zero,n or Vector3.yAxis)end
	describe("True cylinder terrain support",function()
		it("keeps circular support unchanged through forward and rearward pitch",function()
			for _,degrees in {-55,-28,0,28,55}do
				local rotation=CFrame.Angles(math.rad(degrees),0,0)
				near(gap(Vector3.new(0,2,0),rotation.RightVector,2,.25),0)
			end
		end)
		it("accounts for radial and axial extent during roll including a vertical axle",function()
			near(gap(Vector3.new(0,(2+.25)/math.sqrt(2),0),CFrame.Angles(0,0,math.pi/4).RightVector,2,.25),0)
			near(gap(Vector3.new(0,.25,0),Vector3.yAxis,2,.25),0)
		end)
		it("returns vertical ramp gaps and rejects nonfinite or wall-facing planes",function()
			local n=Vector3.new(0,math.sqrt(3)/2,.5)
			near(gap(Vector3.new(0,2/n.Y,0),Vector3.xAxis,2,.25,n),0)
			near(gap(Vector3.new(0,2/n.Y+.7,0),Vector3.xAxis,2,.25,n),.7)
			near(gap(Vector3.new(0,2/n.Y-.2,0),Vector3.xAxis,2,.25,n),-.2)
			expect(gap(Vector3.zero,Vector3.xAxis,2,.25,Vector3.zAxis)).to.equal(nil)
			expect(gap(Vector3.zero,Vector3.zero,2,.25)).to.equal(nil)
			expect(gap(Vector3.new(0/0,0,0),Vector3.xAxis,2,.25)).to.equal(nil)
		end)
		local sequence=0
		local function fixture(pitch,lift,callback)
			sequence+=1
			local model=Instance.new("Model");model.Name="SPEC_CYLINDER_SUPPORT";model.Parent=workspace
			local geometry=Profiles.CRT_001
			local origin=Vector3.new(12000+sequence*80,12000,12000)
			local floor=Instance.new("Part");floor.Size=Vector3.new(40,1,40);floor.CFrame=CFrame.new(origin-Vector3.yAxis*.5);floor.Anchored=true;floor.Parent=model
			local cart=Instance.new("Model");cart:SetAttribute("CartId","CRT_001");cart:SetAttribute("CartGeometryId","CRT_001");cart:SetAttribute("CartGeometryRevision",geometry.Revision);cart:SetAttribute("AssemblyValidationState","Valid");cart.Parent=model
			local root=Instance.new("Part");root.Name="Root";root.CanCollide=false;root.Size=geometry.RootSize;root.Parent=cart;cart.PrimaryPart=root
			local rotation=CFrame.Angles(math.rad(pitch),0,0)
			local support=geometry.Ground.CylinderSamples[1]
			local centreOffset=rotation:VectorToWorldSpace(support.Hub)
			root.CFrame=CFrame.new(origin+Vector3.yAxis*(support.Radius-centreOffset.Y+lift))*rotation
			local profile=TerrainProfiles.Resolve("CRT_001");local sampler=Sampler.new(cart,root,profile)
			local ok,why=xpcall(function()sampler:Resume();callback(sampler,profile)end,debug.traceback)
			sampler:Destroy();model:Destroy();assert(ok,why)
		end
		it("retains all three real flat-ground contacts while the chassis pitches28degrees",function()
			fixture(28,0,function(sampler,profile)
				local first=sampler:SampleNow(0);expect(first.HitCount).to.equal(3)
				local stable=sampler:SampleNow(profile.GroundedReacquireDelay+.01)
				expect(stable.State).to.equal("Grounded");near(stable.GroundDistance,0,.002)
			end)
		end)
		it("preserves the existing hover and penetration rejection thresholds",function()
			fixture(28,1.3,function(sampler)expect(sampler:SampleNow(0).HitCount).to.equal(0)end)
			fixture(-28,-.4,function(sampler)expect(sampler:SampleNow(0).HitCount).to.equal(0)end)
			fixture(28,.5,function(sampler)local snapshot=sampler:SampleNow(0);expect(snapshot.HitCount).to.equal(3);near(snapshot.GroundDistance,.5,.002)end)
		end)
	end)
end
