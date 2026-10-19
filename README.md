# Brazilian e-commerce product catalog

[![validate](https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/actions/workflows/validate.yml/badge.svg)](https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/actions/workflows/validate.yml)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](LICENSE-DATA.md)
[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Kaggle](https://img.shields.io/badge/Kaggle-full%20dataset-20BEFF.svg)](https://www.kaggle.com/datasets/caiquedourado/catalogo-produtos-ecommerce-brasil)

[Leia em português](README.pt-BR.md)

**114.6 million offers from 7,179 Brazilian online stores, collected from 2019 to 2024**, with spec sheets, barcodes, categories and **18.3 million product groups**: the same item sold by different stores, linked by an 11-rule matching engine.

This repository holds a coherent sample (whole groups with all their offers, spec rows, codes and categories) and the scripts that build the data. **The full dataset (9.5 GB of Parquet) is on [Kaggle](https://www.kaggle.com/datasets/caiquedourado/catalogo-produtos-ecommerce-brasil).**

| Table | Rows | What it is |
|---|---|---|
| `produtos` | 114,640,012 | One offer: a product in a store, with name, brand, price, availability, group and image signature |
| `grupos` | 18,328,454 | Product groups, with offer, store and brand counts |
| `ficha` | 31,904,957 | Spec sheet, one row per key/value (4,370 keys) |
| `eans` | 32,119,395 | Product identifiers, classified (79% valid GTIN check digits) |
| `categorias` | 220,060,122 | Store category paths, with normalization |
| `lojas` | 17,899 | Stores, with their e-commerce platform |
| `caracteristicas` | 3,102 | Spec keys with the question-style title used on the sites |
| `plataformas` | 13 | VTEX, Shopify, NuvemShop, Magento… |

Largest stores: Magazine Luiza (19.7M offers), Americanas (14.3M), Shoptime (11.2M), Submarino (10.7M), Extra (10.3M), Casas Bahia (9.9M), Amazon (7.3M), Dafiti (5.9M), Pontofrio (4.4M) and Kanui (1.8M). The top 10 hold 83% of the offers.

## Where it comes from

The catalog powered a network of sites I built from 2019 to 2024: price comparison, spec sheets, size guides, brand customer-service pages and "everything about" each product. Among them:

- [Tudo Sobre Produtos](https://web.archive.org/web/20251021032358/https://tudosobreprodutos.com.br/tudo-sobre-bebedouro-cadence-pure-vita-elegant-0v)
- [Preço Atualizado](https://web.archive.org/web/2020/https://precoatualizado.com.br/)
- [Tamanhos](https://web.archive.org/web/20241107071917/https://tamanhos.com.br/tamanhos-medidas-dimensoes-voltimetro-digital-com-remote-0-a-0v-bateria-som-carro-azul-asx)
- [Atendimento ao Consumidor](https://web.archive.org/web/20201101002617/https://atendimentoaoconsumidor.com.br/assistencia-tecnica-garantia-energetico-monster-energy-47ml)
- [Busca Produto](https://web.archive.org/web/2020/https://buscaproduto.com.br/)

Every product page on those sites was built from one group in this data.

Collection used three sources:

- my own crawlers of store pages (spec sheets, barcodes, breadcrumbs);
- product feeds (Google Shopping, Awin, VTEX, Shopify, NuvemShop…);
- store discovery by e-commerce platform.

Everything went into a SQL Server data lake and was exported here with the scripts in `scripts/`.

## Matching: the same item in different stores

The core of the data is `group_id`. Each new offer was compared with existing ones by **11 keys**, in this order:

1. long EAN, with a blacklist of generic codes and a word-overlap check, so a guitar and a car part that a store registered under the same EAN are not merged;
2. exact name;
3. name fingerprint;
4. metaphone;
5. n-grams;
6. token fingerprint;
7. URL;
8. short EAN + brand (4 variants);
9. **image signature**.

A **two-hop regrouping** then pulled in products similar to the group's members.

- `group_rule_original` keeps the rule of the first, conservative match.
- `group_rule` keeps the rule after regrouping, which merges more and sometimes chains too far.

The 3,107 groups with more than 1,000 offers and the 11,743 with more than 10 brands are flagged in `group_flag`. Use `group_rule_original` when precision matters.

### The image signature

Every product photo was downloaded, shrunk to 16×16 grayscale and hashed with SHA-256 (`image_hash`). The technique is simple and cheap, and it worked well in two ways:

- **Finding the same photo at different sizes:** resellers usually use the manufacturer's photo, each at its own size and compression. Shrunk to 16×16 grayscale, the photo becomes the same signature. This linked products that had no EAN and different names.
- **Finding generic images without looking at them:** when one signature appeared on more than 100 products, it was almost always a "no photo" placeholder or a store logo. Those became `image_is_generic` and stopped linking products.

## What this data can answer

- Which products appear in most stores, and how much the price varies between them at collection time.
- Which e-commerce platforms Brazilian stores used, and how big their catalogs were.
- How stores describe the same product: spec-sheet keys, attribute synonyms, categories.
- The real quality of barcodes in Brazilian retail: valid GTIN, wrong check digit, SKU instead of EAN, codes broken by Excel.
- Training and test material for product matching (entity resolution) in Portuguese.

## Getting started

```python
import duckdb
con = duckdb.connect()
con.sql("""
    SELECT g.short_name, p.store_id, p.price
    FROM 'produtos/*.parquet' p JOIN 'grupos.parquet' g ON g.id = p.group_id
    WHERE g.stores >= 5 AND p.price IS NOT NULL
    LIMIT 20
""")
```

The sample in this repository is in `sample/` (CSV, ~18 MB), with the same file and column names as the full data.

## Documentation

- [Data dictionary](docs/data-dictionary.md): every column and its values
- [Methodology](docs/methodology.md): collection, matching, normalization and build
- [Data quality](docs/data-quality.md): what was fixed, what was only flagged and what was lost at the source

Rule of this dataset: **flag, don't delete**. Every corrected value keeps the original in a `*_raw` column and the reason in a `*_flag` column.

## What I would do differently

- **Keep raw data before normalizing.** Names, brands and categories were normalized in place in 2020, and the stores' original text was lost. A plural rule turned "Home" into "Homes".
- **Test text functions with Portuguese cases.** The fingerprint I used dropped every other word. A category routine deleted every category containing a digit, such as "Galaxy J5".
- **Keep ingestion apart from enrichment.** Loading downloaded images back cleared the product's group, which explains part of the 7.4M offers without a group.

## License and use

- **Data:** CC BY 4.0 ([LICENSE-DATA.md](LICENSE-DATA.md)).
- **Code:** MIT.
- **Store content:** names, brands and spec sheets are factual information collected from stores and public affiliate feeds. Images are not distributed, only their signatures.
- **Removal requests:** customer-service contacts of brands that asked for removal were taken out (224 rows).

## Citation

See [CITATION.cff](CITATION.cff).
