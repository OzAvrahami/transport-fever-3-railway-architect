-- Pure conservative AABB policy. These regions are planning assumptions, not native footprints.
local P={bodyMargin=4,approachHalfWidth=16,routeMargin=12}
P.kinds={"building","construction","street","track","vegetation","unknown"}
function P.kind(o)
    for _,k in ipairs(P.kinds) do if o.kind==k then return k end end
    return "unknown"
end
function P.hard(o) return P.kind(o)~="vegetation" end
local function box(c,center,halfLength,halfWidth)
    local x,y=c.x+c.dx*center,c.y+c.dy*center
    local ex,ey=math.abs(c.dx)*halfLength+math.abs(c.dy)*halfWidth,math.abs(c.dy)*halfLength+math.abs(c.dx)*halfWidth
    return {minX=x-ex,maxX=x+ex,minY=y-ey,maxY=y+ey}
end
function P.regions(c)
    local edge=c.length/2;local reach=128
    return {body=box(c,0,edge+P.bodyMargin,c.width/2+P.bodyMargin),
        approach=box(c,(edge+reach)/2,(reach-edge)/2+P.bodyMargin,P.approachHalfWidth),
        neighborhood=c.clearance}
end
function P.intersects(a,b,p)
    p=p or 0
    return a.minX-p<=b.maxX and a.maxX+p>=b.minX and a.minY-p<=b.maxY and a.maxY+p>=b.minY
end
function P.queryBox(c)
    local r=P.regions(c)
    return {minX=math.min(r.body.minX,r.approach.minX),maxX=math.max(r.body.maxX,r.approach.maxX),
        minY=math.min(r.body.minY,r.approach.minY),maxY=math.max(r.body.maxY,r.approach.maxY)}
end
function P.overlaps(a,b)
    local x,y=P.regions(a),P.regions(b)
    for _,i in ipairs({"body","approach"}) do for _,j in ipairs({"body","approach"}) do
        if P.intersects(x[i],y[j]) then return true end
    end end
    return false
end
function P.inspect(c,objects)
    local regions=P.regions(c)
    local report={body={},approach={},neighborhood={},bodyConflicts=0,approachConflicts=0,
        vegetationClearance=0,blockedKinds={},examples={},modelGroupAffected=false,unknownGroupBlocked=false}
    for _,region in ipairs({"body","approach","neighborhood"}) do
        for _,kind in ipairs(P.kinds) do report[region][kind]=0 end
    end
    local reason
    for _,o in ipairs(objects) do
        local k=P.kind(o);local body=P.intersects(regions.body,o.box);local approach=P.intersects(regions.approach,o.box)
        for _,region in ipairs({"body","approach","neighborhood"}) do
            if P.intersects(regions[region],o.box) then report[region][k]=report[region][k]+1 end
        end
        if body or approach then
            if o.modelGroup then
                report.modelGroupAffected=true
                if k=="unknown" then report.unknownGroupBlocked=true end
            end
            if P.hard(o) then
                if body then report.bodyConflicts=report.bodyConflicts+1 end
                if approach then report.approachConflicts=report.approachConflicts+1 end
                report.blockedKinds[k]=true
                reason=reason or ((body and "station_body_" or "approach_unresolved_")..k)
            else report.vegetationClearance=report.vegetationClearance+1 end
            if #report.examples<3 then report.examples[#report.examples+1]={id=o.id,kind=k,
                region=body and "body" or "approach",source=o.source or "unclassified",issue=o.classificationIssue} end
        end
    end
    return reason==nil,reason,report
end
function P.blocksSample(o,x,y)
    local b=o.box;local p=P.routeMargin
    return P.hard(o) and x>=b.minX-p and x<=b.maxX+p and y>=b.minY-p and y<=b.maxY+p
end
function P.blocksApproach(anchor,direction,x,y,spacing)
    local dx,dy=x-anchor.x,y-anchor.y
    local length=math.sqrt(dx*dx+dy*dy)
    -- Same dot >= .7 condition already enforced by station_sites.approaches.
    return length>0 and math.abs(dx)<=spacing and math.abs(dy)<=spacing
        and (dx*direction.dx+dy*direction.dy)/length<0.7
end
-- Slab intersection, including touches. Grid samples alone cannot detect an obstacle
-- between two waypoints. Every final segment is checked before publishing a candidate.
function P.crosses(a,b,box,margin)
    local enter,leave=0,1;local p=margin or 0
    for _,axis in ipairs({{"x","minX","maxX"},{"y","minY","maxY"}}) do
        local start,delta=a[axis[1]],b[axis[1]]-a[axis[1]]
        local low,high=box[axis[2]]-p,box[axis[3]]+p
        if delta==0 then if start<low or start>high then return false end
        else
            local t0,t1=(low-start)/delta,(high-start)/delta
            if t0>t1 then t0,t1=t1,t0 end
            enter=math.max(enter,t0);leave=math.min(leave,t1)
            if enter>leave then return false end
        end
    end
    return true
end
function P.segment(a,b,objects)
    local vegetation=false
    for _,o in ipairs(objects) do
        if P.crosses(a,b,o.box,P.routeMargin) then
            if P.hard(o) then return o end
            vegetation=true
        end
    end
    return nil,vegetation
end
return P
