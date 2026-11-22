class_name CombatAbility
extends CharacterAbility
## Puñetazos (Gang Beasts): alterna brazo, lanza el antebrazo con un impulso y
## mantiene el brazo recto y rigido durante `punch_duration`. Lo dispara
## `character.want_punch` (jugador: F, IA: al estar cerca).

const ARM_PRIORITY := 30

@export var punch_impulse := 14.0
@export var punch_duration := 0.28
@export var arm_frequency := 32.0         ## rigidez del brazo durante el golpe (rad/s)

var _timers := [0.0, 0.0]
var _next_side := Side.RIGHT


func physics_step(delta: float) -> void:
	var c := character
	if c.want_punch:
		c.want_punch = false
		punch()
	if c.strength <= 0.01:
		return
	for side in 2:
		_timers[side] = maxf(0.0, _timers[side] - delta)


func punch() -> void:
	var c := character
	if c.strength < 0.5:
		return
	var side := _next_side
	_next_side = Side.LEFT if side == Side.RIGHT else Side.RIGHT
	if c.is_grabbing(side):
		return
	_timers[side] = punch_duration
	c.get_lower_arm(side).apply_central_impulse(_punch_dir() * punch_impulse)
	c.get_torso().apply_torque_impulse(Vector3.UP * (4.0 if side == Side.RIGHT else -4.0))


func is_punching(side: int) -> bool:
	return _timers[side] > 0.0


func arm_claim_priority(side: int) -> int:
	return ARM_PRIORITY if _timers[side] > 0.0 else -1


func drive_arm(side: int, _delta: float) -> void:
	# Puñetazo: brazo recto y muy rigido hacia delante
	var c := character
	var pdir := _punch_dir()
	RagdollMuscles.pd_aim(c.get_upper_arm(side), pdir, arm_frequency, 0.8, 500.0 * c.strength, c.get_torso(), c.strength, 2.0)
	RagdollMuscles.pd_aim(c.get_lower_arm(side), pdir, arm_frequency, 0.8, 300.0 * c.strength, null, c.strength)
	c.arm_gravity_compensation(side, c.strength)


func reset() -> void:
	_timers = [0.0, 0.0]


func _punch_dir() -> Vector3:
	var c := character
	return (Quaternion(Vector3.UP, c.facing_yaw) * Quaternion(Vector3.RIGHT, clampf(c.aim_pitch, -0.3, 0.4))) * Vector3.FORWARD
