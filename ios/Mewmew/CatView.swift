import SwiftUI

struct CatView: View {
    let mood: String
    let outfit: String
    let isAnimated: Bool

    @State private var tailIsRaised = false
    @State private var isBreathingIn = false
    @State private var isBlinking = false

    init(
        mood: String,
        outfit: String,
        isAnimated: Bool = true
    ) {
        self.mood = mood
        self.outfit = outfit
        self.isAnimated = isAnimated
    }

    var body: some View {
        ZStack {
            tail
            bodyShape
            ears
            head
            face
            outfitLayer
        }
        .frame(width: 240, height: 240)
        .scaleEffect(breathingScale)
        .animation(
            isAnimated && mood == "sleepy"
                ? .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
                : nil,
            value: isBreathingIn
        )
        .task(id: animationKey) {
            tailIsRaised = false
            isBreathingIn = false
            isBlinking = false
            guard isAnimated else { return }

            switch mood {
            case "happy":
                tailIsRaised = true
            case "content":
                await blinkOccasionally()
            case "sleepy":
                isBreathingIn = true
            default:
                break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var tail: some View {
        CatTailShape()
            .stroke(
                Theme.accent,
                style: StrokeStyle(lineWidth: 18, lineCap: .round)
            )
            .rotationEffect(
                .degrees(tailAngle),
                anchor: UnitPoint(x: 0.69, y: 0.74)
            )
            .animation(
                isAnimated && mood == "happy"
                    ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                    : nil,
                value: tailIsRaised
            )
    }

    private var bodyShape: some View {
        Ellipse()
            .fill(Theme.accent)
            .frame(width: 112, height: 106)
            .offset(y: 56)
    }

    private var ears: some View {
        CatEarsShape()
            .fill(Theme.accent)
    }

    private var head: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 154, height: 154)
            .offset(y: -28)
    }

    @ViewBuilder
    private var face: some View {
        if mood != "sleepy" && !isBlinking {
            // Happy eyes sit wider open than content ones, so the two moods
            // still differ when nothing is moving.
            let eyeSize: CGFloat = mood == "happy" ? 11 : 7
            HStack(spacing: mood == "happy" ? 38 : 42) {
                Circle()
                    .frame(width: eyeSize, height: eyeSize)
                Circle()
                    .frame(width: eyeSize, height: eyeSize)
            }
            .foregroundStyle(Theme.primaryText)
            .offset(y: -34)
        } else {
            CatClosedEyesShape()
                .stroke(
                    Theme.primaryText,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 88, height: 18)
                .offset(y: -31)
        }

        CatNoseShape()
            .fill(Theme.primaryText)
            .frame(width: 12, height: 8)
            .offset(y: -10)
    }

    @ViewBuilder
    private var outfitLayer: some View {
        switch outfit {
        case "scarf":
            scarf
        case "glasses":
            glasses
        default:
            EmptyView()
        }
    }

    private var scarf: some View {
        ZStack {
            // Hanging end first, so the band overlaps its top and the two
            // read as one piece of cloth rather than a cross.
            Capsule()
                .fill(Color.white)
                .frame(width: 15, height: 44)
                .rotationEffect(.degrees(-13))
                .offset(x: 30, y: 22)

            Capsule()
                .fill(Color.white)
                .frame(width: 108, height: 18)
        }
        .offset(y: 40)
    }

    private var glasses: some View {
        HStack(spacing: 7) {
            Circle()
                .stroke(Theme.primaryText, lineWidth: 4)
                .frame(width: 43, height: 43)
            Rectangle()
                .fill(Theme.primaryText)
                .frame(width: 12, height: 4)
            Circle()
                .stroke(Theme.primaryText, lineWidth: 4)
                .frame(width: 43, height: 43)
        }
        .offset(y: -31)
    }

    private var tailAngle: Double {
        // Mood sets the resting angle so a still frame still reads as an alert
        // or a dozing cat; the wag only swings around that rest.
        guard mood == "happy" else { return 0 }
        guard isAnimated else { return 9 }
        return tailIsRaised ? 14 : 4
    }

    private var breathingScale: CGFloat {
        guard isAnimated, mood == "sleepy" else { return 1 }
        return isBreathingIn ? 1.03 : 1
    }

    private var animationKey: String {
        "\(mood)-\(isAnimated)"
    }

    private var accessibilityDescription: String {
        let moodDescription: String
        switch mood {
        case "happy":
            moodDescription = "开心的猫"
        case "sleepy":
            moodDescription = "打盹的猫"
        default:
            moodDescription = "安静的猫"
        }

        switch outfit {
        case "scarf":
            return "\(moodDescription),戴着小围巾"
        case "glasses":
            return "\(moodDescription),戴着圆眼镜"
        default:
            return moodDescription
        }
    }

    @MainActor
    private func blinkOccasionally() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 3_600_000_000)
            } catch {
                return
            }

            withAnimation(.easeInOut(duration: 0.12)) {
                isBlinking = true
            }

            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }

            withAnimation(.easeInOut(duration: 0.12)) {
                isBlinking = false
            }
        }
    }
}

private struct CatTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(x: 0.65, y: 0.75, in: rect))
        path.addCurve(
            to: point(x: 0.89, y: 0.48, in: rect),
            control1: point(x: 0.89, y: 0.82, in: rect),
            control2: point(x: 0.97, y: 0.65, in: rect)
        )
        return path
    }

    private func point(x: CGFloat, y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
    }
}

private struct CatEarsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.3))
        path.addLine(
            to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.05)
        )
        path.addLine(
            to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.25)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.25))
        path.addLine(
            to: CGPoint(x: rect.width * 0.69, y: rect.height * 0.05)
        )
        path.addLine(
            to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.3)
        )
        path.closeSubpath()
        return path
    }
}

private struct CatClosedEyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY),
            control: CGPoint(
                x: rect.minX + rect.width * 0.18,
                y: rect.maxY
            )
        )
        path.move(
            to: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(
                x: rect.minX + rect.width * 0.82,
                y: rect.maxY
            )
        )
        return path
    }
}

private struct CatNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
