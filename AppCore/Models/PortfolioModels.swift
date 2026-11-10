import Foundation
import SwiftUI

// MARK: - Estado de Valoración de la Cartera
public enum ValuationStatus: String, Codable, Equatable {
    case complete = "complete"      // Todos los activos tienen cotización verificada y reciente
    case partial = "partial"        // Solo algunos activos tienen cotización verificada
    case unvalued = "unvalued"      // Ningún activo tiene cotización de mercado verificada
}

// MARK: - Modelos de Datos del Portafolio (100% Anónimos en Git)

public struct RawPosition: Codable, Equatable {
    public let coin: String
    public let name: String
    public let icon: String
    public let color: String
    public let source: String
    public let yahoo_sym: String?
    public let yahoo_sym_eur: String?
    public let invested: Double
    public let entry_price: Double? // Opcional: una inversión válida no se pierde si falta el precio de entrada
    public let currency: String

    public init(
        coin: String,
        name: String,
        icon: String,
        color: String,
        source: String,
        yahoo_sym: String? = nil,
        yahoo_sym_eur: String? = nil,
        invested: Double,
        entry_price: Double? = nil,
        currency: String
    ) {
        self.coin = coin
        self.name = name
        self.icon = icon
        self.color = color
        self.source = source
        self.yahoo_sym = yahoo_sym
        self.yahoo_sym_eur = yahoo_sym_eur
        self.invested = invested
        self.entry_price = entry_price
        self.currency = currency
    }

    private enum CodingKeys: String, CodingKey {
        case coin, name, icon, color, source, yahoo_sym, yahoo_sym_eur, invested, entry_price, currency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(String.self, forKey: .coin)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        source = try container.decode(String.self, forKey: .source)
        yahoo_sym = try container.decodeIfPresent(String.self, forKey: .yahoo_sym)
        yahoo_sym_eur = try container.decodeIfPresent(String.self, forKey: .yahoo_sym_eur)
        invested = try container.decodeIfPresent(Double.self, forKey: .invested) ?? 0.0
        entry_price = try container.decodeIfPresent(Double.self, forKey: .entry_price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
    }
}

public struct MarketQuote: Codable, Equatable {
    public let symbol: String
    public let price: Double
    public let currency: String   // e.g. "USD", "EUR", "GBP", "GBp", "USDT"
    public let timestamp: Date
    public let source: String     // e.g. "binance", "yahoo"
    public let isVerifiedTimestamp: Bool

    public init(
        symbol: String,
        price: Double,
        currency: String,
        timestamp: Date = Date(),
        source: String = "unknown",
        isVerifiedTimestamp: Bool = true
    ) {
        self.symbol = symbol
        self.price = price
        self.currency = currency
        self.timestamp = timestamp
        self.source = source
        self.isVerifiedTimestamp = isVerifiedTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case symbol, price, currency, timestamp, source, isVerifiedTimestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        price = try container.decode(Double.self, forKey: .price)
        currency = try container.decode(String.self, forKey: .currency)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        isVerifiedTimestamp = try container.decodeIfPresent(Bool.self, forKey: .isVerifiedTimestamp) ?? false
    }
}

public struct PortfolioPayload: Codable, Equatable {
    public var updated_at: String
    public var currency: String
    public var currency_symbol: String
    public var total_invested: Double
    public var investmentTotalIsComplete: Bool
    public var total_value: Double?
    public var total_pnl: Double?
    public var total_pnl_pct: Double?
    public var valuation_status: ValuationStatus
    public var valued_count: Int
    public var total_count: Int
    public var liquidity: Double
    public var base_liquidity: Double?
    public var items: [PortfolioItem]
    public var positions: [RawPosition]?

    public var immutableBaseLiquidityEUR: Double {
        base_liquidity ?? liquidity
    }

    public init(
        updated_at: String = "",
        currency: String = "EUR",
        currency_symbol: String = "€",
        total_invested: Double = 0.0,
        investmentTotalIsComplete: Bool = true,
        total_value: Double? = nil,
        total_pnl: Double? = nil,
        total_pnl_pct: Double? = nil,
        valuation_status: ValuationStatus = .unvalued,
        valued_count: Int = 0,
        total_count: Int = 0,
        liquidity: Double = 0.0,
        base_liquidity: Double? = nil,
        items: [PortfolioItem] = [],
        positions: [RawPosition]? = nil
    ) {
        self.updated_at = updated_at
        self.currency = currency
        self.currency_symbol = currency_symbol
        self.total_invested = total_invested
        self.investmentTotalIsComplete = investmentTotalIsComplete
        self.total_value = total_value
        self.total_pnl = total_pnl
        self.total_pnl_pct = total_pnl_pct
        self.valuation_status = valuation_status
        self.valued_count = valued_count
        self.total_count = total_count
        self.liquidity = liquidity
        self.base_liquidity = base_liquidity
        self.items = items
        self.positions = positions
    }

    private enum CodingKeys: String, CodingKey {
        case updated_at, currency, currency_symbol, total_invested, investmentTotalIsComplete, total_value
        case total_pnl, total_pnl_pct, valuation_status, valued_count, total_count
        case liquidity, base_liquidity, items, positions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updated_at = try container.decodeIfPresent(String.self, forKey: .updated_at) ?? ""
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        currency_symbol = try container.decodeIfPresent(String.self, forKey: .currency_symbol) ?? "€"
        total_invested = try container.decodeIfPresent(Double.self, forKey: .total_invested) ?? 0.0
        investmentTotalIsComplete = try container.decodeIfPresent(Bool.self, forKey: .investmentTotalIsComplete) ?? true
        total_value = try container.decodeIfPresent(Double.self, forKey: .total_value)
        total_pnl = try container.decodeIfPresent(Double.self, forKey: .total_pnl)
        total_pnl_pct = try container.decodeIfPresent(Double.self, forKey: .total_pnl_pct)
        valuation_status = try container.decodeIfPresent(ValuationStatus.self, forKey: .valuation_status) ?? .unvalued
        valued_count = try container.decodeIfPresent(Int.self, forKey: .valued_count) ?? 0
        total_count = try container.decodeIfPresent(Int.self, forKey: .total_count) ?? 0
        liquidity = try container.decodeIfPresent(Double.self, forKey: .liquidity) ?? 0.0
        base_liquidity = try container.decodeIfPresent(Double.self, forKey: .base_liquidity)
        items = try container.decodeIfPresent([PortfolioItem].self, forKey: .items) ?? []
        positions = try container.decodeIfPresent([RawPosition].self, forKey: .positions)
    }
}

public struct PortfolioItem: Identifiable, Codable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let icon: String
    public let color: String
    public var invested: Double
    public var value: Double?
    public var pnl: Double?
    public var pnl_pct: Double?
    public var share_pct: Double
    public var current_price: Double?
    public var investmentConversionAvailable: Bool

    public init(
        symbol: String,
        name: String,
        icon: String,
        color: String,
        invested: Double,
        value: Double? = nil,
        pnl: Double? = nil,
        pnl_pct: Double? = nil,
        share_pct: Double = 0.0,
        current_price: Double? = nil,
        investmentConversionAvailable: Bool = true
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
        self.investmentConversionAvailable = investmentConversionAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case symbol, name, icon, color, invested, value, pnl, pnl_pct, share_pct, current_price, investmentConversionAvailable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        invested = try container.decodeIfPresent(Double.self, forKey: .invested) ?? 0.0
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        pnl = try container.decodeIfPresent(Double.self, forKey: .pnl)
        pnl_pct = try container.decodeIfPresent(Double.self, forKey: .pnl_pct)
        share_pct = try container.decodeIfPresent(Double.self, forKey: .share_pct) ?? 0.0
        current_price = try container.decodeIfPresent(Double.self, forKey: .current_price)
        investmentConversionAvailable = try container.decodeIfPresent(Bool.self, forKey: .investmentConversionAvailable) ?? true
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
