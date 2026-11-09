import Foundation
import SwiftUI
import Combine

public final class PortfolioViewModel: ObservableObject {
    // MARK: - Propiedades Publicadas (@Published)
    @Published public var portfolio: PortfolioPayload?
    @Published public var displayCurrency: String = "USD"
    @Published public var selectedSymbol: String? = nil
    @Published public var isSyncing: Bool = false
    @Published public var isUpdatingPrices: Bool = false
    @Published public var statusText: String = "Listo"
    @Published public var hasSyncedOnce: Bool = false
    @Published public var pcHost: String = "192.168.1.128"
    @Published public var pcPort: String = "8765"
    @Published public var lastLiveUpdateDate: Date? = nil

    // MARK: - Claves Constantes de UserDefaults
    private enum Keys {
        static let cachedPortfolio = "cached_portfolio_data"
        static let lastSyncSuccess = "last_sync_success_date"
        static let pcHost = "pc_server_host"
        static let pcPort = "pc_server_port"
        static let displayCurrency = "preferred_display_currency"
        static let lastEurUsdRate = "last_valid_eur_usd_rate"
        static let lastRateDate = "last_valid_eur_usd_rate_date"
        static let cachedQuotes = "cached_market_quotes_v2"
    }

    // MARK: - Control de Temporizadores y Concurrencia
    private var priceTimer: Timer?
    private let autoUpdateInterval: TimeInterval = 30.0

    private var currentUpdateId: Int = 0
    private var pendingRefreshRequested: Bool = false
    private var activeDataTasks: [URLSessionDataTask] = []
    private let lock = NSLock()

    // MARK: - Tipos de Cambio y Caché de Cotizaciones
    private var eurUsdRate: Double = 1.08
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
        }

        let savedRate = defaults.double(forKey: Keys.lastEurUsdRate)
        if savedRate > 0 {
            self.eurUsdRate = savedRate
        }

        // Cargar cotizaciones y datos previos guardados en el iPhone
        loadCachedQuotes()
        loadCachedData()

        // Iniciar el temporizador a 30s y actualizar inmediatamente
        startForegroundUpdates()
        refreshIfNeeded()
    }

    deinit {
        stopForegroundUpdates()
    }

    // MARK: - Ciclo de Vida en Primer Plano (start / stop / refresh)
    public func startForegroundUpdates() {
        stopForegroundUpdates()
        priceTimer = Timer.scheduledTimer(withTimeInterval: autoUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateLivePricesFromInternet()
        }
        if let timer = priceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopForegroundUpdates() {
        priceTimer?.invalidate()
        priceTimer = nil
        cancelActiveDataTasks()
    }

    public func refreshIfNeeded() {
        guard !isUpdatingPrices else { return }
        if let lastUpdate = lastLiveUpdateDate {
            if Date().timeIntervalSince(lastUpdate) >= 20.0 {
                updateLivePricesFromInternet()
            }
        } else {
            updateLivePricesFromInternet()
        }
    }

    private func cancelActiveDataTasks() {
        lock.lock()
        for task in activeDataTasks {
            task.cancel()
        }
        activeDataTasks.removeAll()
        lock.unlock()
    }

    private func trackTask(_ task: URLSessionDataTask) {
        lock.lock()
        activeDataTasks.append(task)
        lock.unlock()
    }

    private func untrackTask(_ task: URLSessionDataTask) {
        lock.lock()
        activeDataTasks.removeAll { $0 === task }
        lock.unlock()
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

    // MARK: - Conmutador EUR <-> USD (Sin errores acumulativos)
    public func toggleCurrency() {
        let oldCurr = displayCurrency
        let newCurr = (oldCurr == "USD") ? "EUR" : "USD"

        displayCurrency = newCurr
        UserDefaults.standard.set(newCurr, forKey: Keys.displayCurrency)

        // Recalcular instantáneamente la cartera desde las posiciones base originales
        recalculatePortfolioFromBase(targetCurrency: newCurr)

        // Solicitar actualización fresca de precios si no hay una en curso
        updateLivePricesFromInternet()
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
            self.lastKnownQuotes = decoded
        }
    }

    private func saveCachedQuotes() {
        if let data = try? JSONEncoder().encode(lastKnownQuotes) {
            UserDefaults.standard.set(data, forKey: Keys.cachedQuotes)
        }
    }

    // MARK: - 1. Sincronización Manual con el Servidor PC
    public func performSync(isManual: Bool = true) {
        guard !isSyncing else { return }

        // Validación de IP y Puerto
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
        request.timeoutInterval = 3.5

        // Autenticación segura mediante Bearer Token cargado desde Keychain
        if let token = KeychainHelper.loadToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.statusText = "Error: Token PC no autorizado"
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

                            // Recalcular con la divisa elegida y actualizar cotizaciones
                            self.recalculatePortfolioFromBase(targetCurrency: self.displayCurrency)
                            self.updateLivePricesFromInternet()
                            return
                        }
                    }
                }

                // Si falla la conexión con el PC, conservar la cartera existente en caché
                if self.portfolio != nil {
                    self.statusText = "PC desconectado (usando caché)"
                    self.updateLivePricesFromInternet()
                } else {
                    self.statusText = "Error al conectar con PC"
                }
            }
        }
        trackTask(task)
        task.resume()
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
        guard let currentPortfolio = self.portfolio,
              let positions = currentPortfolio.positions,
              !positions.isEmpty else {
            return
        }

        // Control de concurrencia: evitar dos ciclos simultáneos
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

        // 1. Obtener tipo de cambio EUR/USD real desde Binance o Yahoo
        group.enter()
        fetchRealEurUsdRate { [weak self] rate in
            if let r = rate, r > 0 {
                self?.lock.lock()
                self?.eurUsdRate = r
                UserDefaults.standard.set(r, forKey: Keys.lastEurUsdRate)
                UserDefaults.standard.set(Date(), forKey: Keys.lastRateDate)
                self?.lock.unlock()
            }
            group.leave()
        }

        // 2. Obtener cotizaciones para cada activo único del portafolio
        let uniqueCoins = Array(Set(positions.map { $0.coin }))

        for coin in uniqueCoins {
            guard let samplePos = positions.first(where: { $0.coin == coin }) else { continue }
            group.enter()

            if samplePos.source == "yahoo" {
                // Si la divisa de visualización es EUR y existe símbolo en EUR, preferirlo
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
                // Cripto vía Binance (USDT)
                fetchBinancePrice(symbol: "\(coin)USDT") { [weak self] price in
                    if let p = price, p > 0 {
                        let q = MarketQuote(symbol: coin, price: p, currency: "USD")
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

            // Comprobación de carrera: descartar si se lanzó una actualización posterior
            guard thisUpdateId == self.currentUpdateId else { return }

            self.isUpdatingPrices = false
            self.lastLiveUpdateDate = Date()
            self.saveCachedQuotes()

            // Determinar estado de la actualización
            let totalExpected = uniqueCoins.count
            let totalReceived = freshlyFetchedQuotes.count
            if totalReceived == totalExpected {
                self.statusText = "Actualizado"
            } else if totalReceived > 0 {
                self.statusText = "Actualización parcial (\(totalReceived)/\(totalExpected))"
            } else {
                self.statusText = "Sin conexión (usando últimos precios)"
            }

            // Aplicar los precios recalculando la cartera sobre la divisa actualmente activa
            self.recalculatePortfolioFromBase(targetCurrency: self.displayCurrency)

            // Si se solicitó una actualización mientras esta procesaba, ejecutarla ahora
            if self.pendingRefreshRequested {
                self.pendingRefreshRequested = false
                self.updateLivePricesFromInternet()
            }
        }
    }

    // MARK: - Recálculo Matemático Consistente desde Posiciones Base
    private func recalculatePortfolioFromBase(targetCurrency: String) {
        guard var current = self.portfolio, let positions = current.positions, !positions.isEmpty else {
            return
        }

        let targetSym = (targetCurrency == "EUR") ? "€" : "$"
        var totalInvested: Double = 0.0
        var totalCurrentVal: Double = 0.0

        var coinInvestedMap: [String: Double] = [:]
        var coinValMap: [String: Double] = [:]
        var coinMetaMap: [String: RawPosition] = [:]
        var coinLivePriceMap: [String: Double] = [:]

        for pos in positions {
            coinMetaMap[pos.coin] = pos

            // Convertir montos invertidos y precio de entrada desde su moneda original al target
            let inv = convertAmount(pos.invested, from: pos.currency, to: targetCurrency)
            let ep = convertAmount(pos.entry_price, from: pos.currency, to: targetCurrency)

            // Obtener el precio actual: usar la última cotización real válida
            var livePriceInTarget: Double = ep
            if let quote = lastKnownQuotes[pos.coin], let converted = convertQuotePrice(quote, to: targetCurrency) {
                livePriceInTarget = converted
            } else if let cachedItem = current.items.first(where: { $0.symbol == pos.coin }),
                      let itemPrice = cachedItem.current_price, itemPrice > 0 {
                // Fallback a la última valoración en caché del ítem si aún no hay quote directa
                livePriceInTarget = (current.currency == targetCurrency) ? itemPrice : convertAmount(itemPrice, from: current.currency, to: targetCurrency)
            }

            coinLivePriceMap[pos.coin] = livePriceInTarget

            // Valor actual = invertido * (precio_actual / precio_entrada)
            let curVal = (ep > 0) ? (inv * (livePriceInTarget / ep)) : inv

            totalInvested += inv
            totalCurrentVal += curVal
            coinInvestedMap[pos.coin, default: 0.0] += inv
            coinValMap[pos.coin, default: 0.0] += curVal
        }

        let totalPnl = totalCurrentVal - totalInvested
        let totalPnlPct = (totalInvested > 0) ? ((totalPnl / totalInvested) * 100.0) : 0.0

        var newItems: [PortfolioItem] = []
        let sortedCoins = coinValMap.sorted { $0.value > $1.value }

        for (ck, curVal) in sortedCoins {
            let inv = coinInvestedMap[ck] ?? 0.0
            let pnl = curVal - inv
            let pnlPct = (inv > 0) ? ((pnl / inv) * 100.0) : 0.0
            let sharePct = (totalCurrentVal > 0) ? ((curVal / totalCurrentVal) * 100.0) : 0.0
            let meta = coinMetaMap[ck]
            let livePrice = coinLivePriceMap[ck] ?? 0.0

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
                current_price: livePrice
            ))
        }

        current.currency = targetCurrency
        current.currency_symbol = targetSym
        current.total_invested = round2(totalInvested)
        current.total_value = round2(totalCurrentVal)
        current.total_pnl = round2(totalPnl)
        current.total_pnl_pct = round2(totalPnlPct)
        current.items = newItems

        withAnimation(.easeInOut(duration: 0.15)) {
            self.portfolio = current
        }
        saveToCache(current)
    }

    // MARK: - Conversión de Divisas
    public func convertAmount(_ amount: Double, from src: String, to dst: String) -> Double {
        let s = src.uppercased()
        let d = dst.uppercased()
        if s == d { return amount }
        if s == "EUR" && d == "USD" { return amount * eurUsdRate }
        if s == "USD" && d == "EUR" { return (eurUsdRate > 0) ? (amount / eurUsdRate) : amount }
        return amount
    }

    private func convertQuotePrice(_ quote: MarketQuote, to targetCurr: String) -> Double? {
        let src = quote.currency.uppercased()
        let dst = targetCurr.uppercased()
        var price = quote.price

        // Manejo especial de peniques británicos (GBp) a Libras (GBP)
        if quote.currency == "GBp" {
            price = price / 100.0
        }

        if src == dst || (quote.currency == "GBp" && dst == "GBP") {
            return price
        }

        if src == "USD" && dst == "EUR" {
            return (eurUsdRate > 0) ? (price / eurUsdRate) : nil
        }
        if src == "EUR" && dst == "USD" {
            return price * eurUsdRate
        }

        // Si la moneda es distinta y no hay conversión directa fiable, conservar el valor conocido
        return price
    }

    private func round2(_ val: Double) -> Double {
        (val * 100).rounded() / 100
    }

    // MARK: - Clientes de Red Nativos (Binance + Yahoo Finance)
    private func fetchRealEurUsdRate(completion: @escaping (Double?) -> Void) {
        // Intento 1: Binance EURUSDT
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=EURUSDT") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceStr = json["price"] as? String,
               let rate = Double(priceStr), rate > 0 {
                completion(rate)
                return
            }

            // Fallback: Yahoo Finance EURUSD=X
            self?.fetchYahooEurUsdFallback(completion: completion)
        }
        trackTask(task)
        task.resume()
    }

    private func fetchYahooEurUsdFallback(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/EURUSD=X?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
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
        trackTask(task)
        task.resume()
    }

    private func fetchBinancePrice(symbol: String, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer { if let t = self?.activeDataTasks.last { self?.untrackTask(t) } }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["price"] as? String,
                  let price = Double(priceStr) else {
                completion(nil)
                return
            }
            completion(price)
        }
        trackTask(task)
        task.resume()
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

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            defer { if let t = self?.activeDataTasks.last { self?.untrackTask(t) } }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = root["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double else {
                completion(nil)
                return
            }

            let currency = (meta["currency"] as? String) ?? "USD"
            let quote = MarketQuote(symbol: symbol, price: price, currency: currency)
            completion(quote)
        }
        trackTask(task)
        task.resume()
    }
}
