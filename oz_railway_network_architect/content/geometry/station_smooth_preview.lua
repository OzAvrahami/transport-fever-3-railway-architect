-- Bounded pure continuation around the authoritative Hermite fitter. Terrain is
-- requested as plain probes; the GUI owner supplies protected read-only responses.
local curve=ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local occupancy=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local sites=ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local flow=ug_require "oz_railway_network_architect::/live_plan_data.lua"
local S={}
function S.policy()
    return {minRadius=40,maxGradient=0.08,maxTerrainDelta=2,maxDeviation=24,
        chordError=0.25,maxSpan=16,maxSegments=1024,maxProbes=4097,maxNodes=8192,maxDepth=12}
end
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
local function valid(p) return type(p)=="table" and flow.finite(p.x) and flow.finite(p.y) and flow.finite(p.z)
    and math.abs(p.x)<=1e7 and math.abs(p.y)<=1e7 and math.abs(p.z)<=1e7 end
function S.reject(j,reason)
    j.finished=true;j.status="fallback";j.reason=reason
    j.points,j.knots,j.curves,j.stack,j.probes=nil,nil,nil,nil,nil
end
function S.start(c,options)
    local j={phase="copy",cursor=1,knots={},status="processing",policy=S.policy(),nodes=0,probeCount=0,
        maxCurvature=0,maxGradient=0,maxTerrainDelta=0,segments=0}
    if options then for k,v in pairs(options) do
        if j.policy[k]==nil or not flow.finite(v) or v<=0
            or (k=="minRadius" and (v<j.policy[k] or v>1e6))
            or (k~="minRadius" and v>j.policy[k]) then S.reject(j,"invalid_or_increased_smoothing_policy");return j end
        j.policy[k]=v
    end end
    if type(c)~="table" or type(c.waypoints)~="table" or #c.waypoints<2 or #c.waypoints>4096
        or not c.stationSites or not sites.valid(c.stationSites.source) or not sites.valid(c.stationSites.destination) then
        S.reject(j,"unsupported_station_curve_input");return j
    end
    j.source=copy(c.stationSites.source.approach);j.destination=copy(c.stationSites.destination.approach)
    if not valid(c.waypoints[1]) or not valid(c.waypoints[#c.waypoints])
        or not same(c.waypoints[1],j.source) or not same(c.waypoints[#c.waypoints],j.destination) then S.reject(j,"station_endpoint_mismatch") end
    return j
end
local function collinear(a,b,c)
    local x,y,z=b.x-a.x,b.y-a.y,b.z-a.z;local u,v,w=c.x-b.x,c.y-b.y,c.z-b.z
    return x*v-y*u==0 and x*w-z*u==0 and y*w-z*v==0 and x*u+y*v+z*w>0
end
local function finish(j)
    j.status="validated";j.finished=true;j.reason="bounded_curve_checks_passed;terrain_sampled;construction_unverified"
    j.curves,j.stack,j.knots,j.probes=nil,nil,nil,nil
end
function S.result(j)
    assert(j.finished)
    return {status=j.status,reason=j.reason,points=j.points,policy=j.policy,segments=j.segments,
        maxCurvatureBound=j.maxCurvature,maxGradientBound=j.maxGradient,maxSampledTerrainDelta=j.maxTerrainDelta,
        probeCount=j.probeCount,constructionStatus="unverified",terrainValidation="sampled_not_continuous",
        obstacleCoverage="known_local_AABBs_only",source=j.source,destination=j.destination}
end
local function nextProbe(j)
    if j.probes and j.probeIndex<=#j.probes then return j.probes[j.probeIndex] end
end
function S.probe(j) return nextProbe(j) end
function S.accept(j,raw)
    local p=nextProbe(j);assert(p and not j.finished)
    j.probeCount=j.probeCount+1
    if not raw or raw.valid~=true or not flow.finite(raw.height) or type(raw.water)~="boolean"
        or (raw.errors and #raw.errors>0) then
        S.reject(j,"curve_terrain_unavailable:"..tostring(raw and raw.errors and raw.errors[1] or "invalid_coordinate"));return
    end
    if raw.water then S.reject(j,"curve_water_excluded");return end
    local delta=math.abs(p.z-raw.height);j.maxTerrainDelta=math.max(j.maxTerrainDelta,delta)
    if delta>j.policy.maxTerrainDelta then S.reject(j,"curve_terrain_clearance_assumption_exceeded");return end
    j.probeIndex=j.probeIndex+1
    if not nextProbe(j) then j.probes=nil end
end
-- One bounded unit: 32 source points, one <=256-knot fit, or one subdivision node.
-- Native probes are performed separately by the owner, at most 16 per callback.
function S.step(j,c,objects,bounds)
    if j.finished or nextProbe(j) then return end
    local p=j.policy
    if j.phase=="copy" then
        for i=j.cursor,math.min(j.cursor+31,#c.waypoints) do
            local v=c.waypoints[i];if not valid(v) then S.reject(j,"invalid_curve_waypoint");return end
            local k=j.knots
            if #k>0 and same(k[#k],v) then S.reject(j,"duplicate_curve_waypoint");return end
            -- Only exact forward-collinear XYZ cleanup; no shortcut or lossy simplification.
            if #k>=2 and collinear(k[#k-1],k[#k],v) then k[#k]=copy(v) else k[#k+1]=copy(v) end
            if #k>256 then S.reject(j,"curve_knot_limit_256_no_truncation");return end
            j.cursor=i+1
        end
        if j.cursor>#c.waypoints then j.phase="fit" end
    elseif j.phase=="fit" then
        local k=j.knots;local a,b=k[1],k[2];local y,z=k[#k-1],k[#k]
        local source,dest=c.stationSites.source,c.stationSites.destination
        local h0=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2);local h1=math.sqrt((z.x-y.x)^2+(z.y-y.y)^2)
        if h0<=1e-6 or h1<=1e-6 then S.reject(j,"station_horizontal_chord_degenerate");return end
        -- A 75% longer shared interior derivative spreads grid turns. This is a
        -- fitting heuristic, not a railway standard; every resulting curve is checked.
        local fit=curve.fit({unit="m",points=k,options={diagnosticSteps=8,tangentScale=1.75,minRadius=p.minRadius,maxGradient=p.maxGradient,
            startDirection={x=source.dx,y=source.dy,z=(b.z-a.z)/h0},
            endDirection={x=-dest.dx,y=-dest.dy,z=(z.z-y.z)/h1}}})
        if fit.status~="candidate" then
            local reason=fit.reason
            if fit.diagnostics then
                reason="sampled_radius="..flow.number(fit.diagnostics.minSampledRadius)
                    .." min_radius="..p.minRadius.." sampled_grade="..flow.number(fit.diagnostics.maxAbsGradient).." max_grade="..p.maxGradient
            end
            S.reject(j,"curve_fit_"..fit.status..":"..tostring(reason));return
        end
        j.curves=fit.segments;j.index=1;j.stack={};j.points={copy(j.source)};j.phase="validate"
        j.probes={copy(j.source)};j.probeIndex=1
    elseif j.phase=="validate" then
        if #j.stack==0 then
            local segment=j.curves[j.index]
            if not segment then
                if not same(j.points[#j.points],j.destination) then S.reject(j,"curve_endpoint_changed");return end
                finish(j);return
            end
            local b=curve.bezier(segment);local bound=curve.bezierBounds(b)
            if not bound or bound.deviation>p.maxDeviation then S.reject(j,"curve_leaves_corridor_envelope");return end
            j.stack[1]={b=b,depth=0};j.index=j.index+1
        end
        j.nodes=j.nodes+1;if j.nodes>p.maxNodes then S.reject(j,"curve_subdivision_budget");return end
        local n=table.remove(j.stack);local b=n.b;local v=curve.bezierBounds(b)
        if not v then S.reject(j,"curve_stationary_span");return end
        local conflict
        for _,o in ipairs(objects) do
            if occupancy.hard(o) and occupancy.intersects(v.box,o.box,12+1/64) then conflict="known_hard_"..occupancy.kind(o)..":"..tostring(o.id);break end
        end
        for _,site in ipairs({c.stationSites.source,c.stationSites.destination}) do
            if occupancy.intersects(v.box,sites.bounds(site,site.length/2+12,site.width/2+12)) then conflict="station_reservation" end
        end
        if v.box.minX<=bounds.minX or v.box.maxX>=bounds.maxX or v.box.minY<=bounds.minY or v.box.maxY>=bounds.maxY then conflict="world_bounds" end
        local why=conflict or (v.maxCurvature>1/p.minRadius and "curvature_bound")
            or (v.maxGradient>p.maxGradient and "gradient_bound")
            or (v.deviation>p.chordError and "ribbon_error") or (v.polygonLength>p.maxSpan and "span_length")
        if why then
            if n.depth>=p.maxDepth then S.reject(j,"curve_"..why.."_unresolved");return end
            local left,right=curve.splitBezier(b)
            j.stack[#j.stack+1]={b=right,depth=n.depth+1};j.stack[#j.stack+1]={b=left,depth=n.depth+1};return
        end
        if j.segments>=p.maxSegments then S.reject(j,"curve_render_limit_no_truncation");return end
        if v.chord<0.001 then S.reject(j,"curve_render_segment_too_small");return end
        if j.probeCount+4>p.maxProbes then S.reject(j,"curve_terrain_probe_limit");return end
        local left=curve.splitBezier(b);local mid=left[4]
        local nx,ny=-(b[4].y-b[1].y)/v.chord*12,(b[4].x-b[1].x)/v.chord*12
        j.probes={copy(mid),copy(b[4]),{x=mid.x+nx,y=mid.y+ny,z=mid.z},{x=mid.x-nx,y=mid.y-ny,z=mid.z}};j.probeIndex=1
        j.segments=j.segments+1;j.points[#j.points+1]=copy(b[4])
        j.maxCurvature=math.max(j.maxCurvature,v.maxCurvature);j.maxGradient=math.max(j.maxGradient,v.maxGradient)
    end
end
return S
