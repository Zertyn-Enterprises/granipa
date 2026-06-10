import Foundation
import Network

actor APIServer {
    private var listener: NWListener?

    func start(
        port: UInt16,
        token: String,
        database: AppDatabase,
        enhanceTrigger: @escaping @Sendable (String) -> Void
    ) throws {
        stopListener()

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port) ?? 7799)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            Self.handle(
                connection: connection,
                token: token,
                database: database,
                enhanceTrigger: enhanceTrigger)
        }
        listener.start(queue: DispatchQueue(label: "com.zertyn.granipa.api"))
        self.listener = listener
    }

    func stop() {
        stopListener()
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    private static func handle(
        connection: NWConnection,
        token: String,
        database: AppDatabase,
        enhanceTrigger: @escaping @Sendable (String) -> Void
    ) {
        connection.start(queue: DispatchQueue(label: "com.zertyn.granipa.api.conn"))
        receive(connection: connection, buffer: Data()) { request in
            let response: HTTPResponse
            if let request {
                response = APIRouter.route(
                    request, token: token, database: database, enhanceTrigger: enhanceTrigger)
            } else {
                response = .error(400, "Malformed request.")
            }
            connection.send(
                content: response.serialize(),
                completion: .contentProcessed { _ in
                    connection.cancel()
                })
        }
    }

    private static func receive(
        connection: NWConnection,
        buffer: Data,
        completion: @escaping @Sendable (HTTPRequest?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            data, _, isComplete, error in
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > 4 << 20 || error != nil {
                completion(nil)
                return
            }
            if let headerEnd = HTTPRequest.headerEndRange(in: buffer) {
                let expectedBody = HTTPRequest.contentLength(
                    fromHeaderData: buffer[buffer.startIndex..<headerEnd.lowerBound])
                let received = buffer.distance(from: headerEnd.upperBound, to: buffer.endIndex)
                if received >= expectedBody {
                    completion(HTTPRequest.parse(buffer))
                    return
                }
            }
            if isComplete {
                completion(HTTPRequest.parse(buffer))
                return
            }
            receive(connection: connection, buffer: buffer, completion: completion)
        }
    }
}
