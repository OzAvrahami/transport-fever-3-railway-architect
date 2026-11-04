-- Offline contract tests. Independent Bezier derivatives, NOT native compatibility mocks.
local curve = ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local adapter = ug_require "oz_railway_network_architect::/geometry/track_geometry_dto.lua"
local passed = 0
local function test(name, run)
    local ok, why = pcall(run); assert(ok, name .. ": " .. tostring(why))
    passed = passed+1; print("PASS geometry DTO: " .. name)
end
local function eq(a,b) assert(a==b, tostring(a).." ~= "..tostring(b)) end
local function near(a,b,e) assert(math.abs(a-b)<=(e or 1e-8), tostring(a).." != "..tostring(b)) end
local function p(x,y,z) return {x=x,y=y,z=z or 0} end
local function input(points, options)
    return {candidate=curve.fit({unit="m",points=points or {p(0,0),p(100,0)},options=options}),
        provenance={source="synthetic_fixture",coordinateFrame="world",candidateId="fixture:1",
            anchors={source={townId=1,approximation="bbox_center"},destination={townId=2}},
            water="unknown",obstacles="unknown"}}
end
local function encode(v)
    if type(v)~="table" then return tostring(v) end
    local keys, parts={},{}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do parts[#parts+1]=tostring(k).."="..encode(v[k]) end
    return "{"..table.concat(parts,",").."}"
end
local function valid(r)
    eq(r.status,"candidate"); eq(r.kind,"intermediate_track_geometry")
    eq(r.report.constructionStatus,"unverified"); eq(r.report.nativeProposalVerification,"not_run")
    eq(r.proposal,nil); eq(r.streetProposal,nil); eq(r.accepted,nil); eq(r.buildable,nil)
end
local function bad(v, reason, status)
    local r=adapter.convert(v); eq(r.status,status or "invalid_input"); eq(r.reason,reason)
    eq(r.segments,nil); eq(r.nodes,nil); eq(r.report.nativeProposalVerification,"not_run")
    return r
end
-- de Casteljau and derivative controls, independently of Hermite evaluation.
local function bezier(values,u)
    local t={table.unpack(values)}
    for n=#t-1,1,-1 do for i=1,n do t[i]=t[i]*(1-u)+t[i+1]*u end end
    return t[1]
end
local function reference(s,u)
    local q,d,dd={},{},{}
    for _,a in ipairs({"x","y","z"}) do
        local b={s.position0[a],s.position0[a]+s.tangent0[a]/3,s.position1[a]-s.tangent1[a]/3,s.position1[a]}
        local v={3*(b[2]-b[1]),3*(b[3]-b[2]),3*(b[4]-b[3])}
        q[a]=bezier(b,u); d[a]=bezier(v,u); dd[a]=bezier({2*(v[2]-v[1]),2*(v[3]-v[2])},u)
    end
    local h=math.sqrt(d.x*d.x+d.y*d.y)
    return q,d,dd,d.z/h,(d.x*dd.y-d.y*dd.x)/(h*h*h),
        (dd.z-d.z*(d.x*dd.x+d.y*dd.y)/(h*h))/(h*h)
end
test("straight field identity preserves derivative magnitude",function()
    local v=input(); local r=adapter.convert(v); valid(r)
    eq(#r.nodes,2); eq(#r.segments,1); eq(r.segments[1].tangent0.x,100); eq(r.segments[1].tangent1.x,100)
    for _,key in ipairs({"position0","position1","tangent0","tangent1"}) do eq(encode(r.segments[1][key]),encode(v.candidate.segments[1][key])) end
    near(r.report.sampledDiagnostics.approximateLength,100); eq(r.report.sampledDiagnostics.maxHorizontalCurvature,0)
end)
test("diagonal negative offset coordinates and full XYZ derivatives survive",function()
    local v=input({p(-300,40,-8),p(-260,70,-3)})
    local r=adapter.convert(v); valid(r); eq(r.segments[1].tangent1.z,5)
    eq(r.nodes[1].position.z,-8); near(r.report.sampledDiagnostics.maxAbsGradient,0.1)
    near(r.report.sampledDiagnostics.approximateLength,math.sqrt(2525))
end)
test("curved segments and sampled diagnostics match independent Bezier oracle",function()
    local v=input({p(0,0,2),p(100,10,4),p(170,40,-3),p(300,70,1)})
    local r=adapter.convert(v); valid(r)
    for _,s in ipairs(r.segments) do
        local maxG,maxK,length,prev=0,0,0,nil
        for j=0,32 do
            local q,d,dd,g,k=reference(s,j/32)
            local actual,ad,add=curve.evaluate(s,j/32)
            for _,a in ipairs({"x","y","z"}) do near(q[a],actual[a]);near(d[a],ad[a]);near(dd[a],add[a]) end
            if prev then length=length+math.sqrt((q.x-prev.x)^2+(q.y-prev.y)^2+(q.z-prev.z)^2) end
            prev=q;maxG=math.max(maxG,math.abs(g));maxK=math.max(maxK,math.abs(k))
        end
        near(s.diagnostics.approximateLength,length);near(s.diagnostics.maxAbsGradient,maxG);near(s.diagnostics.maxHorizontalCurvature,maxK)
    end
end)
test("multi-segment shared endpoints and local indices are exact",function()
    local v=input({p(0,0),p(100,0),p(120,20),p(180,20)})
    local r=adapter.convert(v); valid(r);eq(#r.nodes,4);eq(#r.report.joins,2)
    for i,s in ipairs(r.segments) do
        eq(s.node0Index,i);eq(s.node1Index,i+1);eq(s.entity,nil)
        eq(encode(r.nodes[i].position),encode(s.position0));eq(encode(r.nodes[i+1].position),encode(s.position1))
    end
end)
test("C1 preserves grade but does not imply curvature or grade-rate continuity",function()
    local v=input({p(0,0,0),p(100,0,10),p(180,30,0)})
    local r=adapter.convert(v);valid(r);local j=r.report.joins[1]
    eq(j.C0,true);eq(j.C1,true);eq(j.C2,false);near(j.gradientJump,0)
    assert(math.abs(j.curvatureJump)>1e-6);assert(math.abs(j.gradientRateJump)>1e-6)
    local _,dl,_,gl,kl,rl=reference(r.segments[1],1)
    local _,dr,_,gr,kr,rr=reference(r.segments[2],0)
    for _,a in ipairs({"x","y","z"}) do near(dl[a],dr[a]) end
    near(gl,gr);near(j.curvatureJump,kr-kl);near(j.gradientRateJump,rr-rl)
end)
test("reversed endpoint tangent is not silently repaired",function()
    local v=input();v.candidate.segments[1].tangent1.x=-100
    bad(v,"non_forward_or_stationary_tangent_at_1","unsupported")
end)
test("entire reversed route remains forward in its own direction",function()
    local r=adapter.convert(input({p(100,0),p(0,0)}));valid(r)
    eq(r.segments[1].tangent0.x,-100);eq(r.segments[1].tangent1.x,-100)
end)
test("shared endpoint gap is rejected without welding",function()
    local v=input({p(0,0),p(100,0),p(200,0)});v.candidate.segments[2].position0.x=100+1e-10
    local r=bad(v,"endpoint_or_source_discontinuity_at_2");eq(r.report.endpointContinuity,"failed")
end)
test("same-direction unequal tangent magnitude is not C1",function()
    local v=input({p(0,0),p(100,0),p(200,0)});v.candidate.segments[2].tangent0.x=99
    bad(v,"join_not_exact_C1_at_2","unsupported")
end)
test("zero-length and zero tangent geometry fail",function()
    local v=input();v.candidate.segments[1].position1=p(0,0)
    bad(v,"degenerate_horizontal_chord_at_1","unsupported")
    v=input();v.candidate.segments[1].tangent0=p(0,0)
    bad(v,"non_forward_or_stationary_tangent_at_1","unsupported")
end)
test("positive endpoint tangents do not hide an interior reversal",function()
    local v=input();v.candidate.segments[1].tangent0.x=400;v.candidate.segments[1].tangent1.x=400
    bad(v,"non_forward_or_stationary_tangent_at_1","unsupported")
end)
test("missing template is an explicit prerequisite not a fabricated default",function()
    local r=adapter.convert(input());valid(r);eq(r.templateReferences,nil);eq(r.report.trackTemplateReadiness,"missing")
    eq(r.report.terrainAndCollisions,"not_verified");eq(r.report.bridgeTunnelDecisions,"not_assessed")
    eq(r.report.existingInfrastructureConnections,"not_assessed");assert(#r.report.missingPrerequisites>=6)
end)
test("supplied template strings are not proof of resource readiness",function()
    local v=input();v.template={roadTemplate="::/infrastructure/track/standard/standard.street_template",roadStyle="::/infrastructure/track/standard/standard.street"}
    local r=adapter.convert(v);valid(r);eq(encode(r.templateReferences),encode(v.template))
    eq(r.report.trackTemplateReadiness,"references_supplied_not_resolved");eq(r.segments[1].laneConfigs,nil)
end)
test("malformed native proposal fields are rejected rather than forwarded",function()
    local v=input();v.streetProposal={};bad(v,"input_contract")
    v=input();v.candidate.proposal={};bad(v,"candidate_contract")
    v=input();v.candidate.segments[1].node0=-1;bad(v,"segment_fields_at_1")
    v=input();v.template={roadTemplate="x",roadStyle="y",catenary=true};bad(v,"template_fields")
    v=input();v.template={roadTemplate="x"};bad(v,"template_resource_reference")
end)
test("invalid incomplete sparse and non-finite geometry fail",function()
    for _,value in ipairs({math.huge,0/0,1e9,"0"}) do
        local v=input();v.candidate.segments[1].position0.x=value;bad(v,"position0_invalid_at_1")
    end
    local v=input();v.candidate.segments[1].tangent1=nil;bad(v,"tangent1_invalid_at_1")
    v=input();v.candidate.segments[2]=v.candidate.segments[1];v.candidate.segments[1]=nil;bad(v,"segment_fields_at_1")
    v=input();v.candidate.segments={};bad(v,"empty_geometry")
    v=input();v.candidate.unit="km";bad(v,"candidate_contract")
    v=input();v.candidate.parameter="unit_directions";bad(v,"candidate_contract")
end)
test("diagnostics recomputed and violations never upgraded by a stale input status",function()
    local v=input({p(0,0),p(100,0,10)},{maxGradient=0.02})
    v.candidate.diagnostics.maxAbsGradient=0;v.candidate.status="candidate"
    local r=adapter.convert(v);eq(r.status,"diagnostic_violation");near(r.report.sampledDiagnostics.maxAbsGradient,0.1)
    eq(r.report.sampledDiagnostics.gradientViolations,1);eq(r.report.constructionStatus,"unverified")
    v=input({p(0,0),p(100,0),p(100,100)},{minRadius=1000})
    r=adapter.convert(v);eq(r.status,"diagnostic_violation");assert(r.report.sampledDiagnostics.radiusViolations>0)
end)
test("removed duplicate source indices and provenance stay intact",function()
    local v=input({p(0,0),p(0,0),p(100,0),p(100,0),p(200,0)})
    local r=adapter.convert(v);valid(r);eq(r.sourceRemovedDuplicates,2)
    eq(r.nodes[1].sourcePointIndex,1);eq(r.nodes[2].sourcePointIndex,3);eq(r.nodes[3].sourcePointIndex,5)
    eq(encode(r.provenance),encode(v.provenance))
    v.candidate.segments[2].sourceStartIndex=4;bad(v,"endpoint_or_source_discontinuity_at_2")
end)
test("source diagnostic warning is retained even when recomputed samples pass",function()
    local v=input();v.candidate.status="diagnostic_violation"
    local r=adapter.convert(v);eq(r.status,"diagnostic_violation");eq(r.sourceCandidateStatus,"diagnostic_violation")
    eq(r.report.sampledDiagnostics.gradientViolations,0);eq(r.report.nativeProposalVerification,"not_run")
end)
test("input and output data do not alias and repeated results are deterministic",function()
    local v=input({p(0,0),p(100,20),p(180,0)})
    local before=encode(v);local r=adapter.convert(v);valid(r)
    eq(encode(r),encode(adapter.convert(v)));eq(encode(v),before)
    r.nodes[1].position.x=999;r.segments[1].position0.x=888;r.provenance.anchors.source.townId=500
    r.assumptions.minChord=99;r.sourceWarnings[1]="changed"
    eq(encode(v),before);eq(v.candidate.segments[1].position0.x,0)
end)
test("long route at maximum size has bounded diagnostics and no sample arrays",function()
    local points={};for i=1,256 do points[i]=p(-20000+i*100,math.sin(i/10)*20,-10+i/100) end
    local r=adapter.convert(input(points,{diagnosticSteps=64}));valid(r)
    eq(#r.segments,255);eq(#r.nodes,256);eq(#r.report.joins,254)
    eq(r.report.sampledDiagnostics.evaluatedPoints,255*65)
    eq(r.report.sampledDiagnostics.joinEvaluations,2*254)
    for _,s in ipairs(r.segments) do eq(s.samples,nil);eq(s.waypoints,nil) end
end)
test("segment and diagnostic-work hard limits reject without truncating",function()
    local v=input();for i=2,256 do v.candidate.segments[i]=v.candidate.segments[1] end
    bad(v,"max_segments_255","resource_limit")
    v=input();v.candidate.assumptions.diagnosticSteps=65;bad(v,"candidate_assumptions")
end)
test("provenance requires explicit world frame and bounded plain data",function()
    local v=input();v.provenance.coordinateFrame="construction_local";bad(v,"explicit_world_provenance_required")
    v=input();v.provenance.loop=v.provenance;bad(v,"metadata_depth_or_cycle")
    v=input();v.provenance.source=string.rep("s",1025);bad(v,"metadata_limit")
    v=input();v.provenance.extra={};for i=1,257 do v.provenance.extra[i]=i end;bad(v,"metadata_limit")
    v=input();v.provenance.payload=function() end;bad(v,"metadata_not_plain")
end)
test("native and file APIs are never invoked",function()
    local oldApi,oldIo=api,io
    local trap=setmetatable({}, {__index=function() error("forbidden engine or file access") end})
    api,io=trap,trap
    local ok,r=pcall(adapter.convert,input());api,io=oldApi,oldIo
    assert(ok,r);valid(r)
end)
print(string.format("PASS %d geometry DTO tests",passed))
