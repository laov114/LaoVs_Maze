@tool
class_name Maze
extends TileMapLayer

# --- 迷宫尺寸 ---
@export var maze_width: int = 10:
	set(value):
		maze_width = value
		if Engine.is_editor_hint(): _notify_maze_parameters_changed()
@export var maze_height: int = 8:
	set(value):
		maze_height = value
		if Engine.is_editor_hint(): _notify_maze_parameters_changed()

# --- 墙壁地形配置 (用于此 "Maze" 层) ---
@export_group("Wall Terrain (for 'Maze' Layer's TileSet)")
@export var wall_terrain_set_id: int = 0 
@export var wall_terrain_id: int = 0   

# --- "Objects" 层的引用和路径地形配置 ---
@export_group("Path Terrain (for 'Objects' Layer's TileSet)")
@export var objects_layer_node_path: NodePath:
	set(value):
		objects_layer_node_path = value
		if Engine.is_editor_hint() or (is_inside_tree() and get_tree() and not Engine.is_editor_hint()):
			_update_objects_layer_reference()
@export var path_terrain_set_on_objects_id: int = 1 
@export var path_terrain_on_objects_id: int = 0   

# --- 玩家节点的引用 ---
@export_group("Player Configuration (Runtime)")
@export var player_node_path: NodePath

# --- 编辑器操作按钮 ---
@export_group("") 
@export_tool_button("生成迷宫 (Generate Maze)")
var _button_generate_maze = _on_button_generate_maze_pressed

@export_tool_button("寻路并显示 (Find & Draw Path)")
var _button_find_path = _on_button_find_path_pressed

@export_tool_button("重置迷宫 (Reset Maze)")
var _button_reset_maze = _on_button_reset_maze_pressed

# --- 起点/终点对象图块标识 (在 Objects 层) ---
const START_OBJECT_SOURCE_ID: int = 1
const START_OBJECT_ATLAS_COORDS: Vector2i = Vector2i(0,0)
const START_OBJECT_ALTERNATIVE_TILE: int = 2

const END_OBJECT_SOURCE_ID: int = 1
const END_OBJECT_ATLAS_COORDS: Vector2i = Vector2i(0,0)
const END_OBJECT_ALTERNATIVE_TILE: int = 3

# --- 内部变量 ---
var generator: MazeGenerator = MazeGenerator.new()
var astar_grid: AStarGrid2D = AStarGrid2D.new()

var objects_tilemap_layer: TileMapLayer 
var player_node: CharacterBody2D        

var entry_maze_cell: Vector2i = Vector2i(0, 0) 
var exit_maze_cell: Vector2i                 
var wall_tilemap_coords: Array[Vector2i] = [] 

var _undo_redo_manager_instance: EditorUndoRedoManager 


func _get_editor_undo_redo() -> EditorUndoRedoManager:
	if not Engine.is_editor_hint():
		return null 
	if not _undo_redo_manager_instance:
		var editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface:
			_undo_redo_manager_instance = editor_interface.get_editor_undo_redo() # 使用 get_editor_undo_redo
		else:
			printerr("Failed to get EditorInterface singleton.")
			return null
	if not _undo_redo_manager_instance:
		printerr("Failed to get EditorUndoRedoManager from EditorInterface.")
	return _undo_redo_manager_instance


func _update_objects_layer_reference():
	if objects_layer_node_path and not objects_layer_node_path.is_empty():
		if not is_inside_tree() and Engine.is_editor_hint(): 
			objects_tilemap_layer = null 
			return
		var node_found = get_node_or_null(objects_layer_node_path)
		if node_found is TileMapLayer:
			objects_tilemap_layer = node_found
		else:
			objects_tilemap_layer = null
			if objects_layer_node_path and not objects_layer_node_path.is_empty(): 
				var context = "Editor" if Engine.is_editor_hint() else "Runtime"
				printerr(context, ": Node at path '", objects_layer_node_path, "' is not a TileMapLayer or not found.")
	else:
		objects_tilemap_layer = null


func _ready():
	_update_objects_layer_reference() 
	
	if not Engine.is_editor_hint(): # --- 运行时逻辑 ---
		var valid_config = true
		if not tile_set: 
			printerr("RUNTIME ERROR: 'Maze' TileMapLayer needs a TileSet for wall terrain.")
			valid_config = false
		if valid_config and (wall_terrain_set_id < 0 or wall_terrain_set_id >= tile_set.get_terrain_sets_count() or \
		   wall_terrain_id < 0 or wall_terrain_id >= tile_set.get_terrains_count(wall_terrain_set_id)):
			printerr("RUNTIME ERROR: Invalid wall terrain configuration for 'Maze' layer.")
			valid_config = false
		
		if objects_tilemap_layer and objects_tilemap_layer.tile_set:
			if path_terrain_set_on_objects_id < 0 or path_terrain_set_on_objects_id >= objects_tilemap_layer.tile_set.get_terrain_sets_count() or \
			   path_terrain_on_objects_id < 0 or path_terrain_on_objects_id >= objects_tilemap_layer.tile_set.get_terrains_count(path_terrain_set_on_objects_id):
				printerr("RUNTIME ERROR: Invalid path terrain configuration for 'Objects' layer.")
		elif objects_layer_node_path and not objects_layer_node_path.is_empty() and not objects_tilemap_layer:
			printerr("RUNTIME ERROR: Objects layer specified but not found or invalid.")

		if not valid_config: return 

		var current_maze_width = max(1, maze_width)
		var current_maze_height = max(1, maze_height)

		# --- 运行时检查并设置起点和终点 ---
		var found_entry = false
		var found_exit = false
		if objects_tilemap_layer:
			var used_cells_in_objects = objects_tilemap_layer.get_used_cells()
			for cell_tm_coord in used_cells_in_objects:
				var source_id = objects_tilemap_layer.get_cell_source_id(cell_tm_coord)
				var atlas_coords = objects_tilemap_layer.get_cell_atlas_coords(cell_tm_coord)
				var alt_tile = objects_tilemap_layer.get_cell_alternative_tile(cell_tm_coord)
				if not found_entry and source_id == START_OBJECT_SOURCE_ID and atlas_coords == START_OBJECT_ATLAS_COORDS and alt_tile == START_OBJECT_ALTERNATIVE_TILE:
					if cell_tm_coord.x % 2 == 1 and cell_tm_coord.y % 2 == 1:
						var logical_x = (cell_tm_coord.x - 1) / 2; var logical_y = (cell_tm_coord.y - 1) / 2
						if logical_x >= 0 && logical_x < current_maze_width && logical_y >= 0 && logical_y < current_maze_height:
							entry_maze_cell = Vector2i(logical_x, logical_y); found_entry = true
							print("Runtime: Found existing entry at logical: ", entry_maze_cell)
				elif not found_exit and source_id == END_OBJECT_SOURCE_ID and atlas_coords == END_OBJECT_ATLAS_COORDS and alt_tile == END_OBJECT_ALTERNATIVE_TILE:
					if cell_tm_coord.x % 2 == 1 and cell_tm_coord.y % 2 == 1:
						var logical_x = (cell_tm_coord.x - 1) / 2; var logical_y = (cell_tm_coord.y - 1) / 2
						if logical_x >= 0 && logical_x < current_maze_width && logical_y >= 0 && logical_y < current_maze_height:
							exit_maze_cell = Vector2i(logical_x, logical_y); found_exit = true
							print("Runtime: Found existing exit at logical: ", exit_maze_cell)
				if found_entry and found_exit: break
		else: print("Runtime: Objects layer not available to check for existing start/end points.")

		if not found_entry:
			entry_maze_cell = Vector2i(randi_range(0, current_maze_width - 1), randi_range(0, current_maze_height - 1))
			print("Runtime: No entry found, generated random entry at logical: ", entry_maze_cell)
		
		var assigned_exit_reason = ""
		if not found_exit: assigned_exit_reason = "No exit found"
		elif entry_maze_cell == exit_maze_cell and (current_maze_width > 1 or current_maze_height > 1): assigned_exit_reason = "Exit was same as entry"
		
		if not assigned_exit_reason.is_empty():
			var attempts = 0
			while attempts < 100 : 
				exit_maze_cell = Vector2i(randi_range(0, current_maze_width - 1), randi_range(0, current_maze_height - 1))
				if entry_maze_cell != exit_maze_cell: break
				attempts += 1
			if entry_maze_cell == exit_maze_cell and (current_maze_width > 1 or current_maze_height > 1):
				printerr("Runtime: Could not generate a unique random exit point after 100 attempts.")
				if current_maze_width > 1 : exit_maze_cell.x = (entry_maze_cell.x + 1) % current_maze_width
				elif current_maze_height > 1 : exit_maze_cell.y = (entry_maze_cell.y + 1) % current_maze_height
			print("Runtime: ", assigned_exit_reason, ", generated random exit at logical: ", exit_maze_cell)
		else: # found_exit was true and different from entry (or maze is 1x1)
			exit_maze_cell = exit_maze_cell # Ensure it's set if found
		# --- End of start/end point determination ---

		if player_node_path and not player_node_path.is_empty():
			player_node = get_node_or_null(player_node_path) as CharacterBody2D
			if not player_node: printerr("RUNTIME ERROR: Could not find 'Player' at path: ", player_node_path)
			elif player_node: player_node.hide()
		
		if get_used_cells().size() > 0:
			print("Maze already has content, attempting to use existing structure (runtime).")
			_recalculate_wall_coords_from_tiles() 
			if objects_tilemap_layer: 
				objects_tilemap_layer.clear() 
				place_initial_start_and_end_objects() 
		else:
			print("Maze is empty, generating new maze in _ready (runtime).")
			_perform_generate_maze_base() 
		
		if player_node: position_and_show_player()


func _notify_maze_parameters_changed():
	if Engine.is_editor_hint(): print("Maze dimensions changed. Press 'Generate Maze' to update.")

# --- 按钮回调函数 ---
func _on_button_generate_maze_pressed():
	if not Engine.is_editor_hint(): print("Button for editor use."); return
	_update_objects_layer_reference()
	var ur = _get_editor_undo_redo()
	if not ur: 
		printerr("UndoRedoManager not available. Performing action without undo.")
		_perform_generate_maze_base_and_notify()
		return
	var old_self_tile_data = get_tile_map_data_as_array()
	var old_objects_tile_data = PackedByteArray()
	var objects_layer_ref = objects_tilemap_layer 
	if objects_layer_ref: old_objects_tile_data = objects_layer_ref.get_tile_map_data_as_array()
	var context_node = self if is_inside_tree() else get_tree().get_edited_scene_root() if get_tree() else self
	ur.create_action("Generate Maze", UndoRedo.MERGE_DISABLE, context_node) 
	ur.add_do_method(self, "_perform_generate_maze_base_and_notify")
	ur.add_undo_method(self, "_restore_maze_state_wrapper", old_self_tile_data, objects_layer_ref, old_objects_tile_data)
	ur.commit_action(true)

func _on_button_find_path_pressed():
	if not Engine.is_editor_hint(): print("Button for editor use."); return
	_update_objects_layer_reference()
	if not objects_tilemap_layer: printerr("Objects layer not set. Cannot find/draw path."); return
	var ur = _get_editor_undo_redo()
	if not ur: 
		printerr("UndoRedoManager N/A. Performing action without undo.")
		_perform_find_and_draw_path_and_notify()
		return
	var old_objects_tile_data = objects_tilemap_layer.get_tile_map_data_as_array()
	var context_node = self if is_inside_tree() else get_tree().get_edited_scene_root() if get_tree() else self
	ur.create_action("Find and Draw Path", UndoRedo.MERGE_DISABLE, context_node)
	ur.add_do_method(self, "_perform_find_and_draw_path_and_notify")
	ur.add_undo_method(self, "_restore_single_layer_state_wrapper", objects_tilemap_layer, old_objects_tile_data)
	ur.commit_action(true)

func _on_button_reset_maze_pressed():
	if not Engine.is_editor_hint(): print("Button for editor use."); return
	_update_objects_layer_reference()
	var ur = _get_editor_undo_redo()
	if not ur: 
		printerr("UndoRedoManager N/A. Performing action without undo.")
		_clear_all_maze_visuals_and_notify()
		return
	var old_self_tile_data = get_tile_map_data_as_array()
	var old_objects_tile_data = PackedByteArray()
	var objects_layer_ref = objects_tilemap_layer
	if objects_layer_ref: old_objects_tile_data = objects_layer_ref.get_tile_map_data_as_array()
	var context_node = self if is_inside_tree() else get_tree().get_edited_scene_root() if get_tree() else self
	ur.create_action("Reset Maze", UndoRedo.MERGE_DISABLE, context_node)
	ur.add_do_method(self, "_clear_all_maze_visuals_and_notify")
	ur.add_undo_method(self, "_restore_maze_state_wrapper", old_self_tile_data, objects_layer_ref, old_objects_tile_data)
	ur.commit_action(true)

# --- 执行操作并通知的方法 ---
func _perform_generate_maze_base_and_notify():
	_perform_generate_maze_base()
	if Engine.is_editor_hint(): _notify_all_property_lists_changed()

func _perform_find_and_draw_path_and_notify():
	_perform_find_and_draw_path()
	if Engine.is_editor_hint(): _notify_all_property_lists_changed() 

func _clear_all_maze_visuals_and_notify():
	_clear_all_maze_visuals()
	if Engine.is_editor_hint(): _notify_all_property_lists_changed()

# --- 包装撤销方法 ---
func _restore_maze_state_wrapper(maze_data: PackedByteArray, obj_layer_maybe: Object, obj_data: PackedByteArray):
	set_tile_map_data_from_array(maze_data)
	if obj_layer_maybe is TileMapLayer:
		var obj_layer: TileMapLayer = obj_layer_maybe as TileMapLayer
		if obj_data != null and obj_data.size() > 0: 
			obj_layer.set_tile_map_data_from_array(obj_data)
		elif obj_layer: 
			obj_layer.clear()
	if Engine.is_editor_hint(): _notify_all_property_lists_changed()
	print("Undo/Redo: Maze state restored.")

func _restore_single_layer_state_wrapper(layer: TileMapLayer, data: PackedByteArray):
	if layer and data != null: 
		layer.set_tile_map_data_from_array(data)
		if Engine.is_editor_hint(): layer.notify_property_list_changed()
		print("Undo/Redo: Layer state restored for: ", layer.name)

func _notify_all_property_lists_changed(): 
	if Engine.is_editor_hint():
		notify_property_list_changed() 
		if objects_tilemap_layer and is_instance_valid(objects_tilemap_layer):
			objects_tilemap_layer.notify_property_list_changed() 

# --- 核心逻辑函数 ---
func _perform_generate_maze_base():
	_update_objects_layer_reference() 
	var current_maze_width = max(1, maze_width)
	var current_maze_height = max(1, maze_height)
	# exit_maze_cell 应该已经在 _ready (运行时) 或编辑器生成前 (如果需要) 被设置
	# 为确保编辑器按钮生成时 exit_maze_cell 是基于当前 maze_width/height，这里也更新一下
	if Engine.is_editor_hint():
		exit_maze_cell = Vector2i(current_maze_width - 1, current_maze_height - 1)

	generator.initialize_grid(current_maze_width, current_maze_height)
	generator.generate_dfs(entry_maze_cell) # 使用当前 entry_maze_cell
	draw_maze_walls_and_collect_coords()
	if objects_tilemap_layer: 
		objects_tilemap_layer.clear() 
		place_initial_start_and_end_objects() # 使用当前 entry/exit_maze_cell
	if Engine.is_editor_hint(): print("Maze generated.")

func _perform_find_and_draw_path():
	if not objects_tilemap_layer: printerr("Find Path: Objects layer N/A."); return
	if wall_tilemap_coords.is_empty() and (maze_width > 0 and maze_height > 0):
		printerr("Find Path: Walls N/A. Generate maze first."); return
	var path_on_tilemap: Array[Vector2i] = setup_astar_and_find_path_on_tilemap()
	objects_tilemap_layer.clear() 
	place_initial_start_and_end_objects() 
	if not path_on_tilemap.is_empty():
		objects_tilemap_layer.set_cells_terrain_path(path_on_tilemap, path_terrain_set_on_objects_id, path_terrain_on_objects_id, true)
		var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
		var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
		objects_tilemap_layer.set_cell(start_tm_coord, 1, Vector2i(0,0), 2) 
		objects_tilemap_layer.set_cell(end_tm_coord, 1, Vector2i(0,0), 3) 
	else:
		var err_msg = "寻路失败：从起点 (" + str(entry_maze_cell) + ") 到终点 (" + str(exit_maze_cell) + ") 在迷宫内部没有可连接的路径！"
		if Engine.is_editor_hint(): push_error(err_msg)
		else: print(err_msg)
	if Engine.is_editor_hint(): print("Pathfinding executed.")

func _clear_all_maze_visuals():
	clear() 
	if objects_tilemap_layer: objects_tilemap_layer.clear() 
	wall_tilemap_coords.clear()
	if Engine.is_editor_hint(): print("Maze visuals cleared.")

# --- 公共方法：检查迷宫合法性 (与上一版本相同) ---
func is_maze_valid() -> bool:
	var current_maze_width = max(1, maze_width); var current_maze_height = max(1, maze_height)
	var tm_total_width = current_maze_width * 2 + 1; var tm_total_height = current_maze_height * 2 + 1
	if wall_tilemap_coords.is_empty() and get_used_cells().size() > 0: _recalculate_wall_coords_from_tiles()
	if not (entry_maze_cell.x >= 0 && entry_maze_cell.x < current_maze_width && entry_maze_cell.y >= 0 && entry_maze_cell.y < current_maze_height):
		printerr("Validation Error: Entry cell outside logical bounds."); return false
	if not (exit_maze_cell.x >= 0 && exit_maze_cell.x < current_maze_width && exit_maze_cell.y >= 0 && exit_maze_cell.y < current_maze_height):
		printerr("Validation Error: Exit cell outside logical bounds."); return false
	var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
	if wall_tilemap_coords.has(start_tm_coord): printerr("Validation Error: Start TM coord is wall."); return false
	if wall_tilemap_coords.has(end_tm_coord): printerr("Validation Error: End TM coord is wall."); return false
	for tx in range(tm_total_width):
		if not wall_tilemap_coords.has(Vector2i(tx, 0)): printerr("Validation Error: Top border not walled at x=", tx); return false
		if not wall_tilemap_coords.has(Vector2i(tx, tm_total_height - 1)): printerr("Validation Error: Bottom border not walled at x=", tx); return false
	for ty in range(1, tm_total_height - 1):
		if not wall_tilemap_coords.has(Vector2i(0, ty)): printerr("Validation Error: Left border not walled at y=", ty); return false
		if not wall_tilemap_coords.has(Vector2i(tm_total_width - 1, ty)): printerr("Validation Error: Right border not walled at y=", ty); return false
	var temp_astar_grid = AStarGrid2D.new(); temp_astar_grid.region = Rect2i(0, 0, tm_total_width, tm_total_height)
	temp_astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER; temp_astar_grid.update()
	for wall_coord in wall_tilemap_coords:
		if temp_astar_grid.is_in_boundsv(wall_coord): temp_astar_grid.set_point_solid(wall_coord, true)
	if temp_astar_grid.is_in_boundsv(start_tm_coord) && temp_astar_grid.is_point_solid(start_tm_coord): temp_astar_grid.set_point_solid(start_tm_coord, false) 
	if temp_astar_grid.is_in_boundsv(end_tm_coord) && temp_astar_grid.is_point_solid(end_tm_coord): temp_astar_grid.set_point_solid(end_tm_coord, false)
	if not temp_astar_grid.is_in_boundsv(start_tm_coord) or not temp_astar_grid.is_in_boundsv(end_tm_coord):
		printerr("Validation Error: A* Start/End TM coord out of bounds for path check."); return false
	var path: Array[Vector2i] = temp_astar_grid.get_id_path(start_tm_coord, end_tm_coord)
	if path.is_empty(): printerr("Validation Error: No path found between start and end."); return false
	print("Maze validation successful."); return true

func _recalculate_wall_coords_from_tiles(): # 辅助方法
	wall_tilemap_coords.clear()
	var tm_total_width = max(1, maze_width) * 2 + 1; var tm_total_height = max(1, maze_height) * 2 + 1
	for ty in range(tm_total_height):
		for tx in range(tm_total_width):
			var cell_pos = Vector2i(tx,ty)
			if get_cell_source_id(cell_pos) != -1: wall_tilemap_coords.append(cell_pos)

# --- 迷宫绘制和A*逻辑 (这些函数现在是内部实现细节) ---
func place_initial_start_and_end_objects():
	# ... (与上一版本相同)
	if not objects_tilemap_layer: return
	var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	objects_tilemap_layer.set_cell(start_tm_coord, 1, Vector2i(0,0), 2) 
	var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
	objects_tilemap_layer.set_cell(end_tm_coord, 1, Vector2i(0,0), 3) 

func draw_maze_walls_and_collect_coords():
	# ... (与上一版本相同)
	if generator.grid.is_empty() or not tile_set: return
	clear() 
	wall_tilemap_coords.clear()
	var current_maze_width = max(1, maze_width); var current_maze_height = max(1, maze_height)
	var tm_total_width = current_maze_width * 2 + 1; var tm_total_height = current_maze_height * 2 + 1
	var floor_tm_coords: Dictionary = {} 
	for my in range(current_maze_height):
		for mx in range(current_maze_width):
			floor_tm_coords[Vector2i(mx * 2 + 1, my * 2 + 1)] = true
	for my in range(current_maze_height):
		for mx in range(current_maze_width):
			var cell_data = generator.grid[my][mx] 
			var current_center_tm_coord = Vector2i(mx * 2 + 1, my * 2 + 1)
			if not (cell_data & MazeGenerator.E):
				if mx + 1 < current_maze_width: floor_tm_coords[Vector2i(current_center_tm_coord.x + 1, current_center_tm_coord.y)] = true
			if not (cell_data & MazeGenerator.S):
				if my + 1 < current_maze_height: floor_tm_coords[Vector2i(current_center_tm_coord.x, current_center_tm_coord.y + 1)] = true
	for ty in range(tm_total_height):
		for tx in range(tm_total_width):
			var current_tm_pos = Vector2i(tx, ty)
			if not floor_tm_coords.has(current_tm_pos): wall_tilemap_coords.append(current_tm_pos)
	if not wall_tilemap_coords.is_empty():
		set_cells_terrain_connect(wall_tilemap_coords, wall_terrain_set_id, wall_terrain_id, true)

func setup_astar_and_find_path_on_tilemap() -> Array[Vector2i]:
	# ... (与上一版本相同)
	var current_maze_width = max(1, maze_width); var current_maze_height = max(1, maze_height)
	var tm_total_width = current_maze_width * 2 + 1; var tm_total_height = current_maze_height * 2 + 1
	astar_grid.clear(); astar_grid.region = Rect2i(0, 0, tm_total_width, tm_total_height)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER; astar_grid.update() 
	for wall_coord in wall_tilemap_coords:
		if astar_grid.is_in_boundsv(wall_coord): astar_grid.set_point_solid(wall_coord, true)
	var start_tm_coord = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	var end_tm_coord = Vector2i(exit_maze_cell.x * 2 + 1, exit_maze_cell.y * 2 + 1)
	if astar_grid.is_in_boundsv(start_tm_coord) && astar_grid.is_point_solid(start_tm_coord): astar_grid.set_point_solid(start_tm_coord, false) 
	if astar_grid.is_in_boundsv(end_tm_coord) && astar_grid.is_point_solid(end_tm_coord): astar_grid.set_point_solid(end_tm_coord, false)
	if not astar_grid.is_in_boundsv(start_tm_coord) or not astar_grid.is_in_boundsv(end_tm_coord):
		printerr("A* Start or End TileMap coordinate is out of A* bounds."); return []
	var path: Array[Vector2i] = astar_grid.get_id_path(start_tm_coord, end_tm_coord)
	if path.is_empty(): print("A* No path found on TileMap from ", start_tm_coord, " to ", end_tm_coord)
	return path

func position_and_show_player():
	if Engine.is_editor_hint() or not player_node : return 
	var start_map_pos_on_maze_layer = Vector2i(entry_maze_cell.x * 2 + 1, entry_maze_cell.y * 2 + 1)
	var start_local_pos_on_maze_node = map_to_local(start_map_pos_on_maze_layer) 
	var player_target_pos_in_game_coords = position + start_local_pos_on_maze_node 
	player_node.position = player_target_pos_in_game_coords
	player_node.show()
