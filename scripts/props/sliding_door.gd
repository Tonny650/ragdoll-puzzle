class_name SlidingDoor
extends AnimatableBody3D
## Puerta que se desliza al abrirse. Conectar a las señales de PressurePlate.

@export var open_offset := Vector3(0, 3.2, 0)
@export var speed := 2.5

var _closed_pos := Vector3.ZERO
var _open := false


func _ready() -> void:
	_closed_pos = position


func open() -> void:
	_open = true


func close() -> void:
	_open = false


func _physics_process(delta: float) -> void:
	var goal := _closed_pos + (open_offset if _open else Vector3.ZERO)
	position = position.move_toward(goal, speed * delta)


func get_platform_velocity() -> Vector3:
	return Vector3.ZERO
