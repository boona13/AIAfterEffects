//
//  Design.swift
//  AIAfterEffects
//
//  Clean, minimal design system inspired by modern 3D design tools.
//  Light theme with white cards, soft shadows, and subtle borders.
//

import SwiftUI

// MARK: - App Theme

enum AppTheme {
    
    // MARK: - Brand Colors
    
    enum Colors {
        // Primary brand gradient (warm charcoal)
        static let primaryGradient = LinearGradient(
            colors: [Color(hex: "2C2C2E"), Color(hex: "3A3A3C")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Accent gradient (warm dark)
        static let accentGradient = LinearGradient(
            colors: [Color(hex: "2C2C2E"), Color(hex: "48484A")],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        // Success gradient
        static let successGradient = LinearGradient(
            colors: [Color(hex: "34C759"), Color(hex: "30B350")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Warning gradient
        static let warningGradient = LinearGradient(
            colors: [Color(hex: "FF9F0A"), Color(hex: "E08C00")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Solid colors
        static let primary = Color(hex: "2C2C2E")         // Warm charcoal
        static let secondary = Color(hex: "636366")        // Warm gray
        static let accent = Color(hex: "48484A")           // Warm dark gray
        static let success = Color(hex: "34C759")          // Apple green
        static let warning = Color(hex: "FF9F0A")          // Warm amber
        static let error = Color(hex: "FF3B30")            // Warm red
        
        // Background colors (warm light mode)
        static let background = Color(hex: "F5F5F3")       // Warm off-white
        static let backgroundSecondary = Color(hex: "EEECEA")  // Warm light gray
        static let backgroundTertiary = Color(hex: "F2F0EE")   // Warm paper
        static let surface = Color(hex: "FFFFFF")           // Pure white
        static let surfaceHover = Color(hex: "FAFAF8")      // Warm near-white
        
        // Text colors (warm, not pure black)
        static let textPrimary = Color(hex: "1C1C1E")      // Warm near-black
        static let textSecondary = Color(hex: "8A8A8E")    // Warm medium gray
        static let textTertiary = Color(hex: "AEAEB2")     // Warm light gray
        
        // Border colors (very subtle, warm)
        static let border = Color(hex: "E8E6E3")           // Warm border
        static let borderFocused = Color(hex: "2C2C2E").opacity(0.2)
        
        // Chat specific
        static let userBubble = LinearGradient(
            colors: [Color(hex: "2C2C2E"), Color(hex: "3A3A3C")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let aiBubble = Color(hex: "FFFFFF")
        static let aiAvatar = LinearGradient(
            colors: [Color(hex: "8A8A8E"), Color(hex: "AEAEB2")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let userAvatar = LinearGradient(
            colors: [Color(hex: "2C2C2E"), Color(hex: "48484A")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Canvas specific
        static let canvasBackground = Color(hex: "ECEAE7")  // Warm canvas area
        static let gridLine = Color(hex: "D5D3D0").opacity(0.4)
        static let gridLineAccent = Color(hex: "B0AEAB").opacity(0.25)
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 16, weight: .medium, design: .default)
        static let headline = Font.system(size: 14, weight: .semibold, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 14, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let micro = Font.system(size: 10, weight: .medium, design: .default)
        static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoLarge = Font.system(size: 14, weight: .medium, design: .monospaced)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let sm = (color: Color.black.opacity(0.04), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let md = (color: Color.black.opacity(0.06), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let lg = (color: Color.black.opacity(0.08), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
        static let xl = (color: Color.black.opacity(0.1), radius: CGFloat(24), x: CGFloat(0), y: CGFloat(12))
        static let glow = (color: Color.black.opacity(0.06), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(4))
    }
    
    // MARK: - Animations
    
    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeOut(duration: 0.25)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let bounce = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Clean Card Style Modifier (replaces Glass Morphism)

struct GlassMorphismStyle: ViewModifier {
    var intensity: Double
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Clean white card
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(AppTheme.Colors.surface)
                    
                    // Subtle border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                }
            )
            .shadow(
                color: AppTheme.Shadows.md.color,
                radius: AppTheme.Shadows.md.radius,
                x: AppTheme.Shadows.md.x,
                y: AppTheme.Shadows.md.y
            )
    }
}

extension View {
    func glassMorphism(intensity: Double = 0.8, cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        modifier(GlassMorphismStyle(intensity: intensity, cornerRadius: cornerRadius))
    }
}

// MARK: - Glow Effect Modifier (subtle in light theme)

struct GlowEffectModifier: ViewModifier {
    var color: Color
    var radius: CGFloat
    var isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.15) : .clear, radius: radius)
            .animation(AppTheme.Animation.smooth, value: isActive)
    }
}

extension View {
    func glowEffect(color: Color = AppTheme.Colors.primary, radius: CGFloat = 10, isActive: Bool = true) -> some View {
        modifier(GlowEffectModifier(color: color, radius: radius, isActive: isActive))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    var isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
                }
                .mask(content)
                .opacity(isActive ? 1 : 0)
            )
            .onAppear {
                if isActive {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
    }
}

extension View {
    func shimmer(isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    var isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? 1.05 : 1.0)
            .opacity(isPulsing && isActive ? 0.8 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulse(isActive: Bool = true) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }
}

// MARK: - Modern Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                Group {
                    if isEnabled {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(AppTheme.Colors.primary)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(AppTheme.Colors.textTertiary)
                    }
                }
            )
            .cornerRadius(AppTheme.Radius.md)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.5)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
            .shadow(
                color: isEnabled ? Color.black.opacity(0.08) : .clear,
                radius: configuration.isPressed ? 2 : 6,
                y: configuration.isPressed ? 1 : 3
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyMedium)
            .foregroundColor(isEnabled ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.textSecondary
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyMedium)
            .foregroundColor(color)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                configuration.isPressed ? AppTheme.Colors.surfaceHover : Color.clear
            )
            .cornerRadius(AppTheme.Radius.sm)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isActive ? AppTheme.Colors.primary.opacity(0.1) : (configuration.isPressed ? AppTheme.Colors.surfaceHover : Color.clear))
            )
            .foregroundColor(isActive ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Text Field Style

struct ModernTextFieldStyle: ViewModifier {
    var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .font(AppTheme.Typography.body)
            .foregroundColor(AppTheme.Colors.textPrimary)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(
                        isFocused ? AppTheme.Colors.primary.opacity(0.3) : AppTheme.Colors.border,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.04) : .clear,
                radius: 8
            )
            .animation(AppTheme.Animation.quick, value: isFocused)
    }
}

extension View {
    func modernTextField(isFocused: Bool = false) -> some View {
        modifier(ModernTextFieldStyle(isFocused: isFocused))
    }
}

// MARK: - Divider Style

struct ThemedDivider: View {
    var opacity: Double = 1.0
    
    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.border)
            .frame(height: 1)
            .opacity(opacity)
    }
}

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    var color: Color = AppTheme.Colors.primary
    
    var body: some View {
        Text(text)
            .font(AppTheme.Typography.micro)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .background(color)
            .cornerRadius(AppTheme.Radius.full)
    }
}

// MARK: - Progress Indicators

struct ModernProgressView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(AppTheme.Colors.primary)
    }
}

struct GradientProgressBar: View {
    var progress: Double
    var height: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(AppTheme.Colors.backgroundSecondary)
                
                // Progress
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(AppTheme.Colors.primary)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    .animation(AppTheme.Animation.smooth, value: progress)
            }
        }
        .frame(height: height)
    }
}
