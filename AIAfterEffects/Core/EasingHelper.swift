//
//  EasingHelper.swift
//  AIAfterEffects
//
//  Shared easing functions for animation progress curves
//

import Foundation

enum EasingHelper {
    /// Apply easing curve to a linear progress value (0...1)
    static func apply(_ type: EasingType, to progress: Double) -> Double {
        switch type {
        case .linear:
            return progress
            
        // Basic easing
        case .easeIn:
            return progress * progress
        case .easeOut:
            return 1 - pow(1 - progress, 2)
        case .easeInOut:
            return progress < 0.5
                ? 2 * progress * progress
                : 1 - pow(-2 * progress + 2, 2) / 2
            
        // Quadratic
        case .easeInQuad:
            return progress * progress
        case .easeOutQuad:
            return 1 - (1 - progress) * (1 - progress)
        case .easeInOutQuad:
            return progress < 0.5
                ? 2 * progress * progress
                : 1 - pow(-2 * progress + 2, 2) / 2
            
        // Cubic
        case .easeInCubic:
            return progress * progress * progress
        case .easeOutCubic:
            return 1 - pow(1 - progress, 3)
        case .easeInOutCubic:
            return progress < 0.5
                ? 4 * progress * progress * progress
                : 1 - pow(-2 * progress + 2, 3) / 2
            
        // Quartic
        case .easeInQuart:
            return progress * progress * progress * progress
        case .easeOutQuart:
            return 1 - pow(1 - progress, 4)
        case .easeInOutQuart:
            return progress < 0.5
                ? 8 * progress * progress * progress * progress
                : 1 - pow(-2 * progress + 2, 4) / 2
            
        // Exponential
        case .easeInExpo:
            return progress == 0 ? 0 : pow(2, 10 * progress - 10)
        case .easeOutExpo:
            return progress == 1 ? 1 : 1 - pow(2, -10 * progress)
        case .easeInOutExpo:
            if progress == 0 { return 0 }
            if progress == 1 { return 1 }
            return progress < 0.5
                ? pow(2, 20 * progress - 10) / 2
                : (2 - pow(2, -20 * progress + 10)) / 2
            
        // Back (overshoot)
        case .easeInBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return c3 * progress * progress * progress - c1 * progress * progress
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(progress - 1, 3) + c1 * pow(progress - 1, 2)
        case .easeInOutBack:
            let c1 = 1.70158
            let c2 = c1 * 1.525
            return progress < 0.5
                ? (pow(2 * progress, 2) * ((c2 + 1) * 2 * progress - c2)) / 2
                : (pow(2 * progress - 2, 2) * ((c2 + 1) * (progress * 2 - 2) + c2) + 2) / 2
            
        // Physics-based
        case .spring:
            return 1 - pow(2, -10 * progress) * cos(progress * .pi * 2)
        case .bounce:
            if progress < 4/11 {
                return (121 * progress * progress) / 16
            } else if progress < 8/11 {
                return (363/40 * progress * progress) - (99/10 * progress) + 17/5
            } else if progress < 9/10 {
                return (4356/361 * progress * progress) - (35442/1805 * progress) + 16061/1805
            } else {
                return (54/5 * progress * progress) - (513/25 * progress) + 268/25
            }
        case .elastic:
            if progress == 0 { return 0 }
            if progress == 1 { return 1 }
            return pow(2, -10 * progress) * sin((progress * 10 - 0.75) * (2 * .pi) / 3) + 1
            
        // Special
        case .anticipate:
            let c1 = 1.70158
            return progress * progress * ((c1 + 1) * progress - c1)
        case .overshootSettle:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(progress - 1, 3) + c1 * pow(progress - 1, 2)
        case .snapBack:
            if progress < 0.8 {
                return 1.1 * (progress / 0.8)
            } else {
                let t = (progress - 0.8) / 0.2
                return 1.1 - 0.1 * t
            }
        case .smooth:
            return progress * progress * (3 - 2 * progress)
        case .sharp:
            return progress < 0.5
                ? 4 * progress * progress * progress
                : 1 - pow(-2 * progress + 2, 3) / 2
        case .punch:
            return 1 - pow(1 - progress, 4)
            
        // Quintic (Anime.js-inspired)
        case .easeInQuint:
            return progress * progress * progress * progress * progress
        case .easeOutQuint:
            return 1 - pow(1 - progress, 5)
        case .easeInOutQuint:
            return progress < 0.5
                ? 16 * progress * progress * progress * progress * progress
                : 1 - pow(-2 * progress + 2, 5) / 2
            
        // Sine (Anime.js-inspired)
        case .easeInSine:
            return 1 - cos(progress * .pi / 2)
        case .easeOutSine:
            return sin(progress * .pi / 2)
        case .easeInOutSine:
            return -(cos(.pi * progress) - 1) / 2
            
        // Circular (Anime.js-inspired)
        case .easeInCirc:
            return 1 - sqrt(1 - progress * progress)
        case .easeOutCirc:
            return sqrt(1 - pow(progress - 1, 2))
        case .easeInOutCirc:
            return progress < 0.5
                ? (1 - sqrt(1 - pow(2 * progress, 2))) / 2
                : (sqrt(1 - pow(-2 * progress + 2, 2)) + 1) / 2
            
        // Cubic Bezier (Anime.js-inspired)
        case .cubicBezier(let x1, let y1, let x2, let y2):
            return EasingHelper.cubicBezierValue(x1: x1, y1: y1, x2: x2, y2: y2, progress: progress)
            
        // Steps (Anime.js-inspired)
        case .steps(let count):
            let n = max(1, Double(count))
            return floor(progress * n) / n
            
        // Parametric Spring (Anime.js-inspired)
        case .springCustom(let stiffness, let damping, let mass):
            let springEasing = AnimeSpring(mass: mass, stiffness: stiffness, damping: damping)
            return springEasing.value(at: progress)
        }
    }
    
    // MARK: - Cubic Bezier Solver
    
    /// Solve a CSS-style cubic bezier with control points (0,0), (x1,y1), (x2,y2), (1,1)
    /// Uses Newton's method + bisection fallback (same approach as WebKit/Chrome)
    private static func cubicBezierValue(x1: Double, y1: Double, x2: Double, y2: Double, progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        
        // Polynomial coefficients for the bezier curve
        let cx = 3.0 * x1
        let bx = 3.0 * (x2 - x1) - cx
        let ax = 1.0 - cx - bx
        
        let cy = 3.0 * y1
        let by = 3.0 * (y2 - y1) - cy
        let ay = 1.0 - cy - by
        
        // Newton's method: find t for given x (progress)
        var t = progress
        for _ in 0..<8 {
            let currentX = ((ax * t + bx) * t + cx) * t
            let currentSlope = (3.0 * ax * t + 2.0 * bx) * t + cx
            if abs(currentSlope) < 1e-7 { break }
            t -= (currentX - progress) / currentSlope
        }
        t = max(0, min(1, t))
        
        // Bisection refinement for accuracy
        var a = 0.0, b = 1.0
        for _ in 0..<20 {
            let x = ((ax * t + bx) * t + cx) * t
            if abs(x - progress) < 1e-7 { break }
            if x > progress { b = t } else { a = t }
            t = (a + b) / 2
        }
        
        // Compute y for the found t
        return ((ay * t + by) * t + cy) * t
    }
}
