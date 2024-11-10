local NOACTIVE = -1
local CLOSING_GROUP_STRING = "conway_closing"

local M = {}
---@type uv_timer_t|nil
local conway_timer = nil
---@type ConwaySetupOpts
local default_opts = {
    on_char = "■", --"▊" -- "▇" -- "■"
    off_char = " ",
    update_interval_ms = 100,
    chance = 0.2,
}
local global_opts = default_opts

---initialize_grid creates a new matrix with zeroed values
---@return Grid
local function initialize_grid()
    local height = vim.api.nvim_win_get_height(0)
    local width = vim.api.nvim_win_get_width(0)

    local grid = {}
    for i = 1, height do
        grid[i] = {}
        for j = 1, width do
            grid[i][j] = 0
        end
    end
    return grid
end

---fill_grid_randomly iterates over every node in the grid and sets it to true
---with a chance defined by the global multiplier variable
---
---@param grid Grid
---@return Grid
local function fill_grid_randomly(grid)
    for _, vi in pairs(grid) do
        for j, _ in pairs(vi) do
            vi[j] = math.random() < global_opts.chance and 1 or 0
        end
    end
    return grid
end

---count_neighbors iterates over each neighbor node and checks how many active
---neighbors there are. This is important to determine the next state of the
---current node
---
---Example:
---  Imagine a glider shape where we want to look for neighbors of r which is
---  currently off
---
---1  x
---2 x r
---3 xxx
---
--- ```lua
--- local neighbors = count_neighbors(grid, 2, 3, 10, 10)
--- print(neighbors) -- should print 3 and therefore come alive
--- ```
---
---@param grid Grid
---@param x integer current row
---@param y integer actual position in the row
---@param max_height integer max height of where to look for neighbors
---@param max_width integer max width of where to look for neighbors
---@return integer count of actual active neighbors
local function count_neighbors(grid, x, y, max_height, max_width)
    local count = 0
    local directions = {
        { -1, -1 },
        { -1, 0 },
        { -1, 1 },
        { 0, -1 },
        { 0, 1 },
        { 1, -1 },
        { 1, 0 },
        { 1, 1 },
    }
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 1 and nx <= max_height and ny >= 1 and ny <= max_width and grid[nx][ny] == 1 then
            count = count + 1
        end
    end
    return count
end

---next_generation iterates over every node in the grid and counts each
---neighbors and setting the next state for each node.
---@param grid Grid
---@return Grid
local function next_generation(grid)
    local height = #grid
    local width = #grid[1]
    local new_grid = {}
    for i = 1, height do
        new_grid[i] = {}
        for j = 1, width do
            local neighbors = count_neighbors(grid, i, j, height, width)
            if grid[i][j] == 1 then
                -- A living cell survives only with 2 or 3 living neighbors
                new_grid[i][j] = (neighbors == 2 or neighbors == 3) and 1 or 0
            else
                -- A dead cell becomes alive with exactly 3 living neighbors
                new_grid[i][j] = (neighbors == 3) and 1 or 0
            end
        end
    end
    return new_grid
end

---get_last_active goes through each row and determines the index if the last
---active node. Which is useful to save some performance because we can skip
---emtpy nodes on rendering
---@param row Row
---@return number index or it returns the NOACTIVE constant which is just -1
local function get_last_active_node(row)
    for i = #row, 1, -1 do
        if row[i] == 1 then
            return i
        end
    end
    return NOACTIVE
end

---display_grid renders every node depending on its state. It is either a space
---or a block which can be manipulated by changing the active_char global
---constant
---@param grid Grid a matrix that holds all states of all nodes
---@param buf number the buffer to render to
---@param fill_all boolean wether to fill all possible positions or ignore the
--- ones after the last active node
local function render(grid, buf, fill_all)
    local lines = {}
    for i = 1, #grid do
        local line = {}
        local last_active = get_last_active_node(grid[i])
        for j = 1, #grid[i] do
            if fill_all or (last_active + 1 ~= j and last_active ~= NOACTIVE) then
                table.insert(line, grid[i][j] == 1 and global_opts.on_char or global_opts.off_char)
            end
        end
        table.insert(lines, table.concat(line, ""))
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

---unset_opts turns off options to make the rendered gol more appealing
local function unset_opts()
    vim.api.nvim_set_option_value("list", false, {})
    vim.api.nvim_set_option_value("number", false, {})
    vim.api.nvim_set_option_value("relativenumber", false, {})
    vim.api.nvim_set_option_value("colorcolumn", "", {})
end

---create_scratch_buffer spaws a new scratch buffer with turned off options such
---ass line numbering or white space indications
---@return integer bufferid which is the buffer id of the new created scratch buffer
local function create_scratch_buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    unset_opts()
    return buf
end

---defer_closing creates a new autocmd group which is responsible for stopping
---the timer. It registeres a new autocmd which listens to any event which gets
---triggered when the scratch buffer is destroyed. The autocmd gets destroyed
---as well when the timer was closed.
---@param bufferid integer - buffer id of the scratch buffer
local function defer_closing(bufferid)
    local _ = vim.api.nvim_create_augroup(CLOSING_GROUP_STRING, { clear = true })
    vim.api.nvim_create_autocmd({ "BufLeave", "BufUnload" }, {
        buffer = bufferid,
        once = true,
        group = CLOSING_GROUP_STRING,
        callback = function()
            M.destroy()
            vim.api.nvim_clear_autocmds({ group = CLOSING_GROUP_STRING })
        end,
    })
end

---read_from_current_buffer iterates over every character that is currently
---visible and takes an non whitespace character as a one or true.
---@param grid Grid
---@return Grid grid filled with active nodes depending on the character of the current buffer
local function read_from_current_buffer(grid)
    local current_buf = vim.api.nvim_get_current_buf()
    local first_line = vim.fn.line("w0") - 1 -- convert to zero based index by substracting 1
    local last_line = vim.fn.line("w$")

    local visible_lines = vim.api.nvim_buf_get_lines(current_buf, first_line, last_line, false)
    -- local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)

    for line_num, line in pairs(visible_lines) do
        for char_num = 1, #line do
            local current_char = line:sub(char_num, char_num)
            if grid[line_num] ~= nil and current_char ~= global_opts.off_char then
                grid[line_num][char_num] = 1
            end
        end
    end
    return grid
end

---grid_from_current_buffer combines two function to create a new grid from
---the currently visible characters of your current buffer
---@return Grid grid with active nodes depending on your current buffer
local function grid_from_current_buffer()
    return read_from_current_buffer(initialize_grid())
end

local function start_render_loop(grid, scratch)
    render(grid, scratch, false)
    defer_closing(scratch)

    conway_timer = vim.uv.new_timer()
    conway_timer:start(
        0,
        global_opts.update_interval_ms,
        vim.schedule_wrap(function()
            grid = next_generation(grid)
            render(grid, scratch, false)
        end)
    )
end

---from_current_buffer creates a new grid and reads in every character in your
---current buffer as a one and leaves everything else as a zero and starts
---the game of life loop
function M.from_current_buffer()
    local grid = grid_from_current_buffer()
    local scratch = create_scratch_buffer()
    start_render_loop(grid, scratch)
end

function M.anonymize()
    local grid = grid_from_current_buffer()
    local scratch = create_scratch_buffer()
    render(grid, scratch, false)
end

---new_grid creates and renders a new grid to a new scratch buffer which makes
---it easier to set nodes to 1 because you dont need write a bunch if spaces
function M.new_grid()
    local grid = initialize_grid()
    local buf = create_scratch_buffer()
    render(grid, buf, true)
end

--random iterates over every node and sets to 1 if the random number is greater
--than the multiplier variable. So a 20% change by default.
--It than runs the gol loop
function M.random()
    local scratch = create_scratch_buffer()
    local grid = initialize_grid()
    fill_grid_randomly(grid)
    start_render_loop(grid, scratch)
end

---destroy stops and removes the timer that runs the render loop
function M.pause()
    if conway_timer then
        conway_timer:stop()
        vim.notify("Conway loop paused")
    end
end

function M.resume()
    if conway_timer then
        conway_timer:again()
    end
end

---destroy stops and removes the timer that runs the render loop
function M.destroy()
    if conway_timer then
        conway_timer:stop()
        conway_timer:close()
        conway_timer = nil
        vim.notify("Conway loop stopped & destroyed", vim.log.levels.DEBUG)
    end
end

---setup applies options if defined
---@param opts ConwaySetupOpts
function M.setup(opts)
    if opts == nil then
        global_opts = default_opts
        return
    end

    for k, v in pairs(opts) do
        if v ~= nil then
            global_opts[k] = v
        end
    end
end

---@class ConwaySubcommands
local SUBCOMMANDS = {
    random = M.random,
    from_current = M.from_current_buffer,
    new_grid = M.new_grid,
    anonymize = M.anonymize,
    pause = M.pause,
    resume = M.resume,
    destroy = M.destroy,
}

---returns all values as slice
---@param t table<string, function>
---@return string[]
local function as_string_slice(t)
    local slice = {}
    for k, _ in pairs(t) do
        table.insert(slice, k)
    end
    return slice
end

---parse returns the corresponding subcommand
---@param s string
---@return nil|string
local function parse_cmd(s)
    for k, func in pairs(SUBCOMMANDS) do
        if s == k then
            func()
            return nil
        end
    end
    error("no such command")
end

---handles every subcommand
---@param opts any
local function handle_cmd(opts)
    local cmd = opts.args:match("^%S+")
    local ok, err = pcall(parse_cmd, cmd)
    if not ok then
        print("Error: ", err)
    end
end

---returns the keys as string values for neovim command completion
---@return string[]
local function cmd_completion()
    return as_string_slice(SUBCOMMANDS)
end

vim.api.nvim_create_user_command("Conway", handle_cmd, {
    nargs = 1,
    complete = cmd_completion,
})

return M
