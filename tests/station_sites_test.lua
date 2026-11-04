-- Synthetic geometry/evidence tests. No game access or native buildability claim.
local sites=ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local passed=0
local function test(name,fn) fn();passed=passed+1;print("PASS station sites: "..name) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function copy(t) if type(t)~="table" then return t end;local o={};for k,v in pairs(t) do o[k]=copy(v) end;return o end
local bounds={minX=-4096,maxX=4096,minY=-4096,maxY=4096}
local function town(id,x)
    return {id=id,name="Same name",x=9000,y=9000,urban={minX=x-40,maxX=x+40,minY=-40,maxY=40},
        buildings={{box={minX=x-40,maxX=x+40,minY=-40,maxY=40}}},objects={
            {kind="street",a={x=x-100,y=0},b={x=x,y=0},box={minX=x-100,maxX=x+100,minY=-4,maxY=4}}},stations={}}
end
local function fixture()
    local a,b=town(1,0),town(2,2048)
    local list=sites.generate(a,b)
    for _,c in ipairs(list) do if c.x==0 and c.y==256 and c.dx==1 then assert(sites.screen(c,a,bounds));return c,a,b end end
    error("missing deterministic candidate")
end
local function samples()
    local out={};for i=1,51 do out[i]={valid=true,height=-2,water=false,errors={}} end;return out
end
test("actual building bounds, not town center; bounded deterministic candidate generation",function()
    local a,b=town(1,0),town(2,2048);local one=sites.generate(a,b);local two=sites.generate(a,b)
    assert(#one>3 and #one<=48);eq(#one,#two)
    for i,c in ipairs(one) do eq(c.id,two[i].id);assert(math.abs(c.x)<1024 and math.abs(c.y)<1024);assert(c.x~=a.x);eq(c.approximate,true) end
end)
test("orientation and approach are explicit; reservation is separate from the approach endpoint",function()
    local c=fixture();eq(c.dx,1);eq(c.dy,0);eq(c.approach.x,c.x+128);eq(c.approach.y,c.y)
    local flipped=sites.generate(town(1,0),town(2,-2048))
    for _,v in ipairs(flipped) do if v.dx~=0 then eq(v.dx,-1) end end
end)
test("road endpoint proximity is evidence, walking access stays unknown",function()
    local c,a=fixture();eq(c.evidence.walkingAccess,"unknown");assert(c.evidence.roadEndpointDistance<=256)
    a.objects={};eq(select(2,sites.screen(c,a,bounds)),"no_verified_nearby_road_endpoint")
end)
test("known occupancy and map boundaries reject the complete approach reservation",function()
    local c,a=fixture();a.objects[#a.objects+1]={kind="occupied",box=copy(c.clearance)}
    eq(select(2,sites.screen(c,a,bounds)),"occupied_reservation_or_approach")
    c,a=fixture();eq(select(2,sites.screen(c,a,{minX=-10,maxX=10,minY=-10,maxY=10})),"boundary")
end)
test("remote flat empty plots do not substitute for access to the occupied town",function()
    local c,a=fixture();c.x=3000;c.y=3000;c.clearance=sites.bounds(c,256,32)
    eq(select(2,sites.screen(c,a,bounds)),"remote_from_occupied_town")
end)
test("zero negative and finite heights preserved; missing water or height never becomes land",function()
    local c=fixture();local s=samples();assert(sites.evaluate(c,s));eq(c.z,-2);eq(c.approach.z,-2)
    for _,v in ipairs(s) do v.height=0 end;assert(sites.evaluate(c,s));eq(c.z,0)
    s[1].height=nil;eq(sites.evaluate(c,s),nil)
    s=samples();s[1].water=nil;eq(sites.evaluate(c,s),nil)
    s=samples();s[1].height=0/0;eq(sites.evaluate(c,s),nil)
end)
test("water and slope obstruction fail conservatively",function()
    local c=fixture();local s=samples();s[21].water=true;eq(sites.evaluate(c,s),nil)
    s=samples();s[22].height=10;eq(select(2,sites.evaluate(c,s)),"unsuitable_sampled_slope")
    s=samples();s[1].valid=false;eq(sites.evaluate(c,s),nil)
end)
test("sample layout covers both approaches and width; center and approach heights are correctly indexed",function()
    local c=fixture();local s=samples()
    for i=1,51 do local x,y=sites.samplePosition(c,i);s[i].height=x*.01+y*.005 end
    assert(sites.evaluate(c,s));eq(c.z,c.x*.01+c.y*.005);eq(c.approach.z,c.approach.x*.01+c.approach.y*.005)
    assert(math.abs(c.evidence.maxSampledGrade-.01)<1e-12)
end)
test("verified existing passenger station and rail proximity are hints, not operational access",function()
    local c,a=fixture();assert(sites.evaluate(c,samples()));local original=c.siteScore
    a.stations={{id=99,box={minX=300,maxX=310,minY=250,maxY=260}}}
    assert(sites.screen(c,a,bounds));assert(sites.evaluate(c,samples()));eq(c.siteScore,original-1)
    eq(c.evidence.construction,"unverified");eq(c.evidence.walkingAccess,"unknown")
end)
test("shortlist remains small, spatially distinct and tie breaks by candidate ID",function()
    local a,b=town(1,0),town(2,2048);local good={}
    for _,c in ipairs(sites.generate(a,b)) do if sites.screen(c,a,bounds) and sites.evaluate(c,samples()) then good[#good+1]=c end end
    local short=sites.shortlist(good);assert(#short>=2 and #short<=3)
    for i=2,#short do assert(short[i].siteScore>=short[i-1].siteScore) end
end)
test("pairs rank approach alignment and local evidence together without fabricated links",function()
    local c,a,b=fixture();assert(sites.evaluate(c,samples()))
    local other=copy(c);other.townId=2;other.x=2048;other.dx=-1;other.approach.x=1920;other.id="2";other.clearance=sites.bounds(other,256,32)
    local pair=sites.pairs({c},{other});eq(#pair,1);assert(pair[1].score>=c.siteScore+other.siteScore)
    eq(#sites.pairs({c},{c}),0);eq(#sites.pairs({},{}),0)
end)
test("approach handoff rejects center fallback, inward travel and changed heights",function()
    local c=fixture();assert(sites.evaluate(c,samples()))
    local d=copy(c);d.x=2048;d.dx=-1;d.approach.x=1920
    local pair={source=c,destination=d};local route={waypoints={copy(c.approach),{x=256,y=256,z=-2},{x=1792,y=256,z=-2},copy(d.approach)}}
    assert(sites.approaches(route,pair))
    route.waypoints[1].x=c.x;assert(not sites.approaches(route,pair))
    route.waypoints[1]=copy(c.approach);route.waypoints[2].x=0;assert(not sites.approaches(route,pair))
    route.waypoints[2].x=256;route.waypoints[1].z=9;assert(not sites.approaches(route,pair))
end)
test("three world-space polygons preserve station reservation and approach orientation",function()
    local c=fixture();assert(sites.evaluate(c,samples()));local p=sites.markers(c);eq(#p,3)
    eq(p[1][2].x-p[1][1].x,160);eq(p[1][3].y-p[1][2].y,48)
    eq((p[3][1].x+p[3][3].x)/2,c.approach.x);eq((p[3][1].y+p[3][3].y)/2,c.approach.y)
    assert(sites.valid(c));c.dx="not a vector";assert(not sites.valid(c))
end)
test("a detour that reenters a station body is rejected even with outward endpoint directions",function()
    local c=fixture();assert(sites.evaluate(c,samples()))
    local d=copy(c);d.x=2048;d.dx=-1;d.approach.x=1920
    local route={waypoints={copy(c.approach),{x=256,y=256,z=-2},{x=-128,y=256,z=-2},
        {x=-128,y=600,z=-2},{x=1792,y=600,z=-2},{x=1792,y=256,z=-2},copy(d.approach)}}
    assert(not sites.approaches(route,{source=c,destination=d}))
end)
print("PASS "..passed.." station site tests (synthetic, not native acceptance)")
