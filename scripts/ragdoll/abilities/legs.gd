class_name LegsAbility
extends CharacterAbility
## Pose de las piernas: ciclo de paso al caminar, recogidas en el aire y
## rodillas arriba al trepar. PD relativos a la pelvis.

@export var limb_frequency := 16.0        ## rigidez de las piernas (rad/s)

@export_group("Trepar")
@export var climb_thigh_pitch := 0.6      ## colgado: muslos algo adelantados (rad)
@export var climb_knee := -1.0            ## colgado: rodillas dobladas (rad, negativo = flexion)
@export var mantle_thigh_pitch := 1.5     ## cruzando el borde: rodillas al pecho (rad)
@export var mantle_knee := -1.5           ## cruzando el borde: talones atras (rad)


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
		if c.mantling:
			# cruzando el borde: rodillas al pecho para que los pies pasen la arista
			thigh_pitch = mantle_thigh_pitch + (0.0 if side == Side.LEFT else -0.1)
			knee = mantle_knee
		elif c.climbing:
			# colgado: rodillas arriba para no engancharse en la pared
			thigh_pitch = climb_thigh_pitch + (0.1 if side == Side.LEFT else -0.1)
			knee = climb_knee
		elif not c.grounded and c.air_time > 0.15:
			# en el aire: piernas algo recogidas
			thigh_pitch = 0.35 if side == Side.LEFT else 0.15
			knee = -0.6
		var thigh: RigidBody3D = c.bodies["thigh" + sfx]
		var shin: RigidBody3D = c.bodies["shin" + sfx]
		var spread := 0.04 if side == Side.RIGHT else -0.04
		# Al cruzar un borde el cuerpo va doblado sobre el: los muslos se orientan
		# respecto al mundo (no a la pelvis inclinada) para que las rodillas suban.
		var frame := Quaternion(Vector3.UP, c.facing_yaw) if c.mantling else pelvis.global_basis.get_rotation_quaternion()
		var thigh_t := frame * Quaternion.from_euler(Vector3(thigh_pitch, 0, spread))
		RagdollMuscles.pd_toward(thigh, thigh_t, limb_frequency * 2.0, 1.0, 600.0 * c.strength, pelvis, c.strength, 2.2)
		var shin_t := thigh.global_basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, knee)
		RagdollMuscles.pd_toward(shin, shin_t, limb_frequency * 2.0, 1.0, 350.0 * c.strength, thigh, c.strength, 1.4)
