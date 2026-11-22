class_name RagdollJointDef
extends Resource
## Articulacion ConeTwistJoint3D entre dos piezas. El eje de torsion apunta a lo
## largo del hueso (hacia abajo).

@export var parent: StringName
@export var child: StringName
@export var anchor := Vector3.ZERO       ## en espacio local del personaje
@export var swing_span := 1.0            ## rad
@export var twist_span := 0.5            ## rad
