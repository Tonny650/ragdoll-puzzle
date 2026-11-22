class_name RagdollMuscles
extends RefCounted
## "Musculos" del ragdoll activo: torques PD (proporcional-derivativo) que
## empujan una pieza hacia una orientacion objetivo, escalados por su inercia
## real. Todas las habilidades usan estas funciones.


## Torque que mantiene `body` en la orientacion mundial `target` (equilibrio).
static func upright_torque(body: RigidBody3D, target: Quaternion, k: float, d: float, max_torque: float) -> void:
	var err := rotation_error(body.global_basis.get_rotation_quaternion(), target)
	var w := body.angular_velocity
	var damp := w * d * stable_damping_scale(body, w, d)
	var torque := (err * k - damp).limit_length(max_torque)
	body.apply_torque(torque)


## Factor (0..1) que limita una amortiguacion explicita `-d*w` para que en un
## paso de fisica no frene mas del 70 % de la velocidad. Sin esto, en piezas de
## poca inercia (giro vertical del torso/pelvis) la amortiguacion se pasaba de
## largo cada paso e invertia el giro: temblor permanente de 15-20 rad/s.
static func stable_damping_scale(body: RigidBody3D, w: Vector3, d: float) -> float:
	return damping_scale(body, w, w * d, 0.7)


## Igual para un torque de amortiguacion ya calculado: cuanto frenaria a `body`
## en un paso, como fraccion de `w`. Devuelve el factor para no pasar de `max_frac`.
static func damping_scale(body: RigidBody3D, w: Vector3, damp_torque: Vector3, max_frac: float) -> float:
	var w2 := w.length_squared()
	if w2 < 1e-8:
		return 1.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var decel := (body.get_inverse_inertia_tensor() * damp_torque).dot(w) / w2 * dt
	return minf(1.0, max_frac / decel) if decel > 0.0 else 1.0


## Limite de amortiguacion de los musculos de las extremidades. La reaccion cae
## sobre el padre (p. ej. ambas piernas sobre la pelvis), asi que alli se limita
## a un 35 % por musculo para que la suma de varios siga siendo estable.
static func pd_damping_scale(body: RigidBody3D, counter: RigidBody3D, rel_w: Vector3, d_t: Vector3) -> float:
	var k := damping_scale(body, rel_w, d_t, 0.7)
	if counter:
		k = minf(k, damping_scale(counter, rel_w, d_t, 0.35))
	return k


## Como pd_toward pero solo para la DIRECCION de un hueso (su -Y local hacia
## `target_dir`). No controla la torsion sobre su propio eje: la inercia en ese
## eje es diminuta y controlarla hacia oscilar el antebrazo a 20+ rad/s.
static func pd_aim(body: RigidBody3D, target_dir: Vector3, freq: float, ratio: float,
		max_torque: float, counter: RigidBody3D = null, gain: float = 1.0, inertia_scale: float = 1.0) -> void:
	if gain <= 0.0 or max_torque <= 0.0:
		return
	var cur := -body.global_basis.y
	var axis := cur.cross(target_dir)
	var s := axis.length()
	var angle := atan2(s, cur.dot(target_dir))
	var err := Vector3.ZERO
	if s > 1e-6:
		err = axis / s * angle
	elif cur.dot(target_dir) < 0.0:
		# exactamente opuesto: girar sobre cualquier eje perpendicular
		err = body.global_basis.x * PI
	var rel_w := body.angular_velocity
	if counter:
		rel_w -= counter.angular_velocity
	rel_w -= cur * rel_w.dot(cur)  # amortiguar solo el balanceo, no la torsion
	var inertia := body.get_inverse_inertia_tensor().inverse() * inertia_scale
	var p_t := inertia * (err * freq * freq * gain)
	var d_t := inertia * (rel_w * 2.0 * ratio * freq * sqrt(gain))
	d_t *= pd_damping_scale(body, counter, rel_w, d_t)
	var torque := p_t - d_t
	torque -= cur * torque.dot(cur)  # sin componente de torsion
	torque = torque.limit_length(max_torque)
	body.apply_torque(torque)
	if counter:
		counter.apply_torque(-torque)


## Torque PD que lleva `body` hacia la orientacion mundial `target`.
## Si `counter` no es null aplica el torque opuesto al padre (accion-reaccion).
static func pd_toward(body: RigidBody3D, target: Quaternion, freq: float, ratio: float,
		max_torque: float, counter: RigidBody3D = null, gain: float = 1.0, inertia_scale: float = 1.0) -> void:
	if gain <= 0.0 or max_torque <= 0.0:
		return
	var err := rotation_error(body.global_basis.get_rotation_quaternion(), target)
	var rel_w := body.angular_velocity
	if counter:
		rel_w -= counter.angular_velocity
	var inertia := body.get_inverse_inertia_tensor().inverse() * inertia_scale
	var p_t := inertia * (err * freq * freq * gain)
	var d_t := inertia * (rel_w * 2.0 * ratio * freq * sqrt(gain))
	d_t *= pd_damping_scale(body, counter, rel_w, d_t)
	var torque := (p_t - d_t).limit_length(max_torque)
	body.apply_torque(torque)
	if counter:
		counter.apply_torque(-torque)


## Vector eje*angulo que rota `current` hacia `target` (camino mas corto).
static func rotation_error(current: Quaternion, target: Quaternion) -> Vector3:
	var q := target * current.inverse()
	if q.w < 0.0:
		q = -q
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < 1e-6:
		return Vector3.ZERO
	return v / s * (2.0 * atan2(s, q.w))
