# Training Data

## Location

Use a single canonical dataset file:

- `ai/training/data/training_data.json`

Do not keep duplicate copies at repository root.

## Generate Dataset

From project root:

```bash
python ai/training/data/generate_enhanced_dataset.py
```

## Train Intent Model

From project root:

```bash
python ai/training/train.py
```

## Expected JSON Shape

```json
{
  "intent": [
    {"text": "Remind me to visit Badshahi Mosque tomorrow", "label": "reminder"},
    {"text": "Spent PKR 500 on biryani", "label": "expense"}
  ],
  "ner": [
    {
      "text": "Spent PKR 500 on biryani in Karachi",
      "entities": [
        {"text": "PKR 500", "label": "MONEY", "start": 6, "end": 13},
        {"text": "Karachi", "label": "GPE", "start": 28, "end": 35}
      ]
    }
  ]
}
```

## Validation Checklist

- `intent` exists and contains `{text, label}` objects.
- `ner` exists and contains `{text, entities}` objects.
- Entity spans (`start`, `end`) are valid for each `text`.
- Label distribution is balanced across `reminder`, `note`, `expense`, `query`, `other`.

## Notes

- Current project runtime uses OpenAI APIs for production inference.
- Local dataset is useful for offline/fallback training experiments and academic evaluation evidence.
