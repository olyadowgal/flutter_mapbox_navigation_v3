import Flutter
import MapboxDirections
import MapboxMaps
import MapboxNavigationCore  // Changed from MapboxCoreNavigation
import MapboxNavigationUIKit  // Changed from MapboxNavigation
import UIKit

public class NavigationFactory: NSObject, FlutterStreamHandler {
    var _navigationViewController: NavigationViewController? = nil
    var _eventSink: FlutterEventSink? = nil
    var navigationProvider: MapboxNavigationProvider!

    // Store Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    let ALLOW_ROUTE_SELECTION = false
    let IsMultipleUniqueRoutes = false
    var isEmbeddedNavigation = false

    var _distanceRemaining: Double?
    var _durationRemaining: Double?
    var _navigationMode: String?
    var _routes: [Route]?
    var _wayPointOrder = [Int: Waypoint]()
    var _wayPoints = [Waypoint]()
    var _lastKnownLocation: CLLocation?

    var _options: NavigationRouteOptions?
    var _simulateRoute = false
    var _allowsUTurnAtWayPoints: Bool?
    var _isOptimized = false
    var _language = "en"
    var _voiceUnits = "imperial"
    var _mapStyleUrlDay: String?
    var _mapStyleUrlNight: String?
    var _zoom: Double = 13.0
    var _tilt: Double = 0.0
    var _bearing: Double = 0.0
    var _animateBuildRoute = true
    var _longPressDestinationEnabled = true
    var _alternatives = true
    var _shouldReRoute = true
    var _showReportFeedbackButton = true
    var _showEndOfRouteFeedback = true
    var _enableOnMapTapCallback = false

    // Initialize the navigation provider
    func initializeNavigationProvider() {
        if navigationProvider == nil {
            var coreConfig = CoreConfig()
            if _simulateRoute {
                // Will be set properly when routes are available
                coreConfig.locationSource = .system
            }
            navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)
        }
    }

    func addWayPoints(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard var locations = getLocationsFromFlutterArgument(arguments: arguments) else { return }

        var nextIndex = 1
        for loc in locations {
            let wayPoint = Waypoint(
                coordinate: CLLocationCoordinate2D(
                    latitude: loc.latitude!, longitude: loc.longitude!), name: loc.name)
            wayPoint.separatesLegs = !loc.isSilent
            if _wayPoints.count >= nextIndex {
                _wayPoints.insert(wayPoint, at: nextIndex)
            } else {
                _wayPoints.append(wayPoint)
            }
            nextIndex += 1
        }

        startNavigationWithWayPoints(
            wayPoints: _wayPoints, flutterResult: result, isUpdatingWaypoints: true)
    }

    func startFreeDrive(arguments: NSDictionary?, result: @escaping FlutterResult) {
        initializeNavigationProvider()

        // Create a free drive view controller
        let freeDriveViewController = UIViewController()

        // Create navigation map view
        let navigationMapView = NavigationMapView(
            location: navigationProvider.navigation().locationMatching
                .map(\.mapMatchingResult.enhancedLocation)
                .eraseToAnyPublisher(),
            routeProgress: navigationProvider.navigation().routeProgress
                .map(\.?.routeProgress)
                .eraseToAnyPublisher(),
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )

        // Start free drive session
        navigationProvider.tripSession().startFreeDrive()

        // Configure the map view
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.puckType = .puck2D(.navigationDefault)

        // Add map view to the view controller
        freeDriveViewController.view = navigationMapView

        // Present the free drive view controller
        let flutterViewController = UIApplication.shared.delegate?.window??.rootViewController as! FlutterViewController
        flutterViewController.present(freeDriveViewController, animated: true, completion: nil)

        result(true)
    }

    func startNavigation(arguments: NSDictionary?, result: @escaping FlutterResult) {
        _wayPoints.removeAll()
        _wayPointOrder.removeAll()

        guard var locations = getLocationsFromFlutterArgument(arguments: arguments) else { return }

        for loc in locations {
            let location = Waypoint(
                coordinate: CLLocationCoordinate2D(
                    latitude: loc.latitude!, longitude: loc.longitude!), name: loc.name)

            location.separatesLegs = !loc.isSilent

            _wayPoints.append(location)
            _wayPointOrder[loc.order!] = location
        }

        parseFlutterArguments(arguments: arguments)

        _options?.includesAlternativeRoutes = _alternatives

        if _wayPoints.count > 3 && arguments?["mode"] == nil {
            _navigationMode = "driving"
        }

        if _wayPoints.count > 0 {
            if IsMultipleUniqueRoutes {
                startNavigationWithWayPoints(
                    wayPoints: [_wayPoints.remove(at: 0), _wayPoints.remove(at: 0)],
                    flutterResult: result, isUpdatingWaypoints: false)
            } else {
                startNavigationWithWayPoints(
                    wayPoints: _wayPoints, flutterResult: result, isUpdatingWaypoints: false)
            }
        }
    }

    func startNavigationWithWayPoints(
        wayPoints: [Waypoint], flutterResult: @escaping FlutterResult, isUpdatingWaypoints: Bool
    ) {
        initializeNavigationProvider()
        setNavigationOptions(wayPoints: wayPoints)

        // Use the routing provider to calculate routes
        Task {
            do {
                let routesResponse = try await navigationProvider.routingProvider().calculateRoutes(options: _options!).value

                guard let routes = routesResponse.routes else {
                    flutterResult("No routes found")
                    return
                }

                if routes.count > 1 && self.ALLOW_ROUTE_SELECTION {
                    // Show map to select a specific route
                    self._routes = routes
                    // Note: RouteOptionsViewController would need to be updated for v3
                    // This is a placeholder for that functionality
                    flutterResult("Route selection not implemented in v3 migration")
                } else {
                    if isUpdatingWaypoints {
                        // Update the current route with new waypoints
                        navigationProvider.tripSession().updateNavigationRoutes(routesResponse)
                        flutterResult("true")
                    } else {
                        // Start a new navigation session
                        var dayStyle = CustomDayStyle()
                        if self._mapStyleUrlDay != nil {
                            dayStyle = CustomDayStyle(url: self._mapStyleUrlDay)
                        }

                        var nightStyle = CustomNightStyle()
                        if self._mapStyleUrlNight != nil {
                            nightStyle = CustomNightStyle(url: self._mapStyleUrlNight)
                        }

                        // Configure simulation if needed
                        if self._simulateRoute, let firstRoute = routes.first {
                            var coreConfig = CoreConfig()
                            coreConfig.locationSource = .route(firstRoute)
                            self.navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)
                        }

                        // Create navigation options
                        let navigationOptions = NavigationOptions(
                            mapboxNavigation: self.navigationProvider.mapboxNavigation,
                            voiceController: self.navigationProvider.routeVoiceController,
                            eventsManager: self.navigationProvider.eventsManager(),
                            styles: [dayStyle, nightStyle],
                            predictiveCacheManager: self.navigationProvider.predictiveCacheManager
                        )

                        self.startNavigation(
                            routeResponse: routesResponse, options: self._options!,
                            navOptions: navigationOptions)
                    }
                }
            } catch {
                self.sendEvent(eventType: MapBoxEventType.route_build_failed)
                flutterResult("An error occurred while calculating the route: \(error.localizedDescription)")
            }
        }
    }

    func startNavigation(
        routeResponse: RouteResponse, options: NavigationRouteOptions, navOptions: NavigationOptions
    ) {
        isEmbeddedNavigation = false

        // Create NavigationRoutes from the route response
        let navigationRoutes = NavigationRoutes(routeResponse: routeResponse, routeIndex: 0)

        if self._navigationViewController == nil {
            self._navigationViewController = NavigationViewController(
                navigationRoutes: navigationRoutes,
                navigationOptions: navOptions
            )
            self._navigationViewController!.modalPresentationStyle = .fullScreen
            self._navigationViewController!.delegate = self
            self._navigationViewController!.showsReportFeedback = _showReportFeedbackButton
            self._navigationViewController!.showsEndOfRouteFeedback = _showEndOfRouteFeedback
        }

        let flutterViewController = UIApplication.shared.delegate?.window??.rootViewController as! FlutterViewController
        flutterViewController.present(
            self._navigationViewController!, animated: true, completion: nil)
    }

    func setNavigationOptions(wayPoints: [Waypoint]) {
        var mode: ProfileIdentifier = .automobileAvoidingTraffic

        if _navigationMode == "cycling" {
            mode = .cycling
        } else if _navigationMode == "driving" {
            mode = .automobile
        } else if _navigationMode == "walking" {
            mode = .walking
        }

        let options = NavigationRouteOptions(waypoints: wayPoints, profileIdentifier: mode)

        if _allowsUTurnAtWayPoints != nil {
            options.allowsUTurnAtWaypoint = _allowsUTurnAtWayPoints!
        }

        options.distanceMeasurementSystem = _voiceUnits == "imperial" ? .imperial : .metric
        options.locale = Locale(identifier: _language)
        options.includesAlternativeRoutes = _alternatives
        _options = options
    }

    func parseFlutterArguments(arguments: NSDictionary?) {
        _language = arguments?["language"] as? String ?? _language
        _voiceUnits = arguments?["units"] as? String ?? _voiceUnits
        _simulateRoute = arguments?["simulateRoute"] as? Bool ?? _simulateRoute
        _isOptimized = arguments?["isOptimized"] as? Bool ?? _isOptimized
        _allowsUTurnAtWayPoints = arguments?["allowsUTurnAtWayPoints"] as? Bool
        _navigationMode = arguments?["mode"] as? String ?? "drivingWithTraffic"
        _showReportFeedbackButton =
            arguments?["showReportFeedbackButton"] as? Bool ?? _showReportFeedbackButton
        _showEndOfRouteFeedback =
            arguments?["showEndOfRouteFeedback"] as? Bool ?? _showEndOfRouteFeedback
        _enableOnMapTapCallback =
            arguments?["enableOnMapTapCallback"] as? Bool ?? _enableOnMapTapCallback
        _mapStyleUrlDay = arguments?["mapStyleUrlDay"] as? String
        _mapStyleUrlNight = arguments?["mapStyleUrlNight"] as? String
        _zoom = arguments?["zoom"] as? Double ?? _zoom
        _bearing = arguments?["bearing"] as? Double ?? _bearing
        _tilt = arguments?["tilt"] as? Double ?? _tilt
        _animateBuildRoute = arguments?["animateBuildRoute"] as? Bool ?? _animateBuildRoute
        _longPressDestinationEnabled =
            arguments?["longPressDestinationEnabled"] as? Bool ?? _longPressDestinationEnabled
        _alternatives = arguments?["alternatives"] as? Bool ?? _alternatives
    }

    func continueNavigationWithWayPoints(wayPoints: [Waypoint]) {
        _options?.waypoints = wayPoints

        // Initialize navigation provider if needed
        if navigationProvider == nil {
            initializeNavigationProvider()
        }

        // Use the routing provider to calculate routes with async/await
        Task {
            do {
                let routesResponse = try await navigationProvider.routingProvider().calculateRoutes(options: _options!).value

                self.sendEvent(
                    eventType: MapBoxEventType.route_built,
                    data: self.encodeRouteResponse(response: routesResponse))

                guard let routes = routesResponse.routes else { return }

                if routes.count > 1 && self.ALLOW_ROUTE_SELECTION {
                    // TODO: show map to select a specific route
                } else {
                    // Update the navigation routes
                    self.navigationProvider.tripSession().updateNavigationRoutes(routesResponse)

                    // Start navigation if not already started
                    if !self.navigationProvider.tripSession().isActiveGuidanceActive {
                        self.navigationProvider.tripSession().startActiveGuidance(routesResponse)
                    }
                }
            } catch {
                self.sendEvent(
                    eventType: MapBoxEventType.route_build_failed,
                    data: error.localizedDescription)
            }
        }
    }

    func endNavigation(result: FlutterResult?) {
        sendEvent(eventType: MapBoxEventType.navigation_finished)

        if self._navigationViewController != nil {
            // Stop the navigation session
            if let navProvider = self.navigationProvider {
                navProvider.tripSession().stop()
            }

            if isEmbeddedNavigation {
                self._navigationViewController!.view.removeFromSuperview()
                self._navigationViewController?.removeFromParent()
                self._navigationViewController = nil
            } else {
                self._navigationViewController?.dismiss(
                    animated: true,
                    completion: {
                        self._navigationViewController = nil
                        if result != nil {
                            result!(true)
                        }
                    })
            }
        }
    }

    func getLocationsFromFlutterArgument(arguments: NSDictionary?) -> [Location]? {
        var locations = [Location]()
        guard let oWayPoints = arguments?["wayPoints"] as? NSDictionary else { return nil }
        for item in oWayPoints as NSDictionary {
            let point = item.value as! NSDictionary
            guard let oName = point["Name"] as? String else { return nil }
            guard let oLatitude = point["Latitude"] as? Double else { return nil }
            guard let oLongitude = point["Longitude"] as? Double else { return nil }
            let oIsSilent = point["IsSilent"] as? Bool ?? false
            let order = point["Order"] as? Int
            let location = Location(
                name: oName, latitude: oLatitude, longitude: oLongitude, order: order,
                isSilent: oIsSilent)
            locations.append(location)
        }
        if !_isOptimized {
            //waypoints must be in the right order
            locations.sort(by: { $0.order ?? 0 < $1.order ?? 0 })
        }
        return locations
    }

    func getLastKnownLocation() -> Waypoint {
        return Waypoint(
            coordinate: CLLocationCoordinate2D(
                latitude: _lastKnownLocation!.coordinate.latitude,
                longitude: _lastKnownLocation!.coordinate.longitude))
    }

    func sendEvent(eventType: MapBoxEventType, data: String = "") {
        let routeEvent = MapBoxRouteEvent(eventType: eventType, data: data)

        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(routeEvent)
        let eventJson = String(data: jsonData, encoding: String.Encoding.utf8)
        if _eventSink != nil {
            _eventSink!(eventJson)
        }
    }

    func downloadOfflineRoute(arguments: NSDictionary?, flutterResult: @escaping FlutterResult) {
        // Implementation remains empty as in original code
    }

    func encodeRouteResponse(response: RouteResponse) -> String {
        let routes = response.routes

        if routes != nil && !routes!.isEmpty {
            let jsonEncoder = JSONEncoder()
            let jsonData = try! jsonEncoder.encode(response.routes!)
            return String(data: jsonData, encoding: String.Encoding.utf8) ?? "{}"
        }

        return "{}"
    }

    //MARK: EventListener Delegates
    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        _eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        _eventSink = nil
        return nil
    }
}


extension NavigationFactory: NavigationViewControllerDelegate {
    //MARK: NavigationViewController Delegates

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didUpdate progress: RouteProgress,
        with location: CLLocation,
        rawLocation: CLLocation
    ) {
        _lastKnownLocation = location
        _distanceRemaining = progress.distanceRemaining
        _durationRemaining = progress.durationRemaining
        sendEvent(eventType: MapBoxEventType.navigation_running)

        if _eventSink != nil {
            let jsonEncoder = JSONEncoder()

            let progressEvent = MapBoxRouteProgressEvent(progress: progress)
            let progressEventJsonData = try! jsonEncoder.encode(progressEvent)
            let progressEventJson = String(
                data: progressEventJsonData, encoding: String.Encoding.ascii)

            _eventSink!(progressEventJson)

            if progress.isFinalLeg && progress.currentLegProgress.userHasArrivedAtWaypoint
                && !_showEndOfRouteFeedback
            {
                _eventSink = nil
            }
        }
    }

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didArriveAt waypoint: Waypoint
    ) {
        sendEvent(eventType: MapBoxEventType.on_arrival, data: "true")
        if !_wayPoints.isEmpty && IsMultipleUniqueRoutes {
            continueNavigationWithWayPoints(wayPoints: [
                getLastKnownLocation(), _wayPoints.remove(at: 0),
            ])
            return
        }
    }

    public func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) {
        if canceled {
            sendEvent(eventType: MapBoxEventType.navigation_cancelled)
        }
        endNavigation(result: nil)
    }

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        shouldRerouteFrom location: CLLocation
    ) -> Bool {
        return _shouldReRoute
    }

    public func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didSubmitArrivalFeedback feedback: Bool
    ) {
        if _eventSink != nil {
            let jsonEncoder = JSONEncoder()

            // Create a feedback object with default values since the feedback structure has changed
            let localFeedback = Feedback(rating: 5, comment: "")
            let feedbackJsonData = try! jsonEncoder.encode(localFeedback)
            let feedbackJson = String(data: feedbackJsonData, encoding: String.Encoding.ascii)

            sendEvent(eventType: MapBoxEventType.navigation_finished, data: feedbackJson ?? "")

            _eventSink = nil
        }
    }
}