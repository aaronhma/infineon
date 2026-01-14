/**
 * @file config.h
 * @brief Configuration settings for Face Detection Firmware
 *
 * Infineon PSoC 6 AI Evaluation Kit - Zephyr RTOS
 */

#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>

/* Camera Configuration - reduced for RAM constraints */
#define CAMERA_WIDTH        96
#define CAMERA_HEIGHT       96
#define CAMERA_FPS          15
#define CAMERA_FORMAT       0  /* RGB565 */

/* AI Model Configuration */
#define MODEL_INPUT_WIDTH   96
#define MODEL_INPUT_HEIGHT  96
#define MODEL_INPUT_CHANNELS 3

/* Face Detection Thresholds */
#define FACE_DETECTION_CONFIDENCE   0.5f
#define FACE_PRESENCE_CONFIDENCE    0.5f
#define FACE_TRACKING_CONFIDENCE    0.5f
#define MAX_FACES                   1

/* Eye Aspect Ratio (EAR) Configuration */
#define EAR_THRESHOLD               0.21f
#define DROWSINESS_FRAME_THRESHOLD  20
#define BLINK_COUNT_THRESHOLD       15
#define EAR_VARIANCE_THRESHOLD      0.005f
#define EAR_HISTORY_SIZE            20
#define BLINK_HISTORY_SIZE          30

/* Intoxication Score Thresholds */
#define INTOX_SCORE_DROWSY          3
#define INTOX_SCORE_BLINK           2
#define INTOX_SCORE_UNSTABLE        1
#define INTOX_HIGH_RISK_THRESHOLD   4
#define INTOX_MODERATE_THRESHOLD    2

/* Alert Configuration */
#define ALERT_COOLDOWN_MS           3000
#define SPEEDING_BEEP_FREQ_HZ       900
#define DROWSY_BEEP_FREQ_HZ         1200
#define BEEP_DURATION_MS            300

/* Buffer Sizes */
#define FRAME_BUFFER_SIZE           (CAMERA_WIDTH * CAMERA_HEIGHT * 2)

#endif /* CONFIG_H */
