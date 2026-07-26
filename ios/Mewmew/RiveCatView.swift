import Foundation
import RiveRuntime
import SwiftUI

struct CatPresentation: View {
    enum RenderingMode: Equatable {
        case rive
        case builtIn

        var title: String {
            switch self {
            case .rive:
                return "Rive"
            case .builtIn:
                return "内置绘制"
            }
        }
    }

    let mood: String
    let outfit: String
    let isAnimated: Bool
    let feedTrigger: Int
    let levelUpTrigger: Int

    static var currentRenderingMode: RenderingMode {
        riveViewModel == nil ? .builtIn : .rive
    }

    var body: some View {
        Group {
            if let riveViewModel = Self.riveViewModel {
                riveViewModel.view()
            } else {
                CatView(
                    mood: mood,
                    outfit: outfit,
                    isAnimated: isAnimated
                )
            }
        }
        .onAppear {
            Self.setNumberInput("mood", value: moodValue)
            Self.setNumberInput("outfit", value: outfitValue)
            Self.setPlayback(isAnimated: isAnimated)
        }
        .onChange(of: mood) { _, _ in
            Self.setNumberInput("mood", value: moodValue)
            Self.setPlayback(isAnimated: isAnimated)
        }
        .onChange(of: outfit) { _, _ in
            Self.setNumberInput("outfit", value: outfitValue)
            Self.setPlayback(isAnimated: isAnimated)
        }
        .onChange(of: isAnimated) { _, newValue in
            Self.setPlayback(isAnimated: newValue)
        }
        .onChange(of: feedTrigger) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Self.fireTrigger("feed", isAnimated: isAnimated)
        }
        .onChange(of: levelUpTrigger) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Self.fireTrigger("levelUp", isAnimated: isAnimated)
        }
    }

    private var moodValue: Double {
        switch mood {
        case "happy":
            return 0
        case "sleepy":
            return 2
        default:
            return 1
        }
    }

    private var outfitValue: Double {
        switch outfit {
        case "bell":
            return 1
        case "glasses":
            return 2
        default:
            return 0
        }
    }

    private static let riveViewModel: RiveViewModel? = {
        let bundle = Bundle.main

        // RiveViewModel(fileName:) force-unwraps loading internally. Reading
        // the data ourselves and using RiveFile's throwing initializer keep a
        // missing, unreadable, or invalid asset on the safe SwiftUI fallback.
        guard let resourceURL = bundle.url(
            forResource: "cat",
            withExtension: "riv"
        ) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            let riveFile = try RiveFile(
                data: data,
                loadCdn: false
            )
            let model = RiveModel(riveFile: riveFile)

            // Validate the resource contract with throwing APIs before the
            // RiveViewModel initializer, which configures these using try!.
            try model.setArtboard("Cat")
            try model.setStateMachine("CatState")

            return RiveViewModel(
                model,
                stateMachineName: "CatState",
                fit: .contain,
                alignment: .center,
                autoPlay: false,
                artboardName: "Cat"
            )
        } catch {
            return nil
        }
    }()

    private static let availableInputNames: Set<String> = {
        guard let stateMachine = riveViewModel?.riveModel?.stateMachine else {
            return []
        }
        return Set(stateMachine.inputNames())
    }()

    private static func setNumberInput(_ name: String, value: Double) {
        guard availableInputNames.contains(name) else { return }
        riveViewModel?.setInput(name, value: value)
    }

    private static func fireTrigger(
        _ name: String,
        isAnimated: Bool
    ) {
        guard availableInputNames.contains(name) else { return }
        riveViewModel?.triggerInput(name)
        setPlayback(isAnimated: isAnimated)
    }

    private static func setPlayback(isAnimated: Bool) {
        guard let riveViewModel else { return }
        if isAnimated {
            riveViewModel.play()
        } else {
            riveViewModel.pause()
        }
    }
}
