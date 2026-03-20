//
//  TimelineGridView.swift
//  AIAfterEffects
//
//  Background grid lines for the timeline track area.
//  Draws vertical time lines and horizontal row separators.
//

import SwiftUI

struct TimelineGridView: View {
    let duration: Double
    let pixelsPerSecond: CGFloat
    let rowCount: Int
    let rowHeight: CGFloat
    
    /// Adaptive major interval (same logic as the ruler)
    private var majorInterval: Double {
        if pixelsPerSecond >= 200 { return 0.5 }
        if pixelsPerSecond >= 100 { return 1.0 }
        if pixelsPerSecond >= 50  { return 2.0 }
        if pixelsPerSecond >= 30  { return 5.0 }
        return 10.0
    }
    
    var body: some View {
        Canvas { context, size in
            // Vertical grid lines (time markers)
            let majorStep = majorInterval
            var t: Double = 0
            while t <= duration {
                let x = CGFloat(t) * pixelsPerSecond
                let isMajor = abs(t.truncatingRemainder(dividingBy: majorStep)) < 0.001
                
                let linePath = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                
                let opacity: Double = isMajor ? 0.12 : 0.05
                context.stroke(
                    linePath,
                    with: .color(AppTheme.Colors.textTertiary.opacity(opacity)),
                    lineWidth: isMajor ? 1 : 0.5
                )
                
                t += majorStep / 4.0  // minor ticks
            }
            
            // Horizontal row separators
            for row in 0...rowCount {
                let y = CGFloat(row) * rowHeight
                let rowPath = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(
                    rowPath,
                    with: .color(AppTheme.Colors.border.opacity(0.3)),
                    lineWidth: 0.5
                )
            }
        }
    }
}
