import Foundation
import SwiftUI
import Combine

public final class PortfolioViewModel: ObservableObject {
    @Published public var portfolio: PortfolioPayload?
    @Published public var displayCurrency: String = "USD"
    @Published public var selectedSymbol: String? = nil
    @Published public var isSyncing: Bool = false
    @Published public var statusText: String = "Listo"
    @Published public var hasSyncedOnce: Bool = false
    @Published public var pcHost: String = "192.168.1.128"
    @Published public var pcPort: String = "8765"

    private let userDefaultsKey = "cached_portfolio_data"
    private let lastSuccessKey = "last_sync_success_date"
    private let hostKey = "pc_server_host"
    private let portKey = "pc_server_port"
    private let currencyPrefKey = "preferred_display_currency"

    private var priceTimer: Timer?
    private var eurUsdRate: Double = 1.08

    public init() {
        if let savedHost = UserDefaults.standard.string(forKey: hostKey), !savedHost.isEmpty {
            self.pcHost = savedHost
        }
        if let savedPort = UserDefaults.standard.string(forKey: portKey), !savedPort.isEmpty {
            self.pcPort = savedPort
        }
        if let savedCurr = UserDefaults.standard.string(forKey: currencyPrefKey), !savedCurr.isEmpty {
            self.displayCurrency = savedCurr
        }

        // 1. Cargar posiciones guardadas en el iPhone
        loadCachedData()

        // 2. Actualizar precios en vivo desde Internet automáticamente cada 15s
        updateLivePricesFromInternet()
        startAutoPriceTimer()
    }

    deinit {
        priceTimer?.invalidate()
    }

    public func toggleSelection(for symbol: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedSymbol == symbol {
                selectedSymbol = nil
            } else {
                selectedSymbol = symbol
            }
        }
    }

    // MARK: - Botón Conmutador EUR <-> USD Instantáneo
    public func toggleCurrency() {
        let oldCurr = displayCurrency
        let newCurr = (oldCurr == "USD") ? "EUR" : "USD"
        let newSym = (newCurr == "EUR") ? "€" : "$"

        displayCurrency = newCurr
        UserDefaults.standard.set(newCurr, forKey: currencyPrefKey)

        // Conversión instantánea en pantalla (0ms de espera)
        if var current = self.portfolio {
            let srcCurr = current.currency
            if srcCurr != newCurr {
                current.total_invested = round2(convertAmount(current.total_invested, from: srcCurr, to: newCurr))
                current.total_value = round2(convertAmount(current.total_value, from: srcCurr, to: newCurr))
                current.total_pnl = round2(convertAmount(current.total_pnl, from: srcCurr, to: newCurr))

                var updatedItems: [PortfolioItem] = []
                for var item in current.items {
                    item.invested = round2(convertAmount(item.invested, from: srcCurr, to: newCurr))
                    item.value = round2(convertAmount(item.value, from: srcCurr, to: newCurr))
                    item.pnl = round2(convertAmount(item.pnl, from: srcCurr, to: newCurr))
                    updatedItems.append(item)
                }
                current.items = updatedItems
                current.currency = newCurr
                current.currency_symbol = newSym

                withAnimation(.easeInOut(duration: 0.15)) {
                    self.portfolio = current
                }
                saveToCache(current)
            }
        }

        // Recalcular en segundo plano con las posiciones exactas
        updateLivePricesFromInternet()
    }

    private func round2(_ val: Double) -> Double {
        (val * 100).rounded() / 100
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

    public func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(PortfolioPayload.self, from: data) {
                self.portfolio = decoded
                self.hasSyncedOnce = true
                if UserDefaults.standard.string(forKey: currencyPrefKey) == nil {
                    self.displayCurrency = decoded.currency
                }
            }
        }
    }

    private func saveToCache(_ payload: PortfolioPayload) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(payload) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    // MARK: - 1. Sincronización Manual con el PC (Botón superior)
    public func performSync(isManual: Bool = true) {
        guard !isSyncing else { return }
        isSyncing = true

        guard let url = URL(string: "http://\(pcHost):\(pcPort)/api/portfolio") else {
            isSyncing = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false

                if let data = data, error == nil,
                   let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    if var newPayload = try? decoder.decode(PortfolioPayload.self, from: data) {
                        if UserDefaults.standard.string(forKey: self.currencyPrefKey) == nil {
                            self.displayCurrency = newPayload.currency
                            UserDefaults.standard.set(newPayload.currency, forKey: self.currencyPrefKey)
                        } else if newPayload.currency != self.displayCurrency {
                            let src = newPayload.currency
                            let dst = self.displayCurrency
                            newPayload.total_invested = self.round2(self.convertAmount(newPayload.total_invested, from: src, to: dst))
                            newPayload.total_value = self.round2(self.convertAmount(newPayload.total_value, from: src, to: dst))
                            newPayload.total_pnl = self.round2(self.convertAmount(newPayload.total_pnl, from: src, to: dst))

                            var updatedItems: [PortfolioItem] = []
                            for var item in newPayload.items {
                                item.invested = self.round2(self.convertAmount(item.invested, from: src, to: dst))
                                item.value = self.round2(self.convertAmount(item.value, from: src, to: dst))
                                item.pnl = self.round2(self.convertAmount(item.pnl, from: src, to: dst))
                                updatedItems.append(item)
                            }
                            newPayload.items = updatedItems
                            newPayload.currency = dst
                            newPayload.currency_symbol = (dst == "EUR") ? "€" : "$"
                        }

                        self.portfolio = newPayload
                        self.hasSyncedOnce = true
                        self.saveToCache(newPayload)
                        UserDefaults.standard.set(Date(), forKey: self.lastSuccessKey)

                        self.updateLivePricesFromInternet()
                        return
                    }
                }

                if self.portfolio != nil {
                    self.updateLivePricesFromInternet()
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

        let targetCurr = self.displayCurrency
        let targetSym = (targetCurr == "EUR") ? "€" : "$"
        let uniqueCoins = Array(Set(positions.map { $0.coin }))

        let group = DispatchGroup()
        var fetchedPricesUSD: [String: Double] = [:]
        let lock = NSLock()

        group.enter()
        fetchBinancePrice(symbol: "EURUSDT") { rate in
            if let r = rate, r > 0 {
                lock.lock()
                self.eurUsdRate = r
                lock.unlock()
            }
            group.leave()
        }

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
                    invested: self.round2(inv),
                    value: self.round2(curVal),
                    pnl: self.round2(pnl),
                    pnl_pct: self.round2(pnlPct),
                    share_pct: (sharePct * 10).rounded() / 10
                ))
            }

            updated.currency = targetCurr
            updated.currency_symbol = targetSym
            updated.total_invested = self.round2(totalInvested)
            updated.total_value = self.round2(totalCurrentVal)
            updated.total_pnl = self.round2(totalPnl)
            updated.total_pnl_pct = self.round2(totalPnlPct)
            updated.items = newItems

            self.portfolio = updated
            self.saveToCache(updated)
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
