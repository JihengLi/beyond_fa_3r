#!/usr/bin/env python3
import sys, json, numpy as np, pathlib

profile_dir, out_json = sys.argv[1:3]
bundles = {
    "CG_left",
    "CG_right",
    "UF_left",
    "UF_right",
    "ILF_left",
    "ILF_right",
}

metrics = ["fa", "md", "ad", "rd"]
vec = []

for m in metrics:
    csv_path = pathlib.Path(profile_dir) / f"{m}_profiles.csv"
    header = csv_path.open().readline().lstrip("#").strip().split(";")
    data = np.genfromtxt(csv_path, delimiter=";", skip_header=1)

    for b in bundles:
        col = header.index(b)
        vec.extend(data[:, col].tolist())

vec = (vec + [0.0] * 128)[:128]

with open(out_json, "w") as f:
    json.dump(vec, f, indent=4)
