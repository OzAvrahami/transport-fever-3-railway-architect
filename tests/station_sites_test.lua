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
    eq(select(2,sites.screen(c,a,bounds)),"station_body_unknown")
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
local policy=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local function object(kind,x,y,half)
    half=half or 2
    return {id=500,kind=kind,source="synthetic_"..kind,box={minX=x-half,maxX=x+half,minY=y-half,maxY=y+half}}
end
test("occupancy: body and facing approach are separate from broad inspection",function()
    local c=fixture();local r=policy.regions(c)
    eq(r.body.maxX-r.body.minX,168);eq(r.body.maxY-r.body.minY,56)
    eq(r.approach.minX,76);eq(r.approach.maxX,132);eq(r.approach.maxY-r.approach.minY,32)
    eq(r.neighborhood.maxX-r.neighborhood.minX,512)
    c.dx=0;c.dy=-1;r=policy.regions(c);eq(r.approach.minY,c.y-132);eq(r.approach.maxX-r.approach.minX,32)
end)
test("occupancy: buildings constructions tracks and unknowns in body remain hard blockers",function()
    local c=fixture()
    for _,kind in ipairs({'building','construction','track','unknown'}) do
        local ok,reason,r=policy.inspect(c,{object(kind,c.x,c.y)})
        eq(ok,false);eq(reason,'station_body_'..kind);eq(r.bodyConflicts,1);eq(r.blockedKinds[kind],true)
    end
end)
test("occupancy: rear and remote buildings in old envelope do not become mandatory footprint conflicts",function()
    local c=fixture();local o=object('building',c.x-200,c.y)
    local ok,_,r=policy.inspect(c,{o});eq(ok,true);eq(r.neighborhood.building,1);eq(r.bodyConflicts,0);eq(r.approachConflicts,0)
    o=object('unknown',c.x+200,c.y);ok,_,r=policy.inspect(c,{o});eq(ok,true);eq(r.neighborhood.unknown,1)
end)
test("occupancy: nearby road is access evidence but crossing a station or approach blocks",function()
    local c,a=fixture();local road=object('street',0,c.y+31,2);road.a={x=-20,y=c.y+31};road.b={x=20,y=c.y+31}
    a.objects[#a.objects+1]=road;assert(sites.screen(c,a,bounds));eq(c.evidence.walkingAccess,'unknown')
    road.box=object('street',0,c.y).box;eq(select(2,sites.screen(c,a,bounds)),'station_body_street')
    road.box=object('street',110,c.y).box;eq(select(2,sites.screen(c,a,bounds)),'approach_unresolved_street')
end)
test("occupancy: verified vegetation is provisional clearance, unknown approach remains unresolved",function()
    local c,a=fixture();a.objects[#a.objects+1]=object('vegetation',110,c.y)
    assert(sites.screen(c,a,bounds));eq(c.evidence.vegetationClearance,1);eq(c.evidence.clearanceStatus,'provisional_vegetation_clearance')
    a.objects[#a.objects].kind='unknown';eq(select(2,sites.screen(c,a,bounds)),'approach_unresolved_unknown')
end)
test("occupancy: empty and heavily occupied regions have exact bounded diagnostics",function()
    local c=fixture();local ok,_,r=policy.inspect(c,{});eq(ok,true);eq(#r.examples,0)
    local objects={};for i=1,100 do objects[i]=object('building',0,c.y);objects[i].id=i end
    ok,_,r=policy.inspect(c,objects);eq(ok,false);eq(r.bodyConflicts,100);eq(#r.examples,3)
end)
test("occupancy: masks preserve hard obstacles and provisional vegetation without blanket 80 m exclusion",function()
    local o=object('building',0,0)
    assert(policy.blocksSample(o,0,0));assert(not policy.blocksSample(o,40,0))
    o.kind='vegetation';assert(not policy.blocksSample(o,0,0));o.kind='unknown';assert(policy.blocksSample(o,0,0))
end)
test("occupancy: exact segment guard rejects jumping over small buildings roads or unknowns",function()
    local a,b={x=-64,y=0},{x=64,y=0}
    for _,kind in ipairs({'building','construction','street','track','unknown'}) do
        local o=object(kind,0,0);assert(not policy.blocksSample(o,a.x,a.y));assert(not policy.blocksSample(o,b.x,b.y))
        eq(policy.segment(a,b,{o}),o)
    end
    local hit,veg=policy.segment(a,b,{object('vegetation',0,0)});eq(hit,nil);eq(veg,true)
    eq(policy.segment({x=-64,y=40},{x=64,y=40},{object('building',0,0)}),nil)
end)
test("occupancy: exact guard handles diagonal corner touches negative offsets and reversed travel",function()
    local o=object('building',-100,200,4)
    assert(policy.segment({x=-132,y=168},{x=-68,y=232},{o}))
    assert(policy.segment({x=-68,y=232},{x=-132,y=168},{o}))
    eq(policy.segment({x=-132,y=250},{x=-68,y=250},{o}),nil)
end)
test("occupancy: forward exit evidence ranks sites without reclassifying the neighborhood as a footprint",function()
    local c,a=fixture();a.objects[#a.objects+1]=object('building',200,c.y)
    assert(sites.screen(c,a,bounds));assert(sites.evaluate(c,samples()));eq(c.evidence.approachExitBlocked,true)
    local alternative=copy(c);alternative.id='clear';alternative.x=512;alternative.siteScore=c.siteScore+1
    alternative.evidence.approachExitBlocked=false
    local list=sites.shortlist({c,alternative});eq(list[1].id,'clear');eq(#list,2)
end)
test("occupancy: search approach mask matches accepted direction rule without blocking the exact anchor",function()
    local a,d={x=-128,y=256},{dx=1,dy=0}
    eq(policy.blocksApproach(a,d,-128,256,64),false)
    eq(policy.blocksApproach(a,d,-64,256,64),false);eq(policy.blocksApproach(a,d,-64,320,64),false)
    eq(policy.blocksApproach(a,d,-128,320,64),true);eq(policy.blocksApproach(a,d,-192,256,64),true)
    eq(policy.blocksApproach(a,d,-256,256,64),false)
end)
print("PASS "..passed.." station site tests (synthetic, not native acceptance)")
