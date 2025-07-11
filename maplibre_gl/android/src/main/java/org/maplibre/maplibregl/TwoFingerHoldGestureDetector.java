package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;

/**
 * Detects two-finger hold gestures on the map.
 */
public class TwoFingerHoldGestureDetector {
    private static final long HOLD_DURATION_MS = 500; // 500ms hold duration
    private static final float MOVEMENT_THRESHOLD = 50f; // pixels
    
    private final MapLibreMap mapLibreMap;
    private final OnTwoFingerHoldGestureListener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    
    private boolean isTwoFingerDown = false;
    private PointF initialPoint1;
    private PointF initialPoint2;
    private PointF centerPoint;
    private long gestureStartTime;
    private Runnable holdRunnable;
    
    public interface OnTwoFingerHoldGestureListener {
        void onTwoFingerHoldGesture(PointF point, LatLng latLng, long duration);
    }
    
    public TwoFingerHoldGestureDetector(MapLibreMap mapLibreMap, OnTwoFingerHoldGestureListener listener) {
        this.mapLibreMap = mapLibreMap;
        this.listener = listener;
    }
    
    public boolean onTouchEvent(MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                // First finger down
                if (event.getPointerCount() == 1) {
                    initialPoint1 = new PointF(event.getX(), event.getY());
                }
                break;
                
            case MotionEvent.ACTION_POINTER_DOWN:
                // Second finger down
                if (event.getPointerCount() == 2) {
                    initialPoint2 = new PointF(event.getX(1), event.getY(1));
                    centerPoint = new PointF(
                        (initialPoint1.x + initialPoint2.x) / 2,
                        (initialPoint1.y + initialPoint2.y) / 2
                    );
                    
                    isTwoFingerDown = true;
                    gestureStartTime = System.currentTimeMillis();
                    
                    // Schedule the hold detection
                    holdRunnable = new Runnable() {
                        @Override
                        public void run() {
                            if (isTwoFingerDown && listener != null) {
                                long duration = System.currentTimeMillis() - gestureStartTime;
                                LatLng latLng = mapLibreMap.getProjection().fromScreenLocation(centerPoint);
                                listener.onTwoFingerHoldGesture(centerPoint, latLng, duration);
                            }
                        }
                    };
                    handler.postDelayed(holdRunnable, HOLD_DURATION_MS);
                }
                break;
                
            case MotionEvent.ACTION_MOVE:
                if (isTwoFingerDown && event.getPointerCount() == 2) {
                    // Check if fingers moved too much
                    float currentX1 = event.getX(0);
                    float currentY1 = event.getY(0);
                    float currentX2 = event.getX(1);
                    float currentY2 = event.getY(1);
                    
                    float distance1 = (float) Math.sqrt(
                        Math.pow(currentX1 - initialPoint1.x, 2) + 
                        Math.pow(currentY1 - initialPoint1.y, 2)
                    );
                    float distance2 = (float) Math.sqrt(
                        Math.pow(currentX2 - initialPoint2.x, 2) + 
                        Math.pow(currentY2 - initialPoint2.y, 2)
                    );
                    
                    if (distance1 > MOVEMENT_THRESHOLD || distance2 > MOVEMENT_THRESHOLD) {
                        cancelGesture();
                    }
                }
                break;
                
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                cancelGesture();
                break;
        }
        
        return false; // Don't consume the event
    }
    
    private void cancelGesture() {
        isTwoFingerDown = false;
        if (holdRunnable != null) {
            handler.removeCallbacks(holdRunnable);
            holdRunnable = null;
        }
    }
    
    public void cleanup() {
        cancelGesture();
    }
}