-- Read-only real native asset QA; call Verify(importRoot,{GroupId=optionalFullName}).
-- Match every oriented triangle corner's canonical position, source
-- UV and authored hard normal; native welding/reordering is permitted. Only
-- detached temporary EditableMeshes are allocated and always destroyed.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Volcano_2_2","prototypeId":"CompactMapRoads","groupId":"Path_Volcano_2_2","role":"Road","centre":[358.0,0.07999995164573193,184.33644850000002],"size":[258.0,0.0,35.32710266113281],"localBounds":[[-129.0,0.0,-17.663551330566406],[129.0,0.0,17.663551330566406]],"rgb":[157,127,143],"triangles":[[[-129.0,0.0,-17.663551330566406,0.0,1.0,0.0,1.0,0.0],[-129.0,0.0,12.897196769714355,0.0,0.1349206268787384,0.0,1.0,0.0],[-123.0,0.0,12.897196769714355,0.023255813866853714,0.1349206268787384,0.0,1.0,0.0]],[[-129.0,0.0,-17.663551330566406,0.0,1.0,0.0,1.0,0.0],[-123.0,0.0,12.897196769714355,0.023255813866853714,0.1349206268787384,0.0,1.0,0.0],[-111.0,0.0,12.897196769714355,0.06976744532585144,0.1349206268787384,0.0,1.0,0.0]],[[-129.0,0.0,-17.663551330566406,0.0,1.0,0.0,1.0,0.0],[-111.0,0.0,12.897196769714355,0.06976744532585144,0.1349206268787384,0.0,1.0,0.0],[93.0,0.0,12.897196769714355,0.8604651093482971,0.1349206268787384,0.0,1.0,0.0]],[[93.0,0.0,12.897196769714355,0.8604651093482971,0.1349206268787384,0.0,1.0,0.0],[129.0,0.0,-17.663551330566406,1.0,1.0,0.0,1.0,0.0],[-129.0,0.0,-17.663551330566406,0.0,1.0,0.0,1.0,0.0]],[[97.0,0.0,12.897196769714355,0.8759689927101135,0.1349206268787384,0.0,1.0,0.0],[97.0,0.0,17.663551330566406,0.8759689927101135,0.0,0.0,1.0,0.0],[111.0,0.0,17.663551330566406,0.930232584476471,0.0,0.0,1.0,0.0]],[[129.0,0.0,-17.663551330566406,1.0,1.0,0.0,1.0,0.0],[93.0,0.0,12.897196769714355,0.8604651093482971,0.1349206268787384,0.0,1.0,0.0],[97.0,0.0,12.897196769714355,0.8759689927101135,0.1349206268787384,0.0,1.0,0.0]],[[111.0,0.0,17.663551330566406,0.930232584476471,0.0,0.0,1.0,0.0],[129.0,0.0,-17.663551330566406,1.0,1.0,0.0,1.0,0.0],[97.0,0.0,12.897196769714355,0.8759689927101135,0.1349206268787384,0.0,1.0,0.0]],[[111.0,0.0,17.663551330566406,0.930232584476471,0.0,0.0,1.0,0.0],[125.0,0.0,17.663551330566406,0.9844961166381836,0.0,0.0,1.0,0.0],[125.0,0.0,12.897196769714355,0.9844961166381836,0.1349206268787384,0.0,1.0,0.0]],[[129.0,0.0,-17.663551330566406,1.0,1.0,0.0,1.0,0.0],[111.0,0.0,17.663551330566406,0.930232584476471,0.0,0.0,1.0,0.0],[125.0,0.0,12.897196769714355,0.9844961166381836,0.1349206268787384,0.0,1.0,0.0]],[[129.0,0.0,-17.663551330566406,1.0,1.0,0.0,1.0,0.0],[125.0,0.0,12.897196769714355,0.9844961166381836,0.1349206268787384,0.0,1.0,0.0],[129.0,0.0,12.897196769714355,1.0,0.1349206268787384,0.0,1.0,0.0]]]}]]====])
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
