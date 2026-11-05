-- Native reads only. Boxes are conservative world AABBs, never exact native footprints.
local flow=ug_require "oz_railway_network_architect::/live_plan_data.lua"
local sites=ug_require "oz_railway_network_architect::/planning/station_sites.lua"
local occupancy=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local models=ug_require "oz_railway_network_architect::/station_model_classifier.lua"
local A={newModelContext=models.context}
local function call(path,fn)
    local ok,value=pcall(fn);if not ok then error(path..": "..tostring(value),0) end;return value
end
local function comp(id,name)
    return call("api.engine.getComponent("..name..")",function() return api.engine.getComponent(id,api.type.ComponentType[name]) end)
end
local function box(v)
    if not v or not v.bbox then error("BOUNDING_VOLUME unavailable",0) end
    local b=v.bbox;local out={minX=b.min.x,minY=b.min.y,maxX=b.max.x,maxY=b.max.y}
    if not sites.box(out) then error("invalid world bounding box",0) end;return out
end
function A.buildingIds(a,b)
    local map=call("townBuildingSystem.getTown2BuildingMap",function() return api.engine.system.townBuildingSystem.getTown2BuildingMap() end)
    local x,rx=flow.ids(map[a] or {},512);local y,ry=flow.ids(map[b] or {},512)
    if rx>0 or ry>0 then error("invalid_or_duplicate_town_building_ids",0) end
    return x,y
end
function A.building(id,town)
    local c=comp(id,"TOWN_BUILDING")
    if not c or c.town~=town then error("TOWN_BUILDING unavailable or belongs to another town",0) end
    local v=comp(id,"BOUNDING_VOLUME") or (flow.id(c.construction) and comp(c.construction,"BOUNDING_VOLUME"))
    return {id=id,box=box(v)}
end
function A.query(b,limit)
    local out,seen,overflow={},{},false
    call("octreeSystem.findIntersectingEntities",function()
        local q=api.type.Box3.new(api.type.Vec3f.new(b.minX,b.minY,-10000000),api.type.Vec3f.new(b.maxX,b.maxY,10000000))
        api.engine.system.octreeSystem.findIntersectingEntities(q,function(id,v)
            if not flow.id(id) then error("invalid_spatial_entity_id",0) end
            if not seen[id] then
                if #out>=limit then overflow=true;return end
                seen[id]=true;out[#out+1]={id=id,box=box(v)}
            end
        end)
    end)
    if overflow then error("station_spatial_query_limit",0) end
    table.sort(out,function(a,b) return a.id<b.id end);return out
end
local function startObject(raw,world)
    if raw.id==world or comp(raw.id,"TOWN") then return nil end
    local out={id=raw.id,box=raw.box,kind="unknown",source="BOUNDING_VOLUME"}
    if comp(raw.id,"TOWN_BUILDING") then out.kind="building";out.source=out.source.."+TOWN_BUILDING";return out end
    if comp(raw.id,"CONSTRUCTION") then out.kind="construction";out.source=out.source.."+CONSTRUCTION";return out end
    local edge=comp(raw.id,"BASE_EDGE")
    if edge then
        out.source=out.source.."+BASE_EDGE"
        if edge.roadType==api.type["enum"].RoadType.STREET then out.kind="street"
        elseif edge.roadType==api.type["enum"].RoadType.TRACK then out.kind="track" end
        local a,b=edge.position0,edge.position1
        if not a or not b or not flow.finite(a.x) or not flow.finite(a.y) or not flow.finite(b.x) or not flow.finite(b.y) then error("BASE_EDGE positions unavailable",0) end
        out.a={x=a.x,y=a.y};out.b={x=b.x,y=b.y}
        return out
    end
    if comp(raw.id,"MODEL_INSTANCE_LIST") then
        out.source=out.source.."+MODEL_INSTANCE_LIST"
        return out,models.start(raw.id)
    end
    return out
end
function A.startObjects(raw,world) return {raw=raw,world=world,objects={},cursor=1} end
function A.stepObjects(job,context)
    if job.finished then return end
    local visits,entities=0,0
    while job.cursor<=#job.raw and entities<16 and visits<models.perStep do
        if not job.pending then
            job.current,job.pending=startObject(job.raw[job.cursor],job.world)
        end
        if job.pending then
            visits=visits+models.step(job.pending,context,job.world,models.perStep-visits)
            if not job.pending.finished then break end
            job.current=models.apply(job.current,job.pending);job.pending=nil
        end
        if job.current then job.objects[#job.objects+1]=job.current end
        job.current=nil;job.cursor=job.cursor+1;entities=entities+1
    end
    if job.cursor>#job.raw then job.finished=true;job.raw=nil end
    return visits
end
-- Offline synchronous convenience only; live callers advance stepObjects once/callback.
function A.object(raw,world)
    local job=A.startObjects({raw},world);local ctx=A.newModelContext(world)
    while not job.finished do A.stepObjects(job,ctx) end
    return job.objects[1]
end

function A.stationIds(town)
    local ids,rejected=flow.ids(call("stationSystem.getStations",function() return api.engine.system.stationSystem.getStations(town) end),64)
    if rejected>0 then error("invalid_station_ids",0) end;return ids
end
function A.station(id)
    local station=comp(id,"STATION");if not station then error("STATION missing",0) end
    if #station.terminals>64 then error("station_terminal_limit",0) end
    local passenger=false
    for _,t in ipairs(station.terminals) do
        if type(t.passengersLoad)~="boolean" or type(t.passengersUnload)~="boolean" then
            error("STATION terminal passenger flags unavailable",0)
        end
        local modes=api.type["enum"].TransportMode
        if (t.transportModes[modes.TRAIN] or t.transportModes[modes.ELECTRIC_TRAIN])
            and (t.passengersLoad or t.passengersUnload) then passenger=true end
    end
    if not passenger then return nil end
    local v=comp(id,"BOUNDING_VOLUME")
    if not v then
        local construction=call("streetConnectorSystem.getConstructionEntityForStation",function() return api.engine.system.streetConnectorSystem.getConstructionEntityForStation(id) end)
        v=comp(construction,"BOUNDING_VOLUME")
    end
    return {id=id,box=box(v)}
end
function A.startClear(site,world)
    local job=A.startObjects(A.query(occupancy.queryBox(site),256),world);job.site=site;return job
end
function A.stepClear(job,context)
    if job.finished then return end
    -- Live requests supply their shared budget/cache; wrappers/tests own a private one.
    if not context then job.context=job.context or A.newModelContext(job.world);context=job.context end
    A.stepObjects(job,context)
    if job.finished then
        job.clear,job.reason,job.report=occupancy.inspect(job.site,job.objects)
        job.objects=nil
    end
end
-- Synchronous convenience for offline contract tests; the live owner advances one
-- bounded step per GUI callback using the same policy and adapter.
function A.clear(site,world)
    local job=A.startClear(site,world)
    while not job.finished do A.stepClear(job) end
    return job.clear,job.reason,job.report
end
return A
