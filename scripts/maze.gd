# MazeTileMap.gd
# (附加到 "Maze" TileMapLayer 节点)
extends TileMapLayer
class_name Maze

# --- 迷宫尺寸 ---
@export var maze_width: int = 10
@export var maze_height: int = 8

# --- 墙壁地形配置 (用于此 "Maze" 层) ---
@export_group("Wall Terrain (for 'Maze' Layer's TileSet)")
@export var wall_terrain_set_id: int = 0 
@export var wall_terrain_id: int = 0   

# --- "Objects" 层的引用和路径地形配置 ---
@export_group("Path Terrain (for 'Objects' Layer's TileSet)")
@export var objects_layer_node_path: NodePath
@export var path_terrain_set_on_objects_id: int = 1 
@export var path_terrain_on_objects_id: int = 0   

# --- 玩家节点的引用 ---
@export_group("Player Configuration")
@export var player_node_path: NodePath

# --- 内部变量 ---
var generator: MazeGenerator = MazeGenerator.new()
var astar_grid: AStarGrid2D = AStarGrid2D.new()

var objects_tilemap_layer: TileMapLayer 
var player_node: CharacterBody2D        

var entry_maze_cell: Vector2i = Vector2i(0, 0) 
var exit_maze_cell: Vector2i                 
var wall_tilemap_coords: Array[Vector2i] = [] 


func _ready():
	# 1. 检查此 "Maze" 层的 TileSet 和墙壁地形配置
	if not tile_set: 
		printerr("CRITICAL ERROR: 'Maze' TileMapLayer needs a TileSet assigned for wall terrain.")
		set_process(false)
		return
	if wall_terrain_set_id < 0 or wall_terrain_set_id >= tile_set.get_terrain_sets_count():
		printerr("CRITICAL ERROR: Exported 'wall_terrain_set_id' (", wall_terrain_set_id, ") is invalid for 'Maze' layer's TileSet.")
		printerr("Number of terrain sets in 'Maze' TileSet: ", tile_set.get_terrain_sets_count())
		set_process(false)
		return
	if wall_terrain_id < 0 or wall_terrain_id >= tile_set.get_terrains_count(wall_terrain_set_id):
		printerr("CRITICAL ERROR: Exported 'wall_terrain_id' (", wall_terrain_id, ") is invalid for 'Maze' layer's TileSet at terrain set ", wall_terrain_set_id,".")
		printerr("Number of terrains in set ", wall_terrain_set_id, ": ", tile_set.get_terrains_count(wall_terrain_set_id))
		set_process(false)
		return

	# 2. 获取并检查 "Objects" 层及其 TileSet 和路径地形配置
	if objects_layer_node_path.is_empty():
		printerr("Error: 'Objects Layer Node Path' (for path terrain) not set in Inspector.")
	else:
		objects_tilemap_layer = get_node_or_null(objects_layer_node_path) as TileMapLayer
		if not objects_tilemap_layer:
			printerr("Error: Could not find 'Objects' TileMapLayer at path: ", objects_layer_node_path)
		else:
			if not objects_tilemap_layer.tile_set:
				printerr("CRITICAL ERROR: The 'Objects' TileMapLayer needs a TileSet assigned for path terrain.")
				objects_tilemap_layer = null 
			elif path_terrain_set_on_objects_id < 0 or path_terrain_set_on_objects_id >= objects_tilemap_layer.tile_set.get_terrain_sets_count():
				printerr("CRITICAL ERROR: Exported 'path_terrain_set_on_objects_id' (", path_terrain_set_on_objects_id, ") is invalid for 'Objects' layer's TileSet.")
				printerr("Number of terrain sets in 'Objects' TileSet: ", objects_tilemap_layer.tile_set.get_terrain_sets_count())
				objects_tilemap_layer = null 
			elif path_terrain_on_objects_id < 0 or path_terrain_on_objects_id >= objects_tilemap_layer.tile_set.get_terrains_count(path_terrain_set_on_objects_id):
				printerr("CRITICAL ERROR: Exported 'path_terrain_on_objects_id' (", path_terrain_on_objects_id, ") is invalid for 'Objects' layer's TileSet at terrain set ", path_terrain_set_on_objects_id,".")
				printerr("Number of terrains in set ", path_terrain_set_on_objects_id, ": ", objects_tilemap_layer.tile_set.get_terrains_count(path_terrain_set_on_objects_id))
				objects_tilemap_layer = null 
	
	# 3. 获取 "Player" 节点的引用
	if player_node_path.is_empty():
		printerr("Error: 'Player Node Path' not set in Inspector.")
	else:
		player_node = get_node_or_null(player_node_path) as CharacterBody2D
		if not player_node:
			printerr("Error: Could not find 'Player' (CharacterBody2D) at path: ", player_node_path)
		elif player_node: 
			player_node.hide()

	# 4. 初始化迷宫逻辑尺寸和终点
	var current_maze_width = max(1, maze_width)
	var current_maze_height = max(1, maze_height)
	exit_maze_cell = Vector2i(current_maze_width - 1, current_maze_height - 1)
	
	# 5. 生成并绘制迷宫基础（不包含路径）
	generate_and_draw_maze_base()


func generate_and_draw_maze_base():
	var current_maze_width = max(1, maze_width)
	var current_maze_height = max(1, maze_height)

	generator.initialize_grid(current_maze_width, current_maze_height)
	generator.generate_dfs(entry_maze_cell) 

	# 不再调用 generator.open_wall_at()。迷宫边界将由 draw_maze_walls_and_collect_coords 决定。

	draw_maze_walls_and_collect_coords() 

	if objects_tilemap_layer: 
		place_initial_start_and_end_objects()
	# else: # 错误已在 _ready 中打印
		# printerr("Skipping initial object placement: 'Objects' layer reference is invalid.")
		
	if player_node: 
		position_and_show_player()
	# else: # 错误已在 _ready 中打印
		# printerr("Skipping player positioning: 'Player' node reference is invalid.")


# --- 公共方法：手动触发寻路和路径绘制 ---
func find_and_draw_path():
	if not objects_tilemap_layer: # objects_tilemap_layer 的有效性已在 _ready 中检查
		printerr("Cannot find/draw path: 'Objects' layer reference is invalid (check _ready logs for details).")
		return
	if wall_tilemap_coords.is_empty() and (maze_width > 0 and maze_height > 0) : 
		printerr("Cannot find/draw path: Wall coordinates not collected. Ensure generate_and_draw_maze_base() was called or check logic.")
		return

	var path_on_tilemap: Array[Vector2i] = setup_astar_and_find_path_on_tilemap()
	
	objects_tilemap_layer.clear() # 清除旧路径和旧的起点/终点
	place_initial_start_and_end_objects() # 重新放置起点终点，它们可能被 clear() 移除

	if not path_on_tilemap.is_empty():
		objects_tilemap_layer.set_cells_terrain_path(
			path_on_tilemap,
			path_terrain_set_on_objects_id, # 使用为 Objects 层路径配置的导出变量
			path_terrain_on_objects_id,   # 使用为 Objects 层路径配置的导出变量
			true
		)
		# 在路径绘制后，再次强制绘制起点和终点图块，确保它们在最上层
		var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
		var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
		
		objects_tilemap_layer.set_cell(start_tm_coord, 1, Vector2i(0,0), 2) # 起点图块信息
		objects_tilemap_layer.set_cell(end_tm_coord, 1, Vector2i(0,0), 3)   # 终点图块信息
	else:
		# 如果没有路径，可以选择抛出错误或执行其他逻辑
		push_error("寻路失败：从起点 (" + str(entry_maze_cell) + ") 到终点 (" + str(exit_maze_cell) + ") 在迷宫内部没有可连接的路径！")


func place_initial_start_and_end_objects():
	if not objects_tilemap_layer: return

	var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	objects_tilemap_layer.set_cell(start_tm_coord, 1, Vector2i(0,0), 2) # 起点图块信息

	var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
	objects_tilemap_layer.set_cell(end_tm_coord, 1, Vector2i(0,0), 3)   # 终点图块信息


func draw_maze_walls_and_collect_coords():
	if generator.grid.is_empty() or not tile_set: 
		return

	clear() 
	wall_tilemap_coords.clear()

	var current_maze_width = max(1, maze_width)
	var current_maze_height = max(1, maze_height)
	var tm_total_width = current_maze_width * 2 + 1
	var tm_total_height = current_maze_height * 2 + 1
	
	var floor_tm_coords: Dictionary = {} 

	# 1. 添加所有逻辑迷宫单元格的中心点为地板
	for my in range(current_maze_height):
		for mx in range(current_maze_width):
			var center_tm_coord = Vector2i(mx * 2 + 1, my * 2 + 1)
			floor_tm_coords[center_tm_coord] = true

	# 2. 添加逻辑迷宫单元格之间开放的连接为地板 (基于未经修改的 generator.grid)
	for my in range(current_maze_height):
		for mx in range(current_maze_width):
			var cell_data = generator.grid[my][mx] 
			var current_center_tm_coord = Vector2i(mx * 2 + 1, my * 2 + 1)

			# 向东连接
			if not (cell_data & MazeGenerator.E): # 如果东边没有墙
				if mx + 1 < current_maze_width: # 确保右边邻居在逻辑界内
					var east_connection_tm_coord = Vector2i(current_center_tm_coord.x + 1, current_center_tm_coord.y)
					floor_tm_coords[east_connection_tm_coord] = true
			
			# 向南连接
			if not (cell_data & MazeGenerator.S): # 如果南边没有墙
				if my + 1 < current_maze_height: # 确保下方邻居在逻辑界内
					var south_connection_tm_coord = Vector2i(current_center_tm_coord.x, current_center_tm_coord.y + 1)
					floor_tm_coords[south_connection_tm_coord] = true
	
	# 3. 确定墙壁：所有不在 floor_tm_coords 中的 TileMapLayer 单元格都是墙
	for ty in range(tm_total_height):
		for tx in range(tm_total_width):
			var current_tm_pos = Vector2i(tx, ty)
			if not floor_tm_coords.has(current_tm_pos):
				wall_tilemap_coords.append(current_tm_pos)

	# 4. 应用墙壁地形
	if not wall_tilemap_coords.is_empty():
		set_cells_terrain_connect(
			wall_tilemap_coords,
			wall_terrain_set_id, # 使用为 "Maze" 层墙壁配置的导出变量     
			wall_terrain_id,     # 使用为 "Maze" 层墙壁配置的导出变量     
			true
		)

func setup_astar_and_find_path_on_tilemap() -> Array[Vector2i]:
	var current_maze_width = max(1, maze_width)
	var current_maze_height = max(1, maze_height)
	var tm_total_width = current_maze_width * 2 + 1
	var tm_total_height = current_maze_height * 2 + 1

	astar_grid.clear()
	astar_grid.region = Rect2i(0, 0, tm_total_width, tm_total_height)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update() 

	for wall_coord in wall_tilemap_coords:
		if astar_grid.is_in_boundsv(wall_coord): 
			astar_grid.set_point_solid(wall_coord, true)

	var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)

	# 确保起点和终点在 A* 中是可通行的 (它们应该是地板中心)
	if astar_grid.is_in_boundsv(start_tm_coord) and astar_grid.is_point_solid(start_tm_coord):
		astar_grid.set_point_solid(start_tm_coord, false) 
	if astar_grid.is_in_boundsv(end_tm_coord) and astar_grid.is_point_solid(end_tm_coord):
		astar_grid.set_point_solid(end_tm_coord, false)

	if not astar_grid.is_in_boundsv(start_tm_coord) or not astar_grid.is_in_boundsv(end_tm_coord):
		printerr("A* Start or End TileMap coordinate is out of A* bounds.")
		return []

	var path: Array[Vector2i] = astar_grid.get_id_path(start_tm_coord, end_tm_coord)
	if path.is_empty():
		print("A* No path found on TileMap from ", start_tm_coord, " to ", end_tm_coord)
		
	return path


func position_and_show_player():
	if not player_node: return
	var start_map_pos_on_maze_layer = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	var start_local_pos_on_maze_node = map_to_local(start_map_pos_on_maze_layer) 
	var player_target_pos_in_game_coords = position + start_local_pos_on_maze_node 
	player_node.position = player_target_pos_in_game_coords
	player_node.show()
