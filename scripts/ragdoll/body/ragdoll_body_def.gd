class_name RagdollBodyDef
extends Resource
## Definicion completa de un cuerpo ragdoll: piezas, articulaciones y puntos de
## referencia que usan las habilidades. Duplica humanoid.tres para crear
## personajes con otras proporciones o masas.
##
## Las habilidades esperan estas piezas: pelvis, torso, head, upper_arm_l/r,
## lower_arm_l/r, thigh_l/r, shin_l/r.

const REQUIRED_PARTS: Array[StringName] = [
	&"pelvis", &"torso", &"head",
	&"upper_arm_l", &"lower_arm_l", &"upper_arm_r", &"lower_arm_r",
	&"thigh_l", &"shin_l", &"thigh_r", &"shin_r",
]

@export var parts: Array[RagdollPartDef] = []
@export var joints: Array[RagdollJointDef] = []

@export_group("Puntos de referencia")
@export var hand_offset := Vector3(0.0, -0.18, 0.0)      ## mano, en local del antebrazo
@export var shoulder_offset := Vector3(0.0, 0.16, 0.0)   ## hombro, en local del brazo
@export var elbow_offset := Vector3(0.0, -0.17, 0.0)     ## codo, en local del brazo

@export_group("Fisica")
@export var friction := 0.9
@export var linear_damp := 0.05
@export var angular_damp := 1.5


## Devuelve los nombres de piezas obligatorias que faltan (vacio = valido).
func missing_parts() -> Array[StringName]:
	var have := {}
	for p in parts:
		have[p.name] = true
	var missing: Array[StringName] = []
	for n in REQUIRED_PARTS:
		if not have.has(n):
			missing.append(n)
	return missing
