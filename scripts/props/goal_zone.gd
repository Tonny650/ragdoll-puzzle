class_name GoalZone
extends Area3D
## Meta del puzle: avisa cuando el jugador llega.

signal reached(message: String)

@export var message := "¡Puzle resuelto!"

var _done := false


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	if not body.has_meta("ragdoll_owner"):
		return
	var owner_char = body.get_meta("ragdoll_owner")
	if owner_char is RagdollCharacter and owner_char.player_controlled:
		_done = true
		print("GOAL reached")
		reached.emit(message)
