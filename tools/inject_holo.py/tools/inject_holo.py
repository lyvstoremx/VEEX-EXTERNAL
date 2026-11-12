#!/usr/bin/env python3
import glob, traceback
import UnityPy
from UnityPy.enums import ClassIDType
from UnityPy.files import ObjectReader
from UnityPy.files.SerializedFile import SerializedType
from UnityPy.helpers import TypeTreeHelper
from UnityPy.helpers.Tpk import get_typetree_node
from UnityPy.streams import EndianBinaryWriter
from PIL import Image, ImageDraw, ImageFont

REP = "report.txt"
SRC = glob.glob("work/*.bundle")[0]
OUT = "work/holo_new.bundle"

def log(*a):
    s = " ".join(str(x) for x in a)
    print(s)
    with open(REP, "a", encoding="utf-8") as f:
        f.write(s + "\n")

def build_tex(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype("DejaVuSans-Bold.ttf", 96)
    step, row, y = 175, 0, -14
    while y < size + step:
        x = -50 + (0 if row % 2 == 0 else 88)
        while x < size + step:
            d.text((x, y), "LEVI", font=font, fill=(255, 0, 0, 255))
            x += step
        y += 120
        row += 1
    d.rectangle([0, 0, size - 1, size - 1], outline=(255, 255, 255, 255), width=5)
    d.rectangle([5, 5, size - 6, size - 6], outline=(255, 255, 255, 255), width=2)
    return img.transpose(Image.FLIP_TOP_BOTTOM)

VALUES = {
    "m_Name": "levi_holo",
    "m_ForcedFallbackFormat": 4,
    "m_DownscaleFallback": False,
    "m_IsAlphaChannelOptional": False,
    "m_Width": 512,
    "m_Height": 512,
    "m_TextureFormat": 4,      # RGBA32
    "m_MipCount": 1,
    "m_IsReadable": True,
    "m_MipsStripped": 0,
    "m_ImageSize": 1048576,
}

def fill(node, out, pixels):
    for ch in node.m_Children:
        nm, ty = ch.m_Name, ch.m_Type
        if ty == "TypelessData":
            out[nm] = pixels
        elif nm in VALUES:
            out[nm] = VALUES[nm]
        elif ch.m_Children:
            out[nm] = {}
            fill(ch, out[nm], pixels)
        elif ty in ("string", "char"):
            out[nm] = ""
        elif ty in ("bool",):
            out[nm] = False
        elif ty in ("float", "double"):
            out[nm] = 0.0
        else:
            out[nm] = 0

def main():
    open(REP, "a", encoding="utf-8").close()
    raw = build_tex()
    pixels = raw.tobytes()
    VALUES["m_ImageSize"] = len(pixels)
    log("textura", raw.size, "bytes", len(pixels))

    env = UnityPy.load(SRC)
    sf = None
    for o in env.objects:
        if o.type.name == "Material":
            sf = o.assets_file
            break
    if sf is None:
        log("sin SerializedFile con materiales")
        return 1

    node = get_typetree_node(ClassIDType.Texture2D, sf.version)
    log("CAMPOS:")
    for ch in node.m_Children:
        log("  ", ch.m_Name, "|", ch.m_Type)
    log("VERSION", sf.header.version, sf.unity_version)

    d = {}
    fill(node, d, pixels)
    d["m_CompleteImageSize"] = len(pixels)
    d["image data"] = pixels

    st = object.__new__(SerializedType)
    st.class_id = ClassIDType.Texture2D
    st.is_stripped_type = False
    st.script_type_index = -1
    st.script_id = None
    st.old_type_hash = b"\x00" * 16
    st.node = node
    st.m_ClassName = None
    st.m_NameSpace = None
    st.m_AssemblyName = None
    st.type_dependencies = ()
    st.node_info_handler = None
    sf.types.append(st)
    type_id = len(sf.types) - 1

    w = EndianBinaryWriter(endian=sf.reader.endian)
    TypeTreeHelper.write_typetree(d, node, w, sf)
    blob = w.bytes
    log("blob texture", len(blob), "type_id", type_id)

    new_id = max(sf.objects.keys()) + 1
    obj = ObjectReader(sf, sf.reader, new_id, type_id, st,
                       ClassIDType.Texture2D, ClassIDType.Texture2D,
                       0, len(blob), None, None, blob)
    sf.objects[new_id] = obj
    log("path_id nuevo", new_id)

    hechos = 0
    for o in list(env.objects):
        if o.type.name != "Material":
            continue
        t = o.read_typetree()
        sp = t.get("m_SavedProperties") or {}
        for e in sp.get("m_TexEnvs") or []:
            if e.get("first") in ("_Tex", "_DisTex", "_Mask", "_EmissTex"):
                e["second"]["m_Texture"]["m_PathID"] = new_id
                e["second"]["m_Texture"]["m_FileID"] = 0
                e["second"]["m_Scale"] = {"x": 1.0, "y": 1.0}
                e["second"]["m_Offset"] = {"x": 0.0, "y": 0.0}
        for e in sp.get("m_Colors") or []:
            if e.get("first") in ("_Color", "_Color_Tex", "_EdgeColor"):
                e["second"] = {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
        o.save_typetree(t)
        hechos += 1
    log("materiales parcheados", hechos)

    f = list(env.files.values())[0]
    data = f.save(packer="original")
    open(OUT, "wb").write(data)
    log("bundle nuevo", len(data), "B")
    return 0

try:
    raise SystemExit(main())
except SystemExit:
    raise
except Exception:
    log("FALLO")
    log(traceback.format_exc())
    raise SystemExit(1)
