extends Node
## Prueba automatica del controlador ragdoll. Ejecutar headless:
##   godot --headless res://tests/test_ragdoll.tscn --quit-after 2400
## Imprime lineas "ASSERT ok/fail <nombre>" y "METRIC ...".

var arena: Node
var player: RagdollCharacter
var t := 0.0
var _steps: Array = []
var _mark := Vector3.ZERO
var _done := false
var _arm_dots := [[], []]


func _ready() -> void:
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	_steps = [
		[2.0, _check_standing.bind("stand_idle")],
		[2.0, func(): _mark = player.get_center(); Input.action_press("move_forward")],
		[4.5, func():
			Input.action_release("move_forward")
			var d := player.get_center() - _mark
			_assert("walk_forward", d.z < -3.0 and absf(d.x) < 1.5, "delta=%s" % d)],
		[6.5, _check_standing.bind("stand_after_walk")],
		[6.5, func(): _mark = player.get_center(); Input.action_press("jump")],
		[6.9, func():
			Input.action_release("jump")
			_assert("jump", player.get_center().y > _mark.y + 0.3, "dy=%.2f" % (player.get_center().y - _mark.y))],
		[8.5, _check_standing.bind("stand_after_jump")],
		[8.5, func(): player.knock_out(1.5)],
		[9.5, func(): _assert("ko_limp", player.strength == 0.0 and player.get_center().y < 0.8, "y=%.2f" % player.get_center().y)],
		[14.0, _check_standing.bind("recover_after_ko")],
		[14.0, func(): Input.action_press("grab_left"); Input.action_press("grab_right")],
		[15.0, func():
			# brazos apuntando a la mira: promedio de cos(angulo) en los ultimos 0,4 s
			var avg_l := _avg(_arm_dots[0])
			var avg_r := _avg(_arm_dots[1])
			_assert("arms_raise", avg_l > 0.9 and avg_r > 0.9,
				"avg_dotL=%.2f avg_dotR=%.2f min_dotL=%.2f min_dotR=%.2f" % [
				avg_l, avg_r, _arm_dots[0].min(), _arm_dots[1].min()])
			Input.action_release("grab_left"); Input.action_release("grab_right")],
		[17.0, _check_standing.bind("stand_final")],
		# --- agarrar y arrastrar la caja pesada ---
		[17.0, func():
			var crate: Node3D = arena.get_node("Props/HeavyCrate")
			player.set_spawn(Transform3D(Basis.IDENTITY, crate.global_position + Vector3(0, -0.45, 1.05)))
			player.respawn()
			arena.get_node("CameraRig").pitch = -0.75
			_mark = crate.global_position],
		[18.0, func(): Input.action_press("grab_left"); Input.action_press("grab_right")],
		[19.5, func():
			_assert("grab_crate", player.is_grabbing(0) or player.is_grabbing(1), "L=%s R=%s" % [player.is_grabbing(0), player.is_grabbing(1)])
			Input.action_press("move_back")],
		[21.5, func():
			Input.action_release("move_back")
			var crate: Node3D = arena.get_node("Props/HeavyCrate")
			_assert("drag_crate", crate.global_position.z - _mark.z > 0.6, "moved=%.2f" % (crate.global_position.z - _mark.z))
			Input.action_release("grab_left"); Input.action_release("grab_right")],
		[22.5, func(): _assert("release", not player.is_grabbing(0) and not player.is_grabbing(1), "")],
		[22.5, func(): _done = true],
	]


func _physics_process(delta: float) -> void:
	t += delta
	if int(t * 120.0) % 120 == 0:
		var c := player.get_center()
		print("METRIC t=%.1f pos=(%.2f, %.2f, %.2f) up=%.2f grounded=%s strength=%.2f" % [
			t, c.x, c.y, c.z, player.get_torso().global_basis.y.dot(Vector3.UP), player.grounded, player.strength])
	if t > 14.6 and t < 15.0:
		# muestras para la prueba arms_raise (promedio, no un solo fotograma)
		var aim := player.get_aim_direction()
		for side in 2:
			_arm_dots[side].append((-player.get_lower_arm(side).global_basis.y).dot(aim))
	while not _steps.is_empty() and t >= _steps[0][0]:
		(_steps.pop_front()[1] as Callable).call()
	if _done:
		get_tree().quit()


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _check_standing(name: String) -> void:
	var up := player.get_torso().global_basis.y.dot(Vector3.UP)
	var h := player.get_pelvis().global_position.y
	_assert(name, up > 0.85 and h > 0.7, "up=%.2f pelvis_y=%.2f" % [up, h])


func _assert(name: String, cond: bool, info: String) -> void:
	if cond:
		print("ASSERT ok %s (%s)" % [name, info])
	else:
		print("ASSERT fail %s: %s" % [name, info])
