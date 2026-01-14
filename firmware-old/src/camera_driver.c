/**
 * @file camera_driver.c
 * @brief Camera driver stub for Zephyr RTOS
 *
 * Infineon PSoC 6 AI Evaluation Kit
 *
 * TODO: Implement actual camera driver for your sensor
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "camera_driver.h"
#include "config.h"

LOG_MODULE_REGISTER(camera, LOG_LEVEL_INF);

static struct {
    bool initialized;
    uint16_t width;
    uint16_t height;
    uint8_t fps;
} camera_state = {0};

int camera_init(uint16_t width, uint16_t height, uint8_t fps)
{
    if (camera_state.initialized) {
        return 0;
    }

    /*
     * TODO: Initialize actual camera hardware
     *
     * For Zephyr, you would typically:
     * 1. Get the video device: device_get_binding("VIDEO_0")
     * 2. Configure format with video_set_format()
     * 3. Start capture with video_stream_start()
     */

    camera_state.width = width;
    camera_state.height = height;
    camera_state.fps = fps;
    camera_state.initialized = true;

    LOG_INF("Camera initialized: %dx%d @ %d fps (stub)", width, height, fps);
    return 0;
}

void camera_deinit(void)
{
    camera_state.initialized = false;
}

int camera_capture(uint8_t *buffer, uint32_t buffer_size)
{
    if (!camera_state.initialized || !buffer) {
        return -1;
    }

    uint32_t required_size = camera_state.width * camera_state.height * 2;
    if (buffer_size < required_size) {
        return -2;
    }

    /*
     * TODO: Capture actual frame from camera
     *
     * Using Zephyr Video API:
     * struct video_buffer *vbuf;
     * video_dequeue(dev, VIDEO_EP_OUT, &vbuf, K_FOREVER);
     * memcpy(buffer, vbuf->buffer, vbuf->bytesused);
     * video_enqueue(dev, VIDEO_EP_OUT, vbuf);
     */

    /* Generate test pattern for now */
    uint16_t *pixels = (uint16_t *)buffer;
    static uint8_t frame_num = 0;
    frame_num++;

    for (uint16_t y = 0; y < camera_state.height; y++) {
        for (uint16_t x = 0; x < camera_state.width; x++) {
            /* Moving gradient pattern */
            uint8_t r = ((x + frame_num) * 31) / camera_state.width;
            uint8_t g = ((y + frame_num) * 63) / camera_state.height;
            uint8_t b = 15;

            pixels[y * camera_state.width + x] = (r << 11) | (g << 5) | b;
        }
    }

    /* Simulate frame rate delay */
    k_msleep(1000 / camera_state.fps);

    return 0;
}

int camera_start_stream(void (*callback)(uint8_t *frame, uint32_t size))
{
    (void)callback;
    return -ENOTSUP;
}

void camera_stop_stream(void)
{
}

int camera_set_exposure(uint16_t exposure)
{
    (void)exposure;
    return 0;
}

int camera_set_gain(uint8_t gain)
{
    (void)gain;
    return 0;
}
