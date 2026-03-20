//
//  AnimeSpring.swift
//  AIAfterEffects
//
//  Parametric spring simulation inspired by Anime.js createSpring().
//  Solves a damped harmonic oscillator for physically-based easing.
//

import Foundation

struct AnimeSpring {
    let mass: Double
    let stiffness: Double
    let damping: Double
    let velocity: Double
    
    /// Settling duration in seconds (when oscillation amplitude < 0.1%)
    let settlingDuration: Double
    
    private let omega: Double      // Natural frequency: sqrt(stiffness / mass)
    private let zeta: Double       // Damping ratio: damping / (2 * sqrt(stiffness * mass))
    private let omegaD: Double     // Damped frequency
    private let b: Double          // Initial velocity coefficient
    
    init(mass: Double = 1.0, stiffness: Double = 100, damping: Double = 10, velocity: Double = 0) {
        self.mass = max(0.1, mass)
        self.stiffness = max(1, stiffness)
        self.damping = max(0, damping)
        self.velocity = velocity
        
        self.omega = sqrt(self.stiffness / self.mass)
        self.zeta = self.damping / (2 * sqrt(self.stiffness * self.mass))
        
        if self.zeta < 1 {
            // Underdamped
            self.omegaD = self.omega * sqrt(1 - self.zeta * self.zeta)
            self.b = (self.zeta * self.omega + -velocity) / self.omegaD
        } else {
            // Critically or overdamped
            self.omegaD = 0
            self.b = -velocity + self.omega
        }
        
        self.settlingDuration = AnimeSpring.computeSettlingDuration(
            omega: self.omega,
            zeta: self.zeta
        )
    }
    
    /// Compute the spring value at a normalized progress (0.0 - 1.0).
    /// Returns a value that converges to 1.0.
    func value(at progress: Double) -> Double {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        
        let t = progress * settlingDuration
        
        if zeta < 1 {
            // Underdamped: oscillates before settling
            return 1 - exp(-zeta * omega * t) * (cos(omegaD * t) + b * sin(omegaD * t))
        } else if zeta == 1 {
            // Critically damped: fastest non-oscillating response
            return 1 - exp(-omega * t) * (1 + b * t)
        } else {
            // Overdamped: slow approach without oscillation
            let r1 = -omega * (zeta + sqrt(zeta * zeta - 1))
            let r2 = -omega * (zeta - sqrt(zeta * zeta - 1))
            let c2 = (-r1) / (r2 - r1)
            let c1 = 1 - c2
            return 1 - c1 * exp(r1 * t) - c2 * exp(r2 * t)
        }
    }
    
    /// Compute when the spring effectively settles (amplitude < 0.1% of target)
    private static func computeSettlingDuration(omega: Double, zeta: Double) -> Double {
        let threshold = 0.001
        if zeta > 0 {
            // Envelope e^(-ζωt) < threshold => t > -ln(threshold) / (ζω)
            return min(-log(threshold) / (zeta * omega), 10.0)
        } else {
            return 10.0 // Undamped: never settles, cap at 10s
        }
    }
    
    // MARK: - Presets
    
    /// Gentle, bouncy spring (like a UI element settling)
    static let gentle = AnimeSpring(mass: 1.0, stiffness: 120, damping: 14)
    
    /// Snappy spring with minimal oscillation
    static let snappy = AnimeSpring(mass: 1.0, stiffness: 300, damping: 20)
    
    /// Wobbly spring with pronounced oscillation
    static let wobbly = AnimeSpring(mass: 1.0, stiffness: 180, damping: 8)
    
    /// Heavy, slow spring (like a heavy object)
    static let heavy = AnimeSpring(mass: 3.0, stiffness: 200, damping: 20)
    
    /// Very stiff, almost no oscillation
    static let stiff = AnimeSpring(mass: 1.0, stiffness: 400, damping: 30)
}
