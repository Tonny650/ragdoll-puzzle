class_name LocomotionAbility
extends CharacterAbility
## Desplazamiento: empuja pelvis y torso hacia la velocidad deseada y avanza la
## fase del paso que usan Legs y Arms. Tambien calcula `gait_amplitude`.

@export var max_speed := 3.6
@export var acceleration := 9.0
@export var air_control := 0.25
@export var step_frequency := 1.9         ## pasos por segundo a velocidad maxima
@export var wall_check_distance := 0.55   ## alcance de los rayos que detectan paredes delante
@export_flags_3d_physics var wall_mask := 1  ## capas que cuentan como pared fija (no props movibles)


func physics_step(delta: float) -> void:
	var c := character
	var pelvis := c.get_pelvis()
	var torso := c.get_torso()
	# Amplitud del paso (piernas y balanceo de brazos)
	c.gait_amplitude = 0.0
	if c.grounded and c.move_input.length() > 0.1:
		var pv := pelvis.linear_velocity
		c.gait_amplitude = clampf(Vector2(pv.x, pv.z).length() / max_speed, 0.35, 1.0) * 0.75

	var vel := (pelvis.linear_velocity + torso.linear_velocity) * 0.5
	var vel_h := Vector3(vel.x, 0.0, vel.z)
	var desired := c.move_input * max_speed
	var control := (1.0 if c.grounded else air_control) * c.strength
	if control <= 0.0:
		return
	var force := (desired - vel_h) * acceleration * c.total_mass * control
	if c.move_input.length_squared() < 0.01 and not c.grounded:
		force = Vector3.ZERO
	force = force.limit_length(c.total_mass * 30.0)
	force = _remove_wall_push(force)
	if c.climbing:
		# No apretarse contra la pared: la friccion impediria subir.
		force *= 0.1
	pelvis.apply_central_force(force * 0.5)
	torso.apply_central_force(force * 0.5)

	var speed01 := clampf(vel_h.length() / max_speed, 0.0, 1.0)
	_advance_phase(delta, speed01)


## No empujar contra paredes fijas: esa fuerza no mueve al personaje, solo lo
## aprieta contra la pared y la friccion lo deja pegado (p. ej. al soltarse de
## un muro sin dejar de pulsar W). Se quita la componente hacia la pared; la
## componente paralela se conserva, asi que se puede caminar pegado a ella.
## Rayos a la altura de cadera y pecho: los escalones quedan por debajo.
func _remove_wall_push(force: Vector3) -> Vector3:
	var c := character
	var dir := Vector3(force.x, 0.0, force.z)
	if dir.length_squared() < 1e-6:
		return force
	dir = dir.normalized()
	var space := c.get_world_3d().direct_space_state
	for body: RigidBody3D in [c.get_pelvis(), c.get_torso()]:
		var from := body.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * wall_check_distance, wall_mask, c.own_rids)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.5:
			continue  # suelo, rampa o techo: no es pared
		n = Vector3(n.x, 0.0, n.z).normalized()
		var into := force.dot(n)
		if into < 0.0:
			force -= n * into
	return force


func _advance_phase(delta: float, speed01: float) -> void:
	var c := character
	if c.grounded and c.move_input.length_squared() > 0.01:
		c.walk_phase = fmod(c.walk_phase + delta * TAU * step_frequency * maxf(speed01, 0.45), TAU)
	else:
		c.walk_phase = lerpf(c.walk_phase, 0.0 if c.walk_phase < PI else TAU, delta * 4.0)
