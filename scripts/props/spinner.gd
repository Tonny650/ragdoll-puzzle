class_name Spinner
extends AnimatableBody3D
## Aspa giratoria: obstaculo que derriba al personaje (estilo Gang Beasts).

@export var speed_deg := 70.0


func _physics_process(delta: float) -> void:
	rotate_y(deg_to_rad(speed_deg) * delta)


func get_platform_velocity() -> Vector3:
	return Vector3.ZERO
