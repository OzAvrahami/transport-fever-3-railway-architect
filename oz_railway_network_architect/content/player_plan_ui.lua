-- Player presentation only. Native work stays in the authoritative Game Script owner.
local builtin = ug_require "::/gui/main/builtin.lua"
local ui = {}
function ui.children(v)
    local text, state, choice = v.text, v.state, v.selection:old()
    local children = {}
    local function available()
        return v.isLive() and not v.sending:get() and not v.transportFailed:get()
    end
    local function combo(role,label)
        children[#children+1]=text(label)
        local counts,seen={},{}
        for _,town in ipairs(state.towns) do counts[town.name]=(counts[town.name] or 0)+1 end
        local items={builtin.ComboBoxItem{value="",content=text("Choose a town")}}
        for _,town in ipairs(state.towns) do
            seen[town.name]=(seen[town.name] or 0)+1
            local name=town.name..(counts[town.name]>1 and (" ("..seen[town.name]..")") or "")
            items[#items+1]=builtin.ComboBoxItem{value=tostring(town.id),content=text(name),
                available=tostring(town.id)~=choice[role=="source" and "destination" or "source"]}
        end
        children[#children+1]=builtin.ComboBox{value=choice[role],items=items,
            meta={class="rna-planner-town",enabled=state.canPlan==true and not state.busy},
            onValueChange=function(value)
                if not available() then return end
                local latest=v.current:get();if not latest or latest.busy then return end
                local previous=v.selected:get();local other=role=="source" and "destination" or "source"
                if value~="" and value==previous[other] then return end
                local nextValue={source=previous.source,destination=previous.destination};nextValue[role]=value
                v.selected:set(nextValue);v.selection:set(nextValue);v.errorState:set("")
                v.form:set({current=latest,selected=nextValue})
            end}
    end
    combo("source","Source town");combo("destination","Destination town")
    children[#children+1]=builtin.Button{content=text("Plan Railway"),
        meta={enabled=state.canPlan==true and not state.busy and not v.transportFailed:get()
            and choice.source~="" and choice.destination~="" and choice.source~=choice.destination},
        onClick=function()
            if not available() then return end
            local latest,pair=v.current:get(),v.selected:get()
            if not latest or latest.busy or not latest.canPlan or pair.source=="" or pair.destination=="" or pair.source==pair.destination then return end
            v.errorState:set("");v.confirmed:set(false)
            v.send("plan",{world=latest.world,epoch=latest.epoch,requestId=latest.requestId+1,
                sourceId=tonumber(pair.source),destinationId=tonumber(pair.destination)})
        end}
    local fresh=v.confirmed:old() and not v.transportFailed:get()
    local p=fresh and state.preview
    local o=fresh and state.routeOverlay or {}
    local status="Ready"
    if v.transportFailed:get() then status="Connection lost. Close and reopen this window."
    elseif state.busy then status="Planning railway..."
    elseif o.status=="rendering" then status="Showing route..."
    elseif o.status=="shown" then status="Proposed alignment shown on map"
    elseif o.status=="error" then status="Cannot show route. See the game log."
    elseif o.status=="unsupported" then status="Cannot display this route."
    elseif p then status="Route found"
    elseif state.status=="waiting" or state.status=="loading" then status="Loading towns... Unpause briefly."
    elseif state.status~="idle" and state.status~="ok" then status="No route found. Try another pair of towns." end
    if v.errorState:old()~="" and not v.transportFailed:get() then status="Action unavailable. Please try again when ready." end
    children[#children+1]=text(status)
    local function action(kind,id)
        if not available() or not fresh then return end
        local latest=v.current:get();local active=latest and latest.routeOverlay
        if not latest or not active or not active.lease or latest.world~=state.world or latest.epoch~=state.epoch
            or latest.requestId~=state.requestId or active.sequence~=o.sequence then return end
        v.errorState:set("")
        v.send("plan",{world=latest.world,epoch=latest.epoch,overlay={action=kind,lease=active.lease,
            sequence=active.sequence+1,requestId=latest.requestId,candidateId=id}})
    end
    if p and o.lease then
        children[#children+1]=text(p.source.name.." — "..p.destination.name)
        local selectedId=o.candidateId
        local found=false
        for _,c in ipairs(p.candidates) do if c.id==selectedId then found=true end end
        if not found then selectedId=p.candidates[1].id end
        if #p.candidates>1 then
            local items={}
            for i,c in ipairs(p.candidates) do items[i]=builtin.ComboBoxItem{value=c.id,content=text("Route "..i)} end
            children[#children+1]=builtin.ComboBox{value=selectedId,items=items,meta={class="rna-planner-town"},
                onValueChange=function(id) action("show",id) end}
        end
        children[#children+1]=builtin.Button{content=text("Hide Route"),meta={enabled=o.status=="shown" or o.status=="rendering"},
            onClick=function() action("hide",selectedId) end}
        children[#children+1]=builtin.Button{content=text("Show Route"),meta={enabled=o.status~="shown" and o.status~="rendering"},
            onClick=function() action("show",selectedId) end}
        children[#children+1]=builtin.Button{content=text("Focus Route"),onClick=function() action("focus",selectedId) end}
        children[#children+1]=text("Proposed alignment only. No railway has been built.")
    end
    return children
end
return ui
