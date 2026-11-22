class_name ClimbAbility
extends CharacterAbility
## Trepar estilo HFF. Necesita GrabAbility en el mismo personaje.
## Agarrado a algo fijo (o muy pesado) + mirando hacia arriba: los brazos izan
## el cuerpo. Empujando hacia delante el torso se dobla sobre el borde y la
## cadera pasa por encima ("mantle"). Soltar al estar arriba.

const ARM_PRIORITY := 20

@export var climb_strength := 1.0         ## multiplicador de la fuerza para izarse
@export var climb_min_pitch := 0.2        ## cuanto hay que mirar hacia arriba para trepar
@export var climb_min_anchor_mass := 40.0 ## masa minima de un RigidBody para poder trepar por el
@export var arm_frequency := 12.0         ## rigidez de los brazos colgados (rad/s)
@export var foot_assist := 1.0            ## ayuda a subir los pies por encima del borde al cruzarlo (0 = sin ayuda)
@export var mantle_friction := 0.05       ## friccion de cadera y piernas mientras se cruza el borde
@export var finish_time := 1.0            ## tras soltar a mitad del cruce, segundos de ayuda para acabar de subir

## Piezas que se deslizan sobre la arista al cruzarla (rodillas, espinillas).
const SLIDE_PARTS: Array[StringName] = [&"pelvis", &"thigh_l", &"shin_l", &"thigh_r", &"shin_r"]

var _grab: GrabAbility
var _slippery := PhysicsMaterial.new()
var _normal_materials := {}
var _sliding := false
var _finish_left := 0.0
var _edge_y := 0.0


func setup() -> void:
	_grab = character.get_ability(GrabAbility) as GrabAbility
	if _grab == null:
		push_warning("%s: ClimbAbility necesita GrabAbility; trepar desactivado." % character.name)
		enabled = false
	_slippery.friction = mantle_friction
	_slippery.bounce = 0.0
	for n in SLIDE_PARTS:
		var rb: RigidBody3D = character.bodies[String(n)]
		_normal_materials[n] = rb.physics_material_override


func physics_step(delta: float) -> void:
	var c := character
	var holds := 0
	var anchor := Vector3.ZERO
	for side in 2:
		if c.want_grab[side] and is_climb_anchor(side):
			holds += 1
			anchor += _grab.get_grab_point(side) as Vector3
	if holds == 0 or c.strength < 0.3 or c.aim_pitch < climb_min_pitch:
		c.climbing = false
		_finish_mantle(delta)
		return
	anchor /= holds
	c.climbing = true
	c.climb_anchor = anchor
	var torso := c.get_torso()
	var pelvis := c.get_pelvis()
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, c.facing_yaw)
	var pushing := c.move_input.dot(fwd) > 0.3
	var target_y := anchor.y + (0.95 if pushing else 0.35)
	var vy := (torso.linear_velocity.y + pelvis.linear_velocity.y) * 0.5
	var accel := 9.8 + (target_y - torso.global_position.y) * 25.0 - vy * 8.0
	var hands := 0.6 + 0.2 * holds   # una mano iza menos que dos
	var lift := clampf(accel, 0.0, 9.8 * 2.2) * c.total_mass * c.strength * hands * climb_strength
	torso.apply_central_force(Vector3.UP * lift * 0.6)
	pelvis.apply_central_force(Vector3.UP * lift * 0.4)
	c.mantling = false
	if pushing:
		var above := torso.global_position.y - anchor.y
		if above > 0.1:
			c.mantling = true
			_finish_left = finish_time
			_edge_y = anchor.y
			# Pasar el borde: empujar sobre todo la cadera hacia delante...
			var mantle := clampf(above * 2.0, 0.0, 1.0) * c.strength
			var f := fwd * c.total_mass * 18.0 * mantle
			torso.apply_central_force(f * 0.4)
			pelvis.apply_central_force(f * 0.6)
			# ...y subirla por encima de la arista para que no se enganche en ella.
			var hip_err := (anchor.y + 0.3) - pelvis.global_position.y
			if hip_err > 0.0:
				pelvis.apply_central_force(Vector3.UP * c.total_mass * minf(hip_err * 40.0, 12.0) * mantle)
			_lift_feet(anchor, fwd, mantle)
	_set_sliding(c.mantling)


## Se solto a mitad del cruce (pecho ya por encima del borde): sin ayuda queda
## sentado en la arista con las piernas colgando, o de pie sobre la punta de los
## pies. Durante `finish_time` se sigue empujando hacia delante y subiendo los
## pies que cuelguen, hasta que ambos pies apoyan arriba.
func _finish_mantle(delta: float) -> void:
	var c := character
	if _finish_left <= 0.0 or c.strength < 0.3:
		_end_finish()
		return
	_finish_left -= delta
	var hanging := 0
	for shin_name in [&"shin_l", &"shin_r"]:
		if not _foot_supported(shin_name):
			hanging += 1
	if hanging == 0:
		_end_finish()
		return
	c.mantling = true
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, c.facing_yaw)
	var f := fwd * c.total_mass * 8.0 * c.strength
	c.get_torso().apply_central_force(f * 0.4)
	c.get_pelvis().apply_central_force(f * 0.6)
	_lift_feet(Vector3(0.0, _edge_y, 0.0), fwd, c.strength)
	_set_sliding(true)


func _end_finish() -> void:
	_finish_left = 0.0
	character.mantling = false
	_set_sliding(false)


## Hay suelo justo debajo del pie (no cuelga por fuera de un borde).
func _foot_supported(shin_name: StringName) -> bool:
	var c := character
	var foot := c.get_foot_position(shin_name)
	var q := PhysicsRayQueryParameters3D.create(foot, foot + Vector3.DOWN * 0.2, RagdollCharacter.GROUND_MASK, c.own_rids)
	return not c.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Al cruzar el borde el personaje queda "arrodillado" sobre la arista: rodillas
## y espinillas cargan peso y la friccion normal (0.9) frena el avance. Mientras
## dura el cruce esas piezas resbalan, y al terminar recuperan su material.
func _set_sliding(on: bool) -> void:
	if on == _sliding:
		return
	_sliding = on
	for n in SLIDE_PARTS:
		var rb: RigidBody3D = character.bodies[String(n)]
		rb.physics_material_override = _slippery if on else _normal_materials[n]


## Al cruzar el borde los pies quedan por debajo de la arista y se enganchan en
## la cara del muro. Mientras un pie siga por debajo del borde se sostiene el
## peso de su espinilla y se empuja hacia arriba y adelante, para que pase por
## encima de la arista y apoye arriba.
func _lift_feet(anchor: Vector3, fwd: Vector3, mantle: float) -> void:
	if foot_assist <= 0.0:
		return
	var c := character
	for shin_name in [&"shin_l", &"shin_r"]:
		var shin: RigidBody3D = c.bodies[shin_name]
		var foot := c.get_foot_position(shin_name)
		var below := (anchor.y + 0.12) - foot.y
		if below <= 0.0:
			continue
		var up := 9.8 + minf(below * 60.0, 25.0)
		shin.apply_central_force((Vector3.UP * up + fwd * 8.0) * shin.mass * mantle * foot_assist)


## Solo se trepa por cosas fijas o muy pesadas (no por una caja que llevas).
func is_climb_anchor(side: int) -> bool:
	if _grab == null or not _grab.is_grabbing(side):
		return false
	var target = _grab.get_grabbed(side)
	if not is_instance_valid(target):
		return false
	if target is StaticBody3D:  # incluye AnimatableBody3D (puertas, plataformas)
		return true
	return target is RigidBody3D and (target as RigidBody3D).mass >= climb_min_anchor_mass


func arm_claim_priority(side: int) -> int:
	return ARM_PRIORITY if character.want_grab[side] and is_climb_anchor(side) else -1


func drive_arm(side: int, _delta: float) -> void:
	# Colgado de algo fijo: el brazo se alinea con el agarre en vez de apuntar a
	# la camara, para no empujar el cuerpo hacia abajo.
	var c := character
	var upper := c.get_upper_arm(side)
	var shoulder := upper.global_transform * c.body.shoulder_offset
	var to_hand := (_grab.get_grab_point(side) as Vector3) - shoulder
	if to_hand.length_squared() > 1e-4:
		var hdir := to_hand.normalized()
		RagdollMuscles.pd_aim(upper, hdir, arm_frequency, 1.0, 140.0 * c.strength, c.get_torso(), c.strength, 2.0)
		RagdollMuscles.pd_aim(c.get_lower_arm(side), hdir, arm_frequency, 1.0, 100.0 * c.strength, null, c.strength)


func reset() -> void:
	character.climbing = false
	_end_finish()
