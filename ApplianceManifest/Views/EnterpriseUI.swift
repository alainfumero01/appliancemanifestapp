import SwiftUI

// MARK: - Theme

enum EnterpriseTheme {
    // Backgrounds — warm off-white layered system
    static let backgroundPrimary   = Color(red: 0.969, green: 0.965, blue: 0.957) // #F7F6F4
    static let backgroundSecondary = Color(red: 0.945, green: 0.941, blue: 0.933) // #F1F0EE
    static let surfacePrimary      = Color.white
    static let surfaceSecondary    = Color(red: 0.988, green: 0.988, blue: 0.984) // #FCFCFB

    // Borders — subtle, not aggressive
    static let border       = Color(red: 0.898, green: 0.894, blue: 0.882) // #E5E4E2
    static let borderStrong = Color(red: 0.780, green: 0.776, blue: 0.765) // #C7C6C3

    // Text — high contrast on light surfaces
    static let textPrimary   = Color(red: 0.067, green: 0.094, blue: 0.153) // #111827
    static let textSecondary = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    static let textTertiary  = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF

    // Accent — professional indigo blue
    static let accent    = Color(red: 0.145, green: 0.337, blue: 0.859) // #2556DB
    static let accentDim = Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.09)

    // Semantic colors
    static let success = Color(red: 0.055, green: 0.573, blue: 0.420) // #0E9269
    static let warning = Color(red: 0.851, green: 0.467, blue: 0.024) // #D97706
    static let danger  = Color(red: 0.863, green: 0.149, blue: 0.149) // #DC2626
    static let shadow  = Color.black.opacity(0.055)

    // Layout constants
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat  = 14
    static let fieldRadius: CGFloat = 10
}

// MARK: - Background

struct EnterpriseBackground: View {
    var body: some View {
        ZStack {
            // Warm off-white base
            EnterpriseTheme.backgroundPrimary

            // Whisper of indigo at the top — barely perceptible depth
            RadialGradient(
                colors: [EnterpriseTheme.accent.opacity(0.05), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
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
                                     with: .color(Color.black.opacity(0.04)))
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
            Color.white
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
        case .sold:      return Color(red: 0.4, green: 0.3, blue: 0.8)
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
