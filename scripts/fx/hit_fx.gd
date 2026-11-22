class_name HitFx
extends RefCounted
## Respuesta de un golpe: chispas, sonido seco y sacudida de camara (solo si el
## jugador da o recibe el golpe). Sin "hit stop": bajar Engine.time_scale
## acorta el paso de fisica y desajusta los limites de amortiguacion del ragdoll.

static var _sound: AudioStreamWAV
static var _rng := RandomNumberGenerator.new()  # propio: no altera el azar global (IA)


## `power` 0..1 (golpe flojo .. golpe que noquea).
## En red lo llama el anfitrion y NetSync lo repite en los clientes.
static func punch(victim: RagdollCharacter, attacker: RagdollCharacter, pos: Vector3, dir: Vector3, power: float) -> void:
	show(victim, attacker, pos, dir, power)
	if NetSync.current:
		NetSync.current.broadcast(NetSync.current, &"_fx_punch",
			[victim.get_path(), attacker.get_path() if attacker else NodePath(), pos, dir, power])


## Solo el efecto en este PC (chispas, sonido y, si va con el jugador local, sacudida).
static func show(victim: RagdollCharacter, attacker: RagdollCharacter, pos: Vector3, dir: Vector3, power: float) -> void:
	var world := victim.get_parent()
	_spawn_sparks(world, pos, dir, power)
	_play_sound(world, pos, power)
	if victim.is_local or (attacker != null and attacker.is_local):
		var cam := victim.get_tree().get_first_node_in_group(&"orbit_camera")
		if cam and cam.has_method("add_shake"):
			cam.add_shake(0.06 + 0.12 * power)


static func _spawn_sparks(world: Node, pos: Vector3, dir: Vector3, power: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(10 + 16 * power)
	p.lifetime = 0.35
	p.local_coords = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.6)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	p.direction = dir if dir.length_squared() > 1e-4 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0 + 2.0 * power
	p.initial_velocity_max = 4.0 + 4.0 * power
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4 + power
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 0.85))
	fade.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	p.color_ramp = fade
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _play_sound(world: Node, pos: Vector3, power: float) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = _get_sound()
	a.pitch_scale = _rng.randf_range(0.85, 1.15) - 0.15 * power
	a.volume_db = lerpf(-6.0, 3.0, power)
	a.unit_size = 6.0
	world.add_child(a)
	a.global_position = pos
	a.finished.connect(a.queue_free)
	a.play()


## Golpe seco sintetizado: chasquido de ruido + "bum" grave que cae de tono.
static func _get_sound() -> AudioStreamWAV:
	if _sound:
		return _sound
	var rate := 22050
	var n := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		phase += TAU * lerpf(150.0, 55.0, minf(t / 0.12, 1.0)) / rate
		var thump := sin(phase) * exp(-t * 22.0)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
		var s := clampf(thump * 0.9 + crack * 0.55, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	_sound = AudioStreamWAV.new()
	_sound.format = AudioStreamWAV.FORMAT_16_BITS
	_sound.mix_rate = rate
	_sound.data = data
	return _sound
