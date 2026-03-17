import SwiftUI

struct OnboardingView: View {
    @AppStorage("loadscan.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    @State private var isExiting = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "shippingbox.fill",
            iconColor: Color(red: 0.145, green: 0.337, blue: 0.859),
            title: "Welcome to LoadScan",
            body: "The smarter way to buy, price, and track appliance loads. Let's walk through how it works.",
            isWelcome: true
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: Color(red: 0.145, green: 0.337, blue: 0.859),
            title: "Your Dashboard",
            body: "The Dashboard shows your active inventory, aging loads, and — when you use Load Pricing — real profit figures for every load you've sold."
        ),
        OnboardingPage(
            icon: "doc.text.magnifyingglass",
            iconColor: Color(red: 1.0, green: 0.6, blue: 0.1),
            title: "Build a Load Manifest",
            body: "Tap New Load on the Loads tab to start. Scan a sticker photo or type a model number — AI looks up the product name and MSRP automatically."
        ),
        OnboardingPage(
            icon: "camera.viewfinder",
            iconColor: Color(red: 0.2, green: 0.7, blue: 0.5),
            title: "Scan or Type",
            body: "Point the camera at any appliance sticker. If scanning isn't an option, switch to manual entry — just type the model number and hit search."
        ),
        OnboardingPage(
            icon: "tag.fill",
            iconColor: Color(red: 0.85, green: 0.35, blue: 0.55),
            title: "Smart Pricing",
            body: "Enter what you paid for the whole load and your target profit margin. LoadScan distributes prices across every item proportionally by MSRP and condition — then tracks your profit on the Dashboard."
        ),
        OnboardingPage(
            icon: "dollarsign.circle.fill",
            iconColor: Color(red: 0.4, green: 0.3, blue: 0.8),
            title: "Mark Loads as Sold",
            body: "Swipe left on any load in your list to mark it sold. Sold loads with pricing data feed straight into your Dashboard profit totals.",
            isLast: true
        )
    ]

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color(red: 0.97, green: 0.97, blue: 0.975).ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button row
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") { dismiss() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.145, green: 0.337, blue: 0.859))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        PageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Dots + button
                VStack(spacing: 24) {
                    // Page dots
                    HStack(spacing: 7) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage
                                      ? Color(red: 0.145, green: 0.337, blue: 0.859)
                                      : Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.2))
                                .frame(width: i == currentPage ? 22 : 7, height: 7)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Action button
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.145, green: 0.337, blue: 0.859))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color(red: 0.145, green: 0.337, blue: 0.859).opacity(0.3),
                                    radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 48)
            }
        }
        .opacity(isExiting ? 0 : 1)
        .scaleEffect(isExiting ? 0.96 : 1)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.22)) {
            isExiting = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            hasSeenOnboarding = true
        }
    }
}

// MARK: - Page View

private struct PageView: View {
    let page: OnboardingPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(page.iconColor.opacity(0.08))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(page.iconColor.opacity(0.13))
                    .frame(width: 110, height: 110)
                // Icon badge
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(page.iconColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: page.iconColor.opacity(0.35), radius: 16, x: 0, y: 8)
                Image(systemName: page.icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: appeared)

            Spacer().frame(height: 40)

            // Text
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: page.isWelcome ? 30 : 26, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.15))
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.35).delay(0.12), value: appeared)

                Text(page.body)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.38, green: 0.38, blue: 0.42))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 12)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    var isWelcome: Bool = false
    var isLast: Bool = false
}
