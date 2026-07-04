"""Modelos Pydantic da coffee-api."""

from pydantic import BaseModel, Field


class MenuItem(BaseModel):
    slug: str
    name: str
    description: str
    price_cents: int
    list_price_cents: int
    available: bool


class MenuOut(BaseModel):
    store_name: str
    motd: str
    discount_pct: float
    items: list[MenuItem]


class InventoryItem(BaseModel):
    slug: str
    name: str
    stock: int


class OrderItemIn(BaseModel):
    slug: str
    quantity: int = Field(ge=1, le=50)


class OrderIn(BaseModel):
    items: list[OrderItemIn] = Field(min_length=1)


class OrderItemOut(BaseModel):
    slug: str
    name: str
    quantity: int
    unit_price_cents: int


class OrderOut(BaseModel):
    id: str
    status: str
    created_at: str
    total_cents: int
    items: list[OrderItemOut]


class HealthOut(BaseModel):
    status: str
    version: str
    platform: str
    store_name: str
    motd: str
