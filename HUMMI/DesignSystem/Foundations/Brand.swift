//
//  Brand.swift
//  HUMMI
//
//  The brand palette: electric lime on deep forest over a calm off-white
//  canvas — Wise-family contrast, pushed a little hotter, with gradients
//  where a flat fill would feel dead. Dark mode swaps the canvas to a
//  forest-black and lets the lime carry the light.
//

import SwiftUI
import UIKit

enum Brand {
    /// The hero colour. Fixed across appearances — it IS the brand.
    static let lime = Color(red: 163 / 255, green: 240 / 255, blue: 99 / 255)
    /// Gradient partner for lime — hotter and greener.
    static let limeDeep = Color(red: 106 / 255, green: 214 / 255, blue: 52 / 255)
    /// Text/glyph colour on lime surfaces. Always this, in both modes.
    static let forest = Color(red: 23 / 255, green: 51 / 255, blue: 0)

    /// Body text on the canvas: forest in light, pale lime in dark.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 217 / 255, green: 247 / 255, blue: 191 / 255, alpha: 1)
            : UIColor(red: 23 / 255, green: 51 / 255, blue: 0, alpha: 1)
    })

    /// The screen canvas: warm off-white in light, forest-black in dark.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 12 / 255, green: 21 / 255, blue: 5 / 255, alpha: 1)
            : UIColor(red: 244 / 255, green: 247 / 255, blue: 240 / 255, alpha: 1)
    })

    /// The signature fill for primary surfaces — never flat.
    static let limeGradient = LinearGradient(
        colors: [lime, limeDeep], startPoint: .top, endPoint: .bottom)
}
