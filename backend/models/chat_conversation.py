from sqlalchemy import Column, Integer, String
try:
    from ..database import Base
except ImportError:
    from database import Base


class ChatConversation(Base):
    """A single chat thread between the user and Travel Buddy AI.

    Persisted per-user so the ChatGPT-style sidebar can list old conversations.
    `last_location` implements v6's LAST_LOCATION continuity rule so follow-up
    questions like "how do I get there?" can silently inherit context.
    """

    __tablename__ = "chat_conversations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)
    title = Column(String, nullable=False, default="New Chat")
    last_location = Column(String, nullable=True)
    last_intent = Column(String, nullable=True)
    created_at = Column(String, nullable=False)
    updated_at = Column(String, nullable=False, index=True)
