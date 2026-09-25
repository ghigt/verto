import AppKit

/// Pictogramme de Verto (barre de menus et icône d'app) : la fenêtre de Verto, échancrée en haut à droite pour loger une étincelle.
/// Dessinée sur une grille 18×18 (repère y vers le bas) et rendue en « template » pour suivre le thème.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            drawGlyph(.menuBar)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Verto"
        return image
    }

    /// Géométrie du pictogramme sur une grille 18×18 (y vers le bas).
    struct Geometry {
        var left, top, right, bottom, cornerRadius: CGFloat
        /// Fin du trait haut / début du trait droit, de part et d'autre de l'échancrure.
        var gapTopEnd, gapRightStart: CGFloat
        /// Lignes de texte : départ commun, puis (y, fin) pour chacune.
        var textStart: CGFloat
        var lines: [(y: CGFloat, end: CGFloat)]
        var sparkleCenter: NSPoint
        var sparkleRadius, sparklePlumpness: CGFloat

        /// Icône d'app : dessinée en grand, aucune contrainte de pixel.
        static let large = Geometry(left: 2, top: 3, right: 16, bottom: 15, cornerRadius: 3,
                                    gapTopEnd: 10.5, gapRightStart: 8.5,
                                    textStart: 5, lines: [(7.5, 10), (10.5, 11.5)],
                                    sparkleCenter: NSPoint(x: 14.8, y: 3.2), sparkleRadius: 3, sparklePlumpness: 0.14)

        /// Barre de menus : mêmes proportions, centrée dans les 18 pt et calée sur les pixels Retina
        /// (traits de 1,5 pt centrés sur des multiples de 0,25 pt), étoile un peu plus pleine pour rester lisible.
        static let menuBar = Geometry(left: 1.75, top: 4.25, right: 15.25, bottom: 15.75, cornerRadius: 3,
                                      gapTopEnd: 9.5, gapRightStart: 9,
                                      textStart: 4.75, lines: [(8.25, 9.25), (11.25, 10.75)],
                                      sparkleCenter: NSPoint(x: 14.25, y: 4.25), sparkleRadius: 3, sparklePlumpness: 0.2)
    }

    /// Dessine le pictogramme dans la couleur courante.
    static func drawGlyph(_ g: Geometry = .large) {
        let window = NSBezierPath()
        window.lineWidth = 1.5
        window.lineCapStyle = .round
        window.lineJoinStyle = .round
        window.move(to: NSPoint(x: g.gapTopEnd, y: g.top))
        window.line(to: NSPoint(x: g.left + g.cornerRadius, y: g.top))
        window.appendArc(from: NSPoint(x: g.left, y: g.top), to: NSPoint(x: g.left, y: g.top + g.cornerRadius), radius: g.cornerRadius)
        window.line(to: NSPoint(x: g.left, y: g.bottom - g.cornerRadius))
        window.appendArc(from: NSPoint(x: g.left, y: g.bottom), to: NSPoint(x: g.left + g.cornerRadius, y: g.bottom), radius: g.cornerRadius)
        window.line(to: NSPoint(x: g.right - g.cornerRadius, y: g.bottom))
        window.appendArc(from: NSPoint(x: g.right, y: g.bottom), to: NSPoint(x: g.right, y: g.bottom - g.cornerRadius), radius: g.cornerRadius)
        window.line(to: NSPoint(x: g.right, y: g.gapRightStart))
        // Lignes de texte
        for line in g.lines {
            window.move(to: NSPoint(x: g.textStart, y: line.y))
            window.line(to: NSPoint(x: line.end, y: line.y))
        }
        window.stroke()

        sparkle(center: g.sparkleCenter, radius: g.sparkleRadius, plumpness: g.sparklePlumpness).fill()
    }

    /// Étincelle à 4 branches incurvées.
    private static func sparkle(center c: NSPoint, radius r: CGFloat, plumpness: CGFloat) -> NSBezierPath {
        let tips = [NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x + r, y: c.y),
                    NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x - r, y: c.y)]
        let k = r * plumpness
        let controls = [NSPoint(x: c.x + k, y: c.y - k), NSPoint(x: c.x + k, y: c.y + k),
                        NSPoint(x: c.x - k, y: c.y + k), NSPoint(x: c.x - k, y: c.y - k)]
        let path = NSBezierPath()
        path.move(to: tips[0])
        for i in 0..<4 {
            let from = tips[i], to = tips[(i + 1) % 4], q = controls[i]
            // Quadratique → cubique
            path.curve(to: to,
                       controlPoint1: NSPoint(x: from.x + 2 / 3 * (q.x - from.x), y: from.y + 2 / 3 * (q.y - from.y)),
                       controlPoint2: NSPoint(x: to.x + 2 / 3 * (q.x - to.x), y: to.y + 2 / 3 * (q.y - to.y)))
        }
        path.close()
        return path
    }
}

/// Icône d'app : le pictogramme en blanc sur un carré arrondi indigo, au gabarit des icônes macOS.
enum AppIcon {
    static func make(size: CGFloat = 1024) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let unit = size / 1024
            // Gabarit macOS : corps de 824 pt centré, rayon ≈ 185 pt.
            let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
            let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)
            NSGradient(starting: NSColor(srgbRed: 0.45, green: 0.48, blue: 1.00, alpha: 1),
                       ending: NSColor(srgbRed: 0.27, green: 0.23, blue: 0.84, alpha: 1))?
                .draw(in: shape, angle: 90)

            // Pictogramme (grille 18) mis à l'échelle au centre, légèrement décalé pour compenser l'étincelle.
            let glyph: CGFloat = 520 * unit
            let transform = NSAffineTransform()
            transform.translateX(by: body.midX - glyph / 2 + 4 * unit, yBy: body.midY - glyph / 2 + 10 * unit)
            transform.scale(by: glyph / 18)
            NSGraphicsContext.saveGraphicsState()
            transform.concat()
            NSColor.white.set()
            MenuBarIcon.drawGlyph(.large)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// Écrit un .iconset (pour `iconutil -c icns`).
    static func exportIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                make(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
