"""
Test suite de verificación en Python para portfolio_server.py:
Verifica:
1. Token ausente (401)
2. Token incorrecto (401)
3. Token correcto (200)
4. Normalización GBp (peniques británicos)
5. Normalización GBP (libras esterlinas)
6. Posición con inversión válida y precio de entrada inválido
7. Coherencia entre items y positions
"""

import unittest
import json
import os
import sys
import threading
import time
import urllib.request
import urllib.error

# Configurar ruta relativa portátil
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Si portfolio_server.py está en CryptoWidget
CRYPTO_WIDGET_DIR = os.path.abspath(os.path.join(CURRENT_DIR, "..", "CryptoWidget"))
if os.path.exists(CRYPTO_WIDGET_DIR):
    sys.path.insert(0, CRYPTO_WIDGET_DIR)

import portfolio_server

class TestPortfolioServer(unittest.TestCase):

    def test_01_normalizacion_gbp(self):
        self.assertEqual(portfolio_server.normalize_currency("GBp"), "GBp")
        self.assertEqual(portfolio_server.normalize_currency("gbx"), "GBp")
        self.assertEqual(portfolio_server.normalize_currency("GBX"), "GBp")

    def test_02_normalizacion_gbp_pounds(self):
        self.assertEqual(portfolio_server.normalize_currency("GBP"), "GBP")
        self.assertEqual(portfolio_server.normalize_currency("gbp"), "GBP")

    def test_03_normalizacion_otras(self):
        self.assertEqual(portfolio_server.normalize_currency("EUR"), "EUR")
        self.assertEqual(portfolio_server.normalize_currency("usd"), "USD")
        self.assertEqual(portfolio_server.normalize_currency(None), "EUR")

    def test_04_posicion_con_inversion_valida_y_ep_invalido(self):
        # Simular lectura con posición sin precio de entrada usando archivo temporal aislado
        dummy_config = {
            "currency": "EUR",
            "portfolio": [
                {"coin": "BTC", "invested": 1000.0, "entry_price": 50000.0, "currency": "EUR"},
                {"coin": "ETH", "invested": 500.0, "entry_price": 0.0, "currency": "EUR"},
                {"coin": "ADA", "invested": 300.0, "entry_price": None, "currency": "EUR"}
            ]
        }
        temp_config_path = os.path.join(CURRENT_DIR, "test_temp_config.json")
        with open(temp_config_path, "w", encoding="utf-8") as f:
            json.dump(dummy_config, f)

        orig_config_path = portfolio_server.CONFIG_PATH
        portfolio_server.CONFIG_PATH = temp_config_path
        try:
            data = portfolio_server.load_portfolio_data()
            self.assertIsNotNone(data)
            # La inversión total debe incluir las 3 posiciones: 1000 + 500 + 300 = 1800 EUR!
            self.assertEqual(data["total_invested"], 1800.0)
            self.assertEqual(len(data["positions"]), 3)
            # Verificar que ETH y ADA tienen entry_price = None, pero su inversión está preservada
            eth_pos = next(p for p in data["positions"] if p["coin"] == "ETH")
            self.assertEqual(eth_pos["invested"], 500.0)
            self.assertIsNone(eth_pos["entry_price"])

            ada_pos = next(p for p in data["positions"] if p["coin"] == "ADA")
            self.assertEqual(ada_pos["invested"], 300.0)
            self.assertIsNone(ada_pos["entry_price"])
        finally:
            portfolio_server.CONFIG_PATH = orig_config_path
            if os.path.exists(temp_config_path):
                os.remove(temp_config_path)

    def test_05_coherencia_items_positions(self):
        data = portfolio_server.load_portfolio_data()
        self.assertIsNotNone(data)
        sum_items_inv = sum(it["invested"] for it in data["items"])
        sum_positions_inv = sum(pos["invested"] for pos in data["positions"])
        self.assertAlmostEqual(sum_items_inv, sum_positions_inv, places=2)
        self.assertAlmostEqual(data["total_invested"], sum_items_inv, places=2)

    def test_06_autenticacion_http_servidor(self):
        # Iniciar servidor en puerto de prueba
        test_port = 8789
        server = portfolio_server.start_server_in_thread(port=test_port)
        self.assertIsNotNone(server)
        time.sleep(0.5)

        try:
            url = f"http://127.0.0.1:{test_port}/api/portfolio"
            expected_token = portfolio_server.get_auth_token()

            # A) Token ausente -> 401
            req_no_token = urllib.request.Request(url)
            try:
                urllib.request.urlopen(req_no_token)
                self.fail("Debió fallar con 401 por falta de token")
            except urllib.error.HTTPError as e:
                self.assertEqual(e.code, 401)

            # B) Token incorrecto -> 401
            req_wrong = urllib.request.Request(url)
            req_wrong.add_header("Authorization", "Bearer token_incorrecto_123")
            try:
                urllib.request.urlopen(req_wrong)
                self.fail("Debió fallar con 401 por token incorrecto")
            except urllib.error.HTTPError as e:
                self.assertEqual(e.code, 401)

            # C) Token correcto -> 200
            req_correct = urllib.request.Request(url)
            req_correct.add_header("Authorization", f"Bearer {expected_token}")
            with urllib.request.urlopen(req_correct) as resp:
                self.assertEqual(resp.status, 200)
                body = json.loads(resp.read().decode("utf-8"))
                self.assertIn("items", body)
                self.assertIn("positions", body)
                # Verificar header no-store
                cache_control = resp.headers.get("Cache-Control", "")
                self.assertIn("no-store", cache_control)

        finally:
            server.shutdown()

if __name__ == "__main__":
    unittest.main()
