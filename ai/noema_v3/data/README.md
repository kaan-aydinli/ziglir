# NOEMA v3 Data Contract (Phase 0)

This directory defines the **Phase 0** data/split contracts for NOEMA v3. It does not contain training data.

## Files

- `manifest_schema.json` — per-source manifest entry schema.
- `split_policy.json` — leakage-free split rules and integrity checks.

## SoA Shard Contract (Phase 5 implementation target, Phase 0 contract)

Spec §6.1 requires zero-parse mmap-friendly SoA shards:

- `stream.bin` — raw UTF-8 bytes (uint8).
- `prov.bin` — provenance tag per byte/event (uint8/enum).
- `reset.bit` — document/segment reset boundaries (bitset).
- `weight.bin` — document-length/loss weights (float32 or fixed-point; exact format locked before Phase 2).
- `docs.idx` — document offsets, lengths, manifest ids, checksums.

**Integrity invariant:** every ingestion pass must satisfy `read == accepted + rejected` and manifest checksum verification. Fail-closed on mismatch.

## Provenance isolation

Data ingestion must preserve provenance tags. Untrusted document text can be stored as `UNTRUSTED_SOURCE` but must never be promoted to `SYSTEM_POLICY` or `VERIFIED_KHG` without deterministic verification.
