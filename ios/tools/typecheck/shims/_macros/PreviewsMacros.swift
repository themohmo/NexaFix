import Foundation
@_spi(PluginMessage) import SwiftCompilerPluginMessageHandling
import SwiftSyntax
import SwiftSyntaxMacros

public struct PreviewMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        var args: [String] = []
        for a in node.arguments {
            let label = a.label.map { $0.text + ": " } ?? ""
            args.append(label + a.expression.description)
        }
        let body = node.trailingClosure?.description ?? "{ EmptyView() }"
        let first = args.isEmpty ? "" : args.joined(separator: ", ") + ", "
        // a global declaration has to bind a name; one unique name per expansion keeps several #Previews per file apart
        let name = context.makeUniqueName("preview")
        return ["@MainActor private let \(name) = SwiftUI.Preview(\(raw: first)body: { SwiftUI._previewBody \(raw: body) })"]
    }
}

struct Connection: MessageConnection {
    func sendMessage<TX: Encodable>(_ message: TX) throws {
        let payload = try JSONEncoder().encode(message)
        var header = UInt64(payload.count).littleEndian
        withUnsafeBytes(of: &header) { _ = fwrite($0.baseAddress, 1, 8, stdout) }
        payload.withUnsafeBytes { _ = fwrite($0.baseAddress, 1, payload.count, stdout) }
        fflush(stdout)
    }
    func waitForNextMessage<RX: Decodable>(_ type: RX.Type) throws -> RX? {
        var header: UInt64 = 0
        let got = withUnsafeMutableBytes(of: &header) { fread($0.baseAddress, 1, 8, stdin) }
        if got < 8 { return nil }
        let n = Int(UInt64(littleEndian: header))
        var buf = [UInt8](repeating: 0, count: n)
        var off = 0
        while off < n {
            let r = buf.withUnsafeMutableBytes { fread($0.baseAddress! + off, 1, n - off, stdin) }
            if r == 0 { return nil }
            off += r
        }
        return try JSONDecoder().decode(RX.self, from: Data(buf))
    }
}

struct Provider: PluginProvider {
    func resolveMacro(moduleName: String, typeName: String) throws -> any Macro.Type {
        guard typeName == "PreviewMacro" else { throw NSError(domain: "PreviewsMacros", code: 1) }
        return PreviewMacro.self
    }
}

@main struct Main {
    static func main() {
        CompilerPluginMessageListener(connection: Connection(), provider: Provider()).main()
    }
}
