"""Build the original Project Velocity runner and bake its GLB clips in Blender."""
import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parent.parent
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, base, metallic, roughness, glow=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*base, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*base, 1)
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Emission Color"].default_value = (*base, 1)
    node.inputs["Emission Strength"].default_value = glow
    return mat


red = material("Oxblood fabric", (.31, .018, .032), .05, .69)
armor = material("Crimson ceramic", (.46, .029, .038), .23, .42)
rubber = material("Graphite weave", (.069, .023, .036), .02, .70)
gold = material("Amber conductor", (1, .38, .045), .39, .29, .83)
trim = material("Rose alloy", (.38, .064, .039), .58, .27)
weave = material("Flexible shell", (.082, .021, .033), .11, .70)
visor = material("Smoked visor", (.027, .055, .084), .47, .20)
skin = material("Lower face", (.49, .238, .163), .02, .62)
lip = material("Lips", (.285, .089, .067), .01, .62)

armature = bpy.data.armatures.new("RunnerSkeleton")
rig = bpy.data.objects.new("RunnerRig", armature)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, head, tip, parent=None):
    obj = armature.edit_bones.new(name)
    obj.head, obj.tail = head, tip
    if parent:
        obj.parent = armature.edit_bones[parent]
    return head


bone("hips", (0, 0, .98), (0, 0, 1.20))
bone("chest", (0, 0, 1.15), (0, 0, 1.53), "hips")
bone("head", (0, 0, 1.54), (0, 0, 1.81), "chest")

for side, sign in (("L", 1), ("R", -1)):
    x = lambda amount: sign * amount
    bone("arm" + side, (x(.228), 0, 1.46), (x(.29), 0, 1.20), "chest")
    bone("fore" + side, (x(.29), 0, 1.20), (x(.315), .01, .965), "arm" + side)
    bone("hand" + side, (x(.315), .01, .965), (x(.325), .015, .85), "fore" + side)
    bone("thigh" + side, (x(.108), 0, .99), (x(.117), .015, .55), "hips")
    bone("shin" + side, (x(.117), .015, .55), (x(.12), -.012, .115), "thigh" + side)
    bone("foot" + side, (x(.12), -.012, .115), (x(.12), .16, .056), "shin" + side)
bpy.ops.object.mode_set(mode="OBJECT")
pieces = []


def mesh_object(name, vertices, faces, mat, joint):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.vertex_groups.new(name=joint).add(list(range(len(vertices))), 1, "REPLACE")
    for polygon in data.polygons:
        polygon.use_smooth = True
    pieces.append(obj)
    return obj


def loft(name, rings, mat, joint, count=20):
    """Each ring contains height, center X/Y, and side/front radii."""
    points = [
        (x + rx * math.cos(i * math.tau / count),
         y + ry * math.sin(i * math.tau / count), z)
        for z, x, y, rx, ry in rings for i in range(count)
    ]
    faces = [tuple(reversed(range(count)))]
    for row in range(len(rings) - 1):
        offset = row * count
        for idx in range(count):
            a, b = offset + idx, offset + (idx + 1) % count
            faces.append((a, b, b + count, a + count))
    faces.append(tuple(range(len(points) - count, len(points))))
    return mesh_object(name, points, faces, mat, joint)


def rounded(name, center, radii, mat, joint):
    z_rings = range(1, 12)
    return loft(name, [
        (center[2] - radii[2] * math.cos(i * math.pi / 12), center[0], center[1],
         radii[0] * math.sin(i * math.pi / 12), radii[1] * math.sin(i * math.pi / 12))
        for i in z_rings
    ], mat, joint, 16)


def plate(name, points, mat, joint):
    vertices = points + [(x, y - .012, z) for x, y, z in points]
    n = len(points)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
    mesh_object(name, vertices, faces, mat, joint)


def trace(name, points, radius, mat, joint):
    """Small material seams and conduits that stay bound to their armor plate."""
    sections = 8
    vertices = []
    for index, (x, y, z) in enumerate(points):
        before = points[max(0, index - 1)]
        after = points[min(len(points) - 1, index + 1)]
        dx, dz = after[0] - before[0], after[2] - before[2]
        scale = max(.001, math.hypot(dx, dz))
        nx, nz = dz / scale, -dx / scale
        for side in range(sections):
            angle = side / sections * math.tau
            width = math.cos(angle) * radius
            vertices.append((x + nx * width, y + math.sin(angle) * radius, z + nz * width))
    faces = []
    for index in range(len(points) - 1):
        for side in range(sections):
            a = index * sections + side
            b = index * sections + (side + 1) % sections
            faces.append((a, b, b + sections, a + sections))
    faces += [tuple(reversed(range(sections))), tuple(range(len(vertices)-sections,len(vertices)))]
    return mesh_object(name, vertices, faces, mat, joint)


loft("Dorsal spine", [
    (1.181, 0, -.105, .046, .018), (1.250, 0, -.112, .067, .022),
    (1.365, 0, -.127, .064, .022), (1.456, 0, -.098, .059, .025),
    (1.488, 0, -.086, .048, .017)
], weave, "chest")
trace("Back insignia", [(-.043,-.137,1.384),(.010,-.153,1.407),(-.005,-.156,1.361),(.044,-.139,1.378)], .0064, gold, "chest")
for band in range(4):
    z = 1.23 + band * .031
    trace("Spine shield " + str(band), [(-.034, -.131, z), (0, -.139, z-.009), (.034, -.131, z)], .005, trim, "chest")
trace("Helmet centre seam", [(0,-.080,1.651),(0,-.103,1.705),(0,-.102,1.766),(0,-.058,1.820)], .004, trim, "head")


loft("Pelvis and belt", [
    (.87, 0, 0, .10, .07), (.94, 0, -.005, .184, .111),
    (1.03, 0, 0, .169, .123), (1.12, 0, 0, .147, .113),
    (1.19, 0, 0, .148, .103)
], rubber, "hips")
loft("Low waist armor", [
    (1.037, 0, .006, .162, .122), (1.054, 0, .005, .165, .125),
    (1.085, 0, .004, .153, .117), (1.102, 0, .003, .15, .114)
], armor, "hips")
loft("Torso", [
    (1.079, 0, -.006, .146, .115), (1.154, 0, -.01, .15, .117),
    (1.24, 0, -.006, .184, .12), (1.33, 0, -.002, .214, .132),
    (1.43, 0, .002, .232, .136), (1.48, 0, 0, .214, .111),
    (1.515, 0, 0, .117, .077), (1.527, 0, 0, .077, .064)
], red, "chest")
loft("Collar", [(1.486, 0, 0, .108, .082), (1.54, 0, 0, .073, .064),
              (1.60, 0, -.003, .064, .057)], rubber, "head")
loft("Helmet", [
    (1.575, 0, .01, .045, .056), (1.612, 0, .008, .072, .076),
    (1.66, 0, 0, .091, .09), (1.724, 0, -.006, .094, .093),
    (1.777, 0, -.012, .084, .087), (1.819, 0, -.012, .057, .06),
    (1.838, 0, -.012, .025, .024)
], armor, "head")
loft("Face opening", [
    (1.576, 0, .047, .023, .033), (1.599, 0, .052, .047, .042),
    (1.626, 0, .052, .064, .047), (1.648, 0, .052, .073, .048),
    (1.674, 0, .050, .073, .051)
], skin, "head")
rounded("Nose", (0, .099, 1.665), (.016, .017, .020), skin, "head")
trace("Mouth", [(-.021,.092,1.622),(-.009,.101,1.623),(0,.105,1.622),
                (.009,.101,1.623),(.021,.092,1.622)], .0025, lip, "head")
loft("Visor", [(1.676, 0, .059, .062, .028), (1.689, 0, .056, .083, .049),
               (1.717, 0, .051, .084, .058), (1.733, 0, .06, .072, .043)],
     visor, "head")
plate("Visor conductor", [(-.068, .102, 1.713), (0, .112, 1.705),
                          (.068, .102, 1.713), (0, .114, 1.697)], gold, "head")
plate("Chest emblem", [(-.038, .137, 1.398), (-.013, .144, 1.419),
                       (.012, .146, 1.382), (.035, .141, 1.411),
                       (.049, .138, 1.397), (.001, .146, 1.344)], gold, "chest")

for side, sign in (("L", 1), ("R", -1)):
    def r(z, x, y, rx, ry):
        return (z, sign * x, y, rx, ry)

    loft("Scapula " + side, [
        r(1.299,.115,-.102,.019,.014), r(1.332,.124,-.111,.052,.024),
        r(1.411,.139,-.104,.071,.038), r(1.465,.15,-.080,.069,.031),
        r(1.484,.141,-.067,.047,.016)
    ], armor, "chest")
    trace("Dorsal conductor " + side, [
        (sign*.177,-.080,1.466), (sign*.147,-.126,1.432), (sign*.123,-.143,1.393),
        (sign*.09,-.137,1.360), (sign*.072,-.131,1.311)
    ], .005, gold, "chest")
    trace("Costal seam " + side, [
        (sign*.158,-.096,1.374),(sign*.168,-.087,1.352),
        (sign*.156,-.091,1.291),(sign*.138,-.086,1.263)
    ], .004, trim, "chest")
    rounded("Pectoral " + side, (sign * .109, .089, 1.412), (.079, .050, .051), armor, "chest")
    rounded("Helmet receiver " + side, (sign * .089, -.016, 1.697), (.017, .037, .043), rubber, "head")
    rounded("Temple conductor " + side, (sign * .098, -.015, 1.699), (.009, .026, .020), gold, "head")
    loft("Shoulder " + side, [
        r(1.379,.248,0,.052,.052), r(1.419,.240,-.003,.063,.065),
        r(1.461,.229,-.002,.065,.066), r(1.489,.221,-.002,.043,.059),
        r(1.513,.208,0,.030,.045)
    ], armor, "arm" + side)
    trace("Deltoid seam " + side, [
        (sign*.282,-.058,1.462),(sign*.303,-.035,1.430),(sign*.304,-.022,1.395)
    ], .0045, gold, "arm" + side)
    trace("Helmet cheek guard "+side, [
        (sign*.093,-.037,1.736),(sign*.101,-.036,1.706),(sign*.087,-.041,1.660)
    ], .0043, trim, "head")
    loft("Upper sleeve " + side, [
        r(1.176, .291, 0, .039, .039), r(1.225, .285, .004, .048, .048),
        r(1.303, .276, .006, .057, .061), r(1.396, .249, 0, .062, .071),
        r(1.456, .228, 0, .047, .062)
    ], red, "arm" + side)
    loft("Forearm guard " + side, [
        r(.944, .313, .013, .029, .031), r(.991, .309, .013, .034, .034),
        r(1.065, .302, .012, .048, .043), r(1.14, .296, .009, .045, .041),
        r(1.216, .289, 0, .039, .040)
    ], armor, "fore" + side)
    rounded("Glove " + side, (sign * .318, .01, .914), (.038, .035, .068), rubber, "hand" + side)
    for digit in range(4):
        rounded("Glove digit " + side, (sign * (.292 + digit * .015), .023, .875 + abs(1 - digit) * .006),
                (.008, .013, .026), rubber, "hand" + side)
    loft("Thigh " + side, [
        r(.535, .117, .014, .053, .057), r(.615, .116, .017, .063, .063),
        r(.720, .115, .003, .077, .084), r(.84, .109, .002, .091, .093),
        r(.959, .106, -.004, .087, .091), r(1.017, .105, -.004, .067, .073)
    ], red, "thigh" + side)
    rounded("Thigh panel " + side, (sign * .166, -.002, .782), (.032, .064, .123), armor, "thigh" + side)
    trace("Thigh seam " + side, [
        (sign*.188,-.029,.894),(sign*.192,-.024,.822),
        (sign*.179,-.031,.718),(sign*.162,-.030,.664)
    ], .0053, trim, "thigh" + side)
    trace("Calf seam " + side, [
        (sign*.154,-.035,.468), (sign*.165,-.055,.411),
        (sign*.148,-.062,.316),(sign*.129,-.047,.248)
    ], .0048, gold, "shin" + side)
    loft("Shin " + side, [
        r(.107, .120, -.010, .037, .047), r(.189, .12, -.013, .046, .048),
        r(.323, .12, -.019, .060, .063), r(.425, .118, -.008, .060, .064),
        r(.563, .117, .012, .052, .055), r(.589, .117, .014, .041, .043)
    ], rubber, "shin" + side)
    rounded("Knee guard " + side, (sign * .117, .053, .553), (.057, .031, .080), armor, "shin" + side)
    rounded("Shin guard " + side, (sign * .12, .035, .337), (.052, .027, .155), red, "shin" + side)
    rounded("Calf conductor " + side, (sign * .154, -.028, .302), (.020, .026, .111), gold, "shin" + side)
    loft("Boot " + side, [
        r(.010, .12, .048, .054, .112), r(.029, .12, .05, .057, .116),
        r(.059, .12, .046, .055, .111), r(.084, .12, .012, .048, .083),
        r(.136, .12, -.01, .043, .054), r(.174, .12, -.013, .038, .044)
    ], armor, "foot" + side)

bpy.ops.object.select_all(action="DESELECT")
for obj in pieces:
    obj.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
runner = bpy.context.object
runner.name = "RunnerSuit"
runner.parent = rig
runner.modifiers.new("Skin", "ARMATURE").object = rig

rig.animation_data_create()
for joint in rig.pose.bones:
    joint.rotation_mode = "XYZ"


def animate(name, frames, stride=0, lean=0, airborne=False, brake=False, gesture=""):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame in range(1, frames + 2, 2):
        phase = (frame - 1) / frames * math.tau
        for joint in rig.pose.bones:
            joint.rotation_euler = (0, 0, 0)
            joint.location = (0, 0, 0)
        hips, chest = rig.pose.bones["hips"], rig.pose.bones["chest"]
        hips.rotation_euler.x = -lean
        # Up is local Y on the pelvis bone.
        hips.location.y = (.024 if stride else .009) * (math.cos(phase * 2) - 1)
        chest.rotation_euler.y = math.sin(phase) * stride * .19
        chest.rotation_euler.z = math.sin(phase + .4) * stride * .058
        rig.pose.bones["head"].rotation_euler.x = lean * .68
        for side, shift in (("L", 0), ("R", math.pi)):
            swing = math.sin(phase + shift)
            thigh, shin, foot = [rig.pose.bones[name + side] for name in ("thigh", "shin", "foot")]
            arm, fore = [rig.pose.bones[name + side] for name in ("arm", "fore")]
            thigh.rotation_euler.x = swing * stride + .12 * stride
            thigh.rotation_euler.z = .04 * stride * (1 if side == "L" else -1)
            shin.rotation_euler.x = -stride * (.20 + max(-swing, 0) * 1.04)
            foot.rotation_euler.x = stride * .24 * math.cos(phase + shift)
            arm.rotation_euler.x = -swing * stride * .83 - .05
            fore.rotation_euler.x = .17 + stride * (.92 + .24 * swing)
            arm.rotation_euler.z = (-.09 - stride * .095) * (1 if side == "L" else -1)
            if airborne:
                thigh.rotation_euler.x = .60 if side == "L" else -.42
                shin.rotation_euler.x = -.82 if side == "L" else -.69
                arm.rotation_euler.x = -.44 if side == "L" else .40
                fore.rotation_euler.x = .80
            if brake:
                thigh.rotation_euler.x = .38 if side == "L" else -.21
                shin.rotation_euler.x = -.33
                arm.rotation_euler.x = -.30
        if gesture:
            beat = max(0, math.sin(phase * .5)) ** 1.8
            arm_r = rig.pose.bones["armR"]
            fore_r = rig.pose.bones["foreR"]
            arm_l = rig.pose.bones["armL"]
            fore_l = rig.pose.bones["foreL"]
            thigh_r = rig.pose.bones["thighR"]
            shin_r = rig.pose.bones["shinR"]
            if gesture in ("Jab", "Heavy", "Counter", "Takedown", "Cast", "Redirect"):
                punch = beat * (1.32 if gesture not in ("Heavy", "Takedown") else 1.64)
                arm_r.rotation_euler.x = punch
                fore_r.rotation_euler.x = .7 * (1 - beat) + .07
                arm_l.rotation_euler.x = .3 * beat
                fore_l.rotation_euler.x = 1.04 * beat
                chest.rotation_euler.y = -.75 * beat
                hips.rotation_euler.x = -.28 * beat
                thigh_r.rotation_euler.x = .48 * beat
            elif gesture in ("Dodge", "Slide", "Launch", "Land", "Fall", "Rise"):
                hips.location.y = (-.70 if gesture in ("Fall", "Rise") else -.30 if gesture in ("Launch", "Land") else -.46) * beat
                hips.rotation_euler.x = -.68 * beat
                thigh_r.rotation_euler.x = .85 * beat
                shin_r.rotation_euler.x = -1.04 * beat
                arm_l.rotation_euler.z = .75 * beat
                arm_r.rotation_euler.x = -.59 * beat
            elif gesture in ("Hit", "Phase", "Portal", "Slow", "Mirage", "Tornado", "Shockwave", "Turn"):
                hips.rotation_euler.x = .26 * beat
                chest.rotation_euler.y = (.62 if gesture in ("Tornado", "Turn") else .29) * beat
                arm_r.rotation_euler.x = .57 * beat
                arm_l.rotation_euler.x = -.45 * beat
                if gesture in ("Shockwave", "Portal", "Slow"):
                    arm_l.rotation_euler.x = .72 * beat
                    arm_r.rotation_euler.z = .62 * beat
                    arm_l.rotation_euler.z = -.62 * beat
        for joint in rig.pose.bones:
            joint.keyframe_insert("rotation_euler", frame=frame, group=joint.name)
            joint.keyframe_insert("location", frame=frame, group=joint.name)
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)


bpy.context.scene.render.fps = 30
animate("Idle", 60)
animate("Walk", 42, .24, .015)
animate("Jog", 30, .43, .08)
animate("Sprint", 22, .87, .25)
animate("Boost", 18, 1.11, .44)
animate("Wall", 20, .65, .21)
animate("Water", 18, .86, .27)
animate("Air", 16, .12, .11, airborne=True)
animate("Brake", 20, .15, -.21, brake=True)
for label, frames in (
    ("Jab", 10), ("Heavy", 16), ("Counter", 12), ("Dodge", 10), ("Slide", 20),
    ("Hit", 12), ("Launch", 10), ("Land", 12), ("Fall", 28), ("Rise", 24),
    ("Takedown", 20), ("Cast", 13), ("Phase", 14), ("Portal", 22), ("Slow", 18),
    ("Mirage", 16), ("Tornado", 28), ("Shockwave", 16), ("Redirect", 12), ("Turn", 14),
):
    animate(label, frames, gesture=label)
bpy.context.scene.frame_set(1)
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / "assets/velocity-runner.glb"),
    export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
)
