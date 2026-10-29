# 5. Keep model data in a bind-mounted NVMe directory

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

Strata's upstream compose file keeps `/data` in a named volume. Named volumes
live under docker's data root, normally on the root filesystem. Q2_0 needs
about 105 GB there: 63 GB of GGUF, a 38 GB prepared pack, and the MTP draft.

Strata leaves the model's second shard, a 29 GB lookup table, on disk and
reads rows from it while generating. Disk speed therefore affects decode, not
only load time. A SATA SSD reads roughly 0.5 GB/s sequentially and is far
weaker at small random reads than a Gen4 NVMe drive at roughly 7 GB/s.

## Decision

Mount `STRATA_DATA_DIR`, an absolute host path, at `/data`. Document that it
belongs on NVMe. Compose refuses to render without it, and `make up` refuses
to start when the directory does not exist.

## Consequences

- The root disk does not fill up, and the data survives `docker volume prune`.
- Moving the data is a plain `mv` plus a `.env` edit.
- How much a SATA SSD actually slows decode has not been measured here
  (unverified); the RAM row cache absorbs part of it after warm-up.
- `make test` fails if `/data` stops being a bind mount in any GPU override.
