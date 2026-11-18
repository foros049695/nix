#!/usr/bin/env python3
"""Pipeline de processamento da logo do Projeto Nix.

Entrada : gravura original (linha preta sobre fundo branco).
Saídas  : SVG vetorizado + PNGs transparentes em várias resoluções/variantes.

Etapas (determinísticas, sem IA generativa — os traços originais são preservados):
  1. Conversão para escala de cinza e remoção de ruído de compressão JPEG.
  2. Upscale Lanczos (fator configurável) + suavização gaussiana leve.
  3. Binarização com limiar alto para preservar hachuras finas.
  4. Vetorização com potrace (curvas Bézier) -> elimina pixelização em qualquer escala.
  5. Renderização do SVG (rsvg-convert) em PNG transparente nas resoluções exigidas.

Uso:
  python3 -m venv /tmp/nixlogo && /tmp/nixlogo/bin/pip install potracer pillow numpy
  /tmp/nixlogo/bin/python scripts/brand/process_logo.py <entrada.jpg> <dir_saida>
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
import potrace
from PIL import Image, ImageFilter

UPSCALE = 4
THRESHOLD = 165  # pixels mais escuros que isto são considerados tinta
TURDSIZE = 6  # remove manchas isoladas (ruído JPEG) menores que N px²


def trace(src: Path) -> tuple[str, int, int]:
    gray = Image.open(src).convert("L")
    gray = gray.filter(ImageFilter.MedianFilter(3))
    w, h = gray.size
    big = gray.resize((w * UPSCALE, h * UPSCALE), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(radius=UPSCALE * 0.45))
    # In potrace.Bitmap(bool_array), True represents background (inverted internally by Bitmap.invert()).
    # Therefore pixels >= THRESHOLD (white background) must be True so only dark ink (< THRESHOLD) is traced.
    background = np.array(big) >= THRESHOLD
    bmp = potrace.Bitmap(background)
    plist = bmp.trace(turdsize=TURDSIZE, alphamax=1.0, opticurve=True, opttolerance=0.2)
    pw, ph = w * UPSCALE, h * UPSCALE
    parts: list[str] = []
    for curve in plist:
        # Collect points to check bounding box and discard outer frame border artifact >= 98% of canvas
        pts: list[tuple[float, float]] = [(curve.start_point.x, curve.start_point.y)]
        for seg in curve.segments:
            if seg.is_corner:
                pts.append((seg.c.x, seg.c.y))
                pts.append((seg.end_point.x, seg.end_point.y))
            else:
                pts.append((seg.c1.x, seg.c1.y))
                pts.append((seg.c2.x, seg.c2.y))
                pts.append((seg.end_point.x, seg.end_point.y))
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        if (max(xs) - min(xs)) >= pw * 0.98 and (max(ys) - min(ys)) >= ph * 0.98:
            continue

        fs = curve.start_point
        parts.append(f"M{fs.x:.2f},{fs.y:.2f}")
        for seg in curve.segments:
            if seg.is_corner:
                parts.append(f"L{seg.c.x:.2f},{seg.c.y:.2f}L{seg.end_point.x:.2f},{seg.end_point.y:.2f}")
            else:
                parts.append(
                    f"C{seg.c1.x:.2f},{seg.c1.y:.2f} {seg.c2.x:.2f},{seg.c2.y:.2f} "
                    f"{seg.end_point.x:.2f},{seg.end_point.y:.2f}"
                )
        parts.append("z")
    return "".join(parts), pw, ph


def svg(path_d: str, w: int, h: int, ink: str, disc: str | None = None) -> str:
    side = max(w, h)
    ox, oy = (side - w) / 2, (side - h) / 2
    disc_el = ""
    if disc:
        # Disco de fundo levemente menor que a moldura original para não vazar além do traço.
        r = side * 0.468
        disc_el = f'<circle cx="{side / 2:.1f}" cy="{side / 2:.1f}" r="{r:.1f}" fill="{disc}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {side} {side}" width="{side}" height="{side}">'
        f"{disc_el}<g transform=\"translate({ox:.1f},{oy:.1f})\">"
        f'<path d="{path_d}" fill="{ink}" fill-rule="evenodd"/></g></svg>'
    )


def render(svg_file: Path, png: Path, size: int) -> None:
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg_file)],
        check=True,
    )


def main() -> None:
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    d, w, h = trace(src)
    variants = {
        # Traço original (escuro #17191E) sobre transparente — temas claros.
        "nix_logo_ink": svg(d, w, h, "#17191E"),
        # Traço claro (#F5F1E6) sobre transparente — temas escuros / AMOLED.
        "nix_logo_light": svg(d, w, h, "#F5F1E6"),
        # Medalhão: gravura original sobre disco claro — ícone de app / launcher.
        "nix_logo_medallion": svg(d, w, h, "#17191E", disc="#F7F4EC"),
    }
    for name, content in variants.items():
        f = out / f"{name}.svg"
        f.write_text(content)
        for size in (2048, 1024, 512, 192, 144, 128, 96, 72, 64, 48):
            render(f, out / f"{name}_{size}.png", size)
    print("ok", w, h)


if __name__ == "__main__":
    main()
