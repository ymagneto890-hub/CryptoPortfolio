import Foundation
import SwiftUI

// MARK: - Modelos de Datos del Portafolio (100% Anónimos en Git)

public struct RawPosition: Codable {
    public let coin: String
    public let name: String
    public let icon: String
    public let color: String
    public let source: String
    public let yahoo_sym: String?
    public let yahoo_sym_eur: String?
    public let invested: Double
    public let entry_price: Double
    public let currency: String
}

public struct PortfolioPayload: Codable {
    public var updated_at: String
    public var currency: String
    public var currency_symbol: String
    public var total_invested: Double
    public var total_value: Double
    public var total_pnl: Double
    public var total_pnl_pct: Double
    public var items: [PortfolioItem]
    public var positions: [RawPosition]?

    public init(
        updated_at: String = "",
        currency: String = "USD",
        currency_symbol: String = "$",
        total_invested: Double = 0.0,
        total_value: Double = 0.0,
        total_pnl: Double = 0.0,
        total_pnl_pct: Double = 0.0,
        items: [PortfolioItem] = [],
        positions: [RawPosition]? = nil
    ) {
        self.updated_at = updated_at
        self.currency = currency
        self.currency_symbol = currency_symbol
        self.total_invested = total_invested
        self.total_value = total_value
        self.total_pnl = total_pnl
        self.total_pnl_pct = total_pnl_pct
        self.items = items
        self.positions = positions
    }
}

public struct PortfolioItem: Identifiable, Codable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let icon: String
    public let color: String
    public var invested: Double
    public var value: Double
    public var pnl: Double
    public var pnl_pct: Double
    public var share_pct: Double
    public var current_price: Double?

    public init(
        symbol: String,
        name: String,
        icon: String,
        color: String,
        invested: Double,
        value: Double,
        pnl: Double,
        pnl_pct: Double,
        share_pct: Double,
        current_price: Double? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.icon = icon
        self.color = color
        self.invested = invested
        self.value = value
        self.pnl = pnl
        self.pnl_pct = pnl_pct
        self.share_pct = share_pct
        self.current_price = current_price
    }

    public var uiColor: Color {
        Color(hex: color)
    }
}

// MARK: - Extensión SwiftUI Color desde HEX
extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 243, 186, 47) // Fallback dorado
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
