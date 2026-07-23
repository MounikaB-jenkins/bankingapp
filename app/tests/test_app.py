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
