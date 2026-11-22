class_name NetInputController
extends CharacterAbility
## En el anfitrion: controla el personaje de un jugador remoto con la ultima
## intencion que ha enviado su PC (ver PlayerSpawner). Debe ser el primer hijo.

var peer_id := 0
var _intent: NetIntent
var _last_punch := -1
var _last_respawn := -1


func setup() -> void:
	character.add_to_group("player")


func set_intent(it: NetIntent) -> void:
	if _intent == null:
		# primera intencion: los contadores empiezan donde esten
		_last_punch = it.punch_count
		_last_respawn = it.respawn_count
	_intent = it


func physics_step(_delta: float) -> void:
	if _intent == null:
		return
	var c := character
	_intent.apply_to(c)
	if _intent.punch_count != _last_punch:
		_last_punch = _intent.punch_count
		c.want_punch = true
	if _intent.respawn_count != _last_respawn:
		_last_respawn = _intent.respawn_count
		c.respawn()
