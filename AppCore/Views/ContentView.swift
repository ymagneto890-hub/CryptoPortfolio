import SwiftUI

public struct ContentView: View {
    @StateObject private var vm = PortfolioViewModel()
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        ZStack {
            // Fondo negro profundo
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 8) {
                // MARK: - Barra Superior con Botón Manual al PC
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.hasSyncedOnce ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color.orange)
                        .frame(width: 8, height: 8)

                    Text("PORTAFOLIO")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white)

                    Spacer()

                    // Botón grande y claro para sincronizar manualmente con el PC
                    Button(action: { vm.performSync(isManual: true) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .rotationEffect(.degrees(vm.isSyncing ? 360 : 0))
                                .animation(vm.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isSyncing)

                            Text(vm.isSyncing ? "Conectando..." : "Sincronizar PC")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.0, green: 0.35, blue: 0.40).opacity(0.45))
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.0, green: 0.85, blue: 0.85).opacity(0.5), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }

                    // Botón Ajustes IP
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.7))
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.13))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

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
                    .padding(.vertical, 2)

                    // MARK: - Tarjetas XL que rellenan todo el alto disponible de la pantalla
                    GeometryReader { geo in
                        let count = CGFloat(payload.items.count)
                        let spacing: CGFloat = 7
                        let totalSpacing = spacing * max(0, count - 1)
                        let calculatedRowHeight = count > 0 ? max(46, (geo.size.height - totalSpacing) / count) : 50

                        if count <= 5 {
                            VStack(spacing: spacing) {
                                ForEach(payload.items) { item in
                                    AssetRowView(
                                        item: item,
                                        currencySymbol: payload.currency_symbol,
                                        isSelected: vm.selectedSymbol == item.symbol,
                                        onTap: {
                                            vm.toggleSelection(for: item.symbol)
                                        }
                                    )
                                    .frame(height: calculatedRowHeight)
                                }
                            }
                            .padding(.horizontal, 10)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: spacing) {
                                    ForEach(payload.items) { item in
                                        AssetRowView(
                                            item: item,
                                            currencySymbol: payload.currency_symbol,
                                            isSelected: vm.selectedSymbol == item.symbol,
                                            onTap: {
                                                vm.toggleSelection(for: item.symbol)
                                            }
                                        )
                                        .frame(height: 52)
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                } else {
                    // MARK: - Estado inicial antes de la primera sincronización
                    Spacer()

                    DonutChartView(
                        items: [],
                        totalValue: 0,
                        totalPnl: 0,
                        totalPnlPct: 0,
                        currencySymbol: "$",
                        isWaitingFirstSync: true
                    )

                    VStack(spacing: 10) {
                        Text("Conecta con tu PC")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Pulsa el botón 'Sincronizar PC' de arriba para descargar tus posiciones por WiFi.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer()
                }

                // MARK: - Footer de Estado en Vivo
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.0, green: 0.85, blue: 0.5))
                    Text(vm.statusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(Color(white: 0.55))
                .padding(.bottom, 5)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(vm: vm)
        }
    }
}
