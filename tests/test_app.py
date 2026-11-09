import pytest

from app.main import SECURITY_HEADERS, create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(TESTING=True)
    return app.test_client()


def test_index_returns_service_info(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["service"] == "secure-cicd-pipeline"


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_greet_valid_name(client):
    response = client.get("/api/greet", query_string={"name": "Ada Lovelace"})
    assert response.status_code == 200
    assert response.get_json() == {"message": "Hello, Ada Lovelace!"}


@pytest.mark.parametrize(
    "name",
    ["", "<script>alert(1)</script>", "Robert'); DROP TABLE users;--", "a" * 51, "123"],
)
def test_greet_rejects_bad_input(client, name):
    response = client.get("/api/greet", query_string={"name": name})
    assert response.status_code == 400


def test_unknown_route_returns_json_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert response.get_json() == {"error": "not found"}


@pytest.mark.parametrize("path", ["/", "/health", "/does-not-exist"])
def test_security_headers_on_every_response(client, path):
    response = client.get(path)
    for header, value in SECURITY_HEADERS.items():
        assert response.headers.get(header) == value
    assert "Server" not in response.headers
