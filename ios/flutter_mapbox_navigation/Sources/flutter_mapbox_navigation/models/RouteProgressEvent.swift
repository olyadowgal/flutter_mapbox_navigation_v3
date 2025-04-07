import Foundation
import MapboxDirections
import MapboxNavigationCore

public class MapBoxRouteProgressEvent: Codable {
    let arrived: Bool
    let distance: Double
    let duration: Double
    let distanceTraveled: Double
    let currentLegDistanceTraveled: Double
    let currentLegDistanceRemaining: Double
    let currentStepInstruction: String
    let legIndex: Int
    let stepIndex: Int
    let currentLeg: MapBoxRouteLeg
    var priorLeg: MapBoxRouteLeg? = nil
    var remainingLegs: [MapBoxRouteLeg] = []

    init(progress: RouteProgress) {
        // In v3, we check if it's the final leg and if the user has arrived at waypoint
        arrived = progress.isFinalLeg && progress.currentLegProgress.userHasArrivedAtWaypoint

        // These properties are still available in v3 with the same names
        distance = Double(progress.distanceRemaining)
        duration = progress.durationRemaining
        distanceTraveled = Double(progress.distanceTraveled)
        legIndex = progress.legIndex
        stepIndex = progress.currentLegProgress.stepIndex

        currentLeg = MapBoxRouteLeg(leg: progress.currentLegProgress.leg)

        if let priorLegValue = progress.priorLeg {
            priorLeg = MapBoxRouteLeg(leg: priorLegValue)
        }

        for leg in progress.remainingLegs {
            remainingLegs.append(MapBoxRouteLeg(leg: leg))
        }

        // These properties are accessed through currentLegProgress in v3
        currentLegDistanceTraveled = Double(progress.currentLegProgress.distanceTraveled)
        currentLegDistanceRemaining = Double(progress.currentLegProgress.distanceRemaining)
        currentStepInstruction = progress.currentLegProgress.currentStep.description
    }
}