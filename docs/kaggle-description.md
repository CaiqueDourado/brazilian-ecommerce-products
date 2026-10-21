**114.6 million offers from 7,179 Brazilian online stores (2019–2024)**, with spec sheets, barcodes, categories and **18.3 million product groups**: the same item sold by different stores, linked by a two-hop matching engine over 11 text and code keys (EAN, exact name, name fingerprints, metaphone, n-grams, URL, short EAN + brand) plus an image signature.

The catalog powered a network of Brazilian product sites (price comparison, spec sheets, size guides, brand customer service). Code, documentation and a small sample: https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil

![One product, many stores](https://raw.githubusercontent.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/main/docs/img/one-product-many-stores.png)

## How offers were grouped

![Matching flow](https://raw.githubusercontent.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/main/docs/img/matching.png)

The matching logic is now a tested library, **DedupKit** (Python and .NET): https://github.com/CaiqueDourado/DedupKit. It also refuses pairs whose names state different sizes, voltages or colours; on the GitHub sample, that check alone would split 795 of the 4,030 groups. The original SQL routine is published read-only in the repository's `legacy/` folder.

![Image signature](https://raw.githubusercontent.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/main/docs/img/image-signature.png)

The image signature links offers that share the same image file and finds "no photo" placeholders. Because SHA-256 is exact, it does not match a photo the store resized or recompressed:

![Exact vs perceptual hash](https://raw.githubusercontent.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/main/docs/img/exact-vs-perceptual-hash.png)

The signature is now a library with perceptual hashes, **SimilarImageFinder** (Python and .NET): https://github.com/CaiqueDourado/SimilarImageFinder. On 442 real photos from this catalog, the exact signature found 20 of 348 copies; a 256-bit pHash found all of them and matched no different picture.

## Barcodes in the real world

![Barcode quality](https://raw.githubusercontent.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/main/docs/img/barcode-quality.png)

## Files

| File | Rows | Content |
|---|---|---|
| `produtos/*.parquet` | 114,640,012 | Offers: name, brand, price, availability, store, group, image signature |
| `grupos.parquet` | 18,328,454 | Product groups with offer, store and brand counts |
| `ficha/*.parquet` | 31,904,957 | Spec sheets, one row per key/value (4,370 keys) |
| `eans/*.parquet` | 32,119,395 | Product identifiers, classified (79% valid GTIN) |
| `categorias/*.parquet` | 220,060,122 | Category paths (breadcrumbs), with normalization |
| `lojas.parquet` | 17,899 | Stores and their e-commerce platform |
| `caracteristicas.parquet` | 3,102 | Spec keys with a question-style title |
| `plataformas.parquet` | 13 | E-commerce platforms |

Column names are in English; flag values are in Portuguese and explained in the data dictionary.

## Rule: flag, don't delete

Every corrected value keeps the original in a `*_raw` column and the reason in a `*_flag` column: zero and "inactive" prices, 13 availability spellings, mojibake in names, barcodes broken by Excel, groups chained by regrouping. For precision, use `group_rule_original` and filter out `group_flag <> 'ok'`.

## Good for

- Product matching / entity resolution in Portuguese
- Price dispersion of the same product across stores (at collection time; there is no price history)
- Barcode quality in Brazilian retail
- Spec-sheet attribute extraction and category taxonomy work
- Which e-commerce platforms Brazilian stores used

## Quick start

```python
import duckdb
duckdb.sql("""
    SELECT g.short_name, COUNT(*) AS offers, MIN(p.price) AS min_price, MAX(p.price) AS max_price
    FROM '/kaggle/input/catalogo-produtos-ecommerce-brasil/produtos/*.parquet' p
    JOIN '/kaggle/input/catalogo-produtos-ecommerce-brasil/grupos.parquet' g ON g.id = p.group_id
    WHERE g.group_flag = 'ok' AND g.stores >= 5 AND p.price IS NOT NULL
    GROUP BY 1 ORDER BY offers DESC LIMIT 20
""")
```

## Libraries rewritten from this catalog

- DedupKit: product matching for Brazilian Portuguese data (fingerprints, phonetic key, barcode rules, attribute check, audit trail). https://github.com/CaiqueDourado/DedupKit
- SimilarImageFinder: perceptual image hashing (aHash, dHash, pHash) with the same results in Python and .NET. https://github.com/CaiqueDourado/SimilarImageFinder

## Related datasets

- Google product taxonomy in Portuguese, used to classify these products: https://www.kaggle.com/datasets/caiquedourado/taxonomia-google-produtos-ptbr
- Brazilian municipalities and states: https://www.kaggle.com/datasets/caiquedourado/municipios-e-estados-do-brasil
- Countries of the world in Portuguese: https://www.kaggle.com/datasets/caiquedourado/paises-do-mundo-ptbr

## Documentation

- Data dictionary (EN / PT): https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/blob/main/docs/data-dictionary.md
- Methodology: https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/blob/main/docs/methodology.md
- Data quality: https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/blob/main/docs/data-quality.md

## License

CC BY 4.0. Product names, brands and spec sheets are factual information from stores and public affiliate feeds. Images are not distributed, only their signatures. Customer-service contacts of brands that asked for removal were taken out.
