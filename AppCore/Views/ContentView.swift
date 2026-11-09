import SwiftUI

public struct ContentView: View {
    @StateObject private var vm = PortfolioViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    public init() {}

    public var body: some View {
        ZStack {
            // Fondo negro profundo
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 10) {
                // MARK: - Barra Superior Minimalista (Solo iconos limpios)
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.hasSyncedOnce ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color.orange)
                        .frame(width: 8, height: 8)

                    Text("PORTAFOLIO")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white)

                    Spacer()

                    // Botón Conmutador Divisa (USD / EUR)
                    Button(action: { vm.toggleCurrency() }) {
                        Text(vm.displayCurrency == "EUR" ? "€ EUR" : "$ USD")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.95))
                            .padding(.horizontal, 9)
                            .frame(height: 32)
                            .background(Color(white: 0.13))
                            .clipShape(Capsule())
                    }

                    // Botón Actualizar desde PC (Solo icono limpio)
                    Button(action: { vm.performSync(isManual: true) }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(vm.isSyncing ? Color(red: 0.0, green: 0.95, blue: 0.95) : Color(white: 0.8))
                            .rotationEffect(.degrees(vm.isSyncing ? 360 : 0))
                            .animation(vm.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isSyncing)
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.13))
                            .clipShape(Circle())
                    }

                    // Botón Ajustes IP
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.75))
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.13))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                if let payload = vm.portfolio, !payload.items.isEmpty {
                    // MARK: - Gráfica Redonda XL Interactiva
                    DonutChartView(
                        items: payload.items,
                        totalValue: payload.total_value,
                        totalPnl: payload.total_pnl,
                        totalPnlPct: payload.total_pnl_pct,
                        currencySymbol: payload.currency_symbol,
                        selectedSymbol: vm.selectedSymbol,
                        isWaitingFirstSync: false,
                        onCenterTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.selectedSymbol = nil
                            }
                        }
                    )
                    .padding(.vertical, 4)

                    // MARK: - Cuadrícula de 2 Columnas (Caben muchos activos sin pegarse abajo)
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: 8) {
                            ForEach(payload.items) { item in
                                AssetRowView(
                                    item: item,
                                    currencySymbol: payload.currency_symbol,
                                    isSelected: vm.selectedSymbol == item.symbol,
                                    onTap: {
                                        vm.toggleSelection(for: item.symbol)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .padding(.bottom, 22)
                    }
                } else {
                    // MARK: - Estado inicial antes de la primera sincronización
                    Spacer()

                    DonutChartView(
                        items: [],
                        totalValue: 0,
                        totalPnl: 0,
                        totalPnlPct: 0,
                        currencySymbol: vm.displayCurrency == "EUR" ? "€" : "$",
                        isWaitingFirstSync: true
                    )

                    VStack(spacing: 8) {
                        Text("Conecta con tu PC")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Pulsa el icono de actualizar arriba a la derecha para traer tus activos.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(vm: vm)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                vm.startForegroundUpdates()
                vm.refreshIfNeeded()
            case .inactive, .background:
                vm.stopForegroundUpdates()
            @unknown default:
                break
            }
        }
    }
}
