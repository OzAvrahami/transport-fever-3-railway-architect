-- Approximate passenger through-station reservations, not native station footprints.
local occupancy=ug_require "oz_railway_network_architect::/planning/station_occupancy.lua"
local sites={length=160,width=48,halfClearLength=256,halfClearWidth=32,
    approach=128,maxGrade=0.03,maxHeightRange=8,maxUrbanDistance=512,maxRoadDistance=256}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e7 end
function sites.box(b)
    return type(b)=="table" and finite(b.minX) and finite(b.minY) and finite(b.maxX) and finite(b.maxY)
        and b.minX<=b.maxX and b.minY<=b.maxY
end
function sites.intersects(a,b,p)
    p=p or 0
    return a.minX-p<=b.maxX and a.maxX+p>=b.minX and a.minY-p<=b.maxY and a.maxY+p>=b.minY
end
local function distance(x,y,p) return math.sqrt((x-p.x)^2+(y-p.y)^2) end
local function boxDistance(x,y,b)
    return math.sqrt(math.max(b.minX-x,0,x-b.maxX)^2+math.max(b.minY-y,0,y-b.maxY)^2)
end
function sites.bounds(c,halfLength,halfWidth)
    local ex=math.abs(c.dx)*halfLength+math.abs(c.dy)*halfWidth
    local ey=math.abs(c.dy)*halfLength+math.abs(c.dx)*halfWidth
    return {minX=c.x-ex,maxX=c.x+ex,minY=c.y-ey,maxY=c.y+ey}
end
function sites.generate(town,other)
    local b=town.urban;assert(sites.box(b),"occupied_urban_area_required")
    local cx,cy=(b.minX+b.maxX)/2,(b.minY+b.maxY)/2
    local ox,oy=(other.urban.minX+other.urban.maxX)/2,(other.urban.minY+other.urban.maxY)/2
    local out,seen={},{}
    local function add(x,y)
        x=math.floor(x/128+0.5)*128;y=math.floor(y/128+0.5)*128
        for axis=1,2 do
            local dx,dy=axis==1 and (ox>=x and 1 or -1) or 0,axis==2 and (oy>=y and 1 or -1) or 0
            local key=string.format("%d:%d:%d",x,y,axis)
            if not seen[key] then
                seen[key]=true
                local c={id=tostring(town.id)..":"..key,townId=town.id,name=town.name,x=x,y=y,dx=dx,dy=dy,
                    length=sites.length,width=sites.width,approximate=true,access="unknown"}
                c.approach={x=x+dx*sites.approach,y=y+dy*sites.approach}
                c.clearance=sites.bounds(c,sites.halfClearLength,sites.halfClearWidth)
                out[#out+1]=c
            end
        end
    end
    for _,margin in ipairs({192,384}) do for _,offset in ipairs({-256,0,256}) do
        add(b.minX-margin,cy+offset);add(b.maxX+margin,cy+offset)
        add(cx+offset,b.minY-margin);add(cx+offset,b.maxY+margin)
    end end
    table.sort(out,function(a,b) return a.id<b.id end)
    return out
end
function sites.screen(c,town,bounds)
    local clear,reason,report=occupancy.inspect(c,town.objects)
    c.occupancy=report
    local b=c.clearance
    if b.minX<=bounds.minX or b.maxX>=bounds.maxX or b.minY<=bounds.minY or b.maxY>=bounds.maxY then return nil,"boundary" end
    local urban,road,rail,station=math.huge,math.huge,math.huge,math.huge
    for _,v in ipairs(town.buildings) do urban=math.min(urban,boxDistance(c.x,c.y,v.box)) end
    if urban>sites.maxUrbanDistance then return nil,"remote_from_occupied_town" end
    if not clear then return nil,reason end
    for _,v in ipairs(town.objects) do
        if v.kind=="street" then road=math.min(road,distance(c.x,c.y,v.a),distance(c.x,c.y,v.b)) end
        if v.kind=="track" then rail=math.min(rail,distance(c.x,c.y,v.a),distance(c.x,c.y,v.b)) end
    end
    if road>sites.maxRoadDistance then return nil,"no_verified_nearby_road_endpoint" end
    for _,v in ipairs(town.stations) do station=math.min(station,boxDistance(c.x,c.y,v.box)) end
    c.evidence={urbanDistance=urban,roadEndpointDistance=road,trackEndpointDistance=rail<math.huge and rail or nil,
        existingPassengerStationDistance=station<math.huge and station or nil,walkingAccess="unknown",construction="unverified",
        vegetationClearance=report.vegetationClearance,clearanceStatus=report.vegetationClearance>0 and "provisional_vegetation_clearance" or "no_known_required_region_conflict"}
    -- Inspection evidence, not another mandatory footprint: prefer a clear straight
    -- exit over one known to meet an obstacle immediately beyond the approach point.
    local exit=occupancy.segment(c.approach,{x=c.approach.x+c.dx*128,y=c.approach.y+c.dy*128},town.objects)
    c.evidence.approachExitBlocked=exit~=nil
    return true
end
function sites.samplePosition(c,index)
    local u=-256+((index-1)%17)*32;local v=-32+math.floor((index-1)/17)*32
    return c.x+c.dx*u-c.dy*v,c.y+c.dy*u+c.dx*v
end
function sites.evaluate(c,samples)
    if #samples~=51 then return nil,"incomplete_terrain" end
    local low,high,grade=math.huge,-math.huge,0
    for i,s in ipairs(samples) do
        if not s.valid or not finite(s.height) or s.water~=false or type(s.errors)~="table" or #s.errors>0 then return nil,"unknown_terrain_or_water" end
        low=math.min(low,s.height);high=math.max(high,s.height)
        if (i-1)%17>0 then grade=math.max(grade,math.abs(s.height-samples[i-1].height)/32) end
        if i>17 then grade=math.max(grade,math.abs(s.height-samples[i-17].height)/32) end
    end
    if grade>sites.maxGrade or high-low>sites.maxHeightRange then return nil,"unsuitable_sampled_slope" end
    c.z=samples[26].height;c.approach.z=samples[30].height
    c.evidence.maxSampledGrade=grade;c.evidence.heightRange=high-low
    local e=c.evidence
    c.siteScore=e.urbanDistance/128+e.roadEndpointDistance/128+grade/0.02
        -(e.existingPassengerStationDistance and e.existingPassengerStationDistance<512 and 1 or 0)
        -(e.trackEndpointDistance and e.trackEndpointDistance<256 and 0.5 or 0)
    return c
end
function sites.shortlist(values)
    table.sort(values,function(a,b)
        local x,y=a.evidence.approachExitBlocked==true,b.evidence.approachExitBlocked==true
        if x~=y then return not x end
        return a.siteScore==b.siteScore and a.id<b.id or a.siteScore<b.siteScore
    end)
    local out={}
    for _,c in ipairs(values) do
        local distinct=true
        for _,old in ipairs(out) do if distance(c.x,c.y,old)<128 then distinct=false end end
        if distinct then out[#out+1]=c;if #out==3 then break end end
    end
    return out
end
function sites.pairs(a,b)
    local out={}
    for _,s in ipairs(a) do for _,d in ipairs(b) do
        local dx,dy=d.approach.x-s.approach.x,d.approach.y-s.approach.y
        local length=math.sqrt(dx*dx+dy*dy)
        if length>0 and not occupancy.overlaps(s,d) then
            local alignment=2-(dx*s.dx+dy*s.dy)/length+(dx*d.dx+dy*d.dy)/length
            out[#out+1]={source=s,destination=d,id=s.id.."/"..d.id,
                blockedExits=(s.evidence.approachExitBlocked and 1 or 0)+(d.evidence.approachExitBlocked and 1 or 0),
                score=s.siteScore+d.siteScore+length/1024+4*alignment}
        end
    end end
    table.sort(out,function(a,b)
        if a.blockedExits~=b.blockedExits then return a.blockedExits<b.blockedExits end
        return a.score==b.score and a.id<b.id or a.score<b.score
    end)
    return out
end
-- Independent XY segment/rectangle intersection. Keep the full corridor outside
-- both reserved station bodies; a later fitting stage must not assume this proves clearance.
local function crosses(a,b,box)
    local enter,leave=0,1
    for _,axis in ipairs({{"x","minX","maxX"},{"y","minY","maxY"}}) do
        local p,d=a[axis[1]],b[axis[1]]-a[axis[1]]
        if d==0 then if p<box[axis[2]] or p>box[axis[3]] then return false end
        else
            local t0,t1=(box[axis[2]]-p)/d,(box[axis[3]]-p)/d
            if t0>t1 then t0,t1=t1,t0 end
            enter=math.max(enter,t0);leave=math.min(leave,t1)
            if enter>leave then return false end
        end
    end
    return true
end
function sites.approaches(c,pair)
    local w=c.waypoints;local s,d=pair.source,pair.destination
    if #w<2 or w[1].x~=s.approach.x or w[1].y~=s.approach.y or w[1].z~=s.approach.z
        or w[#w].x~=d.approach.x or w[#w].y~=d.approach.y or w[#w].z~=d.approach.z then return false end
    local function directed(a,b,dx,dy)
        local x,y=b.x-a.x,b.y-a.y;local l=math.sqrt(x*x+y*y)
        return l>0 and (x*dx+y*dy)/l>=0.7
    end
    for _,site in ipairs({s,d}) do
        local box=sites.bounds(site,site.length/2+12,site.width/2+12)
        for i=2,#w do if crosses(w[i-1],w[i],box) then return false end end
    end
    return directed(w[1],w[2],s.dx,s.dy) and directed(w[#w],w[#w-1],d.dx,d.dy)
end
function sites.markers(s)
    local function rect(hl,hw,x,y)
        local out={}
        for _,v in ipairs({{-hl,-hw},{hl,-hw},{hl,hw},{-hl,hw}}) do
            out[#out+1]={x=x+s.dx*v[1]-s.dy*v[2],y=y+s.dy*v[1]+s.dx*v[2]}
        end
        return out
    end
    return {rect(s.length/2,s.width/2,s.x,s.y),rect(128,3,s.x,s.y),rect(8,8,s.approach.x,s.approach.y)}
end
function sites.valid(s)
    return type(s)=="table" and finite(s.x) and finite(s.y) and finite(s.z) and s.approximate==true
        and s.length==160 and s.width==48 and finite(s.dx) and finite(s.dy)
        and ((math.abs(s.dx)==1 and s.dy==0) or (math.abs(s.dy)==1 and s.dx==0))
        and type(s.approach)=="table" and s.approach.x==s.x+s.dx*128 and s.approach.y==s.y+s.dy*128 and finite(s.approach.z)
end
return sites
