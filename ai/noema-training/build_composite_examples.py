#!/usr/bin/env python3
"""Build auditable JSONL multi-objective examples from the atomic variant catalog."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PAIRS = [
    ("tr-var-sft-0001", "tr-var-pref-0001"),       # supervised + contrastive preference
    ("tr-var-tool-0001", "tr-var-structured-0001"),# tool + structured computation
    ("tr-var-abstain-0001", "tr-var-retrieval-0001"),# causal reasoning + retrieval evidence
    ("tr-var-multimodal-0001", "tr-var-sft-0001"), # media grounding + natural-language answer
    ("tr-var-sequence-0001", "tr-var-eval-0001"), # forecasting + calibration
    ("tr-var-code-0001", "tr-var-pref-0001"),      # executable code + preference comparison
    ("tr-var-safety-0001", "tr-var-ask-0001"),     # safety gate + clarification
    ("tr-var-retrieval-0001", "tr-var-sft-0001"),  # citations + supervised response
    ("tr-var-tool-0001", "tr-var-code-0001"),       # tool use + tested code repair
    ("tr-var-structured-0001", "tr-var-sequence-0001"), # table transform + temporal reasoning
    ("tr-var-safety-0001", "tr-var-tool-0001"),      # authorization gate + tool execution
    ("tr-var-multimodal-0001", "tr-var-abstain-0001"), # media evidence + uncertainty
]


def main() -> None:
    atomic_path = ROOT / "turkish_variants.v1.jsonl"
    atomic = {r["id"]: r for r in (json.loads(line) for line in atomic_path.open(encoding="utf-8"))}
    out = ROOT / "turkish_composite_examples.v1.jsonl"
    with out.open("w", encoding="utf-8", newline="\n") as f:
        for n, ids in enumerate(PAIRS, 1):
            components = [atomic[i] for i in ids]
            variants = [r["variant"] for r in components]
            prompt = "İki alt görevi de ayrı ayrı tamamla; her hedefi kendi kanıt ve çıktı biçimiyle döndür. " + " Ardından ".join(r["messages"][0]["content"] for r in components)
            targets = [{"component_id": r["id"], "variant": r["variant"], "target": r["target"]} for r in components]
            record = {
                "schema": "noema.composite_example.v1",
                "id": f"tr-composite-{n:04d}",
                "group_key": f"composite-family-{n:04d}",
                "split": "train",
                "variant_combo": variants,
                "composition": {"mode": "multi_objective", "operator": "parallel_subtasks", "component_order_is_semantic": True},
                "messages": [{"role": "user", "content": prompt}],
                "components": components,
                "target": {"kind": "multi_target", "items": targets},
                "labels": {"decision": "composite", "component_count": len(components)},
                "provenance": {"source": "synthetic_composition", "license": "internal-demo", "review": "unreviewed", "generator": "build_composite_examples.py"},
            }
            f.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"wrote {len(PAIRS)} JSONL composite examples; {len({v for p in PAIRS for v in (atomic[p[0]]['variant'], atomic[p[1]]['variant'])})} atomic variants covered")


if __name__ == "__main__":
    main()
