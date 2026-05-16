from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.database import Base
from backend.services import chat_service


def test_retrieval_path_does_not_sync_embeddings_when_cache_empty(monkeypatch):
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = Session()
    try:
        def _fail_sync(*args, **kwargs):
            raise AssertionError("sync should not run in retrieval path")

        monkeypatch.setattr(chat_service, "_sync_embedding_cache", _fail_sync)

        context = chat_service._retrieve_relevant_context(  # pylint: disable=protected-access
            query="How much did I spend?",
            db=db,
            user_id="user_a",
            client=object(),
        )
        assert context == "NO_CONTEXT"
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)

