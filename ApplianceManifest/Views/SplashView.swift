import SwiftUI

// MARK: - Icon View
// Matches the generated app icon exactly so the splash feels continuous.

struct LoadScanIconView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    EnterpriseTheme.brandGradientStart,
                    EnterpriseTheme.brandGradientEnd,
                ],
                startPoint: .top,
                endPoint:   .bottom
            )

            Canvas { ctx, canvasSize in
                let s = canvasSize.width

                // ── Corner bracket parameters ──────────────────────────
                let pad   = s * 0.180
                let arm   = s * 0.145
                let thick = s * 0.040

                var b = Path()
                // Top-left
                b.move(to:    CGPoint(x: pad + arm, y: pad))
                b.addLine(to: CGPoint(x: pad,       y: pad))
                b.addLine(to: CGPoint(x: pad,       y: pad + arm))
                // Top-right
                b.move(to:    CGPoint(x: s - pad - arm, y: pad))
                b.addLine(to: CGPoint(x: s - pad,       y: pad))
                b.addLine(to: CGPoint(x: s - pad,       y: pad + arm))
                // Bottom-left
                b.move(to:    CGPoint(x: pad + arm, y: s - pad))
                b.addLine(to: CGPoint(x: pad,       y: s - pad))
                b.addLine(to: CGPoint(x: pad,       y: s - pad - arm))
                // Bottom-right
                b.move(to:    CGPoint(x: s - pad - arm, y: s - pad))
                b.addLine(to: CGPoint(x: s - pad,       y: s - pad))
                b.addLine(to: CGPoint(x: s - pad,       y: s - pad - arm))
                ctx.stroke(b, with: .color(.white),
                           style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))

                // ── Barcode bars ───────────────────────────────────────
                let bw = s * 0.570   // total bar area width
                let bh = s * 0.400   // total bar area height
                let bx = (s - bw) / 2
                let by = (s - bh) / 2

                // (widthFraction, heightFraction) — 9 bars
                let bars: [(CGFloat, CGFloat)] = [
                    (0.155, 1.00), (0.060, 0.78), (0.115, 1.00),
                    (0.060, 0.78), (0.155, 1.00), (0.060, 0.78),
                    (0.115, 1.00), (0.060, 0.78), (0.155, 1.00),
                ]
                let totalW  = bars.reduce(0) { $0 + $1.0 }   // 0.935
                let gap     = (1.0 - totalW) / CGFloat(bars.count - 1)

                var cx = bx
                for (wf, hf) in bars {
                    let barW = bw * wf
                    let barH = bh * hf
                    let barY = by + (bh - barH) / 2
                    let r    = barW * 0.25
                    let rect = CGRect(x: cx, y: barY, width: barW, height: barH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(.white.opacity(wf < 0.1 ? 0.82 : 0.95)))
                    cx += barW + bw * gap
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isActive  = false
    @State private var slideY:  CGFloat = 72
    @State private var opacity: Double  = 0

    var body: some View {
        ZStack {
            if isActive {
                RootView()
                    .transition(.opacity)
            } else {
                splashContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.30), value: isActive)
    }

    // MARK: - Splash content

    private var splashContent: some View {
        ZStack {
            EnterpriseBackground()

            VStack(spacing: 22) {
                // Icon — same design as the home-screen tile
                LoadScanIconView(size: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(
                        color: EnterpriseTheme.brandShadow,
                        radius: 22, x: 0, y: 8
                    )

                // Wordmark
                VStack(spacing: 5) {
                    Text("LoadScan")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(EnterpriseTheme.textPrimary)

                    Text("Load Tracking & Manifest")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(EnterpriseTheme.textSecondary)
                }
            }
            .offset(y: slideY)
            .opacity(opacity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .task {
            // 1. Slide in
            withAnimation(
                .spring(response: 0.52, dampingFraction: 0.76, blendDuration: 0)
            ) {
                slideY  = 0
                opacity = 1
            }

            // 2. Bootstrap session + enforce a minimum splash duration concurrently
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await appViewModel.bootstrap() }
                group.addTask { try? await Task.sleep(for: .seconds(1.6)) }
                for await _ in group {}
            }

            // 3. Fade out to the main app
            isActive = true
        }
    }
}
