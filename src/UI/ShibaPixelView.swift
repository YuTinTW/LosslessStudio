import SwiftUI

public enum ShibaAnimationState: String, CaseIterable, Identifiable {
    case idle = "Idle"
    case converting = "Converting"
    case completed = "Completed"
    case failed = "Failed"
    
    public var id: String { rawValue }
}

public struct ShibaPixelView: View {
    public var state: ShibaAnimationState
    public var pixelSize: CGFloat = 5
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(state: ShibaAnimationState, pixelSize: CGFloat = 5) {
        self.state = state
        self.pixelSize = pixelSize
    }
    
    public var body: some View {
        TimelineView(.periodic(from: .now, by: frameInterval)) { timeline in
            Canvas { context, size in
                let frameIndex = currentFrameIndex(at: timeline.date)
                drawScene(context: &context, size: size, frame: frameIndex)
            }
            .frame(width: 16 * pixelSize, height: 16 * pixelSize)
        }
        .accessibilityLabel(accessibilityDescription)
    }
    
    private var frameInterval: TimeInterval {
        if reduceMotion { return 60.0 }
        switch state {
        case .idle: return 0.45
        case .converting: return 0.14
        case .completed: return 0.25
        case .failed: return 0.35
        }
    }
    
    private func currentFrameIndex(at date: Date) -> Int {
        guard !reduceMotion else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        let step = Int(floor(elapsed / frameInterval))
        switch state {
        case .idle: return step % 2
        case .converting: return step % 4
        case .completed: return step % 2
        case .failed: return step % 2
        }
    }
    
    private var accessibilityDescription: Text {
        switch state {
        case .idle: return Text("柴犬待機中")
        case .converting: return Text("柴犬轉檔中")
        case .completed: return Text("轉檔完成")
        case .failed: return Text("轉檔失敗或警告")
        }
    }
    
    // MARK: - Palette (日系奶油白與暖橘原創配色)
    private func color(for code: Character) -> Color? {
        switch code {
        case "O": return Color(red: 0.91, green: 0.51, blue: 0.23) // 暖橘 #E8823A
        case "D": return Color(red: 0.72, green: 0.38, blue: 0.15) // 暗橘陰影
        case "W": return Color(red: 0.98, green: 0.97, blue: 0.96) // 奶油白 #FAF8F5
        case "K": return Color(red: 0.23, green: 0.21, blue: 0.20) // 軟炭黑 #3A3532
        case "P": return Color(red: 0.96, green: 0.62, blue: 0.66) // 腮紅/舌頭粉
        case "Y": return Color(red: 0.95, green: 0.75, blue: 0.25) // 星星金黃
        case "B": return Color(red: 0.45, green: 0.70, blue: 0.90) // 汗滴淡藍
        case "R": return Color(red: 0.90, green: 0.35, blue: 0.35) // 錯誤紅
        case "G": return Color(red: 0.35, green: 0.80, blue: 0.55) // 成功綠
        default: return nil
        }
    }
    
    // MARK: - Drawing
    private func drawScene(context: inout GraphicsContext, size: CGSize, frame: Int) {
        let grid = spriteGrid(for: state, frame: frame)
        
        for (rowIndex, rowString) in grid.enumerated() {
            for (colIndex, char) in rowString.enumerated() {
                guard let fill = color(for: char) else { continue }
                let rect = CGRect(
                    x: CGFloat(colIndex) * pixelSize,
                    y: CGFloat(rowIndex) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(Path(rect), with: .color(fill))
            }
        }
    }
    
    // MARK: - 16x16 Pixel Grids
    private func spriteGrid(for state: ShibaAnimationState, frame: Int) -> [String] {
        switch state {
        case .idle:
            return frame == 0 ? idleFrame0 : idleFrame1
        case .converting:
            switch frame {
            case 0: return convertingFrame0
            case 1: return convertingFrame1
            case 2: return convertingFrame2
            default: return convertingFrame3
            }
        case .completed:
            return frame == 0 ? completedFrame0 : completedFrame1
        case .failed:
            return frame == 0 ? failedFrame0 : failedFrame1
        }
    }
    
    // Idle: 坐姿搖尾呼吸
    private let idleFrame0: [String] = [
        "................",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOWWOOOOWWOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWWWWO....",
        "....OOOOOOO...O.",
        "...OOWWWWWOO.OO.",
        "...OOWWWWWOOO...",
        "...OOOOOOOOO....",
        "...OOW...WOO....",
        "...WW.....WW....",
        "................",
        "................"
    ]
    
    private let idleFrame1: [String] = [
        "................",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOWWOOOOWWOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWWWWO....",
        "....OOOOOOO..OO.",
        "...OOWWWWWOO..O.",
        "...OOWWWWWOOO...",
        "...OOOOOOOOO....",
        "...OOW...WOO....",
        "...WW.....WW....",
        "................",
        "................"
    ]
    
    // Converting: 奮力轉檔小跑步
    private let convertingFrame0: [String] = [
        "................",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWWWWO....",
        "....OOOOOO......",
        "..OOOOOOOOOOO...",
        ".OOWWWWWWWWWOOO.",
        "..OOOOOOOOOOO.O.",
        "...OO.....OO....",
        "...WW.....WW....",
        "................",
        "................",
        "................"
    ]
    
    private let convertingFrame1: [String] = [
        "....YYYY........",
        "................",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWWWWO....",
        "....OOOOOO..OO..",
        "..OOOOOOOOOOOO..",
        ".OOWWWWWWWWWOO..",
        "..OOOOOOOOOOOO..",
        "....OO...OO.....",
        "....WW...WW.....",
        "................",
        "................"
    ]
    
    private let convertingFrame2: [String] = [
        "....YYYY........",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWWWWO....",
        "....OOOOOO......",
        "..OOOOOOOOOOO...",
        ".OOWWWWWWWWWOOO.",
        "..OOOOOOOOOOO.O.",
        "...OO.....OO....",
        "..WW.......WW...",
        "................",
        "................",
        "................"
    ]
    
    private let convertingFrame3: [String] = [
        "......YYYY......",
        "................",
        "..OO........OO..",
        "..OOO......OOO..",
        "..OOOOWWWWOOOO..",
        "..OOKOOOOOOKOO..",
        "..OOPOWWWWPOWO..",
        "...OOWWWPWWO....",
        "....OOOOOO..OO..",
        "..OOOOOOOOOOOO..",
        ".OOWWWWWWWWWOO..",
        "..OOOOOOOOOOOO..",
        ".....OO.OO......",
        ".....WW.WW......",
        "................",
        "................"
    ]
    
    // Completed: 開心笑眼 + 吐舌 + 閃耀星星
    private let completedFrame0: [String] = [
        ".Y............G.",
        "YJY.OO....OO....",
        ".Y..OOO..OOO....",
        "...OOOOWWOOOO...",
        "...OOWOOOOOWO...",
        "...OKKOOOOKKO...",
        "...OPOWWWWPWO...",
        "....OWWWKWWO....",
        "....OOOOOOO..OO.",
        "...OOWWWWWOO.OO.",
        "...OOWWWWWOOO...",
        "...OOOOOOOOO....",
        "...OOW...WOO....",
        "...WW.....WW....",
        "................",
        "................"
    ]
    
    private let completedFrame1: [String] = [
        ".......G......Y.",
        "....OO....OO.YJY",
        "....OOO..OOO..Y.",
        "...OOOOWWOOOO...",
        "...OOWOOOOOWO...",
        "...OKKOOOOKKO...",
        "...OPOWWWWPWO...",
        "....OWWWPWWO.OO.",
        "....OOOOOOO..OO.",
        "...OOWWWWWOOO...",
        "...OOWWWWWOO....",
        "...OOOOOOOOO....",
        "..WW.......WW...",
        "................",
        "................",
        "................"
    ]
    
    // Failed: 垂耳趴地 + 叉叉眼 + 汗滴與錯誤標記
    private let failedFrame0: [String] = [
        ".......RR.......",
        "......RRRR......",
        ".......RR....B..",
        "............BB..",
        ".DDD........DDD.",
        "DOOOD..WW..DOOOD",
        ".OOOOOWWWWOOOOO.",
        "..OOKOKOOKOKOO..",
        "..OOOOOWWWWOOO..",
        "...OOWWWWWWWOO..",
        "..OOOOOOOOOOOOO.",
        ".OOWWWWWWWWWWWOO",
        ".WWWWWWWWWWWWWWW",
        "................",
        "................",
        "................"
    ]
    
    private let failedFrame1: [String] = [
        "................",
        ".......RR.......",
        "......RRRR......",
        ".......RR....B..",
        ".DDD........DDD.",
        "DOOOD..WW..DOOOD",
        ".OOOOOWWWWOOOOO.",
        "..OOKOKOOKOKOO..",
        "..OOOOOWWWWOOO..",
        "...OOWWWWWWWOO..",
        "..OOOOOOOOOOOOO.",
        ".OOWWWWWWWWWWWOO",
        ".WWWWWWWWWWWWWWW",
        "................",
        "................",
        "................"
    ]
}
