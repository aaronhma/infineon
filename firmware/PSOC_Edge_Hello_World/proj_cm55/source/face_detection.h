/*******************************************************************************
* File Name        : face_detection.h
*
* Description      : Face detection with eye state tracking for PSOC Edge E84
*
********************************************************************************
* Copyright 2024, Infineon Technologies AG
*******************************************************************************/

#ifndef FACE_DETECTION_H
#define FACE_DETECTION_H

#include <stdint.h>
#include <stdbool.h>

/*******************************************************************************
* Macros
*******************************************************************************/

#define MAX_FACES                   (5U)
#define FACE_DETECTION_THRESHOLD    (0.5f)
#define EYE_CLOSED_THRESHOLD        (0.3f)

/* Input image dimensions for the model */
#define FACE_INPUT_WIDTH            (96U)
#define FACE_INPUT_HEIGHT           (96U)

/*******************************************************************************
* Data Types
*******************************************************************************/

/* Bounding box for detected face */
typedef struct {
    int16_t x;          /* Top-left X coordinate */
    int16_t y;          /* Top-left Y coordinate */
    uint16_t width;     /* Width of bounding box */
    uint16_t height;    /* Height of bounding box */
} bbox_t;

/* Eye landmark points */
typedef struct {
    int16_t x;          /* X coordinate of eye center */
    int16_t y;          /* Y coordinate of eye center */
} eye_point_t;

/* Eye state */
typedef enum {
    EYE_OPEN = 0,
    EYE_CLOSED,
    EYE_UNKNOWN
} eye_state_t;

/* Single face detection result */
typedef struct {
    bbox_t bbox;            /* Face bounding box */
    float confidence;       /* Detection confidence (0.0 - 1.0) */
    eye_point_t left_eye;   /* Left eye position */
    eye_point_t right_eye;  /* Right eye position */
    eye_state_t left_eye_state;   /* Left eye open/closed */
    eye_state_t right_eye_state;  /* Right eye open/closed */
    float left_eye_openness;      /* Left eye openness score (0.0 - 1.0) */
    float right_eye_openness;     /* Right eye openness score (0.0 - 1.0) */
    bool valid;             /* True if this face result is valid */
} face_result_t;

/* Complete detection results */
typedef struct {
    face_result_t faces[MAX_FACES];     /* Array of detected faces */
    uint8_t face_count;                  /* Number of faces detected */
    uint32_t inference_time_ms;          /* Time taken for inference */
    uint32_t frame_id;                   /* Frame sequence number */
} detection_result_t;

/* Detection status */
typedef enum {
    DETECTION_OK = 0,
    DETECTION_ERROR_INIT,
    DETECTION_ERROR_MODEL,
    DETECTION_ERROR_INFERENCE,
    DETECTION_ERROR_INVALID_INPUT
} detection_status_t;

/* Detection configuration */
typedef struct {
    float confidence_threshold;     /* Minimum confidence to report face */
    float eye_threshold;            /* Threshold for eye closed detection */
    bool enable_eye_tracking;       /* Enable eye state detection */
    uint16_t input_width;           /* Input image width */
    uint16_t input_height;          /* Input image height */
} detection_config_t;

/*******************************************************************************
* Function Prototypes
*******************************************************************************/

/**
 * @brief Initialize face detection module
 * @param config Detection configuration (NULL for defaults)
 * @return Detection status
 */
detection_status_t face_detection_init(const detection_config_t *config);

/**
 * @brief Deinitialize face detection module
 */
void face_detection_deinit(void);

/**
 * @brief Run face detection on RGB565 image
 * @param image_data Pointer to RGB565 image data
 * @param width Image width
 * @param height Image height
 * @param result Pointer to store detection results
 * @return Detection status
 */
detection_status_t face_detection_run(const uint8_t *image_data,
                                       uint16_t width,
                                       uint16_t height,
                                       detection_result_t *result);

/**
 * @brief Run face detection on grayscale image
 * @param image_data Pointer to grayscale image data
 * @param width Image width
 * @param height Image height
 * @param result Pointer to store detection results
 * @return Detection status
 */
detection_status_t face_detection_run_gray(const uint8_t *image_data,
                                            uint16_t width,
                                            uint16_t height,
                                            detection_result_t *result);

/**
 * @brief Get eye state as string
 * @param state Eye state enum value
 * @return String representation
 */
const char* eye_state_to_string(eye_state_t state);

/**
 * @brief Print detection results to console
 * @param result Detection results to print
 */
void face_detection_print_results(const detection_result_t *result);

/**
 * @brief Convert RGB565 to grayscale
 * @param rgb565 Input RGB565 image
 * @param gray Output grayscale image
 * @param width Image width
 * @param height Image height
 */
void rgb565_to_grayscale(const uint8_t *rgb565,
                          uint8_t *gray,
                          uint16_t width,
                          uint16_t height);

/**
 * @brief Resize grayscale image using bilinear interpolation
 * @param input Input image
 * @param input_width Input width
 * @param input_height Input height
 * @param output Output image
 * @param output_width Output width
 * @param output_height Output height
 */
void resize_image(const uint8_t *input,
                   uint16_t input_width,
                   uint16_t input_height,
                   uint8_t *output,
                   uint16_t output_width,
                   uint16_t output_height);

#endif /* FACE_DETECTION_H */
