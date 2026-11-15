-- Read-only native asset QA. Call returned Verify(importRoot, {GroupId=optionalName}).
-- Vertex/face IDs may be reordered or welded; match oriented triangle corner
-- geometry+UV tuples, preserving exact authored source UV values and per-corner UV seams.
-- Creates only detached temporary EditableMeshes and always destroys them.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Volcano_3_1","localBounds":[[-66.0,0.0,-175.65423583984375],[66.0,0.0,175.65423583984375]],"pathRGB":[157,127,143],"pivot":[607.0,0.07999995164573193,-35.5525425],"region":"Volcano","size":[132.0,0,351.30847500000004],"triangles":[[[-40.0,0.0,-24.447458267211914,0.19696970283985138,0.5695897340774536],[-66.0,0.0,-24.447458267211914,0.0,0.5695897340774536],[-66.0,0.0,3.5525424480438232,0.0,0.48988768458366394]],[[-40.0,0.0,3.5525424480438232,0.19696970283985138,0.48988768458366394],[-40.0,0.0,-24.447458267211914,0.19696970283985138,0.5695897340774536],[-66.0,0.0,3.5525424480438232,0.0,0.48988768458366394]],[[-32.0,0.0,-169.587646484375,0.25757575035095215,0.9827314615249634],[-50.0,0.0,-175.65423583984375,0.12121212482452393,1.0],[-50.0,0.0,-169.587646484375,0.12121212482452393,0.9827314615249634]],[[-32.0,0.0,-32.44745635986328,0.25757575035095215,0.5923617482185364],[-40.0,0.0,-32.44745635986328,0.19696970283985138,0.5923617482185364],[-40.0,0.0,-24.447458267211914,0.19696970283985138,0.5695897340774536]],[[-40.0,0.0,-24.447458267211914,0.19696970283985138,0.5695897340774536],[-40.0,0.0,3.5525424480438232,0.19696970283985138,0.48988768458366394],[-32.0,0.0,-32.44745635986328,0.25757575035095215,0.5923617482185364]],[[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[-66.0,0.0,151.65423583984375,0.0,0.0683160275220871],[-66.0,0.0,175.65423583984375,0.0,0.0]],[[-4.0,0.0,-32.44745635986328,0.469696968793869,0.5923617482185364],[-32.0,0.0,-32.44745635986328,0.25757575035095215,0.5923617482185364],[-40.0,0.0,3.5525424480438232,0.19696970283985138,0.48988768458366394]],[[-40.0,0.0,3.5525424480438232,0.19696970283985138,0.48988768458366394],[-40.0,0.0,11.552542686462402,0.19696970283985138,0.4671156704425812],[4.0,0.0,11.552542686462402,0.5303030014038086,0.4671156704425812]],[[-50.0,0.0,-175.65423583984375,0.12121212482452393,1.0],[-32.0,0.0,-169.587646484375,0.25757575035095215,0.9827314615249634],[14.0,0.0,-175.65423583984375,0.6060606241226196,1.0]],[[-32.0,0.0,-114.04745483398438,0.25757575035095215,0.8246362209320068],[-4.0,0.0,-114.04745483398438,0.469696968793869,0.8246362209320068],[-32.0,0.0,-169.587646484375,0.25757575035095215,0.9827314615249634]],[[-32.0,0.0,-100.04745483398438,0.25757575035095215,0.7847852110862732],[-4.0,0.0,-100.04745483398438,0.469696968793869,0.7847852110862732],[-32.0,0.0,-114.04745483398438,0.25757575035095215,0.8246362209320068]],[[-32.0,0.0,-100.04745483398438,0.25757575035095215,0.7847852110862732],[-32.0,0.0,-86.04745483398438,0.25757575035095215,0.7449342012405396],[-4.0,0.0,-86.04745483398438,0.469696968793869,0.7449342012405396]],[[-32.0,0.0,-86.04745483398438,0.25757575035095215,0.7449342012405396],[-32.0,0.0,-32.44745635986328,0.25757575035095215,0.5923617482185364],[-4.0,0.0,-86.04745483398438,0.469696968793869,0.7449342012405396]],[[-4.0,0.0,-114.04745483398438,0.469696968793869,0.8246362209320068],[-4.0,0.0,-169.587646484375,0.469696968793869,0.9827314615249634],[-32.0,0.0,-169.587646484375,0.25757575035095215,0.9827314615249634]],[[-4.0,0.0,-114.04745483398438,0.469696968793869,0.8246362209320068],[-32.0,0.0,-114.04745483398438,0.25757575035095215,0.8246362209320068],[-4.0,0.0,-100.04745483398438,0.469696968793869,0.7847852110862732]],[[-4.0,0.0,-100.04745483398438,0.469696968793869,0.7847852110862732],[-32.0,0.0,-100.04745483398438,0.25757575035095215,0.7847852110862732],[-4.0,0.0,-86.04745483398438,0.469696968793869,0.7449342012405396]],[[-32.0,0.0,-32.44745635986328,0.25757575035095215,0.5923617482185364],[-4.0,0.0,-32.44745635986328,0.469696968793869,0.5923617482185364],[-4.0,0.0,-86.04745483398438,0.469696968793869,0.7449342012405396]],[[-40.0,0.0,3.5525424480438232,0.19696970283985138,0.48988768458366394],[4.0,0.0,11.552542686462402,0.5303030014038086,0.4671156704425812],[-4.0,0.0,-32.44745635986328,0.469696968793869,0.5923617482185364]],[[-4.0,0.0,-169.587646484375,0.469696968793869,0.9827314615249634],[14.0,0.0,-175.65423583984375,0.6060606241226196,1.0],[-32.0,0.0,-169.587646484375,0.25757575035095215,0.9827314615249634]],[[4.0,0.0,11.552542686462402,0.5303030014038086,0.4671156704425812],[4.0,0.0,-32.44745635986328,0.5303030014038086,0.5923617482185364],[-4.0,0.0,-32.44745635986328,0.469696968793869,0.5923617482185364]],[[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[-66.0,0.0,175.65423583984375,0.0,0.0],[42.0,0.0,175.65423583984375,0.8181818127632141,0.0]],[[-4.0,0.0,-169.587646484375,0.469696968793869,0.9827314615249634],[14.0,0.0,-169.587646484375,0.6060606241226196,0.9827314615249634],[14.0,0.0,-175.65423583984375,0.6060606241226196,1.0]],[[54.0,0.0,175.65423583984375,0.9090909361839294,0.0],[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[42.0,0.0,175.65423583984375,0.8181818127632141,0.0]],[[42.0,0.0,-112.04745483398438,0.8181818127632141,0.818943202495575],[66.0,0.0,-112.04745483398438,1.0,0.818943202495575],[42.0,0.0,-175.65423583984375,0.8181818127632141,1.0]],[[42.0,0.0,-100.04745483398438,0.8181818127632141,0.7847852110862732],[66.0,0.0,-100.04745483398438,1.0,0.7847852110862732],[42.0,0.0,-112.04745483398438,0.8181818127632141,0.818943202495575]],[[42.0,0.0,-88.04745483398438,0.8181818127632141,0.7506272196769714],[66.0,0.0,-88.04745483398438,1.0,0.7506272196769714],[42.0,0.0,-100.04745483398438,0.8181818127632141,0.7847852110862732]],[[42.0,0.0,67.15254211425781,0.8181818127632141,0.3088501989841461],[66.0,0.0,67.15254211425781,1.0,0.3088501989841461],[42.0,0.0,-88.04745483398438,0.8181818127632141,0.7506272196769714]],[[42.0,0.0,79.15254211425781,0.8181818127632141,0.274692177772522],[66.0,0.0,79.15254211425781,1.0,0.274692177772522],[42.0,0.0,67.15254211425781,0.8181818127632141,0.3088501989841461]],[[42.0,0.0,91.15254211425781,0.8181818127632141,0.24053417146205902],[66.0,0.0,91.15254211425781,1.0,0.24053417146205902],[42.0,0.0,79.15254211425781,0.8181818127632141,0.274692177772522]],[[42.0,0.0,91.15254211425781,0.8181818127632141,0.24053417146205902],[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[66.0,0.0,151.65423583984375,1.0,0.0683160275220871]],[[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[54.0,0.0,175.65423583984375,0.9090909361839294,0.0],[66.0,0.0,163.65423583984375,1.0,0.03415801376104355]],[[66.0,0.0,-112.04745483398438,1.0,0.818943202495575],[66.0,0.0,-175.65423583984375,1.0,1.0],[42.0,0.0,-175.65423583984375,0.8181818127632141,1.0]],[[66.0,0.0,-112.04745483398438,1.0,0.818943202495575],[42.0,0.0,-112.04745483398438,0.8181818127632141,0.818943202495575],[66.0,0.0,-100.04745483398438,1.0,0.7847852110862732]],[[66.0,0.0,-100.04745483398438,1.0,0.7847852110862732],[42.0,0.0,-100.04745483398438,0.8181818127632141,0.7847852110862732],[66.0,0.0,-88.04745483398438,1.0,0.7506272196769714]],[[66.0,0.0,-88.04745483398438,1.0,0.7506272196769714],[42.0,0.0,-88.04745483398438,0.8181818127632141,0.7506272196769714],[66.0,0.0,67.15254211425781,1.0,0.3088501989841461]],[[66.0,0.0,67.15254211425781,1.0,0.3088501989841461],[42.0,0.0,67.15254211425781,0.8181818127632141,0.3088501989841461],[66.0,0.0,79.15254211425781,1.0,0.274692177772522]],[[66.0,0.0,79.15254211425781,1.0,0.274692177772522],[42.0,0.0,79.15254211425781,0.8181818127632141,0.274692177772522],[66.0,0.0,91.15254211425781,1.0,0.24053417146205902]],[[66.0,0.0,91.15254211425781,1.0,0.24053417146205902],[42.0,0.0,91.15254211425781,0.8181818127632141,0.24053417146205902],[66.0,0.0,151.65423583984375,1.0,0.0683160275220871]],[[42.0,0.0,151.65423583984375,0.8181818127632141,0.0683160275220871],[66.0,0.0,163.65423583984375,1.0,0.03415801376104355],[66.0,0.0,151.65423583984375,1.0,0.0683160275220871]],[[54.0,0.0,175.65423583984375,0.9090909361839294,0.0],[66.0,0.0,175.65423583984375,1.0,0.0],[66.0,0.0,163.65423583984375,1.0,0.03415801376104355]]]}]]====])
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
