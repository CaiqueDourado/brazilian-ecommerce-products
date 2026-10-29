"""Cover image in English and Portuguese: the 10 largest stores by number of offers.

    python scripts/make_cover.py

Writes docs/img/cover.png (EN, used by README.md) and docs/img/cover.pt-BR.png (PT, used by README.pt-BR.md).
The numbers are the offer counts of the full data (README, "What's inside"), in millions. Needs matplotlib.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
INK, MUTED, GRID, BLUE = "#111111", "#555555", "#e6e8eb", "#2a78d6"
for fam in ("Inter", "DejaVu Sans"):
    try:
        matplotlib.font_manager.findfont(fam, fallback_to_default=False)
        plt.rcParams["font.family"] = fam
        break
    except ValueError:
        pass

STORES = [("Magazine Luiza", 19.7), ("Americanas", 14.3), ("Shoptime", 11.2), ("Submarino", 10.7), ("Extra", 10.3),
          ("Casas Bahia", 9.9), ("Amazon", 7.3), ("Dafiti", 5.9), ("Pontofrio", 4.4), ("Kanui", 1.8)]
T = {
    "": dict(title="Brazilian E-commerce Products",
             sub="114.6M offers · 7,179 stores · 18.3M product groups · 2019–2024 · 10 largest stores",
             x="offers (millions)", unit="M", dec="."),
    ".pt-BR": dict(title="Catálogo de produtos do e-commerce brasileiro",
                   sub="114,6 mi ofertas · 7.179 lojas · 18,3 mi grupos de produto · 2019–2024 · 10 maiores lojas",
                   x="ofertas (milhões)", unit="mi", dec=","),
}


def main() -> None:
    out = ROOT / "docs" / "img"
    names = [s for s, _ in STORES][::-1]
    values = [v for _, v in STORES][::-1]
    for suf, t in T.items():
        fig = plt.figure(figsize=(11, 5.5), dpi=100)
        fig.patch.set_facecolor("white")
        fig.text(0.05, 0.82, t["title"], fontsize=27, weight="bold", color=INK)
        fig.text(0.05, 0.71, t["sub"], fontsize=13.5, color=MUTED)
        ax = fig.add_axes([0.27, 0.13, 0.68, 0.51])
        ax.barh(names, values, color=BLUE, height=0.65)
        for i, v in enumerate(values):
            ax.text(v + 0.25, i, f"{v:.1f}".replace(".", t["dec"]) + f" {t['unit']}", va="center", fontsize=10.5, color=INK)
        ax.set_xlim(0, 22)
        ax.set_xlabel(t["x"], color=MUTED, fontsize=10.5)
        ax.grid(axis="x", color=GRID, lw=0.8)
        ax.set_axisbelow(True)
        for s in ("top", "right", "left"):
            ax.spines[s].set_visible(False)
        ax.spines["bottom"].set_color("#cccccc")
        ax.tick_params(length=0, labelsize=11, colors=INK)
        fig.text(0.05, 0.03, "github.com/CaiqueDourado", fontsize=11, color=MUTED)
        fig.savefig(out / f"cover{suf}.png", facecolor="white")
        plt.close(fig)
    print(f"-> {out}")


if __name__ == "__main__":
    main()
