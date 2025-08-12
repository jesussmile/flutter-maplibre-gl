#include <jni.h>
#include <string>
#include <memory>
#include <android/log.h>
#include "triangle_renderer.h"

#define LOG_TAG "TriangleLayerJNI"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Custom layer callbacks structure that will be passed to MapLibre
struct TriangleCustomLayerCallbacks {
    std::unique_ptr<TriangleRenderer> renderer;
    JavaVM* jvm;
    jobject hostRef;
    
    TriangleCustomLayerCallbacks(JavaVM* vm, jobject host) 
        : jvm(vm), hostRef(host) {
        // Get global reference to Java host object
        JNIEnv* env;
        jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        hostRef = env->NewGlobalRef(host);
        
        // Create the native renderer
        renderer = std::make_unique<TriangleRenderer>();
    }
    
    ~TriangleCustomLayerCallbacks() {
        JNIEnv* env;
        jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (hostRef) {
            env->DeleteGlobalRef(hostRef);
            hostRef = nullptr;
        }
    }
};

// Forward declarations of native callback functions
extern "C" {
    void triangle_layer_initialize(void* context);
    void triangle_layer_render(void* context, const float* matrix);
    void triangle_layer_deinitialize(void* context);
}

// Native callback implementations
void triangle_layer_initialize(void* context) {
    TriangleCustomLayerCallbacks* callbacks = static_cast<TriangleCustomLayerCallbacks*>(context);
    if (callbacks && callbacks->renderer) {
        LOGD("Initializing native triangle renderer");
        callbacks->renderer->initialize();
        
        // Notify Java host
        JNIEnv* env;
        callbacks->jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        jclass hostClass = env->GetObjectClass(callbacks->hostRef);
        jmethodID onInitMethod = env->GetMethodID(hostClass, "onInitialize", "()V");
        if (onInitMethod) {
            env->CallVoidMethod(callbacks->hostRef, onInitMethod);
        }
    }
}

void triangle_layer_render(void* context, const float* matrix) {
    TriangleCustomLayerCallbacks* callbacks = static_cast<TriangleCustomLayerCallbacks*>(context);
    if (callbacks && callbacks->renderer && matrix) {
        // Convert matrix from float array to appropriate format
        // MapLibre provides a 4x4 transformation matrix
        callbacks->renderer->render(matrix);
        
        // Optionally notify Java host about render call
        JNIEnv* env;
        callbacks->jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        jclass hostClass = env->GetObjectClass(callbacks->hostRef);
        jmethodID onRenderMethod = env->GetMethodID(hostClass, "onRender", "([F)V");
        if (onRenderMethod) {
            // Create Java float array from matrix
            jfloatArray matrixArray = env->NewFloatArray(16);
            env->SetFloatArrayRegion(matrixArray, 0, 16, matrix);
            env->CallVoidMethod(callbacks->hostRef, onRenderMethod, matrixArray);
            env->DeleteLocalRef(matrixArray);
        }
    }
}

void triangle_layer_deinitialize(void* context) {
    TriangleCustomLayerCallbacks* callbacks = static_cast<TriangleCustomLayerCallbacks*>(context);
    if (callbacks) {
        LOGD("Deinitializing native triangle renderer");
        if (callbacks->renderer) {
            callbacks->renderer->deinitialize();
        }
        
        // Notify Java host
        JNIEnv* env;
        callbacks->jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        jclass hostClass = env->GetObjectClass(callbacks->hostRef);
        jmethodID onDeinitMethod = env->GetMethodID(hostClass, "onDeinitialize", "()V");
        if (onDeinitMethod) {
            env->CallVoidMethod(callbacks->hostRef, onDeinitMethod);
        }
        
        // Clean up the callbacks object
        delete callbacks;
    }
}

// JNI method implementations
extern "C" JNIEXPORT jlong JNICALL
Java_org_maplibre_maplibregl_MapLibreMapController_createNativeCustomLayerCallbacks(
    JNIEnv* env, jobject thiz, jobject triangleHost) {
    
    LOGD("Creating native custom layer callbacks");
    
    try {
        // Get JavaVM instance
        JavaVM* jvm;
        env->GetJavaVM(&jvm);
        
        // Create callbacks structure
        TriangleCustomLayerCallbacks* callbacks = new TriangleCustomLayerCallbacks(jvm, triangleHost);
        
        // Return the callbacks pointer as a long (this will be passed to CustomLayer constructor)
        return reinterpret_cast<jlong>(callbacks);
        
    } catch (const std::exception& e) {
        LOGE("Exception creating custom layer callbacks: %s", e.what());
        return 0;
    }
}

// Alternative approach: Export callback function pointers that MapLibre can use directly
extern "C" JNIEXPORT jlong JNICALL
Java_org_maplibre_maplibregl_MapLibreMapController_getInitializeFunctionPointer(
    JNIEnv* env, jobject thiz) {
    return reinterpret_cast<jlong>(&triangle_layer_initialize);
}

extern "C" JNIEXPORT jlong JNICALL
Java_org_maplibre_maplibregl_MapLibreMapController_getRenderFunctionPointer(
    JNIEnv* env, jobject thiz) {
    return reinterpret_cast<jlong>(&triangle_layer_render);
}

extern "C" JNIEXPORT jlong JNICALL
Java_org_maplibre_maplibregl_MapLibreMapController_getDeinitializeFunctionPointer(
    JNIEnv* env, jobject thiz) {
    return reinterpret_cast<jlong>(&triangle_layer_deinitialize);
}

extern "C" JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_MapLibreMapController_destroyNativeCustomLayerCallbacks(
    JNIEnv* env, jobject thiz, jlong nativeHandle) {
    
    LOGD("Destroying native custom layer callbacks");
    
    if (nativeHandle != 0) {
        TriangleCustomLayerCallbacks* callbacks = reinterpret_cast<TriangleCustomLayerCallbacks*>(nativeHandle);
        delete callbacks;
    }
}

// Method to update triangle data from Java layer
extern "C" JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomLayerHost_updateTriangleData(
    JNIEnv* env, jobject thiz, jlong nativeHandle, jfloatArray vertices, jintArray indices) {
    
    if (nativeHandle == 0) {
        LOGE("Native handle is null in updateTriangleData");
        return;
    }
    
    TriangleCustomLayerCallbacks* callbacks = reinterpret_cast<TriangleCustomLayerCallbacks*>(nativeHandle);
    if (!callbacks || !callbacks->renderer) {
        LOGE("Invalid callbacks or renderer in updateTriangleData");
        return;
    }
    
    try {
        // Get vertex data
        jfloat* vertexData = nullptr;
        jsize vertexCount = 0;
        if (vertices) {
            vertexData = env->GetFloatArrayElements(vertices, nullptr);
            vertexCount = env->GetArrayLength(vertices);
        }
        
        // Get index data  
        jint* indexData = nullptr;
        jsize indexCount = 0;
        if (indices) {
            indexData = env->GetIntArrayElements(indices, nullptr);
            indexCount = env->GetArrayLength(indices);
        }
        
        // Update renderer with new data
        if (vertexData && indexData) {
            callbacks->renderer->updateTriangles(vertexData, vertexCount, 
                                                reinterpret_cast<unsigned int*>(indexData), indexCount);
            LOGD("Updated triangle data: %d vertices, %d indices", vertexCount, indexCount);
        }
        
        // Release arrays
        if (vertices && vertexData) {
            env->ReleaseFloatArrayElements(vertices, vertexData, JNI_ABORT);
        }
        if (indices && indexData) {
            env->ReleaseIntArrayElements(indices, indexData, JNI_ABORT);
        }
        
    } catch (const std::exception& e) {
        LOGE("Exception updating triangle data: %s", e.what());
    }
}

// Method to set triangle rendering properties
extern "C" JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomLayerHost_setTriangleProperties(
    JNIEnv* env, jobject thiz, jlong nativeHandle, jfloat red, jfloat green, jfloat blue, jfloat alpha) {
    
    if (nativeHandle == 0) {
        LOGE("Native handle is null in setTriangleProperties");
        return;
    }
    
    TriangleCustomLayerCallbacks* callbacks = reinterpret_cast<TriangleCustomLayerCallbacks*>(nativeHandle);
    if (!callbacks || !callbacks->renderer) {
        LOGE("Invalid callbacks or renderer in setTriangleProperties");
        return;
    }
    
    try {
        callbacks->renderer->setColor(red, green, blue, alpha);
        LOGD("Set triangle color: (%f, %f, %f, %f)", red, green, blue, alpha);
    } catch (const std::exception& e) {
        LOGE("Exception setting triangle properties: %s", e.what());
    }
}
