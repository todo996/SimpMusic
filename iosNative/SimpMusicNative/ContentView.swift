import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                sourcePicker
                results
                nowPlaying
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("SimpMusic")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Không thể thực hiện", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm bài hát, nghệ sĩ…", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { model.search() }
            Button {
                model.search()
            } label: {
                if model.isSearching {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSearching)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var sourcePicker: some View {
        Picker("Nguồn", selection: $model.source) {
            ForEach(MusicSource.allCases) { source in
                Text(source == .all ? "Tất cả" : source.rawValue).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var results: some View {
        Group {
            if model.tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)
                    Text("Tìm nhạc để bắt đầu")
                        .font(.headline)
                    Text("Dữ liệu được lấy trực tiếp từ YouTube Music và SoundCloud.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            } else {
                List(model.tracks) { track in
                    TrackRow(track: track, isResolving: model.resolvingTrackID == track.id) {
                        model.play(track)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let track = model.player.currentTrack {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    AsyncImage(url: track.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).lineLimit(1).font(.subheadline.weight(.semibold))
                        Text(track.artist).lineLimit(1).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        model.player.togglePlayback()
                    } label: {
                        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                }
                Slider(value: Binding(
                    get: { model.player.progress },
                    set: { model.player.seek(to: $0) }
                ), in: 0...1)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
    }
}

private struct TrackRow: View {
    let track: MusicTrack
    let isResolving: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.16)
                    Image(systemName: track.source == .soundCloud ? "waveform" : "play.tv")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(track.artist) · \(track.source.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: action) {
                if isResolving {
                    ProgressView()
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
