from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="FastAPI CI/CD Demo", version="1.0.0")

ITEMS: dict[int, dict] = {
    1: {"id": 1, "name": "Widget", "price": 9.99},
    2: {"id": 2, "name": "Gadget", "price": 24.99},
}


class Item(BaseModel):
    name: str
    price: float


@app.get("/")
def root():
    return {"message": "Hello World"}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/items/{item_id}")
def get_item(item_id: int):
    if item_id not in ITEMS:
        raise HTTPException(status_code=404, detail="Item not found")
    return ITEMS[item_id]


@app.post("/items", status_code=201)
def create_item(item: Item):
    new_id = max(ITEMS.keys()) + 1
    ITEMS[new_id] = {"id": new_id, "name": item.name, "price": item.price}
    return ITEMS[new_id]
