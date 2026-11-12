#!/usr/bin/env python3
"""Descifra un paquete .3105 y vuelca payload + blobs de reemplazo."""
import hashlib, os, pathlib, plistlib, sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

MAGIC = b"3105PATCH\x00"
PASSWORD = os.environ["P3105"].encode()

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "out")

raw = src.read_bytes()
if not raw.startswith(MAGIC):
    sys.exit("no empieza por 3105PATCH")

env = plistlib.loads(raw[len(MAGIC):])
pkg = env["packageID"]
aadv = env.get("keyAADVersion", env["schemaVersion"])
salt, iters = env["kdfSalt"], env["kdfIterations"]
fp = env["keyFingerprint"]

print(f"packageID={pkg} schema={env['schemaVersion']} aadv={aadv} "
      f"iters={iters} salt={salt.hex()} prot={env.get('isPasswordProtected')}")

if env.get("isPasswordProtected"):
    kek = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32,
                     salt=salt, iterations=iters).derive(PASSWORD)
    w = env["wrappedContentKey"]
    ck = AESGCM(kek).decrypt(w[:12], w[12:-16] + w[-16:],
                             f"3105PATCH/v{aadv}/key/{pkg}".encode())
else:
    ck = env["publicContentKey"]

got = hashlib.sha256(ck).digest()
if got != fp:
    sys.exit(f"fingerprint MISMATCH -> contraseña incorrecta\n{got.hex()}\n{fp.hex()}")
print("fingerprint: MATCH")

p = env["encryptedPayload"]
payload = AESGCM(ck).decrypt(p[:12], p[12:-16] + p[-16:],
                             f"3105PATCH/v{aadv}/payload/{pkg}".encode())

out.mkdir(parents=True, exist_ok=True)
(out / "payload.bplist").write_bytes(payload)
pl = plistlib.loads(payload)
(out / "payload.xml.plist").write_bytes(plistlib.dumps(pl, fmt=plistlib.FMT_XML))

proj = pl.get("project", {})
print("claves de project:", sorted(proj.keys()))
for r in proj.get("rules", []) or []:
    print(f"  regla {r.get('id')} -> {r.get('destinationPath') or r.get('path')}")

n = 0
def walk(node, path):
    global n
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]")
    elif isinstance(node, (bytes, bytearray)) and len(node) > 64:
        n += 1
        safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in path)[-80:]
        f = out / "blobs" / f"{n:03d}{safe}.bin"
        f.parent.mkdir(exist_ok=True)
        f.write_bytes(node)
        print(f"  blob {f.name}  {len(node)} B  <- {path}")

walk(pl, "root")
print(f"blobs volcados: {n}")
