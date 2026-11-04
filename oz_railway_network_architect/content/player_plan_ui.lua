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
    local t=v.confirmed:old() and state.testTrack or {}
    local selectedRoute=v.confirmed:old() and state.preview and tostring(state.preview.source.id)==choice.source
        and tostring(state.preview.destination.id)==choice.destination
    local status="Ready"
    if v.transportFailed:get() then status="Connection lost. Close and reopen this window."
    elseif t.status=="built" then status="Track built successfully"
    elseif t.status=="building" then status="Placing test track... Unpause to finish."
    elseif t.status=="failed" then status="Cannot place track here"
    elseif t.status=="unverified" then status="Track placement could not be confirmed. Check the map before continuing."
    elseif t.status=="expired" then status="Confirmation expired. Choose the test site again."
    elseif t.status=="confirm" then status="Test site ready"
    elseif state.busy then status="Planning railway..."
    elseif selectedRoute then status="Route found"
    elseif state.status=="ok" then status="Ready"
    elseif state.status=="waiting" or state.status=="loading" then status="Loading towns... Unpause briefly."
    elseif state.status~="idle" then status="No route found. Try another pair of towns." end
    if v.errorState:old()~="" and not v.transportFailed:get() then status="Action unavailable. Please try again when ready." end
    children[#children+1]=text(status)
    local function action(kind)
        if not available() or not v.confirmed:old() then return end
        local latest=v.current:get();local test=latest and latest.testTrack
        if not latest or not test or latest.world~=state.world or latest.epoch~=state.epoch
            or latest.requestId~=state.requestId or test.sequence~=t.sequence then return end
        if kind=="prepare" and (latest.busy or not test.eligible or test.attempted or not selectedRoute) then return end
        if kind~="prepare" and (test.status~="confirm" or test.confirmId~=t.confirmId) then return end
        v.errorState:set("")
        v.send("plan",{world=latest.world,epoch=latest.epoch,track={action=kind,requestId=test.sequence+1,
            corridorRequestId=latest.requestId,confirmId=test.confirmId,disposableCopy=kind=="confirm"}})
    end
    children[#children+1]=builtin.Button{content=text("Build Test Track"),
        meta={enabled=t.eligible==true and selectedRoute==true and not t.attempted and not state.busy and not v.transportFailed:get()},
        onClick=function() action("prepare") end}
    if t.status=="confirm" and v.confirmed:old() then
        children[#children+1]=text("This changes the map: one 80-metre track at the site now in view. It may adjust ground and charge your company. Only proceed on a disposable save copy you made. This does not build the planned route.")
        children[#children+1]=builtin.Button{content=text("This is my disposable copy — build one track"),onClick=function() action("confirm") end}
        children[#children+1]=builtin.Button{content=text("Cancel"),onClick=function() action("cancel") end}
    elseif t.eligible and selectedRoute and not t.attempted then
        children[#children+1]=text("For the test, pan to a clear, flat patch of land. Build Test Track checks the centre of your view before asking for confirmation.")
    end
    return children
end
return ui
