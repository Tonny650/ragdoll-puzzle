class_name PlayerInputController
extends CharacterAbility
## Lee teclado/raton/mando y rellena la intencion del personaje. La direccion
## de la camara activa es a la vez la direccion de marcha y de apuntado (HFF).
## Debe ser el primer hijo del personaje. La lectura en si (`read_intent`) es
## estatica: la usa tambien el cliente en red para enviar su intencion.


func setup() -> void:
	character.add_to_group("player")
	character.is_local = true


func physics_step(_delta: float) -> void:
	read_intent(get_viewport().get_camera_3d()).apply_to(character)


## Intencion del jugador de este PC segun el teclado/mando y la camara `cam`.
static func read_intent(cam: Camera3D) -> NetIntent:
	var it := NetIntent.new()
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if cam:
		var yaw := cam.global_rotation.y
		it.yaw = yaw
		it.pitch = clampf(cam.global_rotation.x * 1.3 + 0.15, -1.35, 1.4)
		it.flags |= NetIntent.FLAG_HAS_VIEW
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		var right := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
		it.move = (right * input.x + fwd * input.y).limit_length(1.0)
	else:
		it.move = Vector3(input.x, 0, -input.y).limit_length(1.0)
	if Input.is_action_pressed("grab_left"):
		it.flags |= NetIntent.FLAG_GRAB_L
	if Input.is_action_pressed("grab_right"):
		it.flags |= NetIntent.FLAG_GRAB_R
	if Input.is_action_pressed("jump"):
		it.flags |= NetIntent.FLAG_JUMP
	if Input.is_action_pressed("go_limp"):
		it.flags |= NetIntent.FLAG_LIMP
	return it


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or character == null:
		return
	if event.is_action_pressed("punch"):
		character.want_punch = true
	elif event.is_action_pressed("respawn"):
		character.respawn()
