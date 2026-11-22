extends Node
## Prueba automatica: trepar la repisa de 1,5 m (Level/ClimbLedge).
## Secuencia estilo Human Fall Flat: acercarse, levantar ambos brazos mirando
## arriba, agarrar el borde, empujar hacia delante para subir y soltar.

const LEDGE_TOP := 1.5
const LEDGE_FRONT_Z := -8.5

var arena: Node
var player: RagdollCharacter
var cam: OrbitCamera
var t := 0.0
var _steps: Array = []
var _done := false


func _ready() -> void:
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	cam = arena.get_node("CameraRig")
	player._spawn_xform = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -7.3))
	player.respawn()
	_steps = [
		# 1) levantar los brazos mirando arriba ANTES de llegar al muro
		[1.0, func():
			cam.pitch = 0.55
			Input.action_press("grab_left")
			Input.action_press("grab_right")],
		# 2) caminar hacia el muro: las manos pasan por encima del borde y lo agarran
		[1.6, func(): Input.action_press("move_forward")],
		[3.5, func():
			_assert("grab_ledge", player.is_grabbing(0) or player.is_grabbing(1),
				"L=%s R=%s" % [player.is_grabbing(0), player.is_grabbing(1)])],
		[7.0, func():
			Input.action_release("grab_left")
			Input.action_release("grab_right")
			cam.pitch = -0.2],
		[9.0, func():
			Input.action_release("move_forward")
			var p := player.get_pelvis().global_position
			_assert("on_top_of_ledge", p.y > LEDGE_TOP + 0.6 and p.z < LEDGE_FRONT_Z - 0.2, "pelvis=%s" % p)
			var up := player.get_torso().global_basis.y.dot(Vector3.UP)
			_assert("standing_on_ledge", up > 0.85 and player.grounded, "up=%.2f grounded=%s" % [up, player.grounded])
			_done = true],
	]


func _physics_process(delta: float) -> void:
	t += delta
	if int(t * 120.0) % 60 == 0:
		var p := player.get_pelvis().global_position
		print("METRIC t=%.1f pelvis=(%.2f, %.2f, %.2f) grabL=%s grabR=%s grounded=%s climbing=%s anchor=%s" % [
			t, p.x, p.y, p.z, player.is_grabbing(0), player.is_grabbing(1), player.grounded, player.climbing, player.climb_anchor])
	while not _steps.is_empty() and t >= _steps[0][0]:
		(_steps.pop_front()[1] as Callable).call()
	if _done:
		get_tree().quit()


func _assert(name: String, cond: bool, info: String) -> void:
	print("ASSERT %s %s (%s)" % ["ok" if cond else "fail", name, info])
