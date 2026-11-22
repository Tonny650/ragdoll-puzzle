class_name RagdollCharacter
extends Node3D
## Nucleo de un personaje "ragdoll activo" (estilo Human Fall Flat / Gang Beasts).
##
## El cuerpo es 100% fisico: piezas RigidBody3D unidas con ConeTwistJoint3D,
## definidas en un recurso RagdollBodyDef (`body`). No hay animaciones: las
## habilidades empujan cada pieza con torques PD (ver RagdollMuscles).
##
## Este nodo solo construye el cuerpo, detecta el suelo y guarda el estado
## compartido. Todo el comportamiento vive en nodos hijo CharacterAbility que
## se ejecutan cada paso de fisica en el orden del arbol:
##   PlayerInput | AIBrain   -> rellenan la intencion (move_input, want_grab...)
##   Knockout                -> fuerza muscular y KO
##   StandSupport            -> sostenerse en pie y saltar
##   Balance                 -> torso/pelvis erguidos, cabeza
##   Locomotion              -> caminar, fase del paso
##   Legs                    -> pose de las piernas
##   Combat                  -> puñetazos
##   Arms                    -> arbitro de brazos (Combat > Climb > Grab > relajado)
##   Climb                   -> trepar (necesita Grab)
##   Grab                    -> agarrar con cada mano
## Quitar un nodo = el personaje pierde esa habilidad.

signal knocked_out
signal recovered
signal grabbed(side: int, body: Node3D)
signal released(side: int)

enum Side { LEFT = 0, RIGHT = 1 }

const GROUND_MASK := 1 | 4          # world + props
const ALL_MASK := 1 | 2 | 4         # world + ragdoll + props
const RAGDOLL_LAYER := 2
const DEFAULT_BODY := preload("res://data/bodies/humanoid.tres")

@export var body: RagdollBodyDef = DEFAULT_BODY  ## piezas, articulaciones y medidas del cuerpo
@export var visual_scene: PackedScene             ## modelo con un nodo por pieza (mismo nombre)
@export var kill_height := -25.0                  ## por debajo de esta altura reaparece

# --- estado compartido (lo leen y escriben las habilidades) ------------------
var bodies := {}                 # nombre -> RigidBody3D
var joints: Array[Joint3D] = []
var abilities: Array[CharacterAbility] = []
var own_rids: Array[RID] = []    # para excluir el propio cuerpo de consultas fisicas
var total_mass := 0.0
var strength := 1.0              # 0 = flacido, 1 = musculos al maximo
var grounded := false
var ground_distance := INF
var stand_height := 0.9          # lo fija StandSupport; se usa para decidir `grounded`
var air_time := 0.0              # segundos sin apoyo (StandSupport)
var walk_phase := 0.0            # fase del ciclo de paso (Locomotion)
var gait_amplitude := 0.0        # amplitud del paso 0..0.75 (Locomotion)
var climbing := false            # colgado y trepando (Climb)
var mantling := false            # trepando y pasando el borde: pecho por encima del agarre (Climb)
var climb_anchor := Vector3.ZERO

# --- intencion (la rellena el controlador: jugador o IA) ---------------------
var move_input := Vector3.ZERO   # direccion deseada en mundo (y = 0), longitud <= 1
var facing_yaw := 0.0
var aim_pitch := 0.0             # -1.4 (abajo) .. 1.4 (arriba)
var want_grab := [false, false]
var want_jump := false
var want_limp := false
var want_punch := false          # peticion de un solo uso (la consume Combat)

var _spawn_xform := Transform3D.IDENTITY
var _rest_local := {}            # nombre -> Transform3D en espacio del personaje


const GROUP := &"ragdoll_characters"


func _ready() -> void:
	add_to_group(GROUP)
	_spawn_xform = global_transform
	facing_yaw = global_rotation.y
	if body == null:
		body = DEFAULT_BODY
	var missing := body.missing_parts()
	if not missing.is_empty():
		push_error("%s: al cuerpo '%s' le faltan piezas %s" % [name, body.resource_path, missing])
		set_physics_process(false)
		return
	_build_body()
	_attach_visuals()
	for child in get_children():
		if child is CharacterAbility:
			child.character = self
			abilities.append(child)
	for a in abilities:
		a.setup()


# =============================================================================
# Construccion
# =============================================================================
func _build_body() -> void:
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = body.friction
	phys_mat.bounce = 0.0

	for def in body.parts:
		var part_name := String(def.name)
		var rb := RigidBody3D.new()
		rb.name = part_name
		rb.mass = def.mass
		rb.position = def.position
		rb.collision_layer = RAGDOLL_LAYER
		rb.collision_mask = ALL_MASK
		rb.physics_material_override = phys_mat
		rb.can_sleep = false
		rb.linear_damp = body.linear_damp
		rb.angular_damp = body.angular_damp
		rb.continuous_cd = def.continuous_cd
		rb.set_meta("ragdoll_owner", self)
		add_child(rb)

		var col := CollisionShape3D.new()
		if def.shape == RagdollPartDef.Shape.SPHERE:
			var s := SphereShape3D.new()
			s.radius = def.radius
			col.shape = s
		else:
			var c := CapsuleShape3D.new()
			c.radius = def.radius
			c.height = def.height
			col.shape = c
		col.position = def.offset
		rb.add_child(col)

		if def.has_foot:
			var foot := CollisionShape3D.new()
			var fb := BoxShape3D.new()
			fb.size = def.foot_size
			foot.shape = fb
			foot.position = def.foot_offset
			rb.add_child(foot)

		bodies[part_name] = rb
		_rest_local[part_name] = Transform3D(Basis.IDENTITY, def.position)
		total_mass += def.mass
		own_rids.append(rb.get_rid())

	# El personaje no colisiona consigo mismo (mas estable), si con otros.
	var list := bodies.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			(list[i] as RigidBody3D).add_collision_exception_with(list[j])

	for jd in body.joints:
		var j := ConeTwistJoint3D.new()
		j.name = "%s_%s" % [jd.parent, jd.child]
		add_child(j)
		# El eje de twist (X local) apunta a lo largo del hueso (hacia abajo).
		j.transform = Transform3D(Basis.from_euler(Vector3(0, 0, -PI * 0.5)), jd.anchor)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, jd.swing_span)
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, jd.twist_span)
		j.node_a = j.get_path_to(bodies[String(jd.parent)])
		j.node_b = j.get_path_to(bodies[String(jd.child)])
		joints.append(j)


func _attach_visuals() -> void:
	var visual_root: Node = visual_scene.instantiate() if visual_scene else null
	for def in body.parts:
		var part_name := String(def.name)
		var rb: RigidBody3D = bodies[part_name]
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var src: MeshInstance3D = null
		if visual_root:
			src = visual_root.find_child(part_name, true, false) as MeshInstance3D
			if src == null:
				var holder := visual_root.find_child(part_name, true, false)
				if holder:
					for c in holder.get_children():
						if c is MeshInstance3D:
							src = c
							break
		mi.mesh = src.mesh if src else _fallback_mesh(def)
		rb.add_child(mi)
	if visual_root:
		visual_root.free()


func _fallback_mesh(def: RagdollPartDef) -> Mesh:
	if def.shape == RagdollPartDef.Shape.SPHERE:
		var s := SphereMesh.new()
		s.radius = def.radius
		s.height = def.radius * 2.0
		return s
	var c := CapsuleMesh.new()
	c.radius = def.radius
	c.height = def.height
	return c


# =============================================================================
# Bucle principal
# =============================================================================
func _physics_process(delta: float) -> void:
	_update_ground()
	for a in abilities:
		if a.enabled:
			a.physics_step(delta)
	if get_pelvis().global_position.y < kill_height:
		respawn()


func _update_ground() -> void:
	var pelvis := get_pelvis()
	var from := pelvis.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, GROUND_MASK | RAGDOLL_LAYER, own_rids)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		ground_distance = from.y - (hit.position as Vector3).y
		grounded = ground_distance < stand_height + 0.3
	else:
		ground_distance = INF
		grounded = false


## Torque que anula el peso del brazo (hombro y codo) para que los musculos
## solo tengan que corregir la direccion: sin esto el brazo extendido se
## cuelga ~30 grados. Lo usan las habilidades que extienden el brazo.
func arm_gravity_compensation(side: int, gain: float) -> void:
	if gain <= 0.0:
		return
	var upper := get_upper_arm(side)
	var lower := get_lower_arm(side)
	var torso := get_torso()
	var lift := Vector3.UP * 9.8
	var shoulder := upper.global_transform * body.shoulder_offset
	var elbow := upper.global_transform * body.elbow_offset
	# codo: sostiene el antebrazo
	var t_elbow := (lower.global_position - elbow).cross(lift * lower.mass) * gain
	lower.apply_torque(t_elbow)
	upper.apply_torque(-t_elbow)
	# hombro: sostiene brazo + antebrazo
	var t_shoulder := ((upper.global_position - shoulder).cross(lift * upper.mass)
		+ (lower.global_position - shoulder).cross(lift * lower.mass)) * gain
	upper.apply_torque(t_shoulder)
	torso.apply_torque(-t_shoulder)


# =============================================================================
# Habilidades
# =============================================================================
## Primera habilidad hija cuyo script es (o hereda de) `type`, o null.
func get_ability(type: Script) -> CharacterAbility:
	for a in abilities:
		if is_instance_of(a, type):
			return a
	return null


func is_player() -> bool:
	var c := get_ability(PlayerInputController)
	return c != null and c.enabled


# --- fachada: delega en las habilidades si existen ---------------------------
func knock_out(duration: float = -1.0) -> void:
	var k := get_ability(KnockoutAbility) as KnockoutAbility
	if k:
		k.knock_out(duration)


func is_knocked_out() -> bool:
	var k := get_ability(KnockoutAbility) as KnockoutAbility
	return k != null and k.is_knocked_out()


func punch() -> void:
	want_punch = true


func release(side: int) -> void:
	var g := get_ability(GrabAbility) as GrabAbility
	if g:
		g.release(side)


func is_grabbing(side: int) -> bool:
	var g := get_ability(GrabAbility) as GrabAbility
	return g != null and g.is_grabbing(side)


func get_grabbed(side: int) -> Node3D:
	var g := get_ability(GrabAbility) as GrabAbility
	return g.get_grabbed(side) if g else null


# =============================================================================
# Utilidades publicas
# =============================================================================
## Cambia el punto de reaparicion (no mueve al personaje; llama a respawn()).
func set_spawn(xform: Transform3D) -> void:
	_spawn_xform = xform


func respawn() -> void:
	for a in abilities:
		a.reset()
	strength = 1.0
	facing_yaw = _spawn_xform.basis.get_euler().y
	for part_name: String in bodies:
		var rb: RigidBody3D = bodies[part_name]
		var xf: Transform3D = _spawn_xform * _rest_local[part_name]
		PhysicsServer3D.body_set_state(rb.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		rb.global_transform = xf
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO


func get_pelvis() -> RigidBody3D:
	return bodies.pelvis


func get_torso() -> RigidBody3D:
	return bodies.torso


func get_head() -> RigidBody3D:
	return bodies.head


func get_upper_arm(side: int) -> RigidBody3D:
	return bodies["upper_arm_l" if side == Side.LEFT else "upper_arm_r"]


func get_lower_arm(side: int) -> RigidBody3D:
	return bodies["lower_arm_l" if side == Side.LEFT else "lower_arm_r"]


func get_hand_position(side: int) -> Vector3:
	return get_lower_arm(side).global_transform * body.hand_offset


## Centro del pie (la caja de colision del pie) de la pieza `shin_name`.
func get_foot_position(shin_name: StringName) -> Vector3:
	var shin: RigidBody3D = bodies[String(shin_name)]
	for def in body.parts:
		if def.name == shin_name:
			return shin.global_transform * def.foot_offset
	return shin.global_position


func get_aim_direction() -> Vector3:
	return (Quaternion(Vector3.UP, facing_yaw) * Quaternion(Vector3.RIGHT, aim_pitch)) * Vector3.FORWARD


func get_center() -> Vector3:
	return get_torso().global_position


func get_linear_velocity() -> Vector3:
	return get_torso().linear_velocity
