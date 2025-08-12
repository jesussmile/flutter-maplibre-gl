#ifndef TRIANGLE_RENDERER_H
#define TRIANGLE_RENDERER_H

#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <memory>

/**
 * High-performance OpenGL ES 2.0 triangle renderer for MapLibre.
 * Provides GPU-accelerated triangle rendering with shader-based graphics pipeline.
 */
class TriangleRenderer {
public:
    TriangleRenderer();
    ~TriangleRenderer();
    
    // Core lifecycle methods
    bool initialize();
    void render(const float* mvpMatrix);
    void deinitialize();
    
    // Data management methods  
    void updateTriangles(const float* vertices, int vertexCount, const unsigned int* indices, int indexCount);
    void setColor(float red, float green, float blue, float alpha);
    
    // State query methods
    bool isInitialized() const { return initialized_; }
    int getTriangleCount() const { return triangleCount_; }

private:
    // OpenGL resources
    GLuint shaderProgram_;
    GLuint vertexShader_;
    GLuint fragmentShader_;
    GLuint vertexBuffer_;
    GLuint indexBuffer_;
    GLuint vertexArray_;
    
    // Shader uniform locations
    GLint mvpMatrixLocation_;
    GLint colorLocation_;
    
    // Rendering state
    bool initialized_;
    int vertexCount_;
    int indexCount_;
    int triangleCount_;
    float color_[4]; // RGBA color
    
    // Internal methods
    bool createShaderProgram();
    GLuint compileShader(GLenum shaderType, const char* source);
    bool linkShaderProgram();
    void createBuffers();
    void destroyResources();
    void checkGLError(const char* operation);
    
    // Shader source constants
    static const char* getVertexShaderSource();
    static const char* getFragmentShaderSource();
    
    // Delete copy constructor and assignment operator
    TriangleRenderer(const TriangleRenderer&) = delete;
    TriangleRenderer& operator=(const TriangleRenderer&) = delete;
};

#endif // TRIANGLE_RENDERER_H
