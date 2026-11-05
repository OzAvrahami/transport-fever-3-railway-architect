-- Read-only native-vector continuation. Only plain counters and cached classifications
-- survive guiUpdate; never retain native components, vectors, models or transforms.
local flow=ug_require "oz_railway_network_architect::/live_plan_data.lua"
local M={maxInstances=4096,maxVisits=65536,maxResources=1024,perStep=64,maxModelId=2147483647}
local function call(path,fn)
    local ok,v=pcall(fn);if not ok then error(path..": "..tostring(v),0) end;return v
end
function M.context(world) return {world=world,visits=0,lookups=0,cache={},cacheHits=0,lookupErrors=0} end
function M.start(id) return {id=id,cursor=1,inspected=0,errors=0,nonTree=0,unknown=0} end
local function finish(j,outcome,reason)
    j.finished=true;j.outcome=outcome;j.reason=reason
end
local function revision(id)
    return call("api.engine.getRevision",function()
        local r=api.engine.getRevision(id);local out={}
        for i=1,3 do
            local n=r.num[i];if not flow.finite(n) or n%1~=0 then error("invalid_entity_revision",0) end
            out[i]=n
        end
        return out
    end)
end
local function same(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
local function resource(ctx,id)
    if not flow.id(id) or id>M.maxModelId then return {kind="unknown",error="invalid_model_id"} end
    local cached=ctx.cache[id]
    if cached then ctx.cacheHits=ctx.cacheHits+1;return cached end
    if ctx.lookups>=M.maxResources then return {kind="unknown",error="model_resource_budget_exhausted",budget=true} end
    ctx.lookups=ctx.lookups+1
    local ok,value=pcall(function()
        local model=call("api.res.modelRep.get",function() return api.res.modelRep.get(id) end)
        if not model or not model.metadata then error("model_metadata_unavailable",0) end
        local m=model.metadata
        -- Explicit incompatible metadata documented/used by installed game scripts.
        return {kind=m.tree and not (m.rock or m.transportVehicle or m.animal or m.person) and "tree" or "non_tree"}
    end)
    if not ok then ctx.lookupErrors=ctx.lookupErrors+1;value={kind="unknown",error=tostring(value):sub(1,240)} end
    ctx.cache[id]=value -- Request-local, including negative results; never cache a native model.
    return value
end
function M.step(j,ctx,world,allowance)
    if j.finished then return 0 end
    local visited=0
    local ok,err=pcall(function()
        if ctx.world~=world then error("model_context_world_changed",0) end
        local before=revision(j.id)
        if j.revision and not same(j.revision,before) then error("model_entity_revision_changed",0) end
        j.revision=j.revision or before
        local mil=call("api.engine.getComponent(MODEL_INSTANCE_LIST)",function()
            return api.engine.getComponent(j.id,api.type.ComponentType.MODEL_INSTANCE_LIST)
        end)
        local fat,thin=mil.fatInstances_native,mil.thinInstances_native
        local nf=call("MODEL_INSTANCE_LIST.fatInstances_native:size",function() return fat:size() end)
        local nt=call("MODEL_INSTANCE_LIST.thinInstances_native:size",function() return thin:size() end)
        if not flow.id(nf) or not flow.id(nt) then error("invalid_model_instance_counts",0) end
        if j.count and (nf~=j.fatCount or nt~=j.thinCount) then error("model_instance_counts_changed",0) end
        j.fatCount,j.thinCount,j.count=nf,nt,nf+nt
        if j.count==0 then finish(j,"unknown","empty_model_group");return end
        if j.count>M.maxInstances then j.instanceLimit=true;finish(j,"unknown","model_instance_limit_4096");return end
        local cap=math.min(allowance or M.perStep,M.perStep)
        while j.cursor<=j.count and visited<cap do
            if ctx.visits>=M.maxVisits then j.budgetLimit=true;finish(j,"unknown","model_visit_budget_65536");return end
            ctx.visits=ctx.visits+1;visited=visited+1
            local instance=call("MODEL_INSTANCE_LIST.native:at(1_based_index)",function()
                if j.cursor<=nf then return fat:at(j.cursor) end
                return thin:at(j.cursor-nf)
            end)
            local result=resource(ctx,instance and instance.modelId)
            j.inspected=j.inspected+1
            if result.kind=="non_tree" then j.nonTree=j.nonTree+1 end
            if result.kind=="unknown" then j.unknown=j.unknown+1;j.errors=j.errors+1;j.reason=j.reason or result.error end
            j.budgetLimit=j.budgetLimit or result.budget
            j.cursor=j.cursor+1
        end
        if not same(j.revision,revision(j.id)) then error("model_entity_revision_changed",0) end
        if j.cursor>j.count then
            if j.unknown>0 then finish(j,"unknown",j.reason)
            elseif j.nonTree>0 then finish(j,"mixed_non_tree","mixed_or_non_tree_models")
            else finish(j,"all_tree",nil) end
        end
    end)
    if not ok then j.errors=j.errors+1;finish(j,"unknown",tostring(err):sub(1,240)) end
    return visited
end
function M.apply(out,j)
    assert(j.finished,"model_group_not_complete")
    out.modelGroup={count=j.count or 0,inspected=j.inspected,outcome=j.outcome,errors=j.errors,
        instanceLimit=j.instanceLimit==true,budgetLimit=j.budgetLimit==true}
    out.spatialPrecision="aggregate_AABB_unresolved"
    if j.outcome=="all_tree" then
        assert(j.count==j.inspected and j.errors==0 and j.nonTree==0 and j.unknown==0)
        out.kind="vegetation";out.source=out.source.."+model.metadata.tree"
    else out.kind="unknown";out.classificationIssue=j.reason end
    return out
end
return M
