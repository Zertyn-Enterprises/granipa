import SwiftUI

enum MeetingSparkline {
    static func samples(id: String, count: Int = 52) -> [CGFloat] {
        var hash: UInt64 = 5_381
        for byte in id.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        var values: [CGFloat] = []
        values.reserveCapacity(count)
        var state = hash == 0 ? 1 : hash
        for i in 0..<count {
            state = state &* 1_103_515_245 &+ 12_345
            let noise = CGFloat((state >> 16) & 0x7FFF) / 32_767
            let envelope = sin(CGFloat(i) / CGFloat(max(count - 1, 1)) * .pi)
            values.append(0.12 + envelope * (0.22 + 0.66 * noise))
        }
        return values
    }
}

struct MeetingSparklineView: View {
    let seed: String
    var color: Color = Color.white.opacity(0.28)

    var body: some View {
        let samples = MeetingSparkline.samples(id: seed)
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let step = size.width / CGFloat(samples.count)
            let barWidth = max(1, step * 0.58)
            for (index, value) in samples.enumerated() {
                let height = 3 + value * 15
                let rect = CGRect(
                    x: CGFloat(index) * step,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .frame(width: 148, height: 18)
        .accessibilityHidden(true)
    }
}

struct MeetingGlyph: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.fillSubtle)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "doc.fill")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
    }
}
