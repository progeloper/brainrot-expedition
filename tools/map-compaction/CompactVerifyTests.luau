local fs=require('@lune/fs')
local roblox=require('@lune/roblox')
local modulePath=process and process.args and process.args[1] or '/Users/noahodukoya/development/Roblox/BrainrotExpedition/tools/map-compaction/Verify.luau'
local factory=assert(loadstring(fs.readFile(modulePath),'CompactVerify'),'Compile verifier failed')
local env=getfenv(factory)
env.game={GetService=function()return {}end}
env.CFrame=roblox.CFrame;env.Vector3=roblox.Vector3
local api=factory()
local passed=0
local function test(name,fn)fn();passed+=1;print('PASS '..name)end
local function near(a,b)assert(math.abs(a-b)<1e-5,string.format('%g differs from %g',a,b))end
test('recursive exact schema rejects omitted/extra keys',function()assert(not api.Equal({id='A',min=0},{id='A'}));assert(not api.Equal({id='A'},{id='A',extra=true}));assert(api.Equal({x={1,2,3}},{x={1,2,3.00001}},.001))end)
test('invalid numeric values cannot compare equal',function()assert(not api.Equal(0/0,0/0));assert(not api.Equal(math.huge,math.huge));assert(not api.Equal(-math.huge,-math.huge))end)
test('rotated native prism bounds include all axes',function()local b=api.Bounds({CFrame=roblox.CFrame.new(10,3,-20)*roblox.CFrame.Angles(0,math.pi/2,0),Size=roblox.Vector3.new(8,6,2)});near(b.minX,9);near(b.maxX,11);near(b.minZ,-24);near(b.maxZ,-16);near(b.minY,0);near(b.maxY,6)end)
local box={minX=-3,maxX=3,minZ=-10,maxZ=10}
test('opening penetration is measured across full wall thickness',function()near(api.PolygonInBounds({{-5,-2},{5,-2},{5,2},{-5,2}},box),24)end)
test('boundary-only contact is zero positive area',function()near(api.PolygonInBounds({{3,-2},{5,-2},{5,2},{3,2}},box),0)end)
test('oblique opening clipped area is winding independent',function()local polygon={{-5,0},{0,-5},{5,0},{0,5}};near(api.PolygonInBounds(polygon,box),42);local reverse={polygon[4],polygon[3],polygon[2],polygon[1]};near(api.PolygonInBounds(reverse,box),42)end)
test('disjoint opening does not intersect',function()near(api.PolygonInBounds({{20,0},{21,0},{21,1},{20,1}},box),0)end)
test('native float32 seam contact is tolerated per axis',function()
 local a={minX=0,maxX=128,minY=0,maxY=26,minZ=0,maxZ=6};local b={minX=127.99998092651367,maxX=220,minY=0,maxY=26,minZ=0,maxZ=6}
 local c=api.Contact(a,b,.01);assert(c.volume>0);assert(not c.overlapsBeyondTolerance);near(c.minimumAxisDepth,1.9073486328125e-5)
end)
test('meaningful three-axis penetration is rejected',function()
 local a={minX=0,maxX=128,minY=0,maxY=26,minZ=0,maxZ=6};local b={minX=127.98,maxX=220,minY=0,maxY=26,minZ=0,maxZ=6}
 local c=api.Contact(a,b,.01);assert(c.overlapsBeyondTolerance);near(c.minimumAxisDepth,.02)
end)
print(string.format('RESULT %d passed / 0 failed',passed))
