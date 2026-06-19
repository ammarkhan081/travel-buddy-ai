"""Routes for the AI Chat API.

Endpoints:
- POST /api/chat/reply                           (legacy stateless, kept for back-compat)
- GET  /api/chat/conversations                   list user's conversations (sidebar)
- POST /api/chat/conversations                   create a new empty conversation
- PATCH /api/chat/conversations/{id}             rename a conversation
- GET  /api/chat/conversations/{id}/messages     get all messages in a conversation
- POST /api/chat/conversations/{id}/reply        send a user message, get assistant reply
- DELETE /api/chat/conversations/{id}            delete a conversation and its messages
"""

import logging
from typing import Dict, List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.chat import (
        ChatConversationResponse,
        ChatMessageResponse,
        ChatRenameRequest,
        ChatSendRequest,
        ChatTurnResponse,
    )
    from ..services import chat_service
    from ..utils.error_policy import ChatError
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.chat import (
        ChatConversationResponse,
        ChatMessageResponse,
        ChatRenameRequest,
        ChatSendRequest,
        ChatTurnResponse,
    )
    from services import chat_service
    from utils.error_policy import ChatError

router = APIRouter()
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Legacy stateless reply (kept so the old frontend path still works)
# ---------------------------------------------------------------------------
class ChatRequest(BaseModel):
    messages: List[Dict[str, str]]
    user_id: str = "default"


class ChatResponse(BaseModel):
    reply: str


@router.post("/reply", response_model=ChatResponse)
async def chat_reply(
    request: ChatRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Stateless one-shot reply with hybrid RAG. Prefer the new conversation routes."""
    try:
        reply = await chat_service.generate_chat_response(
            messages=request.messages,
            user_id=current_user.uid,
            db=db,
        )
        return ChatResponse(reply=reply)
    except ChatError as e:
        logger.warning("chat_reply_service_unavailable", extra={"error": str(e)})
        raise HTTPException(status_code=503, detail="Chat service is temporarily unavailable.")
    except Exception as e:
        logger.exception("chat_reply_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to generate chat reply.")


# ---------------------------------------------------------------------------
# Conversation CRUD
# ---------------------------------------------------------------------------
@router.get("/conversations", response_model=List[ChatConversationResponse])
async def list_conversations(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """List the user's conversations, most recently updated first."""
    return chat_service.list_conversations(db, current_user.uid)


@router.post("/conversations", response_model=ChatConversationResponse)
async def create_conversation(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Create a new empty conversation. The title is auto-generated on first message."""
    return chat_service.create_conversation(db, current_user.uid)


@router.get("/conversations/{conv_id}/messages", response_model=List[ChatMessageResponse])
async def get_messages(
    conv_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Get all messages in a conversation (chronological)."""
    conv = chat_service.get_conversation(db, conv_id, current_user.uid)
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    return chat_service.list_messages(db, conv_id, current_user.uid)


@router.patch("/conversations/{conv_id}", response_model=ChatConversationResponse)
async def rename_conversation(
    conv_id: int,
    payload: ChatRenameRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Rename a saved conversation from the sidebar."""
    try:
        conv = chat_service.rename_conversation(db, conv_id, current_user.uid, payload.title)
    except ChatError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    return conv


@router.post("/conversations/{conv_id}/reply", response_model=ChatTurnResponse)
async def send_message(
    conv_id: int,
    payload: ChatSendRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Send a user message in a conversation and get an AI reply.

    Persists both the user message and the assistant reply. On the first user turn
    the conversation title is auto-generated from the message.
    """
    conv = chat_service.get_conversation(db, conv_id, current_user.uid)
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    try:
        user_row, assistant_row, conv = await chat_service.handle_user_turn(
            db=db,
            conversation=conv,
            user_message=payload.message,
            user_id=current_user.uid,
            user_name=current_user.name,
        )
        return ChatTurnResponse(
            conversation_id=conv.id,
            title=conv.title,
            user_message=ChatMessageResponse.model_validate(user_row),
            assistant_message=ChatMessageResponse.model_validate(assistant_row),
        )
    except ChatError as e:
        logger.warning("chat_turn_validation_failed", extra={"error": str(e)})
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.exception("chat_turn_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to generate chat reply.")


@router.delete("/conversations/{conv_id}")
async def delete_conversation(
    conv_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Delete a conversation and all its messages."""
    if chat_service.delete_conversation(db, conv_id, current_user.uid):
        return {"message": "Conversation deleted."}
    raise HTTPException(status_code=404, detail="Conversation not found.")
