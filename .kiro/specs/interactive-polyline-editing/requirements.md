# Requirements Document

## Introduction

This feature enables interactive editing of polylines on MapLibre maps for Android and iOS platforms. Users can tap and hold on any point along a polyline to break it into two segments, then drag the break point to create new routing paths. This functionality is similar to flight path editing in aviation apps like ForeFlight, where pilots can modify their route by breaking and redirecting segments to different waypoints or airports.

## Requirements

### Requirement 1

**User Story:** As a map user, I want to tap and hold on any point along a polyline, so that I can break it into two separate segments at that location.

#### Acceptance Criteria

1. WHEN a user performs a long press gesture on any point along a polyline THEN the system SHALL detect the touch location and break the polyline into two segments at the nearest point on the line
2. WHEN the polyline is broken THEN the system SHALL create a draggable control point at the break location
3. WHEN the break occurs THEN the system SHALL maintain the original styling and properties of both resulting polyline segments
4. IF the long press is not on a polyline THEN the system SHALL not create any break points or modify existing polylines

### Requirement 2

**User Story:** As a map user, I want to drag the break point to a new location, so that I can redirect the polyline path to connect different coordinates.

#### Acceptance Criteria

1. WHEN a user drags the break point control THEN the system SHALL update both polyline segments in real-time to connect through the new dragged position
2. WHEN dragging occurs THEN the system SHALL provide visual feedback showing the updated path preview
3. WHEN the drag gesture ends THEN the system SHALL finalize the new polyline configuration with the updated coordinates
4. WHEN dragging THEN the system SHALL ensure smooth performance without lag or stuttering during the interaction

### Requirement 3

**User Story:** As a developer, I want this feature to work natively on Android and iOS platforms only, so that I can provide optimal performance for mobile users.

#### Acceptance Criteria

1. WHEN the feature is implemented THEN it SHALL be available only on Android and iOS platforms
2. WHEN running on web or other platforms THEN the system SHALL gracefully handle the absence of this feature without errors
3. WHEN implemented natively THEN the system SHALL use platform-specific gesture recognition for optimal responsiveness
4. WHEN integrated THEN the system SHALL follow MapLibre's existing architecture patterns for platform-specific features

### Requirement 4

**User Story:** As a developer, I want to receive callbacks when polylines are modified, so that I can update my application state and handle the new polyline data.

#### Acceptance Criteria

1. WHEN a polyline is broken THEN the system SHALL trigger a callback with the original polyline ID and the two new polyline segments
2. WHEN a drag operation completes THEN the system SHALL provide a callback with the updated polyline coordinates
3. WHEN callbacks are triggered THEN they SHALL include sufficient data to identify which polylines were affected and their new configurations
4. WHEN errors occur during editing THEN the system SHALL provide error callbacks with descriptive messages

### Requirement 5

**User Story:** As a map user, I want visual feedback during the editing process, so that I can clearly see what changes I'm making to the polyline.

#### Acceptance Criteria

1. WHEN a break point is created THEN the system SHALL display a distinct visual indicator (such as a draggable handle or marker) at the break location
2. WHEN dragging is in progress THEN the system SHALL show a preview of the new polyline path with different styling to indicate it's being modified
3. WHEN the drag operation is complete THEN the system SHALL update the visual representation to show the final polyline configuration
4. WHEN multiple polylines exist THEN the system SHALL only highlight and modify the polyline being actively edited

### Requirement 6

**User Story:** As a developer, I want to configure which polylines are editable, so that I can control which routes users can modify in my application.

#### Acceptance Criteria

1. WHEN creating or updating a polyline THEN the system SHALL accept an "editable" property to enable or disable interactive editing
2. WHEN a polyline is marked as non-editable THEN long press gestures SHALL not create break points on that polyline
3. WHEN polylines have different editability settings THEN the system SHALL only allow editing on polylines explicitly marked as editable
4. IF no editability is specified THEN the system SHALL default to non-editable behavior for backward compatibility