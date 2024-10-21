import SwiftUI
import AVKit

struct VideoView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: CMTime = .zero
    @State private var duration: CMTime = .zero

    var videoURL: URL

    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        player.pause()
                        isPlaying = false
                    }
                    .onChange(of: currentTime) { newTime in
                        player.seek(to: newTime)
                    }
                    .onChange(of: isPlaying) { playing in
                        if playing {
                            player.play()
                        } else {
                            player.pause()
                        }
                    }
            } else {
                Text("Loading video...")
                    .onAppear {
                        loadVideo()
                    }
            }

            HStack {
                Button(action: {
                    isPlaying.toggle()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }

                Slider(value: Binding(
                    get: {
                        currentTime.seconds / duration.seconds
                    },
                    set: { newValue in
                        currentTime = CMTime(seconds: newValue * duration.seconds, preferredTimescale: 600)
                    }
                ))

                Text(formatTime(currentTime))
                Text("/")
                Text(formatTime(duration))
            }
            .padding()
        }
    }

    private func loadVideo() {
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        duration = playerItem.asset.duration
    }

    private func formatTime(_ time: CMTime) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
