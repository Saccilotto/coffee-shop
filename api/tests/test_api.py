import time


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["platform"] == "local"
    assert body["version"]


def test_health_forced_unhealthy(client, monkeypatch):
    monkeypatch.setenv("COFFEE_FORCE_UNHEALTHY", "1")
    r = client.get("/health")
    assert r.status_code == 503
    assert r.json()["status"] == "unhealthy"


def test_menu_lists_seeded_items(client):
    r = client.get("/menu")
    assert r.status_code == 200
    body = r.json()
    slugs = {i["slug"] for i in body["items"]}
    assert {"espresso", "duplo", "coado", "latte", "cold-brew", "descafeinado-404"} <= slugs
    espresso = next(i for i in body["items"] if i["slug"] == "espresso")
    assert espresso["price_cents"] == 700
    assert espresso["available"] is True
    assert body["discount_pct"] == 0


def test_menu_applies_discount_from_config(client, monkeypatch):
    monkeypatch.setenv("COFFEE_DISCOUNT_PCT", "10")
    r = client.get("/menu")
    espresso = next(i for i in r.json()["items"] if i["slug"] == "espresso")
    assert espresso["price_cents"] == 630
    assert espresso["list_price_cents"] == 700
    assert r.json()["discount_pct"] == 10


def test_inventory_shows_stock(client):
    r = client.get("/inventory")
    assert r.status_code == 200
    stock = {i["slug"]: i["stock"] for i in r.json()}
    assert stock["espresso"] == 50
    assert stock["descafeinado-404"] == 20


def test_create_order_decrements_stock_and_totals(client):
    r = client.post(
        "/orders",
        json={"items": [{"slug": "espresso", "quantity": 2}, {"slug": "latte", "quantity": 1}]},
    )
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "received"
    assert body["total_cents"] == 2 * 700 + 1500
    assert len(body["items"]) == 2

    stock = {i["slug"]: i["stock"] for i in client.get("/inventory").json()}
    assert stock["espresso"] == 48
    assert stock["latte"] == 29


def test_order_snapshots_discounted_price(client, monkeypatch):
    monkeypatch.setenv("COFFEE_DISCOUNT_PCT", "50")
    r = client.post("/orders", json={"items": [{"slug": "coado", "quantity": 1}]})
    assert r.status_code == 201
    assert r.json()["total_cents"] == 450


def test_order_status_advances_over_time(client):
    order_id = client.post(
        "/orders", json={"items": [{"slug": "espresso", "quantity": 1}]}
    ).json()["id"]

    assert client.get(f"/orders/{order_id}").json()["status"] == "received"
    time.sleep(0.2)
    assert client.get(f"/orders/{order_id}").json()["status"] == "brewing"
    time.sleep(0.2)
    assert client.get(f"/orders/{order_id}").json()["status"] == "ready"


def test_order_unknown_item_is_404(client):
    r = client.post("/orders", json={"items": [{"slug": "chimarrao", "quantity": 1}]})
    assert r.status_code == 404


def test_order_out_of_stock_is_409_and_rolls_back(client):
    r = client.post(
        "/orders",
        json={"items": [{"slug": "espresso", "quantity": 1}, {"slug": "cold-brew", "quantity": 26}]},
    )
    assert r.status_code == 409

    # A transacao inteira reverte: nem o espresso valido foi decrementado.
    stock = {i["slug"]: i["stock"] for i in client.get("/inventory").json()}
    assert stock["espresso"] == 50
    assert stock["cold-brew"] == 25


def test_get_unknown_order_is_404(client):
    assert client.get("/orders/deadbeef").status_code == 404


def test_order_rejects_empty_items(client):
    assert client.post("/orders", json={"items": []}).status_code == 422
