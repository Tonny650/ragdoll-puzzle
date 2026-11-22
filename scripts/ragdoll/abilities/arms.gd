class_name ArmsAbility
extends CharacterAbility
## Arbitro de los brazos. Para cada brazo pregunta a las demas habilidades
## (`arm_claim_priority`) y deja que lo mueva la de mayor prioridad:
##   Combat (puñetazo) 30 > Climb (colgado) 20 > Grab (apuntar/sujetar) 10.
## Si nadie lo reclama, el brazo queda relajado y se balancea al caminar.
## Debe ir despues de las habilidades que reclaman brazos que necesiten
## actualizar su estado antes (p. ej. Combat).

@export var limb_frequency := 16.0        ## rigidez de los brazos relajados (rad/s)
@export var relaxed_swing := 0.7          ## balanceo al caminar (fraccion del paso)

var _claimants: Array[CharacterAbility] = []


func setup() -> void:
	for a in character.abilities:
		if a != self:
			_claimants.append(a)


func physics_step(delta: float) -> void:
	var c := character
	if c.strength <= 0.01:
		return
	for side in 2:
		var best: CharacterAbility = null
		var best_p := -1
		for a in _claimants:
			if not a.enabled:
				continue
			var p := a.arm_claim_priority(side)
			if p > best_p:
				best_p = p
				best = a
		if best:
			best.drive_arm(side, delta)
		else:
			_relaxed_arm(side)


func _relaxed_arm(side: int) -> void:
	var c := character
	var torso := c.get_torso()
	var upper := c.get_upper_arm(side)
	var lower := c.get_lower_arm(side)
	var sgn := -1.0 if side == Side.LEFT else 1.0
	var swing := -sin(c.walk_phase + (0.0 if side == Side.LEFT else PI)) * c.gait_amplitude * relaxed_swing
	var ut := torso.global_basis.get_rotation_quaternion() * Quaternion.from_euler(Vector3(swing, 0, sgn * 0.12))
	RagdollMuscles.pd_toward(upper, ut, limb_frequency * 0.6, 1.0, 60.0 * c.strength, torso, c.strength * 0.6, 2.0)
	var lt := upper.global_basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.25)
	RagdollMuscles.pd_toward(lower, lt, limb_frequency * 0.6, 1.0, 30.0 * c.strength, upper, c.strength * 0.6)
