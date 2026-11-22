extends Node
## Prueba automatica del multijugador en linea con DOS procesos en este PC:
##   godot --headless res://tests/test_net.tscn -- --role=host
##   godot --headless res://tests/test_net.tscn -- --role=client
## (ver tests/run_net_test.sh, que lanza los dos; admite --lag=MS y --loss=P).
## Comprueba: el cliente entra y aparece su personaje; su intencion (W) lo mueve
## en el anfitrion y el cliente lo ve en el mismo sitio; una caja empujada en el
## anfitrion llega al mismo sitio en el cliente; el puñetazo del cliente llega;
## al salir el cliente su personaje desaparece en el anfitrion.

const PORT := 7799
const TIMEOUT := 45.0

var role := ""
var arena: Node
var t := 0.0
var joined_at := -1.0
var my_char: RagdollCharacter       # cliente: su personaje
var client_char: RagdollCharacter   # anfitrion: el personaje del cliente
var client_id := 0
var start_pos := Vector3.ZERO
var punched := false
var step := 0
var _done := false


func _ready() -> void:
	role = Net.cmdline().get("role", "")
	if role == "host":
		if Net.host(PORT) != OK:
			_assert("host_started", false, Net.last_error)
			_quit()
			return
		_load_arena()
	elif role == "client":
		Net.connected.connect(_load_arena)
		Net.connection_failed.connect(func(r): _assert("client_connected", false, r); _quit())
		Net.session_ended.connect(func(_r): _quit())
		# el anfitrion puede tardar un poco en arrancar
		await get_tree().create_timer(1.0).timeout
		Net.join("127.0.0.1", PORT)
	else:
		push_error("falta --role=host|client")
		_quit()


func _load_arena() -> void:
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	if role == "client":
		_assert("client_connected", true, "id=%d" % Net.my_id())


func _physics_process(delta: float) -> void:
	t += delta
	if t > TIMEOUT and not _done:
		_assert("timeout", false, "paso %d" % step)
		_quit()
		return
	if arena == null:
		return
	if role == "host":
		_host_step()
	else:
		_client_step()


# --- anfitrion ------------------------------------------------------------------
func _host_step() -> void:
	if client_id == 0:
		for c in arena.get_children():
			if c is RagdollCharacter and String(c.name).begins_with("Player_"):
				client_char = c
				client_id = int(String(c.name).substr(7))
				joined_at = t
				start_pos = c.get_center()
				_assert("client_spawned_on_host", true, String(c.name))
		return
	if not is_instance_valid(client_char) or not client_char.is_inside_tree():
		if step == 3:
			_assert("client_left_despawned", true, "")
			_quit()
		return
	var combat := client_char.get_ability(CombatAbility) as CombatAbility
	if combat and (combat.is_punching(0) or combat.is_punching(1) or combat._t[0] >= 0.0 or combat._t[1] >= 0.0):
		punched = true
	var dt := t - joined_at
	if step == 0 and dt > 6.0:
		# el cliente ha caminado de t+1 a t+3 y luego se ha parado
		var moved := (client_char.get_center() - start_pos)
		moved.y = 0.0
		_assert("client_intent_moves_char", moved.length() > 1.0, "movido %.2f m" % moved.length())
		Net.send(client_id, self, &"_check", ["client_char_same_place", client_char.get_pelvis().get_path(), client_char.get_pelvis().global_position, 0.3])
		# empujar una caja en el anfitrion
		var crate := arena.get_node("Props/Crate") as RigidBody3D
		crate.apply_central_impulse(Vector3(1, 0, 0) * crate.mass * 3.0)
		step = 1
	elif step == 1 and dt > 9.5:
		var crate := arena.get_node("Props/Crate") as RigidBody3D
		Net.send(client_id, self, &"_check", ["crate_same_place", crate.get_path(), crate.global_position, 0.1])
		_assert("client_punch_reaches_host", punched, "")
		step = 2
	elif step == 2 and dt > 10.5:
		Net.send(client_id, self, &"_please_leave", [])
		step = 3


# --- cliente --------------------------------------------------------------------
func _client_step() -> void:
	if my_char == null:
		my_char = arena.get_node_or_null("Player_%d" % Net.my_id()) as RagdollCharacter
		if my_char:
			joined_at = t
			_assert("own_char_spawned_on_client", my_char.is_local and my_char.net_puppet, "")
		return
	var dt := t - joined_at
	if step == 0 and dt > 1.0:
		Input.action_press("move_forward")
		step = 1
	elif step == 1 and dt > 3.0:
		Input.action_release("move_forward")
		step = 2
	elif step == 2 and dt > 4.0:
		var ev := InputEventAction.new()
		ev.action = &"punch"
		ev.pressed = true
		Input.parse_input_event(ev)
		step = 3


@rpc("authority", "call_remote", "reliable")
func _check(label: String, path: NodePath, host_pos: Vector3, tol: float) -> void:
	# lo que ve el cliente va `interp_delay_ms` por detras: esperar un poco
	await get_tree().create_timer(0.5).timeout
	var n := get_node_or_null(path) as Node3D
	if n == null:
		_assert(label, false, "no existe %s" % path)
		return
	var d := n.global_position.distance_to(host_pos)
	_assert(label, d < tol, "diferencia %.3f m (anfitrion %s, cliente %s)" % [d, host_pos, n.global_position])


@rpc("authority", "call_remote", "reliable")
func _please_leave() -> void:
	Net.leave()
	_quit()


func _quit() -> void:
	_done = true
	get_tree().quit.call_deferred()


func _assert(name: String, cond: bool, info: String) -> void:
	print("ASSERT %s %s %s (%s)" % ["ok" if cond else "fail", role, name, info])
