local read=ug_require "oz_railway_network_architect::/live_plan_api.lua"
local native=ug_require "oz_railway_network_architect::/station_site_api.lua"
local sites=ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local corridor=ug_require "oz_railway_network_architect::/live_plan_request.lua"
local flow=ug_require "oz_railway_network_architect::/live_plan_data.lua"
local R={}
local function log(s) debugPrint("[RNA:STATION] "..s) end
local function stop(s,status,reason)
    if s.child and not s.child.finished then corridor.invalidate(s.child,reason) end
    s.child,s.towns,s.raw,s.samples,s.proposals,s.objects=nil,nil,nil,nil,nil,nil
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
        s.cursor=1;s.phase="objects"
    elseif s.phase=="objects" then
        local t=s.towns[s.townIndex];local last=math.min(s.cursor+15,#s.raw)
        for i=s.cursor,last do
            local o=native.object(s.raw[i],s.world)
            if o then t.objects[#t.objects+1]=o;s.objects[#s.objects+1]=o end
        end
        s.cursor=last+1
        if s.cursor>#s.raw then s.raw=nil;advanceTown(s) end
    elseif s.phase=="sites" then
        local t=s.towns[s.townIndex];local c=s.proposals[s.townIndex][s.siteIndex]
        if not c then
            t.sites=sites.shortlist(t.sites)
            log("SHORTLIST town="..t.id.." sites="..#t.sites.." buildings="..#t.buildings.." existing_passenger_stations="..#t.stations)
            local reasons={};for reason in pairs(t.rejected) do reasons[#reasons+1]=reason end;table.sort(reasons)
            for _,reason in ipairs(reasons) do log("REJECT town="..t.id.." reason="..reason.." count="..t.rejected[reason]) end
            for _,site in ipairs(t.sites) do
                local e=site.evidence
                log("SITE id="..site.id.." x="..site.x.." y="..site.y.." z="..flow.number(site.z)
                    .." axis="..site.dx..","..site.dy.." approach="..site.approach.x..","..site.approach.y
                    .." urban_distance="..flow.number(e.urbanDistance).." road_endpoint_distance="..flow.number(e.roadEndpointDistance)
                    .." max_sampled_grade="..flow.number(e.maxSampledGrade).." track_endpoint_distance="..flow.number(e.trackEndpointDistance)
                    .." passenger_station_distance="..flow.number(e.existingPassengerStationDistance).." walking_access=unknown")
            end
            if #t.sites==0 then error("station_planning_unresolved_no_suitable_sites town="..t.id,0) end
            s.townIndex=s.townIndex+1;s.siteIndex=1
            if s.townIndex>2 then s.pairs=sites.pairs(s.towns[1].sites,s.towns[2].sites);s.phase="pair" end
            return
        end
        if not s.samples then
            local valid,reason=sites.screen(c,t,s.bounds)
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
        if not pair or s.pairIndex>2 then s.phase="verify";s.verifyIndex=1;return end
        validateSources(s)
        local a,b=pair.source,pair.destination
        log("PAIR index="..s.pairIndex.." source="..a.id.." destination="..b.id.." screen_score="..flow.number(pair.score))
        s.child=corridor.start({id=s.world,tick=s.tick},s.sourceId,s.destinationId,s.requestId,
            {start={townId=s.sourceId,x=a.approach.x,y=a.approach.y,z=a.approach.z},
             destination={townId=s.destinationId,x=b.approach.x,y=b.approach.y,z=b.approach.z},objects=s.objects})
        s.phase="corridor";s.progress="Planning railway between station sites..."
    elseif s.phase=="corridor" then
        corridor.step(s.child)
        if not s.child.finished then return end
        local child=s.child;local pair=s.pairs[s.pairIndex]
        if child.status=="invalidated" or child.status=="performance_limit" or child.status=="resource_limit" or child.status=="timing_unavailable" then
            error({status=child.status,reason="station_corridor_safety_stop:"..child.status..":"..flow.text(child.reason)},0)
        end
        if child.status=="ok" and child.result and child.result.complete then
            for _,c in ipairs(child.result.candidates) do
                if sites.approaches(c,pair) then
                    c.stationSites={source=pair.source,destination=pair.destination}
                    c.stationPairScore=pair.source.siteScore+pair.destination.siteScore
                    c.jointScore=c.score.total+128*c.stationPairScore
                    c.id="station"..s.pairIndex.."-"..c.id
                    s.routes[#s.routes+1]=c
                    s.lastSnapshot=child.result.snapshot
                    break -- One real corridor per evaluated station pair, never fabricated alternatives.
                end
            end
        end
        log("PAIR_RESULT index="..s.pairIndex.." status="..child.status.." retained="..#s.routes)
        s.child=nil;s.pairIndex=s.pairIndex+1;s.phase="pair"
    elseif s.phase=="verify" then
        if #s.routes==0 then error("station_planning_unresolved_no_compatible_corridor",0) end
        validateSources(s)
        local c=s.routes[s.verifyIndex]
        if c then
            if not native.clear(c.stationSites.source,s.world) or not native.clear(c.stationSites.destination,s.world) then error("station_reservation_changed",0) end
            s.verifyIndex=s.verifyIndex+1;return
        end
        table.sort(s.routes,function(a,b) return a.jointScore==b.jointScore and a.id<b.id or a.jointScore<b.jointScore end)
        for i,candidate in ipairs(s.routes) do candidate.rank=i end
        local winner=s.routes[1].stationSites
        s.pair={start={id=s.sourceId,name=winner.source.name,x=winner.source.approach.x,y=winner.source.approach.y,z=winner.source.approach.z},
            destination={id=s.destinationId,name=winner.destination.name,x=winner.destination.approach.x,y=winner.destination.approach.y,z=winner.destination.approach.z}}
        s.result={status="ok",complete=true,candidates=s.routes,profiles={},stats={},snapshot=s.lastSnapshot,
            stationSnapshot={world=s.world,startTick=s.startTick,endTick=s.tick,started=s.started,atomic=false}}
        s.routes=nil;s.pairs=nil
        stop(s,"ok","station_pairs_evaluated;reservations_approximate;walking_access_unknown;smoothing_unverified")
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
        if not flow.finite(ended) or ended<now or ended-now>0.05 then error("station_callback_budget_exceeded",0) end
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
