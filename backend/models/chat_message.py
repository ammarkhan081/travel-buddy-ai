from sqlalchemy import Column, Integer, String, Text
try:
    from ..database import Base
except ImportError:
    from database import Base


class ChatMessage(Base):
    """A single user or assistant message inside a ChatConversation.

    `user_id` is denormalised onto the row so ownership checks remain a single
    indexed lookup without a JOIN. `role` is one of: user | assistant.
    """

    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    conversation_id = Column(Integer, nullable=False, index=True)
    user_id = Column(String, nullable=False, index=True)
    role = Column(String, nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(String, nullable=False)
