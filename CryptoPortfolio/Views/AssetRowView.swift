import SwiftUI

// MARK: - Fila Compacta de Activo adaptada a pantalla de 4 pulgadas
public struct AssetRowView: View {
    public let item: PortfolioItem
    public let currencySymbol: String

    public init(item: PortfolioItem, currencySymbol: String) {
        self.item = item
        self.currencySymbol = currencySymbol
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Punto de color identificativo
            Circle()
                .fill(item.uiColor)
                .frame(width: 8, height: 8)

            // Símbolo y Nombre
            VStack(alignment: .leading, spacing: 1) {
                Text(item.symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(item.name)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }

            Spacer()

            // Porcentaje del total en píldora
            Text(String(format: "%.1f%%", item.share_pct))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(white: 0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(white: 0.16))
                .clipShape(Capsule())

            // Valor actual y PnL
            VStack(alignment: .trailing, spacing: 1) {
                Text(formattedValue(item.value))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                if item.pnl != 0.0 {
                    Text(String(format: "%@%.1f%%", item.pnl_pct >= 0 ? "+" : "", item.pnl_pct))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.9, blue: 0.46) : Color(red: 1.0, green: 0.35, blue: 0.37))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formattedValue(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(Int(val))"
    }
}
