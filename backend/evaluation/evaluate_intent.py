"""Intent evaluation script with reproducible metrics output."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt, detect_intent_spacy

ALLOWED = ["reminder", "note", "expense", "query", "other"]


def _is_live_claim_run(use_llm: bool) -> bool:
    mock_mode = os.getenv("MOCK_MODE", "false").strip().lower() in {"1", "true", "yes", "on"}
    return bool(use_llm) and not mock_mode


def _metrics(y_true: List[str], y_pred: List[str]) -> Dict:
    labels = ALLOWED
    cm = {l: {k: 0 for k in labels} for l in labels}
    for t, p in zip(y_true, y_pred):
        cm[t][p] += 1

    total = len(y_true)
    correct = sum(1 for t, p in zip(y_true, y_pred) if t == p)
    accuracy = (correct / total) if total else 0.0

    per_class = {}
    for c in labels:
        tp = cm[c][c]
        fp = sum(cm[t][c] for t in labels if t != c)
        fn = sum(cm[c][p] for p in labels if p != c)
        precision = tp / (tp + fp) if (tp + fp) else 0.0
        recall = tp / (tp + fn) if (tp + fn) else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
        per_class[c] = {
            "precision": round(precision, 4),
            "recall": round(recall, 4),
            "f1": round(f1, 4),
            "support": sum(cm[c].values()),
        }

    macro_f1 = sum(v["f1"] for v in per_class.values()) / len(labels)
    return {
        "accuracy": round(accuracy, 4),
        "macro_f1": round(macro_f1, 4),
        "per_class": per_class,
        "confusion_matrix": cm,
        "samples": total,
    }


def _load_intent_examples(path: Path) -> List[Tuple[str, str]]:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    rows = []
    for item in data.get("intent", []):
        text = str(item.get("text", "")).strip()
        label = str(item.get("label", "other")).strip().lower()
        if text and label in ALLOWED:
            rows.append((text, label))
    return rows


async def _predict(text: str, use_llm: bool) -> str:
    if use_llm:
        out = await detect_intent_gpt(text)
    else:
        out = detect_intent_spacy(text)
    pred = str(out.get("intent", "other")).lower()
    return pred if pred in ALLOWED else "other"


async def run(args: argparse.Namespace) -> Dict:
    dataset_path = Path(args.dataset)
    rows = _load_intent_examples(dataset_path)
    if not rows:
        raise RuntimeError("No valid intent rows found.")

    rnd = random.Random(args.seed)
    rnd.shuffle(rows)
    if args.sample_size > 0:
        rows = rows[: min(args.sample_size, len(rows))]

    split = int(len(rows) * (1 - args.holdout_ratio))
    holdout = rows[split:]
    if not holdout:
        holdout = rows

    detector_mode_before = os.getenv("INTENT_DETECTOR_MODE", "openai")
    if args.use_llm and detector_mode_before != "openai":
        os.environ["INTENT_DETECTOR_MODE"] = "openai"

    y_true, y_pred = [], []
    errors = []
    try:
        for text, label in holdout:
            pred = await _predict(text, use_llm=args.use_llm)
            y_true.append(label)
            y_pred.append(pred)
            if pred != label and len(errors) < args.max_errors:
                errors.append({"text": text, "true": label, "pred": pred})
    finally:
        if args.use_llm:
            os.environ["INTENT_DETECTOR_MODE"] = detector_mode_before

    result = _metrics(y_true, y_pred)
    live_claim_run = _is_live_claim_run(args.use_llm)
    claim_proven = live_claim_run and result["accuracy"] >= args.target_accuracy
    result["meta"] = {
        "dataset": str(dataset_path.as_posix()),
        "use_llm": bool(args.use_llm),
        "intent_detector_mode_before": detector_mode_before,
        "intent_detector_mode_effective": "openai" if args.use_llm else detector_mode_before,
        "mock_mode": os.getenv("MOCK_MODE", "false"),
        "seed": args.seed,
        "sample_size": len(rows),
        "holdout_size": len(holdout),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "target_accuracy": args.target_accuracy,
        "live_claim_run": live_claim_run,
    }
    result["claim_verdict"] = {
        "metric": "accuracy",
        "target": args.target_accuracy,
        "actual": result["accuracy"],
        "proven": claim_proven,
        "status": "proven" if claim_proven else "not_proven",
        "reason": (
            "accuracy_below_target"
            if live_claim_run and not claim_proven
            else ("not_live_llm_run" if not live_claim_run else "meets_target")
        ),
    }
    result["errors_preview"] = errors
    return result


def _write_markdown_report(result: Dict, out_md: Path) -> None:
    meta = result.get("meta", {})
    claim = result.get("claim_verdict", {})
    per_class = result.get("per_class", {})
    errors = result.get("errors_preview", [])

    lines = [
        "# Intent Evaluation Report",
        "",
        "## Summary",
        f"- Generated at: {meta.get('generated_at', 'n/a')}",
        f"- Dataset: {meta.get('dataset', 'n/a')}",
        f"- Use LLM: {meta.get('use_llm', False)}",
        f"- Mock mode: {meta.get('mock_mode', 'false')}",
        f"- Holdout size: {meta.get('holdout_size', 0)}",
        "",
        "## Metrics",
        f"- Accuracy: {result.get('accuracy', 0.0)}",
        f"- Macro F1: {result.get('macro_f1', 0.0)}",
        "",
        "## Claim Verdict",
        f"- Target accuracy: {claim.get('target', meta.get('target_accuracy', 'n/a'))}",
        f"- Actual accuracy: {claim.get('actual', result.get('accuracy', 0.0))}",
        f"- Live run: {meta.get('live_claim_run', False)}",
        f"- Status: {claim.get('status', 'not_proven')}",
        f"- Reason: {claim.get('reason', 'n/a')}",
        "",
        "## Per-Class",
        "| Class | Precision | Recall | F1 | Support |",
        "|---|---:|---:|---:|---:|",
    ]
    for label in ALLOWED:
        row = per_class.get(label, {})
        lines.append(
            f"| {label} | {row.get('precision', 0.0)} | {row.get('recall', 0.0)} | {row.get('f1', 0.0)} | {row.get('support', 0)} |"
        )

    lines.extend(["", "## Top Errors"])
    if not errors:
        lines.append("- None")
    else:
        for i, e in enumerate(errors[:15], start=1):
            lines.append(f"{i}. true={e.get('true')} pred={e.get('pred')} text=\"{e.get('text')}\"")

    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--dataset", default="ai/training/data/training_data.json")
    p.add_argument("--sample-size", type=int, default=400)
    p.add_argument("--holdout-ratio", type=float, default=0.2)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--use-llm", action="store_true")
    p.add_argument("--mock-mode", action="store_true")
    p.add_argument("--max-errors", type=int, default=25)
    p.add_argument("--target-accuracy", type=float, default=0.90)
    p.add_argument("--enforce-claim-gate", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.mock_mode:
        os.environ["MOCK_MODE"] = "true"
    out = asyncio.run(run(args))

    results_dir = Path("backend/evaluation/results")
    results_dir.mkdir(parents=True, exist_ok=True)
    out_path = results_dir / f"intent_eval_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    md_path = out_path.with_suffix(".md")
    _write_markdown_report(out, md_path)

    print(
        json.dumps(
            {
                "accuracy": out["accuracy"],
                "macro_f1": out["macro_f1"],
                "claim_status": out.get("claim_verdict", {}).get("status", "not_proven"),
                "output_json": str(out_path),
                "output_md": str(md_path),
            },
            indent=2,
        )
    )

    if args.enforce_claim_gate and not out.get("claim_verdict", {}).get("proven", False):
        raise SystemExit("Claim gate failed: intent target not proven by live benchmark run.")


if __name__ == "__main__":
    main()
