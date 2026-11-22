class_name LegsAbility
extends CharacterAbility
## Pose de las piernas: ciclo de paso al caminar, recogidas en el aire y
## rodillas arriba al trepar. PD relativos a la pelvis.

@export var limb_frequency := 16.0        ## rigidez de las piernas (rad/s)


func physics_step(_delta: float) -> void:
	var c := character
	if c.strength <= 0.01:
		return
	var pelvis := c.get_pelvis()
	var amp := c.gait_amplitude
	for side in 2:
		var sfx := "_l" if side == Side.LEFT else "_r"
		var ph := c.walk_phase + (0.0 if side == Side.LEFT else PI)
		var thigh_pitch := sin(ph) * amp
		var knee := -maxf(0.0, cos(ph)) * amp * 1.3 - 0.05
		if c.climbing:
			# trepando: rodillas arriba para subirlas al borde (no engancharse en la pared)
			thigh_pitch = 0.7 if side == Side.LEFT else 0.5
			knee = -1.0
		elif not c.grounded and c.air_time > 0.15:
			# en el aire: piernas algo recogidas
			thigh_pitch = 0.35 if side == Side.LEFT else 0.15
			knee = -0.6
		var thigh: RigidBody3D = c.bodies["thigh" + sfx]
		var shin: RigidBody3D = c.bodies["shin" + sfx]
		var spread := 0.04 if side == Side.RIGHT else -0.04
		var thigh_t := pelvis.global_basis.get_rotation_quaternion() * Quaternion.from_euler(Vector3(thigh_pitch, 0, spread))
		RagdollMuscles.pd_toward(thigh, thigh_t, limb_frequency * 2.0, 1.0, 600.0 * c.strength, pelvis, c.strength, 2.2)
		var shin_t := thigh.global_basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, knee)
		RagdollMuscles.pd_toward(shin, shin_t, limb_frequency * 2.0, 1.0, 350.0 * c.strength, thigh, c.strength, 1.4)
