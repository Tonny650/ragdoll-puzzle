extends Node
## Autoload "Net": sesion multijugador en linea (anfitrion autoritativo).
## El anfitrion simula toda la fisica; los clientes envian su intencion y
## dibujan lo que reciben (ver PlayerSpawner y NetSync en el nivel).
##
## Sin sesion (OFFLINE) el juego funciona igual que en un jugador.
##
## Argumentos de linea de comandos (tras `--`): --host, --join=IP, --port=N,
## --solo, --lag=MS (retraso simulado por sentido), --loss=0.05 (perdida simulada).

signal connected                     # cliente: conectado al anfitrion
signal connection_failed(reason: String)
signal session_ended(reason: String) # el anfitrion se cerro / nos desconectamos
signal peer_joined(id: int)
signal peer_left(id: int)

enum Role { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const CHANNEL_STATE := 1    # instantaneas (sin fiabilidad)
const CHANNEL_INPUT := 2    # intenciones (sin fiabilidad)

var role := Role.OFFLINE
var sim_latency_ms := 0     ## retraso añadido a cada mensaje enviado (pruebas)
var sim_loss := 0.0         ## probabilidad de perder un mensaje sin fiabilidad (pruebas)
var last_error := ""

var _delayed: Array = []     # [tiempo_envio_ms, Callable]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -100
	var args := cmdline()
	if args.has("lag"):
		sim_latency_ms = int(args.lag)
	if args.has("loss"):
		sim_loss = float(args.loss)
	multiplayer.peer_connected.connect(func(id: int): peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Argumentos tras `--` como diccionario: --join=1.2.3.4 -> {"join": "1.2.3.4"}, --host -> {"host": ""}.
func cmdline() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1, 3)
	if err != OK:
		last_error = "No se pudo abrir el puerto %d (%s)" % [port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 3)
	if err != OK:
		last_error = "No se pudo conectar a %s:%d (%s)" % [address, port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	return OK


func leave() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and enet.host:
		# avisar ya de la desconexion (si no, el otro lado espera al timeout de ENet)
		for p in enet.host.get_peers():
			p.peer_disconnect()
		enet.host.flush()
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	_delayed.clear()


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## Decide la fisica este PC (anfitrion o partida sin red).
func is_authority() -> bool:
	return role != Role.CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Ping (ida y vuelta, ms) con el anfitrion, o -1.
func ping_ms() -> int:
	if not is_client():
		return -1
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return -1
	var p := enet.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


## Llama `node.rpc_id(peer, method, args...)` aplicando el retraso y la perdida
## simulados. `reliable` = false permite perder el mensaje.
func send(peer: int, node: Node, method: StringName, args: Array, reliable := true) -> void:
	if not reliable and sim_loss > 0.0 and _rng.randf() < sim_loss:
		return
	var fn := func():
		if is_instance_valid(node) and node.is_inside_tree() and is_online() and peer in multiplayer.get_peers():
			node.rpc_id.callv([peer, method] + args)
	if sim_latency_ms <= 0:
		fn.call()
	else:
		_delayed.append([Time.get_ticks_msec() + sim_latency_ms, fn])


func _process(_delta: float) -> void:
	if _delayed.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _delayed.is_empty() and _delayed[0][0] <= now:
		(_delayed.pop_front()[1] as Callable).call()


func _on_connection_failed() -> void:
	last_error = "No se pudo conectar con el anfitrion."
	leave()
	connection_failed.emit(last_error)


func _on_server_disconnected() -> void:
	last_error = "Se perdio la conexion con el anfitrion."
	leave()
	session_ended.emit(last_error)
