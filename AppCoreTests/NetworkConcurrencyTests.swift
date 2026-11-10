import XCTest
import Foundation
@testable import AppCore

private final class DelayedNetworkURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var started: XCTestExpectation?
    private static var stopped: XCTestExpectation?
    private let stateLock = NSLock()
    private var cancelled = false

    static func configure(started: XCTestExpectation, stopped: XCTestExpectation) {
        lock.lock()
        self.started = started
        self.stopped = stopped
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let expectation = Self.started
        Self.lock.unlock()
        expectation?.fulfill()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let wasCancelled = self.cancelled
            self.stateLock.unlock()
            guard !wasCancelled,
                  let url = self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("{}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
        Self.lock.lock()
        let expectation = Self.stopped
        Self.lock.unlock()
        expectation?.fulfill()
    }
}

final class NetworkConcurrencyTests: XCTestCase {
    func testBackgroundCancelsRealInFlightURLSessionTasks() {
        let started = expectation(description: "Both network requests started")
        started.expectedFulfillmentCount = 2
        let stopped = expectation(description: "Both network requests cancelled")
        stopped.expectedFulfillmentCount = 2
        DelayedNetworkURLProtocol.configure(started: started, stopped: stopped)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedNetworkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let viewModel = PortfolioViewModel(startAutomatically: false, session: session)
        viewModel.portfolio = PortfolioPayload(currency: "EUR", positions: [
            RawPosition(coin: "BTC", name: "Bitcoin", icon: "₿", color: "#F3BA2F",
                        source: "binance", invested: 100, entry_price: 50000, currency: "EUR")
        ])

        viewModel.updateLivePricesFromInternet()
        wait(for: [started], timeout: 3.0)
        viewModel.applicationWillResignActive()
        wait(for: [stopped], timeout: 3.0)

        XCTAssertFalse(viewModel.isUpdatingPrices)
        XCTAssertTrue(viewModel.lastKnownQuotes.isEmpty)
        session.invalidateAndCancel()
    }
}
