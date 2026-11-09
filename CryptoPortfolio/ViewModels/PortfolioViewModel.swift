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

    public init() {
        // Cargar configuración guardada de conexión
        if let savedHost = UserDefaults.standard.string(forKey: hostKey), !savedHost.isEmpty {
            self.pcHost = savedHost
        }
        if let savedPort = UserDefaults.standard.string(forKey: portKey), !savedPort.isEmpty {
            self.pcPort = savedPort
        }

        // Cargar datos locales cacheados (si ya se sincronizó antes)
        loadCachedData()

        // Ejecutar chequeo diario
        checkDailySync()
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

        if let lastSuccess = UserDefaults.standard.object(forKey: lastSuccessKey) as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if formatter.string(from: lastSuccess) == todayString() {
                self.isConnectedToday = true
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                self.statusText = "Sincronizado hoy \(timeFormatter.string(from: lastSuccess))"
            } else {
                self.isConnectedToday = false
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "dd/MM"
                self.statusText = "Última sinc: \(dayFormatter.string(from: lastSuccess))"
            }
        } else {
            self.statusText = "Esperando primera sincronización..."
        }
    }

    public func checkDailySync() {
        let today = todayString()
        let lastAttempt = UserDefaults.standard.string(forKey: lastAttemptKey) ?? ""

        if lastAttempt == today {
            // Ya se intentó hoy: respetar la regla y no saturar ni gastar batería
            return
        }

        // Nuevo día: intentar conectar automáticamente
        performSync(isManual: false)
    }

    public func performSync(isManual: Bool = true) {
        guard !isSyncing else { return }
        isSyncing = true
        statusText = "Conectando al PC..."

        // Registrar intento del día para no reintentar en bucle
        UserDefaults.standard.set(todayString(), forKey: lastAttemptKey)

        guard let url = URL(string: "http://\(pcHost):\(pcPort)/api/portfolio") else {
            isSyncing = false
            statusText = "Dirección IP no válida"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5 // Ultrarrápido para no drenar batería si el PC está apagado

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

                        let timeFormatter = DateFormatter()
                        timeFormatter.dateFormat = "HH:mm"
                        self.statusText = "Sincronizado hoy \(timeFormatter.string(from: Date()))"
                        return
                    }
                }

                // Si ha fallado la conexión con el PC
                if self.portfolio != nil {
                    // Mantiene el portfolio previo offline sin problemas
                    self.statusText = isManual ? "PC no responde (revisa WiFi)" : "Sin conexión hoy • Reintenta mañana"
                } else {
                    self.statusText = "PC desconectado. Toca para reintentar."
                }
            }
        }.resume()
    }
}
