class_name StandSupportAbility
extends CharacterAbility
## "Muelle" vertical que sostiene el peso cuando hay suelo debajo (como HFF), y
## el salto. Sin este nodo el personaje no se tiene en pie.

@export var stand_height := 0.9           ## altura objetivo de la pelvis sobre el suelo
@export var jump_speed := 4.8

var _jump_cooldown := 0.0


func setup() -> void:
	character.stand_height = stand_height


func physics_step(delta: float) -> void:
	var c := character
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	if not c.grounded or c.strength <= 0.01:
		c.air_time += delta
		return
	c.air_time = 0.0
	var pelvis := c.get_pelvis()
	var torso := c.get_torso()
	var vy := (pelvis.linear_velocity.y + torso.linear_velocity.y) * 0.5
	var err := stand_height - c.ground_distance
	var g := 9.8
	var accel := g + err * 120.0 - vy * 18.0
	var force := clampf(accel, 0.0, g * 2.6) * c.total_mass * c.strength
	if _jump_cooldown > 0.25:
		force = 0.0
	pelvis.apply_central_force(Vector3.UP * force * 0.55)
	torso.apply_central_force(Vector3.UP * force * 0.45)

	if c.want_jump and _jump_cooldown <= 0.0 and c.strength > 0.8:
		_jump_cooldown = 0.6
		for rb: RigidBody3D in c.bodies.values():
			rb.linear_velocity.y = maxf(rb.linear_velocity.y, jump_speed)
