/**
 * @file alert_system.h
 * @brief Audio and visual alert system for driver warnings
 *
 * Infineon PSoC 6 AI Evaluation Kit
 */

#ifndef ALERT_SYSTEM_H
#define ALERT_SYSTEM_H

#include <stdint.h>
#include <stdbool.h>
#include "config.h"

/* Alert types */
typedef enum {
    ALERT_TYPE_NONE = 0,
    ALERT_TYPE_SPEEDING,        /* Single beep */
    ALERT_TYPE_DROWSY,          /* Double urgent beep */
    ALERT_TYPE_IMPAIRED,        /* Continuous alert */
    ALERT_TYPE_FACE_NOT_FOUND   /* Periodic reminder */
} alert_type_t;

/* LED status indicators */
typedef enum {
    LED_STATUS_OFF = 0,
    LED_STATUS_GREEN,           /* Alert driver */
    LED_STATUS_ORANGE,          /* Drowsy/moderate risk */
    LED_STATUS_RED,             /* Impaired/high risk */
    LED_STATUS_BLINKING_RED     /* Critical alert */
} led_status_t;

/**
 * @brief Initialize the alert system (buzzer, LEDs)
 * @return 0 on success, negative error code on failure
 */
int alert_system_init(void);

/**
 * @brief Deinitialize alert system
 */
void alert_system_deinit(void);

/**
 * @brief Trigger an alert
 * @param type Type of alert to trigger
 */
void alert_system_trigger(alert_type_t type);

/**
 * @brief Update LED status indicator
 * @param status LED status to display
 */
void alert_system_set_led(led_status_t status);

/**
 * @brief Play a beep tone
 * @param frequency_hz Tone frequency in Hz
 * @param duration_ms Duration in milliseconds
 */
void alert_system_beep(uint16_t frequency_hz, uint16_t duration_ms);

/**
 * @brief Stop any currently playing alert
 */
void alert_system_stop(void);

/**
 * @brief Check if alert cooldown has elapsed
 * @param type Alert type to check
 * @return true if alert can be played
 */
bool alert_system_cooldown_elapsed(alert_type_t type);

/**
 * @brief Process alert system (call from main loop)
 * @param current_time_ms Current timestamp in milliseconds
 */
void alert_system_process(uint32_t current_time_ms);

#endif /* ALERT_SYSTEM_H */
