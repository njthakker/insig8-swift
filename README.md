# Insig8 - Native macOS Command Palette

A powerful, Raycast-like command palette launcher built natively for macOS 26 with Apple Intelligence integration.

![macOS](https://img.shields.io/badge/macOS-26.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Xcode](https://img.shields.io/badge/Xcode-26.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Features

### ⚡ Lightning Fast Command Palette
- **Global Hotkey**: Press `⌘ + Period` to instantly open from anywhere
- **Universal Search**: Apps, files, calculations, system actions, web search
- **Smart Results**: Relevance-based sorting with fuzzy matching
- **Calculator**: Evaluate math expressions inline
- **Web Search**: Quick access to search engines

### 🎛️ Widget System
- **Calendar Widget**: View and search calendar events (EventKit integration)
- **Settings Widget**: Complete app preferences and configuration
- **Clipboard Manager**: Clipboard history and management *(coming soon)*
- **Translation Widget**: Text translation between languages *(coming soon)*
- **Utility Widgets**: Emoji picker, process manager, network info *(coming soon)*

### 🎨 Native macOS Experience
- **Menu Bar Integration**: Click menu bar icon for quick access dropdown
- **Auto-Hide Behavior**: Click outside to dismiss, just like native apps
- **Multi-Screen Support**: Works seamlessly across displays and Spaces
- **Theme Support**: Light, Dark, and System theme modes
- **Keyboard Navigation**: Full keyboard control with arrow keys and shortcuts

### ⌨️ Keyboard Shortcuts
- `⌘ + Period` - Open command palette
- `↑/↓ Arrows` - Navigate search results
- `Enter` - Execute selected item
- `Escape` - Progressive back navigation (clear query → close)
- `⌘ + Escape` - Return to search widget
- `⌘ + W` - Close palette
- `⌘ + ,` - Open settings

## 🏗️ Architecture

### Tech Stack
- **SwiftUI + AppKit**: Hybrid architecture for optimal performance
- **Swift 6**: Latest Swift with strict concurrency
- **macOS 26**: Target for Apple Intelligence features
- **EventKit**: Native calendar integration
- **ServiceManagement**: Launch at login functionality
- **Carbon Framework**: Global hotkey registration

### Design Patterns
- **@Observable State Management**: Reactive UI with centralized AppStore
- **Widget Architecture**: Modular system with pluggable widgets
- **Native Window Management**: Custom NSPanel for floating behavior
- **Focus Management**: Proper keyboard navigation and focus control

## 🛠️ Development

### Requirements
- **macOS 26 beta 4+** (Required for Apple Intelligence features)
- **Xcode 26 beta 4+** (Latest Xcode with macOS 26 SDK)
- **Swift 6.0+** (Strict concurrency mode)

### Building
```bash
git clone https://github.com/yourusername/insig8-swift.git
cd insig8-swift
open Insig8.xcodeproj
```

Build and run with `⌘ + R` in Xcode.

### Project Structure
```
Insig8/
├── Components/          # Reusable SwiftUI components
├── Models/             # Data models and state management
├── Services/           # Core services (search, calendar, etc.)
├── Widgets/            # Individual widget implementations
├── Resources/          # Assets and configuration files
└── Supporting Files/   # Info.plist, etc.
```

## 🎯 Migration Story

This project is a complete migration from a React Native app to native SwiftUI/AppKit, targeting macOS 26 for Apple Intelligence integration. The migration preserves all original functionality while providing significant performance improvements and native macOS behavior.

### Migration Phases
- ✅ **Phase 1**: Project setup and configuration
- ✅ **Phase 2**: Enhanced UI components and design system
- ✅ **Phase 3A**: Core infrastructure and essential widgets
- 🔄 **Phase 3B**: Remaining widgets (Calendar ✅, Clipboard, Translation, Utilities)
- 🔮 **Phase 4**: Apple Intelligence integration with Foundation Models
- 🔮 **Phase 5**: Advanced features and optimizations

## 📸 Screenshots

*(Screenshots will be added once UI is finalized)*

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Guidelines
- Follow Swift 6 concurrency patterns
- Maintain macOS 26 compatibility
- Write comprehensive tests
- Update documentation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [Raycast](https://raycast.com) for command palette UX patterns
- Built for macOS 26 to leverage Apple Intelligence capabilities
- Migrated from React Native to provide native performance and integration

---

**Note**: This app targets macOS 26 beta for Apple Intelligence features. A compatible version of macOS and Xcode is required for development and testing.