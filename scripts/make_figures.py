"""Draw the README figures (English and Portuguese) into docs/img/.

Usage:  python scripts/make_figures.py

Reads the sample (sample/*.csv) for the price example and fixed numbers from the full build for the
barcode chart. The image-signature figures use a drawn lamp, not a real store photo (images are not
distributed); the steps are the same as in the original pipeline (16x16, grayscale, SHA-256).
"""

from __future__ import annotations

import hashlib
import io
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "img"
INK, MUTED, BLUE, LIGHT_BLUE = "#1f1f1f", "#666666", "#2b7bd9", "#9bb8dd"
for family in ("Inter", "DejaVu Sans"):
    try:
        matplotlib.font_manager.findfont(family, fallback_to_default=False)
        plt.rcParams["font.family"] = family
        break
    except ValueError:
        continue

# barcode classes in the full build (build_stats.json, code_type)
CODE_TYPE = {"gtin_valido": 25_492_338, "codigo_alfanumerico": 3_782_277, "numero_curto": 1_464_491,
             "gtin_digito_errado": 441_335, "numero_outro_tamanho": 424_226, "vazio": 247_843,
             "texto": 216_422, "notacao_cientifica": 50_463}

T = {
    "en": {
        "sig_title": "Image signature: from product photo to a matching key",
        "steps": ["1. Product photo", "2. Shrink to 16×16", "3. Grayscale", "4. SHA-256"],
        "subs": ["as downloaded\nfrom the store", "256 pixels left;\nfine detail is gone",
                 "one byte per pixel\n(0 = black, 255 = white)", "of the 256 bytes, written in\ndecimal: the image_hash"],
        "use": "5. Use it",
        "use1": "Same signature on two offers\n→ same image\n→ the offers join one group\n   (one of the 12 matching keys)",
        "use2": "Same signature on more than\n100 products\n→ \"no photo\" placeholder or logo\n→ image_is_generic = true,\n   no longer used for matching",
        "hash_title": "Why an exact hash is fragile, and what a perceptual hash fixes",
        "hash_sub": "The same photo saved at 1000 px and at 300 px (JPEG). After shrinking to 16×16 gray, the pixels are almost equal.",
        "diff": "difference: {n} of 256 pixels, max {m}",
        "sha": "SHA-256 (used in this dataset)",
        "sha_txt": "Completely different: a change of 1 in one pixel changes every byte.\nIt matches only the same image file, as served by sister stores.",
        "dh": "Difference hash (dHash, what I would use today)",
        "dh_txt": "{b} of 256 bits differ → compare by Hamming distance\n(a few bits apart = same picture).",
        "dh_txt2": "Matches resized and recompressed copies of the same photo.",
        "price_title": "One product, many stores: Taschibra TLF 28 pendant lamp",
        "price_sub": "Group 415923 · {n} priced offers in {s} stores · R\\$ {lo} to R\\$ {hi} (+{pct}%) · prices collected on different dates, 2019–2020",
        "price_x": "price (R$)",
        "bar_title": "What stores put in the barcode field",
        "bar_sub": "32,119,395 identifier values, classified by eans.code_type",
        "labels": {"gtin_valido": "Valid GTIN (check digit OK)", "codigo_alfanumerico": "Store SKU (letters and digits)",
                   "numero_curto": "Short number", "gtin_digito_errado": "GTIN with a wrong check digit",
                   "numero_outro_tamanho": "Number of another length (incl. NCM)", "vazio": "Empty", "texto": "Text",
                   "notacao_cientifica": "Broken by Excel (7.89E+12)"},
        "m_title": "Matching: 11 text and code keys plus the image signature",
        "m_sub": "For each new offer, the routine collects every offer that shares a key with it, then every offer that shares a key with those.",
        "new": "New\noffer",
        "hop1": "Hop 1: offers that share any key",
        "keys": ["Long EAN", "Exact name", "Name fingerprint", "Metaphone", "N-grams", "Token fingerprint", "Same URL",
                 "Short EAN + brand", "… + brand tokens", "… + brand fingerprint", "… + brand n-grams", "Image signature"],
        "check": "EAN matches whose names\nshare no word are dropped\n(951k refusals logged)",
        "hop2": "Hop 2: offers that share\na key with those",
        "dec_q": "Any of them already\nin a group?",
        "dec_yes": "Yes: all join the\nlowest group id",
        "dec_no": "No: they form\na new group",
        "guards_title": "Before matching",
        "guards": [("EAN blacklist", "\"SEM GTIN\", 1000000000000, letters only,\ntruncated (\"90E+12\"), >5 products in one store"),
                   ("Generic images", "a signature on >100 products\nis not used as a key"),
                   ("Generic brands", "\"Importado\", \"Original\", \"Não Informado\"…\nare blanked before brand keys")],
        "note": "group_rule_original = key of the first match · group_rule = key after regrouping",
        "suffix": "",
    },
    "pt": {
        "sig_title": "Assinatura da imagem: da foto do produto a uma chave de agrupamento",
        "steps": ["1. Foto do produto", "2. Reduz a 16×16", "3. Tons de cinza", "4. SHA-256"],
        "subs": ["como foi baixada\nda loja", "sobram 256 pixels;\nos detalhes somem",
                 "um byte por pixel\n(0 = preto, 255 = branco)", "dos 256 bytes, escrito em\ndecimal: o image_hash"],
        "use": "5. Uso",
        "use1": "Mesma assinatura em duas ofertas\n→ mesma imagem\n→ as ofertas entram no mesmo grupo\n   (uma das 12 chaves)",
        "use2": "Mesma assinatura em mais de\n100 produtos\n→ imagem \"sem foto\" ou logo\n→ image_is_generic = true,\n   deixa de agrupar",
        "hash_title": "Por que um hash exato é frágil, e o que um hash perceptual resolve",
        "hash_sub": "A mesma foto salva com 1000 px e com 300 px (JPEG). Reduzidas a 16×16 em cinza, os pixels ficam quase iguais.",
        "diff": "diferença: {n} de 256 pixels, no máximo {m}",
        "sha": "SHA-256 (usado nesta base)",
        "sha_txt": "Totalmente diferentes: mudar 1 num pixel muda todos os bytes.\nSó acha o mesmo arquivo de imagem, como o das lojas do mesmo grupo.",
        "dh": "Hash de diferença (dHash, o que eu usaria hoje)",
        "dh_txt": "{b} de 256 bits diferem → comparar pela distância de Hamming\n(poucos bits de diferença = mesma foto).",
        "dh_txt2": "Acha cópias redimensionadas e recomprimidas da mesma foto.",
        "price_title": "Um produto, muitas lojas: pendente Taschibra TLF 28",
        "price_sub": "Grupo 415923 · {n} ofertas com preço em {s} lojas · R\\$ {lo} a R\\$ {hi} (+{pct}%) · preços coletados em datas diferentes, 2019–2020",
        "price_x": "preço (R$)",
        "bar_title": "O que as lojas põem no campo de código de barras",
        "bar_sub": "32.119.395 valores de identificação, classificados em eans.code_type",
        "labels": {"gtin_valido": "GTIN válido (dígito confere)", "codigo_alfanumerico": "SKU da loja (letras e números)",
                   "numero_curto": "Número curto", "gtin_digito_errado": "GTIN com dígito errado",
                   "numero_outro_tamanho": "Número de outro tamanho (inclui NCM)", "vazio": "Vazio", "texto": "Texto",
                   "notacao_cientifica": "Estragado pelo Excel (7,89E+12)"},
        "m_title": "Agrupamento: 11 chaves de texto e código, mais a assinatura da imagem",
        "m_sub": "Para cada oferta nova, a rotina junta todas as ofertas que têm alguma chave igual, e depois as que têm chave igual a essas.",
        "new": "Oferta\nnova",
        "hop1": "Salto 1: ofertas com qualquer chave igual",
        "keys": ["EAN longo", "Nome exato", "Fingerprint do nome", "Metaphone", "N-gramas", "Fingerprint dos tokens", "Mesma URL",
                 "EAN curto + marca", "… + tokens da marca", "… + fingerprint da marca", "… + n-gramas da marca", "Assinatura da imagem"],
        "check": "Casamentos por EAN cujos\nnomes não têm palavra em\ncomum são descartados\n(951 mil recusas)",
        "hop2": "Salto 2: ofertas com chave\nigual a essas",
        "dec_q": "Alguma já está\nnum grupo?",
        "dec_yes": "Sim: todas entram no\ngrupo de menor id",
        "dec_no": "Não: formam\num grupo novo",
        "guards_title": "Antes do agrupamento",
        "guards": [("Lista negra de EAN", "\"SEM GTIN\", 1000000000000, só letras,\ntruncado (\"90E+12\"), >5 produtos na mesma loja"),
                   ("Imagens genéricas", "assinatura em >100 produtos\nnão é usada como chave"),
                   ("Marcas genéricas", "\"Importado\", \"Original\", \"Não Informado\"…\nviram vazio antes das chaves de marca")],
        "note": "group_rule_original = chave do primeiro casamento · group_rule = chave depois do reagrupamento",
        "suffix": ".pt-BR",
    },
}


def br(x: float, decimals: int = 2) -> str:
    return f"{x:,.{decimals}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def lamp(size: int = 1000) -> Image.Image:
    im = Image.new("RGB", (size, size), "white")
    d = ImageDraw.Draw(im)
    s = size / 1000
    d.line([(500 * s, 0), (500 * s, 330 * s)], fill=(40, 40, 40), width=int(10 * s))
    d.rectangle([470 * s, 320 * s, 530 * s, 380 * s], fill=(30, 30, 30))
    d.polygon([(500 * s, 370 * s), (250 * s, 700 * s), (750 * s, 700 * s)], fill=(25, 25, 28))
    d.ellipse([250 * s, 660 * s, 750 * s, 740 * s], fill=(60, 60, 64))
    d.ellipse([440 * s, 690 * s, 560 * s, 780 * s], fill=(255, 214, 120))
    return im


def jpeg(im: Image.Image, size: int, quality: int) -> Image.Image:
    buf = io.BytesIO()
    im.resize((size, size), Image.LANCZOS).save(buf, "JPEG", quality=quality)
    return Image.open(io.BytesIO(buf.getvalue())).convert("RGB")


def gray16(im: Image.Image) -> np.ndarray:
    return np.asarray(im.resize((16, 16), Image.LANCZOS).convert("L"), dtype=np.uint8)


def signature(g: np.ndarray) -> str:
    return "".join(str(b) for b in hashlib.sha256(g.tobytes()).digest())


def dhash(im: Image.Image) -> np.ndarray:
    a = np.asarray(im.convert("L").resize((17, 16), Image.LANCZOS), dtype=int)
    return (a[:, 1:] > a[:, :-1]).flatten()


def frame(ax) -> None:
    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_color("#dddddd")


def fig_signature(t: dict, big: Image.Image) -> None:
    g = gray16(big)
    s = signature(g)
    fig = plt.figure(figsize=(13, 4.6), dpi=110)
    fig.text(0.025, 0.91, t["sig_title"], fontsize=19, weight="bold", color=INK)
    xs, w = [0.025, 0.205, 0.385, 0.565], 0.15
    for i, (x, title, sub) in enumerate(zip(xs, t["steps"], t["subs"])):
        ax = fig.add_axes([x, 0.24, w, 0.55])
        frame(ax)
        if i == 0:
            ax.imshow(big)
        elif i == 1:
            ax.imshow(np.asarray(big.resize((16, 16), Image.LANCZOS)), interpolation="nearest")
        elif i == 2:
            ax.imshow(g, cmap="gray", interpolation="nearest", vmin=0, vmax=255)
        else:
            ax.axis("off")
            ax.text(0.5, 0.5, "\n".join(s[j:j + 17] for j in range(0, len(s), 17)), ha="center", va="center",
                    family="DejaVu Sans Mono", fontsize=11, color=INK,
                    bbox=dict(boxstyle="round,pad=0.6", fc="#f3f6fb", ec="#c9d6ea"))
        fig.text(x, 0.16, title, fontsize=12.5, weight="bold", color=INK)
        fig.text(x, 0.03, sub, fontsize=10.5, color=MUTED, va="bottom")
        fig.text(x + w + 0.008, 0.5, "→", fontsize=26, color=BLUE, va="center")
    ax = fig.add_axes([0.75, 0.06, 0.24, 0.76])
    ax.axis("off")
    ax.text(0, 0.99, t["use"], fontsize=12.5, weight="bold", color=INK, va="top")
    ax.text(0, 0.86, t["use1"], fontsize=10.5, color=INK, va="top", linespacing=1.4)
    ax.text(0, 0.44, t["use2"], fontsize=10.5, color=INK, va="top", linespacing=1.4)
    fig.savefig(OUT / f"image-signature{t['suffix']}.png", facecolor="white")
    plt.close(fig)


def fig_hash(t: dict, big: Image.Image, small: Image.Image) -> None:
    g1, g2 = gray16(big), gray16(small)
    diff = np.abs(g1.astype(int) - g2.astype(int))
    bits = int((dhash(big) != dhash(small)).sum())
    fig = plt.figure(figsize=(12, 4.4), dpi=110)
    fig.text(0.03, 0.90, t["hash_title"], fontsize=19, weight="bold", color=INK)
    fig.text(0.03, 0.82, t["hash_sub"], fontsize=11.5, color=MUTED)
    for k, (g, label) in enumerate([(g1, "1000 px → 16×16"), (g2, "300 px → 16×16")]):
        ax = fig.add_axes([0.03 + k * 0.16, 0.14, 0.14, 0.56])
        ax.imshow(g, cmap="gray", interpolation="nearest", vmin=0, vmax=255)
        frame(ax)
        fig.text(0.03 + k * 0.16, 0.06, label, fontsize=11, color=INK)
    ax = fig.add_axes([0.35, 0.14, 0.14, 0.56])
    ax.imshow(diff, cmap="Reds", interpolation="nearest", vmin=0, vmax=4)
    frame(ax)
    fig.text(0.35, 0.06, t["diff"].format(n=int((diff > 0).sum()), m=int(diff.max())), fontsize=11, color=INK)
    ax = fig.add_axes([0.53, 0.08, 0.45, 0.66])
    ax.axis("off")
    ax.text(0, 0.97, t["sha"], fontsize=13, weight="bold", color=INK, va="top")
    ax.text(0, 0.84, signature(g1)[:42] + "…\n" + signature(g2)[:42] + "…", family="DejaVu Sans Mono",
            fontsize=10.5, color=INK, va="top")
    ax.text(0, 0.64, t["sha_txt"], fontsize=10.5, color=MUTED, va="top")
    ax.text(0, 0.40, t["dh"], fontsize=13, weight="bold", color=INK, va="top")
    ax.text(0, 0.27, t["dh_txt"].format(b=bits), fontsize=10.5, color=INK, va="top")
    ax.text(0, 0.09, t["dh_txt2"], fontsize=10.5, color=MUTED, va="top")
    fig.savefig(OUT / f"exact-vs-perceptual-hash{t['suffix']}.png", facecolor="white")
    plt.close(fig)


def fig_prices(t: dict) -> None:
    sample = (ROOT / "sample").as_posix()
    df = duckdb.sql(f"""
        SELECT l.name AS store, p.price
        FROM read_csv_auto('{sample}/produtos.csv') p
        JOIN read_csv_auto('{sample}/lojas.csv') l ON l.id = p.store_id
        WHERE p.group_id = 415923 AND p.price IS NOT NULL
    """).df()
    order = df.groupby("store").price.min().sort_values(ascending=False).index.tolist()
    lo, hi = df.price.min(), df.price.max()
    fig = plt.figure(figsize=(11, 5.2), dpi=110)
    fig.text(0.03, 0.92, t["price_title"], fontsize=18, weight="bold", color=INK)
    fig.text(0.03, 0.85, t["price_sub"].format(n=len(df), s=len(order), lo=br(lo), hi=br(hi),
                                               pct=round((hi / lo - 1) * 100)), fontsize=11.5, color=MUTED)
    ax = fig.add_axes([0.17, 0.13, 0.78, 0.66])
    y = {s: i for i, s in enumerate(order)}
    ax.scatter(df.price, [y[s] for s in df.store], s=70, color=BLUE, edgecolor="white", linewidth=1.5, zorder=3)
    ax.set_yticks(range(len(order)))
    ax.set_yticklabels(order)
    for sp in ["top", "right", "left"]:
        ax.spines[sp].set_visible(False)
    ax.spines["bottom"].set_color("#cccccc")
    ax.tick_params(left=False, labelsize=11, colors="#333333")
    ax.grid(axis="x", color="#e8e8e8")
    ax.set_axisbelow(True)
    ax.set_xlabel(t["price_x"], fontsize=11, color=MUTED)
    fig.savefig(OUT / f"one-product-many-stores{t['suffix']}.png", facecolor="white")
    plt.close(fig)


def fig_barcodes(t: dict, lang: str) -> None:
    total = sum(CODE_TYPE.values())
    items = list(CODE_TYPE.items())[::-1]
    fig = plt.figure(figsize=(11, 4.8), dpi=110)
    fig.text(0.03, 0.91, t["bar_title"], fontsize=18, weight="bold", color=INK)
    fig.text(0.03, 0.84, t["bar_sub"], fontsize=12, color=MUTED)
    ax = fig.add_axes([0.30, 0.08, 0.62, 0.70])
    bars = ax.barh([t["labels"][k] for k, _ in items], [v / total * 100 for _, v in items],
                   color=[BLUE if k == "gtin_valido" else LIGHT_BLUE for k, _ in items], height=0.66)
    for bar, (_, v) in zip(bars, items):
        pct = f"{v / total * 100:.1f}%"
        amount = f"{v / 1e6:.2f}M" if v >= 1e6 else f"{v / 1e3:,.0f}k"
        if lang == "pt":
            pct, amount = pct.replace(".", ","), amount.replace(".", ",").replace("M", " mi").replace("k", " mil")
        ax.text(bar.get_width() + 0.6, bar.get_y() + bar.get_height() / 2, f"{pct}  ({amount})", va="center",
                fontsize=10.5, color="#333333")
    for sp in ax.spines.values():
        sp.set_visible(False)
    ax.set_xticks([])
    ax.tick_params(left=False, labelsize=11, colors="#333333")
    ax.set_xlim(0, 95)
    fig.savefig(OUT / f"barcode-quality{t['suffix']}.png", facecolor="white")
    plt.close(fig)


def fig_matching(t: dict) -> None:
    from matplotlib.patches import FancyBboxPatch

    def box(ax, x, y, w, h, fc="#eef4fc", ec="#c9d6ea"):
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.004,rounding_size=0.012", fc=fc, ec=ec, lw=1))

    def arrow(ax, x1, y1, x2, y2):
        ax.annotate("", xy=(x2, y2), xytext=(x1, y1), arrowprops=dict(arrowstyle="->", color=BLUE, lw=1.6))

    fig = plt.figure(figsize=(13, 6.2), dpi=110)
    fig.text(0.025, 0.93, t["m_title"], fontsize=18, weight="bold", color=INK)
    fig.text(0.025, 0.875, t["m_sub"], fontsize=11.5, color=MUTED)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    yc = 0.58
    box(ax, 0.025, yc - 0.06, 0.07, 0.12, fc="#ffffff", ec="#999999")
    ax.text(0.06, yc, t["new"], ha="center", va="center", fontsize=11, weight="bold", color=INK)
    arrow(ax, 0.097, yc, 0.118, yc)
    # hop 1: grid of 12 keys
    box(ax, 0.12, 0.33, 0.43, 0.48, fc="#f7f9fc", ec="#dde5f0")
    ax.text(0.13, 0.785, t["hop1"], fontsize=11.5, weight="bold", color=INK, va="top")
    for k, key in enumerate(t["keys"]):
        r, c = divmod(k, 3)
        x, y = 0.13 + c * 0.139, 0.67 - r * 0.085
        image = k == len(t["keys"]) - 1
        box(ax, x, y, 0.131, 0.062, fc="#fff3d6" if image else "#eef4fc", ec="#f0d9a8" if image else "#c9d6ea")
        ax.text(x + 0.0655, y + 0.031, key, ha="center", va="center", fontsize=9.6, color=INK)
    arrow(ax, 0.552, yc, 0.573, yc)
    box(ax, 0.575, 0.60, 0.15, 0.14, fc="#fdecec", ec="#f1c4c4")
    ax.text(0.65, 0.67, t["check"], ha="center", va="center", fontsize=9.6, color=INK, linespacing=1.3)
    box(ax, 0.575, 0.40, 0.15, 0.13)
    ax.text(0.65, 0.465, t["hop2"], ha="center", va="center", fontsize=10.3, weight="bold", color=INK, linespacing=1.3)
    arrow(ax, 0.65, 0.598, 0.65, 0.533)
    arrow(ax, 0.727, 0.465, 0.75, 0.465)
    box(ax, 0.752, 0.40, 0.11, 0.13, fc="#ffffff", ec="#999999")
    ax.text(0.807, 0.465, t["dec_q"], ha="center", va="center", fontsize=10, color=INK, linespacing=1.3)
    arrow(ax, 0.864, 0.50, 0.878, 0.60)
    arrow(ax, 0.864, 0.43, 0.878, 0.33)
    box(ax, 0.88, 0.56, 0.105, 0.11, fc="#e8f5ec", ec="#b9dcc4")
    ax.text(0.9325, 0.615, t["dec_yes"], ha="center", va="center", fontsize=9.8, color=INK, linespacing=1.3)
    box(ax, 0.88, 0.27, 0.105, 0.11, fc="#e8f5ec", ec="#b9dcc4")
    ax.text(0.9325, 0.325, t["dec_no"], ha="center", va="center", fontsize=9.8, color=INK, linespacing=1.3)
    ax.text(0.025, 0.25, t["guards_title"], fontsize=12, weight="bold", color=INK)
    for i, (title, body) in enumerate(t["guards"]):
        x = 0.025 + i * 0.29
        ax.text(x, 0.195, title, fontsize=10.8, weight="bold", color=INK, va="top")
        ax.text(x, 0.145, body, fontsize=9.8, color=MUTED, va="top", linespacing=1.35)
    ax.text(0.025, 0.035, t["note"], fontsize=10, color=MUTED, family="DejaVu Sans Mono")
    fig.savefig(OUT / f"matching{t['suffix']}.png", facecolor="white")
    plt.close(fig)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    original = lamp()
    big, small = jpeg(original, 1000, 95), jpeg(original, 300, 70)
    for lang, t in T.items():
        fig_signature(t, big)
        fig_hash(t, big, small)
        fig_prices(t)
        fig_barcodes(t, lang)
        fig_matching(t)
    print("figures written to", OUT)


if __name__ == "__main__":
    main()
