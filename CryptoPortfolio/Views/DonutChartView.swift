import SwiftUI

// MARK: - Gráfica Redonda (Donut Chart) para iPhone SE 1
public struct DonutChartView: View {
    public let items: [PortfolioItem]
    public let totalValue: Double
    public let totalPnlPct: Double
    public let currencySymbol: String
    public let isWaitingFirstSync: Bool

    private let size: CGFloat = 150
    private let lineWidth: CGFloat = 14

    public init(
        items: [PortfolioItem],
        totalValue: Double,
        totalPnlPct: Double,
        currencySymbol: String,
        isWaitingFirstSync: Bool = false
    ) {
        self.items = items
        self.totalValue = totalValue
        self.totalPnlPct = totalPnlPct
        self.currencySymbol = currencySymbol
        self.isWaitingFirstSync = isWaitingFirstSync
    }

    public var body: some View {
        ZStack {
            if isWaitingFirstSync || items.isEmpty {
                // Anillo de espera previo a la primera sincronización
                Circle()
                    .stroke(
                        Color(white: 0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [4, 6])
                    )
                    .frame(width: size, height: size)

                VStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 0.83)) // Cyan

                    Text("CONECTAR")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Toca abajo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
            } else {
                // Base del anillo oscura
                Circle()
                    .stroke(Color(white: 0.12), lineWidth: lineWidth)
                    .frame(width: size, height: size)

                // Segmentos de cada activo según su porcentaje
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    DonutSliceShape(startAngle: slice.startAngle, endAngle: slice.endAngle)
                        .stroke(
                            slice.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                        .frame(width: size, height: size)
                }

                // Centro de la gráfica (Totales)
                VStack(spacing: 2) {
                    Text("PORTAFOLIO")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color(white: 0.55))

                    Text(formattedValue(totalValue))
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Image(systemName: totalPnlPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .black))

                        Text(String(format: "%@%.1f%%", totalPnlPct >= 0 ? "+" : "", totalPnlPct))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(totalPnlPct >= 0 ? Color(red: 0.0, green: 0.9, blue: 0.46) : Color(red: 1.0, green: 0.35, blue: 0.37))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (totalPnlPct >= 0 ? Color(red: 0.0, green: 0.4, blue: 0.2) : Color(red: 0.4, green: 0.1, blue: 0.1))
                            .opacity(0.35)
                    )
                    .clipShape(Capsule())
                }
                .frame(width: size - (lineWidth * 2) - 10)
            }
        }
        .frame(width: size + 16, height: size + 16)
    }

    private func formattedValue(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(currencySymbol)\(Int(val))"
    }

    private struct SliceData {
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
                let end = Angle(degrees: currentAngle + sweep - 1.5) // 1.5 deg separación
                result.append(SliceData(startAngle: start, endAngle: end, color: item.uiColor))
                currentAngle += sweep
            }
        }
        return result
    }
}

// MARK: - Forma geométrica para trazar cada arco en SwiftUI (iOS 15)
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
