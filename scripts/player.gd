extends CharacterBody2D
class_name Player

@export var max_speed: float = 150.0       # 最大移动速度
@export var acceleration: float = 800.0  # 加速度
@export var friction: float = 1000.0   # 摩擦力/减速度 (当没有输入时)
# const SPEED = 100.0 # 旧的，可以移除或保留作为参考
# const STOP_SPEED = 800.0 # 旧的，现在由 friction 代替

func _physics_process(delta: float) -> void:
	# 1. 获取输入方向
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Input.get_vector 已经返回归一化或零向量，所以不需要额外 normalize

	# 2. 计算目标速度和实际速度
	if input_direction != Vector2.ZERO:
		# 如果有输入，向输入方向加速
		# velocity = input_direction * max_speed # 这是瞬间达到最大速度
		velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
	else:
		# 如果没有输入，施加摩擦力使其减速停止
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# 3. 应用移动
	move_and_slide()
