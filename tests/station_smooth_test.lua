-- Pure mathematics and supplied terrain fixtures, never native acceptance.
local S=ug_require "oz_railway_network_architect::/geometry/station_smooth_preview.lua"
local curve=ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local passed=0
local function test(name,fn) local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));passed=passed+1;print('PASS smooth: '..name) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a)..' != '..tostring(b)) end
local function p(x,y,z) return {x=x,y=y,z=z or 0} end
local function encode(v)
    if type(v)~='table' then return tostring(v) end
    local keys,out={},{};for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..encode(v[k]) end
    return '{'..table.concat(out,',')..'}'
end
local function candidate(points)
    points=points or {p(0,0),p(128,0),p(256,64),p(384,64)}
    local a,b=points[1],points[#points]
    return {waypoints=points,stationSites={
        source={x=a.x-128,y=a.y,z=a.z,dx=1,dy=0,approach=p(a.x,a.y,a.z),length=160,width=48,approximate=true},
        destination={x=b.x+128,y=b.y,z=b.z,dx=-1,dy=0,approach=p(b.x,b.y,b.z),length=160,width=48,approximate=true}}}
end
local bounds={minX=-50000,maxX=50000,minY=-50000,maxY=50000}
local function run(c,objects,terrain,options,worldBounds)
    local j=S.start(c,options);local steps=0
    while not j.finished do
        local probe=S.probe(j)
        if probe then
            S.accept(j,terrain and terrain(probe) or {valid=true,height=probe.z,water=false,errors={}})
        else S.step(j,c,objects or {},worldBounds or bounds) end
        steps=steps+1;assert(steps<30000,'unbounded continuation')
    end
    return S.result(j),steps
end
test('gentle station alignment is smooth, bounded and preserves exact endpoints and all inputs',function()
    local c=candidate();local before=encode(c);local r=run(c)
    eq(r.status,'validated');eq(encode(c),before);eq(encode(r.points[1]),encode(c.waypoints[1]))
    eq(encode(r.points[#r.points]),encode(c.waypoints[#c.waypoints]))
    assert(#r.points>4 and #r.points<=1025);assert(r.maxCurvatureBound<=1/40);assert(r.maxGradientBound<=.08)
    local off=false;for _,q in ipairs(r.points) do if q.y<0 then off=true end end;assert(off,'must follow fitted curve, not original straight chords')
    eq(r.constructionStatus,'unverified');eq(r.terrainValidation,'sampled_not_continuous')
end)
test('endpoint directions match platform axes independently of diagonal neighboring chords',function()
    local points={p(0,0),p(128,64),p(256,64),p(384,0)}
    local r=curve.fit({unit='m',points=points,options={tangentScale=1.75,startDirection=p(1,0,.01),endDirection=p(1,0,-.02)}})
    eq(r.status,'candidate')
    local _,a=curve.evaluate(r.segments[1],0);local _,b=curve.evaluate(r.segments[#r.segments],1)
    near(a.y,0);near(b.y,0);assert(a.x>0 and b.x>0);near(a.z/a.x,.01);near(b.z/b.x,-.02)
    for i=2,#r.segments do for _,axis in ipairs({'x','y','z'}) do
        near(r.segments[i-1].tangent1[axis],r.segments[i].tangent0[axis])
    end end
end)
test('64 metre diagonal transitions can satisfy the preview radius with shared extended tangents',function()
    local r=run(candidate({p(0,0),p(64,0),p(128,64),p(192,64)}))
    assert(r.status=='validated',r.reason);assert(r.maxCurvatureBound<=1/40)
end)
test('rotated and reversed station approaches preserve forward travel and exact XYZ',function()
    local c=candidate();local forward=run(c);eq(forward.status,'validated')
    local reversed={};for i=#c.waypoints,1,-1 do reversed[#reversed+1]=c.waypoints[i] end
    local back={waypoints=reversed,stationSites={source=c.stationSites.destination,destination=c.stationSites.source}}
    local r=run(back);eq(r.status,'validated');eq(encode(r.points[1]),encode(reversed[1]))
    eq(encode(r.points[#r.points]),encode(reversed[#reversed]))
    for _,q in ipairs(c.waypoints) do q.x,q.y=-q.y,q.x end
    for _,site in pairs(c.stationSites) do
        site.x,site.y=-site.y,site.x;site.dx,site.dy=-site.dy,site.dx
        site.approach.x,site.approach.y=-site.approach.y,site.approach.x
    end
    r=run(c);eq(r.status,'validated');eq(r.points[1].y,c.stationSites.source.approach.y)
    eq(r.points[#r.points].x,c.stationSites.destination.approach.x)
end)
test('invalid or backwards endpoint directions cannot silently revert to chord directions',function()
    for _,v in ipairs({p(-1,0),p(0,0),p(0/0,1)}) do
        local r=curve.fit({unit='m',points={p(0,0),p(100,0)},options={startDirection=v}})
        assert(r.status~='candidate')
    end
end)
test('Bezier subdivision matches independently evaluated Hermite and bounds dense derivatives',function()
    local r=curve.fit({unit='m',points={p(-800,80,1),p(-600,100,3),p(-400,150,4)}})
    for _,s in ipairs(r.segments) do
        local b=curve.bezier(s);local left,right=curve.splitBezier(b)
        local mid=curve.evaluate(s,.5);for _,a in ipairs({'x','y','z'}) do near(left[4][a],mid[a]);near(right[1][a],mid[a]) end
        local v=curve.bezierBounds(b)
        for i=0,100 do
            local q,d,dd=curve.evaluate(s,i/100);local speed=math.sqrt(d.x*d.x+d.y*d.y)
            assert(q.x>=v.box.minX-1e-8 and q.x<=v.box.maxX+1e-8 and q.y>=v.box.minY-1e-8 and q.y<=v.box.maxY+1e-8)
            assert(math.abs(d.z)/speed<=v.maxGradient+1e-10)
            assert(math.abs(d.x*dd.y-d.y*dd.x)/speed^3<=v.maxCurvature+1e-10)
        end
    end
end)
test('radius assumption failure retains no partial smooth path',function()
    local r=run(candidate({p(0,0),p(64,0),p(64,64),p(128,64)}))
    eq(r.status,'fallback');assert(r.reason:find('sampled_radius=',1,true));eq(r.points,nil)
end)
test('uphill/downhill smooth grades checked on the new curves',function()
    for _,sign in ipairs({-1,1}) do
        local r=run(candidate({p(0,0,2),p(128,0,2+sign*6.4),p(256,0,2+sign*12.8)}))
        eq(r.status,'validated');near(r.maxGradientBound,.05)
    end
    local r=run(candidate({p(0,0),p(128,0,25.6)}));eq(r.status,'fallback')
end)
test('fresh curved terrain detects a ridge absent at original waypoints',function()
    local r=run(candidate(),{},function(q) return {valid=true,water=false,height=q.z+(q.x>20 and q.x<100 and 3 or 0)} end)
    eq(r.status,'fallback');eq(r.reason,'curve_terrain_clearance_assumption_exceeded');eq(r.points,nil)
end)
test('water on the centreline or ribbon sides excludes a smooth alternative',function()
    for _,side in ipairs({false,true}) do
        local r=run(candidate({p(0,0),p(256,0)}),{},function(q)
            return {valid=true,height=0,water=side and math.abs(q.y)>10 or (not side and q.x>100 and q.x<150)}
        end)
        eq(r.status,'fallback');eq(r.reason,'curve_water_excluded')
    end
end)
test('missing height and native read errors remain unknown',function()
    for _,raw in ipairs({{valid=true,water=false},{valid=false,height=0,water=false},{valid=true,height=0,water=false,errors={'exact read error'}}}) do
        local r=run(candidate(),{},function() return raw end);eq(r.status,'fallback');assert(r.reason:find('curve_terrain_unavailable',1,true))
    end
end)
test('complete Bezier hull checks catch a tiny obstacle between terrain probes',function()
    local r=run(candidate({p(0,0),p(256,0)}),{{id=88,kind='building',box={minX=70.01,maxX=70.02,minY=-.01,maxY=.01}}})
    eq(r.status,'fallback');assert(r.reason:find('known_hard_building:88',1,true))
end)
test('vegetation remains provisional while unknowns remain hard',function()
    local o={id=88,kind='vegetation',box={minX=70,maxX=80,minY=-20,maxY=20}}
    eq(run(candidate({p(0,0),p(256,0)}),{o}).status,'validated')
    o.kind='unknown';eq(run(candidate({p(0,0),p(256,0)}),{o}).status,'fallback')
end)
test('new curved ribbon cannot cut past an obstacle avoided by the original grid ribbon',function()
    local c=candidate({p(0,0),p(64,0),p(128,64),p(192,64)})
    local o={id=90,kind='building',box={minX=40,maxX=44,minY=-18,maxY=-17}}
    local occ=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
    for i=2,#c.waypoints do assert(not occ.crosses(c.waypoints[i-1],c.waypoints[i],o.box,12)) end
    eq(run(c).status,'validated')
    local r=run(c,{o});eq(r.status,'fallback');assert(r.reason:find('known_hard_building:90',1,true))
end)
test('continuous station reservation checks reject a whole curve span within a platform body',function()
    local c=candidate();local j=S.start(c)
    -- Independent straight Bezier span crossing the source platform body; no probe
    -- or waypoint-only test may skip the collision between its two endpoints.
    j.phase='validate';j.stack={{b={p(-240,0),p(-170,0),p(-100,0),p(-30,0)},depth=12}}
    S.step(j,c,{},bounds);eq(j.status,'fallback');eq(j.reason,'curve_station_reservation_unresolved')
end)
test('station reservations cannot be crossed by a looping curve',function()
    local c=candidate({p(0,0),p(256,0),p(512,256),p(256,512),p(-256,512),p(-256,0),p(-64,0)})
    local r=run(c);eq(r.status,'fallback') -- Fitting/deviation or reservation rejection is safe.
    eq(r.points,nil)
end)
test('no changes to station anchors and no town-center fallback on malformed endpoints',function()
    local c=candidate();c.stationSites.source.approach.z=7
    local r=run(c);eq(r.status,'fallback');eq(r.reason,'station_endpoint_mismatch');eq(r.points,nil)
end)
test('exact collinear cleanup supports long straight routes without truncation',function()
    local w={};for i=0,125 do w[#w+1]=p(-4000+i*64,-600,0) end
    local r=run(candidate(w));eq(r.status,'validated');eq(r.points[1].x,-4000);eq(r.points[#r.points].x,4000)
    eq(r.segments,512);assert(r.probeCount<=4097)
end)
test('render limits and subdivision/probe budgets fall back, never truncate',function()
    for _,policy in ipairs({{maxSegments=2},{maxNodes=2},{maxProbes=2},{maxDepth=1}}) do
        local r=run(candidate(),{},nil,policy);eq(r.status,'fallback');eq(r.points,nil)
    end
    local r=run(candidate({p(0,0),p(20000,0)}));eq(r.status,'fallback');assert(r.reason:find('render_limit',1,true))
end)
test('large noncollinear knot lists fail explicitly, without dropping the remainder',function()
    local w={};for i=0,256 do w[#w+1]=p(i*64,i%2*4) end
    local r=run(candidate(w));eq(r.reason,'curve_knot_limit_256_no_truncation');eq(r.points,nil)
end)
test('curve excursion beyond original corridor envelope is rejected',function()
    local r=run(candidate(),{},nil,{maxDeviation=.01})
    eq(r.status,'fallback');eq(r.reason,'curve_leaves_corridor_envelope')
end)
test('offset bounds and negative coordinates are respected without clamped terrain',function()
    local c=candidate({p(-1000,-200),p(-872,-200),p(-744,-136),p(-616,-136)})
    eq(run(c,{},nil,nil,{minX=-1200,maxX=-500,minY=-400,maxY=-50}).status,'validated')
    eq(run(c,{},nil,nil,{minX=-999,maxX=-500,minY=-400,maxY=-50}).status,'fallback')
end)
test('repeated results are deterministic and cancellation drops partial geometry',function()
    local c=candidate();eq(encode(run(c)),encode(run(c)))
    local j=S.start(c);S.step(j,c,{},bounds);S.step(j,c,{},bounds);S.reject(j,'world_invalidated')
    eq(S.result(j).status,'fallback');eq(j.points,nil);eq(j.curves,nil);eq(j.stack,nil)
end)
test('policy overrides cannot weaken geometry limits or increase resource budgets',function()
    for _,options in ipairs({{minRadius=1},{maxGradient=1},{maxSegments=2048},{maxTerrainDelta=100}}) do
        eq(S.start(candidate(),options).status,'fallback')
    end
    eq(S.start(candidate(),{minRadius=100}).status,'processing')
    eq(curve.fit({unit='m',points={p(0,0),p(100,0)},options={tangentScale=2.01}}).status,'invalid_input')
end)
print('PASS '..passed..' station smoothing tests (pure geometry and sampled terrain fixtures)')
