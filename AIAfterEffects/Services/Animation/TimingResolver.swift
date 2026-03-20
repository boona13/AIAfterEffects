//
//  TimingResolver.swift
//  AIAfterEffects
//
//  Resolves timing dependencies between objects in a scene.
//  When objects have a `timingDependency`, the resolver computes an effective
//  start-time offset for each object so that downstream objects auto-shift
//  when upstream durations change.
//
//  Objects without dependencies get offset 0 (absolute timing, backward compatible).
//

import Foundation

struct TimingResolver {
    
    /// Compute the effective start-time offset for each object based on timing dependencies.
    ///
    /// - Parameter objects: All objects in the scene.
    /// - Returns: Dictionary mapping object UUID → effective start offset (seconds).
    ///
    /// Objects without a `timingDependency` get offset 0 (their animations use absolute times).
    /// Objects with a dependency get their offset computed from the parent chain.
    static func resolveOffsets(objects: [SceneObject]) -> [UUID: Double] {
        guard !objects.isEmpty else { return [:] }
        
        var offsets: [UUID: Double] = [:]
        let objectMap = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        
        // Separate into independent and dependent objects
        var resolved = Set<UUID>()
        var pendingIds: [UUID] = []
        
        for obj in objects {
            if obj.timingDependency == nil {
                // No dependency → absolute timing, offset = 0
                offsets[obj.id] = 0
                resolved.insert(obj.id)
            } else {
                pendingIds.append(obj.id)
            }
        }
        
        // Iteratively resolve in topological order.
        // Each iteration resolves objects whose dependency is already resolved.
        // Max iterations = number of pending objects (linear chain worst case).
        var maxIterations = pendingIds.count + 1
        while !pendingIds.isEmpty && maxIterations > 0 {
            maxIterations -= 1
            var stillPending: [UUID] = []
            
            for id in pendingIds {
                guard let obj = objectMap[id],
                      let dep = obj.timingDependency else {
                    offsets[id] = 0
                    resolved.insert(id)
                    continue
                }
                
                // Can't resolve yet — parent not resolved
                guard resolved.contains(dep.dependsOn) else {
                    stillPending.append(id)
                    continue
                }
                
                let parentOffset = offsets[dep.dependsOn] ?? 0
                let parentObj = objectMap[dep.dependsOn]
                
                switch dep.trigger {
                case .afterEnd:
                    // Start after the parent's last animation ends (relative to parent's own start)
                    let parentEndTime = parentObj?.latestAnimationEnd() ?? 0
                    offsets[id] = parentOffset + parentEndTime + dep.gap
                    
                case .withStart:
                    // Start at the same time as the parent (for parallel groups)
                    offsets[id] = parentOffset + dep.gap
                }
                
                resolved.insert(id)
            }
            
            pendingIds = stillPending
        }
        
        // Unresolved objects (cycles or missing parents) get offset 0
        for id in pendingIds {
            offsets[id] = 0
        }
        
        return offsets
    }
    
    /// Compute the total resolved duration of the scene, accounting for all timing dependencies.
    /// This is the latest end time across all objects.
    static func resolvedDuration(objects: [SceneObject], offsets: [UUID: Double]) -> Double {
        var maxEnd: Double = 0
        for obj in objects {
            let offset = offsets[obj.id] ?? 0
            let objEnd = offset + obj.latestAnimationEnd()
            maxEnd = max(maxEnd, objEnd)
        }
        return max(maxEnd, 1.0) // At least 1 second
    }
}

// MARK: - SceneObject Helpers

extension SceneObject {
    /// The latest end time of any animation on this object, relative to the object's own start.
    func latestAnimationEnd() -> Double {
        guard !animations.isEmpty else { return 0 }
        return animations.map { anim in
            let start = anim.startTime + anim.delay
            if anim.repeatCount == -1 {
                return Double.infinity // Infinite loop — unbounded
            }
            let repeats = Double(max(1, anim.repeatCount + 1))
            return start + anim.duration * repeats
        }.max() ?? 0
    }
}
