import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from unittest.mock import patch, MagicMock
from app.app import app


def test_health_endpoint_success():
    """
    Given a successful database connection,
    When the /health endpoint is called,
    Then it should return a 200 OK status.
    """
    # Mock the get_db_connection function to simulate success
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value.__enter__.return_value = mock_cursor

    with patch('app.app.get_db_connection', return_value=mock_conn):
        client = app.test_client()
        response = client.get("/health")
        assert response.status_code == 200
        assert response.get_json()["database"] == "connected"


def test_health_endpoint_db_failure():
    """
    Given a failed database connection,
    When the /health endpoint is called,
    Then it should return a 503 Service Unavailable status.
    """
    # Mock the get_db_connection function to simulate failure (returns None)
    with patch('app.app.get_db_connection', return_value=None):
        client = app.test_client()
        response = client.get("/health")
        assert response.status_code == 503
        assert response.get_json()["reason"] == "Database connection could not be established"

def test_root_endpoint():
    """When not logged in, the root should redirect to the login page."""
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 302
    assert "/login" in response.headers["Location"]
