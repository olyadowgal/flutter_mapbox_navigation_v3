package com.eopeter.fluttermapboxnavigation.models.views

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import android.view.View
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.eopeter.fluttermapboxnavigation.FlutterMapboxNavigationPlugin
import com.eopeter.fluttermapboxnavigation.TurnByTurn
import com.eopeter.fluttermapboxnavigation.activity.NavigationLauncher
import com.eopeter.fluttermapboxnavigation.databinding.NavigationActivityBinding
import com.eopeter.fluttermapboxnavigation.models.MapBoxEvents
import com.eopeter.fluttermapboxnavigation.models.Waypoint
import com.eopeter.fluttermapboxnavigation.utilities.PluginUtilities
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Style
import com.mapbox.maps.extension.style.expressions.dsl.generated.zoom
import com.mapbox.maps.extension.style.style
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.annotation.annotations
import com.mapbox.maps.plugin.annotation.generated.CircleAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.PolylineAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createCircleAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.createPolylineAnnotationManager
import com.mapbox.maps.plugin.gestures.OnMapClickListener
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.navigation.dropin.map.MapViewObserver
import com.mapbox.turf.TurfMeasurement.center
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject

class EmbeddedNavigationMapView(
    context: Context,
    activity: Activity,
    binding: NavigationActivityBinding,
    binaryMessenger: BinaryMessenger,
    vId: Int,
    args: Any?,
    accessToken: String
) : PlatformView, TurnByTurn(context, activity, binding, accessToken) {
    private val viewId: Int = vId
    private val messenger: BinaryMessenger = binaryMessenger
    private val arguments = args as Map<*, *>
    var mapView: MapView? = null
    private var addAnnotationBroadcastReceiver: BroadcastReceiver? = null

    override fun initFlutterChannelHandlers() {
        methodChannel = MethodChannel(messenger, "flutter_mapbox_navigation/${viewId}")
        eventChannel = EventChannel(messenger, "flutter_mapbox_navigation/${viewId}/events")
        super.initFlutterChannelHandlers()
    }

    override fun onMethodCall(methodCall: MethodCall, result: MethodChannel.Result) {
        when (methodCall.method) {
            //This is custom code for StreetIQ
            //addCustomMarkers s a custom StreetIq method to show markers on a map
            "addCustomMarkers" -> {
                addCustomMarkers(methodCall, result)

            }
            "addCustomPolyline" -> {
                addCustomPolyline(methodCall, result)
            }

            "addCenterPoint" -> {
                addCenterPoint(methodCall, result)
            }

            else -> result.notImplemented()
        }
    }


    open fun initialize() {
        initFlutterChannelHandlers()
        initNavigation()

        this.binding.navigationView.registerMapObserver(onMapAttached)

        if (!(this.arguments?.get("longPressDestinationEnabled") as Boolean)) {
            this.binding.navigationView.customizeViewOptions {
                enableMapLongClickIntercept = false;
            }
        }

        if ((this.arguments?.get("enableOnMapTapCallback") as Boolean)) {
            this.binding.navigationView.registerMapObserver(onMapClick)
        }
    }

    override fun getView(): View {
        return binding.root
    }

    override fun dispose() {
        addAnnotationBroadcastReceiver?.let {
            this.activity.unregisterReceiver(it)
        }
        this.binding.navigationView.unregisterMapObserver(onMapAttached)
        if ((this.arguments?.get("enableOnMapTapCallback") as Boolean)) {
            this.binding.navigationView.unregisterMapObserver(onMapClick)
        }
        unregisterObservers()
    }

    //This is custom code for StreetIQ
    /**addCustomMarkers is a custom StreetIq method to show markers on a map
     *This method is called from the Flutter side
     * It takes a list of markers and adds them to the map
     */
    private fun addCustomMarkers(methodCall: MethodCall, result: MethodChannel.Result) {
        // Extract the arguments as a Map<String, Any?> to match the new structure
        val arguments = methodCall.arguments as? Map<String, Any?>

        // Ensure that the 'markers' key exists and that it's a List
        val markersArray = arguments?.get("markers") as? List<Map<String, Any?>>

        if (markersArray.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENTS", "Markers list must not be null or empty", null)
            Log.d("Embedded", "Markers list must not be null or empty")
            return
        }

        // Convert the list of maps into a List<Waypoint>
        val waypoints = markersArray.mapNotNull { marker ->
            val latitude = marker["latitude"] as? Double
            val longitude = marker["longitude"] as? Double
            val title = marker["title"] as? String ?: ""

            if (latitude != null && longitude != null) {
                Log.d("Embedded", "Markers list added Waypoint")
                Waypoint(title, longitude, latitude, false) // Create Waypoint
            } else {
                null // Skip invalid data
            }
        }

        if (waypoints.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "No valid waypoints found", null)
            return
        }

        // Check if mapView is initialized and add annotations
        if (mapView != null) {
            waypoints.forEach { waypoint ->
                Log.d("Embedded", "Markers list: $waypoint")

                val annotationApi = mapView!!.annotations
                val circleAnnotationManager =
                    annotationApi.createCircleAnnotationManager()

                // Create and configure circle annotation options
                val circleAnnotationOptions = CircleAnnotationOptions()
                    .withPoint(
                        Point.fromLngLat(
                            waypoint.point.longitude(),
                            waypoint.point.latitude()
                        )
                    ) // Waypoint's location
                    .withCircleRadius(4.0) // Circle size
                    .withCircleColor("#90c5fc") // Circle color
                    .withCircleStrokeWidth(2.0) // Border thickness
                    .withCircleStrokeColor("#c6ddf5") // Border color

                // Add the circle annotation to the map
                circleAnnotationManager.create(circleAnnotationOptions)
            }
        }
    }

    //This is custom code for StreetIQ
    /**ddCustomPolyline is a custom StreetIq method to draw a polyline on a map
     *This method is called from the Flutter side
     * It takes a list of points and adds them to the map
     */
    private fun addCustomPolyline(methodCall: MethodCall, result: MethodChannel.Result) {
        // Extract the arguments as a Map<String, Any?> to match the new structure
        val arguments = methodCall.arguments as? Map<String, Any?>

        // Ensure that the 'markers' key exists and that it's a List
        val markersArray = arguments?.get("points") as? List<Map<String, Any?>>

        if (markersArray.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENTS", "Markers list must not be null or empty", null)
            Log.d("Embedded", "Markers list must not be null or empty")
            return
        }

        // Convert the list of maps into a List<Waypoint>
        val waypoints = markersArray.mapNotNull { marker ->
            val latitude = marker["latitude"] as? Double
            val longitude = marker["longitude"] as? Double

            if (latitude != null && longitude != null) {
                Log.d("Embedded", "Markers list added Waypoint")
                Point.fromLngLat(longitude, latitude) // Create Waypoint
            } else {
                null // Skip invalid data
            }
        }

        if (waypoints.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "No valid waypoints found", null)
            return
        }

        // Check if mapView is initialized and add annotations
        if (mapView != null) {
            waypoints.forEach { waypoint ->
                Log.d("Embedded", "Markers list: $waypoint")

                val annotationApi = mapView!!.annotations
                val polylineAnnotationManager =
                    annotationApi.createPolylineAnnotationManager()

                // Create and configure circle annotation options
                val polylineAnnotationOptions: PolylineAnnotationOptions = PolylineAnnotationOptions()
                    .withPoints(waypoints)
                    // Style the line that will be added to the map.
                    .withLineColor("#4e86ee")
                    .withLineWidth(5.0)

                // Add the circle annotation to the map
                polylineAnnotationManager.create(polylineAnnotationOptions)
            }
        }
    }
    //This is custom code for StreetIQ
    /**addCenterPoint is a custom StreetIq method to center the map on a specific point
     *This method is called from the Flutter side
     * It takes a single point and centers the map on that point
     */
    private fun addCenterPoint(methodCall: MethodCall, result: MethodChannel.Result) {
        val arguments = methodCall.arguments as? Map<String, Any?>
        val latitude = arguments?.get("latitude") as? Double
        val longitude = arguments?.get("longitude") as? Double
        Log.d("Embedded", "Center point: $latitude, $longitude")

        if (latitude == null || longitude == null) {
            result.error("INVALID_ARGUMENTS", "Latitude and longitude must not be null", null)
            return
        }
        if (mapView != null) {
            mapView!!.getMapboxMap().also {
                it.setCamera(
                    CameraOptions.Builder()
                        .center(Point.fromLngLat(longitude, latitude))
                        .zoom(15.0)
                        .build()
                )
            }

            result.success(null)
        } else {
            result.error("MAP_NOT_READY", "MapView is not initialized", null)
        }
    }


    /**
     * Notifies with attach and detach events on [MapView]
     */
    private val onMapAttached = object : MapViewObserver() {
        override fun onAttached(mapView: MapView) {
            this@EmbeddedNavigationMapView.mapView = mapView
        }
    }

    /**
     * Notifies with attach and detach events on [MapView]
     */
    private val onMapClick = object : MapViewObserver(), OnMapClickListener {

        override fun onAttached(mapView: MapView) {
            mapView.gestures.addOnMapClickListener(this)
        }

        override fun onDetached(mapView: MapView) {
            mapView.gestures.removeOnMapClickListener(this)
        }

        override fun onMapClick(point: Point): Boolean {
            var waypoint = mapOf<String, String>(
                Pair("latitude", point.latitude().toString()),
                Pair("longitude", point.longitude().toString())
            )
            PluginUtilities.sendEvent(MapBoxEvents.ON_MAP_TAP, JSONObject(waypoint).toString())
            return false
        }
    }

}
