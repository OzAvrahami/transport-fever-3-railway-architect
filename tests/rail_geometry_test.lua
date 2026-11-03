-- Independent polynomial/Bezier oracles; no TF3 functions or installed script execution.
local curve = ug_require "oz_railway_network_architect::/geometry/rail_curve.lua"
local passed = 0
local function test(name, run)
    local ok, why = pcall(run); assert(ok, name .. ": " .. tostring(why))
    passed = passed + 1; print("PASS geometry: " .. name)
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, eps) assert(math.abs(a - b) <= (eps or 1e-8), tostring(a) .. " != " .. tostring(b)) end
local function p(x, y, z) return {x = x, y = y, z = z or 0} end
local function fit(points, options) return curve.fit({unit = "m", points = points, options = options}) end
local function valid(r) equal(r.status, "candidate"); equal(r.constructionStatus, "unverified"); equal(r.engineValidation, "not_run") end
local function encode(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys, parts = {}, {}; for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. encode(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
-- Cubic Bezier controls derived from endpoint derivatives. Evaluate by repeated
-- linear interpolation, independently of the implementation's Hermite polynomial.
local function controls(s, a)
    return {s.position0[a], s.position0[a] + s.tangent0[a] / 3,
        s.position1[a] - s.tangent1[a] / 3, s.position1[a]}
end
local function bezier(values, u)
    local v = {}; for i, x in ipairs(values) do v[i] = x end
    for n = #v - 1, 1, -1 do for i = 1, n do v[i] = v[i] * (1 - u) + v[i + 1] * u end end
    return v[1]
end
test("straight derivative scale, length and zero curvature", function()
    local r = fit({p(0,0), p(100,0)}); valid(r)
    local s = r.segments[1]
    equal(s.tangent0.x, 100); equal(s.tangent1.x, 100)
    for i = 0, 8 do local q,d,dd = curve.evaluate(s,i/8); near(q.x,100*i/8); near(d.x,100); near(dd.x,0) end
    near(r.diagnostics.approximateLength,100); equal(r.diagnostics.maxHorizontalCurvature,0)
    equal(r.diagnostics.minSampledRadius,nil); equal(r.diagnostics.maxAbsGradient,0)
end)
test("diagonal and negative forward tangents", function()
    local r = fit({p(30,40),p(0,0)}); valid(r)
    near(r.diagnostics.approximateLength,50)
    equal(r.segments[1].tangent0.x,-30); equal(r.segments[1].tangent1.y,-40)
    local q = curve.evaluate(r.segments[1],0.5); near(q.x,15); near(q.y,20)
end)
test("gentle curves match independent Bezier positions and derivatives", function()
    local r = fit({p(0,0,2),p(100,10,4),p(170,40,7),p(300,70,1)}); valid(r)
    for _,s in ipairs(r.segments) do
        for j = 0, 20 do
            local u = j/20; local q,d,dd = curve.evaluate(s,u)
            for _,a in ipairs({"x","y","z"}) do
                local b = controls(s,a)
                local first = {3*(b[2]-b[1]),3*(b[3]-b[2]),3*(b[4]-b[3])}
                local second = {2*(first[2]-first[1]),2*(first[3]-first[2])}
                near(q[a],bezier(b,u)); near(d[a],bezier(first,u)); near(dd[a],bezier(second,u))
            end
        end
    end
end)
test("unequal-length sections have independently verified C0 and C1 joins", function()
    local r = fit({p(-100,-80,-2),p(-90,-75,1),p(400,10,30),p(410,40,28)}); valid(r)
    for i = 1,#r.segments-1 do
        local a,b=r.segments[i],r.segments[i+1]
        for _,axis in ipairs({"x","y","z"}) do
            local left,right=controls(a,axis),controls(b,axis)
            near(left[4],right[1]); near(3*(left[4]-left[3]),3*(right[2]-right[1]))
        end
    end
end)
test("sharp corners yield radius-assumption violation without claiming infeasibility", function()
    local r=fit({p(0,0),p(100,0),p(100,100)}, {minRadius=1000})
    equal(r.status,"diagnostic_violation"); assert(r.diagnostics.radiusViolations>0)
    assert(r.diagnostics.minSampledRadius>0); equal(r.constructionStatus,"unverified")
end)
test("S-shaped route changes curvature sign", function()
    local r=fit({p(0,0),p(100,40),p(200,-40),p(300,0)}); valid(r)
    local pos,neg=false,false
    for _,s in ipairs(r.segments) do
        for j=0,16 do local _,d,dd=curve.evaluate(s,j/16)
            local k=d.x*dd.y-d.y*dd.x; pos=pos or k>1e-6; neg=neg or k< -1e-6
        end
    end
    assert(pos and neg)
end)
test("uphill and downhill gradient uses horizontal run", function()
    for _,sign in ipairs({-1,1}) do
        local r=fit({p(0,0,10),p(30,40,10+5*sign)}); valid(r)
        near(r.diagnostics.maxAbsGradient,0.1)
        near(r.segments[1].diagnostics.minSignedGradient,sign*0.1)
        near(r.diagnostics.approximateLength,math.sqrt(2525))
    end
end)
test("excessive gradient is caller policy and missing limit is not zero", function()
    local pts={p(0,0),p(100,0,50)}
    local r=fit(pts,{maxGradient=0.02}); equal(r.status,"diagnostic_violation")
    equal(r.diagnostics.gradientViolations,1); near(r.diagnostics.maxAbsGradient,0.5)
    valid(fit(pts)); equal(fit(pts).assumptions.maxGradient,nil)
    equal(fit(pts,{maxGradient=0}).status,"diagnostic_violation")
end)
test("consecutive exact duplicates are removed without dropping different elevations", function()
    local r=fit({p(0,0),p(0,0),p(100,0),p(100,0),p(200,20)})
    valid(r); equal(r.removedDuplicates,2); equal(#r.segments,2)
    equal(r.segments[2].sourceStartIndex,3); equal(r.segments[2].sourceEndIndex,5)
    equal(fit({p(0,0),p(0,0,1)}).status,"unsupported")
    equal(fit({p(0,0),p(0,0)}).status,"invalid_input")
    equal(fit({}).status,"invalid_input"); equal(fit({p(0,0)}).status,"invalid_input")
end)
test("reversals and near-stationary turns are rejected", function()
    equal(fit({p(0,0),p(100,0),p(0,0)}).status,"unsupported")
    equal(fit({p(0,0),p(100,0),p(0,1e-12)}).status,"unsupported")
end)
test("offset and negative world coordinates preserve shape", function()
    local a={p(0,0,-10),p(100,30,0),p(300,-20,15)}
    local b={}; for i,v in ipairs(a) do b[i]=p(v.x-500000,v.y+300000,v.z-70) end
    local x,y=fit(a),fit(b); valid(x); valid(y)
    near(x.diagnostics.approximateLength,y.diagnostics.approximateLength,1e-6)
    near(x.diagnostics.maxAbsGradient,y.diagnostics.maxAbsGradient)
    near(x.diagnostics.maxHorizontalCurvature,y.diagnostics.maxHorizontalCurvature)
end)
test("deterministic results and input immutability", function()
    local input={unit="m",points={p(0,0),p(100,20,4),p(200,0)},options={maxGradient=0.1}}
    local before=encode(input); local a,b=curve.fit(input),curve.fit(input)
    equal(encode(a),encode(b)); equal(encode(input),before)
    a.segments[1].position0.x=999; equal(input.points[1].x,0); equal(b.segments[1].position0.x,0)
end)
test("nonfinite, absent, sparse, unprojected or oversized coordinates fail explicitly", function()
    for _,v in ipairs({0/0,math.huge,-math.huge,1e8}) do equal(fit({p(0,0),p(v,1)}).status,"invalid_input") end
    equal(fit({p(0,0),{x=1,y=1}}).status,"invalid_input")
    equal(fit({[1]=p(0,0),[3]=p(1,1)}).status,"invalid_input")
    equal(fit({p(0,0),{x=1,y=1,z=0,water=false}}).reason,"project_xyz_explicitly")
    equal(curve.fit({unit="feet",points={p(0,0),p(1,1)}}).status,"invalid_input")
    equal(fit(setmetatable({p(0,0),p(1,1)},{})).status,"invalid_input")
end)
test("options and numerical minimum are explicit, never an engine minimum", function()
    local pts={p(0,0),p(0.001,0)}; valid(fit(pts))
    equal(fit(pts,{minChord=1}).status,"unsupported")
    for _,opt in ipairs({false,{diagnosticSteps=false},{minChord=false},{foo=1},{maxGradient=-1},{minRadius=0},{diagnosticSteps=65},{diagnosticSteps=7}}) do
        equal(fit(pts,opt).status,"invalid_input")
    end
    equal(fit({p(0,0),p(1e-7,0)}).status,"unsupported")
end)
test("hard work and memory bounds reject oversized input without truncation", function()
    local points={}; for i=1,256 do points[i]=p(i*100,0) end
    local r=fit(points,{diagnosticSteps=64}); valid(r)
    equal(#r.segments,255); equal(r.diagnostics.evaluatedPoints,255*65)
    points[257]=p(25700,0); local failed=fit(points)
    equal(failed.status,"resource_limit"); equal(#failed.segments,0)
end)
test("diagnostic curvature matches independent control derivatives", function()
    local r=fit({p(0,0),p(100,60),p(250,0)},{diagnosticSteps=16}); valid(r)
    for _,s in ipairs(r.segments) do
        local maxK=0
        for i=0,16 do
            local d,dd={},{}
            for _,a in ipairs({"x","y"}) do
                local b=controls(s,a); local c={3*(b[2]-b[1]),3*(b[3]-b[2]),3*(b[4]-b[3])}
                d[a]=bezier(c,i/16); dd[a]=bezier({2*(c[2]-c[1]),2*(c[3]-c[2])},i/16)
            end
            maxK=math.max(maxK,math.abs(d.x*dd.y-d.y*dd.x)/(d.x*d.x+d.y*d.y)^1.5)
        end
        near(s.diagnostics.maxHorizontalCurvature,maxK)
    end
end)
test("Bezier control projection is monotone along each non-reversing chord", function()
    local r=fit({p(0,0),p(100,10),p(105,50),p(20,150),p(-100,125)}); valid(r)
    for _,s in ipairs(r.segments) do
        local bx,by=controls(s,"x"),controls(s,"y")
        local dx,dy=s.position1.x-s.position0.x,s.position1.y-s.position0.y
        for i=1,3 do assert((bx[i+1]-bx[i])*dx+(by[i+1]-by[i])*dy>0) end
    end
end)
test("public evaluator validates parameter and vectors", function()
    local s=fit({p(0,0),p(10,0)}).segments[1]
    for _,v in ipairs({-1,2,math.huge,0/0}) do equal(curve.evaluate(s,v),nil) end
    s.tangent0=nil; equal(curve.evaluate(s,0.5),nil); equal(curve.evaluate(false,0),nil)
end)
test("near-straight numeric radius overflow remains distinct from zero radius", function()
    local r=fit({p(0,0),p(1000000,1e-300),p(2000000,0)})
    valid(r); equal(r.diagnostics.radiusStatus,"numeric_overflow")
    equal(r.diagnostics.minSampledRadius,nil); assert(r.diagnostics.maxHorizontalCurvature>0)
end)
test("prototype has no dependency on engine, commands or I/O", function()
    local originalApi,originalIo=api,io
    local trap=setmetatable({}, {__index=function() error("unexpected external access") end})
    api,io=trap,trap
    local ok,result=pcall(fit,{p(0,0),p(100,40),p(200,0)})
    api,io=originalApi,originalIo
    assert(ok); valid(result)
end)
print("PASS " .. passed .. " rail geometry tests (offline mathematics, not TF3 construction validation)")
