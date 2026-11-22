class_name GoalZone
extends Area3D
## Meta del puzle: avisa cuando llega un jugador. En red lo decide el
## anfitrion y el mensaje se muestra en todos los PCs.

signal reached(message: String)

@export var message := "¡Puzle resuelto!"

var _done := false


func _on_body_entered(body: Node3D) -> void:
	if _done or not Net.is_authority():
		return
	if not body.has_meta("ragdoll_owner"):
		return
	var owner_char = body.get_meta("ragdoll_owner")
	if owner_char is RagdollCharacter and owner_char.is_player():
		_done = true
		print("GOAL reached")
		reached.emit(message)
		if NetSync.current:
			NetSync.current.broadcast(self, &"_net_reached", [message])


@rpc("authority", "call_remote", "reliable")
func _net_reached(msg: String) -> void:
	_done = true
	reached.emit(msg)
