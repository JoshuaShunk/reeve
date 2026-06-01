import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// VNC Authentication (RFB security type 2): the server sends a 16-byte
/// challenge; the client returns it DES-encrypted with a key derived from the
/// password. Proxmox uses the one-time vncproxy ticket as that password.
public enum VNCAuth {
    /// Build the 16-byte challenge response. The password is truncated/zero-padded
    /// to 8 bytes and, per the long-standing VNC quirk, each key byte's bits are
    /// reversed before use. The 16-byte challenge is encrypted as two independent
    /// DES-ECB blocks.
    public static func response(challenge: Data, password: String) -> Data {
        var key = [UInt8](repeating: 0, count: 8)
        let passwordBytes = Array(password.utf8)
        for index in 0..<8 where index < passwordBytes.count {
            key[index] = reverseBits(passwordBytes[index])
        }

        let input = [UInt8](challenge)
        guard input.count == 16 else { return Data() }

        #if canImport(CommonCrypto)
        var output = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = key.withUnsafeBytes { keyPtr in
            input.withUnsafeBytes { inputPtr in
                CCCrypt(
                    CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES),
                    CCOptions(kCCOptionECBMode),
                    keyPtr.baseAddress, 8,
                    nil,
                    inputPtr.baseAddress, 16,
                    &output, 16, &moved
                )
            }
        }
        guard status == kCCSuccess else { return Data() }
        return Data(output)
        #else
        return Data()
        #endif
    }

    /// Reverse the bit order within a byte (0b10000000 → 0b00000001).
    static func reverseBits(_ byte: UInt8) -> UInt8 {
        var value = byte
        var result: UInt8 = 0
        for _ in 0..<8 {
            result = (result << 1) | (value & 1)
            value >>= 1
        }
        return result
    }
}
