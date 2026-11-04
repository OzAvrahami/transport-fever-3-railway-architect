-- Session-owned mathematical inspection; no native proposals, resource defaults or API calls.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local curve = ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local dto = ug_require "oz_railway_network_architect::/geometry/track_geometry_dto.lua"
local inspection = {}
local function array(t, limit)
    if type(t) ~= "table" or getmetatable(t) ~= nil then return nil end
    local n=0
    for k in pairs(t) do n=n+1; if n>limit or not flow.id(k) or k<1 or k>limit then return nil end end
    for i=1,n do if t[i]==nil then return nil end end
    return n
end
function inspection.running(job) return job ~= nil and not job.finished end
function inspection.matches(job, state)
    local r=state.request
    return job and job.world==state.world and job.epoch==state.epoch and job.corridorRequestId==state.requestId
        and r and r.finished and r.status=="ok" and r.requestId==state.requestId and r.world==state.world
end
function inspection.stop(job, status, reason)
    if not job then return end
    job.finished,job.status,job.reason,job.phase=true,status,reason,"done"
    job.points,job.curves=nil,nil
    if status~="complete" then job.metrics=nil end
end
function inspection.start(state, token)
    if type(token)~="table" or getmetatable(token)~=nil then return nil,"invalid_inspection_token" end
    for k in pairs(token) do
        if k~="requestId" and k~="corridorRequestId" and k~="candidateId" then return nil,"invalid_inspection_token" end
    end
    if not flow.id(token.requestId) or token.requestId~=(state.inspectionRequestId or 0)+1 then return nil,"duplicate_or_stale_inspection" end
    if token.corridorRequestId~=state.requestId then return nil,"stale_corridor_request" end
    local r=state.request
    if not r or r.world~=state.world or r.requestId~=state.requestId
        or not r.finished or r.status~="ok" or not preview.valid(r.preview,state)
        or not r.result or r.result.status~="ok" or r.result.complete~=true
        or not r.result.snapshot or r.result.snapshot.world~=state.world then return nil,"completed_corridor_required" end
    if type(token.candidateId)~="string" or #token.candidateId>100 then return nil,"invalid_candidate_id" end
    local selected=preview.find(r.preview,token.candidateId)
    if not selected or not array(r.result.candidates,3) then return nil,"candidate_not_available" end
    local c
    for _,candidate in ipairs(r.result.candidates) do
        if type(candidate)~="table" then return nil,"malformed_candidate" end
        if candidate.id==token.candidateId then if c then return nil,"duplicate_candidate_id" end;c=candidate end
    end
    if not c or c.searchStatus~="complete" or c.constructionStatus~="unverified"
        or c.feasibility~="sampled_constraints_satisfied" or c.sourceId~=r.sourceId or c.destinationId~=r.destinationId then
        return nil,"candidate_not_complete"
    end
    local job={world=state.world,epoch=state.epoch,corridorRequestId=state.requestId,id=token.requestId,
        candidateId=token.candidateId,status="running",phase="fit",finished=false,points={},maxWorkSeconds=0,
        source={id=r.preview.source.id,name=r.preview.source.name},
        destination={id=r.preview.destination.id,name=r.preview.destination.name},
        snapshotTick=r.result.snapshot.planEndTick,inspectionTick=state.tick,
        sourceSnap=selected.sourceSnap,destinationSnap=selected.destinationSnap,spacing=selected.spacing}
    local n=array(c.waypoints,256)
    if not n then inspection.stop(job,"unsupported","waypoints_must_be_dense_and_at_most_256");return job end
    if n<2 or n~=selected.waypointCount then inspection.stop(job,"unsupported","waypoint_count_mismatch");return job end
    for i,p in ipairs(c.waypoints) do
        if type(p)~="table" or getmetatable(p)~=nil or type(p.water)~="boolean" then
            inspection.stop(job,"unsupported","invalid_waypoint_at_"..i);return job
        end
        for _,axis in ipairs({"x","y","z"}) do
            if not flow.finite(p[axis]) or math.abs(p[axis])>1e7 then
                inspection.stop(job,"unsupported","invalid_"..axis.."_at_"..i);return job
            end
        end
        if p.water then job.touchesWater=true end
        if i>1 then
            local previous=job.points[i-1]
            local dx,dy=math.abs(p.x-previous.x),math.abs(p.y-previous.y)
            local tolerance=job.spacing*1e-9
            if (dx>tolerance and math.abs(dx-job.spacing)>tolerance)
                or (dy>tolerance and math.abs(dy-job.spacing)>tolerance) or dx+dy<=tolerance then
                inspection.stop(job,"unsupported","corridor_grid_discontinuity_at_"..i);return job
            end
        end
        job.points[i]={x=p.x,y=p.y,z=p.z} -- Preserve corridor and water evidence; explicit projection only.
    end
    for _,endpoint in ipairs({{job.points[1],selected.start},{job.points[n],selected.destination}}) do
        for _,axis in ipairs({"x","y","z"}) do
            if endpoint[1][axis]~=endpoint[2][axis] then inspection.stop(job,"unsupported","endpoint_summary_mismatch");return job end
        end
    end
    job.waypointCount=n
    return job
end
function inspection.step(job,state)
    if not inspection.running(job) then return end
    if not inspection.matches(job,state) then inspection.stop(job,"invalidated","session_or_corridor_changed");return end
    if job.phase=="fit" then
        job.curves=curve.fit({unit="m",points=job.points,options={diagnosticSteps=8}})
        job.points=nil
        if job.curves.status~="candidate" and job.curves.status~="diagnostic_violation" then
            inspection.stop(job,"unsupported","fit:"..job.curves.reason);return
        end
        job.phase="validate" -- A later verified guiUpdate performs DTO validation.
    else
        local result=dto.convert({candidate=job.curves,provenance={source="completed_corridor_snapshot",coordinateFrame="world",
            world=job.world,epoch=job.epoch,requestId=job.corridorRequestId,candidateId=job.candidateId,
            sourceId=job.source.id,destinationId=job.destination.id,sourceSnap=job.sourceSnap,destinationSnap=job.destinationSnap,
            planEndTick=job.snapshotTick,inspectionTick=job.inspectionTick,spacing=job.spacing,
            touchesWater=job.touchesWater==true,obstacles="unverified",anchors="approximate_not_stations"}})
        if result.status~="candidate" and result.status~="diagnostic_violation" then
            inspection.stop(job,"unsupported","dto:"..result.reason);return
        end
        local d=result.report.sampledDiagnostics
        local jumps=0;for _,j in ipairs(result.report.joins) do if not j.C2 then jumps=jumps+1 end end
        job.metrics={segments=#result.segments,continuity="exact_C0_C1",nonC2Joins=jumps,
            maxGradient=d.maxAbsGradient,maxCurvature=d.maxHorizontalCurvature,length=d.approximateLength}
        inspection.stop(job,"complete","mathematical_conversion_only")
    end
end
function inspection.summary(job,state)
    if not inspection.matches(job,state) then return nil end
    local lines={
        "Geometry inspection #"..job.id.." | candidate "..job.candidateId.." | "..job.status.." ("..job.phase..")",
        "Source: "..job.source.name.." [#"..job.source.id.."] | destination: "..job.destination.name.." [#"..job.destination.id.."]",
        "Result: "..flow.text(job.reason or "Bounded mathematical processing in progress."),
    }
    if job.metrics then
        local m=job.metrics
        lines[#lines+1]=string.format("%d curve segments | exact endpoint C0 / tangent C1 | %d non-C2 joins",m.segments,m.nonC2Joins)
        lines[#lines+1]=string.format("Sampled max gradient %.3f%% | max horizontal curvature %.6f /m | fitted length %.1f m",m.maxGradient*100,m.maxCurvature,m.length)
    end
    lines[#lines+1]="Original corridor unchanged. Eight diagnostic intervals/segment; extrema and between-sample terrain are unverified."
    lines[#lines+1]="Missing: track template/lanes/style, ownership, bridge/tunnel decisions, clearance/collisions and native validation."
    lines[#lines+1]="Native preview: BLOCKED (activation, non-mutation and cleanup unverified). Construction status: unverified."
    lines[#lines+1]="Historical corridor snapshot; no fresh terrain reads. Town anchors are not stations. No engineering thresholds applied."
    lines[#lines+1]=string.format("Max measured work %.6f s; budget 0.050000 s. Clock resolution unverified; zero is not zero cost.",job.maxWorkSeconds)
    return {world=job.world,epoch=job.epoch,corridorRequestId=job.corridorRequestId,id=job.id,candidateId=job.candidateId,
        status=job.status,running=not job.finished,nativePreview="blocked",constructionStatus="unverified",lines=lines}
end
function inspection.valid(value,state)
    if type(value)~="table" or value.world~=state.world or value.epoch~=state.epoch
        or value.corridorRequestId~=state.requestId or value.id~=state.inspectionRequestId or not flow.id(value.id)
        or type(value.candidateId)~="string" or #value.candidateId>100 or type(value.running)~="boolean"
        or value.nativePreview~="blocked" or value.constructionStatus~="unverified" then return false end
    local statuses={running=true,complete=true,unsupported=true,error=true,invalidated=true,performance_limit=true,timing_unavailable=true}
    if not statuses[value.status] or value.running~=(value.status=="running") then return false end
    local n=array(value.lines,10);if not n or n<1 then return false end
    for _,line in ipairs(value.lines) do if type(line)~="string" or #line>512 then return false end end
    return true
end
return inspection
