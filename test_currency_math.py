"""
Pruebas automatizadas de la lógica de conversión de divisas:
1. Conversión GBP a EUR y GBP a USD.
2. Conversión GBp (peniques) a GBP, EUR y USD.
3. Ausencia de tipo de cambio (debe retornar None y no un valor inventado).
4. Verificación de que nunca se devuelve un valor GBP como EUR o USD sin conversión.
"""

def convert_amount(amount, src, dst, eur_usd_rate=None, gbp_usd_rate=None):
    s = src.strip()
    d = dst.strip().upper()
    val = amount

    # GBp (peniques británicos: 100 GBp = 1 GBP)
    if s in ("GBp", "GBX"):
        val = val / 100.0
        s = "GBP"
    else:
        s = s.upper()

    if s == d:
        return val

    if s == "USD" and d == "EUR":
        if eur_usd_rate is None or eur_usd_rate <= 0:
            return None
        return val / eur_usd_rate

    if s == "EUR" and d == "USD":
        if eur_usd_rate is None or eur_usd_rate <= 0:
            return None
        return val * eur_usd_rate

    if s == "GBP" and d == "USD":
        if gbp_usd_rate is None or gbp_usd_rate <= 0:
            return None
        return val * gbp_usd_rate

    if s == "USD" and d == "GBP":
        if gbp_usd_rate is None or gbp_usd_rate <= 0:
            return None
        return val / gbp_usd_rate

    if s == "GBP" and d == "EUR":
        if gbp_usd_rate is None or gbp_usd_rate <= 0 or eur_usd_rate is None or eur_usd_rate <= 0:
            return None
        return (val * gbp_usd_rate) / eur_usd_rate

    if s == "EUR" and d == "GBP":
        if gbp_usd_rate is None or gbp_usd_rate <= 0 or eur_usd_rate is None or eur_usd_rate <= 0:
            return None
        return (val * eur_usd_rate) / gbp_usd_rate

    return None

def run_tests():
    print("=" * 60)
    print("EJECUTANDO PRUEBAS AUTOMATIZADAS DE CONVERSIÓN DE DIVISAS")
    print("=" * 60)

    EUR_USD = 1.0850
    GBP_USD = 1.2950

    # Test 1: GBP a USD
    # 100 GBP a 1.2950 = 129.50 USD
    res1 = convert_amount(100.0, "GBP", "USD", EUR_USD, GBP_USD)
    print(f"\n[Test 1] 100 GBP -> USD:")
    print(f"  Resultado: {res1} (Esperado: 129.5)")
    assert abs(res1 - 129.5) < 1e-4
    print("  [OK] PASADO")

    # Test 2: GBP a EUR
    # 100 GBP -> (100 * 1.2950) / 1.0850 = 119.3548 EUR
    res2 = convert_amount(100.0, "GBP", "EUR", EUR_USD, GBP_USD)
    expected2 = (100.0 * 1.2950) / 1.0850
    print(f"\n[Test 2] 100 GBP -> EUR:")
    print(f"  Resultado: {res2:.4f} (Esperado: {expected2:.4f})")
    assert abs(res2 - expected2) < 1e-4
    print("  [OK] PASADO")

    # Test 3: GBp a GBP (100 peniques = 1 libra)
    res3 = convert_amount(5500.0, "GBp", "GBP", EUR_USD, GBP_USD)
    print(f"\n[Test 3] 5500 GBp -> GBP:")
    print(f"  Resultado: {res3} (Esperado: 55.0)")
    assert abs(res3 - 55.0) < 1e-4
    print("  [OK] PASADO")

    # Test 4: GBp a EUR
    # 5500 GBp = 55 GBP -> (55 * 1.2950) / 1.0850 = 65.645 EUR
    res4 = convert_amount(5500.0, "GBp", "EUR", EUR_USD, GBP_USD)
    expected4 = (55.0 * 1.2950) / 1.0850
    print(f"\n[Test 4] 5500 GBp -> EUR:")
    print(f"  Resultado: {res4:.4f} (Esperado: {expected4:.4f})")
    assert abs(res4 - expected4) < 1e-4
    print("  [OK] PASADO")

    # Test 5: GBp a USD
    # 5500 GBp = 55 GBP -> 55 * 1.2950 = 71.225 USD
    res5 = convert_amount(5500.0, "GBp", "USD", EUR_USD, GBP_USD)
    expected5 = 55.0 * 1.2950
    print(f"\n[Test 5] 5500 GBp -> USD:")
    print(f"  Resultado: {res5:.4f} (Esperado: {expected5:.4f})")
    assert abs(res5 - expected5) < 1e-4
    print("  [OK] PASADO")

    # Test 6: Ausencia de tipo de cambio EUR/USD -> debe retornar None (NO 1.08 inventado)
    res6 = convert_amount(100.0, "EUR", "USD", eur_usd_rate=None, gbp_usd_rate=GBP_USD)
    print(f"\n[Test 6] Ausencia de EUR/USD (None):")
    print(f"  Resultado: {res6} (Esperado: None)")
    assert res6 is None, f"Esperado None, obtenido {res6}"
    print("  [OK] PASADO: No se genera conversión inventada")

    # Test 7: Ausencia de tipo de cambio GBP/USD al convertir GBP a EUR -> debe retornar None
    res7 = convert_amount(100.0, "GBP", "EUR", eur_usd_rate=EUR_USD, gbp_usd_rate=None)
    print(f"\n[Test 7] Ausencia de GBP/USD al convertir GBP a EUR (None):")
    print(f"  Resultado: {res7} (Esperado: None)")
    assert res7 is None, f"Esperado None, obtenido {res7}"
    print("  [OK] PASADO: No se devuelve GBP como EUR sin convertir")

    # Test 8: EUR a USD y USD a EUR consistencia matemática
    # 100 EUR -> USD -> EUR == 100
    usd_val = convert_amount(100.0, "EUR", "USD", EUR_USD, GBP_USD)
    eur_back = convert_amount(usd_val, "USD", "EUR", EUR_USD, GBP_USD)
    print(f"\n[Test 8] Reversibilidad EUR -> USD -> EUR:")
    print(f"  100 EUR -> {usd_val:.2f} USD -> {eur_back:.2f} EUR")
    assert abs(eur_back - 100.0) < 1e-6
    print("  [OK] PASADO: Sin deriva numérica ni errores de redondeo")

    print("\n" + "=" * 60)
    print("TODAS LAS PRUEBAS DE CONVERSIÓN DE DIVISAS PASARON (8/8)")
    print("=" * 60)

if __name__ == "__main__":
    run_tests()
