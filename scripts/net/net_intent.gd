class_name NetIntent
extends RefCounted
## Lo que un jugador quiere hacer en un paso de fisica: hacia donde camina,
## hacia donde mira y que botones pulsa. Lo rellena PlayerInputController
## (teclado/raton/mando) y se aplica al personaje igual en local que en red:
## en un cliente se empaqueta y se envia al anfitrion (NetInputController).
## Los puñetazos y reapariciones van como contadores: si se pierde un paquete
## el siguiente sigue llevando el contador nuevo y la pulsacion no se pierde.

const FLAG_GRAB_L := 1
const FLAG_GRAB_R := 2
const FLAG_JUMP := 4
const FLAG_LIMP := 8
const FLAG_HAS_VIEW := 16   # yaw/pitch validos (habia camara)

const SIZE := 22

var move := Vector3.ZERO        # direccion deseada en mundo (y = 0), longitud <= 1
var yaw := 0.0
var pitch := 0.0
var flags := 0
var punch_count := 0
var respawn_count := 0


func apply_to(c: RagdollCharacter) -> void:
	if flags & FLAG_HAS_VIEW:
		c.facing_yaw = yaw
		c.aim_pitch = pitch
	c.move_input = move
	c.want_grab[0] = (flags & FLAG_GRAB_L) != 0
	c.want_grab[1] = (flags & FLAG_GRAB_R) != 0
	c.want_jump = (flags & FLAG_JUMP) != 0
	c.want_limp = (flags & FLAG_LIMP) != 0


func pack() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(SIZE)
	b.encode_float(0, move.x)
	b.encode_float(4, move.z)
	b.encode_float(8, yaw)
	b.encode_float(12, pitch)
	b.encode_u8(16, flags)
	b.encode_u16(17, punch_count & 0xFFFF)
	b.encode_u16(19, respawn_count & 0xFFFF)
	b.encode_u8(21, 0)
	return b


static func unpack(b: PackedByteArray) -> NetIntent:
	var it := NetIntent.new()
	if b.size() < SIZE:
		return it
	it.move = Vector3(b.decode_float(0), 0.0, b.decode_float(4)).limit_length(1.0)
	it.yaw = b.decode_float(8)
	it.pitch = clampf(b.decode_float(12), -1.35, 1.4)
	it.flags = b.decode_u8(16)
	it.punch_count = b.decode_u16(17)
	it.respawn_count = b.decode_u16(19)
	return it
