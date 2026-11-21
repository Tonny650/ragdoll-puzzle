class_name MovingPlatform
extends AnimatableBody3D
## Plataforma que va y viene entre su posicion inicial y `offset`.

@export var offset := Vector3(0, 0, -6)
@export var period := 6.0

var _origin := Vector3.ZERO
var _t := 0.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO


func _ready() -> void:
	_origin = position
	_last = global_position


func _physics_process(delta: float) -> void:
	_t += delta
	var k := 0.5 - 0.5 * cos(_t / period * TAU)
	position = _origin + offset * k
	_vel = (global_position - _last) / maxf(delta, 1e-5)
	_last = global_position


func get_platform_velocity() -> Vector3:
	return _vel
