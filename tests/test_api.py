from fastapi.testclient import TestClient

from app import main
from app.main import app

client = TestClient(app)


def test_home():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["application"] == "Student Support AI Agent"


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_ask_agent(monkeypatch):
    monkeypatch.setattr(
        main, "ask_foundry", lambda question: "RAG means Retrieval Augmented Generation."
    )
    response = client.post("/ask", json={"question": "What is RAG?"})
    assert response.status_code == 200
    assert "RAG" in response.json()["answer"]


def test_ask_agent_failure_returns_503(monkeypatch):
    def boom(question):
        raise RuntimeError("foundry down")

    monkeypatch.setattr(main, "ask_foundry", boom)
    response = client.post("/ask", json={"question": "What is RAG?"})
    assert response.status_code == 503


def test_invalid_question():
    response = client.post("/ask", json={"question": "?"})
    assert response.status_code == 422
