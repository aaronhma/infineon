/**
 * @file camera_driver.h
 * @brief Camera interface for PSoC 6 AI Evaluation Kit
 *
 * Infineon PSoC 6 AI Evaluation Kit
 *
 * Supports image sensors connected via the camera interface.
 */

#ifndef CAMERA_DRIVER_H
#define CAMERA_DRIVER_H

#include <stdint.h>

/* Camera pixel formats */
typedef enum {
    CAMERA_FORMAT_RGB565 = 0,
    CAMERA_FORMAT_RGB888,
    CAMERA_FORMAT_GRAYSCALE
} camera_format_t;

/**
 * @brief Initialize camera hardware
 * @param width Capture width in pixels
 * @param height Capture height in pixels
 * @param fps Target frame rate
 * @return 0 on success, negative error code on failure
 */
int camera_init(uint16_t width, uint16_t height, uint8_t fps);

/**
 * @brief Deinitialize camera and release resources
 */
void camera_deinit(void);

/**
 * @brief Capture a single frame
 * @param buffer Destination buffer for frame data
 * @param buffer_size Size of destination buffer
 * @return 0 on success, negative error code on failure
 */
int camera_capture(uint8_t *buffer, uint32_t buffer_size);

/**
 * @brief Start continuous capture mode
 * @param callback Function called when frame is ready
 * @return 0 on success, negative error code on failure
 */
int camera_start_stream(void (*callback)(uint8_t *frame, uint32_t size));

/**
 * @brief Stop continuous capture mode
 */
void camera_stop_stream(void);

/**
 * @brief Set camera exposure
 * @param exposure Exposure value (platform specific)
 * @return 0 on success, negative error code on failure
 */
int camera_set_exposure(uint16_t exposure);

/**
 * @brief Set camera gain
 * @param gain Gain value (platform specific)
 * @return 0 on success, negative error code on failure
 */
int camera_set_gain(uint8_t gain);

#endif /* CAMERA_DRIVER_H */
