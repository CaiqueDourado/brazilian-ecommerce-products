# Changelog

## Unreleased

- Kaggle description and notebook link the libraries rewritten from this catalog (DedupKit, SimilarImageFinder); data dictionary links DedupKit in `group_rule`.
- Matching: the original SQL routine published read-only in `legacy/`, with its known issues; links to DedupKit, the library rewritten from it; data quality notes the missing attribute check.
- Image signature: links to SimilarImageFinder, the library rewritten from it; methodology describes the original Magick.NET steps and the local × AWS mismatch; figure uses pHash.
- Figure dependencies moved to `requirements-figures.txt`.
- Link to the Kaggle notebook; Kaggle metadata with file and column descriptions (`kaggle/dataset-metadata.json`).

## 1.0.0 (2026-10-18)

- First release: 114,640,012 offers from 7,179 stores (2019–2024), 18,328,454 product groups, 31.9M spec-sheet rows, 32.1M identifier rows, 220M category rows, 17,899 stores and 13 platforms.
- Build with "flag, don't delete": price, availability, name, code, group and category flags; original values in `*_raw` columns.
- GitHub sample of 4,030 whole groups; full data on Kaggle.
- README with real examples and figures (`scripts/make_figures.py`); matching described as it ran (two hops over 12 keys); image-signature limits documented.
