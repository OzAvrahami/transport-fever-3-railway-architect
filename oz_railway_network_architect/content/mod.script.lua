-- TF3 resource-loading hook; this does not indicate live-map readiness.
function data()
    return {
        runFn = function()
            debugPrint("[oz_railway_network_architect] Phase 2A bootstrap loaded (revision 1; runScript).")
        end,
    }
end
