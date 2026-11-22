extends Node
## Prueba automatica: soltar las manos a mitad del cruce del borde.
## Trepa la repisa de 1,5 m y, en cuanto la pelvis pasa por encima del borde,
## suelta las manos Y la W. El personaje debe terminar de subir y quedar de pie
## arriba con los dos pies apoyados (antes quedaba sentado en la arista con las
## piernas colgando, o de puntillas en el borde y acababa cayendo hacia atras).

const LEDGE_TOP := 1.5
const LEDGE_FRONT_Z := -8.5

var arena: Node
var player: RagdollCharacter
var cam: OrbitCamera
var t := 0.0
var _released_at := -1.0
var _steps: Array = []
var _done := false


func _ready() -> void:
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	cam = arena.get_node("CameraRig")
	player.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -7.3)))
	player.respawn()
	_steps = [
		[1.0, func():
			cam.pitch = 0.1
			Input.action_press("grab_left")
			Input.action_press("grab_right")],
		[1.6, func(): Input.action_press("move_forward")],
		[2.6, func(): cam.pitch = 0.6],
	]


func _physics_process(delta: float) -> void:
	t += delta
	var pel := player.get_pelvis().global_position
	if _released_at < 0.0 and pel.y > LEDGE_TOP + 0.3 and pel.z < LEDGE_FRONT_Z - 0.1:
		# pecho por encima del borde: soltar todo a mitad del cruce
		_released_at = t
		Input.action_release("grab_left")
		Input.action_release("grab_right")
		Input.action_release("move_forward")
		cam.pitch = -0.2
		print("METRIC release t=%.2f pelvis=%s" % [t, pel])
	if int(t * 120.0) % 60 == 0:
		print("METRIC t=%.1f pelvis=(%.2f, %.2f, %.2f) feet=%s/%s mantling=%s grounded=%s" % [
			t, pel.x, pel.y, pel.z, _foot_on_top(&"shin_l"), _foot_on_top(&"shin_r"), player.mantling, player.grounded])
	while not _steps.is_empty() and t >= _steps[0][0]:
		(_steps.pop_front()[1] as Callable).call()
	if _released_at > 0.0 and t > _released_at + 3.0 and not _done:
		_assert("released_mid_mantle", true, "t=%.2f" % _released_at)
		_assert("both_feet_on_top", _foot_on_top(&"shin_l") and _foot_on_top(&"shin_r"),
			"L=%s R=%s" % [player.get_foot_position(&"shin_l"), player.get_foot_position(&"shin_r")])
		var up := player.get_torso().global_basis.y.dot(Vector3.UP)
		_assert("standing_on_top", up > 0.85 and player.grounded and pel.y > LEDGE_TOP + 0.6,
			"up=%.2f grounded=%s pelvis=%s" % [up, player.grounded, pel])
		_done = true
	if t > 12.0 and not _done:
		_assert("released_mid_mantle", false, "nunca paso el borde")
		_done = true
	if _done:
		get_tree().quit()


## El pie esta arriba de la repisa, apoyado y por dentro del borde.
func _foot_on_top(shin: StringName) -> bool:
	var f := player.get_foot_position(shin)
	return f.y > LEDGE_TOP and f.y < LEDGE_TOP + 0.15 and f.z < LEDGE_FRONT_Z - 0.1


func _assert(name: String, cond: bool, info: String) -> void:
	print("ASSERT %s %s (%s)" % ["ok" if cond else "fail", name, info])
