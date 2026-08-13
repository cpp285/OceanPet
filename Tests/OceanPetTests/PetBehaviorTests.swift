import CoreGraphics
import XCTest
@testable import OceanPet

final class PetBehaviorTests: XCTestCase {
    @MainActor
    func testPupilOffsetFollowsDirectionAndStaysInEye() {
        let right = PetScene.pupilOffset(
            delta: CGVector(dx: 800, dy: 0),
            maxOffset: CGSize(width: 5, height: 4)
        )
        XCTAssertEqual(right.width, 5, accuracy: 0.001)
        XCTAssertEqual(right.height, 0, accuracy: 0.001)

        let upperLeft = PetScene.pupilOffset(
            delta: CGVector(dx: -400, dy: 400),
            maxOffset: CGSize(width: 5, height: 4)
        )
        XCTAssertLessThan(upperLeft.width, 0)
        XCTAssertGreaterThan(upperLeft.height, 0)
        XCTAssertLessThanOrEqual(abs(upperLeft.width), 5)
        XCTAssertLessThanOrEqual(abs(upperLeft.height), 4)
    }

    @MainActor
    func testWalkPoseLoopsContinuouslyWithoutASettlePause() {
        let start = PetScene.walkPose(progress: 0)
        let end = PetScene.walkPose(progress: 1)
        XCTAssertEqual(start.verticalOffset, end.verticalOffset, accuracy: 0.0001)
        XCTAssertEqual(start.rotation, end.rotation, accuracy: 0.0001)
        XCTAssertEqual(start.xScale, end.xScale, accuracy: 0.0001)
        XCTAssertEqual(start.yScale, end.yScale, accuracy: 0.0001)

        let firstStep = PetScene.walkPose(progress: 0.25)
        let oppositeStep = PetScene.walkPose(progress: 0.75)
        XCTAssertGreaterThan(firstStep.verticalOffset, 1)
        XCTAssertEqual(firstStep.verticalOffset, oppositeStep.verticalOffset, accuracy: 0.0001)
        XCTAssertEqual(firstStep.rotation, -oppositeStep.rotation, accuracy: 0.0001)
        XCTAssertLessThan(abs(firstStep.rotation), 0.02)
    }

    @MainActor
    func testRoamingTargetStaysNearHomeAndInsideScreen() {
        let home = CGPoint(x: 500, y: 300)
        let target = PetWindowController.boundedRoamTarget(
            home: home,
            requestedOffset: CGVector(dx: 900, dy: -900),
            visibleFrame: CGRect(x: 0, y: 90, width: 1200, height: 750),
            windowSize: CGSize(width: 210, height: 230)
        )
        XCTAssertEqual(target.x, home.x + 160, accuracy: 0.001)
        XCTAssertEqual(target.y, home.y, accuracy: 0.001)

        let edgeTarget = PetWindowController.boundedRoamTarget(
            home: CGPoint(x: 1080, y: 700),
            requestedOffset: CGVector(dx: 160, dy: 45),
            visibleFrame: CGRect(x: 0, y: 90, width: 1200, height: 750),
            windowSize: CGSize(width: 210, height: 230)
        )
        XCTAssertLessThanOrEqual(edgeTarget.x + 210, 1192)
        XCTAssertLessThanOrEqual(edgeTarget.y + 230, 840)
    }

    @MainActor
    func testRoamingAcceleratesAndStopsWithoutOvershooting() {
        var origin = CGPoint(x: 100, y: 100)
        var velocity = CGVector.zero
        let target = CGPoint(x: 220, y: 120)
        var speeds: [CGFloat] = []
        var reachedTarget = false

        for _ in 0..<600 {
            let step = PetWindowController.nextRoamStep(
                origin: origin,
                velocity: velocity,
                target: target,
                deltaTime: 1.0 / 60.0
            )
            origin = step.origin
            velocity = step.velocity
            speeds.append(hypot(velocity.dx, velocity.dy))
            if step.reachedTarget {
                reachedTarget = true
                break
            }
        }

        XCTAssertTrue(reachedTarget)
        XCTAssertEqual(origin.x, target.x, accuracy: 0.001)
        XCTAssertEqual(origin.y, target.y, accuracy: 0.001)
        XCTAssertEqual(velocity.dx, 0, accuracy: 0.001)
        XCTAssertEqual(velocity.dy, 0, accuracy: 0.001)
        XCTAssertGreaterThan(speeds[4], speeds[0])
    }

    @MainActor
    func testPixelHitTestingDistinguishesBodyFromTransparentArea() throws {
        let store = CharacterStore()
        let character = try XCTUnwrap(store.active)
        let scene = PetScene(size: PetWindow.contentSize)
        try scene.apply(character: character)

        XCTAssertEqual(scene.children.count, 1)
        XCTAssertTrue(scene.children[0].children.isEmpty)
        XCTAssertTrue(scene.isOpaque(at: CGPoint(x: 105, y: 110)))
        XCTAssertFalse(scene.isOpaque(at: CGPoint(x: 34, y: 185)))
        XCTAssertFalse(scene.isOpaque(at: CGPoint(x: 5, y: 225)))
    }

    @MainActor
    func testSquidwardNarrowBodyRemainsClickable() throws {
        let store = CharacterStore()
        let squidward = try XCTUnwrap(store.characters.first { $0.id == "squidward-cartoon" })
        let scene = PetScene(size: PetWindow.contentSize)
        try scene.apply(character: squidward)

        XCTAssertTrue(scene.isOpaque(at: CGPoint(x: 100, y: 120)))
        XCTAssertTrue(scene.isOpaque(at: CGPoint(x: 100, y: 140)))
        XCTAssertTrue(scene.isOpaque(at: CGPoint(x: 120, y: 62)))
        XCTAssertTrue(scene.isOpaque(at: CGPoint(x: 145, y: 120)))
        XCTAssertFalse(scene.isOpaque(at: CGPoint(x: 5, y: 225)))
    }

}
