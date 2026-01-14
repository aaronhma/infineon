/**
 * @file eye_analyzer.c
 * @brief Eye Aspect Ratio (EAR) analysis for Zephyr RTOS
 *
 * Infineon PSoC 6 AI Evaluation Kit
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <string.h>
#include <math.h>

#include "eye_analyzer.h"
#include "config.h"

LOG_MODULE_REGISTER(eye_analyzer, LOG_LEVEL_DBG);

/* Circular buffer for EAR history */
static struct {
    float buffer[EAR_HISTORY_SIZE];
    uint16_t head;
    uint16_t count;
} ear_history = {0};

/* Circular buffer for blink history */
static struct {
    uint8_t buffer[BLINK_HISTORY_SIZE];
    uint16_t head;
    uint16_t count;
} blink_history = {0};

/* Analysis state */
static struct {
    bool initialized;
    uint32_t eye_closed_counter;
    uint32_t total_blinks;
    driver_status_t current_status;
    uint8_t current_intox_score;
} analyzer_state = {0};

static float euclidean_distance(int16_t x1, int16_t y1, int16_t x2, int16_t y2)
{
    float dx = (float)(x2 - x1);
    float dy = (float)(y2 - y1);
    return sqrtf(dx * dx + dy * dy);
}

static void ear_history_push(float value)
{
    ear_history.buffer[ear_history.head] = value;
    ear_history.head = (ear_history.head + 1) % EAR_HISTORY_SIZE;
    if (ear_history.count < EAR_HISTORY_SIZE) {
        ear_history.count++;
    }
}

static float ear_history_variance(void)
{
    if (ear_history.count < 10) {
        return 0.0f;
    }

    float sum = 0.0f;
    for (uint16_t i = 0; i < ear_history.count; i++) {
        sum += ear_history.buffer[i];
    }
    float mean = sum / ear_history.count;

    float var_sum = 0.0f;
    for (uint16_t i = 0; i < ear_history.count; i++) {
        float diff = ear_history.buffer[i] - mean;
        var_sum += diff * diff;
    }

    return var_sum / ear_history.count;
}

static void blink_history_push(uint8_t blink)
{
    blink_history.buffer[blink_history.head] = blink;
    blink_history.head = (blink_history.head + 1) % BLINK_HISTORY_SIZE;
    if (blink_history.count < BLINK_HISTORY_SIZE) {
        blink_history.count++;
    }
}

static uint32_t blink_history_count(void)
{
    uint32_t count = 0;
    for (uint16_t i = 0; i < blink_history.count; i++) {
        count += blink_history.buffer[i];
    }
    return count;
}

int eye_analyzer_init(void)
{
    eye_analyzer_reset();
    analyzer_state.initialized = true;
    LOG_INF("Eye analyzer initialized");
    return 0;
}

void eye_analyzer_reset(void)
{
    memset(&ear_history, 0, sizeof(ear_history));
    memset(&blink_history, 0, sizeof(blink_history));
    analyzer_state.eye_closed_counter = 0;
    analyzer_state.total_blinks = 0;
    analyzer_state.current_status = DRIVER_STATUS_UNKNOWN;
    analyzer_state.current_intox_score = 0;
}

float eye_analyzer_calculate_ear(const eye_landmarks_t *landmarks)
{
    if (!landmarks) {
        return 0.0f;
    }

    /* EAR = (||p2-p6|| + ||p3-p5||) / (2 * ||p1-p4||) */
    float A = euclidean_distance(
        landmarks->landmarks[1][0], landmarks->landmarks[1][1],
        landmarks->landmarks[5][0], landmarks->landmarks[5][1]);

    float B = euclidean_distance(
        landmarks->landmarks[2][0], landmarks->landmarks[2][1],
        landmarks->landmarks[4][0], landmarks->landmarks[4][1]);

    float C = euclidean_distance(
        landmarks->landmarks[0][0], landmarks->landmarks[0][1],
        landmarks->landmarks[3][0], landmarks->landmarks[3][1]);

    if (C < 1.0f) {
        return 0.0f;
    }

    return (A + B) / (2.0f * C);
}

int eye_analyzer_process(const face_detection_result_t *face_result,
                         eye_analysis_result_t *analysis)
{
    if (!analyzer_state.initialized || !face_result || !analysis) {
        return -1;
    }

    memset(analysis, 0, sizeof(eye_analysis_result_t));
    analysis->timestamp_ms = face_result->timestamp_ms;

    if (!face_result->face_detected) {
        analysis->driver_status = DRIVER_STATUS_UNKNOWN;
        return 0;
    }

    /* Calculate EAR */
    analysis->left_ear = eye_analyzer_calculate_ear(&face_result->left_eye);
    analysis->right_ear = eye_analyzer_calculate_ear(&face_result->right_eye);
    analysis->avg_ear = (analysis->left_ear + analysis->right_ear) / 2.0f;

    /* Determine eye states */
    analysis->left_eye_state = (analysis->left_ear < EAR_THRESHOLD)
                                   ? EYE_STATE_CLOSED : EYE_STATE_OPEN;
    analysis->right_eye_state = (analysis->right_ear < EAR_THRESHOLD)
                                    ? EYE_STATE_CLOSED : EYE_STATE_OPEN;

    /* Track history */
    ear_history_push(analysis->avg_ear);

    /* Track blinks */
    if (analysis->avg_ear < EAR_THRESHOLD) {
        analyzer_state.eye_closed_counter++;
    } else {
        if (analyzer_state.eye_closed_counter > 2) {
            analyzer_state.total_blinks++;
            blink_history_push(1);
        } else {
            blink_history_push(0);
        }
        analyzer_state.eye_closed_counter = 0;
    }

    /* Intoxication indicators */
    analysis->intox.is_drowsy =
        (analyzer_state.eye_closed_counter >= DROWSINESS_FRAME_THRESHOLD);

    analysis->blink_count = blink_history_count();
    analysis->intox.excessive_blinking =
        (analysis->blink_count > BLINK_COUNT_THRESHOLD);

    float variance = ear_history_variance();
    analysis->intox.unstable_eyes = (variance > EAR_VARIANCE_THRESHOLD);

    /* Calculate score */
    analysis->intox.score = 0;
    if (analysis->intox.is_drowsy) {
        analysis->intox.score += INTOX_SCORE_DROWSY;
    }
    if (analysis->intox.excessive_blinking) {
        analysis->intox.score += INTOX_SCORE_BLINK;
    }
    if (analysis->intox.unstable_eyes) {
        analysis->intox.score += INTOX_SCORE_UNSTABLE;
    }

    /* Determine status */
    if (analysis->intox.score >= INTOX_HIGH_RISK_THRESHOLD) {
        analysis->driver_status = DRIVER_STATUS_IMPAIRED;
    } else if (analysis->intox.score >= INTOX_MODERATE_THRESHOLD) {
        analysis->driver_status = DRIVER_STATUS_DROWSY;
    } else {
        analysis->driver_status = DRIVER_STATUS_ALERT;
    }

    analyzer_state.current_status = analysis->driver_status;
    analyzer_state.current_intox_score = analysis->intox.score;

    return 0;
}

driver_status_t eye_analyzer_get_driver_status(void)
{
    return analyzer_state.current_status;
}

uint8_t eye_analyzer_get_intoxication_score(void)
{
    return analyzer_state.current_intox_score;
}

bool eye_analyzer_should_alert(void)
{
    return analyzer_state.current_intox_score >= INTOX_HIGH_RISK_THRESHOLD;
}
