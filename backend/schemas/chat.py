"""Schemas for the ChatGPT-style conversation API."""

from typing import Optional
from pydantic import BaseModel, Field


class ChatConversationResponse(BaseModel):
    """A conversation row for the sidebar list."""

    id: int
    title: str
    last_location: Optional[str] = None
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class ChatMessageResponse(BaseModel):
    """A single message inside a conversation."""

    id: int
    conversation_id: int
    role: str = Field(..., description="user | assistant")
    content: str
    created_at: str

    class Config:
        from_attributes = True


class ChatSendRequest(BaseModel):
    """Body for POST /api/chat/conversations/{id}/reply."""

    message: str = Field(..., min_length=1, max_length=4000)


class ChatRenameRequest(BaseModel):
    """Body for renaming a saved conversation."""

    title: str = Field(..., min_length=1, max_length=80)


class ChatTurnResponse(BaseModel):
    """Result of one user turn: persisted user + assistant messages and updated conversation."""

    conversation_id: int
    title: str
    user_message: ChatMessageResponse
    assistant_message: ChatMessageResponse
