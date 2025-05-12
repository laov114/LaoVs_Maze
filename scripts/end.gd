# End.gd
extends Area2D

# (可选) 定义一个信号，当玩家到达终点时发出，供其他节点（如Game节点）监听
signal player_reached_end

func _ready():
	# 连接 body_entered 信号到 _on_body_entered 方法
	# 确保 Area2D 节点上的 CollisionShape2D 是启用的
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	# 检查进入的 body 是否是玩家
	# 我们需要一种方法来识别玩家。有几种方式：
	# 1. 检查节点名称 (不太健壮，如果玩家节点改名就会失效)
	#    if body.name == "Player":
	# 2. 给玩家节点添加到一个组 (推荐)
	#    假设玩家节点在 "player" 组中
	# 3. 检查 body 是否是 Player 类的实例 (如果 Player 有自己的 class_name)
	#    if body is PlayerScript: # 假设 PlayerScript 是 Player 节点的脚本类名

	# 我们这里使用组的方式，假设 Player 节点已添加到 "player" 组
	if body.is_in_group("player"):
		print("Player reached the end!")
		
		# 发出信号，让 Game 节点或其他关心此事件的节点知道
		emit_signal("player_reached_end")
		
		# 执行结束游戏的逻辑
		end_game_action()

func end_game_action():
	# 这里可以放置任何你想要的结束游戏行为
	
	# 示例1: 简单地打印消息
	print("Game Over - Player Won!")
	
	# 示例2: 禁用玩家输入 (如果玩家脚本有相关方法)
	# get_tree().call_group("player", "disable_input") # 假设玩家脚本有 disable_input 方法

	# 示例3: 重新加载当前场景 (作为一种简单的“重玩”或“结束”方式)
	# 注意：如果这是你想要的，确保你有一个方式来真正退出或进入主菜单
	# get_tree().reload_current_scene()
	
	# 示例4: 退出游戏
	# get_tree().quit()

	# 示例5: 切换到一个专门的结束画面场景
	# 假设你有一个 "res://scenes/end_screen.tscn" 场景
	# get_tree().change_scene_to_file("res://scenes/end_screen.tscn")

	# 当前，为了简单起见，我们只打印并可能禁用玩家
	# 如果 Player 节点有 disable_movement 方法
	#if player_node and player_node.has_method("disable_movement"):
		#player_node.disable_movement() # 你需要在 Player 脚本中实现这个方法

	# 或者，如果 Player 节点是直接添加到场景树的，可以尝试直接禁用其处理
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(false) # 禁用物理处理
		player.set_process_input(false) # 禁用输入处理
