import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
