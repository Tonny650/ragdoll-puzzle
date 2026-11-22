class_name GrabAbility
extends CharacterAbility
## Brazos independientes estilo HFF: mantener el boton levanta el brazo hacia
## la camara; si la mano toca un cuerpo se crea un Generic6DOFJoint3D (rotula)
## entre la mano y el objeto. La mano solo se cierra cuando el brazo ya apunta
## a la mira, para no agarrarse a media pared mientras sube.

const ARM_PRIORITY := 10

@export var arm_reach_frequency := 20.0   ## rigidez de brazos al apuntar/agarrar
@export var arm_damping_ratio := 1.5      ## >1 = sin rebote; evita que el brazo tiemble al apuntar
@export var grab_aim_alignment := 0.85    ## cos del angulo brazo/apuntado para cerrar la mano
@export var grab_blocked_time := 0.4      ## si el brazo no llega a apuntar en este tiempo, agarra igual
@export var hand_radius := 0.14

var _joints: Array = [null, null]
var _targets: Array = [null, null]
var _raise_time := [0.0, 0.0]
var _shape := SphereShape3D.new()


func setup() -> void:
	_shape.radius = hand_radius


func physics_step(delta: float) -> void:
	var c := character
	for side in 2:
		var want: bool = c.want_grab[side] and c.strength > 0.3
		if not want:
			_raise_time[side] = 0.0
			release(side)
			continue
		if _joints[side] != null:
			if not is_instance_valid(_targets[side]):
				release(side)
			continue
		# La mano solo se cierra cuando el brazo ya apunta hacia donde se mira
		# (o lleva un rato levantado y algo lo bloquea).
		_raise_time[side] += delta
		var arm_dir := -c.get_lower_arm(side).global_basis.y
		if arm_dir.dot(c.get_aim_direction()) < grab_aim_alignment and _raise_time[side] < grab_blocked_time:
			continue
		var hand := c.get_hand_position(side)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _shape
		params.transform = Transform3D(Basis.IDENTITY, hand)
		params.collision_mask = RagdollCharacter.ALL_MASK
		params.exclude = c.own_rids
		for hit in c.get_world_3d().direct_space_state.intersect_shape(params, 6):
			var col := hit.collider as PhysicsBody3D
			if col:
				_create_grab(side, col, hand)
				break


func arm_claim_priority(side: int) -> int:
	return ARM_PRIORITY if character.want_grab[side] else -1


func drive_arm(side: int, _delta: float) -> void:
	# Brazo extendido hacia donde mira la camara (HFF)
	var c := character
	var sgn := -1.0 if side == Side.LEFT else 1.0
	var dir := (c.get_aim_direction() + Vector3(sgn * 0.12, 0, 0).rotated(Vector3.UP, c.facing_yaw)).normalized()
	var max_t := (420.0 if _joints[side] != null else 260.0) * c.strength
	RagdollMuscles.pd_aim(c.get_upper_arm(side), dir, arm_reach_frequency, arm_damping_ratio, max_t, c.get_torso(), c.strength, 2.0)
	RagdollMuscles.pd_aim(c.get_lower_arm(side), dir, arm_reach_frequency, arm_damping_ratio, max_t * 0.7, null, c.strength)
	c.arm_gravity_compensation(side, c.strength)


func _create_grab(side: int, target: PhysicsBody3D, at: Vector3) -> void:
	var c := character
	var j := Generic6DOFJoint3D.new()
	j.name = "Grab%d" % side
	c.add_child(j)
	j.global_position = at
	# Bloqueo lineal total; giro libre (la mano actua como rotula)
	for axis in ["x", "y", "z"]:
		j.set("angular_limit_%s/enabled" % axis, false)
	j.node_a = j.get_path_to(c.get_lower_arm(side))
	j.node_b = j.get_path_to(target)
	_joints[side] = j
	_targets[side] = target
	c.grabbed.emit(side, target)


func release(side: int) -> void:
	if _joints[side] != null:
		(_joints[side] as Node).queue_free()
		_joints[side] = null
		_targets[side] = null
		character.released.emit(side)


func reset() -> void:
	for side in 2:
		release(side)


func is_grabbing(side: int) -> bool:
	return _joints[side] != null


func get_grabbed(side: int) -> Node3D:
	return _targets[side]


## Punto de agarre en el mundo (null si la mano esta vacia).
func get_grab_point(side: int) -> Variant:
	return (_joints[side] as Node3D).global_position if _joints[side] != null else null
