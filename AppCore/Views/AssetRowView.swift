import SwiftUI

// MARK: - Fila XL con Barra de Peso Integrada y Números Grandes (iPhone SE)
public struct AssetRowView: View {
    public let item: PortfolioItem
    public let currencySymbol: String
    public let isSelected: Bool
    public var onTap: (() -> Void)? = nil

    public init(
        item: PortfolioItem,
        currencySymbol: String,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.item = item
        self.currencySymbol = currencySymbol
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Fondo base de la tarjeta
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: isSelected ? 0.15 : 0.095))

                // Barra de progreso proporcional que rellena el hueco visual
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                item.uiColor.opacity(isSelected ? 0.30 : 0.18),
                                item.uiColor.opacity(0.03)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(36, geo.size.width * CGFloat(min(item.share_pct, 100.0) / 100.0)))

                // Contenido principal de la fila
                HStack(spacing: 10) {
                    // Insignia circular de color
                    ZStack {
                        Circle()
                            .fill(item.uiColor.opacity(0.24))
                            .frame(width: 32, height: 32)

                        Circle()
                            .fill(item.uiColor)
                            .frame(width: 11, height: 11)
                    }

                    // Símbolo Grande + Porcentaje Grande
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.symbol)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)

                        Text(String(format: "%.1f%%", item.share_pct))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(item.uiColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(item.uiColor.opacity(0.16))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    // Valor actual gigante y PnL claro a la derecha
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formattedValue(item.value))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)

                        HStack(spacing: 3) {
                            Text(String(format: "%@%@ (%@%.1f%%)",
                                        item.pnl >= 0 ? "+" : "-",
                                        formattedValue(abs(item.pnl)),
                                        item.pnl_pct >= 0 ? "+" : "",
                                        item.pnl_pct))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? item.uiColor : Color(white: 0.15), lineWidth: isSelected ? 1.8 : 0.8)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
        }
    }

    private func formattedValue(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(Int(val))"
    }
}
