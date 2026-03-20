//
//  AnimeStagger.swift
//  AIAfterEffects
//
//  Stagger utility inspired by Anime.js stagger() function.
//  Generates cascading delay/value arrays for groups of objects.
//

import Foundation

// MARK: - Stagger Types

enum StaggerFrom: Equatable {
    case first           // Start from the first element
    case last            // Start from the last element
    case center          // Expand outward from center
    case index(Int)      // Expand outward from specific index
}

enum StaggerAxis: Equatable {
    case x               // Grid: stagger along X axis only
    case y               // Grid: stagger along Y axis only
    case both            // Grid: radial distance from origin
}

// MARK: - AnimeStagger

struct AnimeStagger {
    
    // MARK: - Delay Staggering
    
    /// Generate staggered delay values for a group of elements.
    ///
    /// - Parameters:
    ///   - count: Number of elements in the group
    ///   - each: Delay between each successive element (seconds)
    ///   - from: Where the stagger originates from
    ///   - grid: Optional grid dimensions for 2D staggering
    ///   - axis: Which axis to use for grid distance calculation
    ///   - ease: Easing applied to the delay distribution
    /// - Returns: Array of delay values (in seconds), one per element
    static func delays(
        count: Int,
        each: Double = 0.1,
        from: StaggerFrom = .first,
        grid: (rows: Int, cols: Int)? = nil,
        axis: StaggerAxis = .both,
        ease: EasingType = .linear
    ) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [0] }
        
        if let grid = grid {
            return gridDelays(
                rows: grid.rows,
                cols: grid.cols,
                each: each,
                from: from,
                axis: axis,
                ease: ease
            )
        }
        
        return linearDelays(count: count, each: each, from: from, ease: ease)
    }
    
    /// Generate staggered values (not just delays) across a range.
    ///
    /// - Parameters:
    ///   - count: Number of elements
    ///   - range: (fromValue, toValue) to distribute across elements
    ///   - from: Where the stagger originates from
    ///   - ease: Easing applied to the value distribution
    /// - Returns: Array of interpolated values, one per element
    static func values(
        count: Int,
        range: (Double, Double),
        from: StaggerFrom = .first,
        ease: EasingType = .linear
    ) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [(range.0 + range.1) / 2] }
        
        let distances = normalizedDistances(count: count, from: from)
        let maxDist = distances.max() ?? 1.0
        
        return distances.map { dist in
            let normalizedProgress = maxDist > 0 ? dist / maxDist : 0
            let easedProgress = EasingHelper.apply(ease, to: normalizedProgress)
            return range.0 + (range.1 - range.0) * easedProgress
        }
    }
    
    // MARK: - Private Helpers
    
    private static func linearDelays(
        count: Int,
        each: Double,
        from: StaggerFrom,
        ease: EasingType
    ) -> [Double] {
        let distances = normalizedDistances(count: count, from: from)
        let maxDist = distances.max() ?? 1.0
        
        return distances.map { dist in
            let normalizedProgress = maxDist > 0 ? dist / maxDist : 0
            let easedProgress = EasingHelper.apply(ease, to: normalizedProgress)
            return easedProgress * each * Double(count - 1)
        }
    }
    
    private static func gridDelays(
        rows: Int,
        cols: Int,
        each: Double,
        from: StaggerFrom,
        axis: StaggerAxis,
        ease: EasingType
    ) -> [Double] {
        let count = rows * cols
        guard count > 0 else { return [] }
        
        // Determine origin point
        let originRow: Double
        let originCol: Double
        
        switch from {
        case .first:
            originRow = 0
            originCol = 0
        case .last:
            originRow = Double(rows - 1)
            originCol = Double(cols - 1)
        case .center:
            originRow = Double(rows - 1) / 2.0
            originCol = Double(cols - 1) / 2.0
        case .index(let idx):
            let clampedIdx = max(0, min(idx, count - 1))
            originRow = Double(clampedIdx / cols)
            originCol = Double(clampedIdx % cols)
        }
        
        // Calculate distances from origin
        var distances: [Double] = []
        for i in 0..<count {
            let row = Double(i / cols)
            let col = Double(i % cols)
            
            let dist: Double
            switch axis {
            case .x:
                dist = abs(col - originCol)
            case .y:
                dist = abs(row - originRow)
            case .both:
                let dx = col - originCol
                let dy = row - originRow
                dist = sqrt(dx * dx + dy * dy)
            }
            
            distances.append(dist)
        }
        
        let maxDist = distances.max() ?? 1.0
        
        return distances.map { dist in
            let normalizedProgress = maxDist > 0 ? dist / maxDist : 0
            let easedProgress = EasingHelper.apply(ease, to: normalizedProgress)
            return easedProgress * each * maxDist
        }
    }
    
    /// Compute normalized distances from the origin for each element (0 = at origin)
    private static func normalizedDistances(count: Int, from: StaggerFrom) -> [Double] {
        switch from {
        case .first:
            return (0..<count).map { Double($0) }
            
        case .last:
            return (0..<count).map { Double(count - 1 - $0) }
            
        case .center:
            let center = Double(count - 1) / 2.0
            return (0..<count).map { abs(Double($0) - center) }
            
        case .index(let idx):
            let origin = Double(max(0, min(idx, count - 1)))
            return (0..<count).map { abs(Double($0) - origin) }
        }
    }
}
