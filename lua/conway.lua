local M = {}
local conway_timer = nil

local function initialize_grid()
	local height = vim.api.nvim_win_get_height(0)
	local width = vim.api.nvim_win_get_width(0)

	local grid = {}
	for i = 1, height do
		grid[i] = {}
		for j = 1, width do
			grid[i][j] = 0 -- math.random() < 0.3 and 1 or 0 -- ca. 30% der Zellen leben zu Beginn
		end
	end
	return grid
end

local function fill_grid_random(grid)
	for _, vi in pairs(grid) do
		for j, _ in pairs(vi) do
			vi[j] = math.random() < 0.1 and 1 or 0
		end
	end
	return grid
end

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

-- Runs a tick (one iteration) of Conway's Game of Life.
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

-- Show the grid in the Neovim buffer
local function display_grid(grid, buf)
	local lines = {}
	for i = 1, #grid do
		local line = {}
		for j = 1, #grid[i] do
			table.insert(line, grid[i][j] == 1 and "■" or " ")
		end
		table.insert(lines, table.concat(line, ""))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Start Conway's Game of Life
function M.start_conway()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	local grid = initialize_grid()
	fill_grid_random(grid)
	display_grid(grid, buf)

	conway_timer = vim.loop.new_timer()
	conway_timer:start(
		0,
		1000,
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

vim.api.nvim_create_user_command("Conway", M.start_conway, { nargs = 0 })
vim.api.nvim_create_user_command("ConwayStop", M.stop_conway, { nargs = 0 })

return M
