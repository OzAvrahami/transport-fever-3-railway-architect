-- Registration only: no simulation data writes, planning, or saved session state.
-- company.script.tl:380-389 subscribes engine state to names handled by its
-- guiHandleEvent. achievements.script.tl:180-196 initializes subscriptions in update.
function data()
    return {
        update = function(_params, state, _dt)
            if state:hasEventSubscriptions() then return end
            state:subscribeToEvent("oz_railway_network_architect.plan.status")
            state:subscribeToEvent("oz_railway_network_architect.plan.refresh")
            state:subscribeToEvent("oz_railway_network_architect.plan.plan")
            state:subscribeToEvent("reactPostInit")
            debugPrint("[RNA:PLAN:4B2] EVENT_SUBSCRIPTIONS_READY count=4")
        end,
    }
end
