import Foundation
import SwiftUI
import Combine

public final class PortfolioViewModel: ObservableObject {
    @Published public var portfolio: PortfolioPayload?
    @Published public var isSyncing: Bool = false
    @Published public var statusText: String = "Iniciando..."
    @Published public var isConnectedToday: Bool = false
    @Published public var pcHost: String = "192.168.1.128"
    @Published public var pcPort: String = "8765"

    private let userDefaultsKey = "cached_portfolio_data"
    private let lastAttemptKey = "last_sync_attempt_day"
    private let lastSuccessKey = "last_sync_success_date"
    private let hostKey = "pc_server_host"
    private let portKey = "pc_server_port"

    private var priceTimer: Timer?
    private var eurUsdRate: Double = 1.08

    public init() {
        if let savedHost = UserDefaults.standard.string(forKey: hostKey), !savedHost.isEmpty {
            self.pcHost = savedHost
        }
        if let savedPort = UserDefaults.standard.string(forKey: portKey), !savedPort.isEmpty {
            self.pcPort = savedPort
        }

        // 1. Cargar posiciones guardadas en el iPhone
        loadCachedData()

        // 2. Comprobar si hoy toca pedir actualización de posiciones al PC (1 vez al día)
        checkDailyPCSync()

        // 3. Actualizar precios en vivo desde Internet por sí solo y programar timer cada 15s
        updateLivePricesFromInternet()
        startAutoPriceTimer()
    }

    deinit {
        priceTimer?.invalidate()
    }

    private func startAutoPriceTimer() {
        priceTimer?.invalidate()
        priceTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.updateLivePricesFromInternet()
        }
    }

    public func saveConnectionSettings(host: String, port: String) {
        self.pcHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pcPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.pcHost, forKey: hostKey)
        UserDefaults.standard.set(self.pcPort, forKey: portKey)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    public func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(PortfolioPayload.self, from: data) {
                self.portfolio = decoded
            }
        }
        updateStatusLabel(liveTime: nil)
    }

    private func saveToCache(_ payload: PortfolioPayload) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(payload) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func updateStatusLabel(liveTime: String?) {
        var pcPart = "Sin sinc. PC"
        if let lastSuccess = UserDefaults.standard.object(forKey: lastSuccessKey) as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if formatter.string(from: lastSuccess) == todayString() {
                self.isConnectedToday = true
                pcPart = "PC al día"
            } else {
                self.isConnectedToday = false
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "dd/MM"
                pcPart = "PC: \(dayFormatter.string(from: lastSuccess))"
            }
        }

        if let live = liveTime {
            self.statusText = "En vivo (\(live)) • \(pcPart)"
        } else if self.portfolio != nil {
            self.statusText = " Guardado • \(pcPart)"
        } else {
            self.statusText = "Esperando 1ª conexión con PC..."
        }
    }

    // MARK: - 1. Petición Diaria al Software del PC (Para nuevos activos o capital)
    public func checkDailyPCSync() {
        let today = todayString()
        let lastAttempt = UserDefaults.standard.string(forKey: lastAttemptKey) ?? ""

        if lastAttempt == today {
            // Ya se intentó conectar con el PC hoy; no volver a pedir al PC hasta mañana
            return
        }

        performSync(isManual: false)
    }

    public func performSync(isManual: Bool = true) {
        guard !isSyncing else { return }
        isSyncing = true
        if isManual {
            statusText = "Sincronizando posiciones con PC..."
        }

        // Registrar el intento de hoy con el PC
        UserDefaults.standard.set(todayString(), forKey: lastAttemptKey)

        guard let url = URL(string: "http://\(pcHost):\(pcPort)/api/portfolio") else {
            isSyncing = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false

                if let data = data, error == nil,
                   let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    if let newPayload = try? decoder.decode(PortfolioPayload.self, from: data) {
                        self.portfolio = newPayload
                        self.isConnectedToday = true
                        UserDefaults.standard.set(data, forKey: self.userDefaultsKey)
                        UserDefaults.standard.set(Date(), forKey: self.lastSuccessKey)

                        let tf = DateFormatter()
                        tf.dateFormat = "HH:mm:ss"
                        self.updateStatusLabel(liveTime: tf.string(from: Date()))

                        // Tras recibir las posiciones del PC, actualizar precios en vivo
                        self.updateLivePricesFromInternet()
                        return
                    }
                }

                // Si el PC estaba apagado hoy, usa el portfolio guardado y actualiza precios por internet
                if self.portfolio != nil {
                    self.updateLivePricesFromInternet()
                } else {
                    self.statusText = "PC desconectado. Toca para sincronizar."
                }
            }
        }.resume()
    }

    // MARK: - 2. Actualización Autónoma por Internet (Binance + Yahoo Finance)
    public func updateLivePricesFromInternet() {
        guard let currentPortfolio = self.portfolio,
              let positions = currentPortfolio.positions,
              !positions.isEmpty else {
            return
        }

        let targetCurr = currentPortfolio.currency
        let uniqueCoins = Array(Set(positions.map { $0.coin }))

        let group = DispatchGroup()
        var fetchedPricesUSD: [String: Double] = [:]
        let lock = NSLock()

        // A. Obtener tipo de cambio EUR/USD en vivo desde Binance
        group.enter()
        fetchBinancePrice(symbol: "EURUSDT") { rate in
            if let r = rate, r > 0 {
                lock.lock()
                self.eurUsdRate = r
                lock.unlock()
            }
            group.leave()
        }

        // B. Obtener precio en vivo de cada activo desde Internet
        for coin in uniqueCoins {
            guard let samplePos = positions.first(where: { $0.coin == coin }) else { continue }
            group.enter()

            if samplePos.source == "yahoo" {
                let ySym = samplePos.yahoo_sym ?? coin
                fetchYahooPrice(symbol: ySym) { price in
                    if let p = price, p > 0 {
                        lock.lock()
                        fetchedPricesUSD[coin] = p
                        lock.unlock()
                    }
                    group.leave()
                }
            } else {
                fetchBinancePrice(symbol: "\(coin)USDT") { price in
                    if let p = price, p > 0 {
                        lock.lock()
                        fetchedPricesUSD[coin] = p
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        // C. Recalcular el portafolio y el círculo en tiempo real en el iPhone
        group.notify(queue: .main) { [weak self] in
            guard let self = self, var updated = self.portfolio else { return }
            guard !fetchedPricesUSD.isEmpty else { return }

            var totalInvested: Double = 0.0
            var totalCurrentVal: Double = 0.0
            var coinInvestedMap: [String: Double] = [:]
            var coinValMap: [String: Double] = [:]
            var coinMetaMap: [String: RawPosition] = [:]

            for pos in positions {
                coinMetaMap[pos.coin] = pos
                let inv = self.convertAmount(pos.invested, from: pos.currency, to: targetCurr)
                let ep = self.convertAmount(pos.entry_price, from: pos.currency, to: targetCurr)

                var livePriceInTarget = ep
                if let rawUsdPrice = fetchedPricesUSD[pos.coin] {
                    livePriceInTarget = self.convertAmount(rawUsdPrice, from: "USD", to: targetCurr)
                }

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

                newItems.append(PortfolioItem(
                    symbol: ck,
                    name: meta?.name ?? ck,
                    icon: meta?.icon ?? "◆",
                    color: meta?.color ?? "#F3BA2F",
                    invested: (inv * 100).rounded() / 100,
                    value: (curVal * 100).rounded() / 100,
                    pnl: (pnl * 100).rounded() / 100,
                    pnl_pct: (pnlPct * 100).rounded() / 100,
                    share_pct: (sharePct * 10).rounded() / 10
                ))
            }

            updated.total_invested = (totalInvested * 100).rounded() / 100
            updated.total_value = (totalCurrentVal * 100).rounded() / 100
            updated.total_pnl = (totalPnl * 100).rounded() / 100
            updated.total_pnl_pct = (totalPnlPct * 100).rounded() / 100
            updated.items = newItems

            self.portfolio = updated
            self.saveToCache(updated)

            let tf = DateFormatter()
            tf.dateFormat = "HH:mm:ss"
            self.updateStatusLabel(liveTime: tf.string(from: Date()))
        }
    }

    private func convertAmount(_ amount: Double, from src: String, to dst: String) -> Double {
        if src == dst { return amount }
        if src == "EUR" && dst == "USD" { return amount * eurUsdRate }
        if src == "USD" && dst == "EUR" { return (eurUsdRate > 0) ? (amount / eurUsdRate) : amount }
        return amount
    }

    private func fetchBinancePrice(symbol: String, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let priceStr = json["price"] as? String,
                  let price = Double(priceStr) else {
                completion(nil)
                return
            }
            completion(price)
        }.resume()
    }

    private func fetchYahooPrice(symbol: String, completion: @escaping (Double?) -> Void) {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=15m&range=1d") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
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
            completion(price)
        }.resume()
    }
}
