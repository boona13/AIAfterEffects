//
//  TimelineRulerView.swift
//  AIAfterEffects
//
//  Time ruler with adaptive tick marks and labels.
//  Clicking on the ruler jumps the playhead to that time position.
//

import SwiftUI

struct TimelineRulerView: View {
    let duration: Double
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    let height: CGFloat
    let viewWidth: CGFloat
    let onTap: (Double) -> Void
    
    /// Adaptive tick interval based on zoom level
    private var majorInterval: Double {
        if pixelsPerSecond >= 200 { return 0.5 }    // Every 0.5s at high zoom
        if pixelsPerSecond >= 100 { return 1.0 }     // Every 1s
        if pixelsPerSecond >= 50  { return 2.0 }     // Every 2s
        if pixelsPerSecond >= 30  { return 5.0 }     // Every 5s
        return 10.0                                    // Every 10s at low zoom
    }
    
    private var minorTicksPerMajor: Int {
        if pixelsPerSecond >= 200 { return 5 }
        if pixelsPerSecond >= 100 { return 4 }
        return 2
    }
    
    private var totalWidth: CGFloat {
        CGFloat(duration) * pixelsPerSecond
    }
    
    var body: some View {
        Canvas { context, size in
            let majorStep = majorInterval
            let minorStep = majorStep / Double(minorTicksPerMajor)
            
            // Draw minor ticks
            var t: Double = 0
            while t <= duration {
                let x = CGFloat(t) * pixelsPerSecond
                
                let isMajor = abs(t.truncatingRemainder(dividingBy: majorStep)) < 0.001
                
                if isMajor {
                    // Major tick + label
                    let tickPath = Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - 10))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(tickPath, with: .color(AppTheme.Colors.textTertiary), lineWidth: 1)
                    
                    // Time label
                    let label = formatRulerLabel(t)
                    context.draw(
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(AppTheme.Colors.textTertiary),
                        at: CGPoint(x: x + 2, y: size.height - 18),
                        anchor: .leading
                    )
                } else {
                    // Minor tick
                    let tickPath = Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - 5))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(tickPath, with: .color(AppTheme.Colors.textTertiary.opacity(0.4)), lineWidth: 0.5)
                }
                
                t += minorStep
            }
            
            // Bottom border line
            let borderPath = Path { p in
                p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            }
            context.stroke(borderPath, with: .color(AppTheme.Colors.border), lineWidth: 0.5)
        }
        .frame(width: max(totalWidth, viewWidth), height: height)
        .background(AppTheme.Colors.backgroundSecondary)
        .contentShape(Rectangle())
        .onTapGesture { location in
            let time = Double(location.x) / Double(pixelsPerSecond)
            onTap(time)
        }
    }
    
    private func formatRulerLabel(_ t: Double) -> String {
        if t == 0 { return "0" }
        if majorInterval < 1 {
            return String(format: "%.1fs", t)
        }
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(secs)s"
    }
}
