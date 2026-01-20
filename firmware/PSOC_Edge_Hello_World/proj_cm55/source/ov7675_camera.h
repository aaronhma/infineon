/*******************************************************************************
* File Name        : ov7675_camera.h
*
* Description      : OV7675 DVP Camera driver for PSOC Edge E84 AI Kit
*
********************************************************************************
* Copyright 2024, Infineon Technologies AG
*******************************************************************************/

#ifndef OV7675_CAMERA_H
#define OV7675_CAMERA_H

#include "cybsp.h"
#include "cy_scb_i2c.h"
#include <stdint.h>
#include <stdbool.h>

/*******************************************************************************
* Macros
*******************************************************************************/

/* OV7675 I2C Address (7-bit) */
#define OV7675_I2C_ADDR             (0x21U)

/* Image dimensions */
#define CAMERA_WIDTH                (320U)
#define CAMERA_HEIGHT               (240U)
#define CAMERA_BYTES_PER_PIXEL      (2U)  /* RGB565 */
#define CAMERA_FRAME_SIZE           (CAMERA_WIDTH * CAMERA_HEIGHT * CAMERA_BYTES_PER_PIXEL)

/* OV7675 Register Addresses */
#define OV7675_REG_GAIN             (0x00U)
#define OV7675_REG_BLUE             (0x01U)
#define OV7675_REG_RED              (0x02U)
#define OV7675_REG_VREF             (0x03U)
#define OV7675_REG_COM1             (0x04U)
#define OV7675_REG_BAVE             (0x05U)
#define OV7675_REG_GbAVE            (0x06U)
#define OV7675_REG_AECHH            (0x07U)
#define OV7675_REG_RAVE             (0x08U)
#define OV7675_REG_COM2             (0x09U)
#define OV7675_REG_PID              (0x0AU)
#define OV7675_REG_VER              (0x0BU)
#define OV7675_REG_COM3             (0x0CU)
#define OV7675_REG_COM4             (0x0DU)
#define OV7675_REG_COM5             (0x0EU)
#define OV7675_REG_COM6             (0x0FU)
#define OV7675_REG_AECH             (0x10U)
#define OV7675_REG_CLKRC            (0x11U)
#define OV7675_REG_COM7             (0x12U)
#define OV7675_REG_COM8             (0x13U)
#define OV7675_REG_COM9             (0x14U)
#define OV7675_REG_COM10            (0x15U)
#define OV7675_REG_HSTART           (0x17U)
#define OV7675_REG_HSTOP            (0x18U)
#define OV7675_REG_VSTART           (0x19U)
#define OV7675_REG_VSTOP            (0x1AU)
#define OV7675_REG_HREF             (0x32U)
#define OV7675_REG_PSHFT            (0x1BU)
#define OV7675_REG_MIDH             (0x1CU)
#define OV7675_REG_MIDL             (0x1DU)
#define OV7675_REG_MVFP             (0x1EU)
#define OV7675_REG_LAEC             (0x1FU)
#define OV7675_REG_TSLB             (0x3AU)
#define OV7675_REG_COM11            (0x3BU)
#define OV7675_REG_COM12            (0x3CU)
#define OV7675_REG_COM13            (0x3DU)
#define OV7675_REG_COM14            (0x3EU)
#define OV7675_REG_EDGE             (0x3FU)
#define OV7675_REG_COM15            (0x40U)
#define OV7675_REG_COM16            (0x41U)
#define OV7675_REG_COM17            (0x42U)

/* Expected Product ID */
#define OV7675_PRODUCT_ID_H         (0x76U)
#define OV7675_PRODUCT_ID_L         (0x73U)

/*******************************************************************************
* Data Types
*******************************************************************************/

/* Camera status */
typedef enum {
    CAMERA_OK = 0,
    CAMERA_ERROR_INIT,
    CAMERA_ERROR_I2C,
    CAMERA_ERROR_NOT_FOUND,
    CAMERA_ERROR_CAPTURE,
    CAMERA_ERROR_TIMEOUT
} camera_status_t;

/* Camera configuration */
typedef struct {
    uint16_t width;
    uint16_t height;
    bool mirror_h;
    bool mirror_v;
} camera_config_t;

/* Frame buffer */
typedef struct {
    uint8_t *data;
    uint32_t size;
    uint16_t width;
    uint16_t height;
    bool ready;
} camera_frame_t;

/*******************************************************************************
* Function Prototypes
*******************************************************************************/

/**
 * @brief Initialize the OV7675 camera
 * @param config Camera configuration
 * @return Camera status
 */
camera_status_t camera_init(const camera_config_t *config);

/**
 * @brief Deinitialize the camera
 */
void camera_deinit(void);

/**
 * @brief Capture a single frame
 * @param frame Pointer to frame buffer structure
 * @return Camera status
 */
camera_status_t camera_capture_frame(camera_frame_t *frame);

/**
 * @brief Start continuous capture mode
 * @return Camera status
 */
camera_status_t camera_start_continuous(void);

/**
 * @brief Stop continuous capture mode
 */
void camera_stop_continuous(void);

/**
 * @brief Check if a new frame is available
 * @return true if frame available
 */
bool camera_frame_available(void);

/**
 * @brief Get the latest captured frame
 * @param frame Pointer to frame buffer structure
 * @return Camera status
 */
camera_status_t camera_get_frame(camera_frame_t *frame);

/**
 * @brief Set camera power state
 * @param power_on true to power on, false to power down
 */
void camera_set_power(bool power_on);

/**
 * @brief Reset the camera
 */
void camera_reset(void);

/**
 * @brief Read camera product ID
 * @param pid_h Pointer to store high byte
 * @param pid_l Pointer to store low byte
 * @return Camera status
 */
camera_status_t camera_read_id(uint8_t *pid_h, uint8_t *pid_l);

#endif /* OV7675_CAMERA_H */
