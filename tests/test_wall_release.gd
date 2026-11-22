extends Node
## Prueba automatica: soltarse de la pared sin dejar de pulsar W.
## Saltar contra la cara trasera del muro alto (2,6 m, inalcanzable de un
## salto), agarrarse a la pared por debajo del borde, empujar
## hacia delante y soltar las manos manteniendo W. El personaje debe caer al
## suelo: no puede quedarse pegado a la pared por la friccion de los pies.


var arena: Node
var player: RagdollCharacter
var cam: OrbitCamera
var t := 0.0
var _steps: Array = []
var _done := false
var _release_y := 0.0


func _ready() -> void:
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	cam = arena.get_node("CameraRig")
	# detras del muro alto (cara trasera en z = -14.5), mirando hacia +Z
	player.set_spawn(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -15.3)))
	player.respawn()
	cam.yaw = PI
	_steps = [
		# 1) saltar hacia la pared pulsando W
		[1.0, func(): cam.pitch = 0.0],
		[1.5, func():
			Input.action_press("move_forward")
			Input.action_press("jump")],
		# 2) en el aire, agarrarse a la cara de la pared (por debajo del borde)
		[1.6, func():
			Input.action_release("jump")
			Input.action_press("grab_left")
			Input.action_press("grab_right")],
		[2.5, func():
			_assert("grab_wall_face", player.is_grabbing(0) or player.is_grabbing(1),
				"L=%s R=%s hand_y=%.2f" % [player.is_grabbing(0), player.is_grabbing(1), player.get_hand_position(0).y])],
		# 3) soltar las manos, SIN soltar W
		[3.5, func():
			Input.action_release("grab_left")
			Input.action_release("grab_right")
			_release_y = player.get_pelvis().global_position.y],
		# 4) la gravedad debe ganar: de pie en el suelo junto a la pared
		[5.5, func():
			var p := player.get_pelvis().global_position
			var feet_y := minf(player.bodies.shin_l.global_position.y, player.bodies.shin_r.global_position.y)
			_assert("falls_after_release", feet_y < 0.4 and p.y < 1.1,
				"pelvis_y=%.2f feet_y=%.2f release_pelvis_y=%.2f z=%.2f" % [p.y, feet_y, _release_y, p.z])
			var up := player.get_torso().global_basis.y.dot(Vector3.UP)
			_assert("stands_after_release", up > 0.85, "up=%.2f" % up)
			Input.action_release("move_forward")
			_done = true],
	]


func _physics_process(delta: float) -> void:
	t += delta
	if int(t * 120.0) % 30 == 0:
		var p := player.get_pelvis().global_position
		var feet_y := minf(player.bodies.shin_l.global_position.y, player.bodies.shin_r.global_position.y)
		print("METRIC t=%.2f pelvis=(%.2f, %.2f, %.2f) feet_y=%.2f grab=%s/%s grounded=%s climbing=%s" % [
			t, p.x, p.y, p.z, feet_y, player.is_grabbing(0), player.is_grabbing(1), player.grounded, player.climbing])
	while not _steps.is_empty() and t >= _steps[0][0]:
		(_steps.pop_front()[1] as Callable).call()
	if _done:
		get_tree().quit()


func _assert(name: String, cond: bool, info: String) -> void:
	print("ASSERT %s %s (%s)" % ["ok" if cond else "fail", name, info])
