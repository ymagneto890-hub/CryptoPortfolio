import SwiftUI

public struct ContentView: View {
    @StateObject private var vm = PortfolioViewModel()
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        ZStack {
            // Fondo oscuro Obsidian Widget
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 8) {
                // Header superior muy limpio
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isConnectedToday ? Color(red: 0.0, green: 0.9, blue: 0.46) : Color.orange)
                        .frame(width: 7, height: 7)

                    Text("PORTAFOLIO")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(Color(white: 0.75))

                    Spacer()

                    // Botón Sincronizar manual
                    Button(action: { vm.performSync(isManual: true) }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(vm.isSyncing ? .cyan : Color(white: 0.6))
                            .rotationEffect(.degrees(vm.isSyncing ? 360 : 0))
                            .animation(vm.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isSyncing)
                    }
                    .padding(6)

                    // Botón Ajustes IP
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.6))
                    }
                    .padding(6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)

                // Gráfica Redonda (El Círculo)
                if let payload = vm.portfolio, !payload.items.isEmpty {
                    DonutChartView(
                        items: payload.items,
                        totalValue: payload.total_value,
                        totalPnlPct: payload.total_pnl_pct,
                        currencySymbol: payload.currency_symbol,
                        isWaitingFirstSync: false
                    )
                    .padding(.vertical, 2)

                    // Lista de Activos desglosados
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(payload.items) { item in
                                AssetRowView(item: item, currencySymbol: payload.currency_symbol)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                } else {
                    // Estado previo a la primera sincronización con el PC
                    Spacer()

                    DonutChartView(
                        items: [],
                        totalValue: 0,
                        totalPnlPct: 0,
                        currencySymbol: "$",
                        isWaitingFirstSync: true
                    )

                    VStack(spacing: 8) {
                        Text("Esperando primera conexión")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text("Abre CryptoWidget en tu PC con Windows y pulsa el botón para traer tu portafolio:")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button(action: { vm.performSync(isManual: true) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(vm.isSyncing ? "Conectando..." : "Sincronizar con PC")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color(red: 0.0, green: 0.75, blue: 0.75))
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    }

                    Spacer()
                }

                // Footer de Estado / Regla de sincronización diaria
                HStack(spacing: 5) {
                    Image(systemName: vm.isConnectedToday ? "checkmark.circle.fill" : "clock")
                        .font(.system(size: 9))
                    Text(vm.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(Color(white: 0.45))
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(vm: vm)
        }
    }
}
