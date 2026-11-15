-- Read-only native asset QA. Call returned Verify(importRoot, {GroupId=optionalName}).
-- Vertex/face IDs may be reordered or welded; match oriented triangle corner
-- geometry+UV tuples, preserving exact authored source UV values and per-corner UV seams.
-- Creates only detached temporary EditableMeshes and always destroys them.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Jungle_1_2","localBounds":[[-188.8135528564453,0.0,-151.0],[188.8135528564453,0.0,151.0]],"pathRGB":[194,146,71],"pivot":[-78.1864405,0.07999995164573193,353.0],"region":"Jungle","size":[377.627119,0,302.0],"triangles":[[[-176.8135528564453,0.0,105.0,0.03177737817168236,0.15231788158416748],[-188.8135528564453,0.0,105.0,0.0,0.15231788158416748],[-188.8135528564453,0.0,133.0,0.0,0.05960264801979065]],[[-176.8135528564453,0.0,133.0,0.03177737817168236,0.05960264801979065],[-176.8135528564453,0.0,105.0,0.03177737817168236,0.15231788158416748],[-188.8135528564453,0.0,133.0,0.0,0.05960264801979065]],[[-184.04721069335938,0.0,-61.0,0.012621855363249779,0.7019867300987244],[-184.04721069335938,0.0,-43.0,0.012621855363249779,0.6423841118812561],[-166.04721069335938,0.0,-43.0,0.060287922620773315,0.6423841118812561]],[[-176.8135528564453,0.0,105.0,0.03177737817168236,0.15231788158416748],[-176.8135528564453,0.0,133.0,0.03177737817168236,0.05960264801979065],[-174.8135528564453,0.0,105.0,0.03707360848784447,0.15231788158416748]],[[-174.8135528564453,0.0,133.0,0.03707360848784447,0.05960264801979065],[-174.8135528564453,0.0,105.0,0.03707360848784447,0.15231788158416748],[-176.8135528564453,0.0,133.0,0.03177737817168236,0.05960264801979065]],[[-148.04721069335938,0.0,-103.0,0.1079539954662323,0.8410596251487732],[-184.04721069335938,0.0,-103.0,0.012621855363249779,0.8410596251487732],[-184.04721069335938,0.0,-79.0,0.012621855363249779,0.7615894079208374]],[[-184.04721069335938,0.0,-61.0,0.012621855363249779,0.7019867300987244],[-148.04721069335938,0.0,-79.0,0.1079539954662323,0.7615894079208374],[-184.04721069335938,0.0,-79.0,0.012621855363249779,0.7615894079208374]],[[-174.8135528564453,0.0,105.0,0.03707360848784447,0.15231788158416748],[-174.8135528564453,0.0,133.0,0.03707360848784447,0.05960264801979065],[-162.8135528564453,0.0,105.0,0.06885098665952682,0.15231788158416748]],[[-178.04721069335938,0.0,-119.0,0.028510544449090958,0.8940397500991821],[-154.04721069335938,0.0,-119.0,0.09206530451774597,0.8940397500991821],[-178.04721069335938,0.0,-151.0,0.028510544449090958,1.0]],[[-184.04721069335938,0.0,-103.0,0.012621855363249779,0.8410596251487732],[-148.04721069335938,0.0,-103.0,0.1079539954662323,0.8410596251487732],[-178.04721069335938,0.0,-119.0,0.028510544449090958,0.8940397500991821]],[[-162.8135528564453,0.0,133.0,0.06885098665952682,0.05960264801979065],[-162.8135528564453,0.0,105.0,0.06885098665952682,0.15231788158416748],[-174.8135528564453,0.0,133.0,0.03707360848784447,0.05960264801979065]],[[-166.04721069335938,0.0,-43.0,0.060287922620773315,0.6423841118812561],[-148.04721069335938,0.0,-79.0,0.1079539954662323,0.7615894079208374],[-184.04721069335938,0.0,-61.0,0.012621855363249779,0.7019867300987244]],[[-154.04721069335938,0.0,-119.0,0.09206530451774597,0.8940397500991821],[-154.04721069335938,0.0,-151.0,0.09206530451774597,1.0],[-178.04721069335938,0.0,-151.0,0.028510544449090958,1.0]],[[-178.04721069335938,0.0,-119.0,0.028510544449090958,0.8940397500991821],[-148.04721069335938,0.0,-103.0,0.1079539954662323,0.8410596251487732],[-154.04721069335938,0.0,-119.0,0.09206530451774597,0.8940397500991821]],[[-148.04721069335938,0.0,-103.0,0.1079539954662323,0.8410596251487732],[-184.04721069335938,0.0,-79.0,0.012621855363249779,0.7615894079208374],[-148.04721069335938,0.0,-79.0,0.1079539954662323,0.7615894079208374]],[[-162.8135528564453,0.0,105.0,0.06885098665952682,0.15231788158416748],[-162.8135528564453,0.0,133.0,0.06885098665952682,0.05960264801979065],[-151.13131713867188,0.0,105.0,0.0997869074344635,0.15231788158416748]],[[-148.04721069335938,0.0,-79.0,0.1079539954662323,0.7615894079208374],[-166.04721069335938,0.0,-43.0,0.060287922620773315,0.6423841118812561],[-151.13131713867188,0.0,-43.0,0.0997869074344635,0.6423841118812561]],[[-151.13131713867188,0.0,105.0,0.0997869074344635,0.15231788158416748],[-162.8135528564453,0.0,133.0,0.06885098665952682,0.05960264801979065],[-142.8135528564453,0.0,133.0,0.12181328237056732,0.05960264801979065]],[[-146.8135528564453,0.0,-79.0,0.1112208291888237,0.7615894079208374],[-148.04721069335938,0.0,-79.0,0.1079539954662323,0.7615894079208374],[-151.13131713867188,0.0,-43.0,0.0997869074344635,0.6423841118812561]],[[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561],[-151.13131713867188,0.0,-43.0,0.0997869074344635,0.6423841118812561],[-151.13131713867188,0.0,105.0,0.0997869074344635,0.15231788158416748]],[[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561],[-146.8135528564453,0.0,-79.0,0.1112208291888237,0.7615894079208374],[-151.13131713867188,0.0,-43.0,0.0997869074344635,0.6423841118812561]],[[-127.13131713867188,0.0,105.0,0.1633416712284088,0.15231788158416748],[-151.13131713867188,0.0,105.0,0.0997869074344635,0.15231788158416748],[-142.8135528564453,0.0,133.0,0.12181328237056732,0.05960264801979065]],[[-151.13131713867188,0.0,105.0,0.0997869074344635,0.15231788158416748],[-127.13131713867188,0.0,105.0,0.1633416712284088,0.15231788158416748],[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561]],[[-146.8135528564453,0.0,-79.0,0.1112208291888237,0.7615894079208374],[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561],[-128.8135528564453,0.0,-79.0,0.1588868945837021,0.7615894079208374]],[[-127.13131713867188,0.0,105.0,0.1633416712284088,0.15231788158416748],[-142.8135528564453,0.0,133.0,0.12181328237056732,0.05960264801979065],[-128.8135528564453,0.0,133.0,0.1588868945837021,0.05960264801979065]],[[-114.81356048583984,0.0,133.0,0.19596050679683685,0.05960264801979065],[-127.13131713867188,0.0,105.0,0.1633416712284088,0.15231788158416748],[-128.8135528564453,0.0,133.0,0.1588868945837021,0.05960264801979065]],[[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561],[-110.81356048583984,0.0,-79.0,0.20655296742916107,0.7615894079208374],[-128.8135528564453,0.0,-79.0,0.1588868945837021,0.7615894079208374]],[[-127.13131713867188,0.0,105.0,0.1633416712284088,0.15231788158416748],[-114.81356048583984,0.0,133.0,0.19596050679683685,0.05960264801979065],[-114.81356048583984,0.0,105.0,0.19596050679683685,0.15231788158416748]],[[-110.81356048583984,0.0,-43.0,0.20655296742916107,0.6423841118812561],[-110.81356048583984,0.0,-79.0,0.20655296742916107,0.7615894079208374],[-127.13131713867188,0.0,-43.0,0.1633416712284088,0.6423841118812561]],[[-114.81356048583984,0.0,105.0,0.19596050679683685,0.15231788158416748],[-114.81356048583984,0.0,133.0,0.19596050679683685,0.05960264801979065],[-44.41355895996094,0.0,105.0,0.38238778710365295,0.15231788158416748]],[[-48.41355895996094,0.0,-43.0,0.37179532647132874,0.6423841118812561],[-110.81356048583984,0.0,-79.0,0.20655296742916107,0.7615894079208374],[-110.81356048583984,0.0,-43.0,0.20655296742916107,0.6423841118812561]],[[-48.41355895996094,0.0,-43.0,0.37179532647132874,0.6423841118812561],[-48.41355895996094,0.0,-79.0,0.37179532647132874,0.7615894079208374],[-110.81356048583984,0.0,-79.0,0.20655296742916107,0.7615894079208374]],[[-44.41355895996094,0.0,133.0,0.38238778710365295,0.05960264801979065],[-44.41355895996094,0.0,105.0,0.38238778710365295,0.15231788158416748],[-114.81356048583984,0.0,133.0,0.19596050679683685,0.05960264801979065]],[[-48.41355895996094,0.0,-79.0,0.37179532647132874,0.7615894079208374],[-48.41355895996094,0.0,-43.0,0.37179532647132874,0.6423841118812561],[-30.413558959960938,0.0,-43.0,0.4194613993167877,0.6423841118812561]],[[-44.41355895996094,0.0,105.0,0.38238778710365295,0.15231788158416748],[-44.41355895996094,0.0,133.0,0.38238778710365295,0.05960264801979065],[-30.413558959960938,0.0,105.0,0.4194613993167877,0.15231788158416748]],[[-30.413558959960938,0.0,-43.0,0.4194613993167877,0.6423841118812561],[-30.413558959960938,0.0,-79.0,0.4194613993167877,0.7615894079208374],[-48.41355895996094,0.0,-79.0,0.37179532647132874,0.7615894079208374]],[[-30.413558959960938,0.0,133.0,0.4194613993167877,0.05960264801979065],[-30.413558959960938,0.0,105.0,0.4194613993167877,0.15231788158416748],[-44.41355895996094,0.0,133.0,0.38238778710365295,0.05960264801979065]],[[-30.413558959960938,0.0,105.0,0.4194613993167877,0.15231788158416748],[-30.413558959960938,0.0,133.0,0.4194613993167877,0.05960264801979065],[-16.413558959960938,0.0,105.0,0.4565350115299225,0.15231788158416748]],[[-30.413558959960938,0.0,-79.0,0.4194613993167877,0.7615894079208374],[-30.413558959960938,0.0,-43.0,0.4194613993167877,0.6423841118812561],[-12.413559913635254,0.0,-43.0,0.4671274721622467,0.6423841118812561]],[[-16.413558959960938,0.0,133.0,0.4565350115299225,0.05960264801979065],[-16.413558959960938,0.0,105.0,0.4565350115299225,0.15231788158416748],[-30.413558959960938,0.0,133.0,0.4194613993167877,0.05960264801979065]],[[-12.413559913635254,0.0,-43.0,0.4671274721622467,0.6423841118812561],[-12.413559913635254,0.0,-79.0,0.4671274721622467,0.7615894079208374],[-30.413558959960938,0.0,-79.0,0.4194613993167877,0.7615894079208374]],[[-16.413558959960938,0.0,105.0,0.4565350115299225,0.15231788158416748],[-16.413558959960938,0.0,133.0,0.4565350115299225,0.05960264801979065],[27.18644142150879,0.0,105.0,0.571992814540863,0.15231788158416748]],[[-12.413559913635254,0.0,-79.0,0.4671274721622467,0.7615894079208374],[-12.413559913635254,0.0,-43.0,0.4671274721622467,0.6423841118812561],[27.18644142150879,0.0,-43.0,0.571992814540863,0.6423841118812561]],[[27.18644142150879,0.0,133.0,0.571992814540863,0.05960264801979065],[27.18644142150879,0.0,105.0,0.571992814540863,0.15231788158416748],[-16.413558959960938,0.0,133.0,0.4565350115299225,0.05960264801979065]],[[27.18644142150879,0.0,-43.0,0.571992814540863,0.6423841118812561],[27.18644142150879,0.0,-79.0,0.571992814540863,0.7615894079208374],[-12.413559913635254,0.0,-79.0,0.4671274721622467,0.7615894079208374]],[[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065],[27.18644142150879,0.0,-79.0,0.571992814540863,0.7615894079208374],[27.18644142150879,0.0,-43.0,0.571992814540863,0.6423841118812561]],[[27.18644142150879,0.0,-43.0,0.571992814540863,0.6423841118812561],[27.18644142150879,0.0,-29.0,0.571992814540863,0.5960264801979065],[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065]],[[45.186439514160156,0.0,87.0,0.619658887386322,0.21192052960395813],[27.18644142150879,0.0,87.0,0.571992814540863,0.21192052960395813],[27.18644142150879,0.0,105.0,0.571992814540863,0.15231788158416748]],[[27.18644142150879,0.0,105.0,0.571992814540863,0.15231788158416748],[27.18644142150879,0.0,133.0,0.571992814540863,0.05960264801979065],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813]],[[27.18644142150879,0.0,-79.0,0.571992814540863,0.7615894079208374],[91.18643951416016,0.0,-93.0,0.7414721846580505,0.807947039604187],[27.18644142150879,0.0,-93.0,0.571992814540863,0.807947039604187]],[[45.186439514160156,0.0,87.0,0.619658887386322,0.21192052960395813],[27.18644142150879,0.0,105.0,0.571992814540863,0.15231788158416748],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813]],[[27.18644142150879,0.0,133.0,0.571992814540863,0.05960264801979065],[27.18644142150879,0.0,151.0,0.571992814540863,0.0],[91.18643951416016,0.0,151.0,0.7414721846580505,0.0]],[[27.18644142150879,0.0,-79.0,0.571992814540863,0.7615894079208374],[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065],[91.18643951416016,0.0,-75.0,0.7414721846580505,0.748344361782074]],[[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065],[45.186439514160156,0.0,87.0,0.619658887386322,0.21192052960395813],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813]],[[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813],[73.18643951416016,0.0,-29.0,0.6938061118125916,0.5960264801979065]],[[27.18644142150879,0.0,133.0,0.571992814540863,0.05960264801979065],[91.18643951416016,0.0,151.0,0.7414721846580505,0.0],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813]],[[91.18643951416016,0.0,-93.0,0.7414721846580505,0.807947039604187],[27.18644142150879,0.0,-79.0,0.571992814540863,0.7615894079208374],[91.18643951416016,0.0,-75.0,0.7414721846580505,0.748344361782074]],[[91.18643951416016,0.0,-75.0,0.7414721846580505,0.748344361782074],[45.186439514160156,0.0,-29.0,0.619658887386322,0.5960264801979065],[73.18643951416016,0.0,-29.0,0.6938061118125916,0.5960264801979065]],[[73.18643951416016,0.0,-29.0,0.6938061118125916,0.5960264801979065],[91.18643951416016,0.0,-47.0,0.7414721846580505,0.6556291580200195],[91.18643951416016,0.0,-75.0,0.7414721846580505,0.748344361782074]],[[73.18643951416016,0.0,-29.0,0.6938061118125916,0.5960264801979065],[91.18643951416016,0.0,-29.0,0.7414721846580505,0.5960264801979065],[91.18643951416016,0.0,-47.0,0.7414721846580505,0.6556291580200195]],[[91.18643951416016,0.0,151.0,0.7414721846580505,0.0],[91.18643951416016,0.0,87.0,0.7414721846580505,0.21192052960395813],[73.18643951416016,0.0,87.0,0.6938061118125916,0.21192052960395813]],[[91.18643951416016,0.0,-47.0,0.7414721846580505,0.6556291580200195],[134.78643798828125,0.0,-75.0,0.8569299578666687,0.748344361782074],[91.18643951416016,0.0,-75.0,0.7414721846580505,0.748344361782074]],[[134.78643798828125,0.0,-47.0,0.8569299578666687,0.6556291580200195],[134.78643798828125,0.0,-75.0,0.8569299578666687,0.748344361782074],[91.18643951416016,0.0,-47.0,0.7414721846580505,0.6556291580200195]],[[134.78643798828125,0.0,-75.0,0.8569299578666687,0.748344361782074],[134.78643798828125,0.0,-47.0,0.8569299578666687,0.6556291580200195],[148.78643798828125,0.0,-75.0,0.8940035700798035,0.748344361782074]],[[148.78643798828125,0.0,-47.0,0.8940035700798035,0.6556291580200195],[148.78643798828125,0.0,-75.0,0.8940035700798035,0.748344361782074],[134.78643798828125,0.0,-47.0,0.8569299578666687,0.6556291580200195]],[[148.78643798828125,0.0,-75.0,0.8940035700798035,0.748344361782074],[148.78643798828125,0.0,-47.0,0.8940035700798035,0.6556291580200195],[162.78643798828125,0.0,-75.0,0.9310771822929382,0.748344361782074]],[[162.78643798828125,0.0,-47.0,0.9310771822929382,0.6556291580200195],[162.78643798828125,0.0,-75.0,0.9310771822929382,0.748344361782074],[148.78643798828125,0.0,-47.0,0.8940035700798035,0.6556291580200195]],[[162.78643798828125,0.0,-75.0,0.9310771822929382,0.748344361782074],[162.78643798828125,0.0,-47.0,0.9310771822929382,0.6556291580200195],[188.8135528564453,0.0,-75.0,1.0,0.748344361782074]],[[162.78643798828125,0.0,-47.0,0.9310771822929382,0.6556291580200195],[188.8135528564453,0.0,-47.0,1.0,0.6556291580200195],[188.8135528564453,0.0,-75.0,1.0,0.748344361782074]]]}]]====])
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
