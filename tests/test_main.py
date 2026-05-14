import pytest
from fastapi.testclient import TestClient

from app.main import app, ITEMS

client = TestClient(app)


@pytest.fixture(autouse=True)
def reset_items():
    """Reset ITEMS to original state before each test."""
    original = {
        1: {"id": 1, "name": "Widget", "price": 9.99},
        2: {"id": 2, "name": "Gadget", "price": 24.99},
    }
    ITEMS.clear()
    ITEMS.update(original)
    yield


class TestRootEndpoint:
    def test_root_returns_hello_world(self):
        response = client.get("/")
        assert response.status_code == 200
        assert response.json() == {"message": "Hello World"}


class TestHealthEndpoint:
    def test_health_returns_ok(self):
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}


class TestGetItem:
    def test_get_existing_item(self):
        response = client.get("/items/1")
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == 1
        assert data["name"] == "Widget"
        assert data["price"] == 9.99

    def test_get_second_item(self):
        response = client.get("/items/2")
        assert response.status_code == 200
        assert response.json()["name"] == "Gadget"

    def test_get_nonexistent_item_returns_404(self):
        response = client.get("/items/999")
        assert response.status_code == 404
        assert response.json()["detail"] == "Item not found"


class TestCreateItem:
    def test_create_item_returns_201(self):
        payload = {"name": "Doohickey", "price": 4.99}
        response = client.post("/items", json=payload)
        assert response.status_code == 201

    def test_create_item_returns_correct_data(self):
        payload = {"name": "Thingamajig", "price": 14.50}
        response = client.post("/items", json=payload)
        data = response.json()
        assert data["name"] == "Thingamajig"
        assert data["price"] == 14.50
        assert "id" in data

    def test_create_item_increments_id(self):
        payload = {"name": "NewItem", "price": 1.00}
        response = client.post("/items", json=payload)
        assert response.json()["id"] == 3

    def test_create_item_missing_name_returns_422(self):
        response = client.post("/items", json={"price": 5.00})
        assert response.status_code == 422

    def test_create_item_missing_price_returns_422(self):
        response = client.post("/items", json={"name": "Oops"})
        assert response.status_code == 422
