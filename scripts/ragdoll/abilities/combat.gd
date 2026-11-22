class_name CombatAbility
extends CharacterAbility
## Puñetazos de boxeo (Gang Beasts). Cada golpe tiene tres fases:
##   1. Carga (`windup_time`): el puño va a la guardia, junto a la barbilla, con
##      el codo abajo, y el hombro de ese lado se echa atras.
##   2. Golpe (`strike_time`): el brazo se estira recto hacia la cara del rival
##      con un impulso en el antebrazo, girando el torso hacia delante.
##   3. Vuelta (`retract_time`): el puño vuelve a la guardia.
## Tras golpear, los dos puños se quedan en guardia `guard_time` segundos, asi
## los golpes seguidos parecen una combinacion. Lo dispara `character.want_punch`
## (jugador: F, IA: al estar cerca). Alterna brazo.
## Si hay un rival a tiro delante, el puño apunta a su cabeza (ayuda de
## apuntado): sin ella los golpes rectos dan en el pecho y nunca noquean.

const ARM_PRIORITY := 30

enum Phase { NONE, WINDUP, STRIKE, RETRACT }

@export var punch_impulse := 18.0         ## impulso del antebrazo al soltar el golpe
@export var windup_time := 0.08
@export var strike_time := 0.16
@export var retract_time := 0.14
@export var guard_time := 0.7             ## puños en guardia tras golpear (s)
@export var arm_frequency := 32.0         ## rigidez del brazo durante el golpe (rad/s)
@export var guard_frequency := 22.0       ## rigidez del brazo en guardia (rad/s)
@export var torso_twist := 5.0            ## giro del torso que acompaña al golpe (impulso angular)
@export_range(0.0, 1.0) var arm_brake := 0.75  ## cuanto se frena el brazo al acabar el golpe
@export var aim_assist_range := 1.1       ## distancia maxima (m) a la cabeza del rival para apuntarle
@export_range(0.0, 90.0, 1.0, "degrees") var aim_assist_angle := 50.0  ## cono delante del personaje
@export var punch_lunge := 1.5            ## al golpear a un rival el torso se lanza hacia el (m/s): alarga el alcance

var _t := [-1.0, -1.0]               # tiempo desde que empezo el golpe de cada brazo (-1 = ninguno)
var _guard := 0.0
var _next_side := Side.RIGHT
var _targets: Array = [null, null]   # cabeza a la que apunta cada puño (o null)
var _aim := [Vector3.FORWARD, Vector3.FORWARD]  # direccion del golpe, fijada al soltarlo


func physics_step(delta: float) -> void:
	var c := character
	if c.want_punch:
		c.want_punch = false
		punch()
	if c.strength <= 0.01:
		return
	_guard = maxf(0.0, _guard - delta)
	for side in 2:
		if _t[side] < 0.0:
			continue
		var before := _phase(side)
		_t[side] += delta
		if before == Phase.WINDUP and _phase(side) == Phase.STRIKE:
			_release(side)
		elif before == Phase.STRIKE and _phase(side) == Phase.RETRACT:
			_brake(side)
		elif _phase(side) == Phase.NONE:
			_t[side] = -1.0


func punch() -> void:
	var c := character
	if c.strength < 0.5:
		return
	var side := _next_side
	if _t[side] >= 0.0 and _phase(side) != Phase.RETRACT:
		return  # ese brazo aun esta golpeando
	_next_side = Side.LEFT if side == Side.RIGHT else Side.RIGHT
	if c.is_grabbing(side):
		return
	_t[side] = 0.0
	_guard = guard_time
	_targets[side] = find_target_head()
	# cargar: el hombro de ese lado hacia atras
	c.get_torso().apply_torque_impulse(Vector3.UP * (-0.4 if side == Side.RIGHT else 0.4) * torso_twist)


func _release(side: int) -> void:
	var c := character
	var dir := _punch_dir(side)
	_aim[side] = dir
	c.get_lower_arm(side).apply_central_impulse(dir * punch_impulse)
	var torso := c.get_torso()
	torso.apply_torque_impulse(Vector3.UP * (1.0 if side == Side.RIGHT else -1.0) * torso_twist)
	if _targets[side] != null:
		torso.apply_central_impulse(Vector3(dir.x, 0.0, dir.z).normalized() * torso.mass * punch_lunge)


## Fin del golpe: los musculos frenan el brazo en seco. Sin esto la inercia del
## puñetazo lo lleva hacia arriba y el puño acaba por encima de la cabeza.
func _brake(side: int) -> void:
	var c := character
	var torso_v := c.get_torso().linear_velocity
	for arm in [c.get_upper_arm(side), c.get_lower_arm(side)]:
		var rb := arm as RigidBody3D
		rb.angular_velocity *= 1.0 - arm_brake
		rb.linear_velocity = rb.linear_velocity.lerp(torso_v, arm_brake)


func _phase(side: int) -> Phase:
	var t: float = _t[side]
	if t < 0.0:
		return Phase.NONE
	if t < windup_time:
		return Phase.WINDUP
	if t < windup_time + strike_time:
		return Phase.STRIKE
	if t < windup_time + strike_time + retract_time:
		return Phase.RETRACT
	return Phase.NONE


## El brazo esta soltando el golpe (solo esta fase hace daño).
func is_punching(side: int) -> bool:
	return _phase(side) == Phase.STRIKE


## `body` es un brazo de este personaje que esta lanzando un puñetazo.
func is_punching_with(body: Node) -> bool:
	for side in 2:
		if is_punching(side) and (body == character.get_lower_arm(side) or body == character.get_upper_arm(side)):
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
	if _t[side] >= 0.0:
		return ARM_PRIORITY
	# guardia: el otro puño tambien arriba, salvo si esa mano esta agarrando
	if _guard > 0.0 and not character.want_grab[side]:
		return ARM_PRIORITY
	return -1


func drive_arm(side: int, _delta: float) -> void:
	var c := character
	var upper := c.get_upper_arm(side)
	var lower := c.get_lower_arm(side)
	if _phase(side) == Phase.STRIKE:
		# brazo recto y muy rigido hacia el objetivo
		var pdir: Vector3 = _aim[side]
		RagdollMuscles.pd_aim(upper, pdir, arm_frequency, 0.8, 500.0 * c.strength, c.get_torso(), c.strength, 2.0)
		RagdollMuscles.pd_aim(lower, pdir, arm_frequency, 0.8, 300.0 * c.strength, null, c.strength)
	else:
		# guardia: codo abajo y algo hacia fuera, puño delante de la barbilla
		var torso := c.get_torso()
		var shoulder := upper.global_transform * c.body.shoulder_offset
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, c.facing_yaw)
		var out := shoulder - torso.global_position
		out = (out - fwd * out.dot(fwd) - Vector3.UP * out.y).normalized()
		var elbow := shoulder + Vector3.DOWN * 0.22 + fwd * 0.15 + out * 0.05
		var fist := shoulder + fwd * 0.36 - Vector3.UP * 0.02 - out * 0.08
		# bien amortiguado: al volver del golpe el brazo no debe pasarse por encima de la cabeza
		RagdollMuscles.pd_aim(upper, (elbow - shoulder).normalized(), guard_frequency, 1.4, 300.0 * c.strength, torso, c.strength, 2.0)
		RagdollMuscles.pd_aim(lower, (fist - elbow).normalized(), guard_frequency, 1.4, 200.0 * c.strength, upper, c.strength, 1.5)
	c.arm_gravity_compensation(side, c.strength)


func reset() -> void:
	_t = [-1.0, -1.0]
	_guard = 0.0
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
