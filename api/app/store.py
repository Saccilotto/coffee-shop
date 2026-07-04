"""Persistencia SQLite + seed + maquina de estados do pedido.

Estado por instancia e deliberado (docs/LIMITACOES.md): cada EC2/instancia do
Beanstalk tem seu proprio arquivo data/coffee.db; em producao seria
DynamoDB/RDS. O status do pedido avanca sozinho por tempo decorrido
(received -> brewing -> ready), para a demo ter movimento sem worker.
"""

import json
import os
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

SEED_PATH = Path(__file__).parent / "seed.json"

STATUS_RECEIVED = "received"
STATUS_BREWING = "brewing"
STATUS_READY = "ready"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    slug        TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    price_cents INTEGER NOT NULL,
    stock       INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS orders (
    id          TEXT PRIMARY KEY,
    created_at  REAL NOT NULL,
    total_cents INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS order_items (
    order_id         TEXT NOT NULL REFERENCES orders(id),
    slug             TEXT NOT NULL,
    name             TEXT NOT NULL,
    quantity         INTEGER NOT NULL,
    unit_price_cents INTEGER NOT NULL
);
"""


class UnknownItemError(Exception):
    def __init__(self, slug: str):
        self.slug = slug
        super().__init__(f"item desconhecido: {slug}")


class OutOfStockError(Exception):
    def __init__(self, slug: str, requested: int, available: int):
        self.slug = slug
        self.requested = requested
        self.available = available
        super().__init__(
            f"estoque insuficiente de {slug}: pedido {requested}, disponivel {available}"
        )


class OrderNotFoundError(Exception):
    pass


def _brew_after() -> float:
    return float(os.environ.get("COFFEE_BREW_AFTER_S", "10"))


def _ready_after() -> float:
    return float(os.environ.get("COFFEE_READY_AFTER_S", "30"))


def order_status(created_at: float, now: float | None = None) -> str:
    elapsed = (now if now is not None else time.time()) - created_at
    if elapsed < _brew_after():
        return STATUS_RECEIVED
    if elapsed < _ready_after():
        return STATUS_BREWING
    return STATUS_READY


class CoffeeStore:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._lock = threading.Lock()
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        with self._lock, self._conn:
            self._conn.executescript(_SCHEMA)
        self._seed_if_empty()

    def _seed_if_empty(self) -> None:
        with self._lock, self._conn:
            count = self._conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
            if count == 0:
                items = json.loads(SEED_PATH.read_text())
                self._conn.executemany(
                    "INSERT INTO items VALUES (:slug, :name, :description, :price_cents, :stock)",
                    items,
                )

    def reseed(self) -> None:
        """Zera itens, pedidos e estoque e recarrega o seed.json."""
        with self._lock, self._conn:
            self._conn.execute("DELETE FROM order_items")
            self._conn.execute("DELETE FROM orders")
            self._conn.execute("DELETE FROM items")
        self._seed_if_empty()

    def ping(self) -> bool:
        self._conn.execute("SELECT 1")
        return True

    def list_items(self) -> list[dict]:
        rows = self._conn.execute("SELECT * FROM items ORDER BY price_cents").fetchall()
        return [dict(r) for r in rows]

    def create_order(self, items: list[tuple[str, int]], discount_pct: float) -> dict:
        """Valida estoque, decrementa e grava o pedido — tudo em uma transacao.

        Recebe [(slug, quantity), ...]; o preco unitario gravado ja tem o
        desconto vigente aplicado (snapshot no momento da compra).
        """
        order_id = uuid.uuid4().hex[:8]
        created_at = time.time()
        factor = 1.0 - discount_pct / 100.0

        with self._lock, self._conn:
            order_rows = []
            total = 0
            for slug, qty in items:
                row = self._conn.execute(
                    "SELECT * FROM items WHERE slug = ?", (slug,)
                ).fetchone()
                if row is None:
                    raise UnknownItemError(slug)
                if row["stock"] < qty:
                    raise OutOfStockError(slug, qty, row["stock"])
                unit_price = round(row["price_cents"] * factor)
                total += unit_price * qty
                order_rows.append((order_id, slug, row["name"], qty, unit_price))
                self._conn.execute(
                    "UPDATE items SET stock = stock - ? WHERE slug = ?", (qty, slug)
                )
            self._conn.execute(
                "INSERT INTO orders VALUES (?, ?, ?)", (order_id, created_at, total)
            )
            self._conn.executemany(
                "INSERT INTO order_items VALUES (?, ?, ?, ?, ?)", order_rows
            )
        return self.get_order(order_id)

    def get_order(self, order_id: str) -> dict:
        row = self._conn.execute(
            "SELECT * FROM orders WHERE id = ?", (order_id,)
        ).fetchone()
        if row is None:
            raise OrderNotFoundError(order_id)
        items = self._conn.execute(
            "SELECT slug, name, quantity, unit_price_cents FROM order_items WHERE order_id = ?",
            (order_id,),
        ).fetchall()
        created_iso = datetime.fromtimestamp(row["created_at"], tz=timezone.utc).isoformat()
        return {
            "id": row["id"],
            "status": order_status(row["created_at"]),
            "created_at": created_iso,
            "total_cents": row["total_cents"],
            "items": [dict(i) for i in items],
        }

    def close(self) -> None:
        self._conn.close()


_store: CoffeeStore | None = None
_store_lock = threading.Lock()


def get_store() -> CoffeeStore:
    global _store
    with _store_lock:
        if _store is None:
            db_path = os.environ.get("COFFEE_DB_PATH", "data/coffee.db")
            _store = CoffeeStore(db_path)
            if os.environ.get("COFFEE_RESEED") == "1":
                _store.reseed()
        return _store


def reset_store() -> None:
    """Fecha e descarta o singleton — usado pelos testes."""
    global _store
    with _store_lock:
        if _store is not None:
            _store.close()
        _store = None
