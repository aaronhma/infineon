/**
 * @file face_detector.h
 * @brief Face detection and landmark extraction for driver monitoring
 *
 * Infineon PSoC 6 AI Evaluation Kit
 */

#ifndef FACE_DETECTOR_H
#define FACE_DETECTOR_H

#include <stdint.h>
#include <stdbool.h>
#include "config.h"

/* Face bounding box structure */
typedef struct {
    int16_t x_min;
    int16_t y_min;
    int16_t x_max;
    int16_t y_max;
    float confidence;
} face_bbox_t;

/* Eye landmark indices (MediaPipe compatible) */
typedef struct {
    int16_t landmarks[6][2];  /* 6 points per eye: [index][x,y] */
} eye_landmarks_t;

/* Face detection result */
typedef struct {
    bool face_detected;
    face_bbox_t bbox;
    eye_landmarks_t left_eye;
    eye_landmarks_t right_eye;
    uint32_t timestamp_ms;
} face_detection_result_t;

/**
 * @brief Initialize the face detector with TFLite Micro model
 * @return 0 on success, negative error code on failure
 */
int face_detector_init(void);

/**
 * @brief Deinitialize the face detector and free resources
 */
void face_detector_deinit(void);

/**
 * @brief Run face detection on an input frame
 * @param frame_data Pointer to RGB565 frame buffer
 * @param width Frame width
 * @param height Frame height
 * @param result Pointer to store detection result
 * @return 0 on success, negative error code on failure
 */
int face_detector_process(const uint8_t *frame_data,
                          uint16_t width,
                          uint16_t height,
                          face_detection_result_t *result);

/**
 * @brief Get the model inference time in milliseconds
 * @return Last inference time in ms
 */
uint32_t face_detector_get_inference_time(void);

/**
 * @brief Check if model is loaded and ready
 * @return true if ready, false otherwise
 */
bool face_detector_is_ready(void);

#endif /* FACE_DETECTOR_H */
