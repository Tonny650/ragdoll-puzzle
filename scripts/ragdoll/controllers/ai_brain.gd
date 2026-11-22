class_name AIBrainController
extends CharacterAbility
## IA sencilla estilo Gang Beasts: si el objetivo esta cerca, va hacia el y le
## pega. Sin objetivo se queda quieto. Debe ser el primer hijo del personaje.

@export var target_path: NodePath          ## personaje al que perseguir y golpear
@export var aggro_radius := 7.0

var target: RagdollCharacter
var _punch_cooldown := 1.0


func setup() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as RagdollCharacter


func physics_step(delta: float) -> void:
	if target == null:
		return
	var c := character
	c.move_input = Vector3.ZERO
	c.want_grab = [false, false]
	_punch_cooldown -= delta
	if target.is_knocked_out():
		return
	var to_target := target.get_center() - c.get_center()
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > aggro_radius or dist < 0.01:
		return
	c.facing_yaw = atan2(-to_target.x, -to_target.z)
	c.aim_pitch = 0.1
	if dist > 1.1:
		c.move_input = to_target / dist * 0.7
	elif _punch_cooldown <= 0.0:
		c.want_punch = true
		_punch_cooldown = randf_range(0.8, 1.6)
