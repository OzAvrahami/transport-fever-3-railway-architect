-- Offline data assembly tests, with no native API objects or compatibility mocks.
local curve=ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local dto=ug_require "oz_railway_network_architect::/geometry/track_geometry_dto.lua"
local assembly=ug_require "oz_railway_network_architect::/geometry/track_proposal_assembly.lua"
local passed=0
local function test(name,fn)
    local ok,err=pcall(fn);assert(ok,name..": "..tostring(err));passed=passed+1;print("PASS assembly: "..name)
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function p(x,y,z) return {x=x,y=y,z=z or 0} end
local function encode(v)
    if type(v)~="table" then return tostring(v) end
    local keys,out={},{};for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do out[#out+1]=tostring(k).."="..encode(v[k]) end
    return "{"..table.concat(out,",").."}"
end
local function fixture(points,options)
    return {geometry=dto.convert({candidate=curve.fit({unit="m",points=points or {p(0,0),p(100,0)},options=options}),
        provenance={source="synthetic_corridor",coordinateFrame="world",anchor={kind="approximate",townId=99}}}),
        track={roadTemplate="::/infrastructure/track/standard/standard.street_template",
            roadStyle="::/infrastructure/track/standard/standard.street",roadType="TRACK",edgeMode="NORMAL",typeIndex=1,
            laneConfigs={{speed=44.439998626708984375,width=4,height=0.5299999713897705078125,offset=0,forward=true,
                transportModes={TRAIN=true,TRAM_TRACK=true}}},
            provenance={basis="synthetic",source="standard template values; typeIndex=1 from mission example; not live resolved"}},
        endpoints={start="isolated_new",finish="isolated_new"},ownership="unresolved"}
end
local function good(input)
    local r=assembly.assemble(input);eq(r.status,"descriptor");eq(r.nativeReadiness,"blocked")
    eq(r.nativeProcessing,"not_run");eq(r.constructionAcceptance,"unverified");eq(r.nativeObjectsCreated,false)
    eq(r.accepted,nil);eq(r.buildable,nil);eq(r.simpleProposal,nil);eq(r.proposal,nil)
    return r
end
local function bad(input,reason)
    local r=assembly.assemble(input);eq(r.status,"invalid_input");eq(r.reason,reason)
    eq(r.streetProposal,nil);eq(r.nativeObjectsCreated,false)
end
test("single straight alignment has explicit fields and preserves metre derivatives",function()
    local r=good(fixture());local s=r.streetProposal;eq(#s.nodesToAdd,2);eq(#s.edgesToAdd,1)
    eq(s.nodesToAdd[1].entity,-1);eq(s.nodesToAdd[2].entity,-2)
    local e=s.edgesToAdd[1];eq(e.entity,-3);eq(e.comp.node0,-1);eq(e.comp.node1,-2)
    eq(e.type,1);eq(e.comp.type,"NORMAL");eq(e.comp.roadType,"TRACK");eq(e.comp.tangent0.x,100);eq(e.comp.tangent1.x,100)
    eq(e.comp.position1.x,100);eq(e.playerOwned,nil);eq(e.streetEdge,nil)
end)
test("two segments share one canonical node with globally unique IDs",function()
    local r=good(fixture({p(0,0),p(100,0),p(200,0)}));local s=r.streetProposal
    eq(#s.nodesToAdd,3);eq(s.edgesToAdd[1].entity,-4);eq(s.edgesToAdd[2].entity,-5)
    eq(s.edgesToAdd[1].comp.node1,s.edgesToAdd[2].comp.node0);eq(s.edgesToAdd[1].comp.node1,-2)
    local ids={};for _,list in ipairs({s.nodesToAdd,s.edgesToAdd}) do for _,x in ipairs(list) do assert(not ids[x.entity]);ids[x.entity]=true end end
    for i=1,5 do assert(ids[-i]) end
end)
test("curved multi-segment geometry preserves every coordinate tangent and source index",function()
    local f=fixture({p(-200,50,-9),p(-100,60,-4),p(0,90,2),p(80,100,1)})
    local r=good(f)
    for i,s in ipairs(f.geometry.segments) do
        local e=r.streetProposal.edgesToAdd[i]
        for _,key in ipairs({"position0","position1","tangent0","tangent1"}) do eq(encode(e.comp[key]),encode(s[key])) end
        eq(r.segmentSources[i].sourceStartIndex,s.sourceStartIndex);eq(r.segmentSources[i].sourceEndIndex,s.sourceEndIndex)
        eq(r.segmentSources[i].entity,e.entity)
        local n0=r.streetProposal.nodesToAdd[-e.comp.node0];local n1=r.streetProposal.nodesToAdd[-e.comp.node1]
        eq(encode(n0.comp.position),encode(e.comp.position0));eq(encode(n1.comp.position),encode(e.comp.position1))
    end
end)
test("forward and reversed alignments have independent Bezier reversal equivalence",function()
    local forward=good(fixture({p(0,0,1),p(100,20,4),p(180,70,2)}))
    local reversed=good(fixture({p(180,70,2),p(100,20,4),p(0,0,1)}))
    for i,e in ipairs(forward.streetProposal.edgesToAdd) do
        local s=e.comp;local r=reversed.streetProposal.edgesToAdd[3-i].comp
        for _,a in ipairs({"x","y","z"}) do
            eq(s.position0[a],r.position1[a]);eq(s.position1[a],r.position0[a])
            eq(s.tangent0[a],-r.tangent1[a]);eq(s.tangent1[a],-r.tangent0[a])
            -- Compare corresponding Bezier handles, independently of curve.evaluate.
            eq(s.position0[a]+s.tangent0[a]/3,r.position1[a]-r.tangent1[a]/3)
            eq(s.position1[a]-s.tangent1[a]/3,r.position0[a]+r.tangent0[a]/3)
        end
    end
end)
test("explicit isolated roles cannot be inferred from town anchors",function()
    local f=fixture();f.endpoints=nil;bad(f,"explicit_isolated_endpoints_required")
    f=fixture();f.endpoints.finish="station";bad(f,"explicit_isolated_endpoints_required")
    f=fixture();f.endpoints.start="existing_track";bad(f,"explicit_isolated_endpoints_required")
    f=fixture();f.endpoints.entity=42;bad(f,"explicit_isolated_endpoints_required")
end)
test("missing track configuration never selects default resources or type index",function()
    local f=fixture();f.track=nil;bad(f,"track_configuration_required")
    f=fixture();f.track.typeIndex=nil;bad(f,"explicit_typeIndex_required")
    f=fixture();f.track.roadTemplate=nil;bad(f,"invalid_resource_reference")
    f=fixture();f.track.roadStyle=nil;bad(f,"invalid_resource_reference")
    f=fixture();f.track.laneConfigs=nil;bad(f,"lane_count_1_8_required")
    f=fixture();f.track.provenance=nil;bad(f,"resource_provenance_required")
end)
test("malformed resources and conflicting DTO resource provenance fail",function()
    for _,name in ipairs({"standard.street_template","::/../standard.street_template","::/x\\y.street_template","::/x.street","::/x\ny.street_template"}) do
        local f=fixture();f.track.roadTemplate=name;bad(f,"invalid_resource_reference")
    end
    local f=fixture();f.geometry.templateReferences={roadTemplate="::/other.street_template",roadStyle=f.track.roadStyle}
    bad(f,"geometry_resource_mismatch")
    f=fixture();f.geometry.templateReferences={roadTemplate=f.track.roadTemplate,roadStyle=f.track.roadStyle};good(f)
end)
test("lane fields preserve boolean enum symbols and require actual rail modes",function()
    local f=fixture();local l=f.track.laneConfigs[1];l.forward=false;l.transportModes.ELECTRIC_TRAIN=false
    local r=good(f);local out=r.streetProposal.edgesToAdd[1].comp.laneConfigs[1]
    eq(encode(out),encode(l));eq(out.transportModes.ELECTRIC_TRAIN,false)
    l.transportModes={CAR=true};bad(f,"invalid_lane_at_1")
    l.transportModes={TRAIN=1};bad(f,"mode_flags_must_be_boolean")
    l.transportModes={TRAIN=false,TRAM_TRACK=true};bad(f,"train_mode_required_at_1")
end)
test("nonfinite invalid and excessive lane data fail without truncation",function()
    local f=fixture();f.track.laneConfigs[1].width=0;bad(f,"nonpositive_lane_speed_or_width_at_1")
    f=fixture();f.track.laneConfigs[1].height=0/0;bad(f,"invalid_lane_height_at_1")
    f=fixture();f.track.laneConfigs[1].offset=math.huge;bad(f,"invalid_lane_offset_at_1")
    f=fixture();for i=2,9 do f.track.laneConfigs[i]=f.track.laneConfigs[1] end;bad(f,"lane_count_1_8_required")
end)
test("unknown native enum numbers and bridge tunnel modes are not guessed",function()
    local f=fixture();f.track.roadType=1;bad(f,"only_explicit_TRACK_NORMAL_supported")
    f=fixture();f.track.edgeMode="BRIDGE";bad(f,"only_explicit_TRACK_NORMAL_supported")
    f=fixture();f.track.edgeMode="TUNNEL";bad(f,"only_explicit_TRACK_NORMAL_supported")
    f=fixture();f.track.typeIndex=-1;bad(f,"explicit_typeIndex_required")
    f=fixture();f.track.typeIndex=math.huge;bad(f,"explicit_typeIndex_required")
end)
test("ownership is never guessed or silently accepted",function()
    for _,owner in ipairs({0,1,"player","unowned"}) do local f=fixture();f.ownership=owner;bad(f,"ownership_must_remain_unresolved") end
    local f=fixture();f.ownership=nil;bad(f,"ownership_must_remain_unresolved")
    f=fixture();f.track.playerOwned={player=0};bad(f,"track_configuration_required")
end)
test("duplicate and disconnected node references are rejected",function()
    local f=fixture({p(0,0),p(100,0),p(200,0)})
    f.geometry.segments[2].node0Index=1;bad(f,"noncanonical_segment_references_at_2")
    f=fixture();f.geometry.segments[1].node1Index=1;bad(f,"noncanonical_segment_references_at_1")
    f=fixture();f.geometry.nodes[2].index=1;bad(f,"noncanonical_node_at_2")
    f=fixture();f.geometry.nodes[2]=f.geometry.nodes[1];bad(f,"noncanonical_node_at_2")
end)
test("node geometry cannot disagree with endpoint geometry",function()
    local f=fixture();f.geometry.nodes[2].position.x=101;bad(f,"noncanonical_node_at_2")
    f=fixture();f.geometry.nodes[2].sourcePointIndex=99;bad(f,"noncanonical_node_at_2")
end)
test("broken endpoint continuity and backwards tangents fail revalidation",function()
    local f=fixture({p(0,0),p(100,0),p(200,0)})
    f.geometry.segments[2].position0.y=1
    bad(f,"geometry_revalidation:endpoint_or_source_discontinuity_at_2")
    f=fixture();f.geometry.segments[1].tangent1.x=-100
    bad(f,"geometry_revalidation:non_forward_or_stationary_tangent_at_1")
end)
test("C1 mismatch zero chord and missing coordinates fail revalidation",function()
    local f=fixture({p(0,0),p(100,0),p(200,0)})
    f.geometry.segments[2].tangent0.x=99;bad(f,"geometry_revalidation:join_not_exact_C1_at_2")
    f=fixture();f.geometry.segments[1].position1=p(0,0);bad(f,"geometry_revalidation:degenerate_horizontal_chord_at_1")
    f=fixture();f.geometry.segments[1].position0.z=nil;bad(f,"geometry_revalidation:position0_invalid_at_1")
end)
test("cached diagnostics cannot hide caller threshold violations",function()
    local f=fixture({p(0,0),p(100,0,10)},{maxGradient=0.02})
    f.geometry.report.sampledDiagnostics.maxAbsGradient=0;f.geometry.status="candidate";f.geometry.sourceCandidateStatus="candidate"
    local r=good(f);eq(r.geometryStatus,"diagnostic_violation");eq(r.geometryReport.sampledDiagnostics.maxAbsGradient,0.1)
    eq(r.nativeReadiness,"blocked")
end)
test("input immutability and no aliases across records",function()
    local f=fixture({p(0,0),p(100,10),p(200,0)});local before=encode(f);local r=good(f);eq(encode(f),before)
    r.streetProposal.nodesToAdd[1].comp.position.x=999
    r.streetProposal.edgesToAdd[1].comp.tangent0.x=888
    r.streetProposal.edgesToAdd[1].comp.laneConfigs[1].transportModes.TRAIN=false
    eq(r.streetProposal.edgesToAdd[2].comp.laneConfigs[1].transportModes.TRAIN,true)
    eq(r.resourceConfiguration.laneConfigs[1].transportModes.TRAIN,true)
    r.geometryProvenance.anchor.townId=123;r.resourceConfiguration.provenance.source="changed"
    eq(encode(f),before)
end)
test("deterministic IDs data and diagnostics on repeated assembly",function()
    local f=fixture({p(0,0),p(100,10),p(200,0)})
    local a=encode(good(f));for i=1,5 do eq(encode(good(f)),a) end
end)
test("long maximum alignment has bounded entities and one shared ID namespace",function()
    local points={};for i=1,256 do points[i]=p(i*100,math.sin(i/10)*20,i/100) end
    local f=fixture(points,{diagnosticSteps=64});local r=good(f);local s=r.streetProposal
    eq(#s.nodesToAdd,256);eq(#s.edgesToAdd,255);eq(s.edgesToAdd[255].entity,-511)
    local seen={};for _,list in ipairs({s.nodesToAdd,s.edgesToAdd}) do for _,v in ipairs(list) do assert(not seen[v.entity]);seen[v.entity]=true end end
    for i=1,511 do assert(seen[-i]) end
    for i=1,254 do eq(s.edgesToAdd[i].comp.node1,s.edgesToAdd[i+1].comp.node0) end
    f.geometry.segments[256]=f.geometry.segments[255];bad(f,"segments_dense_1_255_required")
end)
test("sparse arrays extra native fields and malicious metatables are rejected",function()
    local f=fixture();f.geometry.nodes[3]=f.geometry.nodes[2];f.geometry.nodes[2]=nil;bad(f,"canonical_node_count_required")
    f=fixture();f.geometry.segments[1].entity=42;bad(f,"noncanonical_segment_references_at_1")
    f=fixture();f.geometry.streetProposal={};bad(f,"geometry_DTO_contract")
    f=fixture();setmetatable(f.geometry,{__index=function() error("must not execute") end});bad(f,"geometry_DTO_contract")
end)
test("all uncertainty and source provenance survive assembly",function()
    local f=fixture();local r=good(f)
    eq(encode(r.geometryProvenance),encode(f.geometry.provenance));eq(encode(r.resourceConfiguration),encode(f.track))
    eq(r.geometryReport.terrainAndCollisions,"not_verified");eq(r.geometryReport.bridgeTunnelDecisions,"not_assessed")
    eq(r.geometryReport.nativeProposalVerification,"not_run");assert(#r.missingPrerequisites>=7)
    eq(r.streetProposal.nodesToRemove,nil);eq(r.streetProposal.edgesToRemove,nil)
    eq(r.streetProposal.constructionsToAdd,nil);eq(r.streetProposal.edgeObjectsToAdd,nil)
end)
test("native APIs file IO and processing are never invoked",function()
    local f=fixture();local oldApi,oldIo,oldOs=api,io,os
    local trap=setmetatable({},{__index=function() error("forbidden native or IO call") end})
    api,io,os=trap,trap,trap
    local ok,r=pcall(assembly.assemble,f);api,io,os=oldApi,oldIo,oldOs
    assert(ok,r);eq(r.status,"descriptor");eq(r.nativeObjectsCreated,false)
end)
print(string.format("PASS %d proposal assembly tests (offline only)",passed))
