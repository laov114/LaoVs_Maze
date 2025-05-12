# MazeGenerator.gd
class_name MazeGenerator

# --- 常量 ---
const N: int = 1  # 北
const E: int = 2  # 东
const S: int = 4  # 南
const W: int = 8  # 西

# 方向向量 (使用 Vector2i, Godot 的 Y 轴向下为正)
const DIRECTIONS: Dictionary = {
	N: Vector2i.UP,    # (0, -1)
	E: Vector2i.RIGHT, # (1, 0)
	S: Vector2i.DOWN,  # (0, 1)
	W: Vector2i.LEFT   # (-1, 0)
}

# 相反方向
const OPPOSITE: Dictionary = {N: S, E: W, S: N, W: E}

# --- 变量 ---
var grid: Array = []       # 2D 数组，存储每个单元格的墙壁状态 (位掩码)
var width: int = 0
var height: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var visited: Array = []    # 用于 DFS 和 Prim 算法

# --- 初始化和工具函数 ---
func _init():
	rng.randomize()

func initialize_grid(w: int, h: int):
	width = w
	height = h
	grid.clear()
	visited.clear()

	for y in range(height):
		var row: Array = []
		var visited_row: Array = []
		for x in range(width):
			row.append(N | E | S | W) # 所有墙壁都存在
			visited_row.append(false)
		grid.append(row)
		visited.append(visited_row)

func _is_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func _get_cell_value(pos: Vector2i) -> int:
	if _is_valid(pos):
		return grid[pos.y][pos.x]
	return -1 # 表示无效

func _set_cell_value(pos: Vector2i, value: int):
	if _is_valid(pos):
		grid[pos.y][pos.x] = value

func _is_visited(pos: Vector2i) -> bool:
	if _is_valid(pos):
		return visited[pos.y][pos.x]
	return true # 将界外视为已访问，以简化边界检查

func _set_visited(pos: Vector2i, value: bool = true):
	if _is_valid(pos):
		visited[pos.y][pos.x] = value

func _remove_wall(cell_pos: Vector2i, neighbor_pos: Vector2i, dir_to_neighbor: int):
	if not (_is_valid(cell_pos) and _is_valid(neighbor_pos)):
		printerr("Error: Attempting to remove wall between invalid cells.")
		return

	var current_cell_walls = _get_cell_value(cell_pos)
	_set_cell_value(cell_pos, current_cell_walls & ~dir_to_neighbor)
	
	var neighbor_cell_walls = _get_cell_value(neighbor_pos)
	_set_cell_value(neighbor_pos, neighbor_cell_walls & ~OPPOSITE[dir_to_neighbor])

# --- 算法1: 深度优先搜索 (Recursive Backtracker) ---
func generate_dfs(start_pos_override: Vector2i = Vector2i(-1, -1)):
	if width == 0 or height == 0:
		printerr("Grid not initialized. Call initialize_grid() first.")
		return

	for r in visited: r.fill(false) # 重置 visited

	var stack: Array[Vector2i] = [] # 类型提示
	var current_pos: Vector2i

	if start_pos_override != Vector2i(-1, -1) and _is_valid(start_pos_override):
		current_pos = start_pos_override
	else:
		current_pos = Vector2i(rng.randi_range(0, width - 1), rng.randi_range(0, height - 1))

	_set_visited(current_pos)
	stack.push_back(current_pos)

	while not stack.is_empty():
		current_pos = stack.back()
		var unvisited_neighbors: Array = [] # 存储 {"pos": Vector2i, "dir": int}

		var dir_keys = DIRECTIONS.keys()
		dir_keys.shuffle() # 随机化邻居检查顺序

		for dir_key in dir_keys:
			var neighbor_pos: Vector2i = current_pos + DIRECTIONS[dir_key]
			if _is_valid(neighbor_pos) and not _is_visited(neighbor_pos):
				unvisited_neighbors.append({"pos": neighbor_pos, "dir": dir_key})

		if not unvisited_neighbors.is_empty():
			var chosen_data = unvisited_neighbors.pick_random() # Godot 4 feature
			_remove_wall(current_pos, chosen_data.pos, chosen_data.dir)
			_set_visited(chosen_data.pos)
			stack.push_back(chosen_data.pos)
		else:
			stack.pop_back() # 回溯

# --- 算法2: Prim 算法 ---
func generate_prims(start_pos_override: Vector2i = Vector2i(-1, -1)):
	if width == 0 or height == 0:
		printerr("Grid not initialized. Call initialize_grid() first.")
		return

	for r in visited: r.fill(false) # 重置 visited
	
	var wall_list: Array = [] # 存储 {"cell1": Vector2i, "cell2": Vector2i, "dir_c1_to_c2": int}

	var current_pos: Vector2i
	if start_pos_override != Vector2i(-1, -1) and _is_valid(start_pos_override):
		current_pos = start_pos_override
	else:
		current_pos = Vector2i(rng.randi_range(0, width - 1), rng.randi_range(0, height - 1))
	
	_set_visited(current_pos)

	# 添加初始单元格的墙壁到列表
	for dir_key in DIRECTIONS.keys():
		var neighbor_pos: Vector2i = current_pos + DIRECTIONS[dir_key]
		if _is_valid(neighbor_pos): # 只需要确保邻居在界内
			wall_list.append({"cell1": current_pos, "cell2": neighbor_pos, "dir_c1_to_c2": dir_key})
	
	if not wall_list.is_empty():
		wall_list.shuffle()

	while not wall_list.is_empty():
		var wall_idx = rng.randi_range(0, wall_list.size() - 1) # Or use wall_list.pick_random() if you remove later
		var wall_data = wall_list[wall_idx]
		wall_list.remove_at(wall_idx)

		var cell1_pos = wall_data.cell1
		var cell2_pos = wall_data.cell2

		# 如果墙壁一侧的单元格已访问，另一侧未访问
		if _is_visited(cell1_pos) != _is_visited(cell2_pos): # One is true, other is false
			_remove_wall(cell1_pos, cell2_pos, wall_data.dir_c1_to_c2)
			
			var newly_visited_pos: Vector2i
			if not _is_visited(cell1_pos):
				newly_visited_pos = cell1_pos
			else:
				newly_visited_pos = cell2_pos
			
			_set_visited(newly_visited_pos)
			
			# 将新单元格的墙壁（通向未访问区域的）添加到 wall_list
			for new_dir_key in DIRECTIONS.keys():
				var next_neighbor_pos: Vector2i = newly_visited_pos + DIRECTIONS[new_dir_key]
				if _is_valid(next_neighbor_pos) and not _is_visited(next_neighbor_pos):
					wall_list.append({"cell1": newly_visited_pos, "cell2": next_neighbor_pos, "dir_c1_to_c2": new_dir_key})
			
			# 可选：再次打乱以获得更随机的 Prim 行为，但会影响性能
			# if not wall_list.is_empty(): wall_list.shuffle()


# --- 算法3: Binary Tree 算法 ---
func generate_binary_tree():
	if width == 0 or height == 0:
		printerr("Grid not initialized. Call initialize_grid() first.")
		return

	for y in range(height):
		for x in range(width):
			var current_pos = Vector2i(x, y)
			var possible_carve_dirs: Array[int] = [] # 类型提示

			# 偏向北或西
			if current_pos.y > 0: # 可以向北打通
				possible_carve_dirs.append(N)
			if current_pos.x > 0: # 可以向西打通
				possible_carve_dirs.append(W)

			if not possible_carve_dirs.is_empty():
				var chosen_dir = possible_carve_dirs.pick_random() # Godot 4
				var neighbor_pos: Vector2i = current_pos + DIRECTIONS[chosen_dir]
				_remove_wall(current_pos, neighbor_pos, chosen_dir)
			# 如果单元格在 (0,0)，则没有北或西可以打通，它将保持封闭（除非作为其他单元格的邻居被打通）

# --- (可选) 文本打印函数，用于调试 ---
func print_maze_text():
	if width == 0 or height == 0:
		print("Grid not initialized.")
		return

	var output_string = ""
	for y in range(height):
		var top_line = "" 
		var mid_line = "" 
		
		for x in range(width):
			var cell_pos = Vector2i(x,y)
			var cell_walls = _get_cell_value(cell_pos)
			
			top_line += "+" + ("---" if (cell_walls & N) else "   ")
			mid_line += ("|" if (cell_walls & W) else " ") + "   "
		
		top_line += "+\n"
		var last_cell_east_wall = _get_cell_value(Vector2i(width-1, y))
		mid_line += ("|" if (last_cell_east_wall & E) else " ") + "\n" 
		
		output_string += top_line
		output_string += mid_line
	
	var bottom_line = ""
	for x in range(width):
		var cell_walls_bottom_row = _get_cell_value(Vector2i(x, height-1))
		bottom_line += "+" + ("---" if (cell_walls_bottom_row & S) else "   ")
	bottom_line += "+\n"
	output_string += bottom_line
	
	print(output_string)


func open_wall_at(cell_pos: Vector2i, direction_to_open: int):
	if not _is_valid(cell_pos):
		printerr("Cannot open wall for invalid cell: ", cell_pos)
		return
	if not DIRECTIONS.has(direction_to_open):
		printerr("Invalid direction to open: ", direction_to_open)
		return

	grid[cell_pos.y][cell_pos.x] &= ~direction_to_open

	var neighbor_pos = cell_pos + DIRECTIONS[direction_to_open]
	if _is_valid(neighbor_pos):
		grid[neighbor_pos.y][neighbor_pos.x] &= ~OPPOSITE[direction_to_open]
