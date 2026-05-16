from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.database import Base
from backend.models.alert_cache import AlertCache
from backend.schemas.alerts import AlertRequest, WeatherAlert, NewsAlert
from backend.services import alert_service


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSession()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


@pytest.mark.asyncio
async def test_cache_writes_are_user_scoped_without_duplicates(db):
    req = AlertRequest(user_id="user_a", location="Lahore", alert_types=["weather"])
    weather = WeatherAlert(
        location="Lahore",
        temperature=40.0,
        condition="Clear",
        description="Hot weather",
        risk_level="high",
        recommendations=["Hydrate"],
    )

    with patch.object(alert_service, "fetch_weather", new=AsyncMock(return_value=weather)):
        response = await alert_service.get_alerts_and_cache(db, req)

    assert response.user_id == "user_a"
    rows = db.query(AlertCache).all()
    assert len(rows) == 1
    assert rows[0].user_id == "user_a"
    assert rows[0].type == "weather"


def test_alert_history_filters_by_user(db):
    db.add_all(
        [
            AlertCache(
                user_id="user_a",
                type="weather",
                message="A",
                severity="high",
                location="X",
                created_at="2026-03-09T00:00:00+00:00",
            ),
            AlertCache(
                user_id="user_b",
                type="weather",
                message="B",
                severity="high",
                location="Y",
                created_at="2026-03-09T00:01:00+00:00",
            ),
        ]
    )
    db.commit()

    rows = alert_service.get_alert_history(db, user_id="user_a", limit=10)
    assert len(rows) == 1
    assert rows[0].user_id == "user_a"


@pytest.mark.asyncio
async def test_news_alerts_do_not_crash_when_recommendations_empty(db):
    req = AlertRequest(user_id="user_a", location="Lahore", alert_types=["news"])
    news = NewsAlert(
        location="Lahore",
        headlines=["Local advisory issued"],
        risk_level="low",
        relevant_articles=[],
    )

    with patch.object(alert_service, "fetch_news", new=AsyncMock(return_value=news)):
        response = await alert_service.get_alerts_and_cache(db, req)

    assert response.user_id == "user_a"
    assert response.news is not None
    assert "Review local news updates before departure." in response.recommendations


@pytest.mark.asyncio
async def test_alert_types_none_uses_default_types_without_crash(db):
    req = AlertRequest(user_id="user_a", location="Lahore", alert_types=None)

    with patch.object(alert_service, "fetch_weather", new=AsyncMock(return_value=None)), \
         patch.object(alert_service, "fetch_traffic", new=AsyncMock(return_value=None)), \
         patch.object(alert_service, "fetch_news", new=AsyncMock(return_value=None)):
        response = await alert_service.get_alerts_and_cache(db, req)

    assert response.user_id == "user_a"
    assert response.overall_risk_score == 0.0

