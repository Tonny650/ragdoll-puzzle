class_name RagdollCharacter
extends Node3D
## Controlador de personaje "ragdoll activo" (estilo Human Fall Flat / Gang Beasts).
##
## El cuerpo es 100% fisico: 11 RigidBody3D unidos con ConeTwistJoint3D.
## No hay animaciones: cada parte se empuja hacia una pose objetivo con
## torques PD (proporcional-derivativo), y un "musculo de equilibrio" mantiene
## erguidos pelvis y torso. Al bajar la fuerza muscular (KO, Q) el personaje
## se convierte en un ragdoll flacido y luego se levanta solo.
##
## Controles (jugador): WASD mover, raton mirar, Espacio saltar,
## clic izq/der levantar y agarrar con mano izq/der, F puñetazo,
## Q dejarse caer (flacido), R reaparecer.

signal knocked_out
signal recovered
signal grabbed(side: int, body: Node3D)
signal released(side: int)

enum Side { LEFT = 0, RIGHT = 1 }

const GROUND_MASK := 1 | 4          # world + props
const ALL_MASK := 1 | 2 | 4         # world + ragdoll + props
const RAGDOLL_LAYER := 2

## Definicion del cuerpo. DEBE coincidir con art_source/build_characters.py.
## pos = centro del cuerpo rigido en reposo (personaje mirando a -Z).
const PARTS := {
	"pelvis":      {"pos": Vector3(0.0, 0.92, 0.0),   "mass": 10.0, "shape": "sphere",  "r": 0.17},
	"torso":       {"pos": Vector3(0.0, 1.22, 0.0),   "mass": 14.0, "shape": "capsule", "r": 0.22, "h": 0.58},
	"head":        {"pos": Vector3(0.0, 1.68, 0.0),   "mass": 4.5,  "shape": "sphere",  "r": 0.2},
	"upper_arm_l": {"pos": Vector3(-0.31, 1.30, 0.0), "mass": 2.5,  "shape": "capsule", "r": 0.075, "h": 0.34},
	"lower_arm_l": {"pos": Vector3(-0.31, 0.98, 0.0), "mass": 2.0,  "shape": "capsule", "r": 0.085, "h": 0.42, "off": Vector3(0, -0.05, 0)},
	"upper_arm_r": {"pos": Vector3(0.31, 1.30, 0.0),  "mass": 2.5,  "shape": "capsule", "r": 0.075, "h": 0.34},
	"lower_arm_r": {"pos": Vector3(0.31, 0.98, 0.0),  "mass": 2.0,  "shape": "capsule", "r": 0.085, "h": 0.42, "off": Vector3(0, -0.05, 0)},
	"thigh_l":     {"pos": Vector3(-0.11, 0.62, 0.0), "mass": 6.0,  "shape": "capsule", "r": 0.095, "h": 0.40},
	"shin_l":      {"pos": Vector3(-0.11, 0.24, 0.0), "mass": 4.0,  "shape": "capsule", "r": 0.085, "h": 0.36, "foot": true},
	"thigh_r":     {"pos": Vector3(0.11, 0.62, 0.0),  "mass": 6.0,  "shape": "capsule", "r": 0.095, "h": 0.40},
	"shin_r":      {"pos": Vector3(0.11, 0.24, 0.0),  "mass": 4.0,  "shape": "capsule", "r": 0.085, "h": 0.36, "foot": true},
}

## [padre, hijo, ancla (espacio local del personaje), swing (rad), twist (rad)]
const JOINTS := [
	["pelvis", "torso", Vector3(0.0, 1.04, 0.0), 0.6, 0.5],
	["torso", "head", Vector3(0.0, 1.50, 0.0), 0.7, 0.8],
	["torso", "upper_arm_l", Vector3(-0.31, 1.46, 0.0), 2.7, 0.9],
	["upper_arm_l", "lower_arm_l", Vector3(-0.31, 1.13, 0.0), 1.6, 0.4],
	["torso", "upper_arm_r", Vector3(0.31, 1.46, 0.0), 2.7, 0.9],
	["upper_arm_r", "lower_arm_r", Vector3(0.31, 1.13, 0.0), 1.6, 0.4],
	["pelvis", "thigh_l", Vector3(-0.11, 0.84, 0.0), 1.6, 0.3],
	["thigh_l", "shin_l", Vector3(-0.11, 0.43, 0.0), 1.5, 0.2],
	["pelvis", "thigh_r", Vector3(0.11, 0.84, 0.0), 1.6, 0.3],
	["thigh_r", "shin_r", Vector3(0.11, 0.43, 0.0), 1.5, 0.2],
]

const HAND_OFFSET := Vector3(0.0, -0.18, 0.0)  # mano, en local del antebrazo

@export var visual_scene: PackedScene
@export var player_controlled := true

@export_group("Movimiento")
@export var max_speed := 3.6
@export var acceleration := 9.0
@export var air_control := 0.25
@export var jump_speed := 4.8
@export var stand_height := 0.9           ## altura objetivo de la pelvis sobre el suelo
@export var step_frequency := 1.9         ## pasos por segundo a velocidad maxima

@export_group("Musculos")
@export var upright_stiffness := 1600.0   ## Nm/rad para mantener el torso vertical
@export var upright_damping := 160.0
@export var limb_frequency := 16.0        ## rigidez de piernas/brazos (rad/s)
@export var arm_reach_frequency := 20.0   ## rigidez de brazos al apuntar/agarrar
@export var arm_damping_ratio := 1.5      ## >1 = sin rebote; evita que el brazo tiemble al apuntar
@export var recover_time := 1.6           ## segundos en recuperar la fuerza tras un KO

@export_group("Trepar")
@export var climb_strength := 1.0         ## multiplicador de la fuerza para izarse
@export var climb_min_pitch := 0.2        ## cuanto hay que mirar hacia arriba para trepar
@export var climb_min_anchor_mass := 40.0 ## masa minima de un RigidBody para poder trepar por el
@export var grab_aim_alignment := 0.85    ## cos del angulo brazo/apuntado para cerrar la mano
@export var grab_blocked_time := 0.4      ## si el brazo no llega a apuntar en este tiempo, agarra igual

@export_group("Combate")
@export var knockout_speed := 7.5         ## velocidad relativa de impacto en la cabeza que noquea
@export var knockout_duration := 3.0
@export var punch_impulse := 14.0

@export_group("IA (solo NPC)")
@export var ai_target_path: NodePath      ## si se asigna, el NPC persigue y golpea a este personaje
@export var ai_aggro_radius := 7.0

@export_group("Debug")
@export var kill_height := -25.0

# --- estado ------------------------------------------------------------------
var bodies := {}                 # nombre -> RigidBody3D
var joints: Array[Joint3D] = []
var total_mass := 0.0
var strength := 1.0              # 0 = flacido, 1 = musculos al maximo
var grounded := false
var ground_distance := INF

# entradas (las rellena el jugador o la IA)
var move_input := Vector3.ZERO   # direccion deseada en mundo (y = 0), longitud <= 1
var facing_yaw := 0.0
var aim_pitch := 0.0             # -1.4 (abajo) .. 1.4 (arriba)
var want_grab := [false, false]
var want_jump := false
var want_limp := false

var _spawn_xform := Transform3D.IDENTITY
var _rest_local := {}            # nombre -> Transform3D en espacio del personaje
var _own_rids: Array[RID] = []
var _grab_joints: Array = [null, null]
var _grab_targets: Array = [null, null]
var _punch_timers := [0.0, 0.0]
var _raise_time := [0.0, 0.0]
var _next_punch_side := Side.RIGHT
var _walk_phase := 0.0
var _jump_cooldown := 0.0
var _no_support_timer := 0.0
var _ko_timer := 0.0
var _ai_punch_cooldown := 1.0
var _grab_shape := SphereShape3D.new()
var _ai_target: RagdollCharacter
var climbing := false             # colgado y trepando (lo lee la locomocion)
var climb_anchor := Vector3.ZERO


func _ready() -> void:
	_spawn_xform = global_transform
	facing_yaw = global_rotation.y
	_grab_shape.radius = 0.14
	_build_body()
	_attach_visuals()
	if not ai_target_path.is_empty():
		_ai_target = get_node_or_null(ai_target_path) as RagdollCharacter
	if player_controlled:
		add_to_group("player")


# =============================================================================
# Construccion
# =============================================================================
func _build_body() -> void:
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.9
	phys_mat.bounce = 0.0

	for part_name: String in PARTS:
		var def: Dictionary = PARTS[part_name]
		var rb := RigidBody3D.new()
		rb.name = part_name
		rb.mass = def.mass
		rb.position = def.pos
		rb.collision_layer = RAGDOLL_LAYER
		rb.collision_mask = ALL_MASK
		rb.physics_material_override = phys_mat
		rb.can_sleep = false
		rb.linear_damp = 0.05
		rb.angular_damp = 1.5
		rb.continuous_cd = part_name.begins_with("lower_arm") or part_name == "head"
		rb.set_meta("ragdoll_owner", self)
		add_child(rb)

		var col := CollisionShape3D.new()
		if def.shape == "sphere":
			var s := SphereShape3D.new()
			s.radius = def.r
			col.shape = s
		else:
			var c := CapsuleShape3D.new()
			c.radius = def.r
			c.height = def.h
			col.shape = c
		col.position = def.get("off", Vector3.ZERO)
		rb.add_child(col)

		if def.get("foot", false):
			var foot := CollisionShape3D.new()
			var fb := BoxShape3D.new()
			fb.size = Vector3(0.13, 0.09, 0.26)
			foot.shape = fb
			foot.position = Vector3(0.0, -0.17, -0.05)
			rb.add_child(foot)

		bodies[part_name] = rb
		_rest_local[part_name] = Transform3D(Basis.IDENTITY, def.pos)
		total_mass += def.mass
		_own_rids.append(rb.get_rid())

	# El personaje no colisiona consigo mismo (mas estable), si con otros.
	var list := bodies.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			(list[i] as RigidBody3D).add_collision_exception_with(list[j])

	# Articulaciones
	for jd: Array in JOINTS:
		var j := ConeTwistJoint3D.new()
		j.name = "%s_%s" % [jd[0], jd[1]]
		add_child(j)
		# El eje de twist (X local) apunta a lo largo del hueso (hacia abajo).
		j.transform = Transform3D(Basis.from_euler(Vector3(0, 0, -PI * 0.5)), jd[2])
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, jd[3])
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, jd[4])
		j.node_a = j.get_path_to(bodies[jd[0]])
		j.node_b = j.get_path_to(bodies[jd[1]])
		joints.append(j)

	# Cabeza: detectar golpes para el KO
	var head: RigidBody3D = bodies.head
	head.contact_monitor = true
	head.max_contacts_reported = 4
	head.body_entered.connect(_on_head_hit)


func _attach_visuals() -> void:
	var visual_root: Node = visual_scene.instantiate() if visual_scene else null
	for part_name: String in PARTS:
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
		if src:
			mi.mesh = src.mesh
		else:
			mi.mesh = _fallback_mesh(PARTS[part_name])
		rb.add_child(mi)
	if visual_root:
		visual_root.free()


func _fallback_mesh(def: Dictionary) -> Mesh:
	if def.shape == "sphere":
		var s := SphereMesh.new()
		s.radius = def.r
		s.height = def.r * 2.0
		return s
	var c := CapsuleMesh.new()
	c.radius = def.r
	c.height = def.h
	return c


# =============================================================================
# Bucle principal
# =============================================================================
func _physics_process(delta: float) -> void:
	if player_controlled:
		_read_player_input()
	elif _ai_target:
		_run_ai(delta)

	_update_strength(delta)
	_update_ground()
	_apply_support(delta)
	_apply_balance()
	_apply_locomotion(delta)
	_apply_pose(delta)
	_apply_climb()
	_update_grabs()

	if get_pelvis().global_position.y < kill_height:
		respawn()


func _unhandled_input(event: InputEvent) -> void:
	if not player_controlled:
		return
	if event.is_action_pressed("punch"):
		punch()
	elif event.is_action_pressed("respawn"):
		respawn()


# =============================================================================
# Entrada
# =============================================================================
func _read_player_input() -> void:
	var cam := get_viewport().get_camera_3d()
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if cam:
		var yaw := cam.global_rotation.y
		facing_yaw = yaw
		aim_pitch = clampf(cam.global_rotation.x * 1.3 + 0.15, -1.35, 1.4)
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		var right := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
		move_input = (right * input.x + fwd * input.y).limit_length(1.0)
	else:
		move_input = Vector3(input.x, 0, -input.y).limit_length(1.0)
	want_grab[Side.LEFT] = Input.is_action_pressed("grab_left")
	want_grab[Side.RIGHT] = Input.is_action_pressed("grab_right")
	want_jump = Input.is_action_pressed("jump")
	want_limp = Input.is_action_pressed("go_limp")


func _run_ai(delta: float) -> void:
	move_input = Vector3.ZERO
	want_grab = [false, false]
	_ai_punch_cooldown -= delta
	if _ai_target.is_knocked_out():
		return
	var to_target := _ai_target.get_center() - get_center()
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > ai_aggro_radius or dist < 0.01:
		return
	facing_yaw = atan2(-to_target.x, -to_target.z)
	aim_pitch = 0.1
	if dist > 1.1:
		move_input = to_target / dist * 0.7
	elif _ai_punch_cooldown <= 0.0:
		punch()
		_ai_punch_cooldown = randf_range(0.8, 1.6)


# =============================================================================
# Fuerza muscular / KO
# =============================================================================
func _update_strength(delta: float) -> void:
	if _ko_timer > 0.0:
		_ko_timer -= delta
		strength = 0.0
		if _ko_timer <= 0.0:
			recovered.emit()
		return
	var target := 0.0 if want_limp else 1.0
	strength = move_toward(strength, target, delta / maxf(recover_time, 0.01) if target > strength else delta * 8.0)


func knock_out(duration: float = -1.0) -> void:
	if _ko_timer <= 0.0:
		knocked_out.emit()
	_ko_timer = maxf(_ko_timer, duration if duration > 0.0 else knockout_duration)
	release(Side.LEFT)
	release(Side.RIGHT)


func is_knocked_out() -> bool:
	return _ko_timer > 0.0


func _on_head_hit(other: Node) -> void:
	if other is RigidBody3D and other.get_meta("ragdoll_owner", null) == self:
		return
	var other_vel := Vector3.ZERO
	if other is RigidBody3D:
		other_vel = (other as RigidBody3D).linear_velocity
	elif other.has_method("get_platform_velocity"):
		other_vel = other.get_platform_velocity()
	var rel := (get_head().linear_velocity - other_vel).length()
	if rel >= knockout_speed:
		knock_out()


# =============================================================================
# Suelo, soporte y equilibrio
# =============================================================================
func _update_ground() -> void:
	var pelvis := get_pelvis()
	var from := pelvis.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, GROUND_MASK | RAGDOLL_LAYER, _own_rids)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		ground_distance = from.y - (hit.position as Vector3).y
		grounded = ground_distance < stand_height + 0.3
	else:
		ground_distance = INF
		grounded = false


func _apply_support(delta: float) -> void:
	# "Muelle" vertical que sostiene el peso cuando hay suelo debajo (como HFF).
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	if not grounded or strength <= 0.01:
		_no_support_timer += delta
		return
	_no_support_timer = 0.0
	var pelvis := get_pelvis()
	var torso := get_torso()
	var vy := (pelvis.linear_velocity.y + torso.linear_velocity.y) * 0.5
	var err := stand_height - ground_distance
	var g := 9.8
	var accel := g + err * 120.0 - vy * 18.0
	var force := clampf(accel, 0.0, g * 2.6) * total_mass * strength
	if _jump_cooldown > 0.25:
		force = 0.0
	pelvis.apply_central_force(Vector3.UP * force * 0.55)
	torso.apply_central_force(Vector3.UP * force * 0.45)

	if want_jump and _jump_cooldown <= 0.0 and strength > 0.8:
		_jump_cooldown = 0.6
		for rb: RigidBody3D in bodies.values():
			rb.linear_velocity.y = maxf(rb.linear_velocity.y, jump_speed)


func _apply_balance() -> void:
	if strength <= 0.01:
		return
	var yaw_q := Quaternion(Vector3.UP, facing_yaw)
	var lean := 0.0
	if climbing:
		# Colgado: doblarse hacia delante sobre el borde al empujar (negativo = adelante).
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, facing_yaw)
		lean = -0.75 if move_input.dot(fwd) > 0.3 else 0.0
	elif want_grab[0] or want_grab[1]:
		lean = clampf(aim_pitch, -0.9, 0.5) * 0.35
	lean -= move_input.length() * 0.08
	var torso_target := yaw_q * Quaternion(Vector3.RIGHT, lean)
	var k := upright_stiffness * strength * (total_mass / 60.0)
	var d := upright_damping * strength * (total_mass / 60.0)
	_upright_torque(get_torso(), torso_target, k, d, 2200.0)
	_upright_torque(get_pelvis(), yaw_q, k * 0.6, d * 0.6, 1400.0)
	# cabeza mirando hacia donde se apunta
	var head_target := yaw_q * Quaternion(Vector3.RIGHT, clampf(aim_pitch, -0.8, 0.8) * 0.6)
	_pd_toward(get_head(), head_target, 10.0, 1.0, 60.0 * strength, get_torso(), strength)


func _upright_torque(body: RigidBody3D, target: Quaternion, k: float, d: float, max_torque: float) -> void:
	var err := _rotation_error(body.global_basis.get_rotation_quaternion(), target)
	var w := body.angular_velocity
	var damp := w * d * _stable_damping_scale(body, w, d)
	var torque := (err * k - damp).limit_length(max_torque)
	body.apply_torque(torque)


## Factor (0..1) que limita una amortiguacion explicita `-d*w` para que en un
## paso de fisica no frene mas del 70 % de la velocidad. Sin esto, en piezas de
## poca inercia (giro vertical del torso/pelvis) la amortiguacion se pasaba de
## largo cada paso e invertia el giro: temblor permanente de 15-20 rad/s.
func _stable_damping_scale(body: RigidBody3D, w: Vector3, d: float) -> float:
	return _damping_scale(body, w, w * d, 0.7)


## Igual para un torque de amortiguacion ya calculado: cuanto frenaria a `body`
## en un paso, como fraccion de `w`. Devuelve el factor para no pasar de `max_frac`.
func _damping_scale(body: RigidBody3D, w: Vector3, damp_torque: Vector3, max_frac: float) -> float:
	var w2 := w.length_squared()
	if w2 < 1e-8:
		return 1.0
	var dt := get_physics_process_delta_time()
	var decel := (body.get_inverse_inertia_tensor() * damp_torque).dot(w) / w2 * dt
	return minf(1.0, max_frac / decel) if decel > 0.0 else 1.0


## Limite de amortiguacion de los musculos de las extremidades. La reaccion cae
## sobre el padre (p. ej. ambas piernas sobre la pelvis), asi que alli se limita
## a un 35 % por musculo para que la suma de varios siga siendo estable.
func _pd_damping_scale(body: RigidBody3D, counter: RigidBody3D, rel_w: Vector3, d_t: Vector3) -> float:
	var k := _damping_scale(body, rel_w, d_t, 0.7)
	if counter:
		k = minf(k, _damping_scale(counter, rel_w, d_t, 0.35))
	return k


# =============================================================================
# Locomocion
# =============================================================================
func _apply_locomotion(delta: float) -> void:
	var pelvis := get_pelvis()
	var torso := get_torso()
	var vel := (pelvis.linear_velocity + torso.linear_velocity) * 0.5
	var vel_h := Vector3(vel.x, 0.0, vel.z)
	var desired := move_input * max_speed
	var control := (1.0 if grounded else air_control) * strength
	if control <= 0.0:
		return
	var force := (desired - vel_h) * acceleration * total_mass * control
	if move_input.length_squared() < 0.01 and not grounded:
		force = Vector3.ZERO
	force = force.limit_length(total_mass * 30.0)
	if climbing:
		# No apretarse contra la pared: la friccion impediria subir.
		force *= 0.1
	pelvis.apply_central_force(force * 0.5)
	torso.apply_central_force(force * 0.5)

	var speed01 := clampf(vel_h.length() / max_speed, 0.0, 1.0)
	if grounded and move_input.length_squared() > 0.01:
		_walk_phase = fmod(_walk_phase + delta * TAU * step_frequency * maxf(speed01, 0.45), TAU)
	else:
		_walk_phase = lerpf(_walk_phase, 0.0 if _walk_phase < PI else TAU, delta * 4.0)


# =============================================================================
# Pose: piernas, brazos (PD relativos al padre)
# =============================================================================
func _apply_pose(delta: float) -> void:
	if strength <= 0.01:
		return
	var pelvis := get_pelvis()
	var torso := get_torso()
	var moving := move_input.length() > 0.1
	var amp := 0.0
	if grounded and moving:
		var vel := pelvis.linear_velocity
		amp = clampf(Vector2(vel.x, vel.z).length() / max_speed, 0.35, 1.0) * 0.75

	# --- Piernas ---------------------------------------------------------------
	for side in 2:
		var sfx := "_l" if side == Side.LEFT else "_r"
		var ph := _walk_phase + (0.0 if side == Side.LEFT else PI)
		var thigh_pitch := sin(ph) * amp
		var knee := -maxf(0.0, cos(ph)) * amp * 1.3 - 0.05
		if climbing:
			# trepando: rodillas arriba para subirlas al borde (no engancharse en la pared)
			thigh_pitch = 0.7 if side == Side.LEFT else 0.5
			knee = -1.0
		elif not grounded and _no_support_timer > 0.15:
			# en el aire: piernas algo recogidas
			thigh_pitch = 0.35 if side == Side.LEFT else 0.15
			knee = -0.6
		var thigh: RigidBody3D = bodies["thigh" + sfx]
		var shin: RigidBody3D = bodies["shin" + sfx]
		var spread := 0.04 if side == Side.RIGHT else -0.04
		var thigh_t := pelvis.global_basis.get_rotation_quaternion() * Quaternion.from_euler(Vector3(thigh_pitch, 0, spread))
		_pd_toward(thigh, thigh_t, limb_frequency * 2.0, 1.0, 600.0 * strength, pelvis, strength, 2.2)
		var shin_t := thigh.global_basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, knee)
		_pd_toward(shin, shin_t, limb_frequency * 2.0, 1.0, 350.0 * strength, thigh, strength, 1.4)

	# --- Brazos ----------------------------------------------------------------
	var yaw_q := Quaternion(Vector3.UP, facing_yaw)
	var aim_dir := (yaw_q * Quaternion(Vector3.RIGHT, aim_pitch)) * Vector3.FORWARD
	for side in 2:
		_punch_timers[side] = maxf(0.0, _punch_timers[side] - delta)
		var sfx := "_l" if side == Side.LEFT else "_r"
		var upper: RigidBody3D = bodies["upper_arm" + sfx]
		var lower: RigidBody3D = bodies["lower_arm" + sfx]
		var sgn := -1.0 if side == Side.LEFT else 1.0
		if _punch_timers[side] > 0.0:
			# Puñetazo: brazo recto y muy rigido hacia delante
			var pdir := (yaw_q * Quaternion(Vector3.RIGHT, clampf(aim_pitch, -0.3, 0.4))) * Vector3.FORWARD
			_pd_aim(upper, pdir, arm_reach_frequency * 1.6, 0.8, 500.0 * strength, torso, strength, 2.0)
			_pd_aim(lower, pdir, arm_reach_frequency * 1.6, 0.8, 300.0 * strength, null, strength)
			_arm_gravity_compensation(side, strength)
		elif want_grab[side] and _is_climb_anchor(side):
			# Colgado de algo fijo: el brazo se alinea con el agarre en vez de
			# apuntar a la camara, para no empujar el cuerpo hacia abajo.
			var shoulder := upper.global_transform * Vector3(0.0, 0.16, 0.0)
			var to_hand := (_grab_joints[side] as Node3D).global_position - shoulder
			if to_hand.length_squared() > 1e-4:
				var hdir := to_hand.normalized()
				_pd_aim(upper, hdir, arm_reach_frequency * 0.6, 1.0, 140.0 * strength, torso, strength, 2.0)
				_pd_aim(lower, hdir, arm_reach_frequency * 0.6, 1.0, 100.0 * strength, null, strength)
		elif want_grab[side]:
			# Brazo extendido hacia donde mira la camara (HFF)
			var dir := (aim_dir + Vector3(sgn * 0.12, 0, 0).rotated(Vector3.UP, facing_yaw)).normalized()
			var holding := _grab_joints[side] != null
			var max_t := (420.0 if holding else 260.0) * strength
			_pd_aim(upper, dir, arm_reach_frequency, arm_damping_ratio, max_t, torso, strength, 2.0)
			_pd_aim(lower, dir, arm_reach_frequency, arm_damping_ratio, max_t * 0.7, null, strength)
			_arm_gravity_compensation(side, strength)
		else:
			# Brazos relajados, balanceo al caminar
			var swing := -sin(_walk_phase + (0.0 if side == Side.LEFT else PI)) * amp * 0.7
			var ut := torso.global_basis.get_rotation_quaternion() * Quaternion.from_euler(Vector3(swing, 0, sgn * 0.12))
			_pd_toward(upper, ut, limb_frequency * 0.6, 1.0, 60.0 * strength, torso, strength * 0.6, 2.0)
			var lt := upper.global_basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.25)
			_pd_toward(lower, lt, limb_frequency * 0.6, 1.0, 30.0 * strength, upper, strength * 0.6)


# =============================================================================
# Trepar (estilo HFF)
# =============================================================================
## Agarrado a algo fijo + mirando hacia arriba: los brazos izan el cuerpo.
## Si ademas se empuja hacia delante, el pecho sube por encima del agarre y el
## cuerpo se desplaza sobre el borde ("mantle"). Soltar al estar arriba.
func _apply_climb() -> void:
	var holds := 0
	var anchor := Vector3.ZERO
	for side in 2:
		if want_grab[side] and _is_climb_anchor(side):
			holds += 1
			anchor += (_grab_joints[side] as Node3D).global_position
	if holds == 0 or strength < 0.3 or aim_pitch < climb_min_pitch:
		climbing = false
		return
	anchor /= holds
	climbing = true
	climb_anchor = anchor
	var torso := get_torso()
	var pelvis := get_pelvis()
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, facing_yaw)
	var pushing := move_input.dot(fwd) > 0.3
	var target_y := anchor.y + (0.95 if pushing else 0.35)
	var vy := (torso.linear_velocity.y + pelvis.linear_velocity.y) * 0.5
	var accel := 9.8 + (target_y - torso.global_position.y) * 25.0 - vy * 8.0
	var hands := 0.6 + 0.2 * holds   # una mano iza menos que dos
	var lift := clampf(accel, 0.0, 9.8 * 2.2) * total_mass * strength * hands * climb_strength
	torso.apply_central_force(Vector3.UP * lift * 0.6)
	pelvis.apply_central_force(Vector3.UP * lift * 0.4)
	if pushing:
		var above := torso.global_position.y - anchor.y
		if above > 0.1:
			# Pasar el borde: empujar sobre todo la cadera hacia delante...
			var mantle := clampf(above * 2.0, 0.0, 1.0) * strength
			var f := fwd * total_mass * 18.0 * mantle
			torso.apply_central_force(f * 0.4)
			pelvis.apply_central_force(f * 0.6)
			# ...y subirla por encima de la arista para que no se enganche en ella.
			var hip_err := (anchor.y + 0.3) - pelvis.global_position.y
			if hip_err > 0.0:
				pelvis.apply_central_force(Vector3.UP * total_mass * minf(hip_err * 40.0, 12.0) * mantle)


## Solo se trepa por cosas fijas o muy pesadas (no por una caja que llevas).
func _is_climb_anchor(side: int) -> bool:
	if _grab_joints[side] == null:
		return false
	var target = _grab_targets[side]
	if not is_instance_valid(target):
		return false
	if target is StaticBody3D:  # incluye AnimatableBody3D (puertas, plataformas)
		return true
	return target is RigidBody3D and (target as RigidBody3D).mass >= climb_min_anchor_mass


## Torque que anula el peso del brazo (hombro y codo) para que el PD solo tenga
## que corregir la direccion: sin esto el brazo extendido se cuelga ~30 grados.
func _arm_gravity_compensation(side: int, gain: float) -> void:
	if gain <= 0.0:
		return
	var upper: RigidBody3D = get_upper_arm(side)
	var lower := get_lower_arm(side)
	var torso := get_torso()
	var lift := Vector3.UP * 9.8
	var shoulder := upper.global_transform * Vector3(0.0, 0.16, 0.0)
	var elbow := upper.global_transform * Vector3(0.0, -0.17, 0.0)
	# codo: sostiene el antebrazo
	var t_elbow := (lower.global_position - elbow).cross(lift * lower.mass) * gain
	lower.apply_torque(t_elbow)
	upper.apply_torque(-t_elbow)
	# hombro: sostiene brazo + antebrazo
	var t_shoulder := ((upper.global_position - shoulder).cross(lift * upper.mass)
		+ (lower.global_position - shoulder).cross(lift * lower.mass)) * gain
	upper.apply_torque(t_shoulder)
	torso.apply_torque(-t_shoulder)

## Como _pd_toward pero solo para la DIRECCION de un hueso (su -Y local hacia
## `target_dir`). No controla la torsion sobre su propio eje: la inercia en ese
## eje es diminuta y controlarla hacia oscilar el antebrazo a 20+ rad/s.
func _pd_aim(body: RigidBody3D, target_dir: Vector3, freq: float, ratio: float,
		max_torque: float, counter: RigidBody3D = null, gain: float = 1.0, inertia_scale: float = 1.0) -> void:
	if gain <= 0.0 or max_torque <= 0.0:
		return
	var cur := -body.global_basis.y
	var axis := cur.cross(target_dir)
	var s := axis.length()
	var angle := atan2(s, cur.dot(target_dir))
	var err := Vector3.ZERO
	if s > 1e-6:
		err = axis / s * angle
	elif cur.dot(target_dir) < 0.0:
		# exactamente opuesto: girar sobre cualquier eje perpendicular
		err = body.global_basis.x * PI
	var rel_w := body.angular_velocity
	if counter:
		rel_w -= counter.angular_velocity
	rel_w -= cur * rel_w.dot(cur)  # amortiguar solo el balanceo, no la torsion
	var inertia := body.get_inverse_inertia_tensor().inverse() * inertia_scale
	var p_t := inertia * (err * freq * freq * gain)
	var d_t := inertia * (rel_w * 2.0 * ratio * freq * sqrt(gain))
	d_t *= _pd_damping_scale(body, counter, rel_w, d_t)
	var torque := p_t - d_t
	torque -= cur * torque.dot(cur)  # sin componente de torsion
	torque = torque.limit_length(max_torque)
	body.apply_torque(torque)
	if counter:
		counter.apply_torque(-torque)


## Torque PD que lleva `body` hacia la orientacion mundial `target`.
## Si `counter` no es null aplica el torque opuesto al padre (accion-reaccion).
func _pd_toward(body: RigidBody3D, target: Quaternion, freq: float, ratio: float,
		max_torque: float, counter: RigidBody3D = null, gain: float = 1.0, inertia_scale: float = 1.0) -> void:
	if gain <= 0.0 or max_torque <= 0.0:
		return
	var err := _rotation_error(body.global_basis.get_rotation_quaternion(), target)
	var rel_w := body.angular_velocity
	if counter:
		rel_w -= counter.angular_velocity
	var inertia := body.get_inverse_inertia_tensor().inverse() * inertia_scale
	var p_t := inertia * (err * freq * freq * gain)
	var d_t := inertia * (rel_w * 2.0 * ratio * freq * sqrt(gain))
	d_t *= _pd_damping_scale(body, counter, rel_w, d_t)
	var torque := (p_t - d_t).limit_length(max_torque)
	body.apply_torque(torque)
	if counter:
		counter.apply_torque(-torque)


## Vector eje*angulo que rota `current` hacia `target` (camino mas corto).
static func _rotation_error(current: Quaternion, target: Quaternion) -> Vector3:
	var q := target * current.inverse()
	if q.w < 0.0:
		q = -q
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < 1e-6:
		return Vector3.ZERO
	return v / s * (2.0 * atan2(s, q.w))


# =============================================================================
# Agarrar
# =============================================================================
func _update_grabs() -> void:
	for side in 2:
		var want: bool = want_grab[side] and strength > 0.3
		if not want:
			_raise_time[side] = 0.0
			release(side)
			continue
		if _grab_joints[side] != null:
			if not is_instance_valid(_grab_targets[side]):
				release(side)
			continue
		# La mano solo se cierra cuando el brazo ya apunta hacia donde se mira
		# (o lleva un rato levantado y algo lo bloquea). Asi no se agarra a
		# media pared mientras el brazo aun esta subiendo.
		_raise_time[side] += get_physics_process_delta_time()
		var arm_dir := -get_lower_arm(side).global_basis.y
		if arm_dir.dot(get_aim_direction()) < grab_aim_alignment and _raise_time[side] < grab_blocked_time:
			continue
		var hand := get_hand_position(side)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _grab_shape
		params.transform = Transform3D(Basis.IDENTITY, hand)
		params.collision_mask = ALL_MASK
		params.exclude = _own_rids
		for hit in get_world_3d().direct_space_state.intersect_shape(params, 6):
			var col := hit.collider as PhysicsBody3D
			if col:
				_create_grab(side, col, hand)
				break


func _create_grab(side: int, target: PhysicsBody3D, at: Vector3) -> void:
	var lower := get_lower_arm(side)
	var j := Generic6DOFJoint3D.new()
	j.name = "Grab%d" % side
	add_child(j)
	j.global_position = at
	# Bloqueo lineal total; giro libre (la mano actua como rotula)
	for axis in ["x", "y", "z"]:
		j.set("angular_limit_%s/enabled" % axis, false)
	j.node_a = j.get_path_to(lower)
	j.node_b = j.get_path_to(target)
	_grab_joints[side] = j
	_grab_targets[side] = target
	grabbed.emit(side, target)


func release(side: int) -> void:
	if _grab_joints[side] != null:
		(_grab_joints[side] as Node).queue_free()
		_grab_joints[side] = null
		_grab_targets[side] = null
		released.emit(side)


func is_grabbing(side: int) -> bool:
	return _grab_joints[side] != null


func get_grabbed(side: int) -> Node3D:
	return _grab_targets[side]


# =============================================================================
# Combate
# =============================================================================
func punch() -> void:
	if strength < 0.5:
		return
	var side := _next_punch_side
	_next_punch_side = Side.LEFT if side == Side.RIGHT else Side.RIGHT
	if is_grabbing(side):
		return
	_punch_timers[side] = 0.28
	var dir := (Quaternion(Vector3.UP, facing_yaw) * Quaternion(Vector3.RIGHT, clampf(aim_pitch, -0.3, 0.4))) * Vector3.FORWARD
	get_lower_arm(side).apply_central_impulse(dir * punch_impulse)
	get_torso().apply_torque_impulse(Vector3.UP * (4.0 if side == Side.RIGHT else -4.0))


# =============================================================================
# Utilidades publicas
# =============================================================================
func respawn() -> void:
	for side in 2:
		release(side)
	_ko_timer = 0.0
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
	return get_lower_arm(side).global_transform * HAND_OFFSET


func get_aim_direction() -> Vector3:
	return (Quaternion(Vector3.UP, facing_yaw) * Quaternion(Vector3.RIGHT, aim_pitch)) * Vector3.FORWARD


func get_center() -> Vector3:
	return get_torso().global_position


func get_linear_velocity() -> Vector3:
	return get_torso().linear_velocity
