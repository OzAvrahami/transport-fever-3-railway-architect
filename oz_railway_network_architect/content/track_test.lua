-- One explicitly confirmed native experiment. No automatic search, retry or removal.
local read = ug_require "oz_railway_network_architect::/live_plan_api.lua"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local curve = ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local track = {}
local resource = "::/infrastructure/track/simple/simple.street_template"
local style = "::/infrastructure/track/simple/simple.street"
local function log(text) debugPrint("[RNA:BUILD:MVP] " .. text) end
local function call(path, fn)
    local ok, result = pcall(fn)
    if not ok then error(path .. ": " .. tostring(result), 0) end
    return result
end
local function check(value, reason) if not value then error(reason, 0) end end
function track.busy(state)
    local t = state.testTrack
    return t and (t.status == "confirm" or t.status == "building") or false
end
function track.eligible(state)
    local r = state.request
    return not state.trackAttempted and state.ready == true and r and r.finished and r.status == "ok"
        and r.requestId == state.requestId and r.world == state.world and preview.valid(r.preview, state) or false
end
local function template()
    local id = call("streetTemplateRep.find", function() return api.res.streetTemplateRep.find(resource) end)
    check(flow.id(id), "track_resource_unavailable")
    local t = call("streetTemplateRep.get", function() return api.res.streetTemplateRep.get(id) end)
    check(t and t.roadType == api.type["enum"].RoadType.TRACK and t.streetStyle == style, "unexpected_track_resource")
    local sid = call("streetStyleRep.find", function() return api.res.streetStyleRep.find(style) end)
    check(flow.id(sid), "track_style_unavailable")
    check(#t.laneConfigs == 1, "expected_single_track_lane")
    local lane = t.laneConfigs[1]
    check(lane.transportModes[api.type["enum"].TransportMode.TRAIN] == true
        and flow.finite(lane.width) and lane.width > 0 and lane.width <= 10
        and flow.finite(lane.speed) and lane.speed > 0, "invalid_track_lane")
    return t
end
local function site(x, y, world)
    check(flow.finite(x) and flow.finite(y) and x % 1 == 0 and y % 1 == 0, "invalid_site_coordinates")
    local bounds, samples = read.bounds(), {}
    local low, high = math.huge, -math.huge
    -- 27 actual samples: 80 m east-west centerline and a 10 m strip on each side.
    for offset = -10, 10, 10 do for i = 0, 8 do
        local s = read.sample(bounds, x-40+i*10, y+offset)
        check(s.valid and #s.errors == 0 and flow.finite(s.height) and s.water == false,
            "site_terrain_unavailable_or_water: " .. table.concat(s.errors, "; "))
        samples[#samples+1] = s.height; low=math.min(low,s.height);high=math.max(high,s.height)
    end end
    check(high-low <= 0.4, "site_not_flat_enough_for_test") -- Experiment policy, not a TF3 rail limit.
    local box = call("Box3.new", function()
        return api.type.Box3.new(api.type.Vec3f.new(x-60,y-20,-1000000),api.type.Vec3f.new(x+60,y+20,1000000))
    end)
    local occupied, count = false, 0
    call("octreeSystem.findIntersectingEntities", function()
        api.engine.system.octreeSystem.findIntersectingEntities(box, function(id)
            count=count+1
            if count>256 then occupied=true;return end
            -- Town bounding volumes are not physical structures. Everything else blocks the site.
            if id ~= world and api.engine.getComponent(id,api.type.ComponentType.TOWN)==nil then occupied=true end
        end)
    end)
    check(not occupied, "site_occupied_or_query_limit")
    local a,b={x=x-40,y=y,z=samples[10]},{x=x+40,y=y,z=samples[18]}
    local fitted=curve.fit({unit="m",points={a,b},options={diagnosticSteps=8}})
    check(fitted.status=="candidate" and #fitted.segments==1, "invalid_straight_geometry")
    return {x=x,y=y,position0=a,position1=b,samples=samples}
end
local function same(a,b)
    if a.x~=b.x or a.y~=b.y then return false end
    for i,h in ipairs(a.samples) do if b.samples[i]~=h then return false end end
    return true
end
local function nativeProposal(s, t)
    local function vec(p) return api.type.Vec3f.new(p.x,p.y,p.z) end
    local p=api.type.SimpleProposal.new()
    local a,b=api.type.NodeAndEntity.new(),api.type.NodeAndEntity.new()
    a.entity,b.entity=-3,-4;a.comp.position,b.comp.position=vec(s.position0),vec(s.position1)
    local edge=api.type.SegmentAndEntity.new();edge.entity=-1;edge.type=1
    edge.comp.node0,edge.comp.node1=-3,-4
    edge.comp.position0,edge.comp.position1=vec(s.position0),vec(s.position1)
    local tangent={x=80,y=0,z=s.position1.z-s.position0.z}
    edge.comp.tangent0,edge.comp.tangent1=vec(tangent),vec(tangent)
    edge.comp.type,edge.comp.typeIndex=api.type["enum"].BaseEdgeType.NORMAL,1 -- Shipped isolated builder's NORMAL convention.
    edge.comp.roadType=api.type["enum"].RoadType.TRACK
    edge.comp.roadTemplate,edge.comp.roadStyle=resource,t.streetStyle
    edge.comp.laneConfigs=t.laneConfigs -- Copy into native component; never edit repository data.
    p.streetProposal.nodesToAdd={a,b};p.streetProposal.edgesToAdd={edge}
    p.streetProposal.nodesToRemove={};p.streetProposal.edgesToRemove={}
    p.streetProposal.edgeObjectsToRemove={};p.streetProposal.nodeConfigsToRemove={}
    p.constructionsToAdd={};p.constructionsToRemove={};p.old2new={}
    local context=api.type.Context.new()
    context.player=api.engine.util.getPlayer()
    check(flow.id(context.player) and api.engine.entityExists(context.player),"player_unavailable")
    context.checkTerrainAlignment=true;context.cleanupStreetGraph=false
    context.gatherBuildings=false;context.gatherFields=false;context.extendProposalRedoPillars=false
    return api.cmd.makeWorldBuildProposalCmd(p,context,false,true)
end
local function pointNear(a,b)
    return a and b and flow.finite(a.x) and flow.finite(a.y) and flow.finite(a.z)
        and math.abs(a.x-b.x)<0.02 and math.abs(a.y-b.y)<0.02 and math.abs(a.z-b.z)<0.02
end
local function verify(data, s)
    local found,seen=nil,{}
    check(data and data.resultEntities and #data.resultEntities<=16,"native_result_entities_unavailable_or_limit")
    for _,pair in ipairs(data.resultEntities) do
        local id=pair[1]
        check(flow.id(id) and api.engine.entityExists(id),"result_entity_missing")
        local e=api.engine.getComponent(id,api.type.ComponentType.BASE_EDGE)
        if e and not seen[id] then
            check(e.roadType==api.type["enum"].RoadType.TRACK and e.roadTemplate==resource
                and e.type==api.type["enum"].BaseEdgeType.NORMAL
                and pointNear(e.position0,s.position0) and pointNear(e.position1,s.position1),"result_track_geometry_mismatch")
            local a=api.engine.getComponent(e.node0,api.type.ComponentType.BASE_NODE)
            local b=api.engine.getComponent(e.node1,api.type.ComponentType.BASE_NODE)
            check(e.node0~=e.node1 and a and b and pointNear(a.position,s.position0) and pointNear(b.position,s.position1),"result_nodes_unverified")
            check(not found,"unexpected_multiple_tracks");found=id;seen[id]=true
        end
    end
    check(found,"new_track_not_verified")
    return found
end
local function nativeErrors(data)
    local result={}
    local ok=pcall(function()
        local e=data.resultProposalData.errorState
        for i,message in ipairs(e.messages) do if i>4 then break end;result[#result+1]=flow.text(message) end
    end)
    return ok and #result>0 and table.concat(result,"; ") or "no_native_error_messages_available"
end
function track.expire(state)
    local t=state.testTrack
    if t and t.status=="confirm" then
        local now=read.seconds()
        if not flow.finite(now) or now<t.began or now-t.began>30 or t.corridorRequestId~=state.requestId then
            t.status="expired";t.site=nil;log("CONFIRMATION_EXPIRED")
        end
    end
end
function track.handle(state, token, guiState)
    if type(token)~="table" or not flow.id(token.requestId) or token.requestId~=(state.trackSequence or 0)+1 then return false,"stale_track_request" end
    if token.action~="prepare" and token.action~="cancel" and token.action~="confirm" then return false,"invalid_track_action" end
    local t=state.testTrack
    if token.action=="cancel" then
        if not t or t.status~="confirm" or token.confirmId~=t.id then return false,"stale_confirmation" end
        state.trackSequence=token.requestId;t.status="cancelled";t.site=nil;return true
    end
    if state.trackAttempted then return false,"one_attempt_per_loaded_session" end
    if not track.eligible(state) then return false,"completed_route_required" end
    if token.corridorRequestId~=state.requestId then return false,"stale_corridor" end
    if token.action=="prepare" then
        if track.busy(state) then return false,"busy" end
        state.trackSequence=token.requestId
        t={id=token.requestId,status="preparing",world=state.world,epoch=state.epoch,corridorRequestId=state.requestId}
        state.testTrack=t
        local ok,why=pcall(function()
            local began=read.seconds();check(flow.finite(began),"clock_unavailable")
            template()
            local camera=call("gui.camera.getCameraData",function() return api.gui.camera.getCameraData() end)
            check(camera and flow.finite(camera.x) and flow.finite(camera.y),"camera_position_unavailable")
            t.site=site(math.floor(camera.x+0.5),math.floor(camera.y+0.5),state.world)
            t.began=read.seconds();check(flow.finite(t.began),"clock_unavailable")
            check(t.began>=began and t.began-began<=0.05,"preparation_work_limit")
            check(not flow.worldChanged(state,read.world()),"world_changed_during_preparation")
            t.status="confirm"
            call("gui.camera.focusPosition",function() api.gui.camera.focusPosition(api.type.Vec3f.new(t.site.x,t.site.y,t.site.position0.z),180) end)
        end)
        if not ok then t.status="failed";t.site=nil;log("SITE_REJECTED reason="..flow.text(why))
        else log("SITE_READY confirmation="..t.id.." x="..t.site.x.." y="..t.site.y.." length=80") end
        return true
    end
    if not t or t.status~="confirm" or token.confirmId~=t.id or token.disposableCopy~=true then return false,"explicit_disposable_confirmation_required" end
    track.expire(state);if t.status~="confirm" then return false,"confirmation_expired" end
    -- Consume before revalidation/dispatch. Never automatically retry ambiguous outcomes.
    state.trackSequence=token.requestId;state.trackAttempted=true;t.status="building"
    guiState:set(state)
    local issued=false
    local ok,why=pcall(function()
        local began=read.seconds();check(flow.finite(began),"clock_unavailable")
        local resourceData=template()
        check(same(t.site,site(t.site.x,t.site.y,state.world)),"terrain_changed_since_confirmation")
        check(not flow.worldChanged(state,read.world()),"world_changed_before_dispatch")
        local cmd=call("makeWorldBuildProposalCmd",function() return nativeProposal(t.site,resourceData) end)
        local ended=read.seconds();check(flow.finite(ended) and ended>=began and ended-began<=0.05,"confirmation_work_limit")
        check(not flow.worldChanged(state,read.world()),"world_changed_before_send")
        log("DISPATCH confirmation="..t.id.." world="..state.world.." ignoreErrors=false")
        issued=true
        api.cmd.sendCommand(cmd,function(data,success)
            local handled,reason=pcall(function()
                local latest=guiState:get()
                if not latest or latest.epoch~=t.epoch or latest.world~=t.world or flow.worldChanged(latest,read.world())
                    or not latest.testTrack or latest.testTrack.id~=t.id or latest.testTrack.status~="building" then
                    log("STALE_CALLBACK_DISCARDED success="..tostring(success));return
                end
                local current=latest.testTrack
                log("NATIVE_RESULT success="..tostring(success).." reason="..nativeErrors(data))
                if success~=true then current.status="failed"
                else
                    local verified,id=pcall(verify,data,current.site)
                    if verified then
                        current.status="built";current.entity=id;log("VERIFIED entity="..id)
                        local focused,err=pcall(function() api.gui.camera.focusPosition(api.type.Vec3f.new(current.site.x,current.site.y,current.site.position0.z),180) end)
                        if not focused then log("CAMERA_ERROR "..flow.text(err)) end
                    else current.status="unverified";log("VERIFY_FAILED "..flow.text(id)) end
                end
                current.site=nil;guiState:set(latest)
            end)
            if not handled then log("CALLBACK_ERROR "..flow.text(reason)) end
        end)
    end)
    if not ok then t.status=issued and "unverified" or "failed";t.site=nil;log("DISPATCH_OR_CHECK_FAILED "..flow.text(why)) end
    return true
end
function track.summary(state)
    local t=state.testTrack
    return {sequence=state.trackSequence or 0,status=t and t.corridorRequestId==state.requestId and t.status or "idle",confirmId=t and t.id,
        attempted=state.trackAttempted==true,eligible=track.eligible(state)}
end
return track
