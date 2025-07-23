import SwiftUI

// MARK: - Animation Presets
extension Animation {
    // Enhanced timing functions
    static let quickEase = Animation.easeInOut(duration: 0.15)
    static let smoothEase = Animation.easeInOut(duration: 0.25)
    static let slowEase = Animation.easeInOut(duration: 0.35)
    
    // Spring animations
    static let quickSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let smoothSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let bouncySpring = Animation.spring(response: 0.5, dampingFraction: 0.6)
    
    // Specialized animations
    static let slideIn = Animation.easeOut(duration: 0.3)
    static let slideOut = Animation.easeIn(duration: 0.25)
    static let fadeInOut = Animation.easeInOut(duration: 0.2)
    static let scaleEffect = Animation.spring(response: 0.2, dampingFraction: 0.8)
    
    // Complex animations
    static let modalPresentation = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let listItemAppear = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let buttonPress = Animation.spring(response: 0.1, dampingFraction: 0.9)
}

// MARK: - Transition Effects
struct SlideTransition: ViewModifier {
    let edge: Edge
    let distance: CGFloat
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(offsetForEdge)
            .opacity(isActive ? 1 : 0)
    }
    
    private var offsetForEdge: CGSize {
        guard !isActive else { return .zero }
        
        switch edge {
        case .top:
            return CGSize(width: 0, height: -distance)
        case .bottom:
            return CGSize(width: 0, height: distance)
        case .leading:
            return CGSize(width: -distance, height: 0)
        case .trailing:
            return CGSize(width: distance, height: 0)
        }
    }
}

struct ScaleTransition: ViewModifier {
    let scale: CGFloat
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1 : scale)
            .opacity(isActive ? 1 : 0)
    }
}

struct FadeTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
    }
}

struct RotationTransition: ViewModifier {
    let degrees: Double
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? 0 : degrees))
            .opacity(isActive ? 1 : 0)
    }
}

// MARK: - Interactive Animations
struct PressAnimation: ViewModifier {
    @State private var isPressed = false
    let scale: CGFloat
    let animation: Animation
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(animation, value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

struct HoverAnimation: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat
    let animation: Animation
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(animation, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct ShakeAnimation: ViewModifier {
    let isShaking: Bool
    @State private var shakeOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: isShaking) { _, shaking in
                if shaking {
                    startShaking()
                }
            }
    }
    
    private func startShaking() {
        let animation = Animation.linear(duration: 0.05).repeatCount(6, autoreverses: true)
        withAnimation(animation) {
            shakeOffset = 5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shakeOffset = 0
        }
    }
}

struct PulseAnimation: ViewModifier {
    let isActive: Bool
    @State private var pulse = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.1 : 1.0)
            .opacity(pulse ? 0.8 : 1.0)
            .onAppear {
                if isActive {
                    startPulsing()
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    startPulsing()
                } else {
                    stopPulsing()
                }
            }
    }
    
    private func startPulsing() {
        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
    
    private func stopPulsing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pulse = false
        }
    }
}

// MARK: - Loading Animations
struct SpinnerAnimation: View {
    @State private var rotation: Double = 0
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    init(size: CGFloat = 20, lineWidth: CGFloat = 2, color: Color = .accentColor) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color.opacity(0.1), color]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: rotation))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct DotsAnimation: View {
    @State private var animationIndex = 0
    let dotCount: Int
    let size: CGFloat
    let color: Color
    
    init(dotCount: Int = 3, size: CGFloat = 8, color: Color = .accentColor) {
        self.dotCount = dotCount
        self.size = size
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .scaleEffect(animationIndex == index ? 1.2 : 1.0)
                    .opacity(animationIndex == index ? 1.0 : 0.5)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationIndex = (animationIndex + 1) % dotCount
            }
        }
    }
}

struct ProgressBarAnimation: View {
    let progress: Double
    let height: CGFloat
    let backgroundColor: Color
    let foregroundColor: Color
    let cornerRadius: CGFloat
    
    init(
        progress: Double,
        height: CGFloat = 8,
        backgroundColor: Color = Color.gray.opacity(0.2),
        foregroundColor: Color = .accentColor,
        cornerRadius: CGFloat = 4
    ) {
        self.progress = progress
        self.height = height
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Page Transitions
struct PageTransition: ViewModifier {
    let transition: PageTransitionType
    let isPresented: Bool
    
    enum PageTransitionType {
        case slide(Edge)
        case scale
        case fade
        case move(Edge)
        case opacity
    }
    
    func body(content: Content) -> some View {
        content
            .transition(transitionEffect)
    }
    
    private var transitionEffect: AnyTransition {
        switch transition {
        case .slide(_):
            return .slide
        case .scale:
            return .scale.combined(with: .opacity)
        case .fade:
            return .opacity
        case .move(let edge):
            return .move(edge: edge)
        case .opacity:
            return .opacity.animation(.easeInOut(duration: 0.2))
        }
    }
}

// MARK: - Stagger Animation
struct StaggeredAppear<Content: View>: View {
    let content: Content
    let delay: Double
    let staggerDelay: Double
    
    @State private var appeared = false
    
    init(
        delay: Double = 0,
        staggerDelay: Double = 0.1,
        @ViewBuilder content: () -> Content
    ) {
        self.delay = delay
        self.staggerDelay = staggerDelay
        self.content = content()
    }
    
    var body: some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    // Transition effects
    func slideTransition(
        from edge: Edge,
        distance: CGFloat = 300,
        isActive: Bool
    ) -> some View {
        modifier(SlideTransition(edge: edge, distance: distance, isActive: isActive))
    }
    
    func scaleTransition(scale: CGFloat = 0.8, isActive: Bool) -> some View {
        modifier(ScaleTransition(scale: scale, isActive: isActive))
    }
    
    func fadeTransition(isActive: Bool) -> some View {
        modifier(FadeTransition(isActive: isActive))
    }
    
    func rotationTransition(degrees: Double = 90, isActive: Bool) -> some View {
        modifier(RotationTransition(degrees: degrees, isActive: isActive))
    }
    
    // Interactive animations
    func pressAnimation(
        scale: CGFloat = 0.95,
        animation: Animation = .quickSpring
    ) -> some View {
        modifier(PressAnimation(scale: scale, animation: animation))
    }
    
    func hoverAnimation(
        scale: CGFloat = 1.05,
        animation: Animation = .quickSpring
    ) -> some View {
        modifier(HoverAnimation(scale: scale, animation: animation))
    }
    
    func shake(isShaking: Bool) -> some View {
        modifier(ShakeAnimation(isShaking: isShaking))
    }
    
    func pulse(isActive: Bool) -> some View {
        modifier(PulseAnimation(isActive: isActive))
    }
    
    // Page transitions
    func pageTransition(
        _ type: PageTransition.PageTransitionType,
        isPresented: Bool
    ) -> some View {
        modifier(PageTransition(transition: type, isPresented: isPresented))
    }
    
    // Staggered animations
    func staggeredAppear(delay: Double = 0, staggerDelay: Double = 0.1) -> some View {
        StaggeredAppear(delay: delay, staggerDelay: staggerDelay) {
            self
        }
    }
    
    // Conditional animations
    func animatedChange<T: Equatable>(
        _ value: T,
        animation: Animation = .default
    ) -> some View {
        self.animation(animation, value: value)
    }
    
    func conditionalTransition<T: Equatable>(
        _ condition: T,
        transition: AnyTransition
    ) -> some View {
        self.transition(transition)
    }
}

#Preview("Animation System") {
    ScrollView {
        VStack(spacing: DesignTokens.Spacing.xl) {
            // Loading animations
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("Loading Animations")
                    .font(DesignTokens.Typography.headline)
                
                HStack(spacing: DesignTokens.Spacing.lg) {
                    SpinnerAnimation()
                    DotsAnimation()
                    ProgressBarAnimation(progress: 0.7)
                        .frame(width: 100)
                }
            }
            .cardLayout()
            
            // Interactive animations
            VStack(spacing: DesignTokens.Spacing.md) {
                Text("Interactive Effects")
                    .font(DesignTokens.Typography.headline)
                
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text("Press Me")
                        .padding()
                        .background(DesignTokens.Colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(DesignTokens.Radius.md)
                        .pressAnimation()
                    
                    Text("Hover Me")
                        .padding()
                        .background(DesignTokens.Colors.surfaceVariant)
                        .cornerRadius(DesignTokens.Radius.md)
                        .hoverAnimation()
                }
            }
            .cardLayout()
            
            // Staggered appear
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Staggered Animation")
                    .font(DesignTokens.Typography.headline)
                
                ForEach(0..<4) { index in
                    Text("Item \(index + 1)")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.surfaceVariant)
                        .cornerRadius(DesignTokens.Radius.sm)
                        .staggeredAppear(delay: Double(index) * 0.1)
                }
            }
            .cardLayout()
        }
        .padding()
    }
}