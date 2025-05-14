extends Node2D

@onready var maze : Maze = $Maze
@onready var objects : TileMapLayer = $Objects
@onready var player : Player = $Player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#maze.find_and_draw_path()
	print(maze.is_maze_valid())
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
