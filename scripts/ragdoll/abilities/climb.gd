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

var _grab: GrabAbility


func setup() -> void:
	_grab = character.get_ability(GrabAbility) as GrabAbility
	if _grab == null:
		push_warning("%s: ClimbAbility necesita GrabAbility; trepar desactivado." % character.name)
		enabled = false


func physics_step(_delta: float) -> void:
	var c := character
	var holds := 0
	var anchor := Vector3.ZERO
	for side in 2:
		if c.want_grab[side] and is_climb_anchor(side):
			holds += 1
			anchor += _grab.get_grab_point(side) as Vector3
	if holds == 0 or c.strength < 0.3 or c.aim_pitch < climb_min_pitch:
		c.climbing = false
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
	if pushing:
		var above := torso.global_position.y - anchor.y
		if above > 0.1:
			# Pasar el borde: empujar sobre todo la cadera hacia delante...
			var mantle := clampf(above * 2.0, 0.0, 1.0) * c.strength
			var f := fwd * c.total_mass * 18.0 * mantle
			torso.apply_central_force(f * 0.4)
			pelvis.apply_central_force(f * 0.6)
			# ...y subirla por encima de la arista para que no se enganche en ella.
			var hip_err := (anchor.y + 0.3) - pelvis.global_position.y
			if hip_err > 0.0:
				pelvis.apply_central_force(Vector3.UP * c.total_mass * minf(hip_err * 40.0, 12.0) * mantle)


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
