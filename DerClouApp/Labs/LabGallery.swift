import SwiftUI

/// The camera labs, side by side, switchable without relaunching.
///
/// Three ways of looking at the same kind of board, kept so they can be compared
/// by eye rather than argued about. Launch the app with `CAMLAB=1`.
struct LabGallery: View {
    enum Lab: String, CaseIterable, Identifiable {
        /// The game's camera as it ships: anchored to the tops of the walls.
        case wallTops = "Верх стен"
        /// The same camera, anchored to the floor instead.
        case floor = "Пол"
        /// A tabletop diorama with an ordinary camera, in the manner of Hitman GO.
        case board = "Диорама"

        var id: String { rawValue }
    }

    /// Which lab opens first, so each can be screenshotted without tapping.
    @State private var lab: Lab = {
        switch ProcessInfo.processInfo.environment["LAB"] {
        case "walls": .wallTops
        case "board": .board
        default: .floor
        }
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            switch lab {
            case .wallTops: CameraLab()
            case .floor: FloorAnchoredLab()
            case .board: BoardGameLab()
            }

            Picker("", selection: $lab) {
                ForEach(Lab.allCases) { lab in
                    Text(lab.rawValue).tag(lab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
