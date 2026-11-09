import SwiftUI

// MARK: - Tarjeta Compacta para Cuadrícula de 2 Columnas (iPhone SE)
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
        ZStack(alignment: .leading) {
            // Fondo de la tarjeta
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(white: isSelected ? 0.16 : 0.095))

            // Brillo sutil del color del activo
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            item.uiColor.opacity(isSelected ? 0.28 : 0.14),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                // Fila 1: Punto de color + Símbolo + Badge de rendimiento (+15.4%)
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.uiColor)
                        .frame(width: 8, height: 8)

                    Text(item.symbol)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if let lp = item.current_price, lp > 0 {
                        Text(String(format: "%@%.1f%%", item.pnl_pct >= 0 ? "+" : "", item.pnl_pct))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.45, blue: 0.22) : Color(red: 0.45, green: 0.1, blue: 0.1))
                                    .opacity(0.40)
                            )
                            .clipShape(Capsule())
                    } else {
                        Text("—")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(white: 0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.2).opacity(0.4))
                            .clipShape(Capsule())
                    }

                }

                // Fila 2: Precio actual de mercado en grande y limpio (o — si no hay cotización)
                Text(formattedPrice(item.current_price))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? item.uiColor : Color(white: 0.14), lineWidth: isSelected ? 1.8 : 0.8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private func formattedPrice(_ priceOpt: Double?) -> String {
        guard let val = priceOpt, val > 0 else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol

        if val >= 1000 {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        } else if val >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else if val >= 0.01 {
            formatter.maximumFractionDigits = 3
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        }

        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(val)"
    }
}
