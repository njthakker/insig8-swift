import SwiftUI
import Combine
import AppKit

struct EmojiWidgetView: View {
    @StateObject private var emojiStore = EmojiStore()
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Category selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(EmojiCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            category: category,
                            isSelected: emojiStore.selectedCategory == category,
                            action: { emojiStore.selectedCategory = category }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Emoji grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(50)), count: 10), spacing: 10) {
                    ForEach(emojiStore.filteredEmojis(for: appStore.searchQuery), id: \.self) { emoji in
                        EmojiButton(emoji: emoji) {
                            emojiStore.copyEmoji(emoji)
                            // Close window after copying
                            NSApp.keyWindow?.close()
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct CategoryButton: View {
    let category: EmojiCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(category.icon)
                    .font(.title2)
                
                Text(category.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct EmojiButton: View {
    let emoji: Emoji
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(emoji.character)
                .font(.title)
                .frame(width: 50, height: 50)
                .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(emoji.name)
    }
}

// EmojiStore implementation
@MainActor
class EmojiStore: ObservableObject {
    @Published var selectedCategory: EmojiCategory = .smileys
    @Published var recentEmojis: [Emoji] = []
    
    private let allEmojis: [EmojiCategory: [Emoji]] = [
        .smileys: [
            Emoji("😀", "Grinning Face"),
            Emoji("😃", "Grinning Face with Big Eyes"),
            Emoji("😄", "Grinning Face with Smiling Eyes"),
            Emoji("😁", "Beaming Face with Smiling Eyes"),
            Emoji("😅", "Grinning Face with Sweat"),
            Emoji("😂", "Face with Tears of Joy"),
            Emoji("🤣", "Rolling on the Floor Laughing"),
            Emoji("😊", "Smiling Face with Smiling Eyes"),
            Emoji("😇", "Smiling Face with Halo"),
            Emoji("🙂", "Slightly Smiling Face"),
            Emoji("🙃", "Upside-Down Face"),
            Emoji("😉", "Winking Face"),
            Emoji("😌", "Relieved Face"),
            Emoji("😍", "Smiling Face with Heart-Eyes"),
            Emoji("🥰", "Smiling Face with Hearts"),
            Emoji("😘", "Face Blowing a Kiss"),
            Emoji("😗", "Kissing Face"),
            Emoji("😙", "Kissing Face with Smiling Eyes"),
            Emoji("😚", "Kissing Face with Closed Eyes"),
            Emoji("😋", "Face Savoring Food"),
            Emoji("😛", "Face with Tongue"),
            Emoji("😜", "Winking Face with Tongue"),
            Emoji("🤪", "Zany Face"),
            Emoji("😝", "Squinting Face with Tongue"),
            Emoji("🤑", "Money-Mouth Face"),
            Emoji("🤗", "Hugging Face"),
            Emoji("🤭", "Face with Hand Over Mouth"),
            Emoji("🤫", "Shushing Face"),
            Emoji("🤔", "Thinking Face"),
            Emoji("🤐", "Zipper-Mouth Face"),
            Emoji("🤨", "Face with Raised Eyebrow"),
            Emoji("😐", "Neutral Face"),
            Emoji("😑", "Expressionless Face"),
            Emoji("😶", "Face Without Mouth"),
            Emoji("😏", "Smirking Face"),
            Emoji("😒", "Unamused Face"),
            Emoji("🙄", "Face with Rolling Eyes"),
            Emoji("😬", "Grimacing Face"),
            Emoji("🤥", "Lying Face"),
            Emoji("😌", "Relieved Face"),
            Emoji("😔", "Pensive Face"),
            Emoji("😪", "Sleepy Face"),
            Emoji("🤤", "Drooling Face"),
            Emoji("😴", "Sleeping Face")
        ],
        .animals: [
            Emoji("🐶", "Dog Face"),
            Emoji("🐱", "Cat Face"),
            Emoji("🐭", "Mouse Face"),
            Emoji("🐹", "Hamster"),
            Emoji("🐰", "Rabbit Face"),
            Emoji("🦊", "Fox"),
            Emoji("🐻", "Bear"),
            Emoji("🐼", "Panda"),
            Emoji("🐨", "Koala"),
            Emoji("🐯", "Tiger Face"),
            Emoji("🦁", "Lion"),
            Emoji("🐮", "Cow Face"),
            Emoji("🐷", "Pig Face"),
            Emoji("🐸", "Frog"),
            Emoji("🐵", "Monkey Face"),
            Emoji("🙈", "See-No-Evil Monkey"),
            Emoji("🙉", "Hear-No-Evil Monkey"),
            Emoji("🙊", "Speak-No-Evil Monkey"),
            Emoji("🐒", "Monkey"),
            Emoji("🐔", "Chicken"),
            Emoji("🐧", "Penguin"),
            Emoji("🐦", "Bird"),
            Emoji("🐤", "Baby Chick"),
            Emoji("🦆", "Duck"),
            Emoji("🦅", "Eagle"),
            Emoji("🦉", "Owl"),
            Emoji("🦇", "Bat"),
            Emoji("🐺", "Wolf"),
            Emoji("🐗", "Boar"),
            Emoji("🐴", "Horse Face")
        ],
        .foods: [
            Emoji("🍎", "Red Apple"),
            Emoji("🍐", "Pear"),
            Emoji("🍊", "Tangerine"),
            Emoji("🍋", "Lemon"),
            Emoji("🍌", "Banana"),
            Emoji("🍉", "Watermelon"),
            Emoji("🍇", "Grapes"),
            Emoji("🍓", "Strawberry"),
            Emoji("🍈", "Melon"),
            Emoji("🍒", "Cherries"),
            Emoji("🍑", "Peach"),
            Emoji("🥭", "Mango"),
            Emoji("🍍", "Pineapple"),
            Emoji("🥥", "Coconut"),
            Emoji("🥝", "Kiwi Fruit"),
            Emoji("🍅", "Tomato"),
            Emoji("🍆", "Eggplant"),
            Emoji("🥑", "Avocado"),
            Emoji("🥦", "Broccoli"),
            Emoji("🥬", "Leafy Green"),
            Emoji("🥒", "Cucumber"),
            Emoji("🌶", "Hot Pepper"),
            Emoji("🌽", "Corn"),
            Emoji("🥕", "Carrot"),
            Emoji("🥔", "Potato"),
            Emoji("🍠", "Sweet Potato"),
            Emoji("🥐", "Croissant"),
            Emoji("🍞", "Bread"),
            Emoji("🥖", "Baguette"),
            Emoji("🥨", "Pretzel"),
            Emoji("🧀", "Cheese"),
            Emoji("🥚", "Egg"),
            Emoji("🍳", "Fried Egg"),
            Emoji("🥞", "Pancakes"),
            Emoji("🥓", "Bacon"),
            Emoji("🥩", "Steak"),
            Emoji("🍗", "Poultry Leg"),
            Emoji("🍖", "Meat on Bone"),
            Emoji("🌭", "Hot Dog"),
            Emoji("🍔", "Hamburger"),
            Emoji("🍟", "French Fries"),
            Emoji("🍕", "Pizza"),
            Emoji("🥪", "Sandwich"),
            Emoji("🌮", "Taco"),
            Emoji("🌯", "Burrito")
        ],
        .activities: [
            Emoji("⚽", "Soccer Ball"),
            Emoji("🏀", "Basketball"),
            Emoji("🏈", "American Football"),
            Emoji("⚾", "Baseball"),
            Emoji("🥎", "Softball"),
            Emoji("🎾", "Tennis"),
            Emoji("🏐", "Volleyball"),
            Emoji("🏉", "Rugby"),
            Emoji("🎱", "Pool 8 Ball"),
            Emoji("🏓", "Ping Pong"),
            Emoji("🏸", "Badminton"),
            Emoji("🏒", "Ice Hockey"),
            Emoji("🏑", "Field Hockey"),
            Emoji("🥍", "Lacrosse"),
            Emoji("🏏", "Cricket"),
            Emoji("⛳", "Flag in Hole"),
            Emoji("🏹", "Bow and Arrow"),
            Emoji("🎣", "Fishing Pole"),
            Emoji("🤿", "Diving Mask"),
            Emoji("🥊", "Boxing Glove"),
            Emoji("🥋", "Martial Arts Uniform"),
            Emoji("🎽", "Running Shirt"),
            Emoji("🛹", "Skateboard"),
            Emoji("🛷", "Sled"),
            Emoji("⛸", "Ice Skate"),
            Emoji("🥌", "Curling Stone"),
            Emoji("🎿", "Skis"),
            Emoji("⛷", "Skier"),
            Emoji("🏂", "Snowboarder")
        ],
        .objects: [
            Emoji("⌚", "Watch"),
            Emoji("📱", "Mobile Phone"),
            Emoji("📲", "Mobile Phone with Arrow"),
            Emoji("💻", "Laptop"),
            Emoji("⌨️", "Keyboard"),
            Emoji("🖥", "Desktop Computer"),
            Emoji("🖨", "Printer"),
            Emoji("🖱", "Computer Mouse"),
            Emoji("🖲", "Trackball"),
            Emoji("🕹", "Joystick"),
            Emoji("🗜", "Clamp"),
            Emoji("💾", "Floppy Disk"),
            Emoji("💿", "Optical Disk"),
            Emoji("📀", "DVD"),
            Emoji("📼", "Videocassette"),
            Emoji("📷", "Camera"),
            Emoji("📸", "Camera with Flash"),
            Emoji("📹", "Video Camera"),
            Emoji("🎥", "Movie Camera"),
            Emoji("📽", "Film Projector"),
            Emoji("🎞", "Film Frames"),
            Emoji("📞", "Telephone Receiver"),
            Emoji("☎️", "Telephone"),
            Emoji("📟", "Pager"),
            Emoji("📠", "Fax Machine"),
            Emoji("📺", "Television"),
            Emoji("📻", "Radio"),
            Emoji("🎙", "Studio Microphone"),
            Emoji("🎚", "Level Slider"),
            Emoji("🎛", "Control Knobs")
        ],
        .symbols: [
            Emoji("❤️", "Red Heart"),
            Emoji("🧡", "Orange Heart"),
            Emoji("💛", "Yellow Heart"),
            Emoji("💚", "Green Heart"),
            Emoji("💙", "Blue Heart"),
            Emoji("💜", "Purple Heart"),
            Emoji("🖤", "Black Heart"),
            Emoji("🤍", "White Heart"),
            Emoji("🤎", "Brown Heart"),
            Emoji("💔", "Broken Heart"),
            Emoji("❣️", "Heart Exclamation"),
            Emoji("💕", "Two Hearts"),
            Emoji("💞", "Revolving Hearts"),
            Emoji("💓", "Beating Heart"),
            Emoji("💗", "Growing Heart"),
            Emoji("💖", "Sparkling Heart"),
            Emoji("💘", "Heart with Arrow"),
            Emoji("💝", "Heart with Ribbon"),
            Emoji("💟", "Heart Decoration"),
            Emoji("☮️", "Peace Symbol"),
            Emoji("✝️", "Latin Cross"),
            Emoji("☪️", "Star and Crescent"),
            Emoji("🕉", "Om"),
            Emoji("☸️", "Wheel of Dharma"),
            Emoji("✡️", "Star of David"),
            Emoji("🔯", "Six-Pointed Star with Middle Dot"),
            Emoji("🕎", "Menorah"),
            Emoji("☯️", "Yin Yang"),
            Emoji("☦️", "Orthodox Cross"),
            Emoji("🛐", "Place of Worship"),
            Emoji("⛎", "Ophiuchus"),
            Emoji("♈", "Aries"),
            Emoji("♉", "Taurus"),
            Emoji("♊", "Gemini"),
            Emoji("♋", "Cancer"),
            Emoji("♌", "Leo"),
            Emoji("♍", "Virgo"),
            Emoji("♎", "Libra"),
            Emoji("♏", "Scorpio"),
            Emoji("♐", "Sagittarius"),
            Emoji("♑", "Capricorn"),
            Emoji("♒", "Aquarius"),
            Emoji("♓", "Pisces")
        ]
    ]
    
    init() {
        loadRecentEmojis()
    }
    
    func filteredEmojis(for query: String) -> [Emoji] {
        let emojis = allEmojis[selectedCategory] ?? []
        
        guard !query.isEmpty else { return emojis }
        
        let lowercasedQuery = query.lowercased()
        return emojis.filter { emoji in
            emoji.name.lowercased().contains(lowercasedQuery)
        }
    }
    
    func copyEmoji(_ emoji: Emoji) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(emoji.character, forType: .string)
        
        // Add to recent emojis
        recentEmojis.removeAll { $0.character == emoji.character }
        recentEmojis.insert(emoji, at: 0)
        
        if recentEmojis.count > 20 {
            recentEmojis = Array(recentEmojis.prefix(20))
        }
        
        saveRecentEmojis()
    }
    
    private func loadRecentEmojis() {
        // Load from UserDefaults
    }
    
    private func saveRecentEmojis() {
        // Save to UserDefaults
    }
}

struct Emoji: Hashable {
    let character: String
    let name: String
    
    init(_ character: String, _ name: String) {
        self.character = character
        self.name = name
    }
}

enum EmojiCategory: String, CaseIterable {
    case smileys = "Smileys"
    case animals = "Animals"
    case foods = "Food"
    case activities = "Activities"
    case objects = "Objects"
    case symbols = "Symbols"
    
    var name: String { rawValue }
    
    var icon: String {
        switch self {
        case .smileys: return "😀"
        case .animals: return "🐶"
        case .foods: return "🍎"
        case .activities: return "⚽"
        case .objects: return "💻"
        case .symbols: return "❤️"
        }
    }
}