#!/usr/bin/env python3
"""
image-diff: PNG pixel-level diff with 8x8 grid hotspots and alpha channel check.
Ported from LazyCodex visual-qa cli.ts image-diff.

Usage:
  python3 image-diff.py <reference.png> <actual.png>

Outputs JSON to stdout:
  {
    "dimensionsMatch": bool,
    "reference": {"width": N, "height": N},
    "actual": {"width": N, "height": N},
    "totalPixels": N,
    "diffPixels": N,
    "diffRatio": float (0..1),
    "similarityScore": int (0..100),
    "alphaChannelIntact": bool,
    "hotspots": [
      {"gridX": int, "gridY": int, "x": int, "y": int,
       "width": int, "height": int, "diffRatio": float}
    ],
    "summary": str
  }
"""

import json
import sys
from PIL import Image

GRID_SIZE = 8


def load_rgba(path):
    img = Image.open(path).convert("RGBA")
    return img, img.tobytes(), img.size


def has_transparent_pixels(rgba_bytes):
    # Stride is 4 bytes per pixel, alpha is byte index 3
    for i in range(3, len(rgba_bytes), 4):
        if rgba_bytes[i] < 255:
            return True
    return False


def diff_images(ref_path, act_path):
    ref_img, ref_bytes, (ref_w, ref_h) = load_rgba(ref_path)
    act_img, act_bytes, (act_w, act_h) = load_rgba(act_path)

    overlap_w = min(ref_w, act_w)
    overlap_h = min(ref_h, act_h)
    total = overlap_w * overlap_h

    cols = max(1, min(GRID_SIZE, overlap_w))
    rows = max(1, min(GRID_SIZE, overlap_h))
    cell_diff = [0] * (cols * rows)
    cell_total = [0] * (cols * rows)

    diff_pixels = 0
    for y in range(overlap_h):
        cell_y = min(rows - 1, (y * rows) // overlap_h)
        for x in range(overlap_w):
            cell_x = min(cols - 1, (x * cols) // overlap_w)
            cell_i = cell_y * cols + cell_x
            cell_total[cell_i] += 1

            ref_off = (y * ref_w + x) * 4
            act_off = (y * act_w + x) * 4

            if (
                ref_bytes[ref_off] != act_bytes[act_off]
                or ref_bytes[ref_off + 1] != act_bytes[act_off + 1]
                or ref_bytes[ref_off + 2] != act_bytes[act_off + 2]
                or ref_bytes[ref_off + 3] != act_bytes[act_off + 3]
            ):
                diff_pixels += 1
                cell_diff[cell_i] += 1

    hotspots = []
    for gy in range(rows):
        for gx in range(cols):
            i = gy * cols + gx
            d = cell_diff[i]
            t = cell_total[i]
            if d == 0 or t == 0:
                continue
            left = (gx * overlap_w) // cols
            right = ((gx + 1) * overlap_w) // cols
            top = (gy * overlap_h) // rows
            bottom = ((gy + 1) * overlap_h) // rows
            hotspots.append({
                "gridX": gx,
                "gridY": gy,
                "x": left,
                "y": top,
                "width": right - left,
                "height": bottom - top,
                "diffRatio": round(d / t, 4),
            })
    hotspots.sort(key=lambda h: -h["diffRatio"])

    diff_ratio = 0 if total == 0 else diff_pixels / total
    similarity = round((1 - diff_ratio) * 100)
    dimensions_match = (ref_w == act_w) and (ref_h == act_h)
    alpha_intact = not (has_transparent_pixels(ref_bytes) and not has_transparent_pixels(act_bytes))

    parts = [f"{similarity}/100 similarity", f"{diff_pixels}/{total} pixels differ"]
    if not dimensions_match:
        parts.append("dimensions differ")
    if hotspots:
        parts.append(f"{len(hotspots)} hotspot region(s)")

    return {
        "command": "image-diff",
        "dimensionsMatch": dimensions_match,
        "reference": {"width": ref_w, "height": ref_h},
        "actual": {"width": act_w, "height": act_h},
        "totalPixels": total,
        "diffPixels": diff_pixels,
        "diffRatio": round(diff_ratio, 4),
        "similarityScore": similarity,
        "alphaChannelIntact": alpha_intact,
        "hotspots": hotspots,
        "summary": "; ".join(parts) + ".",
    }


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: image-diff.py <reference.png> <actual.png>\n")
        sys.exit(1)

    try:
        result = diff_images(sys.argv[1], sys.argv[2])
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"image-diff error: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
