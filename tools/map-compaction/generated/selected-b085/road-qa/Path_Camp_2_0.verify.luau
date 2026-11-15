-- Read-only native asset QA. Call returned Verify(importRoot, {GroupId=optionalName}).
-- Vertex/face IDs may be reordered or welded; match oriented triangle corner
-- geometry+UV tuples, preserving exact authored source UV values and per-corner UV seams.
-- Creates only detached temporary EditableMeshes and always destroys them.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Camp_2_0","localBounds":[[-54.12453079223633,0.0,-40.499412536621094],[54.12453079223633,0.0,40.499412536621094]],"pathRGB":[232,201,138],"pivot":[174.875468,0.07999995164573193,-251.70619349999998],"region":"Camp","size":[108.249064,0,80.99882699999998],"triangles":[[[-50.291526794433594,0.0,36.66640853881836,0.03540913760662079,0.04732174798846245],[-54.12453079223633,0.0,40.499412536621094,0.0,0.0],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-45.84406661987305,0.0,32.21894836425781,0.07649455219507217,0.10222943127155304],[-50.291526794433594,0.0,36.66640853881836,0.03540913760662079,0.04732174798846245]],[[-45.84406661987305,0.0,32.21894836425781,0.07649455219507217,0.10222943127155304],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-41.396610260009766,0.0,27.77149200439453,0.11757997423410416,0.15713711082935333]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-36.949153900146484,0.0,23.324033737182617,0.15866537392139435,0.21204479038715363],[-41.396610260009766,0.0,27.77149200439453,0.11757997423410416,0.15713711082935333]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-32.50169372558594,0.0,18.876577377319336,0.19975079596042633,0.2669524848461151],[-36.949153900146484,0.0,23.324033737182617,0.15866537392139435,0.21204479038715363]],[[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154],[-32.50169372558594,0.0,18.876577377319336,0.19975079596042633,0.2669524848461151]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944],[-23.606779098510742,0.0,9.981661796569824,0.2819216251373291,0.3767678141593933]],[[-23.606779098510742,0.0,9.981661796569824,0.2819216251373291,0.3767678141593933],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944],[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154],[-3.2128429412841797,0.0,40.499412536621094,0.4703198969364166,0.0],[-2.598392963409424,0.0,39.88496398925781,0.4759961664676666,0.007585912477225065]],[[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516],[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754],[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983]],[[-28.054237365722656,0.0,14.429118156433105,0.24083620309829712,0.3218601644039154],[-2.598392963409424,0.0,39.88496398925781,0.4759961664676666,0.007585912477225065],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944]],[[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983],[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257],[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685]],[[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026],[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969],[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685]],[[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754],[-19.15932273864746,0.0,5.53420352935791,0.3230070471763611,0.431675523519516],[1.8490639925003052,0.0,35.437503814697266,0.5170815587043762,0.062493596225976944]],[[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257],[-18.603389739990234,0.0,4.978271484375,0.3281427025794983,0.43853896856307983],[6.29652214050293,0.0,30.990047454833984,0.5581669807434082,0.11740127950906754]],[[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187],[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253],[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969]],[[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685],[6.85245418548584,0.0,30.43411636352539,0.5633026361465454,0.12426473945379257],[9.99264144897461,0.0,27.293928146362305,0.5923115611076355,0.16303303837776184]],[[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247],[-4.696847915649414,0.0,-8.92827033996582,0.4566107392311096,0.6102271676063538]],[[-15.463203430175781,0.0,1.8380844593048096,0.3571516275405884,0.4773072600364685],[9.99264144897461,0.0,27.293928146362305,0.5923115611076355,0.16303303837776184],[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026]],[[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822],[-4.696847915649414,0.0,-8.92827033996582,0.4566107392311096,0.6102271676063538]],[[-11.874418258666992,0.0,-1.7507004737854004,0.39030465483665466,0.5216138958930969],[13.581425666809082,0.0,23.705142974853516,0.6254646182060242,0.20733967423439026],[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187]],[[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531],[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822]],[[-8.285633087158203,0.0,-5.3394856452941895,0.42345768213272095,0.5659205317497253],[17.170211791992188,0.0,20.116357803344727,0.6586176156997681,0.2516463100910187],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247]],[[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441],[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0],[6.124532222747803,0.0,-37.52745056152344,0.5565781593322754,0.963308572769165]],[[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106],[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154],[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239]],[[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239],[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441]],[[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531],[-1.108062982559204,0.0,-12.51705551147461,0.4897637665271759,0.6545338034629822],[20.758995056152344,0.0,16.527572631835938,0.6917706727981567,0.2959529161453247]],[[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154],[2.480721950531006,0.0,-16.1058406829834,0.5229167938232422,0.6988404393196106],[24.347780227661133,0.0,12.938788414001465,0.7249237298965454,0.3402595520019531]],[[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996],[6.069507122039795,0.0,-19.694625854492188,0.5560698509216309,0.743147075176239],[27.936565399169922,0.0,9.350003242492676,0.7580767273902893,0.38456618785858154]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381],[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441]],[[35.1141357421875,0.0,2.172433614730835,0.8243828415870667,0.4731794595718384],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441],[31.52535057067871,0.0,5.761218547821045,0.791229784488678,0.42887282371520996]],[[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441],[35.1141357421875,0.0,2.172433614730835,0.8243828415870667,0.4731794595718384],[38.70292282104492,0.0,-1.416351556777954,0.8575358390808105,0.5174860954284668]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381],[6.124532222747803,0.0,-19.749650955200195,0.5565781593322754,0.7438263893127441],[38.70292282104492,0.0,-1.416351556777954,0.8575358390808105,0.5174860954284668]],[[22.12453269958496,0.0,-40.499412536621094,0.7043854594230652,1.0],[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381],[54.12453079223633,0.0,-40.499412536621094,1.0,1.0]],[[38.814022064208984,0.0,-1.527451515197754,0.858562171459198,0.5188577175140381],[54.12453079223633,0.0,-1.527451515197754,1.0,0.5188577175140381],[54.12453079223633,0.0,-40.499412536621094,1.0,1.0]]]}]]====])
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
    assert((importRoot.Name=="CompactMap_ImportedRoads" or importRoot.Name=="CompactMapRoads" and importRoot.Parent.Name=="CompactMap_ImportedAssets") and importRoot:IsDescendantOf(game:GetService("ServerStorage")),
           "Read actual native import under ServerStorage.CompactMap_ImportedRoads only")
    local found={};local all=importRoot:GetDescendants()
    if importRoot:IsA("MeshPart") then table.insert(all,importRoot) end
    for _,item in ipairs(all) do if item:IsA("MeshPart") then
        found[item.Name]=found[item.Name] or {};table.insert(found[item.Name],item)
    end end
    local report={status="Passed",groups={},failures={},worldMutations=0,temporaryEditableMeshesDestroyed=0,
        canonicalSourceSHA256="73c1deb0ee7abe3b758ed67ea68f57f4e4dcc42137de3e692939040961c24bdf",studioImportSHA256="bdd81be39782c1649694deecaf3264e5e82db25d9bb7ed7f783f05c1ab6fbd4e",
        sourceRoutePointSHA256="7c0411ac82bd863df409dcf71ebc49f6649564dcb30aa2a6a9e6e59408dd20a5",
        routeGeometryHash="696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0",
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
