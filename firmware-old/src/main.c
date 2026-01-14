/**
 * @file main.c
 * @brief Main application for Driver Monitoring System
 *
 * Infineon PSoC 6 AI Evaluation Kit - Zephyr RTOS
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>

#include "config.h"
#include "face_detector.h"
#include "eye_analyzer.h"
#include "alert_system.h"
#include "camera_driver.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

/* Frame buffer */
static uint8_t frame_buffer[FRAME_BUFFER_SIZE];

/* Statistics */
static struct {
    uint32_t frame_count;
    uint32_t faces_detected;
    uint32_t alerts_triggered;
} stats = {0};

/**
 * @brief Handle alerts based on driver status
 */
static void handle_alerts(const eye_analysis_result_t *analysis)
{
    switch (analysis->driver_status) {
    case DRIVER_STATUS_ALERT:
        alert_system_set_led(LED_STATUS_GREEN);
        break;

    case DRIVER_STATUS_DROWSY:
        if (alert_system_cooldown_elapsed(ALERT_TYPE_DROWSY)) {
            alert_system_trigger(ALERT_TYPE_DROWSY);
            stats.alerts_triggered++;
        }
        break;

    case DRIVER_STATUS_IMPAIRED:
        if (alert_system_cooldown_elapsed(ALERT_TYPE_IMPAIRED)) {
            alert_system_trigger(ALERT_TYPE_IMPAIRED);
            stats.alerts_triggered++;
        }
        break;

    case DRIVER_STATUS_UNKNOWN:
    default:
        alert_system_set_led(LED_STATUS_OFF);
        break;
    }
}

int main(void)
{
    int ret;
    face_detection_result_t face_result;
    eye_analysis_result_t eye_analysis;

    LOG_INF("==========================================");
    LOG_INF("  Infineon PSoC 6 AI Evaluation Kit");
    LOG_INF("  Driver Monitoring System v1.0");
    LOG_INF("  Running on Zephyr RTOS");
    LOG_INF("==========================================");

    /* Initialize subsystems */
    LOG_INF("Initializing camera...");
    ret = camera_init(CAMERA_WIDTH, CAMERA_HEIGHT, CAMERA_FPS);
    if (ret != 0) {
        LOG_ERR("Camera init failed: %d", ret);
        return ret;
    }

    LOG_INF("Initializing face detector...");
    ret = face_detector_init();
    if (ret != 0) {
        LOG_ERR("Face detector init failed: %d", ret);
        return ret;
    }

    LOG_INF("Initializing eye analyzer...");
    ret = eye_analyzer_init();
    if (ret != 0) {
        LOG_ERR("Eye analyzer init failed: %d", ret);
        return ret;
    }

    LOG_INF("Initializing alert system...");
    ret = alert_system_init();
    if (ret != 0) {
        LOG_ERR("Alert system init failed: %d", ret);
        return ret;
    }

    LOG_INF("System ready. Starting monitoring...");
    alert_system_set_led(LED_STATUS_GREEN);

    /* Main loop */
    while (1) {
        /* Capture frame from camera */
        ret = camera_capture(frame_buffer, sizeof(frame_buffer));
        if (ret != 0) {
            k_msleep(10);
            continue;
        }

        /* Run face detection */
        ret = face_detector_process(frame_buffer,
                                    CAMERA_WIDTH, CAMERA_HEIGHT,
                                    &face_result);
        if (ret != 0) {
            continue;
        }

        stats.frame_count++;
        if (face_result.face_detected) {
            stats.faces_detected++;
        }

        /* Analyze eyes */
        ret = eye_analyzer_process(&face_result, &eye_analysis);
        if (ret != 0) {
            continue;
        }

        /* Handle alerts */
        handle_alerts(&eye_analysis);

        /* Process alert system */
        alert_system_process(k_uptime_get_32());

        /* Print status periodically */
        if ((stats.frame_count % CAMERA_FPS) == 0) {
            if (eye_analysis.driver_status != DRIVER_STATUS_UNKNOWN) {
                LOG_INF("EAR: %.3f | Status: %s | Score: %d",
                        (double)eye_analysis.avg_ear,
                        eye_analysis.driver_status == DRIVER_STATUS_ALERT ? "ALERT" :
                        eye_analysis.driver_status == DRIVER_STATUS_DROWSY ? "DROWSY" : "IMPAIRED",
                        eye_analysis.intox.score);
            }
        }

        /* Yield to other threads */
        k_yield();
    }

    return 0;
}
