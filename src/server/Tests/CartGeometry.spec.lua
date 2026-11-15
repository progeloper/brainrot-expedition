--!nocheck
return function()
	local RS=game:GetService("ReplicatedStorage")
	local Geometry=require(RS.Shared.Utility.CartGeometry)
	local Profiles=require(RS.Shared.Config.CartGeometry)
	local Swap=require(script.Parent.Parent.Utility.CartGeometrySwap)
	local function part(parent,name,class)
		local p=Instance.new(class or "Part");p.Name=name;p.CanCollide=false;p.Parent=parent;return p
	end
	local function fixture(profile,world)
		local cart=Instance.new("Model");cart.Name="GeometryFixture";cart:SetAttribute("CartId","CRT_001")
		local root=part(cart,"Root");root.CFrame=world or CFrame.new(1000,20,1000);root.Anchored=true;cart.PrimaryPart=root
		for _,name in {"MovementAttachment","OrientationAttachment"}do local a=Instance.new("Attachment");a.Name=name;a.Parent=root end
		part(cart,"DriverSeat","VehicleSeat");part(cart,"CameraTarget");local h=part(cart,"HarpoonOrigin");local a=Instance.new("Attachment");a.Name="MuzzleAttachment";a.Parent=h
		for _,name in {"CargoSlots","FormationSlots"}do local f=Instance.new("Folder");f.Name=name;f.Parent=cart
			for i=1,6 do local p=part(f,"Slot"..i);local at=Instance.new("Attachment");at.Name=if name=="CargoSlots"then"CargoAttachment"else"FormationAttachment";at.Parent=p end
		end
		local c=Instance.new("Folder");c.Name="Constraints";c.Parent=cart
		local visual=Instance.new("Model");visual.Name="Visual";visual.Parent=cart
		local art=Instance.new("Model");art.Name="ArcadeV3";art.Parent=visual
		if profile.BodyMesh then local p=part(art,"Body","MeshPart");p.PivotOffset=profile.BodyMesh.PivotOffset else part(art,"RunnerBodyArt")end
		for _,w in profile.Wheels do local p=part(art,w.Name,"MeshPart");p.PivotOffset=w.PivotOffset end
		local ok,reason=Geometry.ApplyDetached(cart,profile);assert(ok,reason)
		return cart
	end
	local function jointCount(cart)
		local n=0;for _,v in cart:GetDescendants()do if v:IsA("JointInstance")or v:IsA("WeldConstraint")then n+=1 end end;return n
	end
	local function close(a,b)expect((a-b).Magnitude<0.01).to.equal(true)end
	describe("Explicit vehicle geometry integration",function()
		it("authors distinct dimensions without changing the legacy no-profile path",function()
			local cart=Instance.new("Model");expect(Geometry.Get(cart)).to.equal(nil);expect(Geometry.SpawnOffset(cart)).to.equal(CFrame.new(0,4,0));cart:Destroy()
			for _,p in Profiles do local ok,reason=Geometry.Validate(p);assert(ok,reason)end
			expect(Profiles.CRT_013.BodySize.X/Profiles.CRT_008.BodySize.X>1.15).to.equal(true)
		end)
		it("keeps rider cargo and staged swaps valid without retired launcher markers",function()
			local cart=fixture(Profiles.CRT_001);local source=fixture(Profiles.CRT_013)
			cart.HarpoonOrigin:Destroy();source.HarpoonOrigin:Destroy()
			expect(Geometry.ValidateTemplate(cart)).to.equal(true)
			assert(Geometry.ApplyDetached(cart,Profiles.CRT_001))
			local root,seat,slot=cart.Root,cart.DriverSeat,cart.CargoSlots.Slot6
			local t=assert(Swap.Prepare(cart,source,root.CFrame));t.Apply();t.Commit()
			expect(cart.Root).to.equal(root);expect(cart.DriverSeat).to.equal(seat);expect(cart.CargoSlots.Slot6).to.equal(slot)
			expect(Geometry.ValidateTemplate(cart)).to.equal(true)
			cart:Destroy();source:Destroy()
		end)
		it("three profile applications keep immutable wheel binds and prune only dangling rig joints",function()
			local cart=fixture(Profiles.CRT_001)
			local root=cart.Root;local count=jointCount(cart)
			local ghost=Instance.new("WeldConstraint");ghost.Part0=root;ghost.Parent=cart.Constraints
			for _=1,3 do
				assert(Geometry.ApplyDetached(cart,Profiles.CRT_001))
				expect(cart.Root).to.equal(root);expect(jointCount(cart)).to.equal(count)
				for _,w in Profiles.CRT_001.Wheels do
					local p=cart.Visual.ArcadeV3[w.Name];close(p.Size,w.BindSize)
					close(root.CFrame:PointToObjectSpace(p:GetPivot().Position),w.Hub.Position)
					local motor=p:FindFirstChild("CartWheel_"..w.Name);expect(motor.Part0).to.equal(root);expect(motor.C1).to.equal(w.PivotOffset)
				end
			end
			expect(ghost.Parent).to.equal(nil);cart:Destroy()
		end)
		it("ten staged swap cycles preserve root/seat/slot identities without size drift",function()
			local cart=fixture(Profiles.CRT_001);local compact=fixture(Profiles.CRT_008);local large=fixture(Profiles.CRT_013)
			local root,seat,slot=cart.Root,cart.DriverSeat,cart.CargoSlots.Slot6
			for i=1,10 do
				local source=if i%2==1 then compact else large;local profile=if i%2==1 then Profiles.CRT_008 else Profiles.CRT_013
				local t=assert(Swap.Prepare(cart,source,root.CFrame));t.Apply();t.Commit()
				expect(cart.Root).to.equal(root);expect(cart.DriverSeat).to.equal(seat);expect(cart.CargoSlots.Slot6).to.equal(slot)
				close(root.Size,profile.RootSize);close(root.CFrame:PointToObjectSpace(slot.CargoAttachment.WorldPosition),profile.CargoSlots[6].Position)
				for _,w in profile.Wheels do close(cart.Visual.ArcadeV3[w.Name].Size,w.BindSize)end
				expect(Geometry.ValidateTemplate(cart)).to.equal(true)
			end
			cart:Destroy();compact:Destroy();large:Destroy()
		end)
		it("failed unit preparation and rollback retain the complete working unit",function()
			local cart=fixture(Profiles.CRT_001);local source=fixture(Profiles.CRT_013)
			local beforeVisual=cart.Visual;local beforeSize=cart.Root.Size;local beforeSlot=cart.CargoSlots.Slot1.CFrame
			local t=assert(Swap.Prepare(cart,source,cart.Root.CFrame));t.Apply();t.Rollback()
				expect(cart.Visual).to.equal(beforeVisual);expect(cart.Root.Size).to.equal(beforeSize);expect(cart.CargoSlots.Slot1.CFrame).to.equal(beforeSlot);expect(Geometry.Get(cart)).to.equal(Profiles.CRT_001)
			local bad=source.CargoSlots.Slot6;bad:Destroy();expect(Swap.Prepare(cart,source,cart.Root.CFrame)).to.equal(nil)
			cart:Destroy();source:Destroy()
		end)
		it("keeps42 total mass in the root and two actual wheel-contact cylinders",function()
			for _,profile in {Profiles.CRT_001,Profiles.CRT_008,Profiles.CRT_013}do
				local cart=fixture(profile);local total=cart.Root:GetMass();local weighted=0
				expect(cart.Root.RootPriority).to.equal(127)
				for _,physical in cart.Visual:GetDescendants()do
					if physical:IsA("BasePart")and not physical.Massless then total+=physical:GetMass();weighted+=1;expect(physical:IsA("Part")and physical.Shape==Enum.PartType.Cylinder).to.equal(true)end
				end
				expect(weighted).to.equal(2);expect(math.abs(total-42)<.01).to.equal(true)
				for _,artPart in cart.Visual.ArcadeV3:GetDescendants()do if artPart:IsA("BasePart")then expect(artPart.Massless).to.equal(true)end end
				cart:Destroy()
			end
		end)
		it("a Studio runner profile uses no wheel bind or invented catalogue identity",function()
			local profile=Profiles.DEV_RUNNER_FIXTURE;local cart=fixture(profile)
			expect(#profile.Wheels).to.equal(0);expect(cart:GetAttribute("CartId")).to.equal("CRT_001")
			for _,j in cart:GetDescendants()do expect(j:IsA("Motor6D")).to.equal(false)end
			expect(Geometry.ValidateTemplate(cart)).to.equal(true);cart:Destroy()
		end)
	end)
end
