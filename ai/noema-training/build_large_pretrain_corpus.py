#!/usr/bin/env python3
"""Assemble local documentation into plain-text topic records for LIR pretraining.

This is offline corpus preparation only. It removes Markdown presentation/code
blocks, groups adjacent prose paragraphs, and writes a standalone '---' line
between topics. No tokens or model-specific labels are created.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "ai/noema-training/pretrain_corpus_large.tr.txt"
MAX_TOPIC_BYTES = 10_000
PROSE_SOURCES = [
    "README.md",
    "ai/README.md",
    "ai/docs/DESIGN.md",
    "ai/docs/NOEMA.md",
    "ai/noema-training/DATASET_VARIANTS.md",
    "ai/noema-training/training_chat_results.md",
    "docs/AI.md",
    "docs/BROWSER.md",
    "docs/CHEATSHEET.md",
    "docs/CMF_PARADIGM.md",
    "docs/COMPILER_ARCHITECTURE.md",
    "docs/CONTRIBUTING.md",
    "docs/CORE_LANGUAGE.md",
    "docs/CSHARP_SCOPE.md",
    "docs/HYPERION_ASSESSMENT.md",
    "docs/LANGUAGE_EXTENSIONS.md",
    "docs/LANGUAGE_REFERENCE.md",
    "docs/LOW_LEVEL_LANGUAGE.md",
    "docs/ODIN_VS_LIR.md",
    "docs/PROJECTS.md",
    "docs/REVIEW.md",
    "docs/ROADMAP.md",
    "docs/SPEC.md",
    "docs/STATUS.md",
    "docs/STDLIB.md",
]
CODE_SOURCES = [
    "src/lir/compiler.lir",
    "src/lir/compiler/lexer.lir",
    "src/lir/compiler/parser.lir",
    "src/lir/compiler/types.lir",
    "src/lir/compiler/codegen.lir",
    "src/lir/compiler/optimizer.lir",
    "src/lir/compiler/main.lir",
    "src/lir/build_system.lir",
    "src/lir/main.lir",
    "src/lir/std/core.lir",
    "src/lir/std/io.lir",
    "src/lir/std/json.lir",
    "src/lir/std/os.lir",
    "ai/src/noema_pretrain.lir",
    "ai/src/noema_reasoning.lir",
    "ai/src/noema_chat.lir",
    "examples/canonical-tour.lir",
    "examples/echo_server.lir",
    "examples/file_io_demo.lir",
    "examples/modern-demo.lir",
    "examples/thread_demo.lir",
]


def plain_text(markdown: str) -> list[str]:
    text = re.sub(r"(?s)<!--.*?-->", " ", markdown)
    text = re.sub(r"(?m)^\s*```.*$", " ", text)
    text = re.sub(r"(?m)^\s*~~~.*$", " ", text)
    text = re.sub(r"(?m)^\s*\|.*$", " ", text)
    text = re.sub(r"!\[([^]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", text)
    text = re.sub(r"(?m)^\s*(?:[-*+]\s+|\d+[.)]\s+)", "", text)
    text = re.sub(r"(?m)^\s*[-*_]{3,}\s*$", " ", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]+)\*", r"\1", text)
    text = re.sub(r"(?m)^\s*>\s?", "", text)
    chunks = []
    for paragraph in re.split(r"\n\s*\n+", text):
        paragraph = re.sub(r"\s+", " ", paragraph).strip()
        if len(paragraph.encode("utf-8")) >= 100:
            chunks.append(paragraph)
    return chunks


def pack(paragraphs: list[str]) -> list[str]:
    topics: list[str] = []
    current: list[str] = []
    size = 0
    for paragraph in paragraphs:
        psize = len(paragraph.encode("utf-8"))
        if psize > MAX_TOPIC_BYTES:
            # Split only at spaces, retaining the text and avoiding an oversized
            # single .nbin record; this is framing, not tokenization.
            words = paragraph.split(" ")
            part = ""
            for word in words:
                candidate = word if not part else part + " " + word
                if len(candidate.encode("utf-8")) > MAX_TOPIC_BYTES:
                    if part:
                        if current:
                            topics.append(" ".join(current))
                            current, size = [], 0
                        topics.append(part)
                    part = word
                else:
                    part = candidate
            if part:
                if current:
                    topics.append(" ".join(current))
                    current, size = [], 0
                topics.append(part)
            continue
        extra = psize + (1 if current else 0)
        if current and size + extra > MAX_TOPIC_BYTES:
            topics.append(" ".join(current))
            current, size = [], 0
        current.append(paragraph)
        size += psize + (1 if len(current) > 1 else 0)
    if current:
        topics.append(" ".join(current))
    return topics


def main() -> None:
    sources = PROSE_SOURCES + CODE_SOURCES
    missing = [name for name in sources if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit("Missing corpus source(s): " + ", ".join(missing))
    paras: list[str] = []
    for name in PROSE_SOURCES:
        source = ROOT / name
        paras.extend(plain_text(source.read_text(encoding="utf-8")))
    topics = pack(paras)
    # LIR files are included as unmodified plain-text/code documents, line-packed
    # only to keep each binary record within the model reader's bounded buffer.
    for name in CODE_SOURCES:
        source = ROOT / name
        pending = ""
        for line in source.read_text(encoding="utf-8").splitlines(keepends=True):
            if len((pending + line).encode("utf-8")) > MAX_TOPIC_BYTES and pending:
                topics.append(pending.rstrip("\r\n"))
                pending = ""
            pending += line
        if pending.strip():
            topics.append(pending.rstrip("\r\n"))
    topics = [topic.strip(" \t\r\n") for topic in topics]
    topics = [topic for topic in topics if topic]
    if not topics:
        raise SystemExit("No prose topics found")
    OUTPUT.write_text("\n---\n".join(topics), encoding="utf-8")
    raw_bytes = sum(len(topic.encode("utf-8")) for topic in topics)
    print(f"topics={len(topics)}")
    print(f"payload_bytes={raw_bytes}")
    print(f"source_file_bytes={OUTPUT.stat().st_size}")
    print(f"output={OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
