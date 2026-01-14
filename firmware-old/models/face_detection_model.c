/**
 * @file face_detection_model.c
 * @brief TensorFlow Lite Micro model data placeholder
 *
 * This file should contain the converted face detection model
 * as a C array. Use the xxd tool or TFLite conversion script
 * to generate the actual model data.
 *
 * To generate from a TFLite model:
 *   xxd -i face_detection.tflite > face_detection_model.c
 *
 * Or use the Python converter:
 *   python3 scripts/convert_model.py model.tflite face_detection_model.c
 */

#include <stdint.h>

/**
 * Placeholder model data
 *
 * Replace this with actual model data converted from:
 * - MediaPipe Face Detection model (BlazeFace)
 * - Or a custom trained face detection model
 *
 * Model requirements:
 * - Input: 96x96x3 RGB image (int8 quantized)
 * - Output: Face bounding boxes + landmarks
 * - Size: Should fit within tensor arena (128KB default)
 */

/* Model data array - replace with actual model */
const unsigned char face_detection_model[] __attribute__((aligned(4))) = {
    /* TFLite FlatBuffer header (placeholder) */
    0x20, 0x00, 0x00, 0x00,  /* Offset to root table */
    0x54, 0x46, 0x4C, 0x33,  /* "TFL3" magic */

    /*
     * IMPORTANT: This is a placeholder!
     *
     * To get the actual model:
     *
     * 1. Download MediaPipe face detection model:
     *    curl -L -o face_detection.tflite \
     *      "https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite"
     *
     * 2. Quantize for int8 (optional, for better MCU performance):
     *    python3 -c "
     *    import tensorflow as tf
     *    converter = tf.lite.TFLiteConverter.from_saved_model('model')
     *    converter.optimizations = [tf.lite.Optimize.DEFAULT]
     *    converter.target_spec.supported_types = [tf.int8]
     *    tflite_model = converter.convert()
     *    open('face_detection_int8.tflite', 'wb').write(tflite_model)
     *    "
     *
     * 3. Convert to C array:
     *    xxd -i face_detection_int8.tflite > face_detection_model.c
     *
     * 4. Update the array name to match this file
     */

    /* Minimal valid TFLite header for compilation */
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

/* Model size in bytes */
const unsigned int face_detection_model_len = sizeof(face_detection_model);

/*
 * Expected model specifications after proper conversion:
 *
 * Input Tensor:
 *   - Name: "input"
 *   - Shape: [1, 96, 96, 3]
 *   - Type: INT8 or FLOAT32
 *   - Quantization: scale=0.0078125, zero_point=128
 *
 * Output Tensors:
 *   - Face detection scores: [1, N] confidence scores
 *   - Face bounding boxes: [1, N, 4] in YXYX format
 *   - Landmarks (optional): [1, N, 6, 2] for 6 key points
 *
 * Where N is the maximum number of detected faces
 */
