--!nocheck
return function()
 local P=require(game.ReplicatedStorage.Shared.Utility.ChariotPresentation)
 describe('Phase 9 presentation bounds',function()
  local function cart()
   local m=Instance.new('Model')local root=Instance.new('Part')root.Name='Root'root.CFrame=CFrame.identity root.Parent=m m.PrimaryPart=root
   local chassis=Instance.new('Part')chassis.Name='Chassis'chassis.Size=Vector3.new(8,1.5,11)chassis.CFrame=CFrame.new(0,.75,0)chassis.Parent=m
   local wheels=Instance.new('Folder')wheels.Name='Wheels'wheels.Parent=m
   for _,side in {-1,1}do local w=Instance.new('Part')w.Size=Vector3.new(4,1,4)w.CFrame=CFrame.new(side*6,-.5,0)w.Parent=wheels end
   return m
  end
  it('uses the measured wheel support instead of an assumed floor',function()local m=cart()local a=P.Adapter(m)expect(a.supportY).to.equal(-1)expect(a.width).to.equal(2.2)m:Destroy()end)
  it('all six docked envelopes fit the chassis and clear passenger seats and aiming lane',function()
   local m=cart()local a=P.Adapter(m)
   for i=1,6 do local cf=P.Position(a,i,true)assert(math.abs(cf.X)+a.dockWidth/2<4,'Outside chassis')assert(math.abs(cf.X)-a.dockWidth/2>=.8,'Aiming lane')assert(cf.Z-a.dockDepth/2>=-5.5,'Front overhang')assert(cf.Z+a.dockDepth/2<-2,'Passenger conflict')end m:Destroy()
  end)
  it('occupied order fills left then right and preserves three separate rows',function()local m=cart()local a=P.Adapter(m)for i=1,6 do local cf=P.Position(a,i,false)expect(cf.X<0).to.equal(i%2==1)assert(math.abs(cf.Z-(a.row-math.floor((i-1)/2)*a.spacing))<1e-5,"Compact row mismatch")end m:Destroy()end)
  it('detects starting overlap at a closed semantic gate',function()local door=Instance.new('Part')door.Size=Vector3.new(24,18,.3)door.CFrame=CFrame.new(0,9,-10)expect(P.IntersectsGate(CFrame.new(2,1.5,-10),Vector3.new(2,3,2),Vector3.zero,door)).to.equal(true)door:Destroy()end)
  it('predicts a forward sweep before gate penetration',function()local door=Instance.new('Part')door.Size=Vector3.new(24,18,.3)door.CFrame=CFrame.new(0,9,-10)expect(P.IntersectsGate(CFrame.new(2,1.5,-6),Vector3.new(2,3,2),Vector3.new(0,0,-4),door)).to.equal(true)door:Destroy()end)
  it('a clear footprint does not dock due to an unrelated distant gate',function()local door=Instance.new('Part')door.Size=Vector3.new(24,18,.3)door.CFrame=CFrame.new(100,9,-10)expect(P.IntersectsGate(CFrame.new(2,1.5,-6),Vector3.new(2,3,2),Vector3.new(0,0,-4),door)).to.equal(false)door:Destroy()end)
 end)
end
