-- Offline symbolic assembly descriptor only. Never instantiate or submit native objects.
local dto = ug_require "oz_railway_network_architect::/geometry/track_geometry_dto.lua"
local assembly = {}
local function plain(v) return type(v) == "table" and getmetatable(v) == nil end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function integer(v, lo, hi) return finite(v) and v % 1 == 0 and v >= lo and v <= hi end
local function keys(v, allowed)
    if not plain(v) then return false end
    for k in pairs(v) do if not allowed[k] then return false end end
    return true
end
local function dense(v, limit)
    if not plain(v) then return nil end
    local n = 0
    for k in pairs(v) do
        n = n+1
        if n > limit or not integer(k, 1, limit) then return nil end
    end
    for i=1,n do if v[i] == nil then return nil end end
    return n
end
local function xyz(v) return {x=v.x,y=v.y,z=v.z} end
local function same(a,b)
    return keys(a,{x=true,y=true,z=true}) and a.x==b.x and a.y==b.y and a.z==b.z
end
local function reference(v, suffix)
    return type(v)=="string" and #v<=512 and v:match("^[%w_.%-]*::/[^%s]+$") ~= nil
        and not v:find("%c") and not v:find("\\",1,true) and not v:find("//",1,true)
        and not v:find("/../",1,true) and not v:find("/./",1,true) and v:sub(-#suffix)==suffix
end
local function copyLanes(lanes)
    local out={}
    for i,l in ipairs(lanes) do
        local modes={};for k,v in pairs(l.transportModes) do modes[k]=v end
        out[i]={speed=l.speed,width=l.width,height=l.height,forward=l.forward,offset=l.offset,transportModes=modes}
    end
    return out
end
local function failure(reason)
    return {kind="offline_track_proposal_assembly",status="invalid_input",reason=reason,
        nativeObjectsCreated=false,nativeProcessing="not_run",constructionAcceptance="unverified"}
end

function assembly.assemble(input)
    if not keys(input,{geometry=true,track=true,endpoints=true,ownership=true}) then return failure("input_contract") end
    if not keys(input.endpoints,{start=true,finish=true}) or input.endpoints.start~="isolated_new"
        or input.endpoints.finish~="isolated_new" then return failure("explicit_isolated_endpoints_required") end
    -- Omit the optional playerOwned component; this is NOT an assertion of unowned land/track.
    if input.ownership~="unresolved" then return failure("ownership_must_remain_unresolved") end
    local t=input.track
    if not keys(t,{roadTemplate=true,roadStyle=true,roadType=true,edgeMode=true,typeIndex=true,laneConfigs=true,provenance=true}) then
        return failure("track_configuration_required")
    end
    if t.roadType~="TRACK" or t.edgeMode~="NORMAL" then return failure("only_explicit_TRACK_NORMAL_supported") end
    if not integer(t.typeIndex,0,2147483647) then return failure("explicit_typeIndex_required") end
    if not reference(t.roadTemplate,".street_template") or not reference(t.roadStyle,".street") then return failure("invalid_resource_reference") end
    if not keys(t.provenance,{source=true,basis=true}) or type(t.provenance.source)~="string"
        or #t.provenance.source<1 or #t.provenance.source>512
        or (t.provenance.basis~="synthetic" and t.provenance.basis~="installed_source" and t.provenance.basis~="live_snapshot") then
        return failure("resource_provenance_required")
    end
    local laneCount=dense(t.laneConfigs,8)
    if not laneCount or laneCount<1 then return failure("lane_count_1_8_required") end
    local modesAllowed={TRAIN=true,ELECTRIC_TRAIN=true,TRAM_TRACK=true,ELECTRIC_TRAM_TRACK=true}
    for i=1,laneCount do
        local l=t.laneConfigs[i]
        if not keys(l,{speed=true,width=true,height=true,forward=true,offset=true,transportModes=true})
            or type(l.forward)~="boolean" or not keys(l.transportModes,modesAllowed) then return failure("invalid_lane_at_"..i) end
        for _,k in ipairs({"speed","width","height","offset"}) do
            if not finite(l[k]) or math.abs(l[k])>1e6 then return failure("invalid_lane_"..k.."_at_"..i) end
        end
        if l.speed<=0 or l.width<=0 then return failure("nonpositive_lane_speed_or_width_at_"..i) end
        for _,v in pairs(l.transportModes) do if type(v)~="boolean" then return failure("mode_flags_must_be_boolean") end end
        if l.transportModes.TRAIN~=true and l.transportModes.ELECTRIC_TRAIN~=true then return failure("train_mode_required_at_"..i) end
    end
    local g=input.geometry
    if not keys(g,{kind=true,status=true,unit=true,parameter=true,sourceCandidateStatus=true,sourceRemovedDuplicates=true,
        provenance=true,assumptions=true,sourceWarnings=true,templateReferences=true,nodes=true,segments=true,report=true})
        or g.kind~="intermediate_track_geometry" or (g.status~="candidate" and g.status~="diagnostic_violation")
        or not plain(g.report) or g.report.nativeProposalVerification~="not_run" or g.report.constructionStatus~="unverified" then
        return failure("geometry_DTO_contract")
    end
    local count=dense(g.segments,255)
    if not count or count<1 then return failure("segments_dense_1_255_required") end
    if dense(g.nodes,256)~=count+1 then return failure("canonical_node_count_required") end
    if g.templateReferences~=nil and (not keys(g.templateReferences,{roadTemplate=true,roadStyle=true})
        or g.templateReferences.roadTemplate~=t.roadTemplate or g.templateReferences.roadStyle~=t.roadStyle) then
        return failure("geometry_resource_mismatch")
    end
    -- Revalidate geometry through the authoritative Phase 6B adapter, without fitting
    -- new curves or trusting cached diagnostics. Never forward arbitrary DTO fields.
    local candidate={kind="offline_hermite_candidate",status=g.sourceCandidateStatus,unit=g.unit,parameter=g.parameter,
        constructionStatus="unverified",engineValidation="not_run",removedDuplicates=g.sourceRemovedDuplicates,
        assumptions=g.assumptions,warnings=g.sourceWarnings,segments={},diagnostics={}}
    for i=1,count do
        local s=g.segments[i]
        if not keys(s,{index=true,node0Index=true,node1Index=true,position0=true,position1=true,tangent0=true,tangent1=true,
            sourceStartIndex=true,sourceEndIndex=true,diagnostics=true})
            or s.index~=i or s.node0Index~=i or s.node1Index~=i+1 then return failure("noncanonical_segment_references_at_"..i) end
        candidate.segments[i]={position0=s.position0,position1=s.position1,tangent0=s.tangent0,tangent1=s.tangent1,
            sourceStartIndex=s.sourceStartIndex,sourceEndIndex=s.sourceEndIndex,diagnostics={}}
    end
    local checked=dto.convert({candidate=candidate,provenance=g.provenance,template=g.templateReferences})
    if checked.status~="candidate" and checked.status~="diagnostic_violation" then return failure("geometry_revalidation:"..checked.reason) end
    if g.status=="diagnostic_violation" then checked.status="diagnostic_violation" end
    for i,n in ipairs(checked.nodes) do
        local source=g.nodes[i]
        if not keys(source,{index=true,position=true,sourcePointIndex=true}) or source.index~=i
            or source.sourcePointIndex~=n.sourcePointIndex or not same(source.position,n.position) then
            return failure("noncanonical_node_at_"..i)
        end
    end
    local nodes,edges,sources={},{},{}
    -- One namespace for all new entities. Never reuse positive live IDs or DTO indices.
    for i,n in ipairs(checked.nodes) do nodes[i]={entity=-i,comp={position=xyz(n.position)}} end
    for i,s in ipairs(checked.segments) do
        edges[i]={entity=-(#nodes+i),type=1, -- Explicit native discriminator: type.d.tl:2524-2525.
            comp={node0=-s.node0Index,node1=-s.node1Index,position0=xyz(s.position0),position1=xyz(s.position1),
                tangent0=xyz(s.tangent0),tangent1=xyz(s.tangent1),type=t.edgeMode,typeIndex=t.typeIndex,
                roadType=t.roadType,roadTemplate=t.roadTemplate,roadStyle=t.roadStyle,laneConfigs=copyLanes(t.laneConfigs)}}
        sources[i]={entity=edges[i].entity,sourceStartIndex=s.sourceStartIndex,sourceEndIndex=s.sourceEndIndex}
    end
    return {kind="offline_track_proposal_assembly",status="descriptor",representation="symbolic_fields_not_native_objects",
        nativeObjectsCreated=false,nativeProcessing="not_run",constructionAcceptance="unverified",nativeReadiness="blocked",
        geometryStatus=checked.status,geometryProvenance=checked.provenance,geometryReport=checked.report,
        geometryAssumptions=checked.assumptions,geometrySourceWarnings=checked.sourceWarnings,
        sourceCandidateStatus=checked.sourceCandidateStatus,sourceRemovedDuplicates=checked.sourceRemovedDuplicates,
        endpoints={start="isolated_new",finish="isolated_new"},ownership="unresolved",segmentSources=sources,
        resourceConfiguration={roadTemplate=t.roadTemplate,roadStyle=t.roadStyle,roadType=t.roadType,edgeMode=t.edgeMode,
            typeIndex=t.typeIndex,laneConfigs=copyLanes(t.laneConfigs),provenance={source=t.provenance.source,basis=t.provenance.basis}},
        streetProposal={nodesToAdd=nodes,edgesToAdd=edges},
        missingPrerequisites={"native_objects_Vec3f_and_symbolic_enum_resolution",
            "live_template_lane_style_identity_and_availability", "NORMAL_typeIndex_semantics_and_constructor_defaults",
            "ownership_and_processing_context", "native_interpolation_terrain_collisions_and_support",
            "ProposalViewer_activation_non_mutation_and_cleanup", "native_processing_and_construction_acceptance"}}
end
return assembly
