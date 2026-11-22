class_name PlayerSpawner
extends Node
## Jugadores en linea. El nodo `Player` de la escena es siempre el personaje del
## anfitrion (o el tuyo si juegas solo); por cada jugador que se une se crea
## `Player_<peer_id>` en el siguiente punto de aparicion libre.
##  - Anfitrion: ese personaje lo mueve NetInputController con la intencion que
##    llega del PC del jugador.
##  - Clientes: todos los personajes son marionetas (NetSync los mueve); el
##    propio ademas tiene la camara y envia la intencion al anfitrion.
## Sin red no hace nada.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const SLOT_COLORS: Array[Color] = [Color(0.35, 0.65, 1.0), Color(1.0, 0.45, 0.35), Color(0.45, 0.9, 0.45), Color(1.0, 0.85, 0.3)]

@export var host_player_path: NodePath = ^"../Player"
@export var camera_path: NodePath = ^"../CameraRig"
@export var net_sync_path: NodePath = ^"../NetSync"
## Puntos de aparicion de los jugadores 2..4 (el 1 es el `Player` de la escena).
@export var spawn_points: Array[Vector3] = [Vector3(-1.5, 0.05, 6), Vector3(1.5, 0.05, 6), Vector3(3.0, 0.05, 6)]

var _slots := {}            # peer_id -> plaza (1..3) de los jugadores remotos
var _ready_peers := {}      # anfitrion: clientes con el nivel cargado
var _punches := 0           # cliente: contadores de la intencion propia
var _respawns := 0
var _send_tick := 0


func _ready() -> void:
	var host_player := get_node(host_player_path) as RagdollCharacter
	if not Net.is_online():
		return
	_label(host_player, 0)
	if Net.is_host():
		Net.peer_left.connect(_on_peer_left)
	else:
		# el `Player` de la escena es el del anfitrion: aqui es una marioneta (NetSync)
		_rpc_host(&"_client_ready", [])


func get_player(peer_id: int) -> RagdollCharacter:
	if peer_id == 1:
		return get_node(host_player_path) as RagdollCharacter
	return get_parent().get_node_or_null("Player_%d" % peer_id) as RagdollCharacter


func peer_count() -> int:
	return _slots.size() + 1


# --- anfitrion ------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if _ready_peers.has(id):
		return
	var slot := _free_slot()
	if slot < 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# al recien llegado: los jugadores que ya estaban
	for pid in _slots:
		Net.send(id, self, &"_spawn_player", [pid, _slots[pid]])
	_ready_peers[id] = true
	_spawn(id, slot)
	for pid in _ready_peers:
		Net.send(pid, self, &"_spawn_player", [id, slot])
	_sync().on_players_changed()
	_sync().send_full_state(id)


func _on_peer_left(id: int) -> void:
	_ready_peers.erase(id)
	if not _slots.has(id):
		return
	_despawn(id)
	for pid in _ready_peers:
		Net.send(pid, self, &"_despawn_player", [id])
	_sync().on_players_changed()


func ready_peers() -> Array:
	return _ready_peers.keys()


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _intent(data: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var p := get_player(multiplayer.get_remote_sender_id())
	if p == null:
		return
	var ni := p.get_ability(NetInputController) as NetInputController
	if ni:
		ni.set_intent(NetIntent.unpack(data))


func _free_slot() -> int:
	for s in range(1, Net.MAX_PLAYERS):
		if not s in _slots.values():
			return s
	return -1


# --- clientes -------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func _spawn_player(peer_id: int, slot: int) -> void:
	if get_player(peer_id) == null:
		_spawn(peer_id, slot)
	_sync().on_players_changed()


@rpc("authority", "call_remote", "reliable")
func _despawn_player(peer_id: int) -> void:
	_despawn(peer_id)
	_sync().on_players_changed()


func _physics_process(_delta: float) -> void:
	if not Net.is_client():
		return
	_send_tick += 1
	if _send_tick % 2 != 0:   # 60 Hz
		return
	var it := PlayerInputController.read_intent(get_viewport().get_camera_3d())
	it.punch_count = _punches
	it.respawn_count = _respawns
	Net.send(1, self, &"_intent", [it.pack()], false)


func _unhandled_input(event: InputEvent) -> void:
	if not Net.is_client():
		return
	if event.is_action_pressed("punch"):
		_punches += 1
	elif event.is_action_pressed("respawn"):
		_respawns += 1


# --- comun ------------------------------------------------------------------------
func _spawn(peer_id: int, slot: int) -> void:
	var p := PLAYER_SCENE.instantiate() as RagdollCharacter
	p.name = "Player_%d" % peer_id
	p.position = spawn_points[(slot - 1) % spawn_points.size()]
	var input := p.get_node_or_null("PlayerInput")
	if Net.is_host():
		# lo controla la intencion que llega por red
		if input:
			p.remove_child(input)
			input.free()
		var ni := NetInputController.new()
		ni.name = "NetInput"
		ni.peer_id = peer_id
		p.add_child(ni)
		p.move_child(ni, 0)
	else:
		p.net_puppet = true
	get_parent().add_child(p)
	_slots[peer_id] = slot
	_label(p, slot)
	if Net.is_client() and peer_id == Net.my_id():
		p.is_local = true
		var cam := get_node_or_null(camera_path) as OrbitCamera
		if cam:
			cam.set_target(p)


func _despawn(peer_id: int) -> void:
	var p := get_player(peer_id)
	if p:
		p.get_parent().remove_child(p)
		p.queue_free()
	_slots.erase(peer_id)


## Etiqueta "J1".."J4" sobre la cabeza, del color del jugador.
func _label(p: RagdollCharacter, slot: int) -> void:
	var l := Label3D.new()
	l.name = "NameTag"
	l.text = "J%d" % (slot + 1)
	l.modulate = SLOT_COLORS[slot % SLOT_COLORS.size()]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0015
	l.font_size = 48
	l.outline_size = 12
	l.position = Vector3(0, 0.38, 0)
	p.get_head().add_child(l)


func _rpc_host(method: StringName, args: Array) -> void:
	Net.send(1, self, method, args)


func _sync() -> NetSync:
	return get_node(net_sync_path) as NetSync
