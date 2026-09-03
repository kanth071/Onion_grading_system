"""
Fixes a real labeling bug: build_real_onion_dataset.py collapsed every
non-"onion" Roboflow box into a single generic "bad" bucket, and the
merged/ dataset then labeled every one of those crops as class 1
"damaged" - discarding the original fine-grained labels (sprouted,
rotten, cuts, black smut, ...) that are still recoverable from
roboflow_meta/boxes.txt via the crop filename (base image + box index).

This rewrites merged_v2/{train,valid}/labels/cropbad_*.txt with the
correct class id instead of a blanket "damaged".
"""
import os
import re
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # onion grading/
BOXES_TXT = os.path.join(os.path.dirname(ROOT), "onion_grading", "roboflow_meta", "boxes.txt")
DATASET = os.path.join(ROOT, "training", "merged_v2")

CLASS_IDS = {"healthy": 0, "damaged": 1, "rotten": 2, "sprouted": 3}

PAT = re.compile(r"^(.*?)_(train|valid|test)_([0-9a-fA-F]{8})_(\d+)(?:_augflip_[hv])?\.jpg$")


def load_box_labels():
    box_data = {}
    with open(BOXES_TXT, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("|")
            name = parts[0]
            labels = []
            if len(parts) > 3 and parts[3]:
                for b in parts[3].split(";"):
                    labels.append(b.split(",")[0])
            box_data[name] = labels
    return box_data


def norm_label(label: str) -> str:
    l = label.lower()
    if "sprout" in l or "root" in l:
        return "sprouted"
    if "rotten" in l:
        return "rotten"
    if l in ("onion", "stem"):
        return "damaged"  # no real defect signal in the label; keep conservative default
    return "damaged"  # cuts, black smut, discoloured, staining, etc.


def main():
    box_data = load_box_labels()
    counts = collections.Counter()
    missed = 0

    for split in ("train", "valid"):
        labels_dir = os.path.join(DATASET, split, "labels")
        for fn in os.listdir(labels_dir):
            if not fn.startswith("cropbad_") or not fn.endswith(".txt"):
                continue
            img_fn = fn[len("cropbad_"):-len(".txt")] + ".jpg"
            m = PAT.match(img_fn)
            if not m:
                missed += 1
                continue
            base, _split, _variant, idx = m.groups()
            key = base + ".jpg"
            labels = box_data.get(key)
            if not labels or int(idx) >= len(labels):
                missed += 1
                continue
            new_class = CLASS_IDS[norm_label(labels[int(idx)])]

            path = os.path.join(labels_dir, fn)
            with open(path) as f:
                lines = f.read().strip().splitlines()
            new_lines = []
            for line in lines:
                parts = line.split()
                parts[0] = str(new_class)
                new_lines.append(" ".join(parts))
            with open(path, "w") as f:
                f.write("\n".join(new_lines) + "\n")

            counts[(split, new_class)] += 1

    print("Relabeled counts (split, class_id) -> count:")
    for k, v in sorted(counts.items()):
        print(f"  {k}: {v}")
    print("Missed (no label recovered, left as damaged):", missed)


if __name__ == "__main__":
    main()
