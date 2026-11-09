import SwiftUI

// MARK: - Gráfica Redonda XL Interactiva para iPhone SE (4 pulgadas)
public struct DonutChartView: View {
    public let items: [PortfolioItem]
    public let totalValue: Double?
    public let totalPnl: Double?
    public let totalPnlPct: Double?
    public let currencySymbol: String
    public let valuationStatus: ValuationStatus
    public let valuedCount: Int
    public let totalCount: Int
    public let selectedSymbol: String?
    public let isWaitingFirstSync: Bool
    public var onCenterTap: (() -> Void)? = nil

    private let size: CGFloat = 182
    private let lineWidth: CGFloat = 20

    public init(
        items: [PortfolioItem],
        totalValue: Double?,
        totalPnl: Double? = nil,
        totalPnlPct: Double? = nil,
        currencySymbol: String,
        valuationStatus: ValuationStatus = .complete,
        valuedCount: Int = 0,
        totalCount: Int = 0,
        selectedSymbol: String? = nil,
        isWaitingFirstSync: Bool = false,
        onCenterTap: (() -> Void)? = nil
    ) {
        self.items = items
        self.totalValue = totalValue
        self.totalPnl = totalPnl
        self.totalPnlPct = totalPnlPct
        self.currencySymbol = currencySymbol
        self.valuationStatus = valuationStatus
        self.valuedCount = valuedCount
        self.totalCount = totalCount
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

                // Segmentos de cada activo con distribución matemática coherente
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

                        if let val = item.value {
                            Text(formattedValue(val))
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        } else {
                            Text("—")
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(white: 0.6))
                        }

                        Text(item.investmentConversionAvailable ? "Inv: \(formattedValue(item.invested))" : "Inv: —")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(white: 0.68))

                        if let pct = item.pnl_pct {
                            Text(String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    (pct >= 0 ? Color(red: 0.0, green: 0.45, blue: 0.22) : Color(red: 0.45, green: 0.1, blue: 0.1))
                                        .opacity(0.45)
                                )
                                .clipShape(Capsule())
                        } else {
                            Text("Sin cotización")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(white: 0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(white: 0.2).opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(width: size - (lineWidth * 2) - 8)
                    .contentShape(Circle())
                    .onTapGesture {
                        onCenterTap?()
                    }
                } else {
                    VStack(spacing: 3) {
                        // Título del portafolio: Indica expresamente si la valoración es parcial
                        Text(valuationStatus == .partial ? "PARCIAL (\(valuedCount)/\(totalCount))" : "PORTAFOLIO")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundColor(valuationStatus == .partial ? Color(red: 1.0, green: 0.78, blue: 0.28) : Color(white: 0.6))

                        if let tVal = totalValue {
                            Text(formattedValue(tVal))
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        } else {
                            Text("—")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(white: 0.6))
                        }

                        // Badge inferior: Distingue rigurosamente Complete, Partial y Unvalued
                        switch valuationStatus {
                        case .complete:
                            if let pnl = totalPnl, let pct = totalPnlPct {
                                HStack(spacing: 3) {
                                    Text(String(format: "%@%@ (%@%.1f%%)",
                                                pnl >= 0 ? "+" : "-",
                                                formattedValue(abs(pnl)),
                                                pct >= 0 ? "+" : "",
                                                pct))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .foregroundColor(pct >= 0 ? Color(red: 0.0, green: 0.95, blue: 0.5) : Color(red: 1.0, green: 0.42, blue: 0.44))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    (pct >= 0 ? Color(red: 0.0, green: 0.45, blue: 0.22) : Color(red: 0.45, green: 0.1, blue: 0.1))
                                        .opacity(0.45)
                                )
                                .clipShape(Capsule())
                            }

                        case .partial:
                            // Indica que la cifra central representa únicamente los activos con cotización
                            Text("Subtotal cotizados")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.28))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.4, green: 0.3, blue: 0.08).opacity(0.50))
                                .clipShape(Capsule())

                        case .unvalued:
                            Text("Sin cotización")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(white: 0.65))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.2).opacity(0.45))
                                .clipShape(Capsule())
                        }
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
