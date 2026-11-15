from pathlib import Path
p=Path('/private/tmp/GateGapAudit/NativeBoundaryClosureAudit.Template.luau')
s=p.read_text()
s=s.replace('mutations=0,checks=0,failures={},failureCount=0,sections={},perimeters={},gates={},proposalCores={},','mutations=0,checks=0,failures={},failureCount=0,sections={},perimeters={},gates={},proposalCores={},\n  initialPointSolidEvidence={interior=0,boundaryContact=0,examples={}},')
s=s.replace('report.closureCollisionPartCount=#colliders','''-- Raycast intentionally omits hits when an origin starts in a collider.
 -- Resolve that case only against exact native block geometry, not bounds of
 -- meshes/unions/wedges. A 1e-5 contact tolerance covers float precision at a
 -- shared face; it is far smaller than any player/cart traversable gap.
 local exactBlocks={}
 local seenBlocks={}
 local function addExactBlock(p)
  if p:IsA("Part") and p.Shape==Enum.PartType.Block and p.Anchored and p.CanCollide and p.CanQuery and not seenBlocks[p] then
   seenBlocks[p]=true;table.insert(exactBlocks,p)
  end
 end
 for _,path in input.existingProxies do local p=resolve(path);if p then addExactBlock(p) end end
 for _,p in gates:GetDescendants() do addExactBlock(p) end
 for _,p in colliders do addExactBlock(p) end
 local function blockedPointRay(a,b,params,blocks,section)
  local hit=Workspace:Raycast(a,b-a,params)
  if hit then return hit.Instance,"Raycast" end
  for _,p in blocks do
   local q=p.CFrame:PointToObjectSpace(a)
   local h=p.Size/2
   local dx,dy,dz=math.abs(q.X)-h.X,math.abs(q.Y)-h.Y,math.abs(q.Z)-h.Z
   if dx<=1e-5 and dy<=1e-5 and dz<=1e-5 then
    local mode=dx<-1e-5 and dy<-1e-5 and dz<-1e-5 and "interior" or "boundaryContact"
    report.initialPointSolidEvidence[mode]+=1
    local examples=report.initialPointSolidEvidence.examples
    if #examples<24 then table.insert(examples,{section=section,kind=mode,part=p:GetFullName(),origin={a.X,a.Y,a.Z},localPoint={q.X,q.Y,q.Z},halfSize={h.X,h.Y,h.Z}}) end
    return p,"InitialExactBlock:"..mode
   end
  end
  return nil,"NoPhysicalBlock"
 end
 report.exactInitialBlockProxyCount=#exactBlocks
 report.initialPointSolidTolerance=1e-5
 report.closureCollisionPartCount=#colliders''')
s=s.replace('''local forward=Workspace:Raycast(p-n*80,n*160,rp)
      local reverse=Workspace:Raycast(p+n*80,-n*160,rp)
      check(forward~=nil and reverse~=nil,"UnexpectedPerimeterOpening",{region=e.region,axis=e.axis,fixed=e.fixed,along=al,height=height,forward=forward and forward.Instance:GetFullName(),reverse=reverse and reverse.Instance:GetFullName()})''','''local forward,forwardKind=blockedPointRay(p-n*80,p+n*80,rp,exactBlocks,"perimeter")
      local reverse,reverseKind=blockedPointRay(p+n*80,p-n*80,rp,exactBlocks,"perimeter")
      check(forward~=nil and reverse~=nil,"UnexpectedPerimeterOpening",{region=e.region,axis=e.axis,fixed=e.fixed,along=al,height=height,forward=forward and forward:GetFullName(),reverse=reverse and reverse:GetFullName(),forwardKind=forwardKind,reverseKind=reverseKind})''')
s=s.replace('''local hit=Workspace:Raycast(a,b-a,rp)
        local reverse=Workspace:Raycast(b,a-b,rp)
        check(hit~=nil and reverse~=nil,"CornerDiagonalOpening",{corner=key,height=height,theta=theta,offset=offset})''','''local hit,hitKind=blockedPointRay(a,b,rp,exactBlocks,"corners")
        local reverse,reverseKind=blockedPointRay(b,a,rp,exactBlocks,"corners")
        check(hit~=nil and reverse~=nil,"CornerDiagonalOpening",{corner=key,height=height,theta=theta,offset=offset,forwardKind=hitKind,reverseKind=reverseKind})''')
s=s.replace('''local hit=Workspace:Raycast(a,b-a,rp)
       local reverse=Workspace:Raycast(b,a-b,rp)
       row.pointChecks+=1
       check(hit~=nil and reverse~=nil,"GateSideDiagonalOpening",{gate=g.gate,along=al,height=height,alongDelta=slope*2})''','''local hit,hitKind=blockedPointRay(a,b,rp,exactBlocks,"flanks")
       local reverse,reverseKind=blockedPointRay(b,a,rp,exactBlocks,"flanks")
       row.pointChecks+=1
       check(hit~=nil and reverse~=nil,"GateSideDiagonalOpening",{gate=g.gate,along=al,height=height,alongDelta=slope*2,forwardKind=hitKind,reverseKind=reverseKind})''')
s=s.replace('''local forward=Workspace:Raycast(a,b-a,crp)
     local reverse=Workspace:Raycast(b,a-b,crp)
     row.rayChecks+=1
     check(forward~=nil and reverse~=nil,"ClosureCoreNotSolidAtSample",{id=p.id,fractionAlong=fractionX,fractionHeight=fractionY})''','''local forward,forwardKind=blockedPointRay(a,b,crp,colliders,"closures")
     local reverse,reverseKind=blockedPointRay(b,a,crp,colliders,"closures")
     row.rayChecks+=1
     check(forward~=nil and reverse~=nil,"ClosureCoreNotSolidAtSample",{id=p.id,fractionAlong=fractionX,fractionHeight=fractionY,forwardKind=forwardKind,reverseKind=reverseKind})''')
s=s.replace('Loaded-cart empty broad-phase overlap plus native Blockcast certifies clearance.','Raycast origins initially within/contacting exact CFrame-local native block geometry count as solid; never meshes/unions/wedges. Loaded-cart empty broad-phase overlap plus native Blockcast certifies clearance.')
p.write_text(s)
