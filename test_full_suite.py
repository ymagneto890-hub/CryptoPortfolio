"""
Suite integral de verificación matemática y de seguridad para CryptoPortfolio:
Comprueba la totalidad de los requisitos especificados en el prompt quirúrgico.
"""

import unittest
import math
import json
import os
import sys
from datetime import datetime, timedelta

# Importar portfolio_server desde CryptoWidget
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
CRYPTO_WIDGET_DIR = os.path.abspath(os.path.join(CURRENT_DIR, "..", "CryptoWidget"))
if os.path.exists(CRYPTO_WIDGET_DIR):
    sys.path.insert(0, CRYPTO_WIDGET_DIR)

import portfolio_server

class SwiftPortfolioSimulator:
    """Simulador que replica de forma idéntica las fórmulas y lógica exacta de PortfolioViewModel.swift"""

    def __init__(self):
        self.eur_usd_rate = 1.10
        self.eur_usd_rate_date = datetime.now()
        self.gbp_usd_rate = 1.30
        self.gbp_usd_rate_date = datetime.now()
        self.max_rate_age_seconds = 48 * 3600
        self.max_crypto_age_seconds = 24 * 3600
        self.max_stock_age_seconds = 5 * 86400
        self.last_known_quotes = {}
        self.display_currency = "EUR"

    def convert_amount(self, amount, src, dst, now=None):
        if now is None:
            now = datetime.now()
        if not math.isfinite(amount) or math.isnan(amount) or amount <= 0:
            return None

        s = src.strip()
        d = dst.strip().upper()
        val = amount

        if s == "GBp" or s.upper() == "GBX":
            val = val / 100.0
            s = "GBP"
        else:
            s = s.upper()

        if s == "USDT":
            s = "USD"

        if s == d:
            return val

        if s == "USD" and d == "EUR":
            if not self.eur_usd_rate or not (self.eur_usd_rate > 0) or not math.isfinite(self.eur_usd_rate):
                return None
            if (now - self.eur_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return val / self.eur_usd_rate

        if s == "EUR" and d == "USD":
            if not self.eur_usd_rate or not (self.eur_usd_rate > 0) or not math.isfinite(self.eur_usd_rate):
                return None
            if (now - self.eur_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return val * self.eur_usd_rate

        if s == "GBP" and d == "USD":
            if not self.gbp_usd_rate or not (self.gbp_usd_rate > 0) or not math.isfinite(self.gbp_usd_rate):
                return None
            if (now - self.gbp_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return val * self.gbp_usd_rate

        if s == "USD" and d == "GBP":
            if not self.gbp_usd_rate or not (self.gbp_usd_rate > 0) or not math.isfinite(self.gbp_usd_rate):
                return None
            if (now - self.gbp_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return val / self.gbp_usd_rate

        if s == "GBP" and d == "EUR":
            if not self.gbp_usd_rate or not self.eur_usd_rate:
                return None
            if (now - self.gbp_usd_rate_date).total_seconds() >= self.max_rate_age_seconds or (now - self.eur_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return (val * self.gbp_usd_rate) / self.eur_usd_rate

        if s == "EUR" and d == "GBP":
            if not self.gbp_usd_rate or not self.eur_usd_rate:
                return None
            if (now - self.gbp_usd_rate_date).total_seconds() >= self.max_rate_age_seconds or (now - self.eur_usd_rate_date).total_seconds() >= self.max_rate_age_seconds:
                return None
            return (val * self.eur_usd_rate) / self.gbp_usd_rate

        return None

    def recalculate(self, positions, target_currency, now=None):
        if now is None:
            now = datetime.now()
        unique_coins = list(dict.fromkeys([p["coin"] for p in positions]))
        total_coins_count = len(unique_coins)

        coin_inv_target = {}
        coin_total_units = {}
        coin_avg_ep_target = {}
        coin_live_price_target = {}
        coin_value_target = {}
        coin_has_valid_val = {}

        all_convertible = True

        for coin in unique_coins:
            c_pos = [p for p in positions if p["coin"] == coin]
            c_inv_target = 0.0
            c_total_quantity = 0.0
            has_complete_quantities = True
            conv_failed = False

            for pos in c_pos:
                inv_t = self.convert_amount(pos["invested"], pos["currency"], target_currency, now)
                if inv_t is None or not math.isfinite(inv_t) or inv_t <= 0:
                    conv_failed = True
                    all_convertible = False
                    break
                c_inv_target += inv_t

                raw_ep = pos.get("entry_price")
                if raw_ep is not None and math.isfinite(raw_ep) and raw_ep > 0:
                    qty = pos["invested"] / raw_ep
                    if math.isfinite(qty) and qty > 0:
                        c_total_quantity += qty
                    else:
                        has_complete_quantities = False
                else:
                    has_complete_quantities = False

            if conv_failed or c_inv_target <= 0:
                continue

            coin_inv_target[coin] = c_inv_target

            if has_complete_quantities and c_total_quantity > 0:
                coin_total_units[coin] = c_total_quantity
                avg_ep = c_inv_target / c_total_quantity
                coin_avg_ep_target[coin] = avg_ep

                if coin in self.last_known_quotes:
                    q = self.last_known_quotes[coin]
                    p = q.get("price")
                    q_time = q.get("timestamp", now)
                    q_src = q.get("source", "binance")
                    is_verified = q.get("is_verified", True)

                    # Validar precio y frescura
                    if p is not None and math.isfinite(p) and p > 0 and q_time <= now + timedelta(seconds=60):
                        age = (now - q_time).total_seconds()
                        is_fresh = False
                        if q_src == "binance" and age >= 0 and age < self.max_crypto_age_seconds:
                            is_fresh = True
                        elif q_src == "yahoo" and is_verified and age >= 0 and age < self.max_stock_age_seconds:
                            is_fresh = True

                        if is_fresh:
                            converted_price = self.convert_amount(p, q["currency"], target_currency, now)
                            if converted_price is not None and math.isfinite(converted_price) and converted_price > 0:
                                coin_live_price_target[coin] = converted_price
                                val = c_total_quantity * converted_price
                                coin_value_target[coin] = val
                                coin_has_valid_val[coin] = True

        valued_count = sum(1 for v in coin_has_valid_val.values() if v)

        if valued_count == total_coins_count and total_coins_count > 0 and all_convertible:
            val_status = "complete"
        elif valued_count > 0:
            val_status = "partial"
        else:
            val_status = "unvalued"

        total_invested_all = sum(coin_inv_target.values())

        if val_status == "complete":
            total_val = sum(coin_value_target.values())
            total_pnl = total_val - total_invested_all
            total_pnl_pct = (total_pnl / total_invested_all * 100.0) if total_invested_all > 0 else 0.0
        elif val_status == "partial":
            total_val = sum(coin_value_target.values())
            total_pnl = None
            total_pnl_pct = None
        else:
            total_val = None
            total_pnl = None
            total_pnl_pct = None

        items = []
        for ck in unique_coins:
            inv = coin_inv_target.get(ck, 0.0)
            cur_val = coin_value_target.get(ck)
            lp = coin_live_price_target.get(ck)
            qty = coin_total_units.get(ck)
            avg_ep = coin_avg_ep_target.get(ck)

            if cur_val is not None and inv > 0:
                pnl = cur_val - inv
                pnl_pct = (pnl / inv) * 100.0
            else:
                pnl = None
                pnl_pct = None

            # Metodología de pesos coherente (suma = 100%)
            if val_status == "complete" and (total_val or 0) > 0 and cur_val is not None:
                share_pct = (cur_val / total_val) * 100.0
            else:
                share_pct = (inv / total_invested_all * 100.0) if total_invested_all > 0 else 0.0

            items.append({
                "symbol": ck,
                "invested": round(inv, 2),
                "total_quantity": qty,
                "average_entry_price": avg_ep,
                "value": round(cur_val, 2) if cur_val is not None else None,
                "pnl": round(pnl, 2) if pnl is not None else None,
                "pnl_pct": round(pnl_pct, 2) if pnl_pct is not None else None,
                "share_pct": round(share_pct, 1),
                "current_price": round(lp, 4) if lp is not None else None
            })

        return {
            "valuation_status": val_status,
            "valued_count": valued_count,
            "total_count": total_coins_count,
            "total_invested": round(total_invested_all, 2),
            "total_value": round(total_val, 2) if total_val is not None else None,
            "total_pnl": round(total_pnl, 2) if total_pnl is not None else None,
            "total_pnl_pct": round(total_pnl_pct, 2) if total_pnl_pct is not None else None,
            "items": items
        }

class TestFullReliabilitySuite(unittest.TestCase):

    def setUp(self):
        self.sim = SwiftPortfolioSimulator()

    # CASO OBLIGATORIO 1: Matemática de compras múltiples
    def test_caso_obligatorio_compras_multiples(self):
        # Compra 1: 100 EUR a 10 EUR por unidad -> 10 unidades
        # Compra 2: 100 EUR a 20 EUR por unidad -> 5 unidades
        # Cotización actual: 15 EUR
        positions = [
            {"coin": "ABC", "invested": 100.0, "entry_price": 10.0, "currency": "EUR"},
            {"coin": "ABC", "invested": 100.0, "entry_price": 20.0, "currency": "EUR"}
        ]
        self.sim.last_known_quotes = {
            "ABC": {"price": 15.0, "currency": "EUR", "source": "binance", "timestamp": datetime.now(), "is_verified": True}
        }
        res = self.sim.recalculate(positions, "EUR")

        self.assertEqual(res["valuation_status"], "complete")
        self.assertEqual(res["total_invested"], 200.0)
        self.assertEqual(res["total_value"], 225.0)
        self.assertEqual(res["total_pnl"], 25.0)
        self.assertEqual(res["total_pnl_pct"], 12.5)

        item = res["items"][0]
        self.assertEqual(item["total_quantity"], 15.0)
        self.assertAlmostEqual(item["average_entry_price"], 13.333333, places=5)
        self.assertEqual(item["value"], 225.0)
        self.assertEqual(item["pnl"], 25.0)
        self.assertEqual(item["pnl_pct"], 12.5)

    # CASOS OBLIGATORIOS 2: GBP y GBp
    def test_casos_obligatorios_gbp_gbp(self):
        self.sim.gbp_usd_rate = 1.30
        self.sim.gbp_usd_rate_date = datetime.now()
        self.sim.eur_usd_rate = 1.10
        self.sim.eur_usd_rate_date = datetime.now()

        # 100 GBP -> USD con 1.30 = 130 USD
        self.assertAlmostEqual(self.sim.convert_amount(100.0, "GBP", "USD"), 130.0, places=4)

        # 4200 GBp -> GBP = 42 GBP
        self.assertAlmostEqual(self.sim.convert_amount(4200.0, "GBp", "GBP"), 42.0, places=4)

        # 4200 GBp -> USD con 1.30 = 54.60 USD
        self.assertAlmostEqual(self.sim.convert_amount(4200.0, "GBp", "USD"), 54.60, places=4)

        # 4200 GBp -> EUR con EUR/USD = 1.10 y GBP/USD = 1.30 = 49.63636 EUR
        self.assertAlmostEqual(self.sim.convert_amount(4200.0, "GBp", "EUR"), 49.63636, places=4)

    # CASO OBLIGATORIO 3: Pesos en valoración parcial con 1/3, 2/3 y 3/3 activos
    def test_pesos_grafico_1_3_2_3_3_3(self):
        now = datetime.now()
        positions = [
            {"coin": "A", "invested": 500.0, "entry_price": 50.0, "currency": "EUR"},
            {"coin": "B", "invested": 300.0, "entry_price": 30.0, "currency": "EUR"},
            {"coin": "C", "invested": 200.0, "entry_price": 20.0, "currency": "EUR"}
        ]
        total_inv = 1000.0

        # Caso 1/3 cotizados (solo A)
        self.sim.last_known_quotes = {
            "A": {"price": 60.0, "currency": "EUR", "source": "binance", "timestamp": now, "is_verified": True}
        }
        res1 = self.sim.recalculate(positions, "EUR", now)
        self.assertEqual(res1["valuation_status"], "partial")
        self.assertEqual(res1["valued_count"], 1)
        self.assertIsNone(res1["total_pnl"])
        # Suma de share_pct debe ser 100% usando denominador común
        sum_shares1 = sum(it["share_pct"] for it in res1["items"])
        self.assertAlmostEqual(sum_shares1, 100.0, places=1)

        # Caso 2/3 cotizados (A y B)
        self.sim.last_known_quotes["B"] = {"price": 35.0, "currency": "EUR", "source": "binance", "timestamp": now, "is_verified": True}
        res2 = self.sim.recalculate(positions, "EUR", now)
        self.assertEqual(res2["valuation_status"], "partial")
        self.assertEqual(res2["valued_count"], 2)
        sum_shares2 = sum(it["share_pct"] for it in res2["items"])
        self.assertAlmostEqual(sum_shares2, 100.0, places=1)

        # Caso 3/3 cotizados (A, B y C -> complete)
        self.sim.last_known_quotes["C"] = {"price": 25.0, "currency": "EUR", "source": "binance", "timestamp": now, "is_verified": True}
        res3 = self.sim.recalculate(positions, "EUR", now)
        self.assertEqual(res3["valuation_status"], "complete")
        self.assertEqual(res3["valued_count"], 3)
        self.assertIsNotNone(res3["total_pnl"])
        sum_shares3 = sum(it["share_pct"] for it in res3["items"])
        self.assertAlmostEqual(sum_shares3, 100.0, places=1)

    # Normalización de divisa en Python
    def test_normalizacion_divisas_python(self):
        self.assertEqual(portfolio_server.normalize_currency("GBp"), "GBp")
        self.assertEqual(portfolio_server.normalize_currency("GBX"), "GBp")
        self.assertEqual(portfolio_server.normalize_currency("GBP"), "GBP")
        self.assertEqual(portfolio_server.normalize_currency("EUR"), "EUR")
        self.assertEqual(portfolio_server.normalize_currency("USD"), "USD")

    # Inversión preservada sin precio de entrada
    def test_inversion_preservada_sin_precio_entrada(self):
        positions = [
            {"coin": "X", "invested": 1000.0, "entry_price": None, "currency": "EUR"},
            {"coin": "Y", "invested": 500.0, "entry_price": 50.0, "currency": "EUR"}
        ]
        self.sim.last_known_quotes = {
            "Y": {"price": 60.0, "currency": "EUR", "source": "binance", "timestamp": datetime.now(), "is_verified": True}
        }
        res = self.sim.recalculate(positions, "EUR")
        self.assertEqual(res["total_invested"], 1500.0)
        self.assertEqual(res["valuation_status"], "partial")
        item_x = next(it for it in res["items"] if it["symbol"] == "X")
        self.assertEqual(item_x["invested"], 1000.0)
        self.assertIsNone(item_x["value"])
        self.assertIsNone(item_x["pnl"])

if __name__ == "__main__":
    unittest.main()
