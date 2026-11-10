import XCTest
@testable import AppCore

final class AppCoreTests: XCTestCase {

    var vm: PortfolioViewModel!

    override func setUp() {
        super.setUp()
        vm = PortfolioViewModel(startAutomatically: false)
        vm.stopForegroundUpdates() // Aislar de temporizadores asíncronos para pruebas unitarias
    }

    override func tearDown() {
        vm.stopForegroundUpdates()
        vm = nil
        super.tearDown()
    }

    // 1. Sin cotizaciones iniciales
    func test01_sinCotizacionesIniciales() {
        let payload = PortfolioPayload(
            currency: "EUR",
            total_invested: 1000.0,
            valuation_status: .unvalued,
            positions: [
                RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 1000.0, entry_price: 50000.0, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        vm.lastKnownQuotes = [:]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        XCTAssertEqual(vm.portfolio?.valuation_status, .unvalued)
        XCTAssertNil(vm.portfolio?.total_value)
        XCTAssertNil(vm.portfolio?.total_pnl)
        XCTAssertNil(vm.portfolio?.total_pnl_pct)
        XCTAssertEqual(vm.portfolio?.items.first?.current_price, nil)
        XCTAssertEqual(vm.portfolio?.items.first?.value, nil)
    }

    // 2. Valoración completa
    func test02_valoracionCompleta() {
        let now = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = now
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 1000.0, entry_price: 50000.0, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        vm.lastKnownQuotes = [
            "BTC": MarketQuote(symbol: "BTC", price: 60000.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        ]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        XCTAssertEqual(vm.portfolio?.valuation_status, .complete)
        XCTAssertEqual(vm.portfolio?.total_invested, 1000.0)
        XCTAssertEqual(vm.portfolio?.total_value, 1200.0)
        XCTAssertEqual(vm.portfolio?.total_pnl, 200.0)
        XCTAssertEqual(vm.portfolio?.total_pnl_pct, 20.0)
    }

    // 3. Valoración parcial
    func test03_valoracionParcial() {
        let now = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = now
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 1000.0, entry_price: 50000.0, currency: "EUR"),
                RawPosition(coin: "ETH", name: "Ethereum", icon: "Ξ", color: "#9B7DFF", source: "binance", invested: 500.0, entry_price: 2500.0, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        // Solo BTC tiene cotización, ETH no tiene
        vm.lastKnownQuotes = [
            "BTC": MarketQuote(symbol: "BTC", price: 60000.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        ]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        XCTAssertEqual(vm.portfolio?.valuation_status, .partial)
        XCTAssertEqual(vm.portfolio?.valued_count, 1)
        XCTAssertEqual(vm.portfolio?.total_count, 2)
        // Regla matemática: No inventar PnL global incompleto
        XCTAssertNil(vm.portfolio?.total_pnl)
        XCTAssertNil(vm.portfolio?.total_pnl_pct)
        // El subtotal valorado debe reflejar el valor de BTC (1200 EUR)
        XCTAssertEqual(vm.portfolio?.total_value, 1200.0)
    }

    // 4. Valoración sin precios
    func test04_valoracionSinPrecios() {
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "ADA", name: "Cardano", icon: "₳", color: "#00D2D3", source: "binance", invested: 500.0, entry_price: 0.50, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        vm.lastKnownQuotes = [:]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        XCTAssertEqual(vm.portfolio?.valuation_status, .unvalued)
        XCTAssertNil(vm.portfolio?.total_value)
    }

    // 5. Compras múltiples del mismo activo (CASO OBLIGATORIO DE LA AUDITORÍA)
    func test05_comprasMultiplesMismoActivo() {
        let now = Date()
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                // Compra 1: 100 EUR a 10 EUR por unidad -> 10 unidades
                RawPosition(coin: "ABC", name: "Activo ABC", icon: "◆", color: "#FFD700", source: "binance", invested: 100.0, entry_price: 10.0, currency: "EUR"),
                // Compra 2: 100 EUR a 20 EUR por unidad -> 5 unidades
                RawPosition(coin: "ABC", name: "Activo ABC", icon: "◆", color: "#FFD700", source: "binance", invested: 100.0, entry_price: 20.0, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        // Cotización actual: 15 EUR
        vm.lastKnownQuotes = [
            "ABC": MarketQuote(symbol: "ABC", price: 15.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        ]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        let item = vm.portfolio?.items.first(where: { $0.symbol == "ABC" })
        XCTAssertNotNil(item)

        // Verificaciones exactas del caso obligatorio:
        // Cantidad total: 15 unidades
        // Capital invertido: 200 EUR
        // Precio medio: 13.333333 EUR
        // Valor actual: 225 EUR
        // PnL: +25 EUR
        // Rentabilidad: +12.5 %
        XCTAssertEqual(vm.portfolio?.total_invested, 200.0)
        XCTAssertEqual(vm.portfolio?.total_value, 225.0)
        XCTAssertEqual(vm.portfolio?.total_pnl, 25.0)
        XCTAssertEqual(vm.portfolio?.total_pnl_pct, 12.5)

        XCTAssertEqual(item?.invested, 200.0)
        XCTAssertEqual(item?.value, 225.0)
        XCTAssertEqual(item?.pnl, 25.0)
        XCTAssertEqual(item?.pnl_pct, 12.5)
    }

    // 6. Cálculo correcto de unidades
    func test06_calculoCorrectoUnidades() {
        let pos1 = RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 1000.0, entry_price: 50000.0, currency: "EUR")
        let qty = pos1.invested / pos1.entry_price!
        XCTAssertEqual(qty, 0.02)
    }

    // 7. Precio medio ponderado correcto
    func test07_precioMedioPonderadoCorrecto() {
        let now = Date()
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "XYZ", name: "XYZ", icon: "◆", color: "#FFF", source: "binance", invested: 300.0, entry_price: 30.0, currency: "EUR"), // 10 unidades
                RawPosition(coin: "XYZ", name: "XYZ", icon: "◆", color: "#FFF", source: "binance", invested: 100.0, entry_price: 10.0, currency: "EUR")  // 10 unidades
            ]
        )
        vm.portfolio = payload
        vm.lastKnownQuotes = [
            "XYZ": MarketQuote(symbol: "XYZ", price: 20.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        ]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        // 400 EUR invertidos / 20 unidades = 20.0 EUR precio medio de entrada
        // Valor: 20 unidades * 20 EUR = 400 EUR -> PnL: 0
        XCTAssertEqual(vm.portfolio?.total_invested, 400.0)
        XCTAssertEqual(vm.portfolio?.total_value, 400.0)
        XCTAssertEqual(vm.portfolio?.total_pnl, 0.0)
        XCTAssertEqual(vm.portfolio?.total_pnl_pct, 0.0)
    }

    // 8. Conversión EUR/USD
    func test08_conversionEurUsd() {
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = Date()
        let res = vm.convertAmount(100.0, from: "EUR", to: "USD")
        XCTAssertNotNil(res)
        XCTAssertEqual(res!, 110.0, accuracy: 0.0001)
    }

    // 9. Conversión USD/EUR
    func test09_conversionUsdEur() {
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = Date()
        let res = vm.convertAmount(110.0, from: "USD", to: "EUR")
        XCTAssertNotNil(res)
        XCTAssertEqual(res!, 100.0, accuracy: 0.0001)
    }

    // 10. Conversión GBP/USD
    func test10_conversionGbpUsd() {
        vm.gbpUsdRate = 1.30
        vm.gbpUsdRateDate = Date()
        let res = vm.convertAmount(100.0, from: "GBP", to: "USD")
        XCTAssertNotNil(res)
        XCTAssertEqual(res!, 130.0, accuracy: 0.0001)
    }

    // 11. Conversión GBp/GBP
    func test11_conversionGbpToPound() {
        let res = vm.convertAmount(4200.0, from: "GBp", to: "GBP")
        XCTAssertNotNil(res)
        XCTAssertEqual(res!, 42.0, accuracy: 0.0001)
    }

    // 12. Conversión GBp/EUR
    func test12_conversionGbpToEur() {
        vm.gbpUsdRate = 1.30
        vm.gbpUsdRateDate = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = Date()

        // 4200 GBp = 42 GBP -> 42 * 1.30 = 54.60 USD -> 54.60 / 1.10 = 49.63636 EUR
        let res = vm.convertAmount(4200.0, from: "GBp", to: "EUR")
        XCTAssertNotNil(res)
        XCTAssertEqual(res!, 49.63636, accuracy: 0.001)
    }

    // 13. Tipo de cambio caducado (> 48h)
    func test13_tipoDeCambioCaducado() {
        let now = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = now.addingTimeInterval(-97 * 3600) // 97 horas de antigüedad

        let res = vm.convertAmount(100.0, from: "USD", to: "EUR", now: now)
        XCTAssertNil(res, "El tipo de cambio con más de 96h debe ser rechazado como caducado")
    }

    // 14. Tipo de cambio futuro
    func test14_tipoDeCambioFuturo() {
        let now = Date()
        let quote = MarketQuote(symbol: "BTC", price: 60000.0, currency: "EUR", timestamp: now.addingTimeInterval(3600), source: "binance", isVerifiedTimestamp: true)
        XCTAssertFalse(vm.isQuoteTimestampValid(quote, now: now), "Timestamp futuro debe ser rechazado")
    }

    // 15. Cotización caducada (crypto > 24h)
    func test15_cotizacionCaducada() {
        let now = Date()
        let quote = MarketQuote(symbol: "BTC", price: 60000.0, currency: "EUR", timestamp: now.addingTimeInterval(-25 * 3600), source: "binance", isVerifiedTimestamp: true)
        XCTAssertFalse(vm.isQuoteTimestampValid(quote, now: now), "Cotización cripto mayor a 24h debe considerarse obsoleta")
    }

    // 16. Cotización sin timestamp verificable
    func test16_cotizacionSinTimestampVerificable() {
        let now = Date()
        let quote = MarketQuote(symbol: "IGLN", price: 40.0, currency: "USD", timestamp: now, source: "yahoo", isVerifiedTimestamp: false)
        XCTAssertFalse(vm.isQuoteTimestampValid(quote, now: now), "Cotización de Yahoo sin regularMarketTime debe ser rechazada")
    }

    // 17. Cotización NaN o infinita
    func test17_cotizacionNanOInfinita() {
        XCTAssertFalse(vm.isQuotePriceValid(Double.nan))
        XCTAssertFalse(vm.isQuotePriceValid(Double.infinity))
        XCTAssertFalse(vm.isQuotePriceValid(-10.0))
        XCTAssertFalse(vm.isQuotePriceValid(0.0))
        XCTAssertTrue(vm.isQuotePriceValid(42.5))
    }

    // 18. Cotización antigua frente a nueva
    func test18_cotizacionAntiguaFrenteANueva() {
        let now = Date()
        let q1 = MarketQuote(symbol: "BTC", price: 60000.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        let qOld = MarketQuote(symbol: "BTC", price: 50000.0, currency: "EUR", timestamp: now.addingTimeInterval(-100), source: "binance", isVerifiedTimestamp: true)

        vm.lastKnownQuotes["BTC"] = q1
        // Intentar actualizar con qOld
        if let existing = vm.lastKnownQuotes["BTC"], qOld.timestamp >= existing.timestamp {
            vm.lastKnownQuotes["BTC"] = qOld
        }

        XCTAssertEqual(vm.lastKnownQuotes["BTC"]?.price, 60000.0, "La cotización más reciente no debe ser sobrescrita por una antigua")
    }

    // 19. Activo sin precio de entrada
    func test19_activoSinPrecioDeEntrada() {
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 1000.0, entry_price: nil, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        // La inversión se conserva pero no se valora ni calcula PnL
        XCTAssertEqual(vm.portfolio?.total_invested, 1000.0)
        XCTAssertEqual(vm.portfolio?.valuation_status, .unvalued)
    }

    // 20. Valoración parcial con porcentajes coherentes
    func test20_valoracionParcialPorcentajesCoherentes() {
        let now = Date()
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "A", name: "A", icon: "◆", color: "#F00", source: "binance", invested: 60.0, entry_price: 10.0, currency: "EUR"),
                RawPosition(coin: "B", name: "B", icon: "◆", color: "#0F0", source: "binance", invested: 40.0, entry_price: 10.0, currency: "EUR")
            ]
        )
        vm.portfolio = payload
        // Solo A cotiza
        vm.lastKnownQuotes = [
            "A": MarketQuote(symbol: "A", price: 15.0, currency: "EUR", timestamp: now, source: "binance", isVerifiedTimestamp: true)
        ]
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        let itemA = vm.portfolio?.items.first(where: { $0.symbol == "A" })
        let itemB = vm.portfolio?.items.first(where: { $0.symbol == "B" })

        // Ambos activos usan el mismo denominador (100 EUR invertidos):
        // A: 60 / 100 = 60%, B: 40 / 100 = 40% -> Suma = 100%
        XCTAssertEqual(itemA?.share_pct, 60.0)
        XCTAssertEqual(itemB?.share_pct, 40.0)
        let sumShares = (itemA?.share_pct ?? 0) + (itemB?.share_pct ?? 0)
        XCTAssertEqual(sumShares, 100.0, accuracy: 0.1)
    }

    // 21. Cancelación de peticiones
    func test21_cancelacionDePeticiones() {
        vm.isAppActive = false
        vm.stopForegroundUpdates()
        XCTAssertFalse(vm.isUpdatingPrices)
        XCTAssertFalse(vm.isSyncing)
    }

    // 23. Entrada en background y reanudación
    func test23_backgroundYReanudacion() {
        vm.applicationWillResignActive()
        XCTAssertFalse(vm.isAppActive)
        XCTAssertFalse(vm.isUpdatingPrices)

        vm.applicationDidBecomeActive()
        XCTAssertTrue(vm.isAppActive)
    }

    // 24. Cambio de EUR a USD
    func test24_cambioEurAUsd() {
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = Date()
        vm.displayCurrency = "EUR"
        vm.toggleCurrency()
        XCTAssertEqual(vm.displayCurrency, "USD")
    }

    // 25. Cambio de USD a EUR
    func test25_cambioUsdAEur() {
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = Date()
        vm.displayCurrency = "USD"
        vm.toggleCurrency()
        XCTAssertEqual(vm.displayCurrency, "EUR")
    }

    // 26. Conversión fallida que impide cambiar la divisa
    func test26_conversionFallidaImpideCambiarDivisa() {
        vm.eurUsdRate = nil
        vm.eurUsdRateDate = nil
        vm.displayCurrency = "EUR"
        vm.toggleCurrency()
        // No debe cambiar a USD si la tasa no existe
        XCTAssertEqual(vm.displayCurrency, "EUR")
        XCTAssertTrue(vm.statusText.contains("no disponible"))
    }
    // 27. Una inversión cuya divisa no puede convertirse se conserva como no disponible, no como cero.
    func test27_inversionNoConvertibleNoSeMuestraComoCero() {
        let payload = PortfolioPayload(
            currency: "EUR",
            positions: [
                RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F", source: "binance", invested: 500.0, entry_price: 50000.0, currency: "EUR"),
                RawPosition(coin: "ETH", name: "Ethereum", icon: "Ξ", color: "#9B7DFF", source: "binance", invested: 250.0, entry_price: 2500.0, currency: "GBP")
            ]
        )
        vm.eurUsdRate = nil
        vm.eurUsdRateDate = nil
        vm.gbpUsdRate = nil
        vm.gbpUsdRateDate = nil
        vm.portfolio = payload
        vm.recalculatePortfolioFromBase(targetCurrency: "EUR")

        let eth = vm.portfolio?.items.first(where: { $0.symbol == "ETH" })
        XCTAssertNotNil(eth, "La posición original debe permanecer visible")
        XCTAssertEqual(eth?.investmentConversionAvailable, false)
        XCTAssertEqual(eth?.invested, 0.0, "El importe interno es un subtotal técnico; la interfaz debe mostrar un guion")
        XCTAssertFalse(vm.portfolio?.investmentTotalIsComplete ?? true)
        XCTAssertNil(eth?.value)
        XCTAssertNil(eth?.pnl)
    }

    // 28. Los tipos de cambio futuros se rechazan en todas las rutas de conversión.
    func test28_conversionRechazaTipoCambioFuturo() {
        let now = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = now.addingTimeInterval(3600)
        XCTAssertNil(vm.convertAmount(100, from: "EUR", to: "USD", now: now))
        XCTAssertNil(vm.convertAmount(100, from: "USD", to: "EUR", now: now))

        vm.gbpUsdRate = 1.30
        vm.gbpUsdRateDate = now.addingTimeInterval(3600)
        XCTAssertNil(vm.convertAmount(100, from: "GBP", to: "USD", now: now))
        XCTAssertNil(vm.convertAmount(100, from: "GBP", to: "EUR", now: now))
    }


    // 29. Las tasas oficiales diarias pueden cubrir el cierre de fin de semana.
    func test29_tasaDeReferenciaDiariaCubreFinDeSemana() {
        let now = Date()
        vm.eurUsdRate = 1.10
        vm.eurUsdRateDate = now.addingTimeInterval(-72 * 3600)
        XCTAssertNotNil(vm.convertAmount(100, from: "EUR", to: "USD", now: now))
    }

}
