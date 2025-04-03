import Flutter
import MapboxDirections
import MapboxMaps
import MapboxNavigationCore  // Changed from MapboxCoreNavigation
import MapboxNavigationUIKit  // Changed from MapboxNavigation
import UIKit

public class FlutterMapboxNavigationPlugin: NavigationFactory, FlutterPlugin {
    // Navigation provider instance to maintain throughout the app lifecycle
    private var navigationProvider: MapboxNavigationProvider?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_mapbox_navigation", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: "flutter_mapbox_navigation/events", binaryMessenger: registrar.messenger())
        let instance = FlutterMapboxNavigationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        eventChannel.setStreamHandler(instance)

        let viewFactory = FlutterMapboxNavigationViewFactory(messenger: registrar.messenger())
        registrar.register(viewFactory, withId: "FlutterMapboxNavigationView")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? NSDictionary

        if call.method == "getPlatformVersion" {
            result("iOS " + UIDevice.current.systemVersion)
        } else if call.method == "getDistanceRemaining" {
            result(_distanceRemaining)
        } else if call.method == "getDurationRemaining" {
            result(_durationRemaining)
        } else if call.method == "startFreeDrive" {
            startFreeDrive(arguments: arguments, result: result)
        } else if call.method == "startNavigation" {
            startNavigation(arguments: arguments, result: result)
        } else if call.method == "addWayPoints" {
            addWayPoints(arguments: arguments, result: result)
        } else if call.method == "finishNavigation" {
            endNavigation(result: result)
        } else if call.method == "enableOfflineRouting" {
            downloadOfflineRoute(arguments: arguments, flutterResult: result)
        } else {
            result("Method is Not Implemented")
        }
    }

    // Initialize the navigation provider if not already done
    private func initializeNavigationProviderIfNeeded() {
        if navigationProvider == nil {
            let coreConfig = CoreConfig()  // Configure as needed
            navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)
        }
    }

    // You'll need to implement these methods according to v3 API
    private func startFreeDrive(arguments: NSDictionary?, result: @escaping FlutterResult) {
        initializeNavigationProviderIfNeeded()

        // In v3, you use tripSession to start free drive
        Task {
            do {
                try await navigationProvider?.mapboxNavigation.tripSession().startFreeDrive()
                result(true)
            } catch {
                result(
                    FlutterError(
                        code: "FREE_DRIVE_ERROR", message: error.localizedDescription, details: nil)
                )
            }
        }
    }

    private func startNavigation(arguments: NSDictionary?, result: @escaping FlutterResult) {
        initializeNavigationProviderIfNeeded()

        // Implementation will depend on how you're handling routes
        // You'll need to get NavigationRoutes and use tripSession().startActiveGuidance()
        // This is a simplified example
        Task {
            do {
                // Get routes using routingProvider
                // let navigationRoutes = ...

                // Start active guidance
                // try await navigationProvider?.mapboxNavigation.tripSession().startActiveGuidance(navigationRoutes: navigationRoutes)

                result(true)
            } catch {
                result(
                    FlutterError(
                        code: "NAVIGATION_ERROR", message: error.localizedDescription, details: nil)
                )
            }
        }
    }

    private func endNavigation(result: @escaping FlutterResult) {
        Task {
            do {
                try await navigationProvider?.mapboxNavigation.tripSession().end()
                result(true)
            } catch {
                result(
                    FlutterError(
                        code: "END_NAVIGATION_ERROR", message: error.localizedDescription,
                        details: nil))
            }
        }
    }

    // Other methods would need similar updates
}
