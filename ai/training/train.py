"""
Training script for fine-tuning local NLP models.
Supports BERT/DistilBERT fine-tuning for intent detection and NER.
"""

import logging
import os
from pathlib import Path
from typing import Dict, List
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def prepare_training_data(data_path: str) -> Dict:
    """
    Prepare training data from JSON files.
    
    Expected format:
    {
        "intent": [
            {"text": "...", "label": "reminder"},
            ...
        ],
        "ner": [
            {"text": "...", "entities": [...]},
            ...
        ]
    }
    """
    with open(data_path, 'r') as f:
        data = json.load(f)
    
    logger.info(f"Loaded {len(data.get('intent', []))} intent examples")
    logger.info(f"Loaded {len(data.get('ner', []))} NER examples")
    
    return data


def train_intent_model(data: List[Dict], output_dir: str = "ai/models/intent_model"):
    """
    Train intent detection model using Hugging Face Transformers.
    
    Args:
        data: List of training examples with 'text' and 'label'
        output_dir: Directory to save the model
    """
    try:
        from transformers import AutoTokenizer, AutoModelForSequenceClassification, TrainingArguments, Trainer
        from datasets import Dataset
        
        logger.info("Training intent detection model...")
        
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)

        # Load pre-trained model
        model_name = "distilbert-base-uncased"
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        label_names = sorted(set(item["label"] for item in data))
        label_to_id = {label: idx for idx, label in enumerate(label_names)}
        id_to_label = {idx: label for label, idx in label_to_id.items()}
        model = AutoModelForSequenceClassification.from_pretrained(
            model_name,
            num_labels=len(label_names),
            id2label=id_to_label,
            label2id=label_to_id,
        )
        
        # Prepare dataset
        texts = [item["text"] for item in data]
        labels = [label_to_id[item["label"]] for item in data]
        
        # Tokenize
        encodings = tokenizer(texts, truncation=True, padding=True, max_length=128)
        
        # Create dataset
        dataset = Dataset.from_dict({
            "input_ids": encodings["input_ids"],
            "attention_mask": encodings["attention_mask"],
            "labels": labels
        })
        
        # Training arguments
        training_args = TrainingArguments(
            output_dir=output_dir,
            num_train_epochs=3,
            per_device_train_batch_size=16,
            per_device_eval_batch_size=16,
            warmup_steps=500,
            weight_decay=0.01,
            logging_dir=f"{output_dir}/logs",
        )
        
        # Trainer
        trainer = Trainer(
            model=model,
            args=training_args,
            train_dataset=dataset,
        )
        
        # Train
        trainer.train()
        
        # Save model
        model.save_pretrained(output_dir)
        tokenizer.save_pretrained(output_dir)

        # Persist label mapping and model metadata for inference alignment.
        with (output_path / "label_map.json").open("w", encoding="utf-8") as f:
            json.dump({"label_to_id": label_to_id, "id_to_label": id_to_label}, f, indent=2)
        with (output_path / "model_info.json").open("w", encoding="utf-8") as f:
            json.dump(
                {
                    "base_model": model_name,
                    "num_labels": len(label_names),
                    "labels": label_names,
                },
                f,
                indent=2,
            )
        
        logger.info(f"Model saved to {output_dir}")
        
    except ImportError:
        logger.warning("Transformers library not installed. Install with: pip install transformers datasets")
    except Exception as e:
        logger.error(f"Training failed: {e}")


def evaluate_model(model_path: str, test_data: List[Dict]) -> Dict:
    """
    Evaluate model performance.
    
    Returns:
        dict with accuracy, precision, recall, F1 score
    """
    try:
        from transformers import AutoTokenizer, AutoModelForSequenceClassification
        from sklearn.metrics import accuracy_score, precision_recall_fscore_support
        
        # Load model + label mapping artifacts
        tokenizer = AutoTokenizer.from_pretrained(model_path)
        model = AutoModelForSequenceClassification.from_pretrained(model_path)
        label_map_path = Path(model_path) / "label_map.json"
        if not label_map_path.exists():
            raise FileNotFoundError(f"Missing label_map.json in {model_path}")
        with label_map_path.open("r", encoding="utf-8") as f:
            label_map = json.load(f)
        label_to_id = {str(k): int(v) for k, v in label_map.get("label_to_id", {}).items()}
        
        # Predictions
        filtered = [item for item in test_data if item.get("label") in label_to_id]
        dropped_count = len(test_data) - len(filtered)
        if not filtered:
            raise ValueError("No evaluation rows match label_map.json labels")
        texts = [item["text"] for item in filtered]
        true_labels = [label_to_id[item["label"]] for item in filtered]
        
        # Tokenize and predict
        encodings = tokenizer(texts, truncation=True, padding=True, max_length=128, return_tensors="pt")
        outputs = model(**encodings)
        predictions = outputs.logits.argmax(dim=-1).tolist()
        
        # Calculate metrics
        accuracy = accuracy_score(true_labels, predictions)
        precision, recall, f1, _ = precision_recall_fscore_support(true_labels, predictions, average='weighted')
        
        return {
            "accuracy": accuracy,
            "precision": precision,
            "recall": recall,
            "f1_score": f1,
            "samples_used": len(filtered),
            "samples_dropped_unknown_label": dropped_count,
        }
        
    except Exception as e:
        logger.error(f"Evaluation failed: {e}")
        return {}


def main():
    """Main training function."""
    data_path = "ai/training/data/training_data.json"

    if not os.path.exists(data_path):
        logger.warning(f"Training data not found at {data_path}.")
        logger.info("Generating dataset... Run: python ai/training/data/generate_enhanced_dataset.py")
        return
    
    # Load data
    data = prepare_training_data(data_path)
    
    # Check dataset size
    intent_count = len(data.get("intent", []))
    ner_count = len(data.get("ner", []))
    
    logger.info(f"Dataset loaded: {intent_count} intent examples, {ner_count} NER examples")
    
    if intent_count < 100:
        logger.warning("Dataset is small. Consider generating a larger dataset.")
        logger.info("Run: python ai/training/data/generate_enhanced_dataset.py")
    
    # Train intent model
    if data.get("intent") and intent_count >= 10:
        logger.info("Training intent detection model...")
        train_intent_model(data["intent"])
    else:
        logger.warning("Not enough intent examples for training. Need at least 10 examples.")
    
    logger.info("Training completed!")


if __name__ == "__main__":
    main()

