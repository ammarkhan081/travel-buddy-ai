"""Intent classification and unified speech-command orchestration routes."""

import logging
import json
from typing import Optional
from fastapi import APIRouter, HTTPException, UploadFile, File, Depends, Query
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..models.decision_review import DecisionReview
    from ..schemas.intent import (
        IntentClassifyRequest,
        IntentClassifyResponse,
        DecisionReviewResolveRequest,
        DecisionReviewResolveResponse,
    )
    from ..services import intent_orchestrator_service
    from ..utils.error_policy import STTError, IntentError, ExtractionError
    from ..utils.time_utils import now_utc_iso
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from models.decision_review import DecisionReview
    from schemas.intent import (
        IntentClassifyRequest,
        IntentClassifyResponse,
        DecisionReviewResolveRequest,
        DecisionReviewResolveResponse,
    )
    from services import intent_orchestrator_service
    from utils.error_policy import STTError, IntentError, ExtractionError
    from utils.time_utils import now_utc_iso
from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/classify", response_model=IntentClassifyResponse)
async def classify_intent(request: IntentClassifyRequest):
    """
    Classify user text as reminder, expense, note, query, or other.
    Used by the app to automatically create reminder or expense from voice without extra tap.
    """
    try:
        intent_dict = await detect_intent_gpt(request.text)
        intent = intent_dict.get("intent", "other")
        if intent not in ("reminder", "expense", "note", "query", "other"):
            intent = "other"
        return IntentClassifyResponse(intent=intent)
    except Exception as e:
        logger.exception("classify_intent_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to classify intent.")


@router.post("/process-voice")
async def process_voice_command(
    file: UploadFile = File(...),
    persist: bool = Query(default=True),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Unified pipeline endpoint:
    Speech -> STT -> Intent -> (Reminder/Expense/Knowledge) storage
    """
    try:
        return await intent_orchestrator_service.process_voice_command(
            db,
            file.file,
            current_user.uid,
            persist=persist,
        )
    except (STTError, IntentError, ExtractionError) as e:
        logger.warning("process_voice_command_validation_failed", extra={"error": str(e)})
        raise HTTPException(status_code=422, detail="Failed to process voice command.")
    except Exception as e:
        logger.exception("process_voice_command_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Unexpected error while processing voice command.")


@router.post("/reviews/{review_id}/resolve", response_model=DecisionReviewResolveResponse)
async def resolve_decision_review(
    review_id: int,
    payload: DecisionReviewResolveRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Resolve a pending voice-decision audit record as accepted/rejected/edited."""
    review = (
        db.query(DecisionReview)
        .filter(DecisionReview.id == review_id, DecisionReview.user_id == current_user.uid)
        .first()
    )
    if not review:
        raise HTTPException(status_code=404, detail="Review record not found.")

    setattr(review, "status", payload.action)
    setattr(review, "resolution_payload", json.dumps(payload.resolution_payload or {}, ensure_ascii=False))
    setattr(review, "resolved_at", now_utc_iso())
    db.commit()
    db.refresh(review)
    rid = getattr(review, "id", review_id)
    status_value = str(getattr(review, "status", payload.action))
    resolved_at_value = getattr(review, "resolved_at", None)
    return DecisionReviewResolveResponse(
        id=int(rid),
        status=status_value,
        resolved_at=str(resolved_at_value) if resolved_at_value is not None else None,
    )
