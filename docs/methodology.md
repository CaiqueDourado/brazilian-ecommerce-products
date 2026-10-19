# Methodology

## 1. Origin

From 2019 to 2024 I ran a crawler and NLP project (C# / ASP.NET and SQL Server) that fed a network of product sites: Tudo Sobre Produtos, Preço Atualizado, Busca Produto, Tamanhos, Atendimento ao Consumidor and a set of "Tudo sobre…" category sites. This dataset is the product side of that project's data lake: databases `nlp_data_lake` (offers, spec sheets, codes, groups), `nlp_data_lake_CrawlerNewProductDetailCategoria` (categories) and `nlp_management` (stores, platforms).

The runbook lived as a comment in the main crawler page and listed the order in which the pipeline ran:

| Step | What it did |
|---|---|
| 0 | New category sites: choose categories, add them to sites, set affiliate links |
| 1 | New categories from the B2W site map; new pages from Awin JSON feeds; all products listed by BazaarVoice |
| 2–3 | New store feeds; store names from feed metadata; store slugs |
| 4–5 | Products and prices from B2W category pages and from feeds |
| 6–7 | Product details (EAN, breadcrumb, spec sheet) from B2W pages and from feeds |
| 8 | Breadcrumbs split into category pieces; duplicate categories removed |
| 11–13 | Images downloaded, retried, compressed; thumbnails |
| 14 | EAN rows generated; repeated images and repeated EANs taken out of matching |
| 15 | Fingerprints of products, brands and categories |
| 16–17 | Category and brand normalization |
| 18 | **Grouping** of similar products, then post-processing: split groups with more than 100 images, invalid or truncated EANs, too many rows; periodic regrouping of orphans |
| 13*, 14* | Periodically: reactivate groups that gained a price or image; name groups without a name |
| 19–20 | Parent category and parent brand of each group, by fingerprints, with slugs |
| 21–22 | URL parameters stripped; affiliate links |
| 24 | Spec-sheet keys turned into questions; HTML, feeds and sitemaps generated and published |
| 25–28 | Reviews (BazaarVoice): sentiment, sentence split, store names removed, fingerprints, normalization (published as a separate dataset) |

(*The step numbers repeat in the original; the order above is the one in the comment.)

## 2. Collection

- **B2W (Submarino, Americanas, Shoptime):** crawler of the site map, category pages and product pages. Spec sheets, barcodes and breadcrumbs come mostly from here (the `ficha` table is mostly B2W).
- **Feeds:** affiliate and platform feeds (Awin/Zanox, Lomadee, Google Shopping XML, VTEX, Shopify, NuvemShop, Mercado Shops, Moovin…) gave name, brand, price, availability, image, GTIN and category for the other stores.
- **Store discovery:** stores were found and classified by platform through known feed URLs and HTML signatures; `lojas.platform_id` is the most frequent platform among each store's feeds.
- **First collection date:** `produtos.collected_at` is when an offer was first seen. Prices were collected on few dates (crawling everything often was too expensive), so this dataset has no price history.

## 3. Matching (`group_id`)

Routine `agrupa_insere_grupos_produtos_similares_novo_tabela_temp.sql`. For each offer not yet grouped:

1. **Hop 1:** collect every offer that shares one of these keys with it:
   `EAN longo` (long EAN), `productName` (exact), `productName_fingerprint`, `productName_metaphone`, `productName_ngram`, `productName_tokenizada_fingerprint`, `productUrl`, `EAN curto + Brand` / `+ Brand tokenizada` / `+ Brand fingerprint` / `+ Brand ngram` (short EAN plus 4 forms of the brand), and `productImage_hash_Imagio_ComputeHash` (image signature).
2. **Word check:** drop the long-EAN matches whose names share no word (logged in `temp_agrupamentos_ignorados`).
3. **Hop 2:** collect every offer that shares a key with the hop-1 offers, in the full table.
4. **Group:** if any collected offer already has a group, all join the lowest group id; otherwise a new group is created. Each offer records the key it came through.

Safeguards before matching:

- **EAN blacklist** (`ignored_in_grouping`): "SEM GTIN", 1000000000000 and similar placeholders, letters only, truncated with "+" ("90E+12"), codes in more than 5 products of the same store.
- **Generic brands** ("Importado", "Original", "Não Informado"…) blanked before the brand keys; fingerprint and metaphone keys only for names with enough words.
- **Generic images:** an image signature shared by more than 100 products is not used as a key.

Periodic **regrouping** ran the same routine again over existing groups, pulling in products similar to their members. `group_rule_original` is the rule of the first match; `group_rule` is the rule after regrouping. Regrouping finds more matches but can chain unrelated products, which is why `grupos.group_flag` exists.

Group names: when a group is created or reactivated, `short_name` is the shortest name among offers with an image (preferring offers with a price), `long_name` the longest. A group is `active` when at least one offer has a downloaded image.

## 4. Image signature

Images were downloaded (85.8 million download jobs spread over 12–15 machines, coordinated by a queue table in SQL Server), shrunk to 16×16 grayscale with ImageMagick and hashed with SHA-256. The 32 hash bytes were stored as decimal numbers written one after the other (80–84 characters), the format kept in `image_hash`. Equal signatures mean the same image after shrinking. Because SHA-256 is exact, a difference of 1 in a single pixel gives a different signature, so in practice it links offers that share the same image file (sister stores such as Americanas, Submarino and Shoptime), not copies the store resized or recompressed. A perceptual hash compared by Hamming distance would catch those (see the README). A signature on more than 100 products marks a generic image.

## 5. Normalization at the source (2020)

Done in place in the database, so the original store text is not available for older rows:

- **Categories** (`normaliza_categorias_e_insere_nos_grupos_pai.sql`, July 2020): special characters cleaned, capitalization standardized, accents unified, plural forced when both forms existed, categories with fewer than 3 items removed. `category_normalized` is the "hard" merge by metaphone, fingerprint, n-gram and tokens.
- **Brands** (`normaliza_brands_e_insere_nos_grupos_pai.sql`): the same fingerprint voting; symbol-only brands blanked, long brands cut.

## 6. Export and build (this repository)

1. `scripts/export_sqlserver.py` copies the tables to Parquet with keyset pagination (resumable; broken UTF-16 characters replaced and counted).
2. `scripts/profile_raw.py` profiles the raw export (counts, value classes, sizes).
3. `scripts/build.py` (DuckDB) builds the published tables. Rule: flag, don't delete. Each decision is a constant at the top of the script:
   - prices of 0 and ≥ 99,999 (inactive marker) → empty, with `price_flag`;
   - 13 availability spellings → `disponivel` / `indisponivel`, with `availability_reliable`;
   - mojibake (`Ã©`) and HTML entities repaired with ftfy, with `name_flag`;
   - identifier values split by comma, classified (GTIN check digit, NCM, SKU, scientific notation…), origin taken from the spec sheet;
   - group size, stores and brands counted; oversized and multi-brand groups flagged;
   - category origin (`limpa_2020` / `original`) and noise flags;
   - spec-sheet empty markers (`''`, `Null`) → empty;
   - customer-service rows of brands that asked for removal dropped (the only deletion).
4. `scripts/validate.py` checks counts, keys, rules and that no affiliate id leaked.
5. `scripts/sample.py` makes the GitHub sample.
6. `scripts/make_figures.py` draws the README figures from the sample.
