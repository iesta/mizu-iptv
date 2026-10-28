import Cocoa
import FlutterMacOS
import MediaPlayer

class MainFlutterWindow: NSWindow {
  private var mediaChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Mémorise taille/position entre deux lancements (crash compris) : AppKit
    // écrit le cadre dans les préférences à chaque redimensionnement et le
    // restaure ici.
    self.setFrameAutosaveName("MizuMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupMediaSession(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Touche play/pause du clavier Mac et centre de contrôle (MPNowPlayingInfo).
  /// Le canal est piloté depuis Dart (`lib/platform/mac_media_session.dart`).
  private func setupMediaSession(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.mizu.iptv/media", binaryMessenger: binaryMessenger)
    mediaChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        self.updateNowPlaying(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "clear":
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.addTarget { [weak self] _ in
      self?.send("play")
      return .success
    }
    commands.pauseCommand.addTarget { [weak self] _ in
      self?.send("pause")
      return .success
    }
    commands.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.send("toggle")
      return .success
    }
    commands.stopCommand.addTarget { [weak self] _ in
      self?.send("stop")
      return .success
    }
  }

  private func send(_ method: String) {
    mediaChannel?.invokeMethod(method, arguments: nil)
  }

  private func updateNowPlaying(_ args: [String: Any]) {
    let playing = args["playing"] as? Bool ?? false
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: args["title"] as? String ?? "Mizu IPTV",
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime:
        args["position"] as? Double ?? 0.0,
    ]
    if let subtitle = args["subtitle"] as? String, !subtitle.isEmpty {
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if let duration = args["duration"] as? Double, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
  }
}
