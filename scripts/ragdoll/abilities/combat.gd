class_name CombatAbility
extends CharacterAbility
## Puñetazos (Gang Beasts): alterna brazo, lanza el antebrazo con un impulso y
## mantiene el brazo recto y rigido durante `punch_duration`. Lo dispara
## `character.want_punch` (jugador: F, IA: al estar cerca).
## Si hay un rival a tiro delante, el puño apunta a su cabeza (ayuda de
## apuntado): sin ella los golpes rectos dan en el pecho y nunca noquean.

const ARM_PRIORITY := 30

@export var punch_impulse := 14.0
@export var punch_duration := 0.28
@export var arm_frequency := 32.0         ## rigidez del brazo durante el golpe (rad/s)
@export var aim_assist_range := 1.1       ## distancia maxima (m) a la cabeza del rival para apuntarle
@export_range(0.0, 90.0, 1.0, "degrees") var aim_assist_angle := 50.0  ## cono delante del personaje
@export var punch_lunge := 1.5            ## al golpear a un rival el torso se lanza hacia el (m/s): alarga el alcance

var _timers := [0.0, 0.0]
var _next_side := Side.RIGHT
var _targets: Array = [null, null]   # cabeza a la que apunta cada puño (o null)


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
	_targets[side] = find_target_head()
	var dir := _punch_dir(side)
	c.get_lower_arm(side).apply_central_impulse(dir * punch_impulse)
	if _targets[side] != null:
		var torso := c.get_torso()
		torso.apply_central_impulse(Vector3(dir.x, 0.0, dir.z).normalized() * torso.mass * punch_lunge)
	c.get_torso().apply_torque_impulse(Vector3.UP * (4.0 if side == Side.RIGHT else -4.0))


func is_punching(side: int) -> bool:
	return _timers[side] > 0.0


## `body` es un brazo de este personaje que esta lanzando un puñetazo.
func is_punching_with(body: Node) -> bool:
	for side in 2:
		if _timers[side] > 0.0 and (body == character.get_lower_arm(side) or body == character.get_upper_arm(side)):
			return true
	return false


## Cabeza del rival mas cercano a tiro y delante del personaje, o null.
func find_target_head() -> RigidBody3D:
	var c := character
	var from := c.get_torso().global_position
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, c.facing_yaw)
	var best: RigidBody3D = null
	var best_d := aim_assist_range
	for other in c.get_tree().get_nodes_in_group(RagdollCharacter.GROUP):
		if other == c or not (other is RagdollCharacter):
			continue
		var head := (other as RagdollCharacter).get_head()
		var to := head.global_position - from
		var d := to.length()
		var flat := Vector3(to.x, 0.0, to.z)
		if d >= best_d or flat.length_squared() < 1e-4:
			continue
		if rad_to_deg(fwd.angle_to(flat.normalized())) > aim_assist_angle:
			continue
		best = head
		best_d = d
	return best


func arm_claim_priority(side: int) -> int:
	return ARM_PRIORITY if _timers[side] > 0.0 else -1


func drive_arm(side: int, _delta: float) -> void:
	# Puñetazo: brazo recto y muy rigido hacia delante
	var c := character
	var pdir := _punch_dir(side)
	RagdollMuscles.pd_aim(c.get_upper_arm(side), pdir, arm_frequency, 0.8, 500.0 * c.strength, c.get_torso(), c.strength, 2.0)
	RagdollMuscles.pd_aim(c.get_lower_arm(side), pdir, arm_frequency, 0.8, 300.0 * c.strength, null, c.strength)
	c.arm_gravity_compensation(side, c.strength)


func reset() -> void:
	_timers = [0.0, 0.0]
	_targets = [null, null]


func _punch_dir(side: int) -> Vector3:
	var c := character
	var target = _targets[side]
	if is_instance_valid(target):
		var shoulder := c.get_upper_arm(side).global_transform * c.body.shoulder_offset
		var to: Vector3 = (target as RigidBody3D).global_position - shoulder
		if to.length_squared() > 1e-4:
			return to.normalized()
	return (Quaternion(Vector3.UP, c.facing_yaw) * Quaternion(Vector3.RIGHT, clampf(c.aim_pitch, -0.3, 0.4))) * Vector3.FORWARD
