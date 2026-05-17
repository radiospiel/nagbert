import SwiftUI

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    let amplitude: CGFloat = 8
    let frequency: CGFloat = 3

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = sin(animatableData * .pi * 2 * frequency) * amplitude
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

extension View {
    /// Trigger a ~0.55s horizontal shake by toggling `active` true; reset by
    /// flipping it false (or letting the manager reset it after 2s).
    func shake(active: Bool) -> some View {
        modifier(ShakeModifier(active: active))
    }
}

private struct ShakeModifier: ViewModifier {
    let active: Bool
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: progress))
            .onChange(of: active) { newValue in
                if newValue {
                    progress = 0
                    withAnimation(.linear(duration: 0.55)) {
                        progress = 1
                    }
                }
            }
    }
}
