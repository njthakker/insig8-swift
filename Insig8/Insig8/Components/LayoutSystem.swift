import SwiftUI

// MARK: - Responsive Container
struct ResponsiveContainer<Content: View>: View {
    let content: Content
    let breakpoints: Breakpoints
    
    @State private var windowSize: CGSize = .zero
    
    struct Breakpoints {
        let compact: CGFloat
        let regular: CGFloat
        let large: CGFloat
        
        // Move default outside of generic type
        static func `default`() -> Breakpoints {
            return Breakpoints(
                compact: 400,
                regular: 600,
                large: 800
            )
        }
    }
    
    init(
        breakpoints: Breakpoints = Breakpoints.default(),
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.breakpoints = breakpoints
    }
    
    var body: some View {
        content
            .environment(\.sizeClass, currentSizeClass)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            windowSize = geometry.size
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            windowSize = newSize
                        }
                }
            )
    }
    
    private var currentSizeClass: SizeClass {
        if windowSize.width < breakpoints.compact {
            return .compact
        } else if windowSize.width < breakpoints.regular {
            return .regular
        } else {
            return .large
        }
    }
}

// MARK: - Size Class Environment
enum SizeClass {
    case compact, regular, large
}

private struct SizeClassKey: EnvironmentKey {
    static let defaultValue: SizeClass = .regular
}

extension EnvironmentValues {
    var sizeClass: SizeClass {
        get { self[SizeClassKey.self] }
        set { self[SizeClassKey.self] = newValue }
    }
}

// MARK: - Flexible Grid
struct FlexibleGrid<Content: View>: View {
    let content: Content
    let columns: GridColumns
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    
    enum GridColumns {
        case fixed(Int)
        case adaptive(minimum: CGFloat)
        case flexible(minimum: CGFloat, maximum: CGFloat)
    }
    
    init(
        columns: GridColumns,
        spacing: CGFloat = DesignTokens.Spacing.md,
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.columns = columns
        self.spacing = spacing
        self.alignment = alignment
    }
    
    var body: some View {
        LazyVGrid(columns: gridItems, alignment: alignment, spacing: spacing) {
            content
        }
    }
    
    private var gridItems: [GridItem] {
        switch columns {
        case .fixed(let count):
            return Array(repeating: GridItem(.flexible()), count: count)
        case .adaptive(let minimum):
            return [GridItem(.adaptive(minimum: minimum))]
        case .flexible(let minimum, let maximum):
            return [GridItem(.flexible(minimum: minimum, maximum: maximum))]
        }
    }
}

// MARK: - Stack Layout
struct AdaptiveStack<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    let threshold: CGFloat
    
    @Environment(\.sizeClass) private var sizeClass
    
    init(
        spacing: CGFloat = DesignTokens.Spacing.md,
        threshold: CGFloat = 400,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.spacing = spacing
        self.threshold = threshold
    }
    
    var body: some View {
        if sizeClass == .compact {
            VStack(spacing: spacing) {
                content
            }
        } else {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Card Layout
struct CardLayout<Content: View>: View {
    let content: Content
    let style: CardStyle.Variant
    let padding: EdgeInsets
    
    init(
        style: CardStyle.Variant = .elevated,
        padding: EdgeInsets = EdgeInsets(
            top: DesignTokens.Spacing.lg,
            leading: DesignTokens.Spacing.lg,
            bottom: DesignTokens.Spacing.lg,
            trailing: DesignTokens.Spacing.lg
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.style = style
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .cardStyle(style)
    }
}

// MARK: - Sidebar Layout
struct SidebarLayout<Sidebar: View, Content: View>: View {
    let sidebar: Sidebar
    let content: Content
    let sidebarWidth: CGFloat
    let showSidebar: Bool
    
    @Environment(\.sizeClass) private var sizeClass
    
    init(
        sidebarWidth: CGFloat = 200,
        showSidebar: Bool = true,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.sidebarWidth = sidebarWidth
        self.showSidebar = showSidebar
    }
    
    var body: some View {
        if sizeClass == .compact || !showSidebar {
            content
        } else {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .background(DesignTokens.Colors.surfaceSecondary)
                
                Divider()
                
                content
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout<Content: View>: View {
    let content: Content
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    
    init(
        spacing: CGFloat = DesignTokens.Spacing.sm,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
    }
    
    var body: some View {
        _FlowLayout(
            spacing: spacing,
            alignment: alignment
        ) {
            content
        }
    }
}

// Flow layout implementation
private struct _FlowLayout: Layout {
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, in: proposal.replacingUnspecifiedDimensions()).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let layoutResult = layout(sizes: sizes, in: bounds.size)
        
        for (index, position) in layoutResult.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(sizes: [CGSize], in containerSize: CGSize) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentRow: [Int] = []
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        for (index, size) in sizes.enumerated() {
            if currentRowWidth + size.width + (currentRow.isEmpty ? 0 : spacing) <= containerSize.width || currentRow.isEmpty {
                // Fits in current row
                currentRow.append(index)
                currentRowWidth += size.width + (currentRow.count > 1 ? spacing : 0)
            } else {
                // Place current row and start new one
                placeRow(currentRow, sizes: sizes, rowWidth: currentRowWidth, y: totalHeight, positions: &positions)
                totalHeight += currentRow.map { sizes[$0].height }.max() ?? 0
                totalHeight += spacing
                maxWidth = max(maxWidth, currentRowWidth)
                
                currentRow = [index]
                currentRowWidth = size.width
            }
        }
        
        // Place last row
        if !currentRow.isEmpty {
            placeRow(currentRow, sizes: sizes, rowWidth: currentRowWidth, y: totalHeight, positions: &positions)
            totalHeight += currentRow.map { sizes[$0].height }.max() ?? 0
            maxWidth = max(maxWidth, currentRowWidth)
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
    
    private func placeRow(_ row: [Int], sizes: [CGSize], rowWidth: CGFloat, y: CGFloat, positions: inout [CGPoint]) {
        var x: CGFloat = 0
        
        switch alignment {
        case .center:
            x = 0 // FlowLayout will center automatically
        case .trailing:
            x = 0 // Adjust based on container width if needed
        default:
            x = 0
        }
        
        for index in row {
            positions.append(CGPoint(x: x, y: y))
            x += sizes[index].width + spacing
        }
    }
}

// MARK: - List Layout
struct EnhancedList<Content: View>: View {
    let content: Content
    let style: ListStyle
    let spacing: CGFloat
    
    enum ListStyle {
        case plain, insetGrouped, sidebar
    }
    
    init(
        style: ListStyle = .plain,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.style = style
        self.spacing = spacing
    }
    
    var body: some View {
        Group {
            switch style {
            case .plain:
                List {
                    content
                }
                .listStyle(.plain)
            case .insetGrouped:
                List {
                    content
                }
                .listStyle(.plain)
            case .sidebar:
                List {
                    content
                }
                .listStyle(.sidebar)
            }
        }
        .environment(\.defaultMinListRowHeight, spacing > 0 ? spacing : 44)
    }
}

// MARK: - Spacing Helpers
struct LayoutSpacer {
    static func vertical(_ amount: CGFloat) -> some View {
        SwiftUI.Spacer()
            .frame(height: amount)
    }
    
    static func horizontal(_ amount: CGFloat) -> some View {
        SwiftUI.Spacer()
            .frame(width: amount)
    }
}

// MARK: - View Extensions
extension View {
    func responsiveContainer(breakpoints: ResponsiveContainer<AnyView>.Breakpoints = ResponsiveContainer<AnyView>.Breakpoints.default()) -> some View {
        ResponsiveContainer(breakpoints: breakpoints) {
            AnyView(self)
        }
    }
    
    func cardLayout(
        style: CardStyle.Variant = .elevated,
        padding: EdgeInsets = EdgeInsets(
            top: DesignTokens.Spacing.lg,
            leading: DesignTokens.Spacing.lg,
            bottom: DesignTokens.Spacing.lg,
            trailing: DesignTokens.Spacing.lg
        )
    ) -> some View {
        CardLayout(style: style, padding: padding) {
            self
        }
    }
    
    func adaptiveWidth(min: CGFloat = 0, max: CGFloat = .infinity) -> some View {
        frame(minWidth: min, maxWidth: max)
    }
    
    func adaptiveHeight(min: CGFloat = 0, max: CGFloat = .infinity) -> some View {
        frame(minHeight: min, maxHeight: max)
    }
}

#Preview("Layout System") {
    ResponsiveContainer {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Adaptive Stack
            AdaptiveStack {
                Text("Item 1").cardLayout()
                Text("Item 2").cardLayout()
                Text("Item 3").cardLayout()
            }
            
            // Flow Layout
            FlowLayout {
                ForEach(1...8, id: \.self) { i in
                    Text("Tag \(i)")
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(DesignTokens.Colors.primary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            // Flexible Grid
            FlexibleGrid(columns: .adaptive(minimum: 100)) {
                ForEach(1...6, id: \.self) { i in
                    Text("Grid \(i)")
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)
                        .cardLayout()
                }
            }
        }
        .padding()
    }
}