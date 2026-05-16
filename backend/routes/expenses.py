"""Routes for expenses API."""

import logging
from fastapi import APIRouter, HTTPException, UploadFile, File, Depends, Query
from typing import List, Optional
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.expenses import ExpenseCreate, ExpenseResponse, ExpenseExtraction
    from ..services import expense_service, intent_orchestrator_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.expenses import ExpenseCreate, ExpenseResponse, ExpenseExtraction
    from services import expense_service, intent_orchestrator_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[ExpenseResponse])
async def get_expenses(
    user_id: Optional[str] = Query(default="default"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/expenses: Returns all expenses from SQLite as JSON list."""
    return expense_service.get_expenses(db, current_user.uid)


@router.post("/", response_model=ExpenseResponse)
async def add_expense(
    expense: ExpenseCreate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/expenses: Accepts manual expense and saves to SQLite."""
    try:
        expense.user_id = current_user.uid
        return await expense_service.create_expense(db, expense)
    except Exception as e:
        logger.exception("expense_create_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create expense.")


@router.post("/voice", response_model=ExpenseExtraction)
async def add_expense_voice(
    file: UploadFile = File(...),
    user_id: Optional[str] = Query(default="default"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/expenses/voice: Whisper STT + Extraction (Review-first)."""
    try:
        result = await intent_orchestrator_service.process_voice_command(
            db,
            file.file,
            current_user.uid,
            persist=False,
        )
        if result.get("intent") != "expense":
            return ExpenseExtraction(
                amount=0.0,
                currency="USD",
                category="other",
                description=result.get("transcript", "No expense extracted"),
                location=None,
                confidence=0.0,
            )
        details = result.get("details", {})
        return ExpenseExtraction(
            amount=float(details.get("amount", 0.0)),
            currency="USD",
            category=str(details.get("category", "other")),
            description=result.get("transcript", ""),
            location=None,
            confidence=float(details.get("confidence", 0.0)),
        )
    except Exception as e:
        error_msg = str(e)
        if "API key" in error_msg or "401" in error_msg:
            raise HTTPException(
                status_code=503, 
                detail="OpenAI API key is missing or invalid. Please check your .env file."
            )
        raise HTTPException(status_code=422, detail=error_msg)


@router.post("/ocr", response_model=ExpenseExtraction)
async def extract_expense_ocr(
    file: UploadFile = File(...),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    POST /api/expenses/ocr: Extract expense fields from a receipt image
    using OpenAI GPT-4o Vision. Returns parsed amount, category, description, date.
    Falls back to 503 if OpenAI key is missing, 422 if parsing fails.
    """
    import base64
    import json
    from datetime import date as date_module

    try:
        from ..config import Settings
    except ImportError:
        from config import Settings

    settings = Settings()
    api_key = settings.OPENAI_API_KEY
    if not api_key or api_key.startswith("sk-placeholder"):
        raise HTTPException(
            status_code=503,
            detail="OCR is unavailable: OPENAI_API_KEY is missing or invalid in .env",
        )

    # Read and encode the uploaded image
    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=422, detail="No image data received.")
    b64_image = base64.standard_b64encode(image_bytes).decode("utf-8")

    # Infer MIME type (accept JPEG and PNG; default to JPEG if unknown)
    content_type = file.content_type or "image/jpeg"
    if content_type not in ("image/jpeg", "image/png", "image/webp", "image/gif"):
        content_type = "image/jpeg"

    today = date_module.today().isoformat()
    prompt = (
        "You are a receipt parser. Extract expense fields from the receipt image. "
        "Return ONLY a JSON object with these keys: "
        '"amount" (number, total amount paid), '
        '"currency" (string, e.g. USD, PKR), '
        '"category" (one of: food, transportation, shopping, entertainment, bills, other), '
        '"description" (short string, what was purchased), '
        f'"date" (ISO date string YYYY-MM-DD, today is {today}). '
        "If a field cannot be determined, use null for strings and 0 for numbers. "
        "Do not include any explanation, only the JSON object."
    )

    try:
        from openai import OpenAI
        client = OpenAI(api_key=api_key, timeout=30.0)
        response = client.chat.completions.create(
            model="gpt-4o",
            max_tokens=200,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{content_type};base64,{b64_image}",
                                "detail": "low",   # cheaper + faster for receipts
                            },
                        },
                    ],
                }
            ],
        )
        raw = response.choices[0].message.content.strip()
        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        parsed = json.loads(raw)
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=422, detail=f"OCR: could not parse AI response as JSON: {e}")
    except Exception as e:
        err = str(e)
        if "401" in err or "api_key" in err.lower():
            raise HTTPException(status_code=503, detail="OCR: OpenAI API key invalid or unauthorised.")
        raise HTTPException(status_code=422, detail=f"OCR extraction failed: {err}")

    amount = float(parsed.get("amount") or 0.0)
    return ExpenseExtraction(
        amount=amount,
        currency=str(parsed.get("currency") or "USD"),
        category=str(parsed.get("category") or "other"),
        description=str(parsed.get("description") or ""),
        location=None,
        confidence=0.85 if amount > 0 else 0.3,
    )


@router.delete("/{expense_id}")
async def delete_expense(
    expense_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """DELETE /api/expenses/{id}: Deletes expense — only if it belongs to the caller."""
    if expense_service.delete_expense(db, expense_id, current_user.uid):
        return {"message": "Expense deleted successfully"}
    raise HTTPException(status_code=404, detail="Expense not found")


@router.get("/summary")
async def get_expense_summary(
    user_id: Optional[str] = Query(default="default"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/expenses/summary: Returns total, breakdown by category, breakdown by date."""
    return expense_service.get_expense_summary(db, current_user.uid)


@router.get("/filter", response_model=List[ExpenseResponse])
async def filter_expenses(
    user_id: Optional[str] = Query(default="default"),
    category: Optional[str] = Query(None),
    start: Optional[str] = Query(None),
    end: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/expenses/filter: Filters by category, start, and end dates."""
    return expense_service.filter_expenses(db, current_user.uid, category, start, end)
