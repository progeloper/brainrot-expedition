-- Read-only native asset QA. Call returned Verify(importRoot, {GroupId=optionalName}).
-- Vertex/face IDs may be reordered or welded; match oriented triangle corner
-- geometry+UV tuples, preserving exact authored source UV values and per-corner UV seams.
-- Creates only detached temporary EditableMeshes and always destroys them.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Camp_1_0","localBounds":[[-180.47119140625,0.0,-39.013431549072266],[180.47119140625,0.0,39.013431549072266]],"pathRGB":[232,201,138],"pivot":[-86.5288135,0.07999995164573193,-250.2202125],"region":"Camp","size":[360.942373,0,78.02686500000002],"triangles":[[[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0],[-180.47119140625,0.0,-39.013431549072266,0.0,1.0],[-180.47119140625,0.0,-3.013432502746582,0.0,0.5386204719543457]],[[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457],[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0],[-180.47119140625,0.0,-3.013432502746582,0.0,0.5386204719543457]],[[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0],[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0]],[[-168.47119140625,0.0,-3.013432502746582,0.03324630483984947,0.5386204719543457],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0],[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457]],[[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0],[-168.47119140625,0.0,-3.013432502746582,0.03324630483984947,0.5386204719543457]],[[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457],[-162.47119140625,0.0,-39.013431549072266,0.04986945539712906,1.0]],[[-162.47119140625,0.0,-39.013431549072266,0.04986945539712906,1.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457],[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0]],[[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064],[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717],[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457]],[[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234],[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064]],[[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983],[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243],[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234]],[[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0],[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717],[-150.47119140625,0.0,-39.013431549072266,0.08311576396226883,1.0]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064],[-139.59373474121094,0.0,-28.358177185058594,0.11325202882289886,0.8634411692619324]],[[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424],[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702],[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983]],[[-139.59373474121094,0.0,-28.358177185058594,0.11325202882289886,0.8634411692619324],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064],[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783]],[[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902],[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162],[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424]],[[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783],[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234],[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717],[-139.704833984375,0.0,-39.013431549072266,0.11294422298669815,1.0],[-150.47119140625,0.0,-39.013431549072266,0.08311576396226883,1.0]],[[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613],[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621],[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902]],[[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243],[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983],[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702]],[[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821],[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081],[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613]],[[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702],[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424],[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162]],[[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803],[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854],[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821]],[[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162],[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902],[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621]],[[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397],[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995],[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803]],[[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621],[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613],[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081]],[[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858],[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575],[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397]],[[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081],[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821],[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854]],[[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705],[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858],[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988]],[[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854],[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803],[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995]],[[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023],[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988]],[[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995],[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397],[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575]],[[-123.74826049804688,0.0,38.398983001708984,0.15715229511260986,0.007874852046370506],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834],[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247]],[[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575],[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858],[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705]],[[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834],[-123.74826049804688,0.0,38.398983001708984,0.15715229511260986,0.007874852046370506]],[[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023],[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705]],[[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023]],[[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-93.84496307373047,0.0,17.390596389770508,0.2400001585483551,0.2771204113960266]],[[-93.84496307373047,0.0,17.390596389770508,0.2400001585483551,0.2771204113960266],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-89.39749908447266,0.0,21.83805274963379,0.2523219585418701,0.2201213538646698]],[[-89.39749908447266,0.0,21.83805274963379,0.2523219585418701,0.2201213538646698],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-84.95004272460938,0.0,26.285511016845703,0.26464375853538513,0.16312231123447418]],[[-84.95004272460938,0.0,26.285511016845703,0.26464375853538513,0.16312231123447418],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-80.5025863647461,0.0,30.732969284057617,0.27696552872657776,0.10612324625253677]],[[-80.5025863647461,0.0,30.732969284057617,0.27696552872657776,0.10612324625253677],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-76.05513000488281,0.0,35.18042755126953,0.2892873287200928,0.049124181270599365]],[[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0],[-72.22212219238281,0.0,39.013431549072266,0.29990679025650024,0.0],[-76.05513000488281,0.0,35.18042755126953,0.2892873287200928,0.049124181270599365]],[[3.7405784130096436,0.0,27.89478874206543,0.5103633403778076,0.14249764382839203],[-16.259422302246094,0.0,27.89478874206543,0.4549528658390045,0.14249764382839203],[-16.259422302246094,0.0,39.013431549072266,0.4549528658390045,0.0]],[[-16.259422302246094,0.0,39.013431549072266,0.4549528658390045,0.0],[3.7405784130096436,0.0,39.013431549072266,0.5103633403778076,0.0],[3.7405784130096436,0.0,27.89478874206543,0.5103633403778076,0.14249764382839203]],[[93.340576171875,0.0,27.89478874206543,0.7586024403572083,0.14249764382839203],[73.340576171875,0.0,27.89478874206543,0.7031919360160828,0.14249764382839203],[73.340576171875,0.0,39.013431549072266,0.7031919360160828,0.0]],[[73.340576171875,0.0,39.013431549072266,0.7031919360160828,0.0],[93.340576171875,0.0,39.013431549072266,0.7586024403572083,0.0],[93.340576171875,0.0,27.89478874206543,0.7586024403572083,0.14249764382839203]],[[180.47119140625,0.0,27.89478874206543,1.0,0.14249764382839203],[160.47119140625,0.0,27.89478874206543,0.9445894956588745,0.14249764382839203],[160.47119140625,0.0,39.013431549072266,0.9445894956588745,0.0]],[[160.47119140625,0.0,39.013431549072266,0.9445894956588745,0.0],[180.47119140625,0.0,39.013431549072266,1.0,0.0],[180.47119140625,0.0,27.89478874206543,1.0,0.14249764382839203]]]}]]====])
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
