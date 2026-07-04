"""coffee-api: pedidos de cafe. Mesma base roda no Beanstalk (PaaS) e na EC2 (IaaS)."""

import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from . import __version__, config, models, store

app = FastAPI(
    title="coffee-shop API",
    version=__version__,
    description="API de pedidos de cafe — Trabalho 2 AWS DevOps, Grupo 8.",
)


@app.get("/health", response_model=models.HealthOut)
def health():
    # COFFEE_FORCE_UNHEALTHY alimenta a demo de rollback do CodeDeploy: a
    # revisao "quebrada" instala um env file com essa flag e o hook
    # ValidateService passa a receber 503.
    if os.environ.get("COFFEE_FORCE_UNHEALTHY") == "1":
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "reason": "COFFEE_FORCE_UNHEALTHY=1"},
        )
    store.get_store().ping()
    return models.HealthOut(
        status="ok",
        version=__version__,
        platform=os.environ.get("COFFEE_PLATFORM", "local"),
        store_name=config.get("store-name"),
        motd=config.get("motd"),
    )


@app.get("/menu", response_model=models.MenuOut)
def menu():
    discount = config.get_discount_pct()
    factor = 1.0 - discount / 100.0
    items = [
        models.MenuItem(
            slug=i["slug"],
            name=i["name"],
            description=i["description"],
            price_cents=round(i["price_cents"] * factor),
            list_price_cents=i["price_cents"],
            available=i["stock"] > 0,
        )
        for i in store.get_store().list_items()
    ]
    return models.MenuOut(
        store_name=config.get("store-name"),
        motd=config.get("motd"),
        discount_pct=discount,
        items=items,
    )


@app.get("/inventory", response_model=list[models.InventoryItem])
def inventory():
    return [
        models.InventoryItem(slug=i["slug"], name=i["name"], stock=i["stock"])
        for i in store.get_store().list_items()
    ]


@app.post("/orders", response_model=models.OrderOut, status_code=201)
def create_order(order: models.OrderIn):
    try:
        created = store.get_store().create_order(
            [(i.slug, i.quantity) for i in order.items],
            discount_pct=config.get_discount_pct(),
        )
    except store.UnknownItemError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except store.OutOfStockError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return created


@app.get("/orders/{order_id}", response_model=models.OrderOut)
def get_order(order_id: str):
    try:
        return store.get_store().get_order(order_id)
    except store.OrderNotFoundError:
        raise HTTPException(status_code=404, detail=f"pedido nao encontrado: {order_id}")
