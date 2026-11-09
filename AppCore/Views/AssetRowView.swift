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
        ZStack(alignment: .bottomLeading) {
            // Fondo de la tarjeta
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: isSelected ? 0.15 : 0.095))

            // Brillo sutil del color del activo
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

            VStack(alignment: .leading, spacing: 8) {
                // Línea superior: Punto de color + Símbolo + % del portafolio
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.uiColor)
                        .frame(width: 9, height: 9)

                    Text(item.symbol)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Text(String(format: "%.1f%%", item.share_pct))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(item.uiColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.uiColor.opacity(0.16))
                        .clipShape(Capsule())
                }

                // Línea inferior: Valor en grande + % Ganancia/Pérdida
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedValue(item.value))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 2)

                    Text(String(format: "%@%.1f%%", item.pnl_pct >= 0 ? "+" : "", item.pnl_pct))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
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

    private func formattedValue(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(Int(val))"
    }
}
