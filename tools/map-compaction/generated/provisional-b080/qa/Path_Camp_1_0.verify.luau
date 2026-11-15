-- Read-only native asset QA. Call returned Verify(importRoot, {GroupId=optionalName}).
-- Vertex/face IDs may be reordered or welded; match oriented triangle corner
-- geometry+UV tuples, preserving exact authored source UV values and per-corner UV seams.
-- Creates only detached temporary EditableMeshes and always destroys them.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Camp_1_0","localBounds":[[-169.5830535888672,0.0,-36.62813186645508],[169.5830535888672,0.0,36.62813186645508]],"pathRGB":[232,201,138],"pivot":[-81.416949,0.07999995164573193,-237.50270849999998],"region":"Camp","size":[339.166102,0,73.25626499999998],"triangles":[[[-165.71389770507812,0.0,-36.62813186645508,0.011407858692109585,1.0],[-169.5830535888672,0.0,-36.62813186645508,0.0,1.0],[-169.5830535888672,0.0,-0.6281325221061707,0.0,0.5085744261741638]],[[-165.71389770507812,0.0,-0.6281325221061707,0.011407858692109585,0.5085744261741638],[-165.71389770507812,0.0,-36.62813186645508,0.011407858692109585,1.0],[-169.5830535888672,0.0,-0.6281325221061707,0.0,0.5085744261741638]],[[-165.71389770507812,0.0,-36.62813186645508,0.011407858692109585,1.0],[-165.71389770507812,0.0,-0.6281325221061707,0.011407858692109585,0.5085744261741638],[-157.5830535888672,0.0,-36.62813186645508,0.03538089245557785,1.0]],[[-157.5830535888672,0.0,-0.6281325221061707,0.03538089245557785,0.5085744261741638],[-157.5830535888672,0.0,-36.62813186645508,0.03538089245557785,1.0],[-165.71389770507812,0.0,-0.6281325221061707,0.011407858692109585,0.5085744261741638]],[[-155.16973876953125,0.0,-0.6281325221061707,0.04249633103609085,0.5085744261741638],[-157.5830535888672,0.0,-36.62813186645508,0.03538089245557785,1.0],[-157.5830535888672,0.0,-0.6281325221061707,0.03538089245557785,0.5085744261741638]],[[-157.5830535888672,0.0,-36.62813186645508,0.03538089245557785,1.0],[-155.16973876953125,0.0,-0.6281325221061707,0.04249633103609085,0.5085744261741638],[-151.5830535888672,0.0,-36.62813186645508,0.053071342408657074,1.0]],[[-151.5830535888672,0.0,-36.62813186645508,0.053071342408657074,1.0],[-155.16973876953125,0.0,-0.6281325221061707,0.04249633103609085,0.5085744261741638],[-147.71389770507812,0.0,-36.62813186645508,0.06447920203208923,1.0]],[[-129.71389770507812,0.0,-26.08397674560547,0.11755054444074631,0.8560647964477539],[-155.16973876953125,0.0,-0.6281325221061707,0.04249633103609085,0.5085744261741638],[-152.21751403808594,0.0,2.3240885734558105,0.051200684159994125,0.4682745337486267]],[[-155.16973876953125,0.0,-0.6281325221061707,0.04249633103609085,0.5085744261741638],[-129.71389770507812,0.0,-26.08397674560547,0.11755054444074631,0.8560647964477539],[-147.71389770507812,0.0,-36.62813186645508,0.06447920203208923,1.0]],[[-148.92779541015625,0.0,5.613808631896973,0.060900118201971054,0.42336753010749817],[-123.47195434570312,0.0,-19.8420352935791,0.1359543353319168,0.7708578705787659],[-152.21751403808594,0.0,2.3240885734558105,0.051200684159994125,0.4682745337486267]],[[-129.71389770507812,0.0,-26.08397674560547,0.11755054444074631,0.8560647964477539],[-139.5830535888672,0.0,-36.62813186645508,0.08845223486423492,1.0],[-147.71389770507812,0.0,-36.62813186645508,0.06447920203208923,1.0]],[[-145.63807678222656,0.0,8.90352725982666,0.07059955596923828,0.37846052646636963],[-120.18223571777344,0.0,-16.552316665649414,0.14565376937389374,0.7259508371353149],[-148.92779541015625,0.0,5.613808631896973,0.060900118201971054,0.42336753010749817]],[[-129.71389770507812,0.0,-26.08397674560547,0.11755054444074631,0.8560647964477539],[-152.21751403808594,0.0,2.3240885734558105,0.051200684159994125,0.4682745337486267],[-126.76167297363281,0.0,-23.131755828857422,0.1262548863887787,0.8157649040222168]],[[-142.34835815429688,0.0,12.19324779510498,0.08029899001121521,0.3335535228252411],[-116.89250946044922,0.0,-13.262596130371094,0.15535320341587067,0.6810438632965088],[-145.63807678222656,0.0,8.90352725982666,0.07059955596923828,0.37846052646636963]],[[-126.76167297363281,0.0,-23.131755828857422,0.1262548863887787,0.8157649040222168],[-152.21751403808594,0.0,2.3240885734558105,0.051200684159994125,0.4682745337486267],[-123.47195434570312,0.0,-19.8420352935791,0.1359543353319168,0.7708578705787659]],[[-129.71389770507812,0.0,-26.08397674560547,0.11755054444074631,0.8560647964477539],[-129.71389770507812,0.0,-36.62813186645508,0.11755054444074631,1.0],[-139.5830535888672,0.0,-36.62813186645508,0.08845223486423492,1.0]],[[-139.0586395263672,0.0,15.482967376708984,0.08999842405319214,0.28864651918411255],[-113.60279083251953,0.0,-9.972877502441406,0.1650526374578476,0.6361368298530579],[-142.34835815429688,0.0,12.19324779510498,0.08029899001121521,0.3335535228252411]],[[-123.47195434570312,0.0,-19.8420352935791,0.1359543353319168,0.7708578705787659],[-148.92779541015625,0.0,5.613808631896973,0.060900118201971054,0.42336753010749817],[-120.18223571777344,0.0,-16.552316665649414,0.14565376937389374,0.7259508371353149]],[[-135.7689208984375,0.0,18.772686004638672,0.09969785809516907,0.243739515542984],[-110.31307220458984,0.0,-6.683157444000244,0.17475207149982452,0.5912298560142517],[-139.0586395263672,0.0,15.482967376708984,0.08999842405319214,0.28864651918411255]],[[-120.18223571777344,0.0,-16.552316665649414,0.14565376937389374,0.7259508371353149],[-145.63807678222656,0.0,8.90352725982666,0.07059955596923828,0.37846052646636963],[-116.89250946044922,0.0,-13.262596130371094,0.15535320341587067,0.6810438632965088]],[[-132.4792022705078,0.0,22.062406539916992,0.109397292137146,0.19883249700069427],[-107.02335357666016,0.0,-3.393437385559082,0.18445150554180145,0.5463228225708008],[-135.7689208984375,0.0,18.772686004638672,0.09969785809516907,0.243739515542984]],[[-116.89250946044922,0.0,-13.262596130371094,0.15535320341587067,0.6810438632965088],[-142.34835815429688,0.0,12.19324779510498,0.08029899001121521,0.3335535228252411],[-113.60279083251953,0.0,-9.972877502441406,0.1650526374578476,0.6361368298530579]],[[-129.18948364257812,0.0,25.35212516784668,0.11909672617912292,0.15392549335956573],[-103.73363494873047,0.0,-0.10371849685907364,0.19415093958377838,0.5014158487319946],[-132.4792022705078,0.0,22.062406539916992,0.109397292137146,0.19883249700069427]],[[-113.60279083251953,0.0,-9.972877502441406,0.1650526374578476,0.6361368298530579],[-139.0586395263672,0.0,15.482967376708984,0.08999842405319214,0.28864651918411255],[-110.31307220458984,0.0,-6.683157444000244,0.17475207149982452,0.5912298560142517]],[[-126.31097412109375,0.0,28.23063087463379,0.12758374214172363,0.11463186144828796],[-100.8551254272461,0.0,2.7747864723205566,0.2026379406452179,0.46212220191955566],[-129.18948364257812,0.0,25.35212516784668,0.11909672617912292,0.15392549335956573]],[[-110.31307220458984,0.0,-6.683157444000244,0.17475207149982452,0.5912298560142517],[-135.7689208984375,0.0,18.772686004638672,0.09969785809516907,0.243739515542984],[-107.02335357666016,0.0,-3.393437385559082,0.18445150554180145,0.5463228225708008]],[[-125.79571533203125,0.0,28.74588394165039,0.1291029155254364,0.10759827494621277],[-100.33987426757812,0.0,3.2900404930114746,0.20415712893009186,0.45508861541748047],[-126.31097412109375,0.0,28.23063087463379,0.12758374214172363,0.11463186144828796]],[[-121.6736831665039,0.0,32.867919921875,0.14125634729862213,0.0513295903801918],[-96.21784210205078,0.0,7.412074565887451,0.2163105607032776,0.3988199234008789],[-125.79571533203125,0.0,28.74588394165039,0.1291029155254364,0.10759827494621277]],[[-107.02335357666016,0.0,-3.393437385559082,0.18445150554180145,0.5463228225708008],[-132.4792022705078,0.0,22.062406539916992,0.109397292137146,0.19883249700069427],[-103.73363494873047,0.0,-0.10371849685907364,0.19415093958377838,0.5014158487319946]],[[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-96.21784210205078,0.0,7.412074565887451,0.2163105607032776,0.3988199234008789],[-121.6736831665039,0.0,32.867919921875,0.14125634729862213,0.0513295903801918]],[[-103.73363494873047,0.0,-0.10371849685907364,0.19415093958377838,0.5014158487319946],[-129.18948364257812,0.0,25.35212516784668,0.11909672617912292,0.15392549335956573],[-100.8551254272461,0.0,2.7747864723205566,0.2026379406452179,0.46212220191955566]],[[-100.8551254272461,0.0,2.7747864723205566,0.2026379406452179,0.46212220191955566],[-126.31097412109375,0.0,28.23063087463379,0.12758374214172363,0.11463186144828796],[-100.33987426757812,0.0,3.2900404930114746,0.20415712893009186,0.45508861541748047]],[[-100.33987426757812,0.0,3.2900404930114746,0.20415712893009186,0.45508861541748047],[-125.79571533203125,0.0,28.74588394165039,0.1291029155254364,0.10759827494621277],[-96.21784210205078,0.0,7.412074565887451,0.2163105607032776,0.3988199234008789]],[[-96.21784210205078,0.0,7.412074565887451,0.2163105607032776,0.3988199234008789],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-92.09580993652344,0.0,11.53410816192627,0.22846399247646332,0.34255123138427734]],[[-92.09580993652344,0.0,11.53410816192627,0.22846399247646332,0.34255123138427734],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-87.97377014160156,0.0,15.656142234802246,0.24061743915081024,0.2862825393676758]],[[-87.97377014160156,0.0,15.656142234802246,0.24061743915081024,0.2862825393676758],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-83.85173797607422,0.0,19.77817726135254,0.25277087092399597,0.2300138622522354]],[[-83.85173797607422,0.0,19.77817726135254,0.25277087092399597,0.2300138622522354],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-79.72970581054688,0.0,23.900211334228516,0.2649243175983429,0.17374517023563385]],[[-79.72970581054688,0.0,23.900211334228516,0.2649243175983429,0.17374517023563385],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-75.60767364501953,0.0,28.022245407104492,0.27707773447036743,0.11747647821903229]],[[-75.60767364501953,0.0,28.022245407104492,0.27707773447036743,0.11747647821903229],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-71.48563385009766,0.0,32.1442756652832,0.28923118114471436,0.06120780110359192]],[[-71.48563385009766,0.0,32.1442756652832,0.28923118114471436,0.06120780110359192],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-67.36360168457031,0.0,36.26631164550781,0.3013846278190613,0.004939113277941942]],[[-67.36360168457031,0.0,36.26631164550781,0.3013846278190613,0.004939113277941942],[-117.91346740722656,0.0,36.62813186645508,0.1523429900407791,0.0],[-67.00178527832031,0.0,36.62813186645508,0.30245140194892883,0.0]],[[2.5816550254821777,0.0,26.323047637939453,0.5076117515563965,0.1406717300415039],[-17.418344497680664,0.0,26.323047637939453,0.44864362478256226,0.1406717300415039],[-17.418344497680664,0.0,36.62813186645508,0.44864362478256226,0.0]],[[-17.418344497680664,0.0,36.62813186645508,0.44864362478256226,0.0],[2.5816550254821777,0.0,36.62813186645508,0.5076117515563965,0.0],[2.5816550254821777,0.0,26.323047637939453,0.5076117515563965,0.1406717300415039]],[[87.38165283203125,0.0,26.323047637939453,0.7576367855072021,0.1406717300415039],[67.38165283203125,0.0,26.323047637939453,0.6986685991287231,0.1406717300415039],[67.38165283203125,0.0,36.62813186645508,0.6986685991287231,0.0]],[[67.38165283203125,0.0,36.62813186645508,0.6986685991287231,0.0],[87.38165283203125,0.0,36.62813186645508,0.7576367855072021,0.0],[87.38165283203125,0.0,26.323047637939453,0.7576367855072021,0.1406717300415039]],[[169.5830535888672,0.0,26.323047637939453,1.0,0.1406717300415039],[149.5830535888672,0.0,26.323047637939453,0.941031813621521,0.1406717300415039],[149.5830535888672,0.0,36.62813186645508,0.941031813621521,0.0]],[[149.5830535888672,0.0,36.62813186645508,0.941031813621521,0.0],[169.5830535888672,0.0,36.62813186645508,1.0,0.0],[169.5830535888672,0.0,26.323047637939453,1.0,0.1406717300415039]]]}]]====])
local POSITION_TOLERANCE=.01
local UV_TOLERANCE=1e-5
local NORMAL_TOLERANCE=1e-5
local function planarBoundingThickness(value)
    return type(value)=="number" and value==value and value>0 and value<=.05001
        and (math.abs(value-.001)<=1e-5 or math.abs(value-.05)<=1e-5)
end
local function v3(row) return Vector3.new(row[1],row[2],row[3]) end
local function identityRotation(cf)
    local _,_,_,xx,xy,xz,yx,yy,yz,zx,zy,zz=cf:GetComponents()
    return math.max(math.abs(xx-1),math.abs(yy-1),math.abs(zz-1),math.abs(xy),math.abs(xz),
                    math.abs(yx),math.abs(yz),math.abs(zx),math.abs(zy))<=1e-5
end
local function bucket(x,z) return tostring(math.floor(x))..","..tostring(math.floor(z)) end
local function compareCorners(actual,expected,shift)
    local maxPosition,maxUV=0,0
    for i=1,3 do
        local e=expected[(i+shift-1)%3+1]
        local a=actual[i]
        local pe=(a.position-v3(e)).Magnitude
        local ue=(a.uv-Vector2.new(e[4],e[5])).Magnitude
        if pe>POSITION_TOLERANCE or ue>UV_TOLERANCE then return false,pe,ue end
        maxPosition=math.max(maxPosition,pe);maxUV=math.max(maxUV,ue)
    end
    return true,maxPosition,maxUV
end
local function readOne(part,row)
    local mesh=nil
    local report={id=row.id,meshId=tostring(part.MeshId),expectedTriangles=#row.triangles,passed=false,
                  expectedWorldPivot=row.pivot,actualPartCFrame={part.CFrame:GetComponents()},
                  actualPartSize={part.Size.X,part.Size.Y,part.Size.Z},actualParent=part.Parent:GetFullName(),
                  geometryCornersMatched=0,sourceUVValuesPassed=false,upwardNormalsPassed=false,upwardWindingPassed=false,
                  temporaryEditableMeshesDestroyed=0,worldMutations=0,worldPlacementValidated=false,textureMapsValidated=false,failures={}}
    local ok,result=xpcall(function()
        assert(tostring(part.MeshId):match("^rbxassetid://[1-9]%d*$"),"Native mesh has no real numeric MeshId")
        report.identityPartRotation=identityRotation(part.CFrame)
        assert(report.identityPartRotation,"Native part rotation differs from calibrated identity frame")
        assert(math.abs(part.Size.X-row.size[1])<=.01 and math.abs(part.Size.Z-row.size[3])<=.01,
               "Native part XZ size differs from exact final bounds")
        assert(planarBoundingThickness(part.Size.Y),"Native planar bounding thickness must be finite and positive near .001 or .05")
        mesh=AssetService:CreateEditableMeshAsync(Content.fromUri(tostring(part.MeshId)),{FixedSize=true})
        assert(mesh,"Temporary native EditableMesh allocation unavailable")
        local vertexIds,faceIds=mesh:GetVertices(),mesh:GetFaces()
        report.actualVertices=#vertexIds;report.actualTriangles=#faceIds
        assert(#faceIds==#row.triangles,"Native/source triangle count differs")
        local low=Vector3.new(math.huge,math.huge,math.huge)
        local high=Vector3.new(-math.huge,-math.huge,-math.huge)
        for _,id in ipairs(vertexIds) do
            local p=mesh:GetPosition(id)
            low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
            high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
        end
        report.actualMeshBoundsLocal={{low.X,low.Y,low.Z},{high.X,high.Y,high.Z}}
        report.actualEditableSize={mesh:GetSize().X,mesh:GetSize().Y,mesh:GetSize().Z}
        local boundsError=math.max((low-v3(row.localBounds[1])).Magnitude,(high-v3(row.localBounds[2])).Magnitude)
        report.maximumBoundsError=boundsError
        assert(boundsError<=POSITION_TOLERANCE,"Native local bounds/plane are not canonical")
        report.intendedWorldBounds={{low.X+row.pivot[1],low.Y+row.pivot[2],low.Z+row.pivot[3]},
                                    {high.X+row.pivot[1],high.Y+row.pivot[2],high.Z+row.pivot[3]}}
        local bins={}
        for i,triangle in ipairs(row.triangles) do
            local x,z=0,0
            for _,e in ipairs(triangle) do x+=e[1]/3;z+=e[3]/3 end
            local key=bucket(x,z);bins[key]=bins[key] or {};table.insert(bins[key],i)
        end
        local matched={};local maxPosition,maxUV,maxNormal=0,0,0
        local uvLow,uvHigh=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
        local referencedVertices={}
        local probe={}
        for _,faceId in ipairs(faceIds) do
            local vs,us,ns=mesh:GetFaceVertices(faceId),mesh:GetFaceUVs(faceId),mesh:GetFaceNormals(faceId)
            assert(#vs==3 and #us==3 and #ns==3,"Native face lacks3 positions/UVs/normals")
            local actual={};local cx,cz=0,0
            for corner=1,3 do
                local p,uv,n=mesh:GetPosition(vs[corner]),mesh:GetUV(us[corner]),mesh:GetNormal(ns[corner])
                assert(uv and n,"Native corner UV/normal value is missing")
                local ne=(n-Vector3.new(0,1,0)).Magnitude
                if ne>NORMAL_TOLERANCE then report.firstBadNormal={nativeFaceId=faceId,corner=corner,normal={n.X,n.Y,n.Z},error=ne} end
                assert(ne<=NORMAL_TOLERANCE,"Native corner normal is not authored+Y")
                maxNormal=math.max(maxNormal,ne)
                assert(uv.X>=-UV_TOLERANCE and uv.Y>=-UV_TOLERANCE and uv.X<=1+UV_TOLERANCE and uv.Y<=1+UV_TOLERANCE,
                       "Native UV is outside0..1")
                uvLow=Vector2.new(math.min(uvLow.X,uv.X),math.min(uvLow.Y,uv.Y))
                uvHigh=Vector2.new(math.max(uvHigh.X,uv.X),math.max(uvHigh.Y,uv.Y))
                actual[corner]={position=p,uv=uv,normal=n};cx+=p.X/3;cz+=p.Z/3
                referencedVertices[vs[corner]]=true
            end
            assert((actual[2].position-actual[1].position):Cross(actual[3].position-actual[1].position).Y>0,
                   "Native road triangle is downward or degenerate")
            local found=nil;local errorPosition,errorUV=math.huge,math.huge
            for dx=-1,1 do for dz=-1,1 do
                for _,i in ipairs(bins[bucket(cx+dx,cz+dz)] or {}) do
                    if not matched[i] then
                        for shift=0,2 do
                            local pass,pe,ue=compareCorners(actual,row.triangles[i],shift)
                            if pass then found=i;errorPosition=pe;errorUV=ue;break end
                        end
                    end
                    if found then break end
                end
                if found then break end
            end if found then break end end
            if not found then
                local best={positionError=math.huge}
                for i,triangle in ipairs(row.triangles) do for shift=0,2 do
                    local pe,ue,flippedV=0,0,0
                    for corner=1,3 do
                        local e=triangle[(corner+shift-1)%3+1];local a=actual[corner]
                        pe=math.max(pe,(a.position-v3(e)).Magnitude)
                        ue=math.max(ue,(a.uv-Vector2.new(e[4],e[5])).Magnitude)
                        flippedV=math.max(flippedV,(a.uv-Vector2.new(e[4],1-e[5])).Magnitude)
                    end
                    if pe<best.positionError then best={sourceTriangleIndex=i,shift=shift,positionError=pe,UVError=ue,UVVFlippedError=flippedV,
                        sourceCorners=triangle,alreadyMatched=matched[i]==true} end
                end end
                local values={}
                for _,a in ipairs(actual) do table.insert(values,{a.position.X,a.position.Y,a.position.Z,a.uv.X,a.uv.Y}) end
                report.firstMismatchFace={nativeFaceId=faceId,nativeCorners=values,nearestSourceGeometry=best}
            end
            assert(found,"No unused source triangle matches native face geometry+source UV at face "..tostring(faceId))
            matched[found]=true
            maxPosition=math.max(maxPosition,errorPosition);maxUV=math.max(maxUV,errorUV)
            report.geometryCornersMatched+=3
            if #probe==0 then
                for _,a in ipairs(actual) do table.insert(probe,{canonicalWorldXYZ={a.position.X+row.pivot[1],a.position.Y+row.pivot[2],a.position.Z+row.pivot[3]},UV={a.uv.X,a.uv.Y}}) end
            end
        end
        for i in ipairs(row.triangles) do assert(matched[i],"Expected source triangle is absent") end
        for _,id in ipairs(vertexIds) do assert(referencedVertices[id],"Native mesh contains unreferenced vertex") end
        report.maximumPositionError=maxPosition;report.maximumUVError=maxUV;report.maximumNormalError=maxNormal
        report.actualUVRange={{uvLow.X,uvLow.Y},{uvHigh.X,uvHigh.Y}}
        report.nativeTriangleCornerProbe=probe
        report.geometryCornersComplete=true;report.sourceUVValuesPassed=true;report.upwardNormalsPassed=true
        report.upwardWindingPassed=true;report.passed=true
        return report
    end,debug.traceback)
    if mesh then mesh:Destroy();report.temporaryEditableMeshesDestroyed=1 end
    if not ok then table.insert(report.failures,tostring(result));report.passed=false end
    return report
end
local function Verify(importRoot,options)
    options=options or {}
    assert(game.PlaceId==91958083796436 and not RunService:IsRunning(),"Native road QA is authorized in DEV Edit only")
    assert(typeof(importRoot)=="Instance","Supply ServerStorage.CompactMap_ImportedRoads after native import is complete")
    assert(importRoot.Name=="CompactMap_ImportedRoads" and importRoot:IsDescendantOf(game:GetService("ServerStorage")),
           "Read actual native import under ServerStorage.CompactMap_ImportedRoads only")
    local found={};local all=importRoot:GetDescendants()
    if importRoot:IsA("MeshPart") then table.insert(all,importRoot) end
    for _,item in ipairs(all) do if item:IsA("MeshPart") then
        found[item.Name]=found[item.Name] or {};table.insert(found[item.Name],item)
    end end
    local report={status="Passed",groups={},failures={},worldMutations=0,temporaryEditableMeshesDestroyed=0,
        canonicalSourceSHA256="a9520966d90b9955285786839991af17486cc53e09012e98589d64a6fd6670c3",studioImportSHA256="352ec7d09d9884a4ecc8c98fbe10006d4bbd770c2d6104ffa0a5eb3f254a87b1",
        sourceRoutePointSHA256="7c0411ac82bd863df409dcf71ebc49f6649564dcb30aa2a6a9e6e59408dd20a5",
        routeGeometryHash="8b52d62328fdba429c4124e911b2a59e95550f3682ec37c95c8db782a08dd484",
        positionToleranceStuds=POSITION_TOLERANCE,UVTolerance=UV_TOLERANCE,normalTolerance=NORMAL_TOLERANCE,
        normalization="Native compensated mesh local coordinates compare directly to canonical Roblox GLB float32 corners; no UV flip allowed",
        expectedImportRoot=importRoot:GetFullName(),completeBatch=options.GroupId==nil,
        worldPlacementValidated=false,textureMapsValidated=false}
    local names={}
    for _,row in ipairs(EXPECTED) do
        names[row.id]=true
        if not options.GroupId or options.GroupId==row.id then
            local matches=found[row.id]
            if not matches or #matches~=1 then
                table.insert(report.failures,"Expected exactly1 native group "..row.id);report.status="Failed"
            else
                local r=readOne(matches[1],row);table.insert(report.groups,r)
                report.temporaryEditableMeshesDestroyed+=r.temporaryEditableMeshesDestroyed
                if not r.passed then table.insert(report.failures,row.id);report.status="Failed" end
            end
        end
    end
    if options.GroupId then assert(names[options.GroupId],"Unknown expected native group") end
    if not options.GroupId then
        for name in pairs(found) do if not names[name] then table.insert(report.failures,"Unexpected native MeshPart "..name);report.status="Failed" end end
        if #report.groups~=27 then report.status="Failed";table.insert(report.failures,"Expected27 complete native mesh groups") end
    end
    report.checkedGroups=#report.groups
    report.checkedTriangleCorners=0
    for _,row in ipairs(report.groups) do report.checkedTriangleCorners+=row.geometryCornersMatched end
    return report
end
return Verify
