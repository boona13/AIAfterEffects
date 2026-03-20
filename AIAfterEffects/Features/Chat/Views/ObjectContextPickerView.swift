//
//  ObjectContextPickerView.swift
//  AIAfterEffects
//
//  Searchable popover for selecting scene objects as context for the chat.
//  Similar to Cursor's @ context picker.
//

import SwiftUI

struct ObjectContextPickerView: View {
    let project: Project?
    let alreadyAttached: Set<UUID>
    var onSelect: (ObjectContextAttachment) -> Void
    var onDismiss: () -> Void
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    private var filteredObjects: [(sceneName: String, object: SceneObject)] {
        guard let project else { return [] }
        
        var results: [(String, SceneObject)] = []
        for scene in project.orderedScenes {
            for obj in scene.objects {
                if alreadyAttached.contains(obj.id) { continue }
                
                if searchText.isEmpty {
                    results.append((scene.name, obj))
                } else {
                    let query = searchText.lowercased()
                    let matchesName = obj.name.lowercased().contains(query)
                    let matchesType = obj.type.rawValue.lowercased().contains(query)
                    if matchesName || matchesType {
                        results.append((scene.name, obj))
                    }
                }
            }
        }
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                TextField("Search objects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.sm)
            .background(AppTheme.Colors.background)
            
            Divider()
            
            if filteredObjects.isEmpty {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    Text(searchText.isEmpty ? "No objects in scene" : "No matching objects")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(AppTheme.Spacing.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredObjects, id: \.object.id) { item in
                            ObjectContextRow(
                                object: item.object,
                                sceneName: item.sceneName
                            ) {
                                let attachment = ObjectContextAttachment(
                                    object: item.object,
                                    sceneName: item.sceneName
                                )
                                onSelect(attachment)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.xs)
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 280)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Object Row

private struct ObjectContextRow: View {
    let object: SceneObject
    let sceneName: String
    var onTap: () -> Void
    
    @State private var isHovering = false
    
    private var icon: String {
        switch object.type {
        case .text:      return "textformat"
        case .rectangle: return "rectangle.fill"
        case .circle:    return "circle.fill"
        case .ellipse:   return "oval.fill"
        case .polygon:   return "pentagon.fill"
        case .line:      return "line.diagonal"
        case .icon:      return "star.fill"
        case .image:     return "photo.fill"
        case .path:      return "scribble.variable"
        case .model3D:   return "cube.fill"
        case .shader:    return "sparkle"
        case .particleSystem: return "sparkles"
        }
    }
    
    private var typeColor: Color {
        switch object.type {
        case .text:      return Color(hex: "3B82F6")
        case .image:     return Color(hex: "10B981")
        case .model3D:   return Color(hex: "8B5CF6")
        case .shader:    return Color(hex: "F59E0B")
        case .path:      return Color(hex: "EC4899")
        default:         return Color(hex: "6366F1")
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(typeColor)
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(object.name)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(object.type.rawValue) · \(sceneName)")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if object.animations.count > 0 {
                    Text("\(object.animations.count) anim")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.backgroundSecondary)
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(isHovering ? AppTheme.Colors.backgroundSecondary : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
