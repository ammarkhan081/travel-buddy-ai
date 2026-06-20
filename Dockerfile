FROM python:3.10-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN python -m spacy download en_core_web_sm

COPY backend/ ./backend/
COPY ai/ ./ai/

ENV PYTHONPATH=/app
ENV PORT=7860
ENV DIARY_FILES_DIR=/app/diary_files

RUN useradd -m -u 1000 user \
    && mkdir -p /app/diary_files \
    && chown -R user:user /app

USER user

EXPOSE 7860

CMD ["sh", "-c", "cd /app/backend && alembic -c alembic.ini upgrade head && cd /app && uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-7860}"]
