-- GUI-only keyed terrain ribbons. No engine objects, construction or React route arrays.
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local read = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local overlay = {maxSegments=1024, batchSize=16, halfWidth=12}
local prefix = "oz_railway_network_architect.route."
local function log(s) debugPrint("[RNA:ROUTE] "..s) end
local function context(state)
    if not state.routeOverlay then state.routeOverlay={sequence=0,serial=0,viewSerial=0,keys={},status="idle"} end
    return state.routeOverlay
end
local function finitePoint(p)
    return type(p)=="table" and flow.finite(p.x) and flow.finite(p.y) and flow.finite(p.z)
        and math.abs(p.x)<=1e7 and math.abs(p.y)<=1e7 and math.abs(p.z)<=1e7
end
-- Counterclockwise convex rectangle; its centreline is exactly the original segment.
-- Adjacent rectangles contain their shared waypoint, so bends have no disconnected gap.
function overlay.ribbon(a,b)
    if not finitePoint(a) or not finitePoint(b) then return nil,"invalid_waypoint" end
    local dx,dy=b.x-a.x,b.y-a.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.001 then return nil,"degenerate_segment" end
    local nx,ny=-dy/length*overlay.halfWidth,dx/length*overlay.halfWidth
    return {{x=a.x-nx,y=a.y-ny},{x=b.x-nx,y=b.y-ny},
        {x=b.x+nx,y=b.y+ny},{x=a.x+nx,y=a.y+ny}}
end
function overlay.clear(state,status)
    local o=context(state)
    o.job=nil;o.removing=#o.keys>0;o.cleanupBlocked=false;o.status=status or "hidden"
end
function overlay.reset(previous)
    overlay.clear(previous,"idle")
    local o=previous.routeOverlay;o.lease=nil;o.candidateId=nil
    return o -- Carry owned keys into the next session for bounded, exact-key cleanup.
end
function overlay.open(state)
    local o=context(state);overlay.clear(state,"hidden")
    o.viewSerial=o.viewSerial+1;o.lease=o.viewSerial;o.lastSeen=read.seconds()
end
function overlay.heartbeat(state,lease)
    local o=context(state)
    if o.lease and lease==o.lease then o.lastSeen=read.seconds() end
end
local function candidate(state,id)
    local r=state.request
    if not r or not r.finished or r.status~="ok" or not preview.valid(r.preview,state)
        or r.requestId~=state.requestId or r.world~=state.world or not r.result or r.result.status~="ok"
        or not r.result.complete or not r.result.snapshot or r.result.snapshot.world~=state.world then
        return nil,"completed_current_route_required"
    end
    local index
    for i,c in ipairs(r.preview.candidates) do if c.id==id then index=i;break end end
    local c=index and r.result.candidates[index]
    if not c or c.id~=id or c.searchStatus~="complete" or c.constructionStatus~="unverified"
        or c.feasibility~="sampled_constraints_satisfied" or type(c.waypoints)~="table"
        or c.sourceId~=r.sourceId or c.destinationId~=r.destinationId then return nil,"invalid_candidate" end
    local n=#c.waypoints
    if n<2 or n>overlay.maxSegments+1 then return nil,"route_render_limit_no_truncation" end
    -- Reuse the accepted pure continuity/endpoint validator, never the pathfinder.
    local checked,why=preview.build(state)
    if not checked then return nil,why end
    if n~=r.preview.candidates[index].waypointCount then return nil,"waypoint_count_changed" end
    for i=1,n do
        if not finitePoint(c.waypoints[i]) then return nil,"invalid_waypoint" end
        if i>1 and not overlay.ribbon(c.waypoints[i-1],c.waypoints[i]) then return nil,"degenerate_segment" end
    end
    local compact=r.preview.candidates[index]
    for _,pair in ipairs({{c.waypoints[1],compact.start},{c.waypoints[n],compact.destination}}) do
        for _,axis in ipairs({"x","y","z"}) do if pair[1][axis]~=pair[2][axis] then return nil,"endpoint_changed" end end
    end
    return c,index
end
function overlay.start(state,id)
    local o=context(state);overlay.clear(state,"rendering")
    local c,index=candidate(state,id)
    if not c then o.status="unsupported";log("UNAVAILABLE reason="..flow.text(index));return false,index end
    o.serial=o.serial+1;o.candidateId=id
    o.job={world=state.world,epoch=state.epoch,requestId=state.requestId,index=index,id=id,
        cursor=1,count=#c.waypoints-1,serial=o.serial}
    log("START request="..state.requestId.." candidate="..id.." segments="..o.job.count.." prohibitBuilding=false")
    return true
end
function overlay.completed(state)
    local o=context(state);local p=state.request and state.request.preview
    if o.lease and p then overlay.start(state,p.candidates[1].id) end
end
function overlay.working(state)
    local o=state.routeOverlay
    return o and not o.cleanupBlocked and (o.removing or o.job~=nil) or false
end
local function remove(o)
    local key=o.keys[#o.keys]
    local ok,err=pcall(function() api.gui.mission.removeZone(key) end)
    if not ok then o.cleanupBlocked=true;o.status="error";log("ERROR api=api.gui.mission.removeZone detail="..flow.text(err));return false end
    o.keys[#o.keys]=nil
    return true
end
function overlay.step(state)
    local o=context(state)
    if o.lease then
        local now=read.seconds()
        if not flow.finite(now) or not flow.finite(o.lastSeen) or now<o.lastSeen or now-o.lastSeen>5 then
            overlay.clear(state,"hidden");o.lease=nil;log("VIEW_EXPIRED")
        end
    end
    if not overlay.working(state) then return end
    local began=read.seconds()
    if not flow.finite(began) then overlay.clear(state,"error");o.cleanupBlocked=true;log("ERROR clock_unavailable");return end
    local work=0
    while o.removing and #o.keys>0 and work<overlay.batchSize do
        if not remove(o) then return end;work=work+1
    end
    if #o.keys==0 then o.removing=false end
    local j=o.job
    if not o.removing and j then
        local r=state.request
        if not o.lease or state.world~=j.world or state.epoch~=j.epoch or state.requestId~=j.requestId
            or not r or not r.finished or r.status~="ok" then overlay.clear(state,"hidden");return end
        local c=r.result.candidates[j.index]
        if not c or c.id~=j.id or #c.waypoints~=j.count+1 then overlay.clear(state,"error");return end
        while j.cursor<=j.count and work<overlay.batchSize do
            local poly,why=overlay.ribbon(c.waypoints[j.cursor],c.waypoints[j.cursor+1])
            if not poly then overlay.clear(state,"error");log("ERROR "..why);return end
            local key=prefix..j.epoch.."."..j.world.."."..j.requestId.."."..j.serial.."."..j.cursor
            -- Register before dispatch so an ambiguous exception is also cleaned up.
            o.keys[#o.keys+1]=key
            local ok,err=pcall(function()
                local points={}
                for i,p in ipairs(poly) do points[i]=api.type.Vec2f.new(p.x,p.y) end
                api.gui.mission.setZone(key,points,true,api.type.Vec4f.new(0,1,1,0.85),false,false,1)
            end)
            if not ok then overlay.clear(state,"error");log("ERROR api=api.gui.mission.setZone detail="..flow.text(err));return end
            j.cursor=j.cursor+1;work=work+1
        end
        if j.cursor>j.count then
            o.status="shown";o.job=nil
            log("DRAW_SUBMITTED request="..j.requestId.." candidate="..j.id.." zones="..#o.keys.." native_visibility=unverified")
        end
    end
    local ended=read.seconds()
    if not flow.finite(ended) or ended<began or ended-began>0.05 then
        overlay.clear(state,"error");log("ERROR rendering_work_budget_exceeded")
    elseif work>0 and not o.job and #o.keys==0 then log("CLEARED") end
end
function overlay.handle(state,p)
    local o=context(state)
    if type(p)~="table" or not o.lease or p.lease~=o.lease then return false,"stale_route_view" end
    if p.action=="close" then overlay.clear(state,"hidden");o.lease=nil;return true end
    if not flow.id(p.sequence) or p.sequence~=o.sequence+1 or p.requestId~=state.requestId then return false,"stale_route_action" end
    if p.action~="show" and p.action~="hide" and p.action~="focus" then return false,"invalid_route_action" end
    o.sequence=p.sequence
    if p.action=="hide" then overlay.clear(state,"hidden");return true end
    if p.action=="show" then return overlay.start(state,p.candidateId) end
    local c,why=candidate(state,p.candidateId);if not c then return false,why end
    local a=c.waypoints[math.floor((#c.waypoints+1)/2)]
    local minX,maxX,minY,maxY=a.x,a.x,a.y,a.y
    for _,v in ipairs(c.waypoints) do minX=math.min(minX,v.x);maxX=math.max(maxX,v.x);minY=math.min(minY,v.y);maxY=math.max(maxY,v.y) end
    local ok,err=pcall(function() api.gui.camera.focusPosition(api.type.Vec3f.new(a.x,a.y,a.z),math.max(300,math.sqrt((maxX-minX)^2+(maxY-minY)^2)*1.2)) end)
    if not ok then log("ERROR api=api.gui.camera.focusPosition detail="..flow.text(err));return false,"route_focus_failed" end
    return true
end
function overlay.summary(state)
    local o=context(state)
    return {status=o.status,lease=o.lease,sequence=o.sequence,candidateId=o.candidateId}
end
return overlay
