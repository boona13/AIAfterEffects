//
//  SettingsView.swift
//  AIAfterEffects
//
//  Settings panel for API configuration with modern styling
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelsService = OpenRouterModelsService.shared
    
    @State private var apiKey: String = OpenRouterConfig.apiKey
    @State private var showAPIKey: Bool = false
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "selected_model") ?? OpenRouterConfig.defaultModel
    @State private var searchText: String = ""
    @State private var isHoveringDone = false
    
    // Debug proxy
    #if DEBUG
    @State private var useDebugProxy: Bool = OpenRouterConfig.isDebugProxy
    #endif
    
    // Sketchfab settings
    @State private var sketchfabToken: String = SketchfabAuthConfig.apiToken
    @State private var showSketchfabToken: Bool = false
    @State private var isAuthenticatingSketchfab = false
    
    private var capableModels: [OpenRouterModel] {
        modelsService.models.filter { $0.supportsVision && $0.supportsReasoning }
    }

    private var capableModelIds: [String] {
        capableModels.map(\.id)
    }
    
    var filteredModels: [OpenRouterModel] {
        if searchText.isEmpty {
            return capableModels
        }
        return capableModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            ThemedDivider()
            settingsContentView
        }
        .frame(width: 520, height: 780)
        .background(AppTheme.Colors.background)
        .onAppear {
            if !apiKey.isEmpty && modelsService.models.isEmpty {
                Task {
                    await modelsService.fetchModels()
                }
            }
        }
        .onChange(of: capableModelIds) { _, _ in
            if !capableModels.contains(where: { $0.id == selectedModel }),
               let first = capableModels.first {
                selectedModel = first.id
            }
        }
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: AppTheme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.Colors.primary)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text("Settings")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            
            Spacer()
            
            Button(action: {
                saveSettings()
                dismiss()
            }) {
                Text("Done")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(isHoveringDone ? AppTheme.Colors.primary : AppTheme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(AppTheme.Animation.quick) {
                    isHoveringDone = hovering
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
    }
    
    private var settingsContentView: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                #if DEBUG
                debugProxySection
                #endif
                openRouterSection
                sketchfabSection
                aboutSection
            }
            .padding(AppTheme.Spacing.xl)
        }
    }
    
    #if DEBUG
    private var debugProxySection: some View {
        SettingsSection(title: "Debug LLM Proxy", icon: "ladybug.fill", iconColor: AppTheme.Colors.error) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Toggle(isOn: $useDebugProxy) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        Text("Use Local Debug Proxy")
                            .font(AppTheme.Typography.bodyMedium)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        Text("Routes LLM calls to localhost:8765 instead of OpenRouter")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(AppTheme.Colors.error)
                .onChange(of: useDebugProxy) { _, newValue in
                    OpenRouterConfig.setDebugProxy(newValue)
                }
                
                if useDebugProxy {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Circle()
                            .fill(AppTheme.Colors.error)
                            .frame(width: 8, height: 8)
                        Text("DEBUG MODE — run debug_server.py first")
                            .font(AppTheme.Typography.captionMedium)
                            .foregroundColor(AppTheme.Colors.error)
                    }
                    
                    Text("python3 debug_server.py")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .padding(AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Colors.backgroundTertiary)
                        .cornerRadius(AppTheme.Radius.sm)
                }
            }
        }
    }
    #endif
    
    private var openRouterSection: some View {
        SettingsSection(title: "OpenRouter API", icon: "key.fill", iconColor: AppTheme.Colors.warning) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                apiKeyFieldView
                modelSelectionView
            }
        }
    }
    
    private var apiKeyFieldView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("API Key")
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.sm) {
                Group {
                    if showAPIKey {
                        TextField("sk-or-v1-...", text: $apiKey)
                    } else {
                        SecureField("sk-or-v1-...", text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.backgroundTertiary)
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                )
                
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.Colors.surface)
                        .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
            }
            
            Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Text("Get your API key from openrouter.ai")
                        .font(AppTheme.Typography.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.Colors.accent)
            }
            
            Text("Bring your own OpenRouter key. AIAfterEffects does not ship with a bundled production key, and your key is stored locally in your macOS Keychain.")
                .font(AppTheme.Typography.micro)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
    }
    
    private var modelSelectionView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            modelSelectionHeader
            
            if modelsService.models.isEmpty {
                modelsEmptyStateView
            } else {
                modelSearchField
                modelListSection
                selectedModelInfoView
            }
        }
    }
    
    private var modelSelectionHeader: some View {
        HStack {
            Text("Model")
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            if modelsService.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(AppTheme.Colors.primary)
            } else {
                Button(action: {
                    Task {
                        await modelsService.fetchModels()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh models")
            }
        }
    }
    
    @ViewBuilder
    private var modelsEmptyStateView: some View {
        if modelsService.isLoading {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.Colors.primary)
                Text("Loading models...")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.xl)
            .background(AppTheme.Colors.backgroundTertiary)
            .cornerRadius(AppTheme.Radius.md)
        } else if let error = modelsService.error {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.Colors.error)
                
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .multilineTextAlignment(.center)
                
                Button("Retry") {
                    Task {
                        await modelsService.fetchModels()
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.xl)
            .background(AppTheme.Colors.backgroundTertiary)
            .cornerRadius(AppTheme.Radius.md)
        } else {
            Button(action: {
                Task {
                    await modelsService.fetchModels()
                }
            }) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 14))
                    Text("Load Available Models")
                        .font(AppTheme.Typography.bodyMedium)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
    
    private var modelSearchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textPrimary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundTertiary)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var modelListSection: some View {
        if filteredModels.isEmpty {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                Text("No vision + reasoning models found.")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.backgroundTertiary)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
        } else {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.xxs) {
                    ForEach(filteredModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: selectedModel == model.id,
                            onSelect: {
                                selectedModel = model.id
                            }
                        )
                    }
                }
                .padding(AppTheme.Spacing.xs)
            }
            .frame(height: 200)
            .background(AppTheme.Colors.backgroundTertiary)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var selectedModelInfoView: some View {
        if let selected = modelsService.selectedModel(id: selectedModel) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.success)
                
                Text(selected.displayName)
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                if let price = selected.pricePerMillionTokens {
                    Text("•")
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    Text(price)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.success.opacity(0.1))
            .cornerRadius(AppTheme.Radius.md)
        }
    }
    
    // MARK: - Sketchfab Section
    
    private var sketchfabSection: some View {
        SettingsSection(title: "Sketchfab 3D Models", icon: "cube.fill", iconColor: AppTheme.Colors.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Connection status
                HStack(spacing: AppTheme.Spacing.sm) {
                    Circle()
                        .fill(SketchfabAuthConfig.isAuthenticated ? AppTheme.Colors.success : AppTheme.Colors.error)
                        .frame(width: 8, height: 8)
                    
                    Text(SketchfabAuthConfig.isAuthenticated ? "Connected" : "Not connected")
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(SketchfabAuthConfig.isAuthenticated ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    if SketchfabAuthConfig.isAuthenticated {
                        Button(action: {
                            SketchfabAuthConfig.clearAuth()
                            sketchfabToken = ""
                        }) {
                            Text("Disconnect")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.error)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // API Token field
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("API Token")
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Group {
                            if showSketchfabToken {
                                TextField("Paste your Sketchfab API token...", text: $sketchfabToken)
                            } else {
                                SecureField("Paste your Sketchfab API token...", text: $sketchfabToken)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.backgroundTertiary)
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .strokeBorder(
                                    !sketchfabToken.isEmpty ? AppTheme.Colors.success.opacity(0.5) : AppTheme.Colors.border,
                                    lineWidth: 1
                                )
                        )
                        .onChange(of: sketchfabToken) { _, newValue in
                            // Auto-save token as user types
                            SketchfabAuthConfig.apiToken = newValue
                        }
                        
                        Button(action: { showSketchfabToken.toggle() }) {
                            Image(systemName: showSketchfabToken ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.Colors.surface)
                                .cornerRadius(AppTheme.Radius.md)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        Link(destination: URL(string: "https://sketchfab.com/settings/password")!) {
                            HStack(spacing: AppTheme.Spacing.xxs) {
                                Text("Get your API token from sketchfab.com/settings/password")
                                    .font(AppTheme.Typography.caption)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(AppTheme.Colors.accent)
                        }
                        
                        Text("Scroll to the \"API token\" section and copy your token.")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        
                        Text("Sketchfab credentials are stored locally in your macOS Keychain.")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                
                // OAuth Login button (only shown if a client ID is configured)
                if SketchfabService.shared.isOAuthConfigured {
                    ThemedDivider(opacity: 0.3)
                    
                    Button(action: {
                        isAuthenticatingSketchfab = true
                        Task {
                            do {
                                _ = try await SketchfabService.shared.authenticateWithOAuth()
                            } catch {
                                DebugLogger.shared.error("Sketchfab OAuth failed: \(error)", category: .app)
                            }
                            isAuthenticatingSketchfab = false
                        }
                    }) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if isAuthenticatingSketchfab {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(AppTheme.Colors.textPrimary)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 14))
                            }
                            Text("Login with Sketchfab")
                                .font(AppTheme.Typography.bodyMedium)
                        }
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppTheme.Colors.surface)
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticatingSketchfab)
                }
                
                // Cache info
                HStack {
                    Text("Downloaded models cache")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                    Text(AssetManagerService.shared.formattedCacheSize)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Button(action: {
                        try? AssetManagerService.shared.clearCache()
                    }) {
                        Text("Clear")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.error)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.backgroundTertiary)
                .cornerRadius(AppTheme.Radius.sm)
            }
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle.fill", iconColor: AppTheme.Colors.accent) {
            VStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.Colors.warning)
                        Text("Pre-release software")
                            .font(AppTheme.Typography.bodyMedium)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                    }
                    
                    Text("This app is still unstable and under active development. Expect bugs, rough edges, incomplete flows, and breaking changes.")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.warning.opacity(0.12))
                .cornerRadius(AppTheme.Radius.md)
                
                ThemedDivider(opacity: 0.3)
                
                AboutRow(label: "Version", value: "1.0.0")
                
                ThemedDivider(opacity: 0.3)
                
                AboutRow(label: "Built with", value: "SwiftUI + OpenRouter")
                
                ThemedDivider(opacity: 0.3)
                
                HStack {
                    Text("Made with")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.error)
                    
                    Text("for creators")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                }
            }
        }
    }
    
    private func saveSettings() {
        OpenRouterConfig.apiKey = apiKey
        UserDefaults.standard.set(selectedModel, forKey: "selected_model")
        SketchfabAuthConfig.apiToken = sketchfabToken
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var iconColor: Color = AppTheme.Colors.primary
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Section header
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            
            // Section content
            content
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Colors.surface)
                .cornerRadius(AppTheme.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - About Row

struct AboutRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.textPrimary)
        }
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: OpenRouterModel
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(model.displayName)
                        .font(isSelected ? AppTheme.Typography.bodyMedium : AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(model.id)
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                if let price = model.pricePerMillionTokens {
                    Text(price)
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                        .background(AppTheme.Colors.background)
                        .cornerRadius(AppTheme.Radius.xs)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(
                        isSelected 
                            ? AppTheme.Colors.primary.opacity(0.06)
                            : (isHovering ? AppTheme.Colors.background : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(
                        isSelected ? AppTheme.Colors.primary.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    SettingsView()
}
