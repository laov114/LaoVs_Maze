extends CharacterBody2D
class_name Player

const SPEED = 100.0
const STOP_SPEED = 800.0


func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, STOP_SPEED * delta)

	move_and_slide()
