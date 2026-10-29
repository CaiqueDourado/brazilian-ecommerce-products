"""Write one product group as nested JSON (docs/example-product.json), built from the sample.

    python scripts/make_json.py

Joins sample/*.csv: group -> its offers -> store (name, url, platform), barcodes, categories and
spec sheet. The group is fixed (GROUP_ID): a car CD player sold by 8 stores, with prices, barcodes and
a spec sheet. Needs pandas (requirements.txt).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / "sample"
GROUP_ID = 1341338


def clean(v):
    """NaN -> None, numpy scalars -> plain Python."""
    if v is None or (isinstance(v, float) and math.isnan(v)) or v is pd.NA:
        return None
    return v.item() if hasattr(v, "item") else v


def ts(v) -> str | None:
    return None if pd.isna(v) else str(v)[:19]


def read(name: str, **kw) -> pd.DataFrame:
    return pd.read_csv(SAMPLE / f"{name}.csv", keep_default_na=True, **kw)


def build() -> dict:
    grupos = read("grupos")
    produtos = read("produtos", dtype={"brand": str})
    lojas = read("lojas")
    plataformas = read("plataformas").rename(columns={"id": "platform_id", "name": "platform"})
    eans = read("eans", dtype={"code": str, "value_raw": str})
    categorias = read("categorias")
    ficha = read("ficha", dtype={"value": str})

    g = grupos.loc[grupos["id"] == GROUP_ID].iloc[0]
    offers = produtos.loc[produtos["group_id"] == GROUP_ID].sort_values("id")
    stores = lojas.merge(plataformas, on="platform_id", how="left").set_index("id")

    out_offers = []
    for _, p in offers.iterrows():
        s = stores.loc[p["store_id"]]
        codes = eans.loc[eans["product_id"] == p["id"]].sort_values("code_index")
        cats = categorias.loc[categorias["product_id"] == p["id"]].sort_values(["level", "id"])
        spec = ficha.loc[ficha["product_id"] == p["id"]].sort_values(["position", "id"])
        out_offers.append({
            "id": int(p["id"]),
            "store": {"id": int(p["store_id"]), "name": s["name"], "url": s["url"], "platform": clean(s["platform"])},
            "name": p["name"],
            "brand": clean(p["brand"]),
            "price": clean(p["price"]),
            "price_flag": p["price_flag"],
            "availability": clean(p["availability"]),
            "collected_at": ts(p["collected_at"]),
            "group_rule_original": clean(p["group_rule_original"]),
            "group_rule": clean(p["group_rule"]),
            "image_is_generic": bool(p["image_is_generic"]),
            "eans": [{"code": r["code"], "code_type": r["code_type"]} for _, r in codes.iterrows()],
            "categories": [{"category": r["category"], "category_normalized": r["category_normalized"]}
                           for _, r in cats.iterrows()],
            "ficha": {r["key"]: clean(r["value"]) for _, r in spec.iterrows()},
        })

    return {
        "group": {
            "id": int(g["id"]),
            "short_name": g["short_name"],
            "offers": int(g["offers"]),
            "stores": int(g["stores"]),
            "brands": int(g["brands"]),
            "group_flag": g["group_flag"],
            "created_at": ts(g["created_at"]),
        },
        "offers": out_offers,
    }


def main() -> None:
    rec = build()
    out = ROOT / "docs" / "example-product.json"
    out.write_text(json.dumps(rec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(out, len(rec["offers"]), "offers")


if __name__ == "__main__":
    main()
