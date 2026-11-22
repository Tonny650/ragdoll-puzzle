class_name BalanceAbility
extends CharacterAbility
## Musculo de equilibrio: mantiene torso y pelvis erguidos mirando hacia
## `facing_yaw`, inclina el torso al apuntar o al trepar, y orienta la cabeza
## hacia donde se apunta.

@export var upright_stiffness := 1600.0   ## Nm/rad para mantener el torso vertical
@export var upright_damping := 160.0
@export var climb_lean := 0.75            ## inclinacion hacia delante al pasar un borde (rad)


func physics_step(_delta: float) -> void:
	var c := character
	if c.strength <= 0.01:
		return
	var yaw_q := Quaternion(Vector3.UP, c.facing_yaw)
	var lean := 0.0
	if c.climbing:
		# Colgado: doblarse hacia delante sobre el borde al empujar (negativo = adelante).
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, c.facing_yaw)
		lean = -climb_lean if c.move_input.dot(fwd) > 0.3 else 0.0
	elif c.want_grab[0] or c.want_grab[1]:
		lean = clampf(c.aim_pitch, -0.9, 0.5) * 0.35
	lean -= c.move_input.length() * 0.08
	var torso_target := yaw_q * Quaternion(Vector3.RIGHT, lean)
	var k := upright_stiffness * c.strength * (c.total_mass / 60.0)
	var d := upright_damping * c.strength * (c.total_mass / 60.0)
	RagdollMuscles.upright_torque(c.get_torso(), torso_target, k, d, 2200.0)
	RagdollMuscles.upright_torque(c.get_pelvis(), yaw_q, k * 0.6, d * 0.6, 1400.0)
	# cabeza mirando hacia donde se apunta
	var head_target := yaw_q * Quaternion(Vector3.RIGHT, clampf(c.aim_pitch, -0.8, 0.8) * 0.6)
	RagdollMuscles.pd_toward(c.get_head(), head_target, 10.0, 1.0, 60.0 * c.strength, c.get_torso(), c.strength)
