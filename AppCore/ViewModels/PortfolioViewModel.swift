import Foundation
import SwiftUI
import Combine

public final class PortfolioViewModel: ObservableObject {
    // MARK: - Propiedades Publicadas (@Published)
    @Published public var portfolio: PortfolioPayload?
    @Published public var displayCurrency: String = "EUR"
    @Published public var selectedSymbol: String? = nil
    @Published public var isSyncing: Bool = false
    @Published public var isUpdatingPrices: Bool = false
    @Published public var statusText: String = "Listo"
    @Published public var hasSyncedOnce: Bool = false
    @Published public var pcHost: String = "192.168.1.128"
    @Published public var pcPort: String = "8765"
    @Published public var lastLiveUpdateDate: Date? = nil
    @Published public var isAppActive: Bool = true

    // MARK: - Claves Constantes de UserDefaults
    private enum Keys {
        static let cachedPortfolio = "cached_portfolio_data_v3"
        static let lastSyncSuccess = "last_sync_success_date"
        static let pcHost = "pc_server_host"
        static let pcPort = "pc_server_port"
        static let displayCurrency = "preferred_display_currency"
        static let lastEurUsdRate = "last_valid_eur_usd_rate"
        static let lastEurRateDate = "last_valid_eur_usd_rate_date"
        static let lastGbpUsdRate = "last_valid_gbp_usd_rate"
        static let lastGbpRateDate = "last_valid_gbp_usd_rate_date"
        static let cachedQuotes = "cached_market_quotes_v3"
    }

    // MARK: - Control de Temporizadores y Concurrencia
    private var priceTimer: Timer?
    private let autoUpdateInterval: TimeInterval = 30.0

    private var currentUpdateId: Int = 0
    private var currentSyncGen: Int = 0
    private var pendingRefreshRequested: Bool = false
    private var activeDataTasks: Set<URLSessionDataTask> = []
    private let tasksLock = NSLock()

    // MARK: - Tipos de Cambio Reales y Antigüedad Máxima
    private var eurUsdRate: Double? = nil
    private var eurUsdRateDate: Date? = nil

    private var gbpUsdRate: Double? = nil
    private var gbpUsdRateDate: Date? = nil

    // Límites estrictos de frescura de datos financieros
    public let maxRateAgeSeconds: TimeInterval = 48 * 3600 // Máximo 48 horas para FX
    public let maxQuoteAgeSeconds: TimeInterval = 7 * 86400 // Máximo 7 días para cotizaciones

    // Diccionario de cotizaciones verificadas (acceso serializado en DispatchQueue.main)
    private var lastKnownQuotes: [String: MarketQuote] = [:]

    public init() {
        let defaults = UserDefaults.standard

        if let savedHost = defaults.string(forKey: Keys.pcHost), !savedHost.isEmpty {
            self.pcHost = savedHost
        }
        if let savedPort = defaults.string(forKey: Keys.pcPort), !savedPort.isEmpty {
            self.pcPort = savedPort
        }
        if let savedCurr = defaults.string(forKey: Keys.displayCurrency), !savedCurr.isEmpty {
            self.displayCurrency = savedCurr
        } else {
            self.displayCurrency = "EUR"
        }

        // Cargar tipo de cambio EUR/USD previo de la caché verificando fecha y antigüedad
        let savedEurRate = defaults.double(forKey: Keys.lastEurUsdRate)
        if savedEurRate > 0, let rateDate = defaults.object(forKey: Keys.lastEurRateDate) as? Date {
            let age = Date().timeIntervalSince(rateDate)
            if age >= 0 && age < maxRateAgeSeconds {
                self.eurUsdRate = savedEurRate
                self.eurUsdRateDate = rateDate
            }
        }

        // Cargar tipo de cambio GBP/USD previo de la caché verificando fecha y antigüedad
        let savedGbpRate = defaults.double(forKey: Keys.lastGbpUsdRate)
        if savedGbpRate > 0, let rateDate = defaults.object(forKey: Keys.lastGbpRateDate) as? Date {
            let age = Date().timeIntervalSince(rateDate)
            if age >= 0 && age < maxRateAgeSeconds {
                self.gbpUsdRate = savedGbpRate
                self.gbpUsdRateDate = rateDate
            }
        }

        // Cargar cotizaciones y datos previos guardados en el iPhone
        loadCachedQuotes()
        loadCachedData()

        // Iniciar en primer plano
        startForegroundUpdates()
        refreshImmediate()
    }

    deinit {
        stopForegroundUpdates()
    }

    // MARK: - Ciclo de Vida de iOS (Foreground / Background)
    public func applicationDidBecomeActive() {
        isAppActive = true
        startForegroundUpdates()
        refreshImmediate()
    }

    public func applicationWillResignActive() {
        isAppActive = false
        pendingRefreshRequested = false
        stopForegroundUpdates()
    }

    public func startForegroundUpdates() {
        stopForegroundUpdates()
        priceTimer = Timer.scheduledTimer(withTimeInterval: autoUpdateInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isAppActive else { return }
            self.updateLivePricesFromInternet()
        }
        if let timer = priceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopForegroundUpdates() {
        priceTimer?.invalidate()
        priceTimer = nil
        cancelActiveDataTasks()
        isUpdatingPrices = false
        isSyncing = false // Garantiza que no quede bloqueado al regresar a primer plano
    }

    public func refreshImmediate() {
        guard isAppActive && !isUpdatingPrices else { return }
        updateLivePricesFromInternet()
    }

    // MARK: - Gestión Concurrente Segura de URLSession
    private func registerTask(_ task: URLSessionDataTask) {
        tasksLock.lock()
        activeDataTasks.insert(task)
        tasksLock.unlock()
    }

    private func unregisterTask(_ task: URLSessionDataTask) {
        tasksLock.lock()
        activeDataTasks.remove(task)
        tasksLock.unlock()
    }

    private func cancelActiveDataTasks() {
        tasksLock.lock()
        for task in activeDataTasks {
            task.cancel()
        }
        activeDataTasks.removeAll()
        tasksLock.unlock()
    }

    // MARK: - Selección de Activo en la Gráfica
    public func toggleSelection(for symbol: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedSymbol == symbol {
                selectedSymbol = nil
            } else {
                selectedSymbol = symbol
            }
        }
    }

    // MARK: - Conmutador de Divisa (EUR <-> USD)
    public func toggleCurrency() {
        let oldCurr = displayCurrency
        let newCurr = (oldCurr == "EUR") ? "USD" : "EUR"

        // Comprobación de seguridad: Si no hay tipo de cambio disponible o está caducado,
        // NO cambiar el símbolo de divisa para evitar mostrar cifras engañosas
        if !isRateValid() {
            self.statusText = "Tipo de cambio no disponible"
            return
        }

        displayCurrency = newCurr
        UserDefaults.standard.set(newCurr, forKey: Keys.displayCurrency)

        recalculatePortfolioFromBase(targetCurrency: newCurr)

        if isAppActive && !isUpdatingPrices {
            updateLivePricesFromInternet()
        }
    }

    public func isRateValid() -> Bool {
        guard let rate = eurUsdRate, rate > 0, let d = eurUsdRateDate else { return false }
        let age = Date().timeIntervalSince(d)
        return age >= 0 && age < maxRateAgeSeconds
    }

    public func isGbpRateValid() -> Bool {
        guard let rate = gbpUsdRate, rate > 0, let d = gbpUsdRateDate else { return false }
        let age = Date().timeIntervalSince(d)
        return age >= 0 && age < maxRateAgeSeconds
    }

    public func saveConnectionSettings(host: String, port: String) {
        self.pcHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pcPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.pcHost, forKey: Keys.pcHost)
        UserDefaults.standard.set(self.pcPort, forKey: Keys.pcPort)
    }

    // MARK: - Caché Local (UserDefaults)
    public func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: Keys.cachedPortfolio) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(PortfolioPayload.self, from: data) {
                self.portfolio = decoded
                self.hasSyncedOnce = true
                if UserDefaults.standard.string(forKey: Keys.displayCurrency) == nil {
                    self.displayCurrency = decoded.currency
                }
                // Recalcular con cotizaciones verificadas para evitar cualquier residuo ficticio
                recalculatePortfolioFromBase(targetCurrency: self.displayCurrency)
            }
        }
    }

    private func saveToCache(_ payload: PortfolioPayload) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(payload) {
            UserDefaults.standard.set(encoded, forKey: Keys.cachedPortfolio)
        }
    }

    private func loadCachedQuotes() {
        if let data = UserDefaults.standard.data(forKey: Keys.cachedQuotes),
           let decoded = try? JSONDecoder().decode([String: MarketQuote].self, from: data) {
            var freshQuotes: [String: MarketQuote] = [:]
            let now = Date()
            for (coin, quote) in decoded {
                let age = now.timeIntervalSince(quote.timestamp)
                // Solo aceptar cotizaciones con precio válido, fecha verificable y < 7 días
                if age >= 0 && age < maxQuoteAgeSeconds && quote.price > 0 && quote.source != "unknown" {
                    freshQuotes[coin] = quote
                }
            }
            self.lastKnownQuotes = freshQuotes
        }
    }

    private func saveCachedQuotes() {
        if let data = try? JSONEncoder().encode(lastKnownQuotes) {
            UserDefaults.standard.set(data, forKey: Keys.cachedQuotes)
        }
    }

    // MARK: - 1. Sincronización con el Servidor PC
    public func performSync(isManual: Bool = true) {
        guard isAppActive else { return }
        guard !isSyncing else { return }

        let cleanHost = pcHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = pcPort.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidHost(cleanHost), let portInt = Int(cleanPort), (1...65535).contains(portInt) else {
            DispatchQueue.main.async {
                self.statusText = "IP o puerto no válido"
            }
            return
        }

        guard let url = URL(string: "http://\(cleanHost):\(cleanPort)/api/portfolio") else {
            DispatchQueue.main.async {
                self.statusText = "URL no válida"
            }
            return
        }

        currentSyncGen += 1
        let thisSyncGen = currentSyncGen

        isSyncing = true
        statusText = "Sincronizando..."

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0

        if let token = KeychainHelper.loadToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var syncTask: URLSessionDataTask?
        syncTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                if let t = syncTask {
                    self?.unregisterTask(t)
                }
            }

            DispatchQueue.main.async {
                guard let self = self else { return }

                // Restablecer isSyncing SIEMPRE que coincida la generación de sincronización
                if thisSyncGen == self.currentSyncGen {
                    self.isSyncing = false
                }

                // Si fue cancelada o la app pasó a segundo plano, abortar sin modificar estado
                if let urlErr = error as? URLError, urlErr.code == .cancelled {
                    return
                }
                guard self.isAppActive, thisSyncGen == self.currentSyncGen else { return }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.statusText = "Error: Token PC no autorizado (401)"
                        return
                    }

                    if httpResponse.statusCode == 200, let data = data, error == nil {
                        let decoder = JSONDecoder()
                        if var newPayload = try? decoder.decode(PortfolioPayload.self, from: data),
                           !newPayload.items.isEmpty || !(newPayload.positions ?? []).isEmpty {
                            // Cero cotizaciones ficticias: limpiar cualquier precio de servidor no verificado
                            for i in 0..<newPayload.items.count {
                                newPayload.items[i].current_price = nil
                                newPayload.items[i].value = nil
                                newPayload.items[i].pnl = nil
                                newPayload.items[i].pnl_pct = nil
                            }
                            newPayload.total_value = nil
                            newPayload.total_pnl = nil
                            newPayload.total_pnl_pct = nil
                            newPayload.valuation_status = .unvalued

                            self.portfolio = newPayload
                            self.hasSyncedOnce = true
                            self.statusText = "Sincronizado con PC"
                            self.saveToCache(newPayload)
                            UserDefaults.standard.set(Date(), forKey: Keys.lastSyncSuccess)

                            self.recalculatePortfolioFromBase(targetCurrency: self.displayCurrency)
                            self.updateLivePricesFromInternet()
                            return
                        }
                    }
                }

                if self.portfolio != nil {
                    self.statusText = "PC desconectado (usando caché)"
                    self.updateLivePricesFromInternet()
                } else {
                    self.statusText = "Error al conectar con PC"
                }
            }
        }

        if let t = syncTask {
            registerTask(t)
            t.resume()
        }
    }

    private func isValidHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let n = Int(part), (0...255).contains(n) else { return false }
        }
        return true
    }

    // MARK: - 2. Actualización Autónoma de Precios por Internet
    public func updateLivePricesFromInternet() {
        guard isAppActive else {
            isUpdatingPrices = false
            pendingRefreshRequested = false
            return
        }

        guard let currentPortfolio = self.portfolio,
              let positions = currentPortfolio.positions,
              !positions.isEmpty else {
            return
        }

        if isUpdatingPrices {
            pendingRefreshRequested = true
            return
        }

        isUpdatingPrices = true
        currentUpdateId += 1
        let thisUpdateId = currentUpdateId

        let group = DispatchGroup()
        let localLock = NSLock()

        // Contenedores locales seguros para recopilar respuestas sin modificar estado compartido
        var freshlyFetchedQuotes: [String: MarketQuote] = [:]
        var fetchedEurUsdRate: Double? = nil
        var fetchedEurUsdDate: Date? = nil
        var fetchedGbpUsdRate: Double? = nil
        var fetchedGbpUsdDate: Date? = nil

        // 1. Obtener tipo de cambio EUR/USD real (Yahoo Finance EURUSD=X primario, Binance fallback)
        group.enter()
        fetchRealEurUsdRate(updateId: thisUpdateId) { rate, date in
            if let r = rate, r > 0 {
                localLock.lock()
                fetchedEurUsdRate = r
                fetchedEurUsdDate = date ?? Date()
                localLock.unlock()
            }
            group.leave()
        }

        // 2. Obtener tipo de cambio GBP/USD real SOLO SI la cartera contiene activos en GBP/GBp
        let portfolioNeedsGbp = positions.contains { pos in
            let c = pos.currency.uppercased()
            return c == "GBP" || pos.currency == "GBp" || pos.currency == "GBX" || pos.source == "yahoo"
        }

        if portfolioNeedsGbp {
            group.enter()
            fetchRealGbpUsdRate(updateId: thisUpdateId) { rate, date in
                if let r = rate, r > 0 {
                    localLock.lock()
                    fetchedGbpUsdRate = r
                    fetchedGbpUsdDate = date ?? Date()
                    localLock.unlock()
                }
                group.leave()
            }
        }

        // 3. Obtener cotizaciones de cada activo único
        let uniqueCoins = Array(Set(positions.map { $0.coin }))

        for coin in uniqueCoins {
            guard let samplePos = positions.first(where: { $0.coin == coin }) else { continue }
            group.enter()

            if samplePos.source == "yahoo" {
                let currentTarget = self.displayCurrency
                let preferredSymbol: String
                if currentTarget == "EUR", let eurSym = samplePos.yahoo_sym_eur, !eurSym.isEmpty {
                    preferredSymbol = eurSym
                } else {
                    preferredSymbol = samplePos.yahoo_sym ?? coin
                }

                fetchYahooPrice(symbol: preferredSymbol, coin: coin, updateId: thisUpdateId) { quote in
                    if let q = quote, q.price > 0 {
                        localLock.lock()
                        freshlyFetchedQuotes[coin] = q
                        localLock.unlock()
                    }
                    group.leave()
                }
            } else {
                fetchBinancePrice(symbol: "\(coin)USDT", coin: coin, updateId: thisUpdateId) { quote in
                    if let q = quote, q.price > 0 {
                        localLock.lock()
                        freshlyFetchedQuotes[coin] = q
                        localLock.unlock()
                    }
                    group.leave()
                }
            }
        }

        // 4. Aplicación Serializada en DispatchQueue.main (CERO condiciones de carrera)
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Si la aplicación se suspendió o una nueva actualización arrancó, descartar
            guard self.isAppActive, thisUpdateId == self.currentUpdateId else {
                self.isUpdatingPrices = false
                return
            }

            self.isUpdatingPrices = false
            self.lastLiveUpdateDate = Date()

            // Aplicar tipos de cambio solo si fueron recibidos válidos
            if let eurRate = fetchedEurUsdRate, eurRate > 0 {
                self.eurUsdRate = eurRate
                self.eurUsdRateDate = fetchedEurUsdDate ?? Date()
                UserDefaults.standard.set(eurRate, forKey: Keys.lastEurUsdRate)
                UserDefaults.standard.set(self.eurUsdRateDate, forKey: Keys.lastEurRateDate)
            }
            if let gbpRate = fetchedGbpUsdRate, gbpRate > 0 {
                self.gbpUsdRate = gbpRate
                self.gbpUsdRateDate = fetchedGbpUsdDate ?? Date()
                UserDefaults.standard.set(gbpRate, forKey: Keys.lastGbpUsdRate)
                UserDefaults.standard.set(self.gbpUsdRateDate, forKey: Keys.lastGbpRateDate)
            }

            // Aplicar cotizaciones frescas a lastKnownQuotes preservando timestamps más recientes
            for (coin, freshQuote) in freshlyFetchedQuotes {
                if let existing = self.lastKnownQuotes[coin] {
                    if freshQuote.timestamp >= existing.timestamp {
                        self.lastKnownQuotes[coin] = freshQuote
                    }
                } else {
                    self.lastKnownQuotes[coin] = freshQuote
                }
            }
            self.saveCachedQuotes()

            // Estado de la actualización
            let totalExpected = uniqueCoins.count
            let totalReceived = freshlyFetchedQuotes.count
            if totalReceived == totalExpected {
                self.statusText = "Actualizado"
            } else if totalReceived > 0 {
                self.statusText = "Parcial (\(totalReceived)/\(totalExpected))"
            } else {
                self.statusText = "Sin conexión (usando caché)"
            }

            // Recálculo riguroso del portafolio en el hilo principal
            self.recalculatePortfolioFromBase(targetCurrency: self.displayCurrency)

            if self.pendingRefreshRequested && self.isAppActive {
                self.pendingRefreshRequested = false
                self.updateLivePricesFromInternet()
            } else {
                self.pendingRefreshRequested = false
            }
        }
    }

    // MARK: - Recálculo Matemático Riguroso desde Posiciones Base
    public func recalculatePortfolioFromBase(targetCurrency: String) {
        guard var current = self.portfolio, let positions = current.positions, !positions.isEmpty else {
            return
        }

        let targetSym = (targetCurrency == "EUR") ? "€" : (targetCurrency == "GBP" ? "£" : "$")
        let now = Date()

        // 1. Agrupar posiciones por activo para calcular la inversión y el precio medio en la moneda base
        let uniqueCoins = Array(Set(positions.map { $0.coin }))
        let totalCoinsCount = uniqueCoins.count

        var coinInvestedInTarget: [String: Double] = [:]
        var coinEntryPriceInTarget: [String: Double] = [:]
        var coinMetaMap: [String: RawPosition] = [:]
        var coinLivePriceInTarget: [String: Double] = [:]
        var coinValueInTarget: [String: Double] = [:]
        var coinHasValidValuation: [String: Bool] = [:]

        var canConvertAllCurrencies = true

        for coin in uniqueCoins {
            let coinPositions = positions.filter { $0.coin == coin }
            guard let firstPos = coinPositions.first else { continue }
            coinMetaMap[coin] = firstPos

            var coinTotalInvTarget = 0.0
            var coinWeightedCostTarget = 0.0
            var coinConversionFailed = false

            for pos in coinPositions {
                guard let invInTarget = convertAmount(pos.invested, from: pos.currency, to: targetCurrency),
                      let epInTarget = convertAmount(pos.entry_price, from: pos.currency, to: targetCurrency),
                      invInTarget > 0, epInTarget > 0 else {
                    coinConversionFailed = true
                    canConvertAllCurrencies = false
                    break
                }
                coinTotalInvTarget += invInTarget
                coinWeightedCostTarget += (invInTarget * epInTarget)
            }

            if coinConversionFailed || coinTotalInvTarget <= 0 {
                // Si falla la conversión del activo a la moneda objetivo, no inventar cifras
                continue
            }

            let avgEpTarget = coinWeightedCostTarget / coinTotalInvTarget
            coinInvestedInTarget[coin] = coinTotalInvTarget
            coinEntryPriceInTarget[coin] = avgEpTarget

            // 2. Comprobar cotización verificada y reciente (< 7 días)
            if let quote = lastKnownQuotes[coin],
               quote.price > 0,
               quote.source != "unknown" {
                let age = now.timeIntervalSince(quote.timestamp)
                if age >= 0 && age < maxQuoteAgeSeconds {
                    if let convertedPrice = convertQuotePrice(quote, to: targetCurrency), convertedPrice > 0 {
                        coinLivePriceInTarget[coin] = convertedPrice
                        let val = coinTotalInvTarget * (convertedPrice / avgEpTarget)
                        coinValueInTarget[coin] = val
                        coinHasValidValuation[coin] = true
                    }
                }
            }
        }

        // 3. Determinar estado de valoración de la cartera
        let valuedCoinsCount = coinHasValidValuation.filter { $0.value }.count

        let valuationStatus: ValuationStatus
        if valuedCoinsCount == totalCoinsCount && totalCoinsCount > 0 && canConvertAllCurrencies {
            valuationStatus = .complete
        } else if valuedCoinsCount > 0 {
            valuationStatus = .partial
        } else {
            valuationStatus = .unvalued
        }

        // 4. Cálculo matemático consistente según el estado
        let totalInvestedAll = coinInvestedInTarget.values.reduce(0.0, +)

        let totalValue: Double?
        let totalPnl: Double?
        let totalPnlPct: Double?

        switch valuationStatus {
        case .complete:
            let sumVal = coinValueInTarget.values.reduce(0.0, +)
            totalValue = round2(sumVal)
            let pnl = sumVal - totalInvestedAll
            totalPnl = round2(pnl)
            totalPnlPct = totalInvestedAll > 0 ? round2((pnl / totalInvestedAll) * 100.0) : 0.0

        case .partial:
            // Regla matemática: NUNCA restar la inversión de activos sin precio al valor de los activos con precio
            // Si la cartera está parcial, el valor total no es definitivo y el PnL global no debe inducir a error
            let sumValuedVal = coinValueInTarget.values.reduce(0.0, +)
            totalValue = round2(sumValuedVal)
            totalPnl = nil
            totalPnlPct = nil

        case .unvalued:
            totalValue = nil
            totalPnl = nil
            totalPnlPct = nil
        }

        // 5. Construcción de elementos ordenados
        var newItems: [PortfolioItem] = []
        let sortedCoins = uniqueCoins.sorted { c1, c2 in
            let v1 = coinValueInTarget[c1] ?? coinInvestedInTarget[c1] ?? 0
            let v2 = coinValueInTarget[c2] ?? coinInvestedInTarget[c2] ?? 0
            return v1 > v2
        }

        let totalValuedValueSum = coinValueInTarget.values.reduce(0.0, +)

        for ck in sortedCoins {
            let inv = coinInvestedInTarget[ck] ?? 0.0
            let meta = coinMetaMap[ck]
            let livePrice = coinLivePriceInTarget[ck]
            let val = coinValueInTarget[ck]

            let pnl: Double?
            let pnlPct: Double?
            let sharePct: Double

            if let curVal = val, inv > 0 {
                let p = curVal - inv
                pnl = round2(p)
                pnlPct = round2((p / inv) * 100.0)
                if valuationStatus == .complete && (totalValue ?? 0) > 0 {
                    sharePct = (curVal / (totalValue ?? 1.0)) * 100.0
                } else if valuationStatus == .partial && totalValuedValueSum > 0 {
                    sharePct = (curVal / totalValuedValueSum) * 100.0
                } else {
                    sharePct = (totalInvestedAll > 0) ? (inv / totalInvestedAll) * 100.0 : 0.0
                }
            } else {
                pnl = nil
                pnlPct = nil
                sharePct = (totalInvestedAll > 0) ? (inv / totalInvestedAll) * 100.0 : 0.0
            }

            newItems.append(PortfolioItem(
                symbol: ck,
                name: meta?.name ?? ck,
                icon: meta?.icon ?? "◆",
                color: meta?.color ?? "#F3BA2F",
                invested: round2(inv),
                value: val.map { round2($0) },
                pnl: pnl,
                pnl_pct: pnlPct,
                share_pct: (sharePct * 10).rounded() / 10,
                current_price: livePrice
            ))
        }

        current.currency = targetCurrency
        current.currency_symbol = targetSym
        current.total_invested = round2(totalInvestedAll)
        current.total_value = totalValue
        current.total_pnl = totalPnl
        current.total_pnl_pct = totalPnlPct
        current.valuation_status = valuationStatus
        current.valued_count = valuedCoinsCount
        current.total_count = totalCoinsCount
        current.items = newItems

        withAnimation(.easeInOut(duration: 0.15)) {
            self.portfolio = current
        }
        saveToCache(current)
    }

    // MARK: - Conversión Exacta de Divisas (EUR, USD, GBP, GBp)
    public func convertAmount(_ amount: Double, from src: String, to dst: String) -> Double? {
        var s = src.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = dst.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var val = amount

        if s == "GBp" || s == "GBX" {
            val = val / 100.0
            s = "GBP"
        } else {
            s = s.uppercased()
        }

        if s == d { return val }

        // Comprobación de antigüedad de tipos de cambio (< 48 horas)
        let now = Date()

        if s == "USD" && d == "EUR" {
            guard let rate = eurUsdRate, rate > 0,
                  let rDate = eurUsdRateDate, now.timeIntervalSince(rDate) < maxRateAgeSeconds else { return nil }
            return val / rate
        }
        if s == "EUR" && d == "USD" {
            guard let rate = eurUsdRate, rate > 0,
                  let rDate = eurUsdRateDate, now.timeIntervalSince(rDate) < maxRateAgeSeconds else { return nil }
            return val * rate
        }

        if s == "GBP" && d == "USD" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let gDate = gbpUsdRateDate, now.timeIntervalSince(gDate) < maxRateAgeSeconds else { return nil }
            return val * gRate
        }
        if s == "USD" && d == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let gDate = gbpUsdRateDate, now.timeIntervalSince(gDate) < maxRateAgeSeconds else { return nil }
            return val / gRate
        }

        if s == "GBP" && d == "EUR" {
            guard let gRate = gbpUsdRate, gRate > 0, let gDate = gbpUsdRateDate,
                  let eRate = eurUsdRate, eRate > 0, let eDate = eurUsdRateDate,
                  now.timeIntervalSince(gDate) < maxRateAgeSeconds,
                  now.timeIntervalSince(eDate) < maxRateAgeSeconds else { return nil }
            return (val * gRate) / eRate
        }
        if s == "EUR" && d == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0, let gDate = gbpUsdRateDate,
                  let eRate = eurUsdRate, eRate > 0, let eDate = eurUsdRateDate,
                  now.timeIntervalSince(gDate) < maxRateAgeSeconds,
                  now.timeIntervalSince(eDate) < maxRateAgeSeconds else { return nil }
            return (val * eRate) / gRate
        }

        return nil
    }

    public func convertQuotePrice(_ quote: MarketQuote, to targetCurr: String) -> Double? {
        var rawPrice = quote.price
        guard rawPrice > 0 else { return nil }

        var src = quote.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = targetCurr.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Manejo estricto de peniques británicos (GBp a GBP: división por 100)
        if src == "GBp" || src == "GBX" {
            rawPrice = rawPrice / 100.0
            src = "GBP"
        } else {
            src = src.uppercased()
        }

        if src == dst {
            return rawPrice
        }

        return convertAmount(rawPrice, from: src, to: dst)
    }

    private func round2(_ val: Double) -> Double {
        (val * 100).rounded() / 100
    }

    // MARK: - Clientes de Red Nativos Seguros (Cancelación Limpia y Sin Peticiones en Background)

    // Tipo de cambio EUR/USD: Yahoo Finance EURUSD=X (tasa FX real) con fallback a Binance EURUSDT (cripto)
    private func fetchRealEurUsdRate(updateId: Int, completion: @escaping (Double?, Date?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/EURUSD=X?interval=15m&range=1d") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            // Si la tarea fue cancelada o la app está inactiva, NO ejecutar fallback
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil, nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil, nil)
                return
            }

            if let data = data, error == nil,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = root["chart"] as? [String: Any],
               let results = chart["result"] as? [[String: Any]],
               let first = results.first,
               let meta = first["meta"] as? [String: Any],
               let price = meta["regularMarketPrice"] as? Double, price > 0 {
                let regTime = (meta["regularMarketTime"] as? TimeInterval) ?? (meta["regularMarketTime"] as? Int).map { TimeInterval($0) }
                let rateDate = regTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
                completion(price, rateDate)
                return
            }

            // Fallback secundario a Binance EURUSDT (Aproximación USDT documentada)
            self.fetchBinanceEurUsdFallback(updateId: updateId, completion: completion)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchBinanceEurUsdFallback(updateId: Int, completion: @escaping (Double?, Date?) -> Void) {
        guard isAppActive, updateId == currentUpdateId else {
            completion(nil, nil)
            return
        }

        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=EURUSDT") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.5

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil, nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil, nil)
                return
            }

            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = json["price"] as? String,
               let rate = Double(priceStr), rate > 0 {
                completion(rate, Date())
                return
            }
            completion(nil, nil)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    // Tipo de cambio GBP/USD: Yahoo Finance GBPUSD=X (tasa FX real) con fallback a Binance GBPUSDT
    private func fetchRealGbpUsdRate(updateId: Int, completion: @escaping (Double?, Date?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/GBPUSD=X?interval=15m&range=1d") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil, nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil, nil)
                return
            }

            if let data = data, error == nil,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = root["chart"] as? [String: Any],
               let results = chart["result"] as? [[String: Any]],
               let first = results.first,
               let meta = first["meta"] as? [String: Any],
               let price = meta["regularMarketPrice"] as? Double, price > 0 {
                let regTime = (meta["regularMarketTime"] as? TimeInterval) ?? (meta["regularMarketTime"] as? Int).map { TimeInterval($0) }
                let rateDate = regTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
                completion(price, rateDate)
                return
            }

            self.fetchBinanceGbpUsdFallback(updateId: updateId, completion: completion)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchBinanceGbpUsdFallback(updateId: Int, completion: @escaping (Double?, Date?) -> Void) {
        guard isAppActive, updateId == currentUpdateId else {
            completion(nil, nil)
            return
        }

        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=GBPUSDT") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.5

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil, nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil, nil)
                return
            }

            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = json["price"] as? String,
               let rate = Double(priceStr), rate > 0 {
                completion(rate, Date())
                return
            }
            completion(nil, nil)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchBinancePrice(symbol: String, coin: String, updateId: Int, completion: @escaping (MarketQuote?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil)
                return
            }

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["price"] as? String,
                  let price = Double(priceStr), price > 0 else {
                completion(nil)
                return
            }

            let quote = MarketQuote(symbol: coin, price: price, currency: "USD", timestamp: Date(), source: "binance")
            completion(quote)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchYahooPrice(symbol: String, coin: String, updateId: Int, completion: @escaping (MarketQuote?) -> Void) {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task { self?.unregisterTask(t) }
            }

            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                completion(nil)
                return
            }
            guard let self = self, self.isAppActive, updateId == self.currentUpdateId else {
                completion(nil)
                return
            }

            guard let data = data, error == nil,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = root["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double, price > 0,
                  let currency = meta["currency"] as? String, !currency.isEmpty else {
                completion(nil)
                return
            }

            // Extraer marca de tiempo oficial de la bolsa (regularMarketTime)
            let regTime = (meta["regularMarketTime"] as? TimeInterval) ?? (meta["regularMarketTime"] as? Int).map { TimeInterval($0) }
            let quoteDate: Date
            if let t = regTime, t > 0 {
                quoteDate = Date(timeIntervalSince1970: t)
            } else {
                quoteDate = Date()
            }

            let quote = MarketQuote(symbol: coin, price: price, currency: currency, timestamp: quoteDate, source: "yahoo")
            completion(quote)
        }

        if let t = task {
            registerTask(t)
            t.resume()
        }
    }
}
