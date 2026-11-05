-- Native vector/metadata/revision contract mocks, not TF3 acceptance.
local M=ug_require "oz_railway_network_architect::/station_model_classifier.lua"
local passed=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();passed=passed+1;print("PASS grouped models: "..name) end
local function setup(fatIds,thinIds,metadata)
    local f={reads=0,atCalls=0,revision={1,0,0},fat=fatIds or {},thin=thinIds or {}}
    local function vector(key) return {size=function() return #f[key] end,at=function(_,i)
        assert(i%1==0 and i>=1 and i<=#f[key],"native vector is one-based")
        f.atCalls=f.atCalls+1;return {modelId=f[key][i]}
    end} end
    f.component={fatInstances_native=vector('fat'),thinInstances_native=vector('thin')}
    -- Poison Lua-array access: the live adapter must use native bounded access.
    setmetatable(f.component,{__index=function(_,key) error('unverified or bulk access '..key) end})
    api={type={ComponentType={MODEL_INSTANCE_LIST='models'}},engine={
        getRevision=function() return {num=f.revision} end,
        getComponent=function(_,kind) eq(kind,'models');return f.component end},
        res={modelRep={get=function(id)
            f.reads=f.reads+1
            if metadata then return metadata(id) end
            return {metadata={tree={}}}
        end}}}
    f.ctx=M.context(99);f.job=M.start(42)
    function f.run()
        local steps=0
        while not f.job.finished do
            local calls=f.reads;local visits=M.step(f.job,f.ctx,99)
            assert(visits<=64 and f.reads-calls<=64);steps=steps+1;assert(steps<=100)
        end
        return M.apply({id=42,kind='unknown',source='BOUNDING_VOLUME+MODEL_INSTANCE_LIST'},f.job),steps
    end
    return f
end
local function ids(n,id) local r={};for i=1,n do r[i]=id or i end;return r end
test('1, 8, 9 and 513 instances are fully inspected; repeated model IDs use one resource lookup',function()
    for _,n in ipairs({1,8,9,513}) do
        local f=setup(ids(n,0));local out,steps=f.run()
        eq(out.kind,'vegetation');eq(out.modelGroup.inspected,n);eq(f.atCalls,n);eq(f.reads,1)
        eq(f.ctx.cacheHits,n-1);eq(steps,math.ceil(n/64));eq(out.spatialPrecision,'aggregate_AABB_unresolved')
    end
end)
test('fat and thin vectors both use one-based indexing without losing boundary references',function()
    local f=setup(ids(33,4),ids(37,5));local out=f.run()
    eq(out.kind,'vegetation');eq(f.reads,2);eq(out.modelGroup.inspected,70)
end)
test('a non-tree at the last index prevents vegetation, and all references are inspected',function()
    local f=setup(ids(129),{},function(id) return {metadata=id==129 and {} or {tree={}}} end)
    local out=f.run();eq(out.kind,'unknown');eq(out.modelGroup.outcome,'mixed_non_tree');eq(f.atCalls,129)
end)
test('rocks and incompatible vehicle or animal metadata cannot become trees',function()
    for _,m in ipairs({{rock={}},{tree={},rock={}},{tree={},transportVehicle={}},{tree={},animal={}},{tree={},person={}}}) do
        local f=setup({1},{},function() return {metadata=m} end)
        local out=f.run();eq(out.kind,'unknown');eq(out.modelGroup.outcome,'mixed_non_tree')
    end
end)
test('missing metadata and inaccessible resources are unknown and retain diagnostics',function()
    for _,fn in ipairs({function() return {} end,function() error('missing resource fixture') end}) do
        local f=setup(ids(9,1),{},fn);local out=f.run()
        eq(out.kind,'unknown');eq(out.modelGroup.inspected,9);eq(out.modelGroup.errors,9)
        eq(f.reads,1);eq(f.ctx.lookupErrors,1);assert(out.classificationIssue)
    end
end)
test('invalid resource IDs never reach modelRep and cannot be coerced into valid tree indices',function()
    for _,id in ipairs({-1,0.5,'1',false,0/0,math.huge,2147483648}) do
        local f=setup({id});local out=f.run();eq(out.kind,'unknown');eq(f.reads,0)
    end
    local f=setup({1});f.component.fatInstances_native.at=function() return {} end
    eq(f.run().kind,'unknown');eq(f.reads,0)
end)
test('4096 instances finish incrementally; 4097 are unknown with zero instance/resource reads',function()
    local f=setup(ids(4096,1));local out,steps=f.run();eq(out.kind,'vegetation');eq(steps,64)
    f=setup(ids(4097,1));out=f.run();eq(out.kind,'unknown');eq(out.modelGroup.instanceLimit,true);eq(f.atCalls,0);eq(f.reads,0)
end)
test('no partially inspected prefix can be exposed as vegetation',function()
    local f=setup(ids(129,1));M.step(f.job,f.ctx,99)
    eq(f.job.inspected,64);eq(f.job.finished,nil);assert(not pcall(M.apply,{},f.job))
    f.thin[1]=2 -- Structural change in the uninspected remainder invalidates the group.
    M.step(f.job,f.ctx,99);eq(f.job.outcome,'unknown');assert(f.job.reason:find('counts_changed',1,true))
end)
test('revision changes between or within callbacks invalidate even same-size groups',function()
    local f=setup(ids(129,1));M.step(f.job,f.ctx,99);f.revision[3]=1
    M.step(f.job,f.ctx,99);eq(f.job.outcome,'unknown');eq(f.job.inspected,64)
    f=setup({1});api.res.modelRep.get=function() f.revision[2]=2;return {metadata={tree={}}} end
    M.step(f.job,f.ctx,99);eq(f.job.outcome,'unknown')
end)
test('shared request visit budget leaves an uninspected remainder unknown',function()
    local f=setup({1,1});f.ctx.visits=M.maxVisits-1
    local out=f.run();eq(out.kind,'unknown');eq(out.modelGroup.inspected,1);eq(out.modelGroup.budgetLimit,true)
    eq(f.ctx.visits,M.maxVisits)
end)
test('unique resource budget caps calls and cache size; overflow never defaults to vegetation',function()
    local f=setup(ids(1025));local out=f.run();eq(out.kind,'unknown');eq(out.modelGroup.budgetLimit,true)
    eq(f.reads,1024);local n=0;for _ in pairs(f.ctx.cache) do n=n+1 end;eq(n,1024)
end)
test('world mismatch and failed native vector access are unknown',function()
    local f=setup({1});M.step(f.job,f.ctx,100);eq(f.job.outcome,'unknown');eq(f.reads,0)
    f=setup({1});f.component.fatInstances_native.at=function() error('bad native vector') end
    M.step(f.job,f.ctx,99);eq(f.job.outcome,'unknown');assert(f.job.reason:find('native:at',1,true))
end)
test('cache is per context and can be refreshed without resetting spent budgets',function()
    local f=setup(ids(9,1));eq(f.run().kind,'vegetation')
    api.res.modelRep.get=function() f.reads=f.reads+1;return {metadata={rock={}}} end
    f.job=M.start(43);eq(f.run().kind,'vegetation');eq(f.reads,1)
    f.ctx.cache={};f.job=M.start(43);eq(f.run().kind,'unknown');eq(f.ctx.lookups,2)
    f.ctx=M.context(99);f.job=M.start(43);eq(f.run().kind,'unknown');eq(f.ctx.lookups,1)
end)
test('empty groups and fractional vector lengths are unknown, not empty proven vegetation',function()
    local f=setup({});eq(f.run().kind,'unknown');eq(f.reads,0)
    f=setup({1});f.component.fatInstances_native.size=function() return 1.5 end
    eq(f.run().kind,'unknown');eq(f.atCalls,0)
end)
print('PASS '..passed..' grouped model classifier tests (mocked native reads)')
