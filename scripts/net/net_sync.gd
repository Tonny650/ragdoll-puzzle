class_name NetSync
extends Node
## Replica la fisica del anfitrion en los clientes.
##  - Anfitrion: cada `send_every` pasos de fisica manda una instantanea con la
##    posicion y rotacion de todos los cuerpos registrados (props y mecanismos
##    del grupo `net_body` y las piezas de todos los personajes).
##  - Clientes: esos cuerpos estan congelados (cinematicos); se dibujan
##    `interp_delay_ms` por detras de la ultima instantanea, interpolando entre
##    las dos que rodean ese instante. Asi se ve suave aunque lleguen a saltos.
## Tambien reparte eventos (chispas de golpes, placa de presion, meta).
## Sin red no hace nada.

const GROUP_BODY := &"net_body"     # cuerpos que se replican por posicion
const GROUP_STATE := &"net_state"   # nodos con estado propio: send_state_to(peer)
const BODY_BYTES := 20              # 3 x f32 + 4 x f16
const HEADER_BYTES := 8             # u32 tick + u16 version + u16 cantidad

static var current: NetSync

@export var send_every := 4                 ## pasos de fisica entre instantaneas (120/4 = 30 Hz)
@export var interp_delay_ms := 100.0        ## retraso de dibujado en los clientes

var _bodies: Array[Node3D] = []
var _version := 0
var _tick := 0
# cliente
var _client_version := -1
var _snaps: Array = []          # [{tick, data}] ordenadas por tick
var _render_tick := -1.0
var _latest_tick := -1
var _latest_ms := 0


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	if not Net.is_online():
		return
	if Net.is_client():
		for n in _level_nodes(GROUP_BODY):
			_freeze(n)
		# todos los personajes del nivel (jugador del anfitrion, muñecos con IA)
		# los simula el anfitrion: aqui son marionetas
		for c in get_tree().get_nodes_in_group(RagdollCharacter.GROUP):
			if _level().is_ancestor_of(c) and not c.net_puppet:
				c.net_puppet = true
				c._become_puppet()
	_rebuild()


## Han entrado o salido jugadores: rehacer el registro (igual en todos los PCs).
func on_players_changed() -> void:
	_rebuild()
	if Net.is_host():
		_version += 1
		for pid in _spawner_peers():
			Net.send(pid, self, &"_set_version", [_version])


## Al jugador que acaba de entrar: version del registro y estado de los mecanismos.
func send_full_state(peer: int) -> void:
	Net.send(peer, self, &"_set_version", [_version])
	for n in _level_nodes(GROUP_STATE):
		if n.has_method("send_state_to"):
			n.send_state_to(peer)


## Anfitrion: llama `node.method(args)` en todos los clientes (RPC fiable).
func broadcast(node: Node, method: StringName, args: Array) -> void:
	if not Net.is_host():
		return
	for pid in _spawner_peers():
		Net.send(pid, node, method, args)


@rpc("authority", "call_remote", "reliable")
func _fx_punch(victim: NodePath, attacker: NodePath, pos: Vector3, dir: Vector3, power: float) -> void:
	var v := get_node_or_null(victim) as RagdollCharacter
	if v:
		var a: RagdollCharacter = null if attacker.is_empty() else get_node_or_null(attacker) as RagdollCharacter
		HitFx.show(v, a, pos, dir, power)


func body_count() -> int:
	return _bodies.size()


# --- anfitrion --------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if not Net.is_host():
		return
	_tick += 1
	if _tick % send_every != 0:
		return
	var peers := _spawner_peers()
	if peers.is_empty():
		return
	var data := PackedByteArray()
	data.resize(HEADER_BYTES + _bodies.size() * BODY_BYTES)
	data.encode_u32(0, _tick)
	data.encode_u16(4, _version & 0xFFFF)
	data.encode_u16(6, _bodies.size())
	var o := HEADER_BYTES
	for b in _bodies:
		var xf := b.global_transform if is_instance_valid(b) else Transform3D.IDENTITY
		var q := xf.basis.get_rotation_quaternion()
		data.encode_float(o, xf.origin.x)
		data.encode_float(o + 4, xf.origin.y)
		data.encode_float(o + 8, xf.origin.z)
		data.encode_half(o + 12, q.x)
		data.encode_half(o + 14, q.y)
		data.encode_half(o + 16, q.z)
		data.encode_half(o + 18, q.w)
		o += BODY_BYTES
	for pid in peers:
		Net.send(pid, self, &"_snapshot", [data], false)


# --- clientes -----------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func _set_version(v: int) -> void:
	_client_version = v
	_snaps.clear()
	_render_tick = -1.0


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot(data: PackedByteArray) -> void:
	if data.size() < HEADER_BYTES:
		return
	var tick := data.decode_u32(0)
	if data.decode_u16(4) != (_client_version & 0xFFFF) or data.decode_u16(6) != _bodies.size():
		return  # registro distinto (alguien acaba de entrar/salir): esperar a la version nueva
	if data.size() != HEADER_BYTES + _bodies.size() * BODY_BYTES:
		return
	if tick <= _latest_tick:
		return
	_snaps.append({"tick": tick, "data": data})
	if _snaps.size() > 30:
		_snaps.pop_front()
	_latest_tick = tick
	_latest_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if not Net.is_client() or _snaps.is_empty():
		return
	var tps := float(Engine.physics_ticks_per_second)
	var target := _latest_tick + (Time.get_ticks_msec() - _latest_ms) * tps / 1000.0 - interp_delay_ms * tps / 1000.0
	if _render_tick < 0.0 or absf(target - _render_tick) > tps * 0.5:
		_render_tick = target
	else:
		_render_tick += delta * tps
		_render_tick += (target - _render_tick) * minf(1.0, delta * 2.0)
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[0]
	for s in _snaps:
		if s.tick <= _render_tick:
			a = s
			b = s
		else:
			b = s
			break
	var t := 0.0
	if b.tick != a.tick:
		t = clampf((_render_tick - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	_apply(a.data, b.data, t)
	# ya no hacen falta las anteriores a `a`
	while _snaps.size() > 2 and _snaps[1].tick <= _render_tick:
		_snaps.pop_front()


func _apply(da: PackedByteArray, db: PackedByteArray, t: float) -> void:
	var o := HEADER_BYTES
	for body in _bodies:
		if is_instance_valid(body):
			var pa := Vector3(da.decode_float(o), da.decode_float(o + 4), da.decode_float(o + 8))
			var pb := Vector3(db.decode_float(o), db.decode_float(o + 4), db.decode_float(o + 8))
			var qa := Quaternion(da.decode_half(o + 12), da.decode_half(o + 14), da.decode_half(o + 16), da.decode_half(o + 18)).normalized()
			var qb := Quaternion(db.decode_half(o + 12), db.decode_half(o + 14), db.decode_half(o + 16), db.decode_half(o + 18)).normalized()
			body.global_transform = Transform3D(Basis(qa.slerp(qb, t)), pa.lerp(pb, t))
		o += BODY_BYTES


# --- comun --------------------------------------------------------------------------
func _rebuild() -> void:
	_bodies.clear()
	var props := _level_nodes(GROUP_BODY)
	props.sort_custom(func(x: Node, y: Node): return str(x.get_path()) < str(y.get_path()))
	for n in props:
		if n is Node3D:
			_bodies.append(n)
	var chars: Array = []
	for c in get_tree().get_nodes_in_group(RagdollCharacter.GROUP):
		if c.is_inside_tree() and not c.is_queued_for_deletion() and _level().is_ancestor_of(c):
			chars.append(c)
	chars.sort_custom(func(x: Node, y: Node): return String(x.name) < String(y.name))
	for c: RagdollCharacter in chars:
		for def in c.body.parts:
			_bodies.append(c.bodies[String(def.name)])
	_snaps.clear()
	_render_tick = -1.0
	_latest_tick = -1


func _freeze(n: Node) -> void:
	n.set_physics_process(false)   # mecanismos: su script ya no los mueve
	if n is RigidBody3D:
		var rb := n as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true


func _level() -> Node:
	return get_parent()


func _level_nodes(group: StringName) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(group):
		if _level().is_ancestor_of(n):
			out.append(n)
	return out


func _spawner_peers() -> Array:
	var sp := _level().get_node_or_null("PlayerSpawner") as PlayerSpawner
	return sp.ready_peers() if sp else []
