"""Configuracao dinamica: SSM Parameter Store -> variavel de ambiente -> default.

Ordem de resolucao de cada chave (ex.: "motd"):
  1. SSM Parameter Store em /coffee-shop/motd (cache com TTL de 30s), exceto
     quando COFFEE_CONFIG_MODE=local;
  2. variavel de ambiente COFFEE_MOTD;
  3. default embutido abaixo.

O TTL do cache e o que torna a demo do Parameter Store visivel: mudar o
parametro na console/CLI reflete na API em ate 30 segundos, sem restart.
"""

import os
import time

SSM_PREFIX = "/coffee-shop"

DEFAULTS = {
    "store-name": "coffee-shop do Grupo 8",
    "motd": "Bem-vindo! Pedidos via POST /orders.",
    "discount-pct": "0",
}

_cache: dict[str, tuple[float, str]] = {}


def _ttl() -> float:
    return float(os.environ.get("COFFEE_CONFIG_TTL", "30"))


def _env_name(key: str) -> str:
    return "COFFEE_" + key.upper().replace("-", "_")


def _from_ssm(key: str) -> str | None:
    if os.environ.get("COFFEE_CONFIG_MODE", "auto") == "local":
        return None
    try:
        import boto3

        ssm = boto3.client("ssm")
        resp = ssm.get_parameter(Name=f"{SSM_PREFIX}/{key}")
        return resp["Parameter"]["Value"]
    except Exception:
        # Sem credenciais, sem rede ou parametro inexistente: cai para env/default.
        return None


def get(key: str) -> str:
    if key not in DEFAULTS:
        raise KeyError(f"chave de configuracao desconhecida: {key}")

    now = time.monotonic()
    cached = _cache.get(key)
    if cached and now - cached[0] < _ttl():
        return cached[1]

    value = _from_ssm(key)
    if value is None:
        value = os.environ.get(_env_name(key), DEFAULTS[key])
    _cache[key] = (now, value)
    return value


def get_discount_pct() -> float:
    try:
        pct = float(get("discount-pct"))
    except ValueError:
        return 0.0
    return min(max(pct, 0.0), 100.0)


def clear_cache() -> None:
    _cache.clear()
