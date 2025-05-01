import Flutter
import MapboxDirections
import MapboxMaps
import MapboxNavigationCore  // Changed from MapboxCoreNavigation
import MapboxNavigationUIKit  // Changed from MapboxNavigation
import UIKit

public class RouteOptionsViewController: UIViewController, NavigationMapViewDelegate {
    var mapView: NavigationMapView!
    var routeOptions: NavigationRouteOptions?
    var navigationRoutes: NavigationRoutes?
    var routes: [NavigationRoute]!
    var navigationProvider: MapboxNavigationProvider!

    init(navigationRoutes: NavigationRoutes, options: NavigationRouteOptions) {
        self.navigationRoutes = navigationRoutes
        self.routes = navigationRoutes.routes
        self.routeOptions = options
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.routes = nil
        self.routeOptions = nil
        self.navigationRoutes = nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize the navigation provider with core config
        navigationProvider = MapboxNavigationProvider(coreConfig: CoreConfig())

        // Create a new NavigationMapView with the required configuration
        let mapViewConfiguration = MapViewConfiguration.createNew(
            location: navigationProvider.navigation().locationMatching
                .map(\.mapMatchingResult.enhancedLocation)
                .eraseToAnyPublisher(),
            routeProgress: navigationProvider.navigation().routeProgress
                .map(\.?.routeProgress)
                .eraseToAnyPublisher(),
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )

        mapView = NavigationMapView(frame: view.bounds, mapViewConfiguration: mapViewConfiguration)
        view.addSubview(mapView)
        mapView.delegate = self

        // Add a gesture recognizer to the map view
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(didLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
    }

    // long press to select a destination
    @objc func didLongPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
    }

    // Calculate route to be used for navigation
    func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        completion: @escaping (NavigationRoute?, Error?) -> Void
    ) {

        // Coordinate accuracy is how close the route must come to the waypoint in order to be considered viable. It is measured in meters. A negative value indicates that the route is viable regardless of how far the route is from the waypoint.
        let origin = Waypoint(coordinate: origin, coordinateAccuracy: -1, name: "Start")
        let destination = Waypoint(coordinate: destination, coordinateAccuracy: -1, name: "Finish")

        // Specify that the route is intended for automobiles avoiding traffic
        let routeOptions = NavigationRouteOptions(
            waypoints: [origin, destination], profileIdentifier: .automobileAvoidingTraffic)

        // Generate the route object and draw it on the map
        Task {
            do {
                let routingProvider = navigationProvider.mapboxNavigation.routingProvider()
                let routesResponse = try await routingProvider.calculateRoutes(
                    options: routeOptions
                ).value
                self.navigationRoutes = routesResponse
                self.routes = routesResponse.routes
                self.routeOptions = routeOptions

                if let firstRoute = routesResponse.routes.first {
                    // Draw the route on the map after creating it
                    self.drawRoute(route: firstRoute)
                    completion(firstRoute, nil)
                }
            } catch {
                completion(nil, error)
            }
        }
    }

    func drawRoute(route: NavigationRoute) {
        // Implement your route drawing logic here
    }
}
