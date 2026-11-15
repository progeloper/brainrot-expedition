-- Read-only real native asset QA; call Verify(importRoot,{GroupId=optionalFullName}).
-- Match every oriented triangle corner's canonical position, source
-- UV and authored hard normal; native welding/reordering is permitted. Only
-- detached temporary EditableMeshes are allocated and always destroyed.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Camp_2_0","prototypeId":"CompactMapRoads","groupId":"Path_Camp_2_0","role":"Road","centre":[174.875468,0.07999995164573193,-251.70619349999998],"size":[108.24906158447266,0.0,80.99882507324219],"localBounds":[[-54.12453079223633,0.0,-40.499412536621094],[54.12453079223633,0.0,40.499412536621094]],"rgb":[232,201,138],"triangles":[[[-50.291526794433594,0.0,36.66640853881836,0.03540913760662079,0.04732174798846245,0.0,1.0,0.0],[-54.12453079223633,0.0,40.499412536621094,0.0,0.0,0.0,1.0,0.0],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-45.84406661987305,0.0,32.21894836425781,0.07649455219507217,0.10222943127155304,0.0,1.0,0.0],[-50.291526794433594,0.0,36.66640853881836,0.03540913760662079,0.04732174798846245,0.0,1.0,0.0]],[[-45.84406661987305,0.0,32.21894836425781,0.07649455219507217,0.10222943127155304,0.0,1.0,0.0],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-41.396610260009766,0.0,27.77149200439453,0.11757997423410416,0.15713711082935333,0.0,1.0,0.0]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-36.949153900146484,0.0,23.324033737182617,0.15866537392139435,0.21204479038715363,0.0,1.0,0.0],[-41.396610260009766,0.0,27.77149200439453,0.11757997423410416,0.15713711082935333,0.0,1.0,0.0]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-32.50169372558594,0.0,18.876577377319336,0.19975079596042633,0.2669524848461151,0.0,1.0,0.0],[-36.949153900146484,0.0,23.324033737182617,0.15866537392139435,0.21204479038715363,0.0,1.0,0.0]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154,0.0,1.0,0.0],[-32.50169372558594,0.0,18.876577377319336,0.19975079596042633,0.2669524848461151,0.0,1.0,0.0]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154,0.0,1.0,0.0],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944,0.0,1.0,0.0],[-23.606779098510742,0.0,9.981661796569824,0.2819216251373291,0.3767678141593933,0.0,1.0,0.0]],[[-23.606779098510742,0.0,9.981661796569824,0.2819216251373291,0.3767678141593933,0.0,1.0,0.0],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944,0.0,1.0,0.0],[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516,0.0,1.0,0.0]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154,0.0,1.0,0.0],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0,0.0,1.0,0.0],[-2.598392963409424,0.0,39.88496398925781,0.4759961664676666,0.007585912477225065,0.0,1.0,0.0]],[[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516,0.0,1.0,0.0],[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754,0.0,1.0,0.0],[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983,0.0,1.0,0.0]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154,0.0,1.0,0.0],[-2.598392963409424,0.0,39.88496398925781,0.4759961664676666,0.007585912477225065,0.0,1.0,0.0],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944,0.0,1.0,0.0]],[[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983,0.0,1.0,0.0],[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257,0.0,1.0,0.0],[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685,0.0,1.0,0.0]],[[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026,0.0,1.0,0.0],[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969,0.0,1.0,0.0],[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685,0.0,1.0,0.0]],[[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754,0.0,1.0,0.0],[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516,0.0,1.0,0.0],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944,0.0,1.0,0.0]],[[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257,0.0,1.0,0.0],[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983,0.0,1.0,0.0],[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754,0.0,1.0,0.0]],[[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187,0.0,1.0,0.0],[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253,0.0,1.0,0.0],[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969,0.0,1.0,0.0]],[[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685,0.0,1.0,0.0],[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257,0.0,1.0,0.0],[9.99264144897461,0.0,27.293928146362305,0.5923115611076355,0.16303303837776184,0.0,1.0,0.0]],[[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253,0.0,1.0,0.0],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247,0.0,1.0,0.0],[-4.696847915649414,0.0,-8.92827033996582,0.4566107392311096,0.6102271676063538,0.0,1.0,0.0]],[[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685,0.0,1.0,0.0],[9.99264144897461,0.0,27.293928146362305,0.5923115611076355,0.16303303837776184,0.0,1.0,0.0],[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026,0.0,1.0,0.0]],[[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247,0.0,1.0,0.0],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822,0.0,1.0,0.0],[-4.696847915649414,0.0,-8.92827033996582,0.4566107392311096,0.6102271676063538,0.0,1.0,0.0]],[[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969,0.0,1.0,0.0],[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026,0.0,1.0,0.0],[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187,0.0,1.0,0.0]],[[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531,0.0,1.0,0.0],[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106,0.0,1.0,0.0],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822,0.0,1.0,0.0]],[[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253,0.0,1.0,0.0],[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187,0.0,1.0,0.0],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247,0.0,1.0,0.0]],[[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0],[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0,0.0,1.0,0.0],[6.124532222747803,0.0,-37.52745056152344,0.5565781593322754,0.963308572769165,0.0,1.0,0.0]],[[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106,0.0,1.0,0.0],[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154,0.0,1.0,0.0],[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239,0.0,1.0,0.0]],[[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239,0.0,1.0,0.0],[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996,0.0,1.0,0.0],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0]],[[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531,0.0,1.0,0.0],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822,0.0,1.0,0.0],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247,0.0,1.0,0.0]],[[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154,0.0,1.0,0.0],[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106,0.0,1.0,0.0],[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531,0.0,1.0,0.0]],[[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996,0.0,1.0,0.0],[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239,0.0,1.0,0.0],[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154,0.0,1.0,0.0]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381,0.0,1.0,0.0],[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0,0.0,1.0,0.0],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0]],[[35.1141357421875,0.0,2.172433614730835,0.8243828415870667,0.4731794595718384,0.0,1.0,0.0],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0],[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996,0.0,1.0,0.0]],[[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0],[35.1141357421875,0.0,2.172433614730835,0.8243828415870667,0.4731794595718384,0.0,1.0,0.0],[38.70292282104492,0.0,-1.416351556777954,0.8575358390808105,0.5174860954284668,0.0,1.0,0.0]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381,0.0,1.0,0.0],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441,0.0,1.0,0.0],[38.70292282104492,0.0,-1.416351556777954,0.8575358390808105,0.5174860954284668,0.0,1.0,0.0]],[[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0,0.0,1.0,0.0],[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381,0.0,1.0,0.0],[54.12453079223633,0.0,-40.499412536621094,1.0,1.0,0.0,1.0,0.0]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381,0.0,1.0,0.0],[54.12453079223633,0.0,-1.527451515197754,1.0,0.5188577175140381,0.0,1.0,0.0],[54.12453079223633,0.0,-40.499412536621094,1.0,1.0,0.0,1.0,0.0]]]}]]====])
local POSITION_TOLERANCE=.01
local UV_TOLERANCE=1e-5
-- Native uploaded normals are quantized: actual axis readback includes +/-0.0004885197.
-- Permit that bounded precision loss; preserve one constant normal per triangle.
local NORMAL_TOLERANCE=.002
local NORMAL_ANGLE_TOLERANCE_DEGREES=.12
local NORMAL_MAGNITUDE_TOLERANCE=.001
local FACET_NORMAL_SPREAD_TOLERANCE=1e-6
local NORMAL_POLICY="BoundedNativeNormalQuantization_v1"
local function normalAngleDegrees(a,b)
    return math.deg(math.atan2(a:Cross(b).Magnitude,a:Dot(b)))
end
local function v3(row) return Vector3.new(row[1],row[2],row[3]) end
local function expectedNormal(row) return Vector3.new(row[6],row[7],row[8]) end
local function identityRotation(cf)
    local _,_,_,xx,xy,xz,yx,yy,yz,zx,zy,zz=cf:GetComponents()
    return math.max(math.abs(xx-1),math.abs(yy-1),math.abs(zz-1),math.abs(xy),math.abs(xz),math.abs(yx),math.abs(yz),math.abs(zx),math.abs(zy))<=1e-5
end
local function bucket(x,y,z) return tostring(math.floor(x))..","..tostring(math.floor(y))..","..tostring(math.floor(z)) end
local function compareCorners(actual,expected,shift)
    local maxPosition,maxUV,maxNormal,maxNormalAngle=0,0,0,0
    for i=1,3 do
        local e=expected[(i+shift-1)%3+1]
        local a=actual[i]
        local pe=(a.position-v3(e)).Magnitude
        local ue=(a.uv-Vector2.new(e[4],e[5])).Magnitude
        local authoredNormal=expectedNormal(e)
        local ne=(a.normal-authoredNormal).Magnitude
        local na=normalAngleDegrees(a.normal,authoredNormal)
        if pe>POSITION_TOLERANCE or ue>UV_TOLERANCE or ne>NORMAL_TOLERANCE or na>NORMAL_ANGLE_TOLERANCE_DEGREES then return false,pe,ue,ne,na end
        maxPosition=math.max(maxPosition,pe);maxUV=math.max(maxUV,ue);maxNormal=math.max(maxNormal,ne);maxNormalAngle=math.max(maxNormalAngle,na)
    end
    return true,maxPosition,maxUV,maxNormal,maxNormalAngle
end
local function readOne(part,row)
    local mesh=nil
    local report={id=row.id,prototypeId=row.prototypeId,groupId=row.groupId,meshId=tostring(part.MeshId),
        expectedTriangles=#row.triangles,passed=false,canonicalCentre=row.centre,sizeXYZ=row.size,
        actualPartCFrame={part.CFrame:GetComponents()},actualPartSize={part.Size.X,part.Size.Y,part.Size.Z},
        actualParent=part.Parent:GetFullName(),actualPartPath=part:GetFullName(),geometryCornersMatched=0,checkedCorners=0,
        temporaryEditableMeshesDestroyed=0,worldMutations=0,worldPlacementValidated=false,savedMaterialValidated=false,failures={}}
    local ok,result=xpcall(function()
        assert(tostring(part.MeshId):match("^rbxassetid://[1-9]%d*$"),"Native group has no real numeric MeshId")
        report.identityPartRotation=identityRotation(part.CFrame)
        assert(report.identityPartRotation,"Native part rotation differs from calibrated identity frame")
        local planarOK=row.role=="Road" and part.Size.Y>0 and part.Size.Y<=.05001 and (math.abs(part.Size.Y-.001)<=1e-5 or math.abs(part.Size.Y-.05)<=1e-5)
        assert(math.abs(part.Size.X-row.size[1])<=.01 and math.abs(part.Size.Z-row.size[3])<=.01 and (row.role=="Road" and planarOK or row.role~="Road" and math.abs(part.Size.Y-row.size[2])<=.01),"Native bounds/clamp differ from compact source")
        local ancestor=part.Parent
        local prototypeAncestor=false
        while ancestor and ancestor.Name~="CompactMap_ImportedAssets" do
            if ancestor.Name==row.prototypeId then prototypeAncestor=true end
            ancestor=ancestor.Parent
        end
        assert(prototypeAncestor,"Actual imported group lacks its exact prototype-ID ancestor")
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
        local boundsError=math.max((low-v3(row.localBounds[1])).Magnitude,(high-v3(row.localBounds[2])).Magnitude)
        report.maximumBoundsError=boundsError
        assert(boundsError<=POSITION_TOLERANCE,"Native local bounds are not canonical")
        local bins={}
        for i,triangle in ipairs(row.triangles) do
            local x,y,z=0,0,0
            for _,e in ipairs(triangle) do x+=e[1]/3;y+=e[2]/3;z+=e[3]/3 end
            local key=bucket(x,y,z);bins[key]=bins[key] or {};table.insert(bins[key],i)
        end
        local matched,referencedVertices={},{}
        local maxPosition,maxUV,maxNormal,maxNormalAngle,maxNormalMagnitude,maxFacetNormalSpread=0,0,0,0,0,0
        for _,faceId in ipairs(faceIds) do
            local vs,us,ns=mesh:GetFaceVertices(faceId),mesh:GetFaceUVs(faceId),mesh:GetFaceNormals(faceId)
            assert(#vs==3 and #us==3 and #ns==3,"Native face lacks3 positions/UVs/normals")
            local actual={};local cx,cy,cz=0,0,0
            for corner=1,3 do
                local p,uv,n=mesh:GetPosition(vs[corner]),mesh:GetUV(us[corner]),mesh:GetNormal(ns[corner])
                assert(uv and n,"Native corner UV/normal value is missing")
                local lengthError=math.abs(n.Magnitude-1)
                assert(lengthError<=NORMAL_MAGNITUDE_TOLERANCE,"Native corner normal magnitude exceeds bounded compression tolerance")
                maxNormalMagnitude=math.max(maxNormalMagnitude,lengthError)
                actual[corner]={position=p,uv=uv,normal=n};cx+=p.X/3;cy+=p.Y/3;cz+=p.Z/3
                referencedVertices[vs[corner]]=true
            end
            for corner=2,3 do
                local spread=(actual[corner].normal-actual[1].normal).Magnitude
                maxFacetNormalSpread=math.max(maxFacetNormalSpread,spread)
                assert(spread<=FACET_NORMAL_SPREAD_TOLERANCE,"Native triangle has interpolated/smoothed corner normals instead of one authored facet normal")
            end
            local cross=(actual[2].position-actual[1].position):Cross(actual[3].position-actual[1].position)
            assert(cross:Dot(actual[1].normal)>0,"Native face winding is degenerate or reversed from authored hard normal")
            local found=nil;local errorPosition,errorUV,errorNormal,errorNormalAngle=math.huge,math.huge,math.huge,math.huge
            for dx=-1,1 do for dy=-1,1 do for dz=-1,1 do
                for _,i in ipairs(bins[bucket(cx+dx,cy+dy,cz+dz)] or {}) do
                    if not matched[i] then
                        for shift=0,2 do
                            local pass,pe,ue,ne,na=compareCorners(actual,row.triangles[i],shift)
                            if pass then found=i;errorPosition=pe;errorUV=ue;errorNormal=ne;errorNormalAngle=na;break end
                        end
                    end
                    if found then break end
                end
                if found then break end
            end if found then break end end if found then break end end
            if not found then
                local best={positionError=math.huge}
                for i,triangle in ipairs(row.triangles) do for shift=0,2 do
                    local pe,ue,ne=0,0,0
                    for corner=1,3 do
                        local e=triangle[(corner+shift-1)%3+1];local a=actual[corner]
                        pe=math.max(pe,(a.position-v3(e)).Magnitude)
                        ue=math.max(ue,(a.uv-Vector2.new(e[4],e[5])).Magnitude)
                        ne=math.max(ne,(a.normal-expectedNormal(e)).Magnitude)
                    end
                    if pe<best.positionError then best={sourceTriangleIndex=i,shift=shift,positionError=pe,UVError=ue,normalError=ne,
                        sourceCorners=triangle,alreadyMatched=matched[i]==true} end
                end end
                local values={}
                for _,a in ipairs(actual) do table.insert(values,{a.position.X,a.position.Y,a.position.Z,a.uv.X,a.uv.Y,a.normal.X,a.normal.Y,a.normal.Z}) end
                report.firstMismatchFace={nativeFaceId=faceId,nativeCorners=values,nearestSourceGeometry=best}
            end
            assert(found,"No unused source triangle matches native corner geometry/UV/hard normals at face "..tostring(faceId))
            matched[found]=true
            maxPosition=math.max(maxPosition,errorPosition);maxUV=math.max(maxUV,errorUV);maxNormal=math.max(maxNormal,errorNormal);maxNormalAngle=math.max(maxNormalAngle,errorNormalAngle)
            report.geometryCornersMatched+=3;report.checkedCorners+=3
        end
        for i in ipairs(row.triangles) do assert(matched[i],"Expected source triangle is absent") end
        for _,id in ipairs(vertexIds) do assert(referencedVertices[id],"Native mesh contains unreferenced vertex") end
        report.maximumPositionError=maxPosition;report.maximumUVError=maxUV;report.maximumNormalError=maxNormal
        report.maximumNormalAngleErrorDegrees=maxNormalAngle;report.maximumNormalMagnitudeError=maxNormalMagnitude
        report.maximumWithinFaceNormalSpread=maxFacetNormalSpread;report.hardFacetFacesChecked=#faceIds
        report.normalQuantizationPolicy=NORMAL_POLICY;report.flatFacetNormalsPassed=true
        report.geometryCornersComplete=true;report.hardNormalsPassed=true;report.sourceUVValuesPassed=true
        report.sourceWindingPassed=true;report.passed=true
        return report
    end,debug.traceback)
    if mesh then mesh:Destroy();report.temporaryEditableMeshesDestroyed=1 end
    if not ok then table.insert(report.failures,tostring(result));report.passed=false end
    return report
end
local function Verify(importRoot,options)
    options=options or {}
    assert(game.PlaceId==91958083796436 and not RunService:IsRunning(),"Native prototype QA is authorized in DEV Edit only")
    assert(typeof(importRoot)=="Instance" and importRoot.Name=="CompactMap_ImportedAssets" and importRoot:IsDescendantOf(game:GetService("ServerStorage")),
        "Read only actual native import under ServerStorage.CompactMap_ImportedAssets")
    local found={}
    for _,item in ipairs(importRoot:GetDescendants()) do if item:IsA("BasePart") then
        assert(item:IsA("MeshPart"),"Imported prototype root contains a non-MeshPart BasePart")
        found[item.Name]=found[item.Name] or {};table.insert(found[item.Name],item)
    end end
    local report={status="Passed",groups={},failures={},worldMutations=0,temporaryEditableMeshesDestroyed=0,
        sourceSHA256="79939a7a01a7bc2d6099dc34d83d2a01c0cafbb96f4ef26cb7080116ff0764e1",
        roadGeometryHash="696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0",canonicalSourceSHA256="078a93ed83234709bec5799997d7ee41a8dd28cb39bc5fdd8ef18992d3353005",studioImportSHA256="bdd81be39782c1649694deecaf3264e5e82db25d9bb7ed7f783f05c1ab6fbd4e",
        positionToleranceStuds=POSITION_TOLERANCE,UVTolerance=UV_TOLERANCE,normalTolerance=NORMAL_TOLERANCE,
        normalAngleToleranceDegrees=NORMAL_ANGLE_TOLERANCE_DEGREES,normalMagnitudeTolerance=NORMAL_MAGNITUDE_TOLERANCE,
        withinFaceNormalSpreadTolerance=FACET_NORMAL_SPREAD_TOLERANCE,normalQuantizationPolicy=NORMAL_POLICY,
        normalPrecisionReason="Actual native normal readback uses bounded quantization; constant per-face normals, oriented source corner correspondence and all position/UV/winding limits remain required",
        expectedImportRoot=importRoot:GetFullName(),completeBatch=options.GroupId==nil,
        worldPlacementValidated=false,savedMaterialValidated=false,
        normalization="Native compensated local coordinates compare to canonical source float32 position/UV/hard normals; no post-readback axis or UV fix"}
    local names={}
    for _,row in ipairs(EXPECTED) do
        names[row.id]=true
        if not options.GroupId or options.GroupId==row.id then
            local matches=found[row.id]
            if not matches or #matches~=1 then table.insert(report.failures,"Expected exactly1 native group "..row.id);report.status="Failed"
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
        if #report.groups~=#EXPECTED then report.status="Failed";table.insert(report.failures,"Expected complete compact native mesh groups") end
    end
    report.checkedGroups=#report.groups
    report.checkedTriangleCorners=0;report.actualNativeTriangles=0
    for _,row in ipairs(report.groups) do
        report.checkedTriangleCorners+=row.checkedCorners
        report.actualNativeTriangles+=row.actualTriangles or 0
    end
    return report
end
return Verify
