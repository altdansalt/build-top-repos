#!/usr/bin/env python3
"""Generate an OCI runtime config.json for a bundle.

We start from `crun spec --rootless` (canonical, tracks the crun version) and
mutate it for our environment:
  - writable root
  - multi-id uid/gid mappings (needs newuidmap/newgidmap on the host)
  - a working capability set (the rootless default omits CAP_CHOWN -> breaks dpkg)
  - share the host network namespace (so apt/npm can fetch)
  - PATH/HOME and the command to run

Usage: gen_config.py <crun> <bundle_dir> <cwd> <args_json> [mounts_json]
where <args_json> is a JSON list, e.g. '["/bin/sh","-c","..."]', and the
optional [mounts_json] is a JSON list of extra OCI mounts to append.
"""
import glob
import json
import os
import subprocess
import sys

CRUN, BUNDLE, CWD, ARGS_JSON = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
EXTRA_MOUNTS = json.loads(sys.argv[5]) if len(sys.argv) > 5 else []

# Canonical rootless spec, written to BUNDLE/config.json.
subprocess.run([CRUN, "spec", "--rootless"], cwd=BUNDLE, check=True)
cfg_path = BUNDLE + "/config.json"
c = json.load(open(cfg_path))

c["root"]["readonly"] = False
c["process"]["terminal"] = False
c["process"]["cwd"] = CWD
c["process"]["args"] = json.loads(ARGS_JSON)

# Auto-add any language toolchain's bin dir: a toolchain that drops tools under
# /opt/<name>/bin (Node, Go, ...) is picked up here without editing this file.
opt_bins = [
    "/opt/%s/bin" % os.path.basename(os.path.dirname(p))
    for p in sorted(glob.glob(os.path.join(BUNDLE, "rootfs/opt/*/bin")))
]
path = ":".join(opt_bins + ["/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin"])

env = [e for e in c["process"]["env"] if not e.startswith(("PATH=", "HOME="))]
env.append("PATH=" + path)
env.append("HOME=/root")
c["process"]["env"] = env

caps = [
    "CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_FOWNER", "CAP_FSETID",
    "CAP_SETGID", "CAP_SETUID", "CAP_SETPCAP", "CAP_NET_BIND_SERVICE",
    "CAP_KILL", "CAP_AUDIT_WRITE", "CAP_MKNOD", "CAP_SETFCAP",
]
for k in ("bounding", "effective", "permitted", "inheritable"):
    c["process"]["capabilities"][k] = list(caps)

# Multi-id rootless mapping: container 0 -> host 1000, then 1.. -> host 100000..
c["linux"]["uidMappings"] = [
    {"containerID": 0, "hostID": 1000, "size": 1},
    {"containerID": 1, "hostID": 100000, "size": 65536},
]
c["linux"]["gidMappings"] = [
    {"containerID": 0, "hostID": 1000, "size": 1},
    {"containerID": 1, "hostID": 100000, "size": 65536},
]

# Share the host network namespace (drop the isolated one) for network access.
c["linux"]["namespaces"] = [n for n in c["linux"]["namespaces"] if n.get("type") != "network"]

c["mounts"].extend(EXTRA_MOUNTS)

json.dump(c, open(cfg_path, "w"), indent=2)
