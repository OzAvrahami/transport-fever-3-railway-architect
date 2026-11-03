-- Deterministic A* on a validated model. One indexed heap entry per open sample.
local grid = ug_require "oz_railway_network_architect::/planning/corridor_grid.lua"
local search = {}
local offsets = {{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}

function search.start(model, weights, budget)
    return {model = model, weights = weights, budget = budget,
        stats = {expansions = 0, peakOpen = 0}, heap = {}, positions = {},
        cost = {}, priority = {}, heuristic = {}, parent = {}, closed = {}}
end

-- All continuation data is plain Lua; no coroutine/thread/function is retained.
function search.step(state, limit)
    assert(type(limit) == "number" and limit >= 1 and limit <= 49152 and limit % 1 == 0, "invalid expansion slice")
    if state.finished then return state.result end
    local model, weights, budget, stats = state.model, state.weights, state.budget, state.stats
    local function done(result)
        state.finished, state.result = true, result
        return result
    end
    if not model.cells[model.start].traversable or not model.cells[model.destination].traversable then
        return done({status = "unreachable", reason = "endpoint_unavailable", stats = stats})
    end
    local targetC, targetR = grid.indices(model, model.destination)
    local heap, positions, cost, priority, heuristic, parent, closed = state.heap, state.positions,
        state.cost, state.priority, state.heuristic, state.parent, state.closed
    local function less(a, b)
        if priority[a] ~= priority[b] then return priority[a] < priority[b] end
        if heuristic[a] ~= heuristic[b] then return heuristic[a] < heuristic[b] end
        return a < b
    end
    local function swap(a, b)
        heap[a], heap[b] = heap[b], heap[a]
        positions[heap[a]], positions[heap[b]] = a, b
    end
    local function offer(id, g)
        cost[id] = g
        if heuristic[id] == nil then
            local c, r = grid.indices(model, id)
            heuristic[id] = weights.distance * math.sqrt(((targetC - c) * model.spacingX)^2
                + ((targetR - r) * model.spacingY)^2)
        end
        priority[id] = g + heuristic[id]
        local at = positions[id]
        if at == nil then
            heap[#heap + 1] = id
            at, positions[id] = #heap, #heap
            stats.peakOpen = math.max(stats.peakOpen, #heap)
        end
        while at > 1 do
            local up = math.floor(at / 2)
            if not less(heap[at], heap[up]) then break end
            swap(at, up); at = up
        end
    end
    local function pop()
        local id, last = heap[1], heap[#heap]
        heap[#heap], positions[id] = nil, nil
        if #heap > 0 then
            heap[1], positions[last] = last, 1
            local at = 1
            while at * 2 <= #heap do
                local child = at * 2
                if child < #heap and less(heap[child + 1], heap[child]) then child = child + 1 end
                if not less(heap[child], heap[at]) then break end
                swap(at, child); at = child
            end
        end
        return id
    end
    if not state.initialized then offer(model.start, 0); state.initialized = true end
    local stop = stats.expansions + limit
    while #heap > 0 do
        if stats.expansions >= budget then return done({status = "search_limit", stats = stats}) end
        if stats.expansions >= stop then return nil end
        local id = pop()
        closed[id], stats.expansions = true, stats.expansions + 1
        if id == model.destination then
            local reversed, path, cursor = {}, {}, id
            while cursor do reversed[#reversed + 1] = cursor; cursor = parent[cursor] end
            for i = #reversed, 1, -1 do path[#path + 1] = reversed[i] end
            return done({status = "found", path = path, score = cost[id], stats = stats})
        end
        local column, row = grid.indices(model, id)
        for _, offset in ipairs(offsets) do
            local c, r = column + offset[1], row + offset[2]
            if c >= 0 and c < model.columns and r >= 0 and r < model.rows then
                local neighbor = r * model.columns + c + 1
                if not closed[neighbor] then
                    local metrics = grid.step(model, id, neighbor)
                    if metrics then
                        local candidate = cost[id] + grid.score(metrics, weights).total
                        -- Equal costs retain the first parent in the fixed traversal order.
                        if cost[neighbor] == nil or candidate < cost[neighbor] then
                            parent[neighbor] = id
                            offer(neighbor, candidate)
                        end
                    end
                end
            end
        end
    end
    return done({status = "unreachable", reason = "open_set_exhausted", stats = stats})
end

function search.run(model, weights, budget)
    local state = search.start(model, weights, budget)
    repeat search.step(state, 49152) until state.finished
    return state.result
end

return search
