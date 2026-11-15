-- Pure boundary regressions for the actual fit API. The runner supplies the native Luau module.
-- These test arithmetic/helpers only; they cannot mark native map/gameplay acceptance passed.
return function(API)
 local tests={}
 local function add(name,fn)table.insert(tests,{name=name,run=fn})end
 local function close(a,b)assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b))end
 local function bounds(x0,x1,z0,z1)return {min={x0,0,z0},max={x1,3.5,z1},size={x1-x0,3.5,z1-z0}}end
 add("Retain current larger pad independently on each axis",function()
  local p=API.SupportPad(bounds(-1,1,-3,3),Vector3.new(10,.75,4),1);close(p.x,10);close(p.z,8)
 end)
 add("Asymmetric native envelope requires centred support, not width plus margin",function()
  local p=API.SupportPad(bounds(-3.2573934742970345,3.316661073411081,-1,1),Vector3.new(2.1213,.75,2.1213),1)
  close(p.x,8.633322146822162);assert(p.x>6.574054547708116+2,"Asymmetric support must exceed width-only estimate")
 end)
 add("Longer negative native overhang is also fully supported",function()
  local p=API.SupportPad(bounds(-5.5,1,-1,1),Vector3.new(2,.75,2),1);close(p.x,13)
 end)
 add("Exact two-stud pad separation is a passing boundary",function()
  close(API.SignedGap(bounds(-5,5,-5,5),bounds(-5,5,7,17),3),2)
 end)
 add("Touching pads give zero clearance",function()
  close(API.SignedGap(bounds(-5,5,-5,5),bounds(-5,5,5,15),3),0)
 end)
 add("Overlapping adjacent standing envelopes retain a negative signed gap",function()
  close(API.SignedGap(bounds(-1,1,-3.2573934742970345,3.316661073411081),bounds(-1,1,4.5-3.2573934742970345,4.5+3.316661073411081),3),-2.0740545477081156)
 end)
 add("Aisle uses transverse X separation rather than Z",function()
  close(API.SignedGap(bounds(-15,-3,-5,5),bounds(3,15,-5,5),1),6)
 end)
 add("Contraction of centre distance preserves native shape size",function()
  local original=bounds(-2,4,-5,3);local moved=API.TranslateBounds(original,Vector3.new(7.25*(.75-1),0,11.25*(.75-1)))
  close(moved.size[1],6);close(moved.size[3],8);close(moved.min[1],-3.8125);close(moved.max[3],.1875)
 end)
 add("Projection does not mutate cached immutable native bounds",function()
  local original=bounds(-2,4,-5,3);local moved=API.TranslateBounds(original,Vector3.new(10,0,20));moved.min[1]=99;moved.size[1]=99
  close(original.min[1],-2);close(original.size[1],6)
 end)
 add("Larger factor cannot rescue current ten-stud pads on 4.5 stride",function()
  for _,b in {.75,.8,.85,.9,.95,1}do
   local left=bounds(-5,5,-5,5);local right=API.TranslateBounds(left,Vector3.new(0,0,4.5*b))
   assert(API.SignedGap(left,right,3)<2,"Existing pad centres cannot provide two-stud gap")
  end
 end)
 local result={schemaVersion=1,scope="Actual RuntimeBaseFit pure helpers",nativeMapAcceptance=false,gameplayAcceptance=false,tests={},passed=0,failed=0}
 for _,test in tests do local ok,reason=pcall(test.run);table.insert(result.tests,{name=test.name,passed=ok,error=not ok and tostring(reason)or nil});if ok then result.passed+=1 else result.failed+=1 end end
 return result
end
