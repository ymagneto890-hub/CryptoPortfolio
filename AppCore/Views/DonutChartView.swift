import SwiftUI

// MARK: - Gráfica Redonda XL Interactiva para iPhone SE (4 pulgadas)
public struct DonutChartView: View {
    public let items: [PortfolioItem]
    public let totalValue: Double
    public let totalPnl: Double
    public let totalPnlPct: Double
    public let currencySymbol: String
    public let selectedSymbol: String?
    public let isWaitingFirstSync: Bool
    public var onCenterTap: (() -> Void)? = nil

    private let size: CGFloat = 182
    private let lineWidth: CGFloat = 20

    public init(
        items: [PortfolioItem],
        totalValue: Double,
        totalPnl: Double = 0,
        totalPnlPct: Double,
        currencySymbol: String,
        selectedSymbol: String? = nil,
        isWaitingFirstSync: Bool = false,
        onCenterTap: (() -> Void)? = nil
    ) {
        self.items = items
        self.totalValue = totalValue
        self.totalPnl = totalPnl
        self.totalPnlPct = totalPnlPct
        self.currencySymbol = currencySymbol
        self.selectedSymbol = selectedSymbol
        self.isWaitingFirstSync = isWaitingFirstSync
        self.onCenterTap = onCenterTap
    }

    private var selectedItem: PortfolioItem? {
        guard let sym = selectedSymbol else { return nil }
        return items.first(where: { $0.symbol == sym })
    }

    public var body: some View {
        ZStack {
            if isWaitingFirstSync || items.isEmpty {
                Circle()
                    .stroke(
                        Color(white: 0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 8])
                    )
                    .frame(width: size, height: size)

                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(red: 0.0, green: 0.85, blue: 0.85))

                    Text("SIN DATOS")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Pulsa actualizar 🔄")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                }
            } else {
                // Base del anillo
                Circle()
                    .stroke(Color(white: 0.11), lineWidth: lineWidth)
                    .frame(width: size, height: size)

                // Segmentos de cada activo
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    let isDimmed = (selectedSymbol != nil && selectedSymbol != slice.symbol)
                    DonutSliceShape(startAngle: slice.startAngle, endAngle: slice.endAngle)
                        .stroke(
                            slice.color.opacity(isDimmed ? 0.25 : 1.0),
                            style: StrokeStyle(lineWidth: selectedSymbol == slice.symbol ? lineWidth + 4 : lineWidth, lineCap: .butt)
                        )
                        .frame(width: size, height: size)
                }

                // Contenido Central (Global o Activo Seleccionado)
                if let item = selectedItem {
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.uiColor)
                                .frame(width: 8, height: 8)
                            Text("\(item.symbol) • \(String(format: "%.1f%%", item.share_pct))")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(item.uiColor)
                        }

                        Text(formattedValue(item.value))
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)

                        Text("Inv: \(formattedValue(item.invested))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(white: 0.68))

                        Text(String(format: "%@%.1f%%", item.pnl_pct >= 0 ? "+" : "", item.pnl_pct))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                (item.pnl_pct >= 0 ? Color(red: 0.0, green: 0.45, blue: 0.22) : Color(red: 0.45, green: 0.1, blue: 0.1))
                                    .opacity(0.45)
                            )
                            .clipShape(Capsule())
                    }
                    .frame(width: size - (lineWidth * 2) - 8)
                    .contentShape(Circle())
                    .onTapGesture {
                        onCenterTap?()
                    }
                } else {
                    VStack(spacing: 3) {
                        Text("PORTAFOLIO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundColor(Color(white: 0.6))

                        Text(formattedValue(totalValue))
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)

                        HStack(spacing: 3) {
                            Text(String(format: "%@%@ (%@%.1f%%)",
                                        totalPnl >= 0 ? "+" : "-",
                                        formattedValue(abs(totalPnl)),
                                        totalPnlPct >= 0 ? "+" : "",
                                        totalPnlPct))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundColor(totalPnlPct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            (totalPnlPct >= 0 ? Color(red: 0.0, green: 0.45, blue: 0.22) : Color(red: 0.45, green: 0.1, blue: 0.1))
                                .opacity(0.45)
                        )
                        .clipShape(Capsule())
                    }
                    .frame(width: size - (lineWidth * 2) - 8)
                }
            }
        }
        .frame(width: size + lineWidth + 6, height: size + lineWidth + 6)
    }

    private func formattedValue(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(Int(val))"
    }

    private struct SliceData {
        let symbol: String
        let startAngle: Angle
        let endAngle: Angle
        let color: Color
    }

    private var slices: [SliceData] {
        var result: [SliceData] = []
        var currentAngle: Double = -90.0

        for item in items {
            let sweep = (item.share_pct / 100.0) * 360.0
            if sweep > 0.5 {
                let start = Angle(degrees: currentAngle)
                let end = Angle(degrees: currentAngle + sweep - 1.5)
                result.append(SliceData(symbol: item.symbol, startAngle: start, endAngle: end, color: item.uiColor))
                currentAngle += sweep
            }
        }
        return result
    }
}

struct DonutSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
