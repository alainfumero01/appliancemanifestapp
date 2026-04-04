import SwiftUI

// MARK: - Theme

enum EnterpriseTheme {
    // Backgrounds — cool gray/white graphite system
    static let backgroundPrimary   = Color(red: 0.953, green: 0.961, blue: 0.969) // #F3F5F7
    static let backgroundSecondary = Color(red: 0.922, green: 0.933, blue: 0.949) // #EBEEF2
    static let surfacePrimary      = Color.white
    static let surfaceSecondary    = Color(red: 0.973, green: 0.980, blue: 0.988) // #F8FAFC

    // Borders — subtle cool grays
    static let border       = Color(red: 0.843, green: 0.863, blue: 0.890) // #D7DCE3
    static let borderStrong = Color(red: 0.737, green: 0.765, blue: 0.804) // #BCC3CD

    // Text — high contrast on light surfaces
    static let textPrimary   = Color(red: 0.078, green: 0.094, blue: 0.122) // #14181F
    static let textSecondary = Color(red: 0.349, green: 0.380, blue: 0.439) // #596170
    static let textTertiary  = Color(red: 0.541, green: 0.573, blue: 0.627) // #8A92A0

    // Accent — restrained graphite
    static let accent    = Color(red: 0.110, green: 0.129, blue: 0.165) // #1C212A
    static let accentDim = accent.opacity(0.08)
    static let brandGradientStart = Color(red: 0.361, green: 0.392, blue: 0.439) // #5C6470
    static let brandGradientEnd   = Color(red: 0.098, green: 0.114, blue: 0.141) // #191D24
    static let brandShadow        = Color.black.opacity(0.16)

    // Semantic colors
    static let success = Color(red: 0.184, green: 0.420, blue: 0.341) // #2F6B57
    static let warning = Color(red: 0.553, green: 0.416, blue: 0.200) // #8D6A33
    static let danger  = Color(red: 0.635, green: 0.302, blue: 0.302) // #A24D4D
    static let reserved = Color(red: 0.427, green: 0.467, blue: 0.537) // #6D7789
    static let shadow  = Color.black.opacity(0.060)

    // Layout constants
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat  = 14
    static let fieldRadius: CGFloat = 10
}

// MARK: - Background

struct EnterpriseBackground: View {
    var body: some View {
        ZStack {
            // Cool light base
            EnterpriseTheme.backgroundPrimary

            // A faint graphite bloom keeps the light UI from feeling flat.
            RadialGradient(
                colors: [EnterpriseTheme.accent.opacity(0.05), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )

            // Dot grid — rasterised into a single GPU layer so it never redraws
            Canvas { context, size in
                let step: CGFloat = 32
                var row: CGFloat = step / 2
                while row < size.height {
                    var col: CGFloat = step / 2
                    while col < size.width {
                        let rect = CGRect(x: col - 0.75, y: row - 0.75, width: 1.5, height: 1.5)
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(Color.black.opacity(0.028)))
                        col += step
                    }
                    row += step
                }
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

struct EnterpriseCard<Content: View>: View {
    private let padding: CGFloat
    private let accentLeft: Color?
    @ViewBuilder private let content: Content

    init(padding: CGFloat = 18,
         accentLeft: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.padding    = padding
        self.accentLeft = accentLeft
        self.content    = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            if let accentLeft {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accentLeft)
                    .frame(width: 3)
                    .padding(.vertical, 1)
                    .padding(.leading, 1)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EnterpriseTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EnterpriseTheme.cardRadius, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 3, x: 0, y: 1)
    }
}

// MARK: - Section Header

struct EnterpriseSectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.eyebrow  = eyebrow
        self.title    = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(EnterpriseTheme.accent)
                        .frame(width: 12, height: 2)
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.accent)
                        .tracking(1.6)
                }
            }
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(EnterpriseTheme.textSecondary)
            }
        }
    }
}

// MARK: - Metric Tile

struct EnterpriseMetricTile: View {
    let label: String
    let value: String
    var accent: Color = EnterpriseTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(EnterpriseTheme.textTertiary)
                .tracking(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(EnterpriseTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(EnterpriseTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent)
                .frame(height: 2.5)
                .padding(.horizontal, 1)
                .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Field

struct EnterpriseField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(EnterpriseTheme.textSecondary)
                .tracking(1.2)

            Group {
                if secure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textInputAutocapitalization(capitalization)
            .keyboardType(keyboardType)
            .submitLabel(submitLabel)
            .font(.system(size: 16))
            .foregroundStyle(EnterpriseTheme.textPrimary)
            .tint(EnterpriseTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(EnterpriseTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EnterpriseTheme.fieldRadius, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
        }
    }
}

// MARK: - Action Bar

struct EnterpriseActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, EnterpriseTheme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background {
            EnterpriseTheme.surfacePrimary
                .opacity(0.97)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(EnterpriseTheme.border)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .tracking(0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 0.5)
            }
    }
}

struct AppModePicker: View {
    @Binding var selection: AppMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.displayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color.white : EnterpriseTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == mode ? EnterpriseTheme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(EnterpriseTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EnterpriseTheme.border, lineWidth: 1)
        }
        .shadow(color: EnterpriseTheme.shadow, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Button Styles

struct EnterprisePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .tracking(0.1)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EnterpriseTheme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct EnterpriseSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(EnterpriseTheme.textPrimary.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EnterpriseTheme.surfacePrimary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EnterpriseTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Status Extensions

extension LookupStatus {
    var badgeTint: Color {
        switch self {
        case .pending:     return EnterpriseTheme.textTertiary
        case .cached:      return EnterpriseTheme.success
        case .aiSuggested: return EnterpriseTheme.accent
        case .confirmed:   return EnterpriseTheme.success
        case .needsReview: return EnterpriseTheme.warning
        }
    }

    var displayLabel: String {
        switch self {
        case .aiSuggested: return "AI Suggested"
        case .needsReview: return "Needs Review"
        default:           return rawValue.capitalized
        }
    }
}

extension ManifestStatus {
    var badgeTint: Color {
        switch self {
        case .draft:     return EnterpriseTheme.warning
        case .completed: return EnterpriseTheme.success
        case .sold:      return EnterpriseTheme.textSecondary
        }
    }
    var displayLabel: String {
        switch self {
        case .draft:     return "Draft"
        case .completed: return "Completed"
        case .sold:      return "Sold"
        }
    }
}

// MARK: - View Modifier

extension View {
    func enterpriseScreen() -> some View {
        background(EnterpriseBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .preferredColorScheme(.light)
    }
}
