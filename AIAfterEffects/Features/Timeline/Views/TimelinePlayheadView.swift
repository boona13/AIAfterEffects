//
//  TimelinePlayheadView.swift
//  AIAfterEffects
//
//  Draggable red vertical playhead line overlaying the timeline.
//

import SwiftUI

struct TimelinePlayheadView: View {
    let currentTime: Double
    let duration: Double
    let pixelsPerSecond: CGFloat
    let totalHeight: CGFloat
    let rulerHeight: CGFloat
    let onDrag: (Double) -> Void
    
    @State private var isDragging = false
    
    private var xPosition: CGFloat {
        CGFloat(currentTime) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Playhead line (full height)
            Rectangle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 1, height: totalHeight)
                .position(x: xPosition, y: totalHeight / 2)
            
            // Playhead handle (triangle at top)
            PlayheadHandle()
                .fill(Color.red)
                .frame(width: 12, height: 10)
                .position(x: xPosition, y: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
        .contentShape(Rectangle().size(width: 20, height: totalHeight).offset(x: xPosition - 10))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let newTime = Double(value.location.x) / Double(pixelsPerSecond)
                    onDrag(newTime)
                    isDragging = true
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Playhead Handle Shape

struct PlayheadHandle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
