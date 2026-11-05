import SwiftUI

struct ThemePalette: Equatable {
    let name: String
    let paneBase: Color
    let neutralGlow: Color
    let textPrimary: Color
    let textDim: Color
}

enum Theme {
    static let palettes: [ThemePalette] = [
        ThemePalette(
            name: "Cyberpunk",
            paneBase: Color(red: 0.055, green: 0.063, blue: 0.095),
            neutralGlow: Color(red: 0.40, green: 0.90, blue: 1.0),
            textPrimary: Color(red: 0.92, green: 0.96, blue: 1.0),
            textDim: Color(red: 0.56, green: 0.65, blue: 0.76)
        ),
        ThemePalette(
            name: "Vaporwave",
            paneBase: Color(red: 0.09, green: 0.05, blue: 0.12),
            neutralGlow: Color(red: 1.0, green: 0.35, blue: 0.85),
            textPrimary: Color(red: 0.97, green: 0.93, blue: 1.0),
            textDim: Color(red: 0.68, green: 0.58, blue: 0.78)
        ),
        ThemePalette(
            name: "Matrix",
            paneBase: Color(red: 0.03, green: 0.05, blue: 0.03),
            neutralGlow: Color(red: 0.25, green: 1.0, blue: 0.45),
            textPrimary: Color(red: 0.85, green: 1.0, blue: 0.88),
            textDim: Color(red: 0.45, green: 0.65, blue: 0.48)
        ),
        ThemePalette(
            name: "Synthwave",
            paneBase: Color(red: 0.06, green: 0.05, blue: 0.14),
            neutralGlow: Color(red: 1.0, green: 0.45, blue: 0.4),
            textPrimary: Color(red: 0.98, green: 0.94, blue: 0.92),
            textDim: Color(red: 0.65, green: 0.55, blue: 0.62)
        ),
        ThemePalette(
            name: "Classic Paper",
            paneBase: Color(red: 1.0, green: 0.95, blue: 0.78),
            neutralGlow: Color(red: 0.55, green: 0.38, blue: 0.12),
            textPrimary: Color(red: 0.15, green: 0.12, blue: 0.08),
            textDim: Color(red: 0.45, green: 0.38, blue: 0.28)
        ),


        ThemePalette(
            name: "Midnight Ocean",
            paneBase: Color(red: 0.03, green: 0.07, blue: 0.11),
            neutralGlow: Color(red: 0.15, green: 0.75, blue: 0.75),
            textPrimary: Color(red: 0.88, green: 0.97, blue: 0.97),
            textDim: Color(red: 0.45, green: 0.62, blue: 0.65)
        ),
        ThemePalette(
            name: "Blood Moon",
            paneBase: Color(red: 0.10, green: 0.02, blue: 0.03),
            neutralGlow: Color(red: 0.85, green: 0.15, blue: 0.18),
            textPrimary: Color(red: 0.98, green: 0.90, blue: 0.90),
            textDim: Color(red: 0.65, green: 0.42, blue: 0.43)
        ),
        ThemePalette(
            name: "Forest Night",
            paneBase: Color(red: 0.03, green: 0.08, blue: 0.04),
            neutralGlow: Color(red: 0.35, green: 0.85, blue: 0.30),
            textPrimary: Color(red: 0.90, green: 0.98, blue: 0.90),
            textDim: Color(red: 0.52, green: 0.65, blue: 0.50)
        ),
        ThemePalette(
            name: "Arctic Aurora",
            paneBase: Color(red: 0.02, green: 0.05, blue: 0.09),
            neutralGlow: Color(red: 0.30, green: 0.95, blue: 0.70),
            textPrimary: Color(red: 0.90, green: 0.98, blue: 0.96),
            textDim: Color(red: 0.50, green: 0.68, blue: 0.65)
        ),
        ThemePalette(
            name: "Lava",
            paneBase: Color(red: 0.08, green: 0.04, blue: 0.03),
            neutralGlow: Color(red: 1.0, green: 0.42, blue: 0.1),
            textPrimary: Color(red: 1.0, green: 0.92, blue: 0.85),
            textDim: Color(red: 0.68, green: 0.50, blue: 0.40)
        ),
        ThemePalette(
            name: "Royal Purple",
            paneBase: Color(red: 0.08, green: 0.04, blue: 0.12),
            neutralGlow: Color(red: 0.85, green: 0.70, blue: 0.25),
            textPrimary: Color(red: 0.95, green: 0.92, blue: 0.98),
            textDim: Color(red: 0.62, green: 0.55, blue: 0.70)
        ),
        ThemePalette(
            name: "Deep Space",
            paneBase: Color(red: 0.02, green: 0.02, blue: 0.04),
            neutralGlow: Color(red: 0.70, green: 0.80, blue: 1.0),
            textPrimary: Color(red: 0.95, green: 0.96, blue: 1.0),
            textDim: Color(red: 0.55, green: 0.58, blue: 0.68)
        ),
        ThemePalette(
            name: "Toxic Waste",
            paneBase: Color(red: 0.06, green: 0.08, blue: 0.02),
            neutralGlow: Color(red: 0.75, green: 1.0, blue: 0.15),
            textPrimary: Color(red: 0.93, green: 0.98, blue: 0.80),
            textDim: Color(red: 0.58, green: 0.65, blue: 0.35)
        ),
        ThemePalette(
            name: "Blueprint",
            paneBase: Color(red: 0.04, green: 0.08, blue: 0.16),
            neutralGlow: Color(red: 0.55, green: 0.80, blue: 1.0),
            textPrimary: Color(red: 0.92, green: 0.96, blue: 1.0),
            textDim: Color(red: 0.50, green: 0.62, blue: 0.78)
        ),
        ThemePalette(
            name: "Amber Terminal",
            paneBase: Color(red: 0.05, green: 0.04, blue: 0.02),
            neutralGlow: Color(red: 1.0, green: 0.65, blue: 0.1),
            textPrimary: Color(red: 1.0, green: 0.90, blue: 0.70),
            textDim: Color(red: 0.65, green: 0.52, blue: 0.30)
        ),
        ThemePalette(
            name: "Phosphor Green",
            paneBase: Color(red: 0.02, green: 0.04, blue: 0.02),
            neutralGlow: Color(red: 0.35, green: 1.0, blue: 0.35),
            textPrimary: Color(red: 0.85, green: 1.0, blue: 0.85),
            textDim: Color(red: 0.45, green: 0.65, blue: 0.45)
        ),
        ThemePalette(
            name: "Deep Sea",
            paneBase: Color(red: 0.015, green: 0.03, blue: 0.06),
            neutralGlow: Color(red: 0.20, green: 0.95, blue: 0.85),
            textPrimary: Color(red: 0.88, green: 0.98, blue: 0.96),
            textDim: Color(red: 0.42, green: 0.62, blue: 0.60)
        ),
        ThemePalette(
            name: "Dracula",
            paneBase: Color(red: 0.11, green: 0.11, blue: 0.16),
            neutralGlow: Color(red: 1.0, green: 0.45, blue: 0.78),
            textPrimary: Color(red: 0.95, green: 0.95, blue: 0.98),
            textDim: Color(red: 0.62, green: 0.60, blue: 0.72)
        ),
        ThemePalette(
            name: "Solarized Dark",
            paneBase: Color(red: 0.0, green: 0.10, blue: 0.12),
            neutralGlow: Color(red: 0.85, green: 0.45, blue: 0.10),
            textPrimary: Color(red: 0.90, green: 0.93, blue: 0.82),
            textDim: Color(red: 0.42, green: 0.58, blue: 0.58)
        ),
        ThemePalette(
            name: "Nord",
            paneBase: Color(red: 0.13, green: 0.16, blue: 0.21),
            neutralGlow: Color(red: 0.55, green: 0.75, blue: 0.90),
            textPrimary: Color(red: 0.90, green: 0.93, blue: 0.96),
            textDim: Color(red: 0.60, green: 0.65, blue: 0.72)
        ),
        ThemePalette(
            name: "Gruvbox",
            paneBase: Color(red: 0.11, green: 0.09, blue: 0.07),
            neutralGlow: Color(red: 0.95, green: 0.55, blue: 0.15),
            textPrimary: Color(red: 0.92, green: 0.86, blue: 0.72),
            textDim: Color(red: 0.62, green: 0.55, blue: 0.42)
        ),
        ThemePalette(
            name: "Monokai",
            paneBase: Color(red: 0.09, green: 0.09, blue: 0.08),
            neutralGlow: Color(red: 0.65, green: 0.90, blue: 0.30),
            textPrimary: Color(red: 0.95, green: 0.95, blue: 0.90),
            textDim: Color(red: 0.60, green: 0.58, blue: 0.50)
        ),
        ThemePalette(
            name: "Charcoal Slate",
            paneBase: Color(red: 0.09, green: 0.09, blue: 0.10),
            neutralGlow: Color(red: 0.75, green: 0.78, blue: 0.82),
            textPrimary: Color(red: 0.92, green: 0.93, blue: 0.95),
            textDim: Color(red: 0.58, green: 0.60, blue: 0.63)
        ),
        ThemePalette(
            name: "Obsidian Gold",
            paneBase: Color(red: 0.03, green: 0.03, blue: 0.03),
            neutralGlow: Color(red: 0.90, green: 0.75, blue: 0.30),
            textPrimary: Color(red: 0.96, green: 0.93, blue: 0.82),
            textDim: Color(red: 0.62, green: 0.55, blue: 0.38)
        ),
        ThemePalette(
            name: "Emerald City",
            paneBase: Color(red: 0.02, green: 0.07, blue: 0.05),
            neutralGlow: Color(red: 0.20, green: 0.90, blue: 0.55),
            textPrimary: Color(red: 0.88, green: 0.98, blue: 0.92),
            textDim: Color(red: 0.45, green: 0.65, blue: 0.55)
        ),
        ThemePalette(
            name: "Void",
            paneBase: Color(red: 0.0, green: 0.0, blue: 0.0),
            neutralGlow: Color(red: 1.0, green: 1.0, blue: 1.0),
            textPrimary: Color(red: 1.0, green: 1.0, blue: 1.0),
            textDim: Color(red: 0.55, green: 0.55, blue: 0.55)
        ),
        ThemePalette(
            name: "Molten Core",
            paneBase: Color(red: 0.07, green: 0.03, blue: 0.02),
            neutralGlow: Color(red: 1.0, green: 0.30, blue: 0.05),
            textPrimary: Color(red: 1.0, green: 0.88, blue: 0.80),
            textDim: Color(red: 0.65, green: 0.45, blue: 0.35)
        ),
        ThemePalette(
            name: "Galactic Teal",
            paneBase: Color(red: 0.02, green: 0.08, blue: 0.09),
            neutralGlow: Color(red: 0.20, green: 0.95, blue: 0.90),
            textPrimary: Color(red: 0.88, green: 0.98, blue: 0.97),
            textDim: Color(red: 0.45, green: 0.65, blue: 0.63)
        ),
        ThemePalette(
            name: "Plum Noir",
            paneBase: Color(red: 0.09, green: 0.04, blue: 0.09),
            neutralGlow: Color(red: 0.80, green: 0.35, blue: 0.70),
            textPrimary: Color(red: 0.95, green: 0.90, blue: 0.96),
            textDim: Color(red: 0.62, green: 0.50, blue: 0.62)
        ),

        ThemePalette(
            name: "Dawn",
            paneBase: Color(red: 1.0, green: 0.90, blue: 0.85),
            neutralGlow: Color(red: 0.75, green: 0.35, blue: 0.30),
            textPrimary: Color(red: 0.20, green: 0.10, blue: 0.08),
            textDim: Color(red: 0.48, green: 0.35, blue: 0.30)
        ),
        ThemePalette(
            name: "Mint Cream",
            paneBase: Color(red: 0.90, green: 0.98, blue: 0.92),
            neutralGlow: Color(red: 0.10, green: 0.55, blue: 0.35),
            textPrimary: Color(red: 0.08, green: 0.18, blue: 0.12),
            textDim: Color(red: 0.35, green: 0.50, blue: 0.40)
        ),
        ThemePalette(
            name: "Lavender Fields",
            paneBase: Color(red: 0.93, green: 0.90, blue: 0.98),
            neutralGlow: Color(red: 0.45, green: 0.25, blue: 0.70),
            textPrimary: Color(red: 0.15, green: 0.10, blue: 0.22),
            textDim: Color(red: 0.42, green: 0.35, blue: 0.52)
        ),
        ThemePalette(
            name: "Rose Gold",
            paneBase: Color(red: 0.98, green: 0.88, blue: 0.86),
            neutralGlow: Color(red: 0.70, green: 0.35, blue: 0.35),
            textPrimary: Color(red: 0.22, green: 0.12, blue: 0.12),
            textDim: Color(red: 0.50, green: 0.35, blue: 0.33)
        ),
        ThemePalette(
            name: "Sandstone",
            paneBase: Color(red: 0.93, green: 0.85, blue: 0.70),
            neutralGlow: Color(red: 0.45, green: 0.30, blue: 0.12),
            textPrimary: Color(red: 0.18, green: 0.12, blue: 0.06),
            textDim: Color(red: 0.45, green: 0.35, blue: 0.22)
        ),
        ThemePalette(
            name: "Ice",
            paneBase: Color(red: 0.88, green: 0.95, blue: 0.98),
            neutralGlow: Color(red: 0.10, green: 0.35, blue: 0.60),
            textPrimary: Color(red: 0.08, green: 0.12, blue: 0.18),
            textDim: Color(red: 0.35, green: 0.45, blue: 0.55)
        ),
    ]

    private static let defaultsKey = "notestack.themeIndex"

    static var currentIndex: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultsKey) // 0 if never set -- Cyberpunk, the original default
            return (0..<palettes.count).contains(stored) ? stored : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var current: ThemePalette { palettes[currentIndex] }

    @discardableResult
    static func cycleToNext() -> ThemePalette {
        currentIndex = (currentIndex + 1) % palettes.count
        return current
    }

    static var paneBase: Color { current.paneBase }
    static var neutralGlow: Color { current.neutralGlow }
    static var textPrimary: Color { current.textPrimary }
    static var textDim: Color { current.textDim }
}
