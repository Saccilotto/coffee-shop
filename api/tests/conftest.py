"""Modo local forcado ANTES de importar a app: sem AWS, DB temporario,
status de pedido acelerado para os testes verem as transicoes."""

import os

os.environ["COFFEE_CONFIG_MODE"] = "local"
os.environ["COFFEE_CONFIG_TTL"] = "0"
os.environ["COFFEE_BREW_AFTER_S"] = "0.15"
os.environ["COFFEE_READY_AFTER_S"] = "0.3"

import pytest
from fastapi.testclient import TestClient

from app import store
from app.main import app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("COFFEE_DB_PATH", str(tmp_path / "coffee.db"))
    store.reset_store()
    with TestClient(app) as c:
        yield c
    store.reset_store()
