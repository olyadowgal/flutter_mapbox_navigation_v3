import Flutter
import MapboxDirections
import MapboxMaps
import MapboxNavigationCore  // Changed from MapboxCoreNavigation
import MapboxNavigationUIKit  // Changed from MapboxNavigation
import UIKit

public class FlutterMapboxNavigationView: NavigationFactory, FlutterPlatformView {
    // Flutter-related properties (unchanged)
    let frame: CGRect
    let viewId: Int64
    let messenger: FlutterBinaryMessenger
    let channel: FlutterMethodChannel
    let eventChannel: FlutterEventChannel
    var arguments: NSDictionary?

    // Mapbox Navigation v3 properties
    var navigationMapView: NavigationMapView!
    var navigationProvider: MapboxNavigationProvider!

    // Route-related properties
    var routeResponse: RouteResponse?
    var selectedRouteIndex = 0
    var routeOptions: NavigationRouteOptions?

    // State tracking
    var _mapInitialized = false
    var locationManager = CLLocationManager()

    // Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    init(messenger: FlutterBinaryMessenger, frame: CGRect, viewId: Int64, args: Any?) {
        self.frame = frame
        self.viewId = viewId
        self.arguments = args as! NSDictionary?

        self.messenger = messenger
        self.channel = FlutterMethodChannel(
            name: "flutter_mapbox_navigation/\(viewId)", binaryMessenger: messenger)
        self.eventChannel = FlutterEventChannel(
            name: "flutter_mapbox_navigation/\(viewId)/events", binaryMessenger: messenger)

        super.init()

        self.eventChannel.setStreamHandler(self)

        self.channel.setMethodCallHandler { [weak self] (call, result) in

            guard let strongSelf = self else { return }

            let arguments = call.arguments as? NSDictionary

            if call.method == "getPlatformVersion" {
                result("iOS " + UIDevice.current.systemVersion)
            } else if call.method == "buildRoute" {
                strongSelf.buildRoute(arguments: arguments, flutterResult: result)
            } else if call.method == "clearRoute" {
                strongSelf.clearRoute(arguments: arguments, result: result)
            } else if call.method == "getDistanceRemaining" {
                result(strongSelf._distanceRemaining)
            } else if call.method == "getDurationRemaining" {
                result(strongSelf._durationRemaining)
            } else if call.method == "finishNavigation" {
                strongSelf.endNavigation(result: result)
            } else if call.method == "startFreeDrive" {
                strongSelf.startEmbeddedFreeDrive(arguments: arguments, result: result)
            } else if call.method == "startNavigation" {
                strongSelf.startEmbeddedNavigation(arguments: arguments, result: result)
            } else if call.method == "reCenter" {
                //used to recenter map from user action during navigation
                strongSelf.navigationMapView.navigationCamera.follow()
            }
            //This is custom code for StreetIQ
            else if call.method == "addCustomMarkers" {
                print("Received arguments: \(String(describing: arguments))")
                strongSelf.addCustomMarker(arguments: arguments, result: result)
            } else {
                result("method is not implemented")
            }

        }
    }

    public func view() -> UIView {
        if _mapInitialized {
            return navigationMapView
        }

        setupMapView()

        return navigationMapView
    }

    private func setupMapView() {
        // Create CoreConfig
        let coreConfig = CoreConfig()

        // Create navigation provider
        let navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)

        // Initialize NavigationMapView with required publishers
        navigationMapView = NavigationMapView(
            location: navigationProvider.navigation().locationMatching
                .map(\.mapMatchingResult.enhancedLocation)
                .eraseToAnyPublisher(),
            routeProgress: navigationProvider.navigation().routeProgress
                .map(\.?.routeProgress)
                .eraseToAnyPublisher(),
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )

        navigationMapView.delegate = self

        if self.arguments != nil {
            parseFlutterArguments(arguments: arguments)

            if _mapStyleUrlDay != nil {
                navigationMapView.mapView.mapboxMap.style.uri = StyleURI.init(
                    url: URL(string: _mapStyleUrlDay!)!)
            }

            var currentLocation: CLLocation!

            locationManager.requestWhenInUseAuthorization()

            if CLLocationManager.authorizationStatus() == .authorizedWhenInUse
                || CLLocationManager.authorizationStatus() == .authorizedAlways
            {
                currentLocation = locationManager.location
            }

            let initialLatitude =
                arguments?["initialLatitude"] as? Double ?? currentLocation?.coordinate.latitude
            let initialLongitude =
                arguments?["initialLongitude"] as? Double ?? currentLocation?.coordinate.longitude
            if initialLatitude != nil && initialLongitude != nil {
                moveCameraToCoordinates(latitude: initialLatitude!, longitude: initialLongitude!)
            }
        }

        if _longPressDestinationEnabled {
            let gesture = UILongPressGestureRecognizer(
                target: self, action: #selector(handleLongPress(_:)))
            gesture.delegate = self
            navigationMapView?.addGestureRecognizer(gesture)
        }

        if _enableOnMapTapCallback {
            let onTapGesture = UITapGestureRecognizer(
                target: self, action: #selector(handleTap(_:)))
            onTapGesture.numberOfTapsRequired = 1
            onTapGesture.delegate = self
            navigationMapView?.addGestureRecognizer(onTapGesture)
        }
    }

    func clearRoute(arguments: NSDictionary?, result: @escaping FlutterResult) {
        if routeResponse == nil {
            return
        }

        // Stop the navigation session if active
        if let navigationProvider = navigationMapView.navigationProvider {
            navigationProvider.tripSession().stop()
        }

        // Clear routes from the map
        navigationMapView.removeRoutes()

        // Reset route response
        routeResponse = nil

        // Send cancellation event
        sendEvent(eventType: MapBoxEventType.navigation_cancelled)
    }

    func buildRoute(arguments: NSDictionary?, flutterResult: @escaping FlutterResult) {
        _wayPoints.removeAll()
        isEmbeddedNavigation = true
        sendEvent(eventType: MapBoxEventType.route_building)

        guard let oWayPoints = arguments?["wayPoints"] as? NSDictionary else { return }

        var locations = [Location]()

        for item in oWayPoints as NSDictionary {
            let point = item.value as! NSDictionary
            guard let oName = point["Name"] as? String else { return }
            guard let oLatitude = point["Latitude"] as? Double else { return }
            guard let oLongitude = point["Longitude"] as? Double else { return }
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

        for loc in locations {
            let waypoint = Waypoint(
                coordinate: CLLocationCoordinate2D(
                    latitude: loc.latitude!, longitude: loc.longitude!),
                name: loc.name)
            waypoint.separatesLegs = !loc.isSilent
            _wayPoints.append(waypoint)
        }

        parseFlutterArguments(arguments: arguments)

        if _wayPoints.count > 3 && arguments?["mode"] == nil {
            _navigationMode = "driving"
        }

        var mode: ProfileIdentifier = .automobileAvoidingTraffic

        if _navigationMode == "cycling" {
            mode = .cycling
        } else if _navigationMode == "driving" {
            mode = .automobile
        } else if _navigationMode == "walking" {
            mode = .walking
        }

        let navigationRouteOptions = NavigationRouteOptions(
            waypoints: _wayPoints,
            profileIdentifier: mode
        )

        if _allowsUTurnAtWayPoints != nil {
            navigationRouteOptions.allowsUTurnAtWaypoint = _allowsUTurnAtWayPoints!
        }

        navigationRouteOptions.distanceMeasurementSystem =
            _voiceUnits == "imperial" ? .imperial : .metric
        navigationRouteOptions.locale = Locale(identifier: _language)
        navigationRouteOptions.includesAlternativeRoutes = _alternatives
        self.routeOptions = navigationRouteOptions

        // Create navigation provider and get routing provider
        let navigationProvider = MapboxNavigationProvider(coreConfig: .init())
        let routingProvider = navigationProvider.mapboxNavigation.routingProvider()

        // Use Task for async/await pattern
        Task {
            do {
                // Calculate routes using the routing provider
                let routesResponse = try await routingProvider.calculateRoutes(
                    options: navigationRouteOptions
                ).value

                // Handle successful route calculation
                self.routeResponse = routesResponse
                self.sendEvent(
                    eventType: MapBoxEventType.route_built,
                    data: self.encodeRouteResponse(response: routesResponse))

                // Show routes on the map
                if let routes = routesResponse.routes {
                    DispatchQueue.main.async {
                        self.navigationMapView?.show(
                            routes: routes, shouldFit: true, animated: true)
                        flutterResult(true)
                    }
                } else {
                    flutterResult(false)
                }
            } catch {
                print("Route calculation failed: \(error.localizedDescription)")
                self.sendEvent(eventType: MapBoxEventType.route_build_failed)
                flutterResult(false)
            }
        }
    }

    func startEmbeddedFreeDrive(arguments: NSDictionary?, result: @escaping FlutterResult) {
        // Create CoreConfig
        let coreConfig = CoreConfig()

        // Create navigation provider
        let navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)

        // Start free drive session
        navigationProvider.tripSession().startFreeDrive()

        // Configure the navigation map view
        navigationMapView = NavigationMapView(
            location: navigationProvider.navigation().locationMatching.map(\.location)
                .eraseToAnyPublisher(),
            routeProgress: navigationProvider.navigation().routeProgress.map(\.?.routeProgress)
                .eraseToAnyPublisher(),
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )

        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.puckType = .puck2D(.navigationDefault)

        // Configure the viewport data source
        let viewportDataSource = MapboxNavigationViewportDataSource(
            navigationMapView.mapView.mapboxMap)
        viewportDataSource.options.followingFrameOptions.zoomUpdatesAllowed = false
        viewportDataSource.followingMobileCamera = CameraOptions(zoom: _zoom)
        navigationMapView.navigationCamera.viewportDataSource = viewportDataSource

        // Evaluate the viewport to apply changes
        viewportDataSource.evaluate()

        result(true)
    }

    ///This is custom code for StreetIQ
    func addCustomMarker(arguments: NSDictionary?, result: @escaping FlutterResult) {
        // Extract 'markers' from the arguments
        guard let markersArray = arguments?["markers"] as? [[String: Any]] else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENTS", message: "Invalid markers data", details: nil))
            return
        }

        guard let mapView = navigationMapView?.mapView else {
            result(
                FlutterError(
                    code: "MAP_VIEW_NULL", message: "MapView is not initialized", details: nil))
            return
        }

        // In v3, we use the annotations plugin to create a circle annotation manager
        let annotationPlugin = mapView.annotations
        let circleAnnotationManager = annotationPlugin.createCircleAnnotationManager()

        // Create circle annotation options for each marker
        var circleAnnotationOptions: [CircleAnnotationOptions] = []

        for marker in markersArray {
            guard let latitude = marker["latitude"] as? Double,
                let longitude = marker["longitude"] as? Double
            else { continue }

            // Create a point from the coordinates
            let point = Point(coordinates: Position(longitude, latitude))

            // Create circle annotation options
            let options = CircleAnnotationOptions()
                .withPoint(point)
                .withCircleRadius(4.0)
                .withCircleColor(
                    UIColor(
                        red: 144.0 / 255.0, green: 197.0 / 255.0, blue: 252.0 / 255.0, alpha: 1.0
                    ).cgColor
                )
                .withCircleStrokeWidth(2.0)
                .withCircleStrokeColor(
                    UIColor(
                        red: 198.0 / 255.0, green: 221.0 / 255.0, blue: 245.0 / 255.0, alpha: 1.0
                    ).cgColor)

            circleAnnotationOptions.append(options)
        }

        // Create all circle annotations at once
        circleAnnotationManager.create(circleAnnotationOptions)
        result(nil)  // Indicate success
    }

    func startEmbeddedNavigation(arguments: NSDictionary?, result: @escaping FlutterResult) {
        guard let response = self.routeResponse else { return }

        // Create CoreConfig with appropriate location source
        var coreConfig = CoreConfig()
        if self._simulateRoute {
            if let firstRoute = response.routes?.first {
                coreConfig.locationSource = .route(firstRoute)
            }
        } else {
            coreConfig.locationSource = .system
        }

        // Create the navigation provider
        let navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)

        // Create navigation routes from the route response
        let navigationRoutes = NavigationRoutes(
            routeResponse: response, routeIndex: selectedRouteIndex)

        // Create styles
        var dayStyle = CustomDayStyle()
        if _mapStyleUrlDay != nil {
            dayStyle = CustomDayStyle(url: _mapStyleUrlDay)
        }

        var nightStyle = CustomNightStyle()
        if _mapStyleUrlNight != nil {
            nightStyle = CustomNightStyle(url: _mapStyleUrlNight)
        }

        // Create navigation options
        let navigationOptions = NavigationOptions(
            mapboxNavigation: navigationProvider.mapboxNavigation,
            voiceController: navigationProvider.routeVoiceController,
            eventsManager: navigationProvider.eventsManager(),
            styles: [dayStyle, nightStyle],
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )

        // Remove previous navigation view and controller if any
        if _navigationViewController?.view != nil {
            _navigationViewController!.view.removeFromSuperview()
            _navigationViewController?.removeFromParent()
        }

        // Create navigation view controller
        _navigationViewController = NavigationViewController(
            navigationRoutes: navigationRoutes,
            navigationOptions: navigationOptions
        )
        _navigationViewController!.delegate = self

        // Configure UI options
        _navigationViewController!.showsReportFeedback = _showReportFeedbackButton
        _navigationViewController!.showsEndOfRouteFeedback = _showEndOfRouteFeedback

        // Add to view hierarchy
        let flutterViewController =
            UIApplication.shared.delegate?.window?!.rootViewController as! FlutterViewController
        flutterViewController.addChild(_navigationViewController!)

        self.navigationMapView.addSubview(_navigationViewController!.view)
        _navigationViewController!.view.translatesAutoresizingMaskIntoConstraints = false
        constraintsWithPaddingBetween(
            holderView: self.navigationMapView, topView: _navigationViewController!.view,
            padding: 0.0)
        flutterViewController.didMove(toParent: flutterViewController)

        result(true)
    }

    func constraintsWithPaddingBetween(holderView: UIView, topView: UIView, padding: CGFloat) {
        guard holderView.subviews.contains(topView) else {
            return
        }
        topView.translatesAutoresizingMaskIntoConstraints = false
        let pinTop = NSLayoutConstraint(
            item: topView, attribute: .top, relatedBy: .equal,
            toItem: holderView, attribute: .top, multiplier: 1.0, constant: padding)
        let pinBottom = NSLayoutConstraint(
            item: topView, attribute: .bottom, relatedBy: .equal,
            toItem: holderView, attribute: .bottom, multiplier: 1.0, constant: padding)
        let pinLeft = NSLayoutConstraint(
            item: topView, attribute: .left, relatedBy: .equal,
            toItem: holderView, attribute: .left, multiplier: 1.0, constant: padding)
        let pinRight = NSLayoutConstraint(
            item: topView, attribute: .right, relatedBy: .equal,
            toItem: holderView, attribute: .right, multiplier: 1.0, constant: padding)
        holderView.addConstraints([pinTop, pinBottom, pinLeft, pinRight])
    }

    func moveCameraToCoordinates(latitude: Double, longitude: Double) {
        // Create a custom viewport data source
        let viewportDataSource = MapboxNavigationViewportDataSource(
            navigationMapView.mapView.mapboxMap)

        // Configure following camera options
        viewportDataSource.options.followingFrameOptions.zoomUpdatesAllowed = false

        // Set camera properties using CameraOptions
        viewportDataSource.followingMobileCamera = CameraOptions(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            zoom: _zoom,
            bearing: _bearing,
            pitch: 15.0,
            padding: .zero
        )

        // Assign the viewport data source to the navigation camera
        navigationMapView.navigationCamera.viewportDataSource = viewportDataSource

        // Evaluate the viewport to apply changes
        viewportDataSource.evaluate()
    }

    func moveCameraToCenter() {
        var duration = 5.0
        if !_animateBuildRoute {
            duration = 0.0
        }

        // Create a custom viewport data source
        let viewportDataSource = MapboxNavigationViewportDataSource(
            navigationMapView.mapView.mapboxMap)

        // Configure following camera options
        viewportDataSource.options.followingFrameOptions.zoomUpdatesAllowed = false

        // Set camera properties
        viewportDataSource.followingMobileCamera = CameraOptions(
            zoom: 13.0,
            pitch: 15.0,
            padding: .zero
        )

        // Assign the viewport data source to the navigation camera
        navigationMapView.navigationCamera.viewportDataSource = viewportDataSource

        // Evaluate the viewport to apply changes
        viewportDataSource.evaluate()
    }

}

extension FlutterMapboxNavigationView {

    // Setup function to call when initializing your navigation
    func setupNavigationPublishers() {
        // Subscribe to route progress updates
        navigationMapView.navigationProvider.navigation().routeProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                guard let self = self else { return }

                if let location = self.navigationMapView.mapView.location.latestLocation {
                    self._lastKnownLocation = location
                }

                self._distanceRemaining = progress.distanceRemaining
                self._durationRemaining = progress.durationRemaining
                self.sendEvent(eventType: MapBoxEventType.navigation_running)

                if self._eventSink != nil {
                    let jsonEncoder = JSONEncoder()

                    let progressEvent = MapBoxRouteProgressEvent(progress: progress)
                    let progressEventJsonData = try! jsonEncoder.encode(progressEvent)
                    let progressEventJson = String(
                        data: progressEventJsonData, encoding: String.Encoding.ascii)

                    self._eventSink!(progressEventJson)

                    if progress.isFinalLeg && progress.currentLegProgress.userHasArrivedAtWaypoint {
                        self._eventSink = nil
                    }
                }
            }
            .store(in: &cancellables)  // Store the subscription in a Set<AnyCancellable>
    }
}

extension FlutterMapboxNavigationView: NavigationMapViewDelegate {

    // Note: The commented out method has changed in v3
    // If you need this functionality, use the new method signature below:
    // public func navigationMapView(_ mapView: NavigationMapView, didFinishLoadingStyle style: MapboxMaps.Style) {
    //     _mapInitialized = true
    //     sendEvent(eventType: MapBoxEventType.map_ready)
    // }

    public func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        self.selectedRouteIndex = self.routeResponse?.routes?.firstIndex(of: route) ?? 0
        if let routes = self.routeResponse?.routes {
            let sorted = routes.sorted { first, second in
                first == route
            }
            mapView.show(routes: sorted)
        }
    }

    public func navigationMapView(_ mapView: NavigationMapView, didFinishLoadingMap: Bool) {
        // Wait for the map to load before initiating the first camera movement.
        if didFinishLoadingMap {
            moveCameraToCenter()
        }
    }
}

extension FlutterMapboxNavigationView: UIGestureRecognizerDelegate {

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = navigationMapView.mapView.mapboxMap.coordinate(
            for: gesture.location(in: navigationMapView.mapView))
        requestRoute(destination: location)
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = navigationMapView.mapView.mapboxMap.coordinate(
            for: gesture.location(in: navigationMapView.mapView))
        let waypoint: Encodable = [
            "latitude": location.latitude,
            "longitude": location.longitude,
        ]
        do {
            let encodedData = try JSONEncoder().encode(waypoint)
            let jsonString = String(
                data: encodedData,
                encoding: .utf8)

            if jsonString?.isEmpty ?? true {
                return
            }

            sendEvent(eventType: .on_map_tap, data: jsonString!)
        } catch {
            return
        }
    }

    func requestRoute(destination: CLLocationCoordinate2D) {
        isEmbeddedNavigation = true
        sendEvent(eventType: MapBoxEventType.route_building)

        guard let userLocation = navigationMapView.mapView.location.latestLocation else { return }

        // Create waypoints
        let userWaypoint = Waypoint(coordinate: userLocation.coordinate)
        let destinationWaypoint = Waypoint(coordinate: destination)

        // Create navigation route options
        let navigationRouteOptions = NavigationRouteOptions(waypoints: [
            userWaypoint, destinationWaypoint,
        ])

        // Use the routing provider to calculate routes
        let navigationProvider = navigationMapView.navigationProvider

        Task {
            do {
                let routesResponse = try await navigationProvider.routingProvider().calculateRoutes(
                    options: navigationRouteOptions
                ).value

                // Handle successful route calculation
                self.routeResponse = routesResponse
                self.sendEvent(
                    eventType: MapBoxEventType.route_built,
                    data: self.encodeRouteResponse(response: routesResponse))
                self.routeOptions = navigationRouteOptions
                self._routes = routesResponse.routes

                // Show routes on map
                if let routes = routesResponse.routes {
                    self.navigationMapView.show(routes: routes)
                    if let firstRoute = routes.first {
                        self.navigationMapView.showWaypoints(on: firstRoute)
                    }
                }
            } catch {
                print(error.localizedDescription)
                self.sendEvent(eventType: MapBoxEventType.route_build_failed)
            }
        }
    }
}
