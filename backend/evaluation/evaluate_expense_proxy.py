"""Expense extraction proxy benchmark (weak-label based)."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(ROOT))

from ai.inference.expense_parser.expense_extractor import extract_expense_gpt


def _weak_label_amount(text: str) -> Optional[float]:
    m = re.search(r"(\d+(\.\d+)?)", text)
    return float(m.group(1)) if m else None


def _load_expense_texts(path: Path) -> List[str]:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    out = []
    for item in data.get("intent", []):
        if str(item.get("label", "")).lower() == "expense":
            t = str(item.get("text", "")).strip()
            if t:
                out.append(t)
    return out


async def run(args: argparse.Namespace) -> Dict:
    rows = _load_expense_texts(Path(args.dataset))
    rnd = random.Random(args.seed)
    rnd.shuffle(rows)
    if args.sample_size > 0:
        rows = rows[: min(args.sample_size, len(rows))]

    amount_hits = 0
    category_non_other = 0
    total = 0
    failures = []

    for text in rows:
        weak_amount = _weak_label_amount(text)
        try:
            pred = await extract_expense_gpt(text)
        except Exception as e:
            if len(failures) < 20:
                failures.append({"text": text, "error": str(e)})
            continue

        total += 1
        pred_amount = float(pred.get("amount", 0.0) or 0.0)
        if weak_amount is not None:
            if abs(pred_amount - weak_amount) <= max(1.0, weak_amount * 0.1):
                amount_hits += 1
        pred_cat = str(pred.get("category", "other")).lower()
        if pred_cat != "other":
            category_non_other += 1

    amount_proxy_acc = (amount_hits / total) if total else 0.0
    category_signal_rate = (category_non_other / total) if total else 0.0
    return {
        "amount_proxy_accuracy": round(amount_proxy_acc, 4),
        "category_signal_rate": round(category_signal_rate, 4),
        "samples_attempted": len(rows),
        "samples_scored": total,
        "failures_preview": failures,
        "meta": {
            "dataset": args.dataset,
            "mock_mode": os.getenv("MOCK_MODE", "false"),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        },
        "note": "Proxy benchmark only. Use curated ground-truth dataset for publishable extraction metrics.",
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--dataset", default="ai/training/data/training_data.json")
    p.add_argument("--sample-size", type=int, default=300)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--mock-mode", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.mock_mode:
        os.environ["MOCK_MODE"] = "true"
    out = asyncio.run(run(args))

    results_dir = Path("backend/evaluation/results")
    results_dir.mkdir(parents=True, exist_ok=True)
    out_path = results_dir / f"expense_proxy_eval_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(json.dumps({"output": str(out_path), "amount_proxy_accuracy": out["amount_proxy_accuracy"]}, indent=2))


if __name__ == "__main__":
    main()
