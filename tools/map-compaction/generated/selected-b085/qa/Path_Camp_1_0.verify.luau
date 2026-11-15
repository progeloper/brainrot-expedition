-- Read-only real native asset QA; call Verify(importRoot,{GroupId=optionalFullName}).
-- Match every oriented triangle corner's canonical position, source
-- UV and authored hard normal; native welding/reordering is permitted. Only
-- detached temporary EditableMeshes are allocated and always destroyed.
local HttpService=game:GetService("HttpService")
local AssetService=game:GetService("AssetService")
local RunService=game:GetService("RunService")
local EXPECTED=HttpService:JSONDecode([====[[{"id":"Path_Camp_1_0","prototypeId":"CompactMapRoads","groupId":"Path_Camp_1_0","role":"Road","centre":[-86.5288135,0.07999995164573193,-250.2202125],"size":[360.9423828125,0.0,78.02686309814453],"localBounds":[[-180.47119140625,0.0,-39.013431549072266],[180.47119140625,0.0,39.013431549072266]],"rgb":[232,201,138],"triangles":[[[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0,0.0,1.0,0.0],[-180.47119140625,0.0,-39.013431549072266,0.0,1.0,0.0,1.0,0.0],[-180.47119140625,0.0,-3.013432502746582,0.0,0.5386204719543457,0.0,1.0,0.0]],[[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457,0.0,1.0,0.0],[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0,0.0,1.0,0.0],[-180.47119140625,0.0,-3.013432502746582,0.0,0.5386204719543457,0.0,1.0,0.0]],[[-175.704833984375,0.0,-39.013431549072266,0.01320530753582716,1.0,0.0,1.0,0.0],[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457,0.0,1.0,0.0],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0,0.0,1.0,0.0]],[[-168.47119140625,0.0,-3.013432502746582,0.03324630483984947,0.5386204719543457,0.0,1.0,0.0],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0,0.0,1.0,0.0],[-175.704833984375,0.0,-3.013432502746582,0.01320530753582716,0.5386204719543457,0.0,1.0,0.0]],[[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457,0.0,1.0,0.0],[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0,0.0,1.0,0.0],[-168.47119140625,0.0,-3.013432502746582,0.03324630483984947,0.5386204719543457,0.0,1.0,0.0]],[[-168.47119140625,0.0,-39.013431549072266,0.03324630483984947,1.0,0.0,1.0,0.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457,0.0,1.0,0.0],[-162.47119140625,0.0,-39.013431549072266,0.04986945539712906,1.0,0.0,1.0,0.0]],[[-162.47119140625,0.0,-39.013431549072266,0.04986945539712906,1.0,0.0,1.0,0.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457,0.0,1.0,0.0],[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0,0.0,1.0,0.0]],[[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064,0.0,1.0,0.0],[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717,0.0,1.0,0.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457,0.0,1.0,0.0]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717,0.0,1.0,0.0],[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0,0.0,1.0,0.0],[-165.16067504882812,0.0,-3.013432502746582,0.042418159544467926,0.5386204719543457,0.0,1.0,0.0]],[[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234,0.0,1.0,0.0],[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783,0.0,1.0,0.0],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064,0.0,1.0,0.0]],[[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983,0.0,1.0,0.0],[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243,0.0,1.0,0.0],[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234,0.0,1.0,0.0]],[[-157.704833984375,0.0,-39.013431549072266,0.06307476758956909,1.0,0.0,1.0,0.0],[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717,0.0,1.0,0.0],[-150.47119140625,0.0,-39.013431549072266,0.08311576396226883,1.0,0.0,1.0,0.0]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717,0.0,1.0,0.0],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064,0.0,1.0,0.0],[-139.59373474121094,0.0,-28.358177185058594,0.11325202882289886,0.8634411692619324,0.0,1.0,0.0]],[[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424,0.0,1.0,0.0],[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702,0.0,1.0,0.0],[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983,0.0,1.0,0.0]],[[-139.59373474121094,0.0,-28.358177185058594,0.11325202882289886,0.8634411692619324,0.0,1.0,0.0],[-165.04957580566406,0.0,-2.9023325443267822,0.04272596538066864,0.5371965765953064,0.0,1.0,0.0],[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783,0.0,1.0,0.0]],[[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902,0.0,1.0,0.0],[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162,0.0,1.0,0.0],[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424,0.0,1.0,0.0]],[[-136.00494384765625,0.0,-24.769392013549805,0.12319484353065491,0.8174469470977783,0.0,1.0,0.0],[-161.46078491210938,0.0,0.6864525079727173,0.05266878381371498,0.49120235443115234,0.0,1.0,0.0],[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243,0.0,1.0,0.0]],[[-139.704833984375,0.0,-28.469276428222656,0.11294422298669815,0.8648650646209717,0.0,1.0,0.0],[-139.704833984375,0.0,-39.013431549072266,0.11294422298669815,1.0,0.0,1.0,0.0],[-150.47119140625,0.0,-39.013431549072266,0.08311576396226883,1.0,0.0,1.0,0.0]],[[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613,0.0,1.0,0.0],[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621,0.0,1.0,0.0],[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902,0.0,1.0,0.0]],[[-132.41616821289062,0.0,-21.180606842041016,0.13313767313957214,0.7714527249336243,0.0,1.0,0.0],[-157.87200927734375,0.0,4.275237560272217,0.06261160224676132,0.4452081322669983,0.0,1.0,0.0],[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702,0.0,1.0,0.0]],[[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821,0.0,1.0,0.0],[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081,0.0,1.0,0.0],[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613,0.0,1.0,0.0]],[[-128.82737731933594,0.0,-17.591821670532227,0.14308048784732819,0.7254585027694702,0.0,1.0,0.0],[-154.28321838378906,0.0,7.864022731781006,0.07255442440509796,0.39921391010284424,0.0,1.0,0.0],[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162,0.0,1.0,0.0]],[[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803,0.0,1.0,0.0],[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854,0.0,1.0,0.0],[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821,0.0,1.0,0.0]],[[-125.23859405517578,0.0,-14.003036499023438,0.15302330255508423,0.6794642806053162,0.0,1.0,0.0],[-150.69444274902344,0.0,11.452807426452637,0.0824972465634346,0.3532196879386902,0.0,1.0,0.0],[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621,0.0,1.0,0.0]],[[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397,0.0,1.0,0.0],[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995,0.0,1.0,0.0],[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803,0.0,1.0,0.0]],[[-121.6498031616211,0.0,-10.414251327514648,0.16296613216400146,0.6334700584411621,0.0,1.0,0.0],[-147.10565185546875,0.0,15.041592597961426,0.09244006127119064,0.30722546577453613,0.0,1.0,0.0],[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081,0.0,1.0,0.0]],[[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858,0.0,1.0,0.0],[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575,0.0,1.0,0.0],[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397,0.0,1.0,0.0]],[[-118.06101989746094,0.0,-6.825466632843018,0.1729089468717575,0.5874758362770081,0.0,1.0,0.0],[-143.51686096191406,0.0,18.6303768157959,0.10238288342952728,0.2612312436103821,0.0,1.0,0.0],[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854,0.0,1.0,0.0]],[[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705,0.0,1.0,0.0],[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858,0.0,1.0,0.0],[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988,0.0,1.0,0.0]],[[-114.47223663330078,0.0,-3.2366814613342285,0.18285176157951355,0.541481614112854,0.0,1.0,0.0],[-139.92808532714844,0.0,22.219161987304688,0.11232570558786392,0.21523702144622803,0.0,1.0,0.0],[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995,0.0,1.0,0.0]],[[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247,0.0,1.0,0.0],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023,0.0,1.0,0.0],[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988,0.0,1.0,0.0]],[[-110.88345336914062,0.0,0.35210350155830383,0.1927945911884308,0.49548739194869995,0.0,1.0,0.0],[-136.33929443359375,0.0,25.807947158813477,0.12226852029561996,0.16924279928207397,0.0,1.0,0.0],[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575,0.0,1.0,0.0]],[[-123.74826049804688,0.0,38.398983001708984,0.15715229511260986,0.007874852046370506,0.0,1.0,0.0],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834,0.0,1.0,0.0],[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247,0.0,1.0,0.0]],[[-107.7432632446289,0.0,3.492290496826172,0.20149455964565277,0.45524245500564575,0.0,1.0,0.0],[-133.19911193847656,0.0,28.948135375976562,0.13096849620342255,0.12899784743785858,0.0,1.0,0.0],[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705,0.0,1.0,0.0]],[[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834,0.0,1.0,0.0],[-123.74826049804688,0.0,38.398983001708984,0.15715229511260986,0.007874852046370506,0.0,1.0,0.0]],[[-132.64317321777344,0.0,29.504066467285156,0.13250871002674103,0.12187297642230988,0.0,1.0,0.0],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023,0.0,1.0,0.0],[-107.18733215332031,0.0,4.048222541809082,0.20303477346897125,0.44811758399009705,0.0,1.0,0.0]],[[-128.1957244873047,0.0,33.95152282714844,0.14483051002025604,0.06487391144037247,0.0,1.0,0.0],[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834,0.0,1.0,0.0],[-102.73987579345703,0.0,8.495680809020996,0.21535657346248627,0.39111852645874023,0.0,1.0,0.0]],[[-98.29241943359375,0.0,12.943137168884277,0.22767837345600128,0.3341194689273834,0.0,1.0,0.0],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-93.84496307373047,0.0,17.390596389770508,0.2400001585483551,0.2771204113960266,0.0,1.0,0.0]],[[-93.84496307373047,0.0,17.390596389770508,0.2400001585483551,0.2771204113960266,0.0,1.0,0.0],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-89.39749908447266,0.0,21.83805274963379,0.2523219585418701,0.2201213538646698,0.0,1.0,0.0]],[[-89.39749908447266,0.0,21.83805274963379,0.2523219585418701,0.2201213538646698,0.0,1.0,0.0],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-84.95004272460938,0.0,26.285511016845703,0.26464375853538513,0.16312231123447418,0.0,1.0,0.0]],[[-84.95004272460938,0.0,26.285511016845703,0.26464375853538513,0.16312231123447418,0.0,1.0,0.0],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-80.5025863647461,0.0,30.732969284057617,0.27696552872657776,0.10612324625253677,0.0,1.0,0.0]],[[-80.5025863647461,0.0,30.732969284057617,0.27696552872657776,0.10612324625253677,0.0,1.0,0.0],[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-76.05513000488281,0.0,35.18042755126953,0.2892873287200928,0.049124181270599365,0.0,1.0,0.0]],[[-123.1338119506836,0.0,39.013431549072266,0.1588546484708786,0.0,0.0,1.0,0.0],[-72.22212219238281,0.0,39.013431549072266,0.29990679025650024,0.0,0.0,1.0,0.0],[-76.05513000488281,0.0,35.18042755126953,0.2892873287200928,0.049124181270599365,0.0,1.0,0.0]],[[3.7405784130096436,0.0,27.89478874206543,0.5103633403778076,0.14249764382839203,0.0,1.0,0.0],[-16.259422302246094,0.0,27.89478874206543,0.4549528658390045,0.14249764382839203,0.0,1.0,0.0],[-16.259422302246094,0.0,39.013431549072266,0.4549528658390045,0.0,0.0,1.0,0.0]],[[-16.259422302246094,0.0,39.013431549072266,0.4549528658390045,0.0,0.0,1.0,0.0],[3.7405784130096436,0.0,39.013431549072266,0.5103633403778076,0.0,0.0,1.0,0.0],[3.7405784130096436,0.0,27.89478874206543,0.5103633403778076,0.14249764382839203,0.0,1.0,0.0]],[[93.340576171875,0.0,27.89478874206543,0.7586024403572083,0.14249764382839203,0.0,1.0,0.0],[73.340576171875,0.0,27.89478874206543,0.7031919360160828,0.14249764382839203,0.0,1.0,0.0],[73.340576171875,0.0,39.013431549072266,0.7031919360160828,0.0,0.0,1.0,0.0]],[[73.340576171875,0.0,39.013431549072266,0.7031919360160828,0.0,0.0,1.0,0.0],[93.340576171875,0.0,39.013431549072266,0.7586024403572083,0.0,0.0,1.0,0.0],[93.340576171875,0.0,27.89478874206543,0.7586024403572083,0.14249764382839203,0.0,1.0,0.0]],[[180.47119140625,0.0,27.89478874206543,1.0,0.14249764382839203,0.0,1.0,0.0],[160.47119140625,0.0,27.89478874206543,0.9445894956588745,0.14249764382839203,0.0,1.0,0.0],[160.47119140625,0.0,39.013431549072266,0.9445894956588745,0.0,0.0,1.0,0.0]],[[160.47119140625,0.0,39.013431549072266,0.9445894956588745,0.0,0.0,1.0,0.0],[180.47119140625,0.0,39.013431549072266,1.0,0.0,0.0,1.0,0.0],[180.47119140625,0.0,27.89478874206543,1.0,0.14249764382839203,0.0,1.0,0.0]]]}]]====])
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
