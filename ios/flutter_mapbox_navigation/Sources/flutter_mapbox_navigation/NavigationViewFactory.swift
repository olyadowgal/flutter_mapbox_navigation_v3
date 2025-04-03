import Flutter
import MapboxDirections
import MapboxMaps
import MapboxNavigationCore  // Changed from MapboxCoreNavigation
import MapboxNavigationUIKit  // Changed from MapboxNavigation
import UIKit

public class FlutterMapboxNavigationViewFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    public func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
        -> FlutterPlatformView
    {
        return FlutterMapboxNavigationView(
            messenger: self.messenger, frame: frame, viewId: viewId, args: args)
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
