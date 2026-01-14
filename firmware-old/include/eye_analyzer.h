/**
 * @file eye_analyzer.h
 * @brief Eye state analysis using Eye Aspect Ratio (EAR) algorithm
 *
 * Infineon PSoC 6 AI Evaluation Kit
 *
 * Implements drowsiness and intoxication detection based on:
 * - Eye Aspect Ratio (EAR) for open/closed detection
 * - Blink pattern analysis
 * - Eye movement stability metrics
 */

#ifndef EYE_ANALYZER_H
#define EYE_ANALYZER_H

#include <stdint.h>
#include <stdbool.h>
#include "face_detector.h"
#include "config.h"

/* Eye state enumeration */
typedef enum {
    EYE_STATE_UNKNOWN = 0,
    EYE_STATE_OPEN,
    EYE_STATE_CLOSED
} eye_state_t;

/* Driver status enumeration */
typedef enum {
    DRIVER_STATUS_UNKNOWN = 0,
    DRIVER_STATUS_ALERT,
    DRIVER_STATUS_DROWSY,
    DRIVER_STATUS_IMPAIRED
} driver_status_t;

/* Intoxication indicators */
typedef struct {
    bool is_drowsy;             /* Eyes closed for extended period */
    bool excessive_blinking;    /* Abnormal blink rate */
    bool unstable_eyes;         /* High EAR variance */
    uint8_t score;              /* Combined risk score (0-6) */
} intoxication_data_t;

/* Eye analysis result */
typedef struct {
    eye_state_t left_eye_state;
    eye_state_t right_eye_state;
    float left_ear;             /* Left Eye Aspect Ratio */
    float right_ear;            /* Right Eye Aspect Ratio */
    float avg_ear;              /* Average EAR */
    intoxication_data_t intox;
    driver_status_t driver_status;
    uint32_t blink_count;       /* Total blinks in history window */
    uint32_t timestamp_ms;
} eye_analysis_result_t;

/**
 * @brief Initialize the eye analyzer
 * @return 0 on success, negative error code on failure
 */
int eye_analyzer_init(void);

/**
 * @brief Reset all tracking state and history
 */
void eye_analyzer_reset(void);

/**
 * @brief Calculate Eye Aspect Ratio for given landmarks
 * @param landmarks Pointer to 6 eye landmark points
 * @return EAR value (typically 0.1-0.4)
 */
float eye_analyzer_calculate_ear(const eye_landmarks_t *landmarks);

/**
 * @brief Analyze eyes from face detection result
 * @param face_result Face detection result with eye landmarks
 * @param analysis Output analysis result
 * @return 0 on success, negative error code on failure
 */
int eye_analyzer_process(const face_detection_result_t *face_result,
                         eye_analysis_result_t *analysis);

/**
 * @brief Get current driver status based on recent analysis
 * @return Current driver status
 */
driver_status_t eye_analyzer_get_driver_status(void);

/**
 * @brief Get current intoxication score
 * @return Score from 0 (normal) to 6 (high risk)
 */
uint8_t eye_analyzer_get_intoxication_score(void);

/**
 * @brief Check if driver alert should be triggered
 * @return true if alert should sound
 */
bool eye_analyzer_should_alert(void);

#endif /* EYE_ANALYZER_H */
