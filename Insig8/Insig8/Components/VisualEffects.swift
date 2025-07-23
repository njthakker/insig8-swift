import SwiftUI
import AppKit

// MARK: - Enhanced Blur Effects
struct BlurEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    
    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Blur Variants
extension BlurEffect {
    // Common blur presets
    static let sidebar = BlurEffect(material: .sidebar, blendingMode: .behindWindow)
    static let menu = BlurEffect(material: .menu, blendingMode: .behindWindow)
    static let popover = BlurEffect(material: .popover, blendingMode: .behindWindow)
    static let headerView = BlurEffect(material: .headerView, blendingMode: .withinWindow)
    static let sheet = BlurEffect(material: .sheet, blendingMode: .withinWindow)
    static let windowBackground = BlurEffect(material: .windowBackground, blendingMode: .behindWindow)
    static let hudWindow = BlurEffect(material: .hudWindow, blendingMode: .behindWindow)
    
    // Dynamic blur based on system appearance
    static let adaptive: BlurEffect = {
        BlurEffect(material: .sidebar, blendingMode: .behindWindow, state: .active)
    }()
}

// MARK: - Glassmorphism Effect
struct GlassmorphismEffect: View {
    let intensity: Double
    let tintColor: Color
    let borderOpacity: Double
    
    init(
        intensity: Double = 0.1,
        tintColor: Color = .white,
        borderOpacity: Double = 0.2
    ) {
        self.intensity = intensity
        self.tintColor = tintColor
        self.borderOpacity = borderOpacity
    }
    
    var body: some View {
        ZStack {
            // Base blur
            BlurEffect.adaptive
            
            // Tint overlay
            tintColor
                .opacity(intensity)
            
            // Subtle border
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(
                    LinearGradient(
                        colors: [
                            tintColor.opacity(borderOpacity),
                            tintColor.opacity(borderOpacity * 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Gradient Effects
struct GradientBackground: View {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let animated: Bool
    
    @State private var animationOffset: CGFloat = 0
    
    init(
        colors: [Color],
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing,
        animated: Bool = false
    ) {
        self.colors = colors
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.animated = animated
    }
    
    var body: some View {
        if animated {
            animatedGradient
        } else {
            staticGradient
        }
    }
    
    private var staticGradient: some View {
        LinearGradient(
            colors: colors,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
    
    private var animatedGradient: some View {
        LinearGradient(
            colors: colors,
            startPoint: UnitPoint(
                x: startPoint.x + sin(animationOffset) * 0.1,
                y: startPoint.y + cos(animationOffset) * 0.1
            ),
            endPoint: UnitPoint(
                x: endPoint.x + cos(animationOffset) * 0.1,
                y: endPoint.y + sin(animationOffset) * 0.1
            )
        )
        .onAppear {
            withAnimation(
                .linear(duration: 8)
                .repeatForever(autoreverses: false)
            ) {
                animationOffset = .pi * 2
            }
        }
    }
}

// MARK: - Particle Effect
struct ParticleEffect: View {
    let particleCount: Int
    let colors: [Color]
    let size: CGSize
    
    @State private var particles: [Particle] = []
    
    init(
        particleCount: Int = 20,
        colors: [Color] = [.blue, .purple, .pink],
        size: CGSize = CGSize(width: 4, height: 4)
    ) {
        self.particleCount = particleCount
        self.colors = colors
        self.size = size
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles.indices, id: \.self) { index in
                    Circle()
                        .fill(particles[index].color)
                        .frame(width: size.width, height: size.height)
                        .position(particles[index].position)
                        .opacity(particles[index].opacity)
                }
            }
        }
        .onAppear {
            setupParticles()
            startAnimation()
        }
    }
    
    private func setupParticles() {
        particles = (0..<particleCount).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...200),
                    y: CGFloat.random(in: 0...200)
                ),
                color: colors.randomElement() ?? .blue,
                opacity: Double.random(in: 0.3...0.8)
            )
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                updateParticles()
            }
        }
    }
    
    private func updateParticles() {
        for index in particles.indices {
            particles[index].position.y -= CGFloat.random(in: 0.5...2)
            particles[index].position.x += CGFloat.random(in: -1...1)
            
            if particles[index].position.y < -size.height {
                particles[index].position.y = 220
                particles[index].position.x = CGFloat.random(in: 0...200)
            }
        }
    }
    
    struct Particle {
        var position: CGPoint
        let color: Color
        var opacity: Double
    }
}

// MARK: - Loading Shimmer Effect
struct ShimmerEffect: View {
    @State private var animationOffset: CGFloat = -1
    
    let gradient = LinearGradient(
        colors: [
            Color.clear,
            DesignTokens.Colors.onSurface.opacity(0.1),
            Color.clear
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        Rectangle()
            .fill(gradient)
            .offset(x: animationOffset * 400) // Use fixed width for macOS
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    animationOffset = 1
                }
            }
    }
}

// MARK: - Skeleton Loading
struct SkeletonView: View {
    let style: Style
    
    enum Style {
        case text(lines: Int)
        case avatar
        case card
        case button
        case custom(width: CGFloat, height: CGFloat)
    }
    
    var body: some View {
        Group {
            switch style {
            case .text(let lines):
                textSkeleton(lines: lines)
            case .avatar:
                avatarSkeleton
            case .card:
                cardSkeleton
            case .button:
                buttonSkeleton
            case .custom(let width, let height):
                customSkeleton(width: width, height: height)
            }
        }
        .overlay(ShimmerEffect())
        .clipped()
    }
    
    private func textSkeleton(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ForEach(0..<lines, id: \.self) { index in
                Rectangle()
                    .fill(DesignTokens.Colors.surfaceVariant)
                    .frame(height: 16)
                    .frame(width: index == lines - 1 ? 120 : nil)
                    .cornerRadius(DesignTokens.Radius.xs)
            }
        }
    }
    
    private var avatarSkeleton: some View {
        Circle()
            .fill(DesignTokens.Colors.surfaceVariant)
            .frame(width: 40, height: 40)
    }
    
    private var cardSkeleton: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .fill(DesignTokens.Colors.surfaceVariant)
            .frame(height: 100)
    }
    
    private var buttonSkeleton: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(DesignTokens.Colors.surfaceVariant)
            .frame(width: 100, height: 36)
    }
    
    private func customSkeleton(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(DesignTokens.Colors.surfaceVariant)
            .frame(width: width, height: height)
    }
}

// MARK: - View Extensions
extension View {
    func blurBackground(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) -> some View {
        background(BlurEffect(material: material, blendingMode: blendingMode))
    }
    
    func glassmorphism(
        intensity: Double = 0.1,
        tintColor: Color = .white,
        borderOpacity: Double = 0.2
    ) -> some View {
        background(
            GlassmorphismEffect(
                intensity: intensity,
                tintColor: tintColor,
                borderOpacity: borderOpacity
            )
        )
    }
    
    func shimmerLoading() -> some View {
        overlay(ShimmerEffect())
            .clipped()
    }
}

#Preview("Visual Effects") {
    VStack(spacing: DesignTokens.Spacing.lg) {
        // Blur examples
        Text("Blur Effect")
            .padding()
            .blurBackground()
        
        // Glassmorphism
        Text("Glassmorphism")
            .padding()
            .glassmorphism()
        
        // Skeleton loading
        VStack {
            SkeletonView(style: .text(lines: 3))
            SkeletonView(style: .avatar)
            SkeletonView(style: .card)
        }
        
        // Gradient
        Text("Animated Gradient")
            .padding()
            .background(
                GradientBackground(
                    colors: [.blue, .purple, .pink],
                    animated: true
                )
            )
    }
    .padding()
}