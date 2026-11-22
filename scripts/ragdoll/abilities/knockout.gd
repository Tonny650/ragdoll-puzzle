class_name KnockoutAbility
extends CharacterAbility
## Fuerza muscular y KO (Gang Beasts): un golpe fuerte en la cabeza deja el
## cuerpo flacido (`strength` = 0) y luego se recupera solo. Q = dejarse caer.
## Dos formas de caer KO:
## - Puñetazos: cada golpe en la cabeza suma `punch_damage` (algo mas si es rapido); al
##   llegar a `knockout_damage` cae KO. El daño se va curando con el tiempo.
## - Impacto muy fuerte en la cabeza (`knockout_speed`): KO directo.
## Sin este nodo el personaje siempre tiene fuerza 1 y no se le puede noquear.

@export var recover_time := 1.6           ## segundos en recuperar la fuerza tras un KO
@export var knockout_speed := 7.5         ## velocidad relativa de impacto en la cabeza que noquea
@export var knockout_duration := 3.0
@export var knockout_damage := 10.0       ## daño acumulado de puñetazos que noquea
@export var punch_min_speed := 1.5        ## golpes mas lentos no hacen daño
@export var punch_damage := 3.0           ## daño de un puñetazo normal (algo mas si es rapido)
@export var damage_recovery := 1.5        ## daño que se cura por segundo...
@export var damage_recovery_delay := 3.0  ## ...una vez pasados estos segundos sin encajar golpes
@export var punch_knockback := 20.0        ## impulso a cabeza+torso al encajar un puñetazo (escala con la velocidad)
@export var stagger_time := 0.45          ## segundos tambaleandose tras encajar un golpe
@export_range(0.0, 1.0) var stagger_strength := 0.05  ## fuerza muscular mientras se tambalea
@export var recover_grace := 2.0          ## tras levantarse, segundos sin poder ser noqueado otra vez

signal hurt(damage: float, total: float)

var damage := 0.0
var _grace := 0.0
var _stagger := 0.0
var _since_hit := 0.0

var _ko_timer := 0.0


func setup() -> void:
	var head := character.get_head()
	head.contact_monitor = true
	head.max_contacts_reported = 4
	head.body_entered.connect(_on_head_hit)


func physics_step(delta: float) -> void:
	var c := character
	_since_hit += delta
	if _since_hit > damage_recovery_delay:
		damage = maxf(0.0, damage - damage_recovery * delta)
	_grace = maxf(0.0, _grace - delta)
	if _ko_timer > 0.0:
		_ko_timer -= delta
		c.strength = 0.0
		if _ko_timer <= 0.0:
			_grace = recover_grace
			c.recovered.emit()
		return
	if _stagger > 0.0:
		# acaba de encajar un golpe: musculos flojos un instante para que se tambalee
		_stagger -= delta
		c.strength = minf(c.strength, stagger_strength)
		return
	var target := 0.0 if c.want_limp else 1.0
	c.strength = move_toward(c.strength, target, delta / maxf(recover_time, 0.01) if target > c.strength else delta * 8.0)


func knock_out(duration: float = -1.0) -> void:
	if _ko_timer <= 0.0:
		character.knocked_out.emit()
	damage = 0.0
	_ko_timer = maxf(_ko_timer, duration if duration > 0.0 else knockout_duration)
	character.release(Side.LEFT)
	character.release(Side.RIGHT)


func is_knocked_out() -> bool:
	return _ko_timer > 0.0


func reset() -> void:
	_ko_timer = 0.0
	_stagger = 0.0
	_grace = 0.0
	damage = 0.0


func _on_head_hit(other: Node) -> void:
	if not enabled or _grace > 0.0:
		return
	if other.has_meta("ragdoll_owner") and other.get_meta("ragdoll_owner") == character:
		return
	var other_vel := Vector3.ZERO
	if other is RigidBody3D:
		other_vel = (other as RigidBody3D).linear_velocity
	elif other.has_method("get_platform_velocity"):
		other_vel = other.get_platform_velocity()
	var rel := (character.get_head().linear_velocity - other_vel).length()
	if rel >= knockout_speed:
		knock_out()
		return
	if _ko_timer > 0.0 or rel < punch_min_speed or not _is_punch(other):
		return
	var dmg := punch_damage * clampf(rel / 4.0, 0.85, 1.4)
	damage += dmg
	_since_hit = 0.0
	hurt.emit(dmg, damage)
	var head := character.get_head()
	var to_head := head.global_position - (other as Node3D).global_position
	var push := Vector3(other_vel.x, 0.0, other_vel.z)
	if push.length_squared() < 1e-4:
		push = Vector3(to_head.x, 0.0, to_head.z)
	push = push.normalized() + Vector3.UP * 0.15
	var k := punch_knockback * clampf(rel / 4.0, 0.6, 1.6)
	head.apply_central_impulse(push * k * 0.45)
	# en la parte alta del torso: ademas de empujarlo, lo inclina hacia atras
	character.get_torso().apply_impulse(push * k, Vector3.UP * 0.22)
	_stagger = stagger_time
	var finishing := damage >= knockout_damage
	var power := 1.0 if finishing else clampf(damage / knockout_damage, 0.2, 0.8)
	var attacker = other.get_meta("ragdoll_owner")
	HitFx.punch(character, attacker as RagdollCharacter, head.global_position - to_head.normalized() * 0.12, push, power)
	if finishing:
		knock_out()


## `other` es el brazo de otro personaje en pleno puñetazo.
func _is_punch(other: Node) -> bool:
	if not other.has_meta("ragdoll_owner"):
		return false
	var owner_char = other.get_meta("ragdoll_owner")
	if not (owner_char is RagdollCharacter):
		return false
	var combat := (owner_char as RagdollCharacter).get_ability(CombatAbility) as CombatAbility
	return combat != null and combat.is_punching_with(other)
