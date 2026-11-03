-- Synthetic values in metres. They are not TF3 railway design standards.
local fixtures = {}

function fixtures.flat(columns, rows)
    local input = {grid = {columns = columns, rows = rows, originX = 0, originY = 0,
        spacingX = 10, spacingY = 10, unit = "m", cells = {}},
        start = {x = 0, y = math.floor((rows - 1) / 2) * 10},
        destination = {x = (columns - 1) * 10, y = math.floor((rows - 1) / 2) * 10}}
    for id = 1, columns * rows do input.grid.cells[id] = {height = 0, water = false} end
    return input
end

function fixtures.cell(input, column, row)
    return input.grid.cells[(row - 1) * input.grid.columns + column]
end

function fixtures.mountain()
    local input = fixtures.flat(9, 7)
    for row = 2, 6 do fixtures.cell(input, 5, row).height = 40 end
    input.constraints = {maxGradient = 0.25} -- Illustrative rise/run cap only.
    return input
end

function fixtures.valley()
    local input = fixtures.flat(9, 7)
    for _, cell in ipairs(input.grid.cells) do cell.height = 3 end
    for column = 1, 9 do fixtures.cell(input, column, 2).height = 0 end
    for row = 2, 4 do
        fixtures.cell(input, 1, row).height = 0
        fixtures.cell(input, 9, row).height = 0
    end
    return input
end

function fixtures.water()
    local input = fixtures.flat(7, 5)
    for row = 1, 5 do fixtures.cell(input, 4, row).water = true end
    return input
end

function fixtures.comparison()
    local input = fixtures.flat(11, 9)
    -- Ridge: direct pass at row 5, lower pass at row 3, distant flat pass at row 1.
    for row = 2, 9 do fixtures.cell(input, 6, row).height = 20 end
    fixtures.cell(input, 6, 5).height = 5
    fixtures.cell(input, 6, 3).height = 2
    return input
end

return fixtures
