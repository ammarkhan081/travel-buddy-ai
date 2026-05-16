from sqlalchemy import Column, Integer, String, Text
try:
    from ..database import Base
except ImportError:
    from database import Base


class RagEmbedding(Base):
    __tablename__ = "rag_embeddings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)
    source_type = Column(String, nullable=False)  # expense|reminder|diary
    source_id = Column(Integer, nullable=False)
    chunk_index = Column(Integer, nullable=False, default=0)
    chunk_hash = Column(String, nullable=False, index=True)
    chunk_text = Column(Text, nullable=False)
    embedding_json = Column(Text, nullable=False)
    updated_at = Column(String, nullable=False)
