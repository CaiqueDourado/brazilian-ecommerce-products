# Data quality report

What was found while profiling the raw export and reading the code that produced it, and what was done about it. Numbers are from the full build (`build_stats.json`).

## Fixed or flagged in the build

| # | Problem | Rows | Treatment |
|---|---|---|---|
| 1 | Price 0 | 28,057,636 | `price` empty, `price_flag = zero`, value in `price_raw` |
| 2 | Price ≥ 99,999 (the crawler wrote 99,999.99 for inactive products) | 1,495,377 | `price` empty, `price_flag = inativo_99999` |
| 3 | Availability in 13 spellings (`in stock`, `http://schema.org/InStock`, `disponível`…) | all | `availability` = `disponivel` / `indisponivel` / empty; original in `availability_raw` |
| 4 | Mojibake (`BistrÃ´`) and HTML entities in product names | 519,564 | Repaired; `name_flag = reparado`, original in `name_raw` |
| 5 | Replacement character "�" already stored in product names | 978 | Cannot be recovered; `name_flag = caractere_perdido` |
| 6 | Store names: HTML entities and mojibake | 609 | Repaired; `name_flag = reparado` |
| 7 | Store names with "�" stored at collection (feed read with the wrong encoding) | 151 | `name_flag = caractere_perdido` |
| 8 | Old slugs: `²` deleted the digit `2` (accent-insensitive collation), and collisions incremented a trailing number (`iphone-11` → `iphone-12`) | stores | New `slug`; old one in `slug_raw` |
| 9 | Several codes in one value, separated by commas | +9,394 rows | One row per code, `code_index` |
| 10 | Identifier field mixing GTIN, SKU, NCM, text and Excel scientific notation | 32.1M | `code_type`; 79% are valid GTINs |
| 11 | Spec-sheet empty markers (`''`, `Null`, `-`) | — | `value` empty, original in `value_raw` |
| 12 | Groups chained by regrouping | 3,107 > 1,000 offers; 11,743 > 10 brands | `group_flag` |
| 13 | Groups with no offer left | 14,999 | `group_flag = sem_ofertas` |
| 14 | Same `last_change` (2022-04-04 00:03:14.763) written in bulk | ~437k groups | `last_change_is_bulk_date` |
| 15 | Category pieces that are SEO tags, internal codes or noise | 5.9M | `category_flag` |
| 16 | Categories cleaned in 2020 next to raw ones from later crawls | 189.2M / 30.8M | `category_origin` |
| 17 | Customer-service contacts of brands that asked for removal | 224 | Removed (the only deletion) |

## Known limits (documented, not fixable)

- **Original text lost at the source.** In 2020, category, brand, product name and spec-sheet keys were normalized in place. In the category column:
  - plural was forced when both forms existed, so "Home" became "Homes";
  - accents and capitalization were unified;
  - every category containing a digit was deleted (two DELETE statements with swapped comments both ran), e.g. "Galaxy J5".
- **Third feed category never stored:** the feed loader wrote `categoria1` into `categoria3`.
- **`level` is not depth:** it is the position after splitting the breadcrumb text on `>`, `|`, ` - `, `,` and `/`.
- **Availability:** one B2W crawl path stored "out of stock" as "in stock". `availability_reliable` is false for Submarino, Americanas and Shoptime. Other stores were not checked, so read the field with care everywhere.
- **Prices:**
  - the stored price is the sale price when there was one;
  - a script copied Submarino prices to part of the Americanas and Shoptime offers;
  - prices were collected on few dates, so there is no price history.
- **Offers without a group (7.4M):** in part because loading downloaded images back cleared `productGroupId`.
- **`group_rule_original` empty:** some ungrouping scripts erased it.
- **Fingerprint bug:** the fingerprint key used by two matching rules dropped every other token, so some fingerprint matches are weaker than the name suggests. [DedupKit](https://github.com/CaiqueDourado/DedupKit) reproduces it (`legacy_fingerprint`) and measures its effect.
- **No attribute check:** offers that share a barcode or a photo were merged even when their names state different sizes, voltages or colours. Re-checking the sample with [DedupKit](https://github.com/CaiqueDourado/DedupKit) would split 795 of its 4,030 groups.
- **Group names are not refreshed** when offers leave a group, and `active` only checks for an image, not a price.
- **Image size:** `image_width` / `image_height` describe the optimized image and may belong to another image, because of a race condition between download threads.
- **EAN origin key:** the crawler never filled the key column of the identifier table. `source_key` recovers it from the spec sheet when the same code is there.
- **Only the first EAN** of a product was used for matching. The capture regex also handled only products with a single EAN.
- **Ids:** offer ids jump by +39,517,486 at the December 2019 migration.
- **Store names** came from page metadata and are noisy. The `lojas` table also lists stores that were registered but never yielded offers (7,179 of 17,899 have offers).
- **Inactive stores** are kept. Some were deactivated at their own request; `lojas.active` marks them.
