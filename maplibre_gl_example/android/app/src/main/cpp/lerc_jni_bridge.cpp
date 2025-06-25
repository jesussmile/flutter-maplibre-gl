#include <jni.h>
#include <string>
#include <android/log.h>

#include "lerc_wrapper.h"

#define LOG_TAG "LercTerrainJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jboolean JNICALL
Java_org_maplibre_example_terrain_LercNativeLoader_initialize(JNIEnv *env, jobject /* this */) {
    bool result = lerc_wrapper_initialize();
    return static_cast<jboolean>(result);
}

JNIEXPORT jobject JNICALL
Java_org_maplibre_example_terrain_LercNativeLoader_getLercInfo(JNIEnv *env, jobject /* this */, jbyteArray buffer) {
    // Get the byte array from Java
    jsize bufferLength = env->GetArrayLength(buffer);
    jbyte* bufferPtr = env->GetByteArrayElements(buffer, nullptr);
    
    // Get LERC info using the C++ wrapper
    LercInfo* info = lerc_wrapper_get_info(reinterpret_cast<const uint8_t*>(bufferPtr), bufferLength);
    
    // Release the byte array
    env->ReleaseByteArrayElements(buffer, bufferPtr, JNI_ABORT);
    
    if (info == nullptr) {
        return nullptr;
    }
    
    // Create a Java LercInfo object
    jclass lercInfoClass = env->FindClass("org/maplibre/example/terrain/LercInfo");
    if (lercInfoClass == nullptr) {
        LOGE("Could not find LercInfo class");
        lerc_wrapper_free_info(info);
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(lercInfoClass, "<init>", "(IIIIDDD)V");
    if (constructor == nullptr) {
        LOGE("Could not find LercInfo constructor");
        lerc_wrapper_free_info(info);
        return nullptr;
    }
    
    jobject javaInfo = env->NewObject(lercInfoClass, constructor,
        info->width, 
        info->height, 
        info->numBands, 
        info->numValidPixels, 
        info->minValue, 
        info->maxValue, 
        info->noDataValue
    );
    
    // Clean up native LERC info
    lerc_wrapper_free_info(info);
    
    return javaInfo;
}

JNIEXPORT jdoubleArray JNICALL
Java_org_maplibre_example_terrain_LercNativeLoader_decodeLerc(JNIEnv *env, jobject /* this */, jbyteArray buffer, jobject jInfo) {
    // Get LercInfo fields from Java object
    jclass lercInfoClass = env->GetObjectClass(jInfo);
    
    jfieldID widthField = env->GetFieldID(lercInfoClass, "width", "I");
    jfieldID heightField = env->GetFieldID(lercInfoClass, "height", "I");
    
    uint32_t width = env->GetIntField(jInfo, widthField);
    uint32_t height = env->GetIntField(jInfo, heightField);
    
    // Get the byte array from Java
    jsize bufferLength = env->GetArrayLength(buffer);
    jbyte* bufferPtr = env->GetByteArrayElements(buffer, nullptr);
    
    // Create a LercInfo struct for the decoder
    LercInfo nativeInfo;
    nativeInfo.width = width;
    nativeInfo.height = height;
    
    // Decode the LERC data
    double* data = lerc_wrapper_decode(reinterpret_cast<const uint8_t*>(bufferPtr), bufferLength, &nativeInfo);
    
    // Release the byte array
    env->ReleaseByteArrayElements(buffer, bufferPtr, JNI_ABORT);
    
    if (data == nullptr) {
        LOGE("Failed to decode LERC data");
        return nullptr;
    }
    
    // Create a Java double array to return the data
    jdoubleArray resultArray = env->NewDoubleArray(width * height);
    env->SetDoubleArrayRegion(resultArray, 0, width * height, data);
    
    // Free the native data
    lerc_wrapper_free_data(data);
    
    return resultArray;
}

} // extern "C"
