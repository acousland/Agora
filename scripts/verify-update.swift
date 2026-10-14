import CryptoKit
import Foundation

// Verify against the public key shipped to users, independently of the signing keychain.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[2]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
    fatalError("Usage: verify-update.swift archive public-key-base64 signature-base64")
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
guard publicKey.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("Update signature does not match Agora's published public key.\n".utf8))
    exit(1)
}
print("Update signature verified against Agora's published public key.")
