local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    -- Mod-specific classes only; preserve native title bar, movement and focus.
    add("Window!rna-planner-window", {
        anchorPoint = {0.5, 0.5},
        gravity = {0.5, 0.5},
        size = {520, 360},
        minSize = {520, -1},
        maxSize = {520, "80vh"},
    })
    -- Native content inset; do not pad the outer window or its title bar.
    add("Window!rna-planner-window Window::Content", {
        padding = {20, 20, 20, 20},
    })
    add("ScrollArea!rna-planner-scroll", {gravity = {-1, -1}})
    add("BoxLayout!rna-planner-form", {
        gravity = {-1, 0},
        innerSpacing = {8, 8},
    })
    add("BoxLayout!rna-planner-form > Button", {gravity = {0, 0}})
    add("TextView!rna-planner-text", {
        maxSize = {440, -1},
        textAutoWrap = true,
        gravity = {0, 0},
    })
    add("ComboBox!rna-planner-town", {
        minSize = {-1, 32},
        maxSize = {440, -1},
        gravity = {-1, 0},
    })
    return result
end
