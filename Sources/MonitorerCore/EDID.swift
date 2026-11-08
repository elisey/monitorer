import Foundation

public enum EDID {
    private static let descriptorOffsets = [54, 72, 90, 108]
    private static let descriptorLength = 18
    private static let displayNameTag: UInt8 = 0xFC

    /// Returns the monitor name from the display name descriptor of an EDID base block.
    public static func displayName(_ edid: [UInt8]) -> String? {
        for offset in descriptorOffsets where edid.count >= offset + descriptorLength {
            let descriptor = Array(edid[offset..<(offset + descriptorLength)])
            guard descriptor[0] == 0, descriptor[1] == 0, descriptor[3] == displayNameTag else {
                continue
            }
            let text = descriptor[5...].prefix { $0 != 0x0A }
            return String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
