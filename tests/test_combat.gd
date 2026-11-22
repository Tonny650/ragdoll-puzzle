extends Node
## Prueba automatica del combate: puñetazos, KO, recuperacion, dejarse caer (Q)
## y la IA de sparring. Cada fase espera a que pase algo (o a un limite de
## tiempo) y comprueba el resultado con lineas ASSERT.
##   1. El jugador golpea a DummyIdle (pulsando "punch") hasta noquearlo.
##   2. El muñeco noqueado queda flacido y en el suelo, y luego se levanta solo.
##   3. Q deja al jugador flacido; al soltarla se vuelve a poner de pie.
##   4. El jugador se queda quieto junto a DummySparring: la IA le noquea, y al
##      levantarse tiene unos segundos de gracia sin volver a caer KO.

const MAX_PUNCHES := 10

var arena: Node
var player: RagdollCharacter
var idle: RagdollCharacter
var sparring: RagdollCharacter
var cam: OrbitCamera
var t := 0.0
var phase := 0
var phase_t := 0.0
var punches := 0
var _next_punch_t := 1.0
var _ko_count := {}
var _recovered_at := {}


func _ready() -> void:
	seed(12345)  # la IA elige al azar el tiempo entre golpes
	arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	idle = arena.get_node("DummyIdle")
	sparring = arena.get_node("DummySparring")
	cam = arena.get_node("CameraRig")
	for c in [player, idle, sparring]:
		var who: RagdollCharacter = c
		_ko_count[who] = 0
		who.knocked_out.connect(func():
			_ko_count[who] += 1
			print("METRIC t=%.2f KO %s" % [t, who.name]))
		who.recovered.connect(func():
			_recovered_at[who] = t
			print("METRIC t=%.2f RECOVERED %s" % [t, who.name]))
		(who.get_ability(KnockoutAbility) as KnockoutAbility).hurt.connect(func(dmg: float, total: float):
			print("METRIC t=%.2f HURT %s dmg=%.2f total=%.2f" % [t, who.name, dmg, total]))
	# DummyIdle esta en (-3, 0, -3) mirando a +Z: el jugador delante, mirandole
	player.set_spawn(Transform3D(Basis.IDENTITY, Vector3(-3, 0.05, -2.1)))
	player.respawn()
	cam.yaw = 0.0
	cam.pitch = -0.1


func _physics_process(delta: float) -> void:
	t += delta
	phase_t += delta
	match phase:
		0:  # 1. puñetazos hasta noquear a DummyIdle (persiguiendole: cada golpe le empuja)
			var to := idle.get_head().global_position - player.get_head().global_position
			to.y = 0.0
			cam.yaw = atan2(-to.x, -to.z)
			if idle.is_knocked_out():
				Input.action_release("move_forward")
				_assert("punches_knock_out", true, "%d golpes" % punches)
				_next()
			elif punches >= MAX_PUNCHES:
				if phase_t > _next_punch_t + 1.0:
					_assert("punches_knock_out", false, "%d golpes sin KO, daño=%.2f" % [punches, _damage(idle)])
					_finish()
			elif to.length() > 0.85:
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")
				if phase_t > _next_punch_t:
					punches += 1
					_next_punch_t = phase_t + 0.55
					_press_punch()
					print("METRIC t=%.2f golpe %d dist_cabezas=%.2f" % [t, punches, to.length()])
		1:  # 2a. KO: sin fuerza y en el suelo
			if phase_t > 1.5:
				var c := idle.get_center()
				_assert("ko_is_limp", idle.strength == 0.0 and c.y < 0.7,
					"strength=%.2f centro_y=%.2f" % [idle.strength, c.y])
				_next()
		2:  # 2b. se levanta solo
			if idle in _recovered_at and t > _recovered_at[idle] + 3.0:
				var up := idle.get_torso().global_basis.y.dot(Vector3.UP)
				_assert("recovers_and_stands", up > 0.85 and idle.get_center().y > 0.9 and idle.strength > 0.95,
					"up=%.2f centro_y=%.2f strength=%.2f" % [up, idle.get_center().y, idle.strength])
				_next()
			elif phase_t > 8.0:
				_assert("recovers_and_stands", false, "no se recupero")
				_finish()
		3:  # 3. Q: flacido mientras se mantiene, de pie al soltar
			if phase_t < 0.02:
				Input.action_press("go_limp")
			elif phase_t > 1.5 and Input.is_action_pressed("go_limp"):
				_assert("limp_drops", player.strength < 0.05 and player.get_center().y < 0.7,
					"strength=%.2f centro_y=%.2f" % [player.strength, player.get_center().y])
				Input.action_release("go_limp")
			elif phase_t > 5.5:
				var up := player.get_torso().global_basis.y.dot(Vector3.UP)
				_assert("limp_recovers", up > 0.85 and player.get_center().y > 0.9,
					"up=%.2f centro_y=%.2f" % [up, player.get_center().y])
				# junto a DummySparring (14, 0, 7), que patrulla con aggro 5 m
				player.set_spawn(Transform3D(Basis.IDENTITY, Vector3(11.5, 0.05, 7)))
				player.respawn()
				_next()
		4:  # 4. la IA noquea al jugador quieto
			if _ko_count[player] > 0:
				_assert("ai_knocks_out_player", true, "a los %.1f s" % phase_t)
				_next()
			elif phase_t > 40.0:
				_assert("ai_knocks_out_player", false, "sin KO en 40 s, daño=%.2f" % _damage(player))
				_finish()
		5:  # 4b. tras levantarse, gracia: no vuelve a caer enseguida
			if player in _recovered_at and t > _recovered_at[player] + 1.9:
				_assert("grace_after_recovery", _ko_count[player] == 1 and not player.is_knocked_out(),
					"KOs=%d" % _ko_count[player])
				_finish()
			elif phase_t > 8.0:
				_assert("grace_after_recovery", false, "el jugador no se recupero")
				_finish()
	if int(t * 120.0) % 120 == 0:
		print("METRIC t=%.1f fase=%d player_str=%.2f idle_str=%.2f dmg_player=%.2f dmg_idle=%.2f" % [
			t, phase, player.strength, idle.strength, _damage(player), _damage(idle)])


func _press_punch() -> void:
	var ev := InputEventAction.new()
	ev.action = &"punch"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = &"punch"
	up.pressed = false
	Input.parse_input_event(up)


func _damage(c: RagdollCharacter) -> float:
	return (c.get_ability(KnockoutAbility) as KnockoutAbility).damage


func _next() -> void:
	phase += 1
	phase_t = 0.0


func _finish() -> void:
	get_tree().quit()


func _assert(name: String, cond: bool, info: String) -> void:
	print("ASSERT %s %s (%s)" % ["ok" if cond else "fail", name, info])
