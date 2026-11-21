"""
Genera los personajes ragdoll en Blender y los exporta a GLB para Godot.

Uso (Blender 4.2+ / 5.x):
    blender -b --python art_source/build_characters.py

Cada parte del cuerpo es un objeto independiente cuyo ORIGEN coincide con el
centro del RigidBody3D que lo controla en Godot (ver ragdoll_character.gd).
Coordenadas: Godot (x, y, z) == Blender (x, -z_godot -> y, y_godot -> z).
El personaje mira hacia -Z en Godot, que es +Y en Blender.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "characters")
os.makedirs(OUT_DIR, exist_ok=True)


def g2b(x, y, z):
    """Godot -> Blender coordinates."""
    return Vector((x, -z, y))


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*color, 1.0)
    return mat


def new_mesh_object(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def capsule(name, radius, height, material, scale=(1, 1, 1), segs=32, rings=16):
    """Capsula vertical (eje Z en Blender) centrada en el origen.
    height = longitud total incluyendo los casquetes."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    half = max(0.0, height * 0.5 - radius)
    for v in bm.verts:
        if v.co.z > 1e-5:
            v.co.z += half
        elif v.co.z < -1e-5:
            v.co.z -= half
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    return new_mesh_object(name, bm, material)


def sphere(name, radius, material, scale=(1, 1, 1), segs=32, rings=16):
    return capsule(name, radius, radius * 2.0, material, scale, segs, rings)


def box(name, size, material, bevel=0.02):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    obj = new_mesh_object(name, bm, material)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
    return obj


def torus(name, major, minor, material):
    bm = bmesh.new()
    seg_major, seg_minor = 32, 12
    verts = []
    for i in range(seg_major):
        a = 2 * math.pi * i / seg_major
        row = []
        for j in range(seg_minor):
            b = 2 * math.pi * j / seg_minor
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(row)
    for i in range(seg_major):
        for j in range(seg_minor):
            bm.faces.new((verts[i][j], verts[(i + 1) % seg_major][j],
                          verts[(i + 1) % seg_major][(j + 1) % seg_minor], verts[i][(j + 1) % seg_minor]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def place(obj, offset_godot):
    """Coloca un objeto auxiliar relativo al origen de la parte (en coords Godot)."""
    obj.location = g2b(*offset_godot)
    return obj


def join_into(main, others):
    """Une objetos auxiliares a la parte principal manteniendo el origen de la parte."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        # aplicar modificadores antes de unir
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    for o in others:
        o.select_set(True)
    main.select_set(True)
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    return main


# ---------------------------------------------------------------------------
# Definicion del cuerpo (DEBE coincidir con ragdoll_character.gd)
# ---------------------------------------------------------------------------
PARTS = {
    #  nombre        centro (Godot)
    "pelvis":       (0.0, 0.92, 0.0),
    "torso":        (0.0, 1.22, 0.0),
    "head":         (0.0, 1.68, 0.0),
    "upper_arm_l":  (-0.31, 1.30, 0.0),
    "lower_arm_l":  (-0.31, 0.98, 0.0),
    "upper_arm_r":  (0.31, 1.30, 0.0),
    "lower_arm_r":  (0.31, 0.98, 0.0),
    "thigh_l":      (-0.11, 0.62, 0.0),
    "shin_l":       (-0.11, 0.24, 0.0),
    "thigh_r":      (0.11, 0.62, 0.0),
    "shin_r":       (0.11, 0.24, 0.0),
}


def build_character(style):
    reset_scene()
    skin = make_material(f"{style['name']}_body", style["body"], 0.45)
    pants = make_material(f"{style['name']}_pants", style["pants"], 0.8)
    shoes = make_material(f"{style['name']}_shoes", style["shoes"], 0.7)
    dark = make_material("eyes_black", (0.02, 0.02, 0.025), 0.2)
    white = make_material("eyes_white", (0.95, 0.95, 0.95), 0.3)
    accent = make_material(f"{style['name']}_accent", style["accent"], 0.85)

    objs = {}

    # --- Pelvis (pantalon) -------------------------------------------------
    pelvis = sphere("pelvis", 0.17, pants, scale=(1.15, 0.95, 0.85))
    objs["pelvis"] = pelvis

    # --- Torso: cuerpo regordete tipo "gominola" ------------------------------
    torso = capsule("torso", 0.23, 0.62, skin, scale=(1.0, 0.86, 1.0))
    extras = []
    belt = torus("belt", 0.205, 0.035, pants)
    belt.scale = (1.0, 0.86, 1.0)
    extras.append(place(belt, (0, -0.24, 0)))
    if style.get("straps"):
        # Muñeco de entrenamiento: cruz en el pecho
        s1 = box("strap1", (0.06, 0.03, 0.55), accent, 0.01)
        s1.rotation_euler = (0, math.radians(35), 0)
        extras.append(place(s1, (0, 0.02, -0.19)))
        s2 = box("strap2", (0.06, 0.03, 0.55), accent, 0.01)
        s2.rotation_euler = (0, math.radians(-35), 0)
        extras.append(place(s2, (0, 0.02, -0.19)))
    else:
        # Mochila pequeña
        pack = box("backpack", (0.28, 0.12, 0.32), accent, 0.04)
        extras.append(place(pack, (0, 0.02, 0.22)))
    objs["torso"] = join_into(torso, extras)

    # --- Cabeza ------------------------------------------------------------
    head = sphere("head", 0.2, skin, scale=(1.0, 0.95, 1.05))
    extras = []
    for sx in (-1, 1):
        ew = sphere("eye_w", 0.05, white, scale=(1, 0.5, 1.2))
        extras.append(place(ew, (0.075 * sx, 0.03, -0.175)))
        ep = sphere("eye_p", 0.026, dark, scale=(1, 0.5, 1.2))
        extras.append(place(ep, (0.075 * sx, 0.03, -0.198)))
    if style.get("hat"):
        hat = sphere("beanie", 0.212, accent, scale=(1.0, 1.0, 0.78))
        # quitar la mitad inferior
        bpy.context.view_layer.objects.active = hat
        bm = bmesh.new()
        bm.from_mesh(hat.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
        bm.to_mesh(hat.data)
        bm.free()
        extras.append(place(hat, (0, 0.10, 0)))
        rim = torus("rim", 0.205, 0.035, accent)
        extras.append(place(rim, (0, 0.10, 0)))
        pom = sphere("pompom", 0.06, white)
        extras.append(place(pom, (0, 0.29, 0)))
    else:
        mark = box("x_mark", (0.12, 0.02, 0.025), accent, 0.005)
        mark.rotation_euler = (0, math.radians(45), 0)
        extras.append(place(mark, (0, 0.11, -0.16)))
        mark2 = box("x_mark2", (0.12, 0.02, 0.025), accent, 0.005)
        mark2.rotation_euler = (0, math.radians(-45), 0)
        extras.append(place(mark2, (0, 0.11, -0.16)))
    objs["head"] = join_into(head, extras)

    # --- Brazos ------------------------------------------------------------
    for side in ("l", "r"):
        up = capsule(f"upper_arm_{side}", 0.075, 0.34, skin)
        objs[f"upper_arm_{side}"] = up
        low = capsule(f"lower_arm_{side}", 0.068, 0.30, skin)
        hand = sphere("hand", 0.088, skin, scale=(1.0, 1.0, 1.05))
        objs[f"lower_arm_{side}"] = join_into(low, [place(hand, (0, -0.17, 0))])

    # --- Piernas -----------------------------------------------------------
    for side in ("l", "r"):
        th = capsule(f"thigh_{side}", 0.095, 0.40, pants)
        objs[f"thigh_{side}"] = th
        sh = capsule(f"shin_{side}", 0.085, 0.38, pants)
        foot = box("foot", (0.13, 0.26, 0.09), shoes, 0.035)
        sole = box("sole", (0.14, 0.27, 0.025), make_material("sole", (0.9, 0.9, 0.88), 0.9), 0.01)
        objs[f"shin_{side}"] = join_into(sh, [place(foot, (0, -0.17, -0.05)), place(sole, (0, -0.205, -0.05))])

    # Colocar cada parte en su posicion de reposo
    for name, pos in PARTS.items():
        o = objs[name]
        o.name = name
        o.data.name = name + "_mesh"
        o.location = g2b(*pos)

    # Luz/camara para previsualizar dentro del .blend
    bpy.ops.object.light_add(type="SUN", location=(2, -3, 4))
    bpy.ops.object.camera_add(location=(1.8, 3.2, 1.4), rotation=(math.radians(80), 0, math.radians(150)))
    bpy.context.scene.camera = bpy.context.active_object

    blend_path = os.path.join(HERE, f"character_{style['name']}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    # Exportar solo las mallas
    bpy.ops.object.select_all(action="DESELECT")
    for name in PARTS:
        objs[name].select_set(True)
    glb_path = os.path.join(OUT_DIR, f"character_{style['name']}.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("EXPORTED", glb_path)


STYLES = [
    # Jugador: personaje gominola con gorro de lana y mochila
    {"name": "nocto", "body": (0.96, 0.93, 0.86), "pants": (0.16, 0.30, 0.62),
     "shoes": (0.85, 0.25, 0.18), "accent": (0.98, 0.62, 0.12), "hat": True},
    # NPC: muñeco de entrenamiento para probar golpes/agarres
    {"name": "dummy", "body": (0.82, 0.66, 0.44), "pants": (0.35, 0.27, 0.2),
     "shoes": (0.2, 0.2, 0.2), "accent": (0.75, 0.12, 0.12), "straps": True},
]

for st in STYLES:
    build_character(st)
