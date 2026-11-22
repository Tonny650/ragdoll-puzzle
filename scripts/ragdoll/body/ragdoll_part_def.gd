class_name RagdollPartDef
extends Resource
## Una pieza rigida del cuerpo ragdoll. `name` es el contrato con las
## habilidades (pelvis, torso, head, upper_arm_l...) y con el nodo del mismo
## nombre en el modelo .glb.

enum Shape { SPHERE, CAPSULE }

@export var name: StringName
@export var position := Vector3.ZERO     ## centro del cuerpo rigido en reposo (personaje mirando a -Z)
@export var mass := 1.0
@export var shape := Shape.CAPSULE
@export var radius := 0.1
@export var height := 0.4                ## solo capsulas
@export var offset := Vector3.ZERO       ## desplazamiento de la forma de colision
@export var continuous_cd := false       ## deteccion continua (piezas rapidas: antebrazos, cabeza)

@export_group("Pie")
@export var has_foot := false
@export var foot_size := Vector3(0.13, 0.09, 0.26)
@export var foot_offset := Vector3(0.0, -0.17, -0.05)
