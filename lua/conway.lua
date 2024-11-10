require("types")

local NOACTIVE = -1

local M = {}
local conway_timer = nil
local active_char = "■" --"▊" -- "▇" -- "■"
local update_interval = 100
local multiplier = 0.2

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
			vi[j] = math.random() < multiplier and 1 or 0
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
---@return number
local function get_last_active(row)
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
---@param grid Grid
---@param buf number
local function display_grid(grid, buf)
	local lines = {}
	for i = 1, #grid do
		local line = {}
		local index_last_active = get_last_active(grid[i])
		for j = 1, #grid[i] do
			if index_last_active + 1 == j or index_last_active == NOACTIVE then
				goto continue
			end
			table.insert(line, grid[i][j] == 1 and active_char or " ")
			::continue::
		end
		table.insert(lines, table.concat(line, ""))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Show the grid in the Neovim buffer
local function display_grid_fill_all(grid, buf)
	local lines = {}
	for i = 1, #grid do
		local line = {}
		for j = 1, #grid[i] do
			table.insert(line, grid[i][j] == 1 and active_char or " ")
		end
		table.insert(lines, table.concat(line, ""))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function unset_opts()
	vim.api.nvim_set_option_value("list", false, {})
	vim.api.nvim_set_option_value("number", false, {})
	vim.api.nvim_set_option_value("relativenumber", false, {})
	vim.api.nvim_set_option_value("colorcolumn", "", {})
end

local function create_scratch_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	unset_opts()
	return buf
end

local function defer_closing(buf)
	local _ = vim.api.nvim_create_augroup("conway", { clear = true })
	vim.api.nvim_create_autocmd({ "BufLeave", "BufUnload" }, {
		buffer = buf,
		once = true,
		group = "conway",
		callback = function()
			M.stop_conway()
			vim.api.nvim_clear_autocmds({ group = "conway" })
		end,
	})
end

local function fill_from_current_buffer(grid)
	local current_buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)

	for line_num, line in pairs(lines) do
		for char_num = 1, #line do
			local current_char = line:sub(char_num, char_num)
			if grid[line_num] ~= nil and current_char ~= " " then
				grid[line_num][char_num] = 1
			end
		end
	end
end

function M.from_current_buffer()
	local grid = initialize_grid()
	fill_from_current_buffer(grid)
	local buf = create_scratch_buffer()
	display_grid(grid, buf)
	defer_closing(buf)

	conway_timer = vim.uv.new_timer()
	conway_timer:start(
		0,
		update_interval,
		vim.schedule_wrap(function()
			grid = next_generation(grid)
			display_grid(grid, buf)
		end)
	)
end

function M.new_grid()
	local grid = initialize_grid()
	local buf = create_scratch_buffer()
	display_grid_fill_all(grid, buf)
end

-- Start Conway's Game of Life
function M.start_conway()
	local buf = create_scratch_buffer()
	local grid = initialize_grid()
	fill_grid_randomly(grid)
	display_grid(grid, buf)
	defer_closing(buf)

	conway_timer = vim.uv.new_timer()
	conway_timer:start(
		0,
		update_interval,
		vim.schedule_wrap(function()
			grid = next_generation(grid)
			display_grid(grid, buf)
		end)
	)
end

-- Stops the running timer
function M.stop_conway()
	if conway_timer then
		conway_timer:stop()
		conway_timer:close()
		conway_timer = nil
		print("Conway loop stopped")
	else
		print("No Conway loop is currently running")
	end
end

function M.setup(opts)
	print("setup yeaaah")
end

vim.api.nvim_create_user_command("ConwayRandom", M.start_conway, { nargs = 0 })
vim.api.nvim_create_user_command("ConwayFromCurrent", M.from_current_buffer, { nargs = 0 })
vim.api.nvim_create_user_command("ConwayNewGrid", M.new_grid, { nargs = 0 })
vim.api.nvim_create_user_command("ConwayStop", M.stop_conway, { nargs = 0 })

-- vim.api.nvim_create_user_command("Conway", function(opts)
-- 	local subcommand = opts.args:match("^%S+")
-- 	if subcommand == "yeah" then
-- 		print("yeah lets goooooo")
-- 	elseif subcommand == "fuck" then
-- 		print("oh fuck")
-- 	else
-- 		vim.notify("Dont know this command")
-- 	end
-- end, {
-- 	nargs = 1,
-- 	complete = function()
-- 		return { "yeah", "fuck" }
-- 	end,
-- })

return M
