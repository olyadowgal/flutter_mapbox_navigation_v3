//
//  FreeDriveViewController.swift
//  flutter_mapbox_navigation
//
//  Created by Emmanuel Oche on 5/25/23.
//

import UIKit
import MapboxNavigationUIKit // Changed from MapboxNavigation
import MapboxNavigationCore // Changed from MapboxCoreNavigation
import MapboxMaps
import Combine

public class FreeDriveViewController : UIViewController {
    
    private var navigationMapView: NavigationMapView!
    private var navigationProvider: MapboxNavigationProvider!
    private var cancellables = Set<AnyCancellable>()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationProvider()
        setupNavigationMapView()
        startFreeDrive()
    }
    
    private func setupNavigationProvider() {
        let coreConfig = CoreConfig()
        navigationProvider = MapboxNavigationProvider(coreConfig: coreConfig)
    }
    
    private func setupNavigationMapView() {
        // Initialize NavigationMapView with location and routeProgress publishers
        navigationMapView = NavigationMapView(
            location: navigationProvider.navigation().locationMatching
                .map(\.mapMatchingResult.enhancedLocation)
                .eraseToAnyPublisher(),
            routeProgress: navigationProvider.navigation().routeProgress
                .map(\.?.routeProgress)
                .eraseToAnyPublisher(),
            navigationCameraType: .following,
            heading: navigationProvider.navigation().heading,
            predictiveCacheManager: navigationProvider.predictiveCacheManager
        )
        
        navigationMapView.frame = view.bounds
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.puckType = .puck2D() // Updated from userLocationStyle
        
        // Configure the viewport data source
        let navigationViewportDataSource = MobileViewportDataSource(navigationMapView.mapView)
        navigationViewportDataSource.options.followingCameraOptions.zoomUpdatesAllowed = false
        navigationViewportDataSource.options.followingCameraOptions.zoom = 17.0
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        view.addSubview(navigationMapView)
    }
    
    private func startFreeDrive() {
        Task {
            try? await navigationProvider.tripSession().startFreeDrive()
        }
    }
}
