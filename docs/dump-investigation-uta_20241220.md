# Investigation notes: `uta_20241220` dump

Findings from reading the published dump `uta_20241220.pgd.gz` (latest release at time of writing; Docker Hub `latest` tag, Feb 2025), cross-checked against `uta_20240523b` and `uta_20210129b` (section 8). Written 2026-10-16 as a starting point for cleanup and improvement work. Nothing here has been changed in the repo.

**Method.** The dump is a plain-text `pg_dump` (PostgreSQL 14.9 server, pg_dump 14.15; 344 MB gzipped, ~1.4 GB uncompressed). It was streamed with `gzip -dc` and its `COPY` blocks aggregated. No database was restored. Sections 1-7 describe `uta_20241220` unless stated. Row counts are exact; interpretations are labelled **verified** (read directly from the dump or the repo) or **inferred** (consistent with the evidence, not proven).

## 1. Snapshot

| Item | Value |
|---|---|
| Schema | `uta_20241220`, owner `uta_admin` |
| `meta.schema_version` | `1.2` (matches `models.schema_version`) |
| `meta.updated on` | `2024-12-20T12:29:32` |
| `meta.created on` | `2015-08-21T10:53:50` (never updated) |
| `meta.uta version` | `0.2.0a2.dev11+n52ed6e969cfc` (never updated) |
| `alembic_version` | `77076df4224c` (head of `src/alembic/versions`) |
| Tables (12) | `alembic_version`, `associated_accessions`, `exon`, `exon_aln`, `exon_set`, `gene`, `meta`, `origin`, `seq`, `seq_anno`, `transcript`, `translation_exception` |
| Views (13) | `_cds_exons_flat_v`, `_cds_exons_fp_v`, `_cds_exons_v`, `_discontiguous_tx`, `_seq_anno_most_recent`, `exon_set_exons_fp_v`, `exon_set_exons_v`, `tx_alt_exon_pairs_v`, `tx_def_summary_dv`, `tx_def_summary_v`, `tx_exon_aln_v`, `tx_exon_set_summary_dv`, `tx_similarity_v` |
| Matviews (4) | `exon_set_exons_fp_mv`, `tx_def_summary_mv`, `tx_exon_aln_mv`, `tx_exon_set_summary_mv` |

Row counts: `exon` 9,815,902 · `exon_aln` 6,944,543 · `exon_set` 1,032,364 · `associated_accessions` 405,300 · `seq_anno` 375,810 · `seq` 355,446 · `transcript` 329,090 · `gene` 229,168 · `translation_exception` 299 · `origin` 6 · `meta` 5.

## 2. Frozen Ensembl and BLAT data (live data, dead code)

**Verified.** Only NCBI data is refreshed by the current pipeline. Older sources are carried forward unchanged:

| `transcript` origin | Accession prefix | Rows | `added` range |
|---|---|---|---|
| `NCBI` | `NM_` | 127,347 | 2014-02-11 .. 2024-12-20 |
| `NCBI` | `NR_` | 28,739 | (same) |
| `NCBI` | `NC_` | 37 | (same) |
| `ensembl-79` | `ENST` | 172,965 | 2015-08-25 .. 2017-01-05 |
| `BIC` | `U146`, `U437` | 1 each | 2014-02-11 |

`ENST` transcripts are **53%** of all 329,090 transcripts.

`exon_set` rows by `alt_aln_method` (the `/<hash>` suffix stripped):

| Method | Rows | Reference | `added` range |
|---|---|---|---|
| `transcript` | 172,965 `ENST`; 127,550 `NM_`; 28,792 `NR_`; 37 `NC_`; 2 `U`* | self | 2014-02-11 .. 2024-12-20 |
| `splign` | 425,040 `NC`; 35,383 `AC`; 15,529 `NT`; 14,624 `NW`; 5,995 `NG` | NCBI | 2014-02-11 .. 2024-12-20 |
| `genebuild` | 164,601 `NC` | Ensembl | 2015-08-26 .. 2017-01-05 |
| `blat` | 41,829 `NC` | UCSC | 2014-02-11 .. 2015-08-26 |
| `splign-manual` | 14 `NC`, 1 `NW` | NCBI | 2020-08-17 .. 2020-10-02 |
| `BLAST` | 2 `NC` | | 2014-02-13 |

Other `origin` rows: `uta0` (41 `NM` `seq_anno` rows only), `ensembl-81` (registered, no transcripts), `NCBI RefSeq` (id 3, no transcripts; the origin `loading.load_ncbi_seqgene` looks up). Origin ids 1, 3, 6, 8, 10, 11 are present, so ids 2, 4, 5, 7, 9 were deleted at some point.

**Frozen (verified across three releases).** The `ensembl-79` / `ENST` count (172,965), the `genebuild` count (164,601), the `blat` count (41,829) and the archived-`blat` count (583) are identical in `uta_20210129b`, `uta_20240523b` and `uta_20241220`.

**Why it persists (verified).** `sbin/uta-load` builds each release by `pg_dump`ing the previous schema and renaming it (`etc/scripts/create-new-schema.sh`), so every release re-ships every earlier row.

**Open questions.**
- Does anyone still depend on `ENST` / `genebuild` / `blat` data (hgvs users mapping Ensembl accessions)? Check hgvs issues and ask downstream users before proposing removal.
- Which Ensembl release and assembly do the 164,601 `genebuild` alignments use? The `ensembl-79` origin name suggests release 79; that was not checked against the data.
- Should the origin rows `ensembl-81`, `NCBI RefSeq` and `uta0` be removed or documented?

## 3. Manual release steps that are not in `uta-load`

**Verified.**
- All four matviews are populated (the dump ends with `REFRESH MATERIALIZED VIEW` for each, in the order used by `loading.refresh_matviews`). `sbin/uta-load` never calls `refresh-matviews`.
- Every table, view and matview (29 objects) has `GRANT SELECT ... TO PUBLIC`, and the schema has `GRANT USAGE` to `PUBLIC` and `anonymous`. This includes `translation_exception`, created by an alembic migration, so grants were applied after the migration. `sbin/uta-load` never calls `grant-permissions`.
- All 36 owned objects are owned by `uta_admin`.

**Inferred.** The release procedure includes manual (or undocumented) `uta refresh-matviews` and `uta grant-permissions` runs, and probably `analyze`. Nothing in this repo records when or by whom.

**Open questions.**
- Run the three commands inside `uta-load`, or document them in the README procedure.
- `sql/refresh-matviews.sql` lists `tx_aln_cigar_mv`, `tx_aln_summary_mv` and `tx_similarity_mv`, none of which exist in this dump (`tx_similarity_v` is a plain view). The file is stale.
- Are the matviews current relative to `exon_aln`? Populated is verified; freshness is not.

## 4. Data-quality issues carried since 2020-2021

**Verified.**
- `associated_accessions` row `3147152` is the literal CSV header `tx_ac / pro_ac / origin` (`added` 2021-02-03 19:45:47). The identical row (same id, same timestamp) is in `uta_20210129b`, `uta_20240523b` and `uta_20241220`. Counting `associated_accessions` by origin gives `NCBI` 405,299 and `origin` 1. The timestamp falls after the last NCBI data load of that build (2021-01-31) and before the `uta_20210129.pgd.gz` upload (2021-02-04), so it was added during the final steps of the 20210129 build (**inferred**).
- `seq_anno` rows `482197` and `482210` have accessions `NCBI:NM_001025190.1` and `NCBI:NM_033060.3` with descriptions `refseq:NM_...` (`added` 2020-08-17 and 2020-10-02). Same rows, same ids, in all three dumps. Those dates match the `splign-manual` loads (**inferred** cause).
- 7 transcript accessions contain `/` (CDS coordinates changed and the old row was renamed `NM_x.y/<start>..<end>` by `load_txinfo`).
- Archived exon sets (alternative-method rows with a `/<sha1[:8]>` suffix): `transcript` 256, `blat` 583, `splign` 168.
- 35,614 `gene` rows have a NULL `type`; 128,261 have type `biological-region`.

**Open questions.**
- Why did a header row load? Both known loaders should skip it: `load_assoc_ac` uses `csv.DictReader`, and the `loading/Makefile` rule uses `copy ... csv header`. The cause is unknown; a manual `\copy` without `HEADER` around 2021-02-03 is one guess (**unverified**).
- Should loaders reject rows like these, and should the build run a validation step before dumping?
- Do the `NCBI:`-prefixed accessions break any consumer lookups?

## 5. Size breakdown

| Table | MB in dump text |
|---|---|
| `exon_aln` | 434.6 |
| `seq` | 409.9 |
| `exon` | 353.3 |
| `exon_set` | 75.2 |
| `seq_anno` | 37.6 |
| `gene` | 34.8 |
| `transcript` | 31.1 |
| `associated_accessions` | 29.3 |

**Verified.** In `seq`, 89,199 rows hold inline sequence (395.6 MB, ~28% of the whole dump text) and 266,247 are NULL (sequences over 2 Mb are never stored inline, per `load_seqinfo`). hgvs's `get_seq` goes through `SeqFetcher` (SeqRepo or NCBI), not this column; its `tx_seq` query is defined but unused.

**Open questions.**
- Can `seq.seq` be emptied without breaking consumers? Check hgvs and other known clients for reads of `seq.seq`. `cds_md5` (on `transcript`) and `seq_anno` are the parts that matter.
- Compressed savings were not measured; sequence text compresses differently from numeric rows.
- Is `exon_aln.tx_aseq` / `alt_aseq` (nullable aligned sequences) populated? Not measured.

## 6. Lineage

`created on` and `uta version` show the 2015 origin schema, not the current build. The only meta values updated per release are `schema_version` and `updated on` (`loading.update_meta_data`). If the build identity matters, consider recording the repo commit and data sources in `meta`.

## 7. Suggested next investigations (priority order)

1. Confirm hgvs / downstream dependence on `ENST`, `genebuild`, `blat` rows before any data removal.
2. ~~Run the same analysis on `uta_20210129b` and `uta_20240523b`~~ Done; see section 8. Still open: compare these counts with the `sbin/uta-diff` output from the 2024 builds, if the build logs survive (`uta_20240523.pgd.gz.log` / `.loadlog` on dl.biocommons.org).
3. Restore the dump into Postgres and verify matview freshness and the `tx_exon_aln_v` / `tx_def_summary_v` views against hgvs queries.
4. Ask previous maintainers what the manual post-load steps are, how SeqRepo snapshots reach `dl.biocommons.org`, and who runs the Docker Hub build (`misc/docker/`).
5. Add a pre-dump validation step (header rows, accession format, orphan rows).

## 8. Release-to-release comparison

Same analyzer run on three dumps:

| Table | `20210129b` | `20240523b` | `20241220` | Δ 2021→2024-05 | Δ 2024-05→12 |
|---|---|---|---|---|---|
| `exon` | 8,310,936 | 9,716,651 | 9,815,902 | +1,405,715 | +99,251 |
| `exon_aln` | 5,604,190 | 6,847,303 | 6,944,543 | +1,243,113 | +97,240 |
| `exon_set` | 894,082 | 1,022,751 | 1,032,364 | +128,669 | +9,613 |
| `associated_accessions` | 265,035 | 405,253 | 405,300 | +140,218 | +47 |
| `seq_anno` | 360,063 | 375,097 | 375,810 | +15,034 | +713 |
| `seq` | 340,384 | 354,745 | 355,446 | +14,361 | +701 |
| `transcript` | 314,227 | 328,839 | 329,090 | +14,612 | +251 |
| `gene` | 45,857 | 229,123 | 229,168 | +183,266 | +45 |
| `translation_exception` | (table absent) | 241 | 299 | +241 | +58 |

**Verified.**
- **`20210129b` is a re-dump of the 2021 data, not a new build.** The newest NCBI row is 2021-01-31, `meta` has no `updated on`, `schema_version` is `1.1`, there is no `alembic_version` table, and it has only 3 matviews (no `tx_exon_aln_mv`) and no `translation_exception` or `gene.type`. Its file size matches the original `uta_20210129` upload (280.9 MiB both), which fits a re-dump of the same data (**inferred**; the original file isn't available to compare).
- **No data was loaded between 2021-01 and 2024-05.** In `20240523b`, every `transcript` row (14,612) and every `exon_set` row (128,669) with an `added` month after 2021-01 has `added` in 2024-05; those counts equal the Δ column exactly. The 2024-05 build was large (+14.6k transcripts, +1.4M exons, +183k genes). The 2024-05 → 2024-12 build was small and NCBI-only.
- **`20240523b` and `20241220` have identical object lists** (12 tables, 13 views, 4 matviews), the same alembic head `77076df4224c`, and the same 37 `NC_` mito transcripts. Between them only NCBI-sourced counts change: transcripts `NM_` +50 and `NR_` +201, and `splign` alignments to `NC_` sequences +9,035. A diff of two consecutive releases is small and reviewable.
- The `gene` table grew 5x (45,857 → 229,123) in the 2024-05 build. 128,261 of the 229,168 current rows have type `biological-region`, and 35,614 have a NULL type, consistent with legacy rows that predate the `type` column (**inferred**; the 2021 dump has no `type` column to check).
- Docker Hub has 16 tags in all (`uta_20150827` through `uta_20190928`, then `uta_20210129b`, `uta_20240523b`, `uta_20241220`, `latest`). It omits releases that dl.biocommons.org lists (`20201027`, `20210119`, `20210129`), so a missing tag does not prove a missing release.

**Open questions.**
- Why did the data gap last 3+ years? The dl.biocommons.org listing shared earlier (which starts at 2020-10) shows no 2022 or 2023 releases, only the 2023-09 upload of `uta_20210129b`; whether an unpublished intermediate build exists is unknown.
- Why was `uta_20210129b` re-dumped in 2023-09 (PostgreSQL version? checksum change from sha1 to sha512?).
- What exactly changed in the pipeline in 2024 (commit history shows `IPVC-*` work, gene_id migration, `translation_exception`, mito, cdna_match coalescing)?

## Reproducing

```sh
F=~/Downloads/uta_20241220.pgd.gz      # download in a browser; dl.biocommons.org blocks scripts
gzip -t "$F"

# object inventory
gzip -dc "$F" | grep -E '^CREATE (MATERIALIZED VIEW|VIEW|TABLE) '

# matview refreshes and grants
gzip -dc "$F" | grep -E '^REFRESH MATERIALIZED VIEW|^GRANT'

# header row in associated_accessions
gzip -dc "$F" | awk '/^COPY uta_20241220.associated_accessions /{on=1;next} /^\\\.$/{on=0} on && /\ttx_ac\t/'

# per-table size in dump text
gzip -dc "$F" | awk '/^COPY /{t=$2; on=1; next} /^\\\.$/{on=0} on{b[t]+=length($0)+1} END{for(k in b) printf "%10.1f MB  %s\n", b[k]/1e6, k}' | sort -rn
```

The per-origin, per-method and per-prefix tallies came from a small Python script that maps each `COPY` block's columns from its own header and aggregates `meta`, `origin`, `transcript`, `exon_set`, `seq_anno`, `associated_accessions` and `gene` (about 11 s on this dump). It currently lives only in the author's session scratchpad.
