--!strict
-- Pure prepared final-local candidate. Native/root/site acceptance is a separate explicit gate.
local Layout={}
local function finite(n:any):boolean return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function ceil2(n:number):number return math.ceil((n-1e-9)*100)/100 end
local function mapaxis(a:number,b:number):number
 local t=96*b+8;local r=4*math.ceil((t+96*b/2+110*b/2+8)/4);local h=4*math.ceil((r+110*b/2+12)/4);local old,new=0,0
 for i,source in {136,313,420,432}do local target=({t,r,h-12,h})[i];if a<=source then return new+(a-old)*(target-new)/(source-old)end;old,new=source,target end
 error('Interior sample outside Camp')
end
function Layout.Candidate(b:number,measured:any):any
 assert(finite(b)and b>=.75 and b<=1,'Supported base factor required')
 assert(type(measured)=='table'and finite(measured.normalPad)and finite(measured.tangentPad)and finite(measured.centredCartWidth)and finite(measured.centredCartDepth),'Actual measured full support and centered cart envelope required')
 assert(measured.normalPad>0 and measured.tangentPad>0 and measured.centredCartWidth>0 and measured.centredCartDepth>0,'Measured support must be positive')
 local normal,tangent=ceil2(measured.normalPad),ceil2(measured.tangentPad)
 local stride=ceil2(tangent+2.02);local aisle=6.02+2*(.55+2.25);local offset=(normal+aisle)/2
 local width,depth=2*normal+aisle,5*stride+tangent
 local cartw,cartd=math.max(32*b,measured.centredCartWidth),math.max(24*b,measured.centredCartDepth)
 local cartx,cartz=28*b,-54*b
 local shellw,shelld=width+8*b+.2,depth+6.02+2.45*b+.1
 local supportw,supportd=shellw+.2,shelld+.2
 local centrex=math.min(cartx-cartw/2,cartx-12)-.2-supportw/2
 local centrez=-23*b;local supportz=centrez+(2.45*b+.1-6.02)/2
 local loopZ=-(mapaxis(336,b)-mapaxis(192,b));local nearEdge=loopZ+18;local desiredFront=nearEdge+2
 local supportShift=math.max(0,desiredFront-(supportz-supportd/2));local cartShift=math.max(0,desiredFront-(cartz-cartd/2))
 centrez+=supportShift;supportz+=supportShift;cartz+=cartShift
 local row:any={rowOffsetX=offset,formationCenterX=centrex,formationCenterZ=centrez,padNormalStuds=normal,padTangentialStuds=tangent,zCenters={},slots={},support={centreX=centrex,centreZ=supportz,width=supportw,depth=supportd},perimeter={centreX=centrex,centreZ=supportz,width=supportw,depth=supportd,frontSign=-1,postWidth=.625*b,postDepth=.625*b}}
 for i=1,6 do row.zCenters[i]=centrez+(i-3.5)*stride end
 for _,side in {-1,1}do for i=1,6 do table.insert(row.slots,{Index=#row.slots+1,Side=side,X=centrex+side*offset,Z=row.zCenters[i],PadNormalStuds=normal,PadTangentialStuds=tangent})end end
 local plot={minX=-48*b,maxX=48*b,minZ=-78*b,maxZ=32*b}
 local support={minX=centrex-supportw/2,maxX=centrex+supportw/2,minZ=supportz-supportd/2,maxZ=supportz+supportd/2}
 local cart={minX=cartx-cartw/2,maxX=cartx+cartw/2,minZ=cartz-cartd/2,maxZ=cartz+cartd/2}
 local fits=true
 for _,rect in {support,cart}do fits= fits and rect.minX>=plot.minX and rect.maxX<=plot.maxX and rect.minZ>=plot.minZ and rect.maxZ<=plot.maxZ end
 return{b=b,geometry=row,shell={width=shellw,depth=shelld,centreX=centrex,centreZ=supportz,height=22},cartSupport={width=cartw,depth=cartd,centreX=cartx,centreZ=cartz},functionalApproachCorrection={loopCentreZ=loopZ,loopNearEdgeZ=nearEdge,uniformFormationSupportShellShiftZ=supportShift,uniformCartBundleShiftZ=cartShift,houseRamp={centreX=centrex,centreZ=desiredFront-5.8,width=20,depth=12},cartRamp={centreX=cartx,centreZ=desiredFront-5.8,width=24,depth=12}},analyticalRectangleContainmentPassed=fits,runtimeValidated=false,fullAcceptancePassed=false}
end
return table.freeze(Layout)
