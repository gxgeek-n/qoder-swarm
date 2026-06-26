#!/usr/bin/env python3
"""
image-diff: PNG pixel-level diff with 8x8 grid hotspots and alpha channel check.
Ported from LazyCodex visual-qa cli.ts image-diff. Vectorized with numpy when
available; falls back to PIL ImageChops for environments without numpy.

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

Exit codes:
  0  success
  1  usage error / file not found / invalid PNG
"""

import json
import sys
from pathlib import Path

GRID_SIZE = 8


def load_rgba(path):
    """Load PNG as RGBA. Returns (PIL image, (width, height))."""
    try:
        from PIL import Image, UnidentifiedImageError
    except ImportError:
        sys.stderr.write(
            "image-diff error: Pillow is required. Install with: pip3 install Pillow\n"
        )
        sys.exit(1)

    if not Path(path).is_file():
        sys.stderr.write(f"image-diff error: file not found: {path}\n")
        sys.exit(1)

    try:
        img = Image.open(path).convert("RGBA")
    except UnidentifiedImageError as exc:
        sys.stderr.write(f"image-diff error: not a valid image: {path} ({exc})\n")
        sys.exit(1)
    return img, img.size


def diff_with_numpy(ref_img, act_img):
    """Vectorized diff. ~50-200x faster than the per-pixel loop."""
    import numpy as np

    ref = np.array(ref_img, dtype=np.uint8)  # (H, W, 4)
    act = np.array(act_img, dtype=np.uint8)
    ref_h, ref_w = ref.shape[:2]
    act_h, act_w = act.shape[:2]
    overlap_h = min(ref_h, act_h)
    overlap_w = min(ref_w, act_w)

    ref_crop = ref[:overlap_h, :overlap_w]
    act_crop = act[:overlap_h, :overlap_w]

    # Per-pixel diff mask: any RGBA channel differs
    diff_mask = (ref_crop != act_crop).any(axis=-1)  # (overlap_h, overlap_w) bool
    diff_pixels = int(diff_mask.sum())
    total_pixels = overlap_h * overlap_w

    cols = max(1, min(GRID_SIZE, overlap_w))
    rows = max(1, min(GRID_SIZE, overlap_h))

    # Build per-cell stats by binning row/col indices
    y_idx = np.minimum(rows - 1, np.arange(overlap_h) * rows // overlap_h)
    x_idx = np.minimum(cols - 1, np.arange(overlap_w) * cols // overlap_w)
    cell_idx = y_idx[:, None] * cols + x_idx[None, :]  # (overlap_h, overlap_w)

    flat_cells = cell_idx.ravel()
    flat_diff = diff_mask.ravel()
    cell_total = np.bincount(flat_cells, minlength=cols * rows)
    cell_diff = np.bincount(flat_cells, weights=flat_diff.astype(np.int64), minlength=cols * rows)

    hotspots = []
    for gy in range(rows):
        for gx in range(cols):
            i = gy * cols + gx
            d = int(cell_diff[i])
            t = int(cell_total[i])
            if d == 0 or t == 0:
                continue
            left = (gx * overlap_w) // cols
            right = ((gx + 1) * overlap_w) // cols
            top = (gy * overlap_h) // rows
            bottom = ((gy + 1) * overlap_h) // rows
            hotspots.append({
                "gridX": gx,
                "gridY": gy,
                "x": int(left),
                "y": int(top),
                "width": int(right - left),
                "height": int(bottom - top),
                "diffRatio": round(d / t, 4),
            })
    hotspots.sort(key=lambda h: -h["diffRatio"])

    # Alpha intact: if reference has any transparent pixel, actual must too
    ref_has_transparent = bool((ref_crop[..., 3] < 255).any())
    act_has_transparent = bool((act_crop[..., 3] < 255).any())
    alpha_intact = not (ref_has_transparent and not act_has_transparent)

    return {
        "diff_pixels": diff_pixels,
        "total_pixels": total_pixels,
        "overlap_w": overlap_w,
        "overlap_h": overlap_h,
        "ref_w": ref_w,
        "ref_h": ref_h,
        "act_w": act_w,
        "act_h": act_h,
        "hotspots": hotspots,
        "alpha_intact": alpha_intact,
    }


def diff_with_pil(ref_img, act_img):
    """Fallback path when numpy is not installed. Slower but works."""
    from PIL import ImageChops

    ref_w, ref_h = ref_img.size
    act_w, act_h = act_img.size
    overlap_w = min(ref_w, act_w)
    overlap_h = min(ref_h, act_h)

    ref_crop = ref_img.crop((0, 0, overlap_w, overlap_h))
    act_crop = act_img.crop((0, 0, overlap_w, overlap_h))

    # ImageChops.difference does a vectorized C-level subtract per channel
    delta = ImageChops.difference(ref_crop, act_crop)
    # Pixel differs if max channel delta > 0; iterate bytes (still slower than numpy)
    delta_bytes = delta.tobytes()
    cols = max(1, min(GRID_SIZE, overlap_w))
    rows = max(1, min(GRID_SIZE, overlap_h))
    cell_diff = [0] * (cols * rows)
    cell_total = [0] * (cols * rows)
    diff_pixels = 0

    for y in range(overlap_h):
        cy = min(rows - 1, (y * rows) // overlap_h)
        row_offset = y * overlap_w * 4
        for x in range(overlap_w):
            cx = min(cols - 1, (x * cols) // overlap_w)
            i = cy * cols + cx
            cell_total[i] += 1
            off = row_offset + x * 4
            if delta_bytes[off] or delta_bytes[off + 1] or delta_bytes[off + 2] or delta_bytes[off + 3]:
                diff_pixels += 1
                cell_diff[i] += 1

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

    # Alpha intact: ref transparent pixels must still be transparent in actual
    ref_alpha = ref_crop.split()[3].tobytes()
    act_alpha = act_crop.split()[3].tobytes()
    ref_has_transparent = any(b < 255 for b in ref_alpha)
    act_has_transparent = any(b < 255 for b in act_alpha)
    alpha_intact = not (ref_has_transparent and not act_has_transparent)

    return {
        "diff_pixels": diff_pixels,
        "total_pixels": overlap_w * overlap_h,
        "overlap_w": overlap_w,
        "overlap_h": overlap_h,
        "ref_w": ref_w,
        "ref_h": ref_h,
        "act_w": act_w,
        "act_h": act_h,
        "hotspots": hotspots,
        "alpha_intact": alpha_intact,
    }


def diff_images(ref_path, act_path):
    ref_img, _ = load_rgba(ref_path)
    act_img, _ = load_rgba(act_path)

    try:
        import numpy  # noqa: F401
        stats = diff_with_numpy(ref_img, act_img)
    except ImportError:
        stats = diff_with_pil(ref_img, act_img)

    total = stats["total_pixels"]
    diff_ratio = 0.0 if total == 0 else stats["diff_pixels"] / total
    similarity = round((1 - diff_ratio) * 100)
    dimensions_match = stats["ref_w"] == stats["act_w"] and stats["ref_h"] == stats["act_h"]

    parts = [
        f"{similarity}/100 similarity",
        f"{stats['diff_pixels']}/{total} pixels differ",
    ]
    if not dimensions_match:
        parts.append("dimensions differ")
    if stats["hotspots"]:
        parts.append(f"{len(stats['hotspots'])} hotspot region(s)")

    return {
        "command": "image-diff",
        "dimensionsMatch": dimensions_match,
        "reference": {"width": stats["ref_w"], "height": stats["ref_h"]},
        "actual": {"width": stats["act_w"], "height": stats["act_h"]},
        "totalPixels": total,
        "diffPixels": stats["diff_pixels"],
        "diffRatio": round(diff_ratio, 4),
        "similarityScore": similarity,
        "alphaChannelIntact": stats["alpha_intact"],
        "hotspots": stats["hotspots"],
        "summary": "; ".join(parts) + ".",
    }


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: image-diff.py <reference.png> <actual.png>\n")
        sys.exit(1)
    result = diff_images(sys.argv[1], sys.argv[2])
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
