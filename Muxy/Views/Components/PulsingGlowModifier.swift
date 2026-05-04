import SwiftUI

struct PulsingGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    let duration: Double

    @State private var pulse = false
    @State private var animationID = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .opacity(pulse ? 0.2 : 0.05)
                        .allowsHitTesting(false)
                        .onChange(of: animationID) { _, _ in
                            startPulse()
                        }
                        .onAppear {
                            startPulse()
                        }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isActive)
            .onChange(of: AttentionState.shared.settingsVersion) { _, _ in
                animationID += 1
            }
    }

    private func startPulse() {
        pulse = false
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

extension View {
    func pulsingGlow(isActive: Bool, color: Color, duration: Double = 2.0) -> some View {
        modifier(PulsingGlowModifier(isActive: isActive, color: color, duration: duration))
    }
}
