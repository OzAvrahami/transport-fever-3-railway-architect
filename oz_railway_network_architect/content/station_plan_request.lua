local read=ug_require "oz_railway_network_architect::/live_plan_api.lua"
local native=ug_require "oz_railway_network_architect::/station_site_api.lua"
local sites=ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local occupancy=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local corridor=ug_require "oz_railway_network_architect::/live_plan_request.lua"
local flow=ug_require "oz_railway_network_architect::/live_plan_data.lua"
local smooth=ug_require "oz_railway_network_architect::/geometry/station_smooth_preview.lua"
local R={}
local function log(s) debugPrint("[RNA:STATION] "..s) end
local function audit(t,c)
    local r=c.occupancy
    if not t.audit then
        t.audit={candidates=0,bodyConflicts=0,approachConflicts=0,examples=0,seen={},rejected={},body={},approach={},neighborhood={},
            groupAffected=0,unknownGroupBlocked=0}
        for _,kind in ipairs(occupancy.kinds) do
            t.audit.rejected[kind]=0
            for _,region in ipairs({"body","approach","neighborhood"}) do t.audit[region][kind]=0 end
        end
    end
    local a=t.audit;a.candidates=a.candidates+1
    if r.modelGroupAffected then a.groupAffected=a.groupAffected+1 end
    if r.unknownGroupBlocked then a.unknownGroupBlocked=a.unknownGroupBlocked+1 end
    a.bodyConflicts=a.bodyConflicts+r.bodyConflicts;a.approachConflicts=a.approachConflicts+r.approachConflicts
    for _,kind in ipairs(occupancy.kinds) do
        if r.blockedKinds[kind] then a.rejected[kind]=a.rejected[kind]+1 end
        for _,region in ipairs({"body","approach","neighborhood"}) do a[region][kind]=a[region][kind]+r[region][kind] end
    end
    for _,o in ipairs(r.examples) do
        if a.examples<8 and not a.seen[o.id] then
            a.seen[o.id]=true;a.examples=a.examples+1
            log("OBSTRUCTION_SAMPLE town="..t.id.." candidate="..c.id.." entity="..tostring(o.id).." region="..o.region
                .." class="..o.kind.." source="..o.source.." issue="..flow.text(o.issue))
        end
    end
end
local function finishPair(s)
    log("PAIR_RESULT index="..s.pairIndex.." status="..s.child.status.." retained="..#s.routes)
    s.child=nil;s.pairIndex=s.pairIndex+1;s.phase="pair"
end
local function stop(s,status,reason)
    if s.child and not s.child.finished then corridor.invalidate(s.child,reason) end
    s.child,s.towns,s.raw,s.samples,s.proposals,s.objects=nil,nil,nil,nil,nil,nil
    if s.modelContext then
        local c=s.modelContext
        log("MODEL_BUDGET visits="..c.visits.." lookups="..c.lookups.." cache_hits="..c.cacheHits.." lookup_errors="..c.lookupErrors
            .." max_group=4096 max_visits=65536 max_lookups=1024 per_callback=64 spatial_precision=aggregate_AABB_unresolved")
    end
    s.revalidation,s.objectJob,s.modelContext,s.smoothing=nil,nil,nil,nil
    s.finished,s.status,s.reason=true,status,reason
    s.routes,s.pairs=nil,nil
    if status~="ok" then s.result=nil end
end
function R.start(world,a,b,id)
    return {stationAware=true,world=world.id,tick=world.tick,startTick=world.tick,sourceId=a,destinationId=b,
        requestId=id,phase="begin",status="planning",routes={},pairIndex=1,progress="Finding station sites..."}
end
local function advanceTown(s)
    s.townIndex=s.townIndex+1;s.cursor=1
    if s.townIndex>2 then
        s.phase="sites";s.townIndex=1;s.siteIndex=1
        s.proposals={sites.generate(s.towns[1],s.towns[2]),sites.generate(s.towns[2],s.towns[1])}
    else s.phase="buildings" end
end
local function validateSources(s)
    local b=read.bounds()
    for _,key in ipairs({"minX","minY","maxX","maxY"}) do
        if b[key]~=s.bounds[key] then error("station_bounds_invalidated",0) end
    end
    for _,t in ipairs(s.towns) do
        if not flow.sameTown(t,read.town(t.id)) then error("station_town_invalidated",0) end
    end
end
local function work(s)
    if s.phase=="begin" then
        s.bounds=read.bounds();s.towns={};s.objects={};s.townIndex=1;s.cursor=1
        s.modelContext=native.newModelContext(s.world)
        local a,b=native.buildingIds(s.sourceId,s.destinationId)
        for i,id in ipairs({s.sourceId,s.destinationId}) do
            local t=read.town(id)
            if not flow.validTown(t,s.bounds) or t.error then error("selected_town_unavailable",0) end
            t.ids=i==1 and a or b;t.buildings={};t.objects={};t.stations={};t.sites={};t.rejected={}
            if #t.ids==0 then error("occupied_urban_area_unknown_no_buildings",0) end
            s.towns[i]=t
        end
        s.phase="buildings";log("START source="..s.sourceId.." destination="..s.destinationId.." footprint=approximate walking_access=unknown")
    elseif s.phase=="buildings" then
        local t=s.towns[s.townIndex];local last=math.min(s.cursor+15,#t.ids)
        for i=s.cursor,last do
            local v=native.building(t.ids[i],t.id);t.buildings[#t.buildings+1]=v
            if not t.urban then t.urban={minX=v.box.minX,minY=v.box.minY,maxX=v.box.maxX,maxY=v.box.maxY}
            else for _,k in ipairs({"minX","minY"}) do t.urban[k]=math.min(t.urban[k],v.box[k]) end
                for _,k in ipairs({"maxX","maxY"}) do t.urban[k]=math.max(t.urban[k],v.box[k]) end end
        end
        s.cursor=last+1
        if s.cursor>#t.ids then t.ids=native.stationIds(t.id);s.cursor=1;s.phase="stations" end
    elseif s.phase=="stations" then
        local t=s.towns[s.townIndex];local last=math.min(s.cursor+3,#t.ids)
        for i=s.cursor,last do local v=native.station(t.ids[i]);if v then t.stations[#t.stations+1]=v end end
        s.cursor=last+1
        if s.cursor>#t.ids then s.phase="query" end
    elseif s.phase=="query" then
        local t=s.towns[s.townIndex];local b=t.urban
        if b.maxX-b.minX>4096 or b.maxY-b.minY>4096 then error("urban_region_limit",0) end
        s.raw=native.query({minX=b.minX-768,minY=b.minY-768,maxX=b.maxX+768,maxY=b.maxY+768},2048)
        s.objectJob=native.startObjects(s.raw,s.world);s.raw=nil;s.phase="objects"
    elseif s.phase=="objects" then
        local t=s.towns[s.townIndex]
        native.stepObjects(s.objectJob,s.modelContext)
        if s.objectJob.finished then
            t.objects=s.objectJob.objects
            local g={entities=0,multi=0,inspected=0,all_tree=0,mixed_non_tree=0,unknown=0,limits=0,errors=0,errorEvents=0,budgets=0}
            for _,o in ipairs(t.objects) do
                s.objects[#s.objects+1]=o
                local m=o.modelGroup
                if m then
                    g.entities=g.entities+1;g.multi=g.multi+(m.count>1 and 1 or 0);g.inspected=g.inspected+m.inspected
                    g[m.outcome]=g[m.outcome]+1;g.limits=g.limits+(m.instanceLimit and 1 or 0)
                    g.errors=g.errors+(m.errors>0 and 1 or 0);g.budgets=g.budgets+(m.budgetLimit and 1 or 0)
                    g.errorEvents=g.errorEvents+m.errors
                end
            end
            log("MODEL_GROUPS town="..t.id.." unique_entities="..g.entities.." multi_instance_groups="..g.multi
                .." instances_inspected="..g.inspected.." all_tree="..g.all_tree.." mixed_non_tree="..g.mixed_non_tree
                .." unknown="..g.unknown.." instance_limit_failures="..g.limits.." budget_failures="..g.budgets
                .." groups_with_errors="..g.errors.." classification_errors="..g.errorEvents.." spatial_precision=aggregate_AABB_unresolved")
            s.objectJob=nil;advanceTown(s)
        end
    elseif s.phase=="sites" then
        local t=s.towns[s.townIndex];local c=s.proposals[s.townIndex][s.siteIndex]
        if not c then
            t.sites=sites.shortlist(t.sites)
            local a=t.audit
            if a then
                log("MODEL_CANDIDATES town="..t.id.." affected="..a.groupAffected.." unknown_group_blocked="..a.unknownGroupBlocked
                    .." total_screened="..a.candidates.." counts=candidates_not_entities")
                log("OCCUPANCY town="..t.id.." generated="..#s.proposals[s.townIndex].." screened="..a.candidates
                    .." body_conflicts="..a.bodyConflicts.." approach_conflicts="..a.approachConflicts.." counts=candidate_entity_incidences")
                for _,kind in ipairs(occupancy.kinds) do log("OCCUPANCY_CLASS town="..t.id.." class="..kind
                    .." body="..a.body[kind].." approach="..a.approach[kind].." neighborhood="..a.neighborhood[kind]
                    .." rejected_candidates="..a.rejected[kind]) end
            end
            log("SHORTLIST town="..t.id.." sites="..#t.sites.." buildings="..#t.buildings.." existing_passenger_stations="..#t.stations)
            local reasons={};for reason in pairs(t.rejected) do reasons[#reasons+1]=reason end;table.sort(reasons)
            for _,reason in ipairs(reasons) do log("REJECT town="..t.id.." reason="..reason.." count="..t.rejected[reason]) end
            for _,site in ipairs(t.sites) do
                local e=site.evidence
                log("SITE id="..site.id.." x="..site.x.." y="..site.y.." z="..flow.number(site.z)
                    .." axis="..site.dx..","..site.dy.." approach="..site.approach.x..","..site.approach.y
                    .." urban_distance="..flow.number(e.urbanDistance).." road_endpoint_distance="..flow.number(e.roadEndpointDistance)
                    .." max_sampled_grade="..flow.number(e.maxSampledGrade).." track_endpoint_distance="..flow.number(e.trackEndpointDistance)
                    .." passenger_station_distance="..flow.number(e.existingPassengerStationDistance).." walking_access=unknown"
                    .." vegetation_clearance="..e.vegetationClearance.." clearance_status="..e.clearanceStatus
                    .." straight_exit_blocked="..tostring(e.approachExitBlocked))
            end
            if #t.sites==0 then error("station_planning_unresolved_no_suitable_sites town="..t.id,0) end
            s.townIndex=s.townIndex+1;s.siteIndex=1
            if s.townIndex>2 then s.pairs=sites.pairs(s.towns[1].sites,s.towns[2].sites);s.phase="pair" end
            return
        end
        if not s.samples then
            local valid,reason=sites.screen(c,t,s.bounds)
            audit(t,c)
            if not valid then t.rejected[reason]=(t.rejected[reason] or 0)+1;s.siteIndex=s.siteIndex+1;return end
            s.samples={}
        end
        for i=#s.samples+1,math.min(#s.samples+16,51) do
            local x,y=sites.samplePosition(c,i);s.samples[i]=read.sample(s.bounds,x,y)
            s.siteSampleReads=(s.siteSampleReads or 0)+1
            if #s.samples[i].errors>0 and (s.errorExamples or 0)<3 then
                s.errorExamples=(s.errorExamples or 0)+1;log("SITE_READ_ERROR detail="..flow.text(s.samples[i].errors[1]))
            end
        end
        if #s.samples==51 then
            local v,reason=sites.evaluate(c,s.samples)
            if v then t.sites[#t.sites+1]=v else t.rejected[reason]=(t.rejected[reason] or 0)+1 end
            s.samples=nil;s.siteIndex=s.siteIndex+1
        end
    elseif s.phase=="pair" then
        local pair=s.pairs[s.pairIndex]
        if not pair or s.pairIndex>2 then s.phase="smooth";s.smoothIndex=1;return end
        validateSources(s)
        local a,b=pair.source,pair.destination
        log("PAIR index="..s.pairIndex.." source="..a.id.." destination="..b.id.." screen_score="..flow.number(pair.score)
            .." blocked_straight_exits="..pair.blockedExits)
        s.child=corridor.start({id=s.world,tick=s.tick},s.sourceId,s.destinationId,s.requestId,
            {start={townId=s.sourceId,x=a.approach.x,y=a.approach.y,z=a.approach.z},
             destination={townId=s.destinationId,x=b.approach.x,y=b.approach.y,z=b.approach.z},objects=s.objects,
             reservations={sites.bounds(a,a.length/2,a.width/2),sites.bounds(b,b.length/2,b.width/2)},
             directions={start={dx=a.dx,dy=a.dy},destination={dx=b.dx,dy=b.dy}}})
        s.phase="corridor";s.progress="Planning railway between station sites..."
    elseif s.phase=="corridor" then
        corridor.step(s.child)
        if not s.child.finished then return end
        local child=s.child;local pair=s.pairs[s.pairIndex]
        if child.status=="invalidated" or child.status=="performance_limit" or child.status=="resource_limit" or child.status=="timing_unavailable" then
            error({status=child.status,reason="station_corridor_safety_stop:"..child.status..":"..flow.text(child.reason)},0)
        end
        if child.status=="ok" and child.result and child.result.complete then
            s.phase="corridor_check";s.candidateIndex=1;s.waypointIndex=2;s.routeVegetation=false
        else finishPair(s) end
    elseif s.phase=="corridor_check" then
        local c=s.child.result.candidates[s.candidateIndex];local pair=s.pairs[s.pairIndex]
        if not c then finishPair(s);return end
        local function reject(reason)
            log("CORRIDOR_CONFLICT candidate="..c.id.." reason="..reason)
            s.candidateIndex=s.candidateIndex+1;s.waypointIndex=2;s.routeVegetation=false
        end
        if s.waypointIndex==2 and not sites.approaches(c,pair) then reject("station_approach_or_body");return end
        for i=s.waypointIndex,math.min(s.waypointIndex+15,#c.waypoints) do
            local obstacle,vegetation=occupancy.segment(c.waypoints[i-1],c.waypoints[i],s.objects)
            if obstacle then reject("hard_"..occupancy.kind(obstacle).." entity="..obstacle.id);return end
            s.routeVegetation=s.routeVegetation or vegetation;s.waypointIndex=i+1
        end
        if s.waypointIndex>#c.waypoints then
            c.stationSites={source=pair.source,destination=pair.destination}
            c.vegetationClearanceUnverified=s.routeVegetation
            c.stationPairScore=pair.source.siteScore+pair.destination.siteScore
            c.jointScore=c.score.total+128*c.stationPairScore
            c.id="station"..s.pairIndex.."-"..c.id
            s.routes[#s.routes+1]=c;s.lastSnapshot=s.child.result.snapshot
            log("CORRIDOR_OCCUPANCY candidate="..c.id.." hard_conflicts=0 vegetation_clearance_unverified="..tostring(s.routeVegetation)
                .." coverage=collected_local_neighborhoods construction=unverified")
            finishPair(s) -- One real corridor per evaluated station pair, never fabricated alternatives.
        end
    elseif s.phase=="smooth" then
        local c=s.routes[s.smoothIndex]
        if not c then s.phase="verify";s.verifyIndex=1;return end
        s.smoothStarted=s.smoothStarted or read.seconds()
        if not s.smoothing then
            s.smoothing=smooth.start(c);s.progress="Refining railway preview..."
            log("SMOOTH_START candidate="..c.id.." min_radius=40 max_grade=0.08 terrain_delta=2 assumptions=provisional")
        end
        local j=s.smoothing;local reads=0;local units=0
        local ok,err=pcall(function()
            if read.seconds()-s.smoothStarted>10 or s.smoothWorkExceeded then smooth.reject(j,"smoothing_work_budget_grid_retained") end
            while not j.finished and units<8 and reads<16 do
                local probe=smooth.probe(j)
                if probe then
                    smooth.accept(j,read.sampleCurve(s.bounds,probe.x,probe.y));reads=reads+1
                else
                    local phase=j.phase;smooth.step(j,c,s.objects,s.bounds);units=units+1
                    if phase=="fit" or phase=="copy" then break end
                end
            end
        end)
        if not ok then smooth.reject(j,"smoothing_error:"..flow.text(err)) end
        if j.finished then
            c.smoothPreview=smooth.result(j)
            log("SMOOTH_COMPLETE candidate="..c.id.." status="..j.status.." reason="..flow.text(j.reason)
                .." segments="..j.segments.." probes="..j.probeCount.." max_curvature_bound="..flow.number(j.maxCurvature)
                .." max_grade_bound="..flow.number(j.maxGradient).." terrain_delta="..flow.number(j.maxTerrainDelta)
                .." obstacle_coverage=known_local_AABBs terrain_validation=sampled construction=unverified")
            s.smoothing=nil;s.smoothIndex=s.smoothIndex+1
        end
    elseif s.phase=="verify" then
        if #s.routes==0 then error("station_planning_unresolved_no_compatible_corridor",0) end
        if not s.finalModelCacheReset then
            s.modelContext.cache={};s.finalModelCacheReset=true -- Refresh metadata for final checks; retain spent budgets.
        end
        validateSources(s)
        local c=s.routes[s.verifyIndex]
        if c then
            local site=c.stationSites[s.verifyRole==2 and "destination" or "source"]
            if not s.revalidation then s.revalidation=native.startClear(site,s.world);return end
            native.stepClear(s.revalidation,s.modelContext)
            if not s.revalidation.finished then return end
            local clear,reason,report=s.revalidation.clear,s.revalidation.reason,s.revalidation.report
            s.revalidation=nil
            log("REVALIDATION town="..site.townId.." clear="..tostring(clear).." body_conflicts="..report.bodyConflicts
                .." approach_conflicts="..report.approachConflicts.." vegetation_clearance="..report.vegetationClearance.." reason="..flow.text(reason))
            if not clear then
                for _,o in ipairs(report.examples) do log("REVALIDATION_SAMPLE entity="..tostring(o.id).." class="..o.kind
                    .." region="..o.region.." source="..o.source.." issue="..flow.text(o.issue)) end
                error("station_reservation_changed:"..reason,0)
            end
            site.evidence.finalVegetationClearance=report.vegetationClearance
            if report.vegetationClearance>0 then site.evidence.clearanceStatus="provisional_vegetation_clearance" end
            if s.verifyRole==2 then s.verifyIndex=s.verifyIndex+1;s.verifyRole=1 else s.verifyRole=2 end
            return
        end
        table.sort(s.routes,function(a,b) return a.jointScore==b.jointScore and a.id<b.id or a.jointScore<b.jointScore end)
        for i,candidate in ipairs(s.routes) do candidate.rank=i end
        local winner=s.routes[1].stationSites
        s.pair={start={id=s.sourceId,name=winner.source.name,x=winner.source.approach.x,y=winner.source.approach.y,z=winner.source.approach.z},
            destination={id=s.destinationId,name=winner.destination.name,x=winner.destination.approach.x,y=winner.destination.approach.y,z=winner.destination.approach.z}}
        s.result={status="ok",complete=true,candidates=s.routes,profiles={},stats={},snapshot=s.lastSnapshot,
            stationSnapshot={world=s.world,startTick=s.startTick,endTick=s.tick,started=s.started,atomic=false}}
        s.routes=nil;s.pairs=nil
        stop(s,"ok","station_pairs_evaluated;reservations_approximate;walking_access_unknown;smooth_preview_optional;construction_unverified")
    end
end
function R.step(s)
    if s.finished then return end
    local ok,reason=pcall(function()
        local now=read.seconds();if not flow.finite(now) then error("clock_unavailable",0) end
        s.started=s.started or now
        if now<s.started or now-s.started>60 then error("station_snapshot_invalidated_expired",0) end
        local world=read.world();if flow.worldChanged(s,world) then error("station_world_invalidated",0) end;s.tick=world.tick
        work(s)
        if flow.worldChanged(s,read.world()) then error("station_world_invalidated",0) end
        local ended=read.seconds()
        if flow.finite(ended) and ended>=now then
            s.maxWorkSeconds=math.max(s.maxWorkSeconds or 0,ended-now)
            s.zeroClockDelta=s.zeroClockDelta or ended==now;s.elapsedSeconds=ended-s.started
        end
        if flow.finite(ended) and ended>=now and ended-now>0.05 and s.phase=="smooth" then
            -- Stop optional smoothing on observed overrun; preserve already accepted
            -- grid corridors, then perform the normal final reservation checks.
            s.smoothWorkExceeded=true
            if s.smoothing then smooth.reject(s.smoothing,"smoothing_work_budget_grid_retained") end
            local c=s.routes[s.smoothIndex-1]
            if not s.smoothing and c and c.smoothPreview then
                c.smoothPreview={status="fallback",reason="smoothing_work_budget_grid_retained",constructionStatus="unverified"}
                log("SMOOTH_FALLBACK candidate="..c.id.." reason=observed_50ms_work_guard")
            end
        elseif not flow.finite(ended) or ended<now or ended-now>0.05 then error("station_callback_budget_exceeded",0) end
    end)
    if not ok then
        local message=flow.text(type(reason)=="table" and reason.reason or reason)
        local status=type(reason)=="table" and reason.status or message:find("invalidated",1,true) and "invalidated"
            or message:find("budget_exceeded",1,true) and "performance_limit" or "unsupported"
        stop(s,status,message)
    end
    if s.finished then
        log("COMPLETE status="..s.status.." reason="..flow.text(s.reason))
        log("PERFORMANCE site_reads="..tostring(s.siteSampleReads or 0).." max_work_seconds="..flow.number(s.maxWorkSeconds)
            .." elapsed_seconds="..flow.number(s.elapsedSeconds).." zero_delta_observed="..tostring(s.zeroClockDelta==true)
            .." timing_resolution=unknown preemptive=false state_copy_excluded=true")
    end
end
function R.invalidate(s,reason) stop(s,"invalidated",reason);log("INVALIDATED reason="..flow.text(reason)) end
return R
