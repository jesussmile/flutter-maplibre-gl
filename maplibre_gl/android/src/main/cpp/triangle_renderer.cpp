#include "triangle_renderer.h"
#include <jni.h>
#include <GLES2/gl2.h>
#include <android/log.h>
#include <vector>
#include <cstring>

#define LOG_TAG "TriangleRenderer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Static shader sources
const char* TriangleRenderer::getVertexShaderSource() {
    static const char* source = R"(
        attribute vec3 a_position;
        uniform mat4 u_mvpMatrix;
        uniform vec4 u_color;
        varying vec4 v_color;
        
        void main() {
            gl_Position = u_mvpMatrix * vec4(a_position, 1.0);
            v_color = u_color;
        }
    )";
    return source;
}

const char* TriangleRenderer::getFragmentShaderSource() {
    static const char* source = R"(
        precision mediump float;
        varying vec4 v_color;
        
        void main() {
            gl_FragColor = v_color;
        }
    )";
    return source;
}

// Constructor
TriangleRenderer::TriangleRenderer() 
    : shaderProgram_(0)
    , vertexShader_(0)
    , fragmentShader_(0)
    , vertexBuffer_(0)
    , indexBuffer_(0)
    , vertexArray_(0)
    , mvpMatrixLocation_(-1)
    , colorLocation_(-1)
    , initialized_(false)
    , vertexCount_(0)
    , indexCount_(0)
    , triangleCount_(0) {
    
    color_[0] = 1.0f; // Red
    color_[1] = 0.0f; // Green
    color_[2] = 0.0f; // Blue
    color_[3] = 1.0f; // Alpha
    
    LOGI("TriangleRenderer created");
}

// Destructor
TriangleRenderer::~TriangleRenderer() {
    deinitialize();
    LOGI("TriangleRenderer destroyed");
}

// Initialize the renderer
bool TriangleRenderer::initialize() {
    if (initialized_) {
        LOGI("TriangleRenderer already initialized");
        return true;
    }
    
    LOGI("Initializing TriangleRenderer");
    
    if (!createShaderProgram()) {
        LOGE("Failed to create shader program");
        return false;
    }
    
    // Get uniform locations
    mvpMatrixLocation_ = glGetUniformLocation(shaderProgram_, "u_mvpMatrix");
    colorLocation_ = glGetUniformLocation(shaderProgram_, "u_color");
    
    if (mvpMatrixLocation_ == -1 || colorLocation_ == -1) {
        LOGE("Failed to get uniform locations");
        return false;
    }
    
    createBuffers();
    checkGLError("initialize");
    
    initialized_ = true;
    LOGI("TriangleRenderer initialized successfully");
    return true;
}

// Deinitialize the renderer
void TriangleRenderer::deinitialize() {
    if (!initialized_) {
        return;
    }
    
    destroyResources();
    initialized_ = false;
    LOGI("TriangleRenderer deinitialized");
}

// Update triangle data
void TriangleRenderer::updateTriangles(const float* vertices, int vertexCount, const unsigned int* indices, int indexCount) {
    if (!initialized_) {
        LOGE("TriangleRenderer not initialized");
        return;
    }
    
    vertexCount_ = vertexCount;
    indexCount_ = indexCount;
    triangleCount_ = indexCount / 3;
    
    // Update vertex buffer
    if (vertexBuffer_ > 0 && vertices && vertexCount > 0) {
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
        glBufferData(GL_ARRAY_BUFFER, vertexCount * 3 * sizeof(float), vertices, GL_DYNAMIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    
    // Update index buffer
    if (indexBuffer_ > 0 && indices && indexCount > 0) {
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer_);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexCount * sizeof(unsigned int), indices, GL_DYNAMIC_DRAW);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    }
    
    checkGLError("updateTriangles");
    LOGI("Updated %d triangles (%d vertices, %d indices)", triangleCount_, vertexCount, indexCount);
}

// Set triangle color
void TriangleRenderer::setColor(float red, float green, float blue, float alpha) {
    color_[0] = red;
    color_[1] = green;
    color_[2] = blue;
    color_[3] = alpha;
    LOGI("Set color to (%.2f, %.2f, %.2f, %.2f)", red, green, blue, alpha);
}

// Render triangles
void TriangleRenderer::render(const float* mvpMatrix) {
    if (!initialized_ || triangleCount_ == 0 || !mvpMatrix) {
        return;
    }
    
    // Use shader program
    glUseProgram(shaderProgram_);
    
    // Set uniforms
    glUniformMatrix4fv(mvpMatrixLocation_, 1, GL_FALSE, mvpMatrix);
    glUniform4fv(colorLocation_, 1, color_);
    
    // Bind vertex buffer and set attributes
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    
    // Bind index buffer and draw
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer_);
    glDrawElements(GL_TRIANGLES, indexCount_, GL_UNSIGNED_INT, 0);
    
    // Clean up state
    glDisableVertexAttribArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glUseProgram(0);
    
    checkGLError("render");
}

// Create shader program
bool TriangleRenderer::createShaderProgram() {
    // Compile vertex shader
    vertexShader_ = compileShader(GL_VERTEX_SHADER, getVertexShaderSource());
    if (vertexShader_ == 0) {
        LOGE("Failed to compile vertex shader");
        return false;
    }
    
    // Compile fragment shader
    fragmentShader_ = compileShader(GL_FRAGMENT_SHADER, getFragmentShaderSource());
    if (fragmentShader_ == 0) {
        LOGE("Failed to compile fragment shader");
        glDeleteShader(vertexShader_);
        vertexShader_ = 0;
        return false;
    }
    
    // Create and link program
    shaderProgram_ = glCreateProgram();
    if (shaderProgram_ == 0) {
        LOGE("Failed to create shader program");
        glDeleteShader(vertexShader_);
        glDeleteShader(fragmentShader_);
        vertexShader_ = 0;
        fragmentShader_ = 0;
        return false;
    }
    
    glAttachShader(shaderProgram_, vertexShader_);
    glAttachShader(shaderProgram_, fragmentShader_);
    
    // Bind attribute locations before linking
    glBindAttribLocation(shaderProgram_, 0, "a_position");
    
    if (!linkShaderProgram()) {
        destroyResources();
        return false;
    }
    
    checkGLError("createShaderProgram");
    return true;
}

// Compile shader
GLuint TriangleRenderer::compileShader(GLenum shaderType, const char* source) {
    GLuint shader = glCreateShader(shaderType);
    if (shader == 0) {
        LOGE("Failed to create shader of type %d", shaderType);
        return 0;
    }
    
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    
    GLint compiled;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        GLint infoLen = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLen);
        if (infoLen > 1) {
            char* infoLog = new char[infoLen];
            glGetShaderInfoLog(shader, infoLen, nullptr, infoLog);
            LOGE("Shader compilation failed: %s", infoLog);
            delete[] infoLog;
        }
        glDeleteShader(shader);
        return 0;
    }
    
    return shader;
}

// Link shader program
bool TriangleRenderer::linkShaderProgram() {
    glLinkProgram(shaderProgram_);
    
    GLint linked;
    glGetProgramiv(shaderProgram_, GL_LINK_STATUS, &linked);
    if (!linked) {
        GLint infoLen = 0;
        glGetProgramiv(shaderProgram_, GL_INFO_LOG_LENGTH, &infoLen);
        if (infoLen > 1) {
            char* infoLog = new char[infoLen];
            glGetProgramInfoLog(shaderProgram_, infoLen, nullptr, infoLog);
            LOGE("Shader program linking failed: %s", infoLog);
            delete[] infoLog;
        }
        return false;
    }
    
    return true;
}

// Create buffers
void TriangleRenderer::createBuffers() {
    // Generate vertex buffer
    glGenBuffers(1, &vertexBuffer_);
    if (vertexBuffer_ == 0) {
        LOGE("Failed to generate vertex buffer");
    }
    
    // Generate index buffer
    glGenBuffers(1, &indexBuffer_);
    if (indexBuffer_ == 0) {
        LOGE("Failed to generate index buffer");
    }
    
    checkGLError("createBuffers");
}

// Destroy OpenGL resources
void TriangleRenderer::destroyResources() {
    if (vertexBuffer_ > 0) {
        glDeleteBuffers(1, &vertexBuffer_);
        vertexBuffer_ = 0;
    }
    
    if (indexBuffer_ > 0) {
        glDeleteBuffers(1, &indexBuffer_);
        indexBuffer_ = 0;
    }
    
    if (vertexArray_ > 0) {
        // Note: VAOs are not supported in OpenGL ES 2.0
        vertexArray_ = 0;
    }
    
    if (shaderProgram_ > 0) {
        glDeleteProgram(shaderProgram_);
        shaderProgram_ = 0;
    }
    
    if (vertexShader_ > 0) {
        glDeleteShader(vertexShader_);
        vertexShader_ = 0;
    }
    
    if (fragmentShader_ > 0) {
        glDeleteShader(fragmentShader_);
        fragmentShader_ = 0;
    }
    
    checkGLError("destroyResources");
}

// Check for OpenGL errors
void TriangleRenderer::checkGLError(const char* operation) {
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        LOGE("OpenGL error in %s: 0x%x", operation, error);
    }
}

// Global renderer instances
static std::vector<std::unique_ptr<TriangleRenderer>> renderers;
static long nextRendererId = 1;

extern "C" {

JNIEXPORT jlong JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_createTriangleRenderer(JNIEnv *env, jobject thiz) {
    try {
        auto renderer = std::make_unique<TriangleRenderer>();
        if (!renderer->initialize()) {
            LOGE("Failed to initialize triangle renderer");
            return 0;
        }
        
        long rendererId = nextRendererId++;
        if (rendererId >= renderers.size()) {
            renderers.resize(rendererId + 1);
        }
        renderers[rendererId] = std::move(renderer);
        
        LOGI("Created triangle renderer with ID: %ld", rendererId);
        return rendererId;
    } catch (const std::exception& e) {
        LOGE("Exception creating triangle renderer: %s", e.what());
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_destroyTriangleRenderer(JNIEnv *env, jobject thiz, jlong rendererId) {
    if (rendererId > 0 && rendererId < renderers.size() && renderers[rendererId]) {
        renderers[rendererId].reset();
        LOGI("Destroyed triangle renderer with ID: %ld", rendererId);
    }
}

JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_updateTriangles(JNIEnv *env, jobject thiz, jlong rendererId, jfloatArray vertices, jint vertexCount, jintArray indices, jint indexCount) {
    if (rendererId <= 0 || rendererId >= renderers.size() || !renderers[rendererId]) {
        LOGE("Invalid renderer ID: %ld", rendererId);
        return;
    }
    
    jfloat* vertexData = env->GetFloatArrayElements(vertices, nullptr);
    jint* indexData = env->GetIntArrayElements(indices, nullptr);
    
    if (vertexData && indexData) {
        // Convert jint to unsigned int for indices
        std::vector<unsigned int> uintIndices(indexCount);
        for (int i = 0; i < indexCount; i++) {
            uintIndices[i] = static_cast<unsigned int>(indexData[i]);
        }
        
        renderers[rendererId]->updateTriangles(vertexData, vertexCount, uintIndices.data(), indexCount);
    }
    
    if (vertexData) {
        env->ReleaseFloatArrayElements(vertices, vertexData, JNI_ABORT);
    }
    if (indexData) {
        env->ReleaseIntArrayElements(indices, indexData, JNI_ABORT);
    }
}

JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_renderTriangles(JNIEnv *env, jobject thiz, jlong rendererId, jfloatArray mvpMatrix) {
    if (rendererId <= 0 || rendererId >= renderers.size() || !renderers[rendererId]) {
        LOGE("Invalid renderer ID: %ld", rendererId);
        return;
    }
    
    jfloat* matrix = env->GetFloatArrayElements(mvpMatrix, nullptr);
    if (matrix) {
        renderers[rendererId]->render(matrix);
        env->ReleaseFloatArrayElements(mvpMatrix, matrix, JNI_ABORT);
    }
}

JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_setColor(JNIEnv *env, jobject thiz, jlong rendererId, jfloat red, jfloat green, jfloat blue, jfloat alpha) {
    if (rendererId <= 0 || rendererId >= renderers.size() || !renderers[rendererId]) {
        LOGE("Invalid renderer ID: %ld", rendererId);
        return;
    }
    
    renderers[rendererId]->setColor(red, green, blue, alpha);
}

JNIEXPORT void JNICALL
Java_org_maplibre_maplibregl_TriangleCustomStyleLayer_setProperties(JNIEnv *env, jobject thiz, jlong rendererId, 
    jfloat size, jfloatArray color, jfloat opacity, jfloatArray translate, jfloat rotation, 
    jfloat blur, jfloat strokeWidth, jfloatArray strokeColor, jfloat strokeOpacity) {
    // Properties are handled per-instance in the triangle data
    // This method exists for compatibility but the actual properties are passed via updateTriangles
    LOGI("Triangle renderer properties set for ID: %ld", rendererId);
}

}
