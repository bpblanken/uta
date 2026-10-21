# Release data and consumers

What a published UTA release actually contains, and how hgvs and SeqRepo consume it. Moved out of `AGENTS.md` to keep that file short; measurements and open questions are in `dump-investigation-uta_20241220.md`.

## What a release contains

Measured from `uta_20210129b`, `uta_20240523b` and `uta_20241220` (details in `dump-investigation-uta_20241220.md`):

- Only NCBI data is refreshed. 172,965 `ENST` transcripts (origin `ensembl-79`, 53% of all transcripts), their 164,601 `genebuild` alignments and 41,829 `blat` alignments were loaded 2014-2017 and are re-shipped unchanged by every release, because each release starts from the previous dump. No step in the current pipeline regenerates them.
- The Ensembl rows are **GRCh37**, despite the `ensembl-79` label (Ensembl 79 itself is GRCh38.p2). `sbin/ensembl-fetch` names the origin after the installed Perl API version (`"ensembl-" . software_version()`) and defaults to port 3337, the GRCh37 server (`3337 is GRCh37; 5306 is GRCh38`). Checked in the dump: BRCA1 `ENST00000357654` has a `genebuild` alignment only on `NC_000017.10`, starting at the same coordinate as RefSeq's `NC_000017.10` alignment (41,196,311), not the `NC_000017.11` one (43,044,294). Which GRCh37 database release was queried is unknown.
- The Ensembl rows are not accidental carry-over. They use Ensembl gene ids (`ENSG…`, 35,523 distinct; the 35,523 NULL-type rows in `gene`), and the 2024 `gene_id` migration reloaded them from `misc/gene-update/gene_update.tsv.gz` and `transcript_update.tsv.gz` to keep them valid. `ENST` accessions are unversioned and have no `associated_accessions` rows.
- The extractors are `sbin/ensembl-fetch` (Perl) and `misc/EnsemblUTA/` (a 2019 Python rewrite for releases 82/90/94; no such origin exists in the dumps, so its output apparently never loaded). The only BLAT code is `archive/ucsc-fetch`. Treat removing those rows as a data decision that needs downstream sign-off, not a code cleanup. I have not confirmed that hgvs or any other client reads `ENST` rows through UTA, so ask before assuming either way.
- Releases: `20210129` → `20240523b` → `20241220`. No data was loaded between 2021-01 and 2024-05. `uta_20210129b` is a 2023 re-dump of the 2021 data.
- Known bad rows carried forward since 2021: `associated_accessions` id 3147152 is a literal header row (`tx_ac`, `pro_ac`, `origin`), and two `seq_anno` rows have `NCBI:`-prefixed accessions (`NCBI:NM_001025190.1`, `NCBI:NM_033060.3`). Run a sanity check for these before a release.
- `meta.created on` (2015-08-21) and `meta.uta version` (`0.2.0a2.dev11+n52ed6e969cfc`) are copied forward from the original schema and don't identify the build. Only `schema_version` and `updated on` change.
- The `gene` table holds NCBI gene records of all types (about 193k numeric-id rows, 128k of them `biological-region`) plus the 35,523 Ensembl `ENSG` genes, not just genes with transcripts.
- `seq.seq` stores sequence inline for 89,199 rows (about 28% of the dump text). hgvs does not read it.

## Consumers

- The interface is the SQL schema. hgvs reads UTA with raw SQL via psycopg 3 (e.g. `tx_exon_aln_v`, marked `USED BY: hgvs` in `sql/views.sql`), declares `required_version = "1.1"` and reads the schema name from the URL path (`.../uta/uta_20241220`). It does not import the `uta` Python package (PyPI `uta` 0.1.8 is a stale release pointing at Bitbucket). Renaming a column or view used by hgvs is a breaking change even though no Python API moves.
- hgvs gets sequence separately: `HGVS_SEQREPO_DIR` (local SeqRepo), else `HGVS_SEQREPO_URL` (REST), else NCBI via `bioutils`. SeqRepo is a directory of files plus SQLite, with no server. UTA only needs Postgres, and hgvs defaults to the public `uta.biocommons.org`.
- This repo's SeqRepo steps change only the local `seqrepo-volume`. Publishing a new public SeqRepo is done in biocommons.seqrepo (`misc/update_seqrepo.sh`: load, `seqrepo snapshot`, rsync to `dl.biocommons.org`) on the hosting machine, and nothing here records who runs it. Its load list includes RefSeqGene (`NG_`), which `etc/ncbi-files.txt` does not download.
- `dl.biocommons.org/uta/` serves each release as `<v>.pgd.gz`, `<v>-schema.pgd.gz` (schema only), a checksum (`.sha1`, later `.sha512`) and logs. It sits behind a human-verification page, so scripts can't download dumps; use a browser.
