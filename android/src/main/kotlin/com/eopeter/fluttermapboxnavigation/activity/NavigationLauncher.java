package com.eopeter.fluttermapboxnavigation.activity;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;

import com.eopeter.fluttermapboxnavigation.models.Waypoint;

import java.io.Serializable;
import java.util.List;

public class NavigationLauncher {
    public static final String KEY_ADD_WAYPOINTS = "com.my.mapbox.broadcast.ADD_WAYPOINTS";
    public static final String KEY_STOP_NAVIGATION = "com.my.mapbox.broadcast.STOP_NAVIGATION";
    public static final String KEY_ADD_ANNOTATION = "com.my.mapbox.broadcast.ADD_ANNOTATION";

    public static void startNavigation(Activity activity, List<Waypoint> wayPoints) {
        Intent navigationIntent = new Intent(activity, NavigationActivity.class);
        navigationIntent.putExtra("waypoints", (Serializable) wayPoints);
        activity.startActivity(navigationIntent);
    }

    public static void addWayPoints(Activity activity, List<Waypoint> wayPoints) {
        Intent navigationIntent = new Intent(activity, NavigationActivity.class);
        navigationIntent.setAction(KEY_ADD_WAYPOINTS);
        navigationIntent.putExtra("isAddingWayPoints", true);
        navigationIntent.putExtra("waypoints", (Serializable) wayPoints);
        activity.sendBroadcast(navigationIntent);
    }

    public static void stopNavigation(Activity activity) {
        Intent stopIntent = new Intent();
        stopIntent.setAction(KEY_STOP_NAVIGATION);
        activity.sendBroadcast(stopIntent);
    }

    //This is custom code for StreetIQ
    public static void addAnnotations(Activity activity, List<Waypoint> annotations) {
        Intent annotationIntent = new Intent();
        annotationIntent.setAction(KEY_ADD_ANNOTATION);
        annotationIntent.putExtra("annotations", (Serializable) annotations);
        activity.sendBroadcast(annotationIntent);
        Log.d("Embedded", "Broadcast sent");
    }

}
