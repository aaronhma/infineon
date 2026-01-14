/**
 * @file face_detector.c
 * @brief Face detection stub for Zephyr RTOS
 *
 * Infineon PSoC 6 AI Evaluation Kit
 *
 * TODO: Integrate TensorFlow Lite Micro when model is ready
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <string.h>

#include "face_detector.h"
#include "config.h"

LOG_MODULE_REGISTER(face_detector, LOG_LEVEL_INF);

static struct {
    bool initialized;
    uint32_t last_inference_time_ms;
    uint32_t frame_count;
} detector_state = {0};

int face_detector_init(void)
{
    if (detector_state.initialized) {
        return 0;
    }

    /*
     * TODO: Initialize TensorFlow Lite Micro
     *
     * 1. Load model from face_detection_model[]
     * 2. Create interpreter with MicroMutableOpResolver
     * 3. Allocate tensors
     *
     * Requires:
     * - CONFIG_TENSORFLOW_LITE_MICRO=y in prj.conf
     * - Converted face detection model
     */

    detector_state.initialized = true;
    LOG_INF("Face detector initialized (stub mode)");
    return 0;
}

void face_detector_deinit(void)
{
    detector_state.initialized = false;
}

int face_detector_process(const uint8_t *frame_data,
                          uint16_t width,
                          uint16_t height,
                          face_detection_result_t *result)
{
    if (!detector_state.initialized || !frame_data || !result) {
        return -1;
    }

    uint32_t start_time = k_uptime_get_32();

    memset(result, 0, sizeof(face_detection_result_t));
    result->timestamp_ms = start_time;

    detector_state.frame_count++;

    /*
     * TODO: Run actual TFLite inference
     *
     * 1. Preprocess image (resize, normalize)
     * 2. Copy to input tensor
     * 3. Invoke interpreter
     * 4. Parse output tensors for bounding boxes and landmarks
     */

    /* Stub: Simulate face detection every few frames */
    if ((detector_state.frame_count % 3) != 0) {
        result->face_detected = true;

        /* Simulated face in center of frame */
        result->bbox.x_min = width / 4;
        result->bbox.y_min = height / 4;
        result->bbox.x_max = 3 * width / 4;
        result->bbox.y_max = 3 * height / 4;
        result->bbox.confidence = 0.95f;

        /* Simulated eye landmarks */
        int16_t face_cx = (result->bbox.x_min + result->bbox.x_max) / 2;
        int16_t face_cy = (result->bbox.y_min + result->bbox.y_max) / 2;
        int16_t eye_offset = (result->bbox.x_max - result->bbox.x_min) / 4;

        /* Left eye (6 landmarks) */
        result->left_eye.landmarks[0][0] = face_cx - eye_offset - 10;
        result->left_eye.landmarks[0][1] = face_cy - 20;
        result->left_eye.landmarks[1][0] = face_cx - eye_offset - 5;
        result->left_eye.landmarks[1][1] = face_cy - 25;
        result->left_eye.landmarks[2][0] = face_cx - eye_offset + 5;
        result->left_eye.landmarks[2][1] = face_cy - 25;
        result->left_eye.landmarks[3][0] = face_cx - eye_offset + 10;
        result->left_eye.landmarks[3][1] = face_cy - 20;
        result->left_eye.landmarks[4][0] = face_cx - eye_offset + 5;
        result->left_eye.landmarks[4][1] = face_cy - 15;
        result->left_eye.landmarks[5][0] = face_cx - eye_offset - 5;
        result->left_eye.landmarks[5][1] = face_cy - 15;

        /* Right eye (6 landmarks) */
        result->right_eye.landmarks[0][0] = face_cx + eye_offset - 10;
        result->right_eye.landmarks[0][1] = face_cy - 20;
        result->right_eye.landmarks[1][0] = face_cx + eye_offset - 5;
        result->right_eye.landmarks[1][1] = face_cy - 25;
        result->right_eye.landmarks[2][0] = face_cx + eye_offset + 5;
        result->right_eye.landmarks[2][1] = face_cy - 25;
        result->right_eye.landmarks[3][0] = face_cx + eye_offset + 10;
        result->right_eye.landmarks[3][1] = face_cy - 20;
        result->right_eye.landmarks[4][0] = face_cx + eye_offset + 5;
        result->right_eye.landmarks[4][1] = face_cy - 15;
        result->right_eye.landmarks[5][0] = face_cx + eye_offset - 5;
        result->right_eye.landmarks[5][1] = face_cy - 15;
    }

    detector_state.last_inference_time_ms = k_uptime_get_32() - start_time;

    return 0;
}

uint32_t face_detector_get_inference_time(void)
{
    return detector_state.last_inference_time_ms;
}

bool face_detector_is_ready(void)
{
    return detector_state.initialized;
}
