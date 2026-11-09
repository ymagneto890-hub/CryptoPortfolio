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
        static let cachedPortfolio = "cached_portfolio_data"
        static let lastSyncSuccess = "last_sync_success_date"
        static let pcHost = "pc_server_host"
        static let pcPort = "pc_server_port"
        static let displayCurrency = "preferred_display_currency"
        static let lastEurUsdRate = "last_valid_eur_usd_rate"
        static let lastEurRateDate = "last_valid_eur_usd_rate_date"
        static let lastGbpUsdRate = "last_valid_gbp_usd_rate"
        static let lastGbpRateDate = "last_valid_gbp_usd_rate_date"
        static let cachedQuotes = "cached_market_quotes_v2"
    }

    // MARK: - Control de Temporizadores y Concurrencia
    private var priceTimer: Timer?
    private let autoUpdateInterval: TimeInterval = 30.0

    private var currentUpdateId: Int = 0
    private var pendingRefreshRequested: Bool = false
    private var activeDataTasks: Set<URLSessionDataTask> = []
    private let tasksLock = NSLock()

    // MARK: - Tipos de Cambio Reales (CERO valores iniciales ficticios)
    private var eurUsdRate: Double? = nil
    private var eurUsdRateDate: Date? = nil

    private var gbpUsdRate: Double? = nil
    private var gbpUsdRateDate: Date? = nil

    private let maxRateAgeSeconds: TimeInterval = 48 * 3600 // 48 horas máx antigüedad
    private let maxQuoteAgeSeconds: TimeInterval = 7 * 86400 // 7 días máx cotización

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

        displayCurrency = newCurr
        UserDefaults.standard.set(newCurr, forKey: Keys.displayCurrency)

        recalculatePortfolioFromBase(targetCurrency: newCurr)

        if isAppActive && !isUpdatingPrices {
            updateLivePricesFromInternet()
        }
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
            // Filtrar cotizaciones obsoletas
            var freshQuotes: [String: MarketQuote] = [:]
            let now = Date()
            for (coin, quote) in decoded {
                let age = now.timeIntervalSince(quote.timestamp)
                if age >= 0 && age < maxQuoteAgeSeconds && quote.price > 0 {
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
                guard let self = self, self.isAppActive else { return }
                self.isSyncing = false

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.statusText = "Error: Token PC no autorizado (401)"
                        return
                    }

                    if httpResponse.statusCode == 200, let data = data, error == nil {
                        let decoder = JSONDecoder()
                        if let newPayload = try? decoder.decode(PortfolioPayload.self, from: data),
                           !newPayload.items.isEmpty || !(newPayload.positions ?? []).isEmpty {
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
        var freshlyFetchedQuotes: [String: MarketQuote] = [:]
        let localLock = NSLock()

        // 1. Obtener tipo de cambio EUR/USD real
        group.enter()
        fetchRealEurUsdRate { [weak self] rate in
            if let r = rate, r > 0 {
                self?.tasksLock.lock()
                self?.eurUsdRate = r
                self?.eurUsdRateDate = Date()
                UserDefaults.standard.set(r, forKey: Keys.lastEurUsdRate)
                UserDefaults.standard.set(Date(), forKey: Keys.lastEurRateDate)
                self?.tasksLock.unlock()
            }
            group.leave()
        }

        // 2. Obtener tipo de cambio GBP/USD real
        group.enter()
        fetchRealGbpUsdRate { [weak self] rate in
            if let r = rate, r > 0 {
                self?.tasksLock.lock()
                self?.gbpUsdRate = r
                self?.gbpUsdRateDate = Date()
                UserDefaults.standard.set(r, forKey: Keys.lastGbpUsdRate)
                UserDefaults.standard.set(Date(), forKey: Keys.lastGbpRateDate)
                self?.tasksLock.unlock()
            }
            group.leave()
        }

        // 3. Obtener cotizaciones de cada activo
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

                fetchYahooPrice(symbol: preferredSymbol) { [weak self] quote in
                    if let q = quote, q.price > 0 {
                        localLock.lock()
                        freshlyFetchedQuotes[coin] = q
                        self?.lastKnownQuotes[coin] = q
                        localLock.unlock()
                    }
                    group.leave()
                }
            } else {
                fetchBinancePrice(symbol: "\(coin)USDT") { [weak self] price in
                    if let p = price, p > 0 {
                        let q = MarketQuote(symbol: coin, price: p, currency: "USD", timestamp: Date())
                        localLock.lock()
                        freshlyFetchedQuotes[coin] = q
                        self?.lastKnownQuotes[coin] = q
                        localLock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            guard self.isAppActive else {
                self.isUpdatingPrices = false
                self.pendingRefreshRequested = false
                return
            }

            guard thisUpdateId == self.currentUpdateId else { return }

            self.isUpdatingPrices = false
            self.lastLiveUpdateDate = Date()
            self.saveCachedQuotes()

            let totalExpected = uniqueCoins.count
            let totalReceived = freshlyFetchedQuotes.count
            if totalReceived == totalExpected {
                self.statusText = "Actualizado"
            } else if totalReceived > 0 {
                self.statusText = "Parcial (\(totalReceived)/\(totalExpected))"
            } else {
                self.statusText = "Sin conexión (últimas cotizaciones)"
            }

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
    private func recalculatePortfolioFromBase(targetCurrency: String) {
        guard var current = self.portfolio, let positions = current.positions, !positions.isEmpty else {
            return
        }

        let targetSym = (targetCurrency == "EUR") ? "€" : (targetCurrency == "GBP" ? "£" : "$")
        var totalInvested: Double = 0.0
        var totalCurrentVal: Double = 0.0
        var hasAtLeastOneValidPrice = false

        var coinInvestedMap: [String: Double] = [:]
        var coinValMap: [String: Double] = [:]
        var coinMetaMap: [String: RawPosition] = [:]
        var coinLivePriceMap: [String: Double?] = [:]

        for pos in positions {
            coinMetaMap[pos.coin] = pos

            // Conversión estricta de inversión inicial
            let inv = convertAmount(pos.invested, from: pos.currency, to: targetCurrency) ?? pos.invested
            let ep = convertAmount(pos.entry_price, from: pos.currency, to: targetCurrency) ?? pos.entry_price

            // Determinar cotización de mercado real
            var livePriceInTarget: Double? = nil
            if let quote = lastKnownQuotes[pos.coin], let converted = convertQuotePrice(quote, to: targetCurrency) {
                livePriceInTarget = converted
                hasAtLeastOneValidPrice = true
            } else if let cachedItem = current.items.first(where: { $0.symbol == pos.coin }),
                      let itemPrice = cachedItem.current_price, itemPrice > 0 {
                livePriceInTarget = convertAmount(itemPrice, from: current.currency, to: targetCurrency)
                if livePriceInTarget != nil {
                    hasAtLeastOneValidPrice = true
                }
            }

            coinLivePriceMap[pos.coin] = livePriceInTarget

            // Valor actual: SI NO HAY COTIZACIÓN VÁLIDA, NO ASUMIR QUE VALOR ES IGUAL A ENTRADA
            let curVal: Double
            if let lp = livePriceInTarget, ep > 0 {
                curVal = inv * (lp / ep)
            } else {
                curVal = 0.0
            }

            totalInvested += inv
            totalCurrentVal += curVal
            coinInvestedMap[pos.coin, default: 0.0] += inv
            coinValMap[pos.coin, default: 0.0] += curVal
        }

        let totalPnl = hasAtLeastOneValidPrice ? (totalCurrentVal - totalInvested) : 0.0
        let totalPnlPct = (hasAtLeastOneValidPrice && totalInvested > 0) ? ((totalPnl / totalInvested) * 100.0) : 0.0

        var newItems: [PortfolioItem] = []
        let sortedCoins = coinInvestedMap.sorted { (coinValMap[$0.key] ?? 0) > (coinValMap[$1.key] ?? 0) }

        for (ck, _) in sortedCoins {
            let inv = coinInvestedMap[ck] ?? 0.0
            let curVal = coinValMap[ck] ?? 0.0
            let lp = coinLivePriceMap[ck] ?? nil
            let meta = coinMetaMap[ck]

            let pnl: Double
            let pnlPct: Double
            let sharePct: Double

            if lp != nil && inv > 0 {
                pnl = curVal - inv
                pnlPct = (pnl / inv) * 100.0
                sharePct = (totalCurrentVal > 0) ? ((curVal / totalCurrentVal) * 100.0) : 0.0
            } else {
                pnl = 0.0
                pnlPct = 0.0
                sharePct = (totalInvested > 0) ? ((inv / totalInvested) * 100.0) : 0.0
            }

            newItems.append(PortfolioItem(
                symbol: ck,
                name: meta?.name ?? ck,
                icon: meta?.icon ?? "◆",
                color: meta?.color ?? "#F3BA2F",
                invested: round2(inv),
                value: round2(curVal),
                pnl: round2(pnl),
                pnl_pct: round2(pnlPct),
                share_pct: (sharePct * 10).rounded() / 10,
                current_price: lp
            ))
        }

        current.currency = targetCurrency
        current.currency_symbol = targetSym
        current.total_invested = round2(totalInvested)
        current.total_value = hasAtLeastOneValidPrice ? round2(totalCurrentVal) : 0.0
        current.total_pnl = round2(totalPnl)
        current.total_pnl_pct = round2(totalPnlPct)
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

        if s == "USD" && d == "EUR" {
            guard let rate = eurUsdRate, rate > 0 else { return nil }
            return val / rate
        }
        if s == "EUR" && d == "USD" {
            guard let rate = eurUsdRate, rate > 0 else { return nil }
            return val * rate
        }

        if s == "GBP" && d == "USD" {
            guard let gRate = gbpUsdRate, gRate > 0 else { return nil }
            return val * gRate
        }
        if s == "USD" && d == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0 else { return nil }
            return val / gRate
        }

        if s == "GBP" && d == "EUR" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let eRate = eurUsdRate, eRate > 0 else { return nil }
            return (val * gRate) / eRate
        }
        if s == "EUR" && d == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let eRate = eurUsdRate, eRate > 0 else { return nil }
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

        if src == "USD" && dst == "EUR" {
            guard let rate = eurUsdRate, rate > 0 else { return nil }
            return rawPrice / rate
        }
        if src == "EUR" && dst == "USD" {
            guard let rate = eurUsdRate, rate > 0 else { return nil }
            return rawPrice * rate
        }

        if src == "GBP" && dst == "USD" {
            guard let gRate = gbpUsdRate, gRate > 0 else { return nil }
            return rawPrice * gRate
        }
        if src == "USD" && dst == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0 else { return nil }
            return rawPrice / gRate
        }

        if src == "GBP" && dst == "EUR" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let eRate = eurUsdRate, eRate > 0 else { return nil }
            return (rawPrice * gRate) / eRate
        }
        if src == "EUR" && dst == "GBP" {
            guard let gRate = gbpUsdRate, gRate > 0,
                  let eRate = eurUsdRate, eRate > 0 else { return nil }
            return (rawPrice * eRate) / gRate
        }

        // Si no existe tipo de cambio fiable, no devolver cotización en moneda errónea
        return nil
    }

    private func round2(_ val: Double) -> Double {
        (val * 100).rounded() / 100
    }

    // MARK: - Clientes de Red Nativos
    private func fetchRealEurUsdRate(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=EURUSDT") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = json["price"] as? String,
               let rate = Double(priceStr), rate > 0 {
                completion(rate)
                return
            }
            self?.fetchYahooEurUsdFallback(completion: completion)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchYahooEurUsdFallback(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/EURUSD=X?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = root["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double, price > 0 else {
                completion(nil)
                return
            }
            completion(price)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchRealGbpUsdRate(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=GBPUSDT") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = json["price"] as? String,
               let rate = Double(priceStr), rate > 0 {
                completion(rate)
                return
            }
            self?.fetchYahooGbpUsdFallback(completion: completion)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchYahooGbpUsdFallback(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/GBPUSD=X?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = root["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double, price > 0 else {
                completion(nil)
                return
            }
            completion(price)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchBinancePrice(symbol: String, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["price"] as? String,
                  let price = Double(priceStr), price > 0 else {
                completion(nil)
                return
            }
            completion(price)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }

    private func fetchYahooPrice(symbol: String, completion: @escaping (MarketQuote?) -> Void) {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer {
                if let t = task {
                    self?.unregisterTask(t)
                }
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = root["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double, price > 0,
                  let currency = meta["currency"] as? String, !currency.isEmpty else {
                // Si Yahoo NO devuelve meta.currency, NO asumir USD; descartar
                completion(nil)
                return
            }

            let quote = MarketQuote(symbol: symbol, price: price, currency: currency, timestamp: Date())
            completion(quote)
        }
        if let t = task {
            registerTask(t)
            t.resume()
        }
    }
}
