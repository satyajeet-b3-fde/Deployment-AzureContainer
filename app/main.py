import logging
import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import agent

load_dotenv()  # local development only; .env is never baked into the image

logging.basicConfig(level=logging.INFO)
for noisy in ("azure", "httpx", "httpx2"):
    logging.getLogger(noisy).setLevel(logging.WARNING)
logger = logging.getLogger(__name__)

app = FastAPI(title="Student Support AI Agent", version="1.0.0")


class Question(BaseModel):
    question: str = Field(min_length=2, max_length=2000)


def ask_foundry(question: str) -> str:
    # Indirection so tests can monkeypatch `app.main.ask_foundry`.
    return agent.ask_foundry(question)


@app.get("/")
def home():
    return {
        "application": "Student Support AI Agent",
        "environment": os.getenv("APP_ENV", "local"),
        "version": os.getenv("APP_VERSION", "1.0.0"),
    }


@app.get("/health")
def health():
    return {"status": "healthy", "environment": os.getenv("APP_ENV", "local")}


@app.post("/ask")
def ask_agent(request: Question):
    try:
        answer = ask_foundry(request.question)
        return {
            "question": request.question,
            "answer": answer,
            "environment": os.getenv("APP_ENV", "local"),
        }
    except Exception:
        logger.exception("Foundry agent request failed")
        raise HTTPException(status_code=503, detail="AI agent is temporarily unavailable")
