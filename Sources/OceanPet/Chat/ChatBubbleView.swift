import SwiftUI

public struct ChatBubbleView: View {
    @ObservedObject var store: ChatStore
    let onClose: () -> Void
    let onRecoverError: (ChatStore.ErrorRecoveryAction) -> Void

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.black.opacity(0.85))
            messages
            if let error = store.errorText {
                errorBanner(error)
            }
            composer
        }
        .frame(width: 390, height: 410)
        .background(Color(red: 1.0, green: 0.97, blue: 0.79))
        .overlay(Rectangle().stroke(Color.black.opacity(0.88), lineWidth: 3))
        .shadow(color: .black.opacity(0.22), radius: 0, x: 6, y: 6)
        .padding(8)
        .background(Color.clear)
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(Color(red: 0.99, green: 0.83, blue: 0.12))
                Text("▦")
                    .font(.custom("Menlo-Bold", size: 18))
            }
            .frame(width: 30, height: 30)
            .overlay(Rectangle().stroke(.black, lineWidth: 2))

            VStack(alignment: .leading, spacing: 1) {
                Text("比奇堡热线")
                    .font(.custom("Hiragino Sans GB W6", size: 14))
                Text(store.voiceStatus ?? (store.isSending ? "正在想一个好主意…" : "DeepSeek · 在线"))
                    .font(.custom("Menlo", size: 9))
                    .foregroundStyle(.black.opacity(0.58))
            }
            Spacer()
            Button(action: onClose) {
                Text("×")
                    .font(.custom("Menlo-Bold", size: 18))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(PixelButtonStyle(fill: Color(red: 0.98, green: 0.43, blue: 0.25)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(red: 0.23, green: 0.78, blue: 0.82))
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.messages) { message in
                        HStack {
                            if message.role == .user { Spacer(minLength: 48) }
                            Text(message.content)
                                .font(.custom("Hiragino Sans GB", size: 13))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(message.role == .user
                                    ? Color(red: 0.60, green: 0.89, blue: 0.91)
                                    : Color.white.opacity(0.82))
                                .overlay(Rectangle().stroke(.black.opacity(0.78), lineWidth: 2))
                            if message.role == .assistant { Spacer(minLength: 48) }
                        }
                        .id(message.id)
                    }
                    if store.isSending {
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle().frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(Color(red: 0.16, green: 0.58, blue: 0.64))
                        .padding(10)
                    }
                }
                .padding(13)
            }
            .background(
                ZStack {
                    Color(red: 1.0, green: 0.98, blue: 0.86)
                    PixelDotPattern().opacity(0.15)
                }
            )
            .onChange(of: store.messages.count) { _, _ in
                if let id = store.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!").font(.custom("Menlo-Bold", size: 13))
            Text(text)
                .font(.custom("Hiragino Sans GB", size: 11))
                .lineLimit(2)
            Spacer()
            if let recovery = store.errorRecoveryAction {
                Button(recovery.buttonTitle) {
                    onRecoverError(recovery)
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color(red: 1.0, green: 0.76, blue: 0.63))
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("和\(store.characterName)说点什么…", text: $store.input)
                .textFieldStyle(.plain)
                .font(.custom("Hiragino Sans GB", size: 13))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.white.opacity(0.9))
                .overlay(Rectangle().stroke(.black.opacity(0.8), lineWidth: 2))
                .onSubmit(store.send)
                .disabled(store.isSending || store.isListening)

            Button(action: store.toggleVoiceInput) {
                Text(store.isListening ? "■" : "🎤")
                    .font(.system(size: store.isListening ? 13 : 15, weight: .bold))
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(PixelButtonStyle(fill: store.isListening
                ? Color(red: 0.98, green: 0.43, blue: 0.25)
                : Color.white.opacity(0.9)))
            .disabled(store.isSending)

            Button(action: store.send) {
                Text("发送")
                    .font(.custom("Hiragino Sans GB W6", size: 12))
                    .frame(width: 48, height: 30)
            }
            .buttonStyle(PixelButtonStyle(fill: Color(red: 0.98, green: 0.78, blue: 0.10)))
            .disabled(store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending || store.isListening)
        }
        .padding(11)
        .background(Color(red: 0.23, green: 0.78, blue: 0.82))
    }
}

private struct PixelButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black.opacity(0.86))
            .background(fill.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay(Rectangle().stroke(.black.opacity(0.86), lineWidth: 2))
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

private struct PixelDotPattern: View {
    var body: some View {
        Canvas { context, size in
            let dot = Path(CGRect(x: 0, y: 0, width: 2, height: 2))
            for x in stride(from: 8.0, through: size.width, by: 18.0) {
                for y in stride(from: 8.0, through: size.height, by: 18.0) {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(.black))
                }
            }
        }
    }
}
