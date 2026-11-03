local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local area = ug_require "::/gui/main/main_mod_button_area.tl"
local flow = ug_require "oz_railway_network_architect::/live_plan_data.lua"
local preview = ug_require "oz_railway_network_architect::/live_plan_preview.lua"
local networkData = ug_require "oz_railway_network_architect::/network_live_data.lua"
local worklist = ug_require "oz_railway_network_architect::/network_worklist.lua"
local eventId = "oz_railway_network_architect.plan"

-- Native window content is instantiated by the game's window container, never in
-- MainModButtonArea's horizontal/vertically non-scrolling subtree.
local PlannerWindow = react.RegisterWrapperRecipe("OzRailwayNetworkArchitectWindow", builtin.Window,
    function(params)
        local saved = params.form:get()
        local view = react.useState(saved.current or {towns = {}, status = "waiting", message = "Waiting for planner session."})
        local current = react.useRef(saved.current)
        local selection = react.useState(saved.selected or {source = "", destination = ""})
        local selected = react.useRef(saved.selected or {source = "", destination = ""})
        local errorState = react.useState("")
        local sending = react.useRef(false)
        local alive = react.useRef(true)
        local transportFailed = react.useRef(false)
        -- Reopen must receive a fresh session response before restoring a summary.
        local previewConfirmed = react.useState(false)
        local candidate = react.useState("")
        local candidateRef = react.useRef("")
        local networkLink = react.useState("")
        local networkLinkRef = react.useRef("")

        local function isLive()
            return not view:hasExpired() and alive:get() and params.isCurrent()
        end

        local function apply(value)
            local problem
            if type(value) ~= "table" then problem = "response_type=" .. type(value)
            elseif type(value.towns) ~= "table" then problem = "towns_type=" .. type(value.towns)
            elseif not flow.id(value.epoch) then problem = "invalid_epoch=" .. flow.text(value.epoch)
            elseif not flow.id(value.requestId) or not flow.id(value.listVersion) then problem = "invalid_request_or_catalog_version"
            elseif type(value.status) ~= "string" or type(value.message) ~= "string" then problem = "invalid_status_or_message"
            elseif type(value.busy) ~= "boolean" or type(value.canPlan) ~= "boolean" then problem = "invalid_busy_or_canPlan" end
            if problem then
                error("api.gui.fireGuiScriptEvent: planner response unavailable; " .. problem, 0)
            end
            local count = 0
            for key in pairs(value.towns) do
                count = count + 1
                if count > 256 then error("api.gui.fireGuiScriptEvent: town response exceeds limit", 0) end
                if not flow.id(key) or key < 1 or key > 256 then
                    error("api.gui.fireGuiScriptEvent: towns response is not an array", 0)
                end
            end
            for index = 1, count do
                local town = value.towns[index]
                if type(town) ~= "table" or not flow.id(town.id) or type(town.name) ~= "string" then
                    error("api.gui.fireGuiScriptEvent: malformed town record index=" .. index, 0)
                end
            end
            if value.networkSummary ~= nil and not networkData.valid(value.networkSummary, value) then
                error("api.gui.fireGuiScriptEvent: invalid network summary", 0)
            end
            if value.worklist ~= nil and not worklist.valid(value.worklist, value) then
                error("api.gui.fireGuiScriptEvent: invalid network worklist", 0)
            end
            if value.corridorOrigin ~= nil then
                local o = value.corridorOrigin
                if type(o) ~= "table" or o.world ~= value.world or o.epoch ~= value.epoch
                    or o.requestId ~= value.requestId or type(o.lines) ~= "table" or #o.lines ~= 4 then
                    error("api.gui.fireGuiScriptEvent: invalid corridor origin", 0)
                end
                for _, line in ipairs(o.lines) do
                    if type(line) ~= "string" or #line > 1600 then error("invalid corridor origin text", 0) end
                end
            end
            local old = current:get()
            local linkId = networkLinkRef:get()
            if not old or old.world ~= value.world or old.epoch ~= value.epoch
                or old.networkRequestId ~= value.networkRequestId or not networkData.find(value.networkSummary, linkId) then
                linkId = value.networkSummary and value.networkSummary.links[1] and value.networkSummary.links[1].id or ""
            end
            networkLinkRef:set(linkId); networkLink:set(linkId)
            if value.preview ~= nil and not preview.valid(value.preview, value) then
                error("api.gui.fireGuiScriptEvent: invalid corridor summary", 0)
            end
            local selectedCandidate = candidateRef:get()
            if not old or old.epoch ~= value.epoch or old.world ~= value.world or old.requestId ~= value.requestId
                or not preview.find(value.preview, selectedCandidate) then
                selectedCandidate = value.preview and value.preview.candidates[1].id or ""
            end
            candidateRef:set(selectedCandidate); candidate:set(selectedCandidate)
            previewConfirmed:set(true)
            if not old or old.epoch ~= value.epoch or old.world ~= value.world or old.listVersion ~= value.listVersion then
                selected:set({source = "", destination = ""})
                selection:set(selected:get())
                errorState:set("")
            end
            current:set(value); view:set(value)
            params.form:set({current = value, selected = selected:get()})
        end
        local function send(name, request)
            if not isLive() or sending:get() or (name == "status" and transportFailed:get()) then return end
            sending:set(true)
            -- onStepTimer uses restricted deferred work. Dispatch only in the
            -- documented main-thread join, also for mount and user actions.
            react.enqueueJoin(function()
                if not isLive() then return end
                local trace = params.nextTrace()
                request._rnaTrace = trace
                local function traceEvent(message)
                    if trace.enabled then
                        debugPrint("[RNA:PLAN:4B2] COMM " .. message .. " trace=" .. trace.id)
                    end
                end
                traceEvent("GUI_DISPATCH id=" .. eventId .. " name=" .. eventId .. "." .. name)
                local ok, result = pcall(function()
                    local value = api.gui.fireGuiScriptEvent(eventId, eventId .. "." .. name, request)
                    traceEvent("GUI_RESULT type=" .. type(value)
                        .. " towns_type=" .. (type(value) == "table" and type(value.towns) or "unavailable")
                        .. " epoch=" .. (type(value) == "table" and flow.text(value.epoch) or "unavailable")
                        .. " response_trace=" .. (type(value) == "table" and flow.text(value._rnaTraceId) or "unavailable"))
                    if isLive() then apply(value) end
                    return value
                end)
                if not isLive() then return end
                sending:set(false)
                if not ok then
                    transportFailed:set(true)
                    previewConfirmed:set(false)
                    errorState:set("Interface error: " .. flow.text(result) .. " | Polling paused; use Refresh towns to retry.")
                    debugPrint("[RNA:PLAN:4B2] UI_ERROR api=api.gui.fireGuiScriptEvent action=" .. name
                        .. " trace=" .. trace.id .. " polling=paused detail=" .. flow.text(result))
                    return
                end
                transportFailed:set(false)
                if result.reason then errorState:set("Request rejected: " .. flow.text(result.reason)) end
            end, "RNA:PLAN:4B2:" .. name)
        end

        react.onMount(function() send("status", {}) end)
        react.onUnmount(function()
            if not alive:hasExpired() then alive:set(false) end
            params.onDetached()
        end)
        react.onStepTimer(function() send("status", {}) end, 0.5, false)
        react.useInputAction("IA_MENU_BACK", react.iaHandler(params.onClose))

        local function text(value)
            return builtin.TextView {text = value, meta = {class = "rna-planner-text"}}
        end
        local children = {}
        local state = view:old()
        local choice = selection:old()
        local function combo(role, other)
            local items = {builtin.ComboBoxItem {value = "", content = text("Select town...")}}
            for _, town in ipairs(state.towns) do
                items[#items + 1] = builtin.ComboBoxItem {
                    value = tostring(town.id), available = tostring(town.id) ~= other,
                    content = text(flow.text(town.name):sub(1, 70) .. " [#" .. town.id .. "]"),
                }
            end
            return builtin.ComboBox {
                meta = {class = "rna-planner-town", enabled = state.canPlan == true and not state.busy},
                value = choice[role], items = items,
                onValueChange = function(value)
                    if not isLive() then return end
                    local previous = selected:get()
                    local nextValue = {source = previous.source, destination = previous.destination}
                    local otherRole = role == "source" and "destination" or "source"
                    if value ~= "" and value == previous[otherRole] then
                        errorState:set("Select two different towns."); return
                    end
                    nextValue[role] = value
                    selected:set(nextValue); selection:set(nextValue); errorState:set("")
                    params.form:set({current = current:get(), selected = nextValue})
                end,
            }
        end
        children[#children + 1] = text("Source town")
        children[#children + 1] = combo("source", choice.destination)
        children[#children + 1] = text("Destination town")
        children[#children + 1] = combo("destination", choice.source)
        children[#children + 1] = builtin.Button {
            content = text("Plan"),
            meta = {enabled = state.canPlan == true and not state.busy and not transportFailed:get()
                and choice.source ~= "" and choice.destination ~= "" and choice.source ~= choice.destination},
            onClick = function()
                if not isLive() then return end
                local snapshot, pair = current:get(), selected:get()
                if sending:get() or transportFailed:get() or not snapshot or snapshot.busy then return end
                if pair.source == "" or pair.destination == "" or pair.source == pair.destination then
                    errorState:set("Select two different towns."); return
                end
                errorState:set("")
                previewConfirmed:set(false)
                send("plan", {world = snapshot.world, epoch = snapshot.epoch, requestId = snapshot.requestId + 1,
                    sourceId = tonumber(pair.source), destinationId = tonumber(pair.destination)})
            end,
        }
        children[#children + 1] = builtin.Button {
            content = text("Refresh towns"), meta = {enabled = not state.busy or transportFailed:get()},
            onClick = function()
                if not isLive() or sending:get() then return end
                errorState:set(""); previewConfirmed:set(false); send("refresh", {})
            end,
        }
        children[#children + 1] = builtin.Button {
            content = text("Analyze Network"),
            meta = {enabled = state.canAnalyze == true and not state.busy and not transportFailed:get()},
            onClick = function()
                if not isLive() or sending:get() or transportFailed:get() then return end
                local snapshot = current:get()
                if not snapshot or snapshot.busy or not snapshot.canAnalyze then return end
                errorState:set(""); previewConfirmed:set(false)
                send("analyzeNetwork", {world = snapshot.world, epoch = snapshot.epoch, requestId = snapshot.networkRequestId + 1})
            end,
        }
        children[#children + 1] = text("Status: " .. state.status .. " | Towns: " .. #state.towns)
        children[#children + 1] = text(errorState:old() ~= "" and errorState:old() or state.message)
        children[#children + 1] = text("Approximate town anchors. Corridors are not construction-ready.")
        children[#children + 1] = text("Work timing resolution is unverified; zero readings do not mean zero cost.")
        if previewConfirmed:old() and not transportFailed:get() and state.corridorOrigin then
            for _, line in ipairs(state.corridorOrigin.lines) do children[#children + 1] = text(line) end
        end
        children[#children + 1] = text("Corridor summary (in-panel only; not a map overlay)")
        local summary = previewConfirmed:old() and not transportFailed:get() and state.preview or nil
        if summary then
            local items = {}
            for _, c in ipairs(summary.candidates) do
                items[#items + 1] = builtin.ComboBoxItem {value = c.id,
                    content = text("Rank " .. c.rank .. " | " .. c.profile)}
            end
            children[#children + 1] = builtin.ComboBox {
                meta = {class = "rna-planner-town"}, value = candidate:old(), items = items,
                onValueChange = function(id)
                    if not isLive() or transportFailed:get() then return end
                    local latest = current:get()
                    -- Ignore callbacks retained from a replaced result or old session.
                    if not latest or latest.world ~= state.world or latest.epoch ~= state.epoch
                        or latest.requestId ~= state.requestId or not preview.find(latest.preview, id) then return end
                    candidateRef:set(id); candidate:set(id)
                end,
            }
        end
        for _, line in ipairs(preview.lines(summary, candidate:old())) do children[#children + 1] = text(line) end
        children[#children + 1] = text("Network: " .. (state.networkStatus or "idle") .. " | "
            .. (state.networkMessage or "No network analysis requested."))
        local networkSummary = previewConfirmed:old() and not transportFailed:get() and state.networkSummary or nil
        if networkSummary then
            for _, line in ipairs(networkSummary.lines) do children[#children + 1] = text(line) end
            if #networkSummary.links > 0 then
                local items = {}
                for _, link in ipairs(networkSummary.links) do
                    local entry = worklist.find(state.worklist, link.id)
                    local suffix = entry and (" | " .. (entry.included and "included" or "excluded")
                        .. " | " .. entry.actor .. (entry.furtherStudy and " | further study" or "")) or ""
                    items[#items + 1] = builtin.ComboBoxItem {value = link.id, content = text(link.label .. suffix)}
                end
                children[#children + 1] = builtin.ComboBox {
                    meta = {class = "rna-planner-town"}, value = networkLink:old(), items = items,
                    onValueChange = function(id)
                        if not isLive() or transportFailed:get() then return end
                        local latest = current:get()
                        if not latest or latest.world ~= state.world or latest.epoch ~= state.epoch
                            or latest.networkRequestId ~= state.networkRequestId
                            or not networkData.find(latest.networkSummary, id) then return end
                        networkLinkRef:set(id); networkLink:set(id)
                    end,
                }
                local link = networkData.find(networkSummary, networkLink:old())
                for _, line in ipairs(link and link.lines or {}) do children[#children + 1] = text(line) end
            end
        end
        children[#children + 1] = text("Network Plan")
        local plan = networkSummary and state.worklist or nil
        local planEntry = worklist.find(plan, networkLink:old())
        if plan then
            for _, line in ipairs(plan.lines) do children[#children + 1] = text(line) end
            if planEntry then
                children[#children + 1] = text("Selected connection: " .. (planEntry.included and "included" or "excluded")
                    .. " | Original proposal: " .. planEntry.classification .. " | Decision: " .. planEntry.actor
                    .. " (" .. planEntry.action .. ") | Further study: " .. tostring(planEntry.furtherStudy))
                children[#children + 1] = text("Original branch relationship: " .. planEntry.branchRelationship)
            end
        else children[#children + 1] = text(state.worklistError or "Run Analyze Network to create a session worklist.") end
        local function editButton(label, action, all)
            return builtin.Button {
                content = text(label),
                meta = {enabled = plan ~= nil and not state.busy and not transportFailed:get() and (all or planEntry ~= nil)},
                onClick = function()
                    if not isLive() or sending:get() or transportFailed:get() or not previewConfirmed:old() then return end
                    local latest = current:get()
                    if not plan or not latest or latest.busy or not latest.worklist
                        or latest.world ~= state.world or latest.epoch ~= state.epoch
                        or latest.worklist.snapshotId ~= plan.snapshotId or latest.worklist.networkRequestId ~= plan.networkRequestId
                        or latest.worklist.revision ~= plan.revision then return end
                    local edgeId = not all and networkLinkRef:get() or nil
                    if not all and not worklist.find(latest.worklist, edgeId) then return end
                    errorState:set("")
                    send("plan", {world = latest.world, epoch = latest.epoch,
                        worklist = {networkRequestId = plan.networkRequestId, snapshotId = plan.snapshotId,
                            revision = plan.revision, action = action, edgeId = edgeId}})
                end,
            }
        end
        for _, item in ipairs({{"Include in plan", "include"}, {"Exclude from plan", "exclude"},
            {"Restore original recommendation", "restore"}, {"Mark for further study", "mark_study"}}) do
            children[#children + 1] = editButton(item[1], item[2], false)
        end
        children[#children + 1] = editButton("Reset all edits", "reset_all", true)
        local studyLink = networkData.find(networkSummary, networkLink:old())
        children[#children + 1] = builtin.Button {
            content = text("Study Corridor"),
            meta = {enabled = state.canStudy == true and not state.busy and not transportFailed:get()
                and studyLink ~= nil and studyLink.recommended == true and (not planEntry or planEntry.included)},
            onClick = function()
                if not isLive() or sending:get() or transportFailed:get() or not previewConfirmed:old() then return end
                local latest = current:get()
                -- Retained callbacks must not launch a different/newer recommendation.
                if not latest or latest.busy or not latest.canStudy or latest.world ~= state.world
                    or latest.epoch ~= state.epoch or latest.networkRequestId ~= state.networkRequestId
                    or not networkSummary or not latest.networkSummary
                    or latest.networkSummary.snapshotId ~= networkSummary.snapshotId then return end
                local link = networkData.find(latest.networkSummary, networkLinkRef:get())
                if not link or not link.recommended then return end
                local edited = worklist.find(latest.worklist, link.id)
                if edited and not edited.included then return end
                errorState:set(""); previewConfirmed:set(false)
                send("plan", {world = latest.world, epoch = latest.epoch, requestId = latest.requestId + 1,
                    network = {requestId = latest.networkRequestId,
                        snapshotId = latest.networkSummary.snapshotId, edgeId = link.id}})
            end,
        }
        if networkSummary and state.studyReason then children[#children + 1] = text(state.studyReason) end
        return builtin.Window {
            meta = {class = "rna-planner-window"},
            id = "oz_railway_network_architect.plan.window",
            title = "Railway Network Architect",
            closable = true, movable = true, pinnable = false,
            initialX = 0.5, initialY = 0.5,
            autoFocusOnBecomingVisible = true, autoVisibilityOnFocusChange = false,
            onClose = params.onClose,
            content = builtin.ScrollArea {
                meta = {class = "rna-planner-scroll"},
                horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
                verticalPolicy = builtin.type.ScrollBarPolicy.Simple,
                content = builtin.Component {
                    layout = builtin.BoxLayout {meta = {class = "rna-planner-form"},
                        orientation = builtin.type.Orientation.Vertical, children = children},
                },
            },
        }
    end)

local RailwayNetworkArchitect = react.RegisterPluginRecipe(area.MainModButtonAreaExtension,
    "OzRailwayNetworkArchitect", function()
        local opened = react.useState(false)
        local openRef = react.useRef(false)
        local form = react.useRef({})
        local owner = react.useRef(nil)
        local generation = react.useRef(0)
        local traceSequence = react.useRef(0)
        local alive = react.useRef(true)
        local failure = react.useState("")

        local function guarded(path, operation)
            local ok, reason = pcall(operation)
            if not ok then
                if alive:get() then failure:set(path .. ": " .. flow.text(reason)) end
                debugPrint("[RNA:PLAN:4B2] UI_ERROR detail=" .. path .. ": " .. flow.text(reason))
            end
            return ok
        end
        local function detached(token)
            if generation:hasExpired() or token ~= generation:get() then return end
            owner:set(nil); openRef:set(false)
            if alive:get() then opened:set(false) end
        end
        local function close(token, returnFocus)
            if token ~= generation:get() then return end
            guarded("WindowAPI.removeAllWindows", function()
                local container = owner:get()
                if container and not container:hasExpired() then
                    container:get():getApi().removeAllWindows(PlannerWindow)
                end
                detached(token)
                if returnFocus and alive:get() then
                    -- Native Mods focus handler; no global keybinding or control replacement.
                    react.fireEvent(nil, "focusMainModButtonArea")
                end
            end)
        end
        react.onMount(function()
            alive:set(true)
            debugPrint("[RNA:PLAN:4B2] UI_INIT entry=MainModButtonArea launcher_only=true request=none communication=trace-v1")
        end)
        react.onUnmount(function()
            alive:set(false)
            close(generation:get(), false)
        end)
        local launcher = builtin.Button {
            meta = {tooltip = failure:old() ~= "" and failure:old() or "Open or close the corridor planning window"},
            content = builtin.TextView {text = failure:old() ~= "" and "Railway Network Architect (UI error)"
                or (opened:old() and "Close Railway Network Architect" or "Railway Network Architect")},
            onClick = function()
                failure:set("")
                if openRef:get() then close(generation:get(), true); return end
                guarded("game_react_globals.getDefaultWindowContainer / WindowAPI.addSingletonWindow", function()
                    -- Lazy import: game.tl owns the extension loader and must finish initializing first.
                    local globals = ug_require "::/gui/main/game_react_globals.tl"
                    local container = globals.getDefaultWindowContainer()
                    if not container or container:hasExpired() then error("native window container unavailable", 0) end
                    local token = generation:get() + 1
                    generation:set(token)
                    container:get():getApi().addSingletonWindow(PlannerWindow, {
                        -- WindowContainer forwards these to WindowContainerChild.
                        initialX = 0.5, initialY = 0.5,
                        form = form,
                        nextTrace = function()
                            local sequence = traceSequence:get() + 1
                            traceSequence:set(sequence)
                            return {id = "w" .. token .. ":e" .. sequence, enabled = sequence <= 8}
                        end,
                        isCurrent = function()
                            return not opened:hasExpired() and alive:get() and generation:get() == token
                                and not container:hasExpired()
                        end,
                        onClose = function() close(token, true) end,
                        onDetached = function() detached(token) end,
                    })
                    owner:set(container); openRef:set(true); opened:set(true)
                end)
            end,
        }
        return builtin.BoxLayout {
            orientation = builtin.type.Orientation.Horizontal,
            children = {launcher},
        }
    end)

-- Lua script-resource exports use data(); the shipped Teal example returns a table.
function data()
    return {RailwayNetworkArchitect = RailwayNetworkArchitect}
end
