class_name PlayerInputController
extends CharacterAbility
## Lee teclado/raton/mando y rellena la intencion del personaje. La direccion
## de la camara activa es a la vez la direccion de marcha y de apuntado (HFF).
## Debe ser el primer hijo del personaje.


func setup() -> void:
	character.add_to_group("player")


func physics_step(_delta: float) -> void:
	var c := character
	var cam := get_viewport().get_camera_3d()
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if cam:
		var yaw := cam.global_rotation.y
		c.facing_yaw = yaw
		c.aim_pitch = clampf(cam.global_rotation.x * 1.3 + 0.15, -1.35, 1.4)
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		var right := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
		c.move_input = (right * input.x + fwd * input.y).limit_length(1.0)
	else:
		c.move_input = Vector3(input.x, 0, -input.y).limit_length(1.0)
	c.want_grab[Side.LEFT] = Input.is_action_pressed("grab_left")
	c.want_grab[Side.RIGHT] = Input.is_action_pressed("grab_right")
	c.want_jump = Input.is_action_pressed("jump")
	c.want_limp = Input.is_action_pressed("go_limp")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or character == null:
		return
	if event.is_action_pressed("punch"):
		character.want_punch = true
	elif event.is_action_pressed("respawn"):
		character.respawn()
