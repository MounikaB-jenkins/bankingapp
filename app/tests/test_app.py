import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.app import app


def test_health_endpoint():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_root_endpoint():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["service"] == "BankingApp"
