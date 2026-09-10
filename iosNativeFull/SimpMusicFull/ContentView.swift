import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPlayer = false

    var body: some View {
        TabView(selection: $model.selectedTab) {
            HomeView(showPlayer: $showPlayer)
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }
                .tag(AppTab.home)
            SearchView(showPlayer: $showPlayer)
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            LibraryView(showPlayer: $showPlayer)
                .tabItem { Label("Thư viện", systemImage: "books.vertical.fill") }
                .tag(AppTab.library)
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(.accentColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.player.currentTrack != nil {
                MiniPlayer(showPlayer: $showPlayer)
            }
        }
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .presentationDetents([.large])
        }
        .alert("SimpMusic", isPresented: Binding(
            get: { model.errorMessage != nil || model.player.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil; model.player.errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) {
                model.errorMessage = nil
                model.player.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? model.player.errorMessage ?? "Đã xảy ra lỗi.")
        }
        .preferredColorScheme(model.darkMode ? .dark : .light)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showPlayer: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    moodChips
                    if model.isLoadingHome && model.homeTracks.isEmpty {
                        ProgressView("Đang tải Home YouTube Music…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if model.homeTracks.isEmpty {
                        EmptyState(
                            icon: "wifi.exclamationmark",
                            title: "Chưa tải được trang chủ",
                            message: "Kiểm tra mạng rồi kéo xuống để thử lại."
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        Text("Gợi ý hôm nay")
                            .font(.title2.bold())
                            .padding(.horizontal)
                        LazyVStack(spacing: 0) {
                            ForEach(model.homeTracks) { track in
                                TrackRow(track: track, isResolving: model.isResolvingTrackID == track.id) {
                                    model.playFromHome(track)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .refreshable { model.refreshAll() }
            .navigationTitle("SimpMusic")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.refreshAll() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingHome)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.bold())
            Text("Nghe nhạc từ YouTube Music và SoundCloud")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Chào buổi sáng"
        case 12..<18: return "Chào buổi chiều"
        default: return "Chào buổi tối"
        }
    }

    private var moodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(["Tất cả", "Thư giãn", "Tập trung", "Tập luyện", "Ngủ", "Tiệc"], id: \.self) { mood in
                    Button {
                        if mood != "Tất cả" {
                            model.query = mood + " music"
                            model.selectedTab = .search
                            model.search()
                        }
                    } label: {
                        Text(mood)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showPlayer: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Picker("Nguồn", selection: $model.source) {
                    ForEach(MusicSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if model.isSearching {
                    ProgressView("Đang tìm trên các nguồn nhạc…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.filteredTracks.isEmpty {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "Tìm bài hát, nghệ sĩ hoặc album",
                        message: "Kết quả YouTube Music và SoundCloud sẽ được ghép trong một danh sách."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.filteredTracks) { track in
                        TrackRow(track: track, isResolving: model.isResolvingTrackID == track.id) {
                            model.playFromSearch(track)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                model.toggleFavorite(track)
                            } label: {
                                Label("Yêu thích", systemImage: model.isFavorite(track) ? "heart.slash" : "heart")
                            }
                            .tint(.pink)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tìm kiếm")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Bài hát, nghệ sĩ, album…", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { model.search() }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Button { model.search() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSearching)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showPlayer: Bool
    @State private var filter: LibraryFilter = .favorites
    @State private var showNewPlaylist = false

    private var rows: [MusicTrack] {
        switch filter {
        case .favorites: return model.favorites
        case .history: return model.history
        case .playlists: return model.favorites
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Thư viện", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .padding()
                if filter == .playlists {
                    if model.playlists.isEmpty {
                        EmptyState(icon: "rectangle.stack.badge.plus", title: "Chưa có playlist", message: "Tạo playlist để lưu các bài hát yêu thích.")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetail(playlist: playlist, showPlayer: $showPlayer)
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(playlist.name).font(.headline)
                                        Text("\(playlist.tracks.count) bài hát").font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                } else if rows.isEmpty {
                    EmptyState(
                        icon: filter == .favorites ? "heart" : "clock",
                        title: filter == .favorites ? "Chưa có bài yêu thích" : "Chưa có lịch sử nghe",
                        message: "Các bài hát bạn phát sẽ được lưu cục bộ trên iPhone."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(rows) { track in
                        TrackRow(track: track, isResolving: model.isResolvingTrackID == track.id) {
                            model.playFromSearch(track)
                        }
                        .swipeActions {
                            if filter == .favorites {
                                Button(role: .destructive) { model.toggleFavorite(track) } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Thư viện")
            .toolbar {
                if filter == .playlists {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
                    }
                }
                if filter == .history && !model.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Xóa lịch sử", role: .destructive) { model.clearHistory() }
                    }
                }
            }
            .sheet(isPresented: $showNewPlaylist) {
                NewPlaylistSheet { name in
                    model.createPlaylist(named: name)
                    showNewPlaylist = false
                }
                .presentationDetents([.height(220)])
            }
        }
    }
}

private struct PlaylistDetail: View {
    @EnvironmentObject private var model: AppModel
    let playlist: LocalPlaylist
    @Binding var showPlayer: Bool

    var body: some View {
        Group {
            if playlist.tracks.isEmpty {
                EmptyState(icon: "music.note", title: "Playlist trống", message: "Thêm bài hát từ kết quả tìm kiếm bằng menu ngữ cảnh.")
            } else {
                List(playlist.tracks) { track in
                    TrackRow(track: track, isResolving: model.isResolvingTrackID == track.id) {
                        model.player.setQueue(playlist.tracks)
                        Task { @MainActor in await model.play(track) }
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.remove(track, from: playlist.id) } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
    }
}

private struct NewPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên playlist", text: $name)
            }
            .navigationTitle("Playlist mới")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") { onCreate(name); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện") {
                    Toggle("Chế độ tối", isOn: Binding(
                        get: { model.darkMode },
                        set: { model.setDarkMode($0) }
                    ))
                }
                Section("Phát nhạc") {
                    Label("YouTube Music", systemImage: "play.tv.fill")
                    Label("SoundCloud Web API", systemImage: "waveform")
                    Label("Phát nền và màn hình khóa", systemImage: "lock.display")
                }
                Section("Dữ liệu") {
                    Text("Không cần API key cho YouTube Music hoặc SoundCloud. SoundCloud client_id web được trích xuất và lưu tạm tự động.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Xóa lịch sử nghe", role: .destructive) { model.clearHistory() }
                }
                Section("Dự án") {
                    Link("Mã nguồn SimpMusic", destination: URL(string: "https://github.com/todo996/SimpMusic")!)
                    Text("iOS 16 trở lên · giao diện SwiftUI native · dữ liệu lấy trực tiếp từ nhà cung cấp")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}

private struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let track = model.player.currentTrack {
                        ArtworkView(url: track.artworkURL)
                            .frame(maxWidth: 340, maxHeight: 340)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .shadow(radius: 18)
                            .padding(.top, 12)
                        VStack(spacing: 5) {
                            Text(track.title).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(track.artist).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(formatTime(model.player.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { model.player.progress },
                                set: { model.player.seek(to: $0) }
                            ), in: 0...1)
                            Text(formatTime(model.player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 34) {
                            Button { model.player.previous() } label: { Image(systemName: "backward.fill").font(.title2) }
                            Button { model.player.togglePlayback() } label: {
                                Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 62))
                            }
                            Button { model.player.next() } label: { Image(systemName: "forward.fill").font(.title2) }
                        }
                        HStack {
                            Button { model.toggleFavorite(track) } label: {
                                Label(model.isFavorite(track) ? "Đã thích" : "Yêu thích", systemImage: model.isFavorite(track) ? "heart.fill" : "heart")
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Text(track.source.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        LyricsPanel()
                    } else {
                        EmptyState(icon: "music.note", title: "Chưa phát bài nào", message: "Chọn một bài hát từ Home hoặc Tìm kiếm.")
                    }
                }
                .padding()
            }
            .navigationTitle("Đang phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } }
            }
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct LyricsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lời bài hát").font(.title3.bold())
            if model.isLoadingLyrics {
                ProgressView("Đang tải lời từ LRCLIB…")
            } else if let lyrics = model.lyrics {
                ForEach(lyrics.lines) { line in
                    Text(line.text)
                        .font(line.time == nil ? .body : .body.weight(.medium))
                        .foregroundStyle(line.time == nil ? .secondary : .primary)
                }
            } else {
                Text("Chưa tìm thấy lời bài hát cho bản này.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showPlayer: Bool

    var body: some View {
        if let track = model.player.currentTrack {
            Button { showPlayer = true } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.player.previous() } label: { Image(systemName: "backward.fill") }
                        .buttonStyle(.plain)
                    Button { model.player.togglePlayback() } label: {
                        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var model: AppModel
    let track: MusicTrack
    let isResolving: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkURL)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(track.source.rawValue)
                    if !track.durationText.isEmpty { Text("·"); Text(track.durationText) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button(action: action) {
                if isResolving { ProgressView() }
                else { Image(systemName: "play.circle.fill").font(.title2) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button { model.toggleFavorite(track) } label: {
                Label(model.isFavorite(track) ? "Bỏ yêu thích" : "Thêm yêu thích", systemImage: "heart")
            }
            if !model.playlists.isEmpty {
                Menu("Thêm vào playlist", systemImage: "text.badge.plus") {
                    ForEach(model.playlists) { playlist in
                        Button(playlist.name) { model.add(track, to: playlist.id) }
                    }
                }
            }
            if let url = track.permalinkURL {
                ShareLink(item: url) { Label("Chia sẻ", systemImage: "square.and.arrow.up") }
            }
        }
        .onTapGesture(perform: action)
    }
}

private struct ArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image): image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.7), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.title).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }
}
