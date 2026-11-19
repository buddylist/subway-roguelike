import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

struct Bullet: View {
    let line: Line
    var size: CGFloat = 34
    var body: some View {
        Text(line.id)
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(line.id == "R" ? .black : .white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: line.colorHex)))
    }
}

struct UnitCard: View {
    let unit: Unit
    var mystery = false
    var dimmed = false
    var body: some View {
        VStack(spacing: 2) {
            Text(mystery ? "📦" : unit.emoji).font(.system(size: 30))
            Text(mystery ? "???" : unit.name).font(.caption2).lineLimit(1)
            Text(mystery ? "?/?" : "\(unit.atk)⚔️ \(max(0, unit.hp))❤️").font(.caption.bold())
            if unit.lv > 1 && !mystery { Text("★\(unit.lv)").font(.caption2).foregroundStyle(.yellow) }
        }
        .frame(width: 76, height: 96)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .opacity(dimmed ? 0.35 : 1)
    }
}

struct Hud: View {
    @EnvironmentObject var game: Game
    var body: some View {
        HStack(spacing: 14) {
            Label("\(game.gold)", systemImage: "dollarsign.circle")
            Label(String(repeating: "●", count: max(0, game.swipes)) + String(repeating: "○", count: max(0, 3 - game.swipes)), systemImage: "creditcard")
            Label("\(game.wins)W", systemImage: "trophy")
            Spacer()
            Text("round \(game.round)").foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
