/*******************************************************************************
* File Name        : main.c
*
* Description      : This source file contains the main routine for CM55 CPU
*                    Implements face detection with eye state tracking using
*                    the OV7675 camera module.
*
* Related Document : See README.md
*
********************************************************************************
* Copyright 2023-2025, Cypress Semiconductor Corporation (an Infineon company) or
* an affiliate of Cypress Semiconductor Corporation.  All rights reserved.
*
* This software, including source code, documentation and related
* materials ("Software") is owned by Cypress Semiconductor Corporation
* or one of its affiliates ("Cypress") and is protected by and subject to
* worldwide patent protection (United States and foreign),
* United States copyright laws and international treaty provisions.
* Therefore, you may use this Software only as provided in the license
* agreement accompanying the software package from which you
* obtained this Software ("EULA").
* If no EULA applies, Cypress hereby grants you a personal, non-exclusive,
* non-transferable license to copy, modify, and compile the Software
* source code solely for use in connection with Cypress's
* integrated circuit products.  Any reproduction, modification, translation,
* compilation, or representation of this Software except as specified
* above is prohibited without the express written permission of Cypress.
*
* Disclaimer: THIS SOFTWARE IS PROVIDED AS-IS, WITH NO WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, NONINFRINGEMENT, IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. Cypress
* reserves the right to make changes to the Software without notice. Cypress
* does not assume any liability arising out of the application or use of the
* Software or any product or circuit described in the Software. Cypress does
* not authorize its products for use in any products where a malfunction or
* failure of the Cypress product may reasonably be expected to result in
* significant property damage, injury or death ("High Risk Product"). By
* including Cypress's product in a High Risk Product, the manufacturer
* of such system or application assumes all risk of such use and in doing
* so agrees to indemnify Cypress against all liability.
*******************************************************************************/

/*******************************************************************************
* Header Files
*******************************************************************************/

#include "cybsp.h"
#include "cy_syslib.h"
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "retarget_io_init.h"
#include "source/ov7675_camera.h"
#include "source/face_detection.h"

/*******************************************************************************
* Macros
*******************************************************************************/

/* Detection loop delay in milliseconds */
#define DETECTION_LOOP_DELAY_MS     (500U)

/* Maximum consecutive camera errors before reset */
#define MAX_CAMERA_ERRORS           (3U)


/*******************************************************************************
* Global Variables
*******************************************************************************/

/* Camera frame buffer */
static camera_frame_t frame;

/* Detection results */
static detection_result_t detection_result;

/*******************************************************************************
* Function Prototypes
*******************************************************************************/

static void run_face_detection_loop(void);
static void print_startup_message(void);

/*******************************************************************************
* Function Name: main
********************************************************************************
* Summary:
* This is the main function for CM55 application.
*
* Initializes the camera and face detection modules, then runs continuous
* face detection with eye state tracking, printing results to the console.
*
* Parameters:
*  void
*
* Return:
*  int
*
*******************************************************************************/
int main(void)
{
    cy_rslt_t result;

    /* Initialize the device and board peripherals. */
    result = cybsp_init();

    /* Board init failed. Stop program execution. */
    if (CY_RSLT_SUCCESS != result)
    {
        /* Disable all interrupts. */
        __disable_irq();
        CY_ASSERT(0);
        while(true);
    }

    /* Enable global interrupts. */
    __enable_irq();

    /* Initialize retarget-io for printf support */
    init_retarget_io_cm55();

    /* Print startup message */
    print_startup_message();

    /* Initialize camera */
    camera_config_t cam_config = {
        .width = CAMERA_WIDTH,
        .height = CAMERA_HEIGHT,
        .mirror_h = false,
        .mirror_v = false
    };

    printf("Initializing OV7675 camera...\r\n");
    camera_status_t cam_status = camera_init(&cam_config);

    if (cam_status != CAMERA_OK)
    {
        printf("ERROR: Camera not found!\r\n");
        printf("Error code: %d (0=OK, 1=INIT, 2=I2C, 3=NOT_FOUND, 4=CAPTURE, 5=TIMEOUT)\r\n", cam_status);
        printf("Please connect OV7675 camera module to J14 header.\r\n");
        printf("\r\nSystem halted.\r\n");

        /* Halt - blink LED to indicate error */
        while (true)
        {
            Cy_GPIO_Inv(CYBSP_USER_LED2_PORT, CYBSP_USER_LED2_PIN);
            Cy_SysLib_Delay(200);
        }
    }

    uint8_t pid_h, pid_l;
    camera_read_id(&pid_h, &pid_l);
    printf("Camera initialized successfully!\r\n");
    printf("Camera ID: 0x%02X%02X\r\n\r\n", pid_h, pid_l);

    /* Initialize face detection */
    detection_config_t det_config = {
        .confidence_threshold = 0.4f,
        .eye_threshold = 0.35f,
        .enable_eye_tracking = true,
        .input_width = FACE_INPUT_WIDTH,
        .input_height = FACE_INPUT_HEIGHT
    };

    printf("Initializing face detection module...\r\n");
    detection_status_t det_status = face_detection_init(&det_config);

    if (det_status != DETECTION_OK)
    {
        printf("Face detection initialization failed! Error: %d\r\n", det_status);
        /* Continue anyway - we can still try to process frames */
    }
    else
    {
        printf("Face detection initialized successfully!\r\n\r\n");
    }

    printf("Starting face detection loop...\r\n");
    printf("============================================\r\n\r\n");

    /* Run the main detection loop */
    run_face_detection_loop();

    /* Should never reach here */
    return 0;
}

/*******************************************************************************
* Function Name: run_face_detection_loop
********************************************************************************
* Summary:
* Main detection loop that continuously captures frames and runs face detection.
*
*******************************************************************************/
static void run_face_detection_loop(void)
{
    uint32_t frame_count = 0;
    uint32_t error_count = 0;
    camera_status_t cam_status;
    detection_status_t det_status;

    while (true)
    {
        frame_count++;

        /* Capture a frame from the camera */
        cam_status = camera_capture_frame(&frame);

        if (cam_status != CAMERA_OK)
        {
            error_count++;

            if (error_count >= MAX_CAMERA_ERRORS)
            {
                printf("Too many camera errors. Resetting camera...\r\n");
                camera_reset();
                Cy_SysLib_Delay(100);
                error_count = 0;
            }

            Cy_SysLib_Delay(DETECTION_LOOP_DELAY_MS);
            continue;
        }

        error_count = 0;

        /* Run face detection on the captured frame */
        det_status = face_detection_run(frame.data,
                                         frame.width,
                                         frame.height,
                                         &detection_result);

        if (det_status != DETECTION_OK)
        {
            printf("Frame %lu: Detection error %d\r\n",
                   (unsigned long)frame_count, det_status);
            Cy_SysLib_Delay(DETECTION_LOOP_DELAY_MS);
            continue;
        }

        /* Print detection results */
        face_detection_print_results(&detection_result);

        /* Print summary line for quick monitoring */
        printf("Frame %lu: %u face(s) detected",
               (unsigned long)frame_count,
               detection_result.face_count);

        if (detection_result.face_count > 0)
        {
            printf(" | ");
            for (uint8_t i = 0; i < detection_result.face_count; i++)
            {
                const face_result_t *face = &detection_result.faces[i];
                if (face->valid)
                {
                    printf("Face%u@(%d,%d) L:%s R:%s ",
                           i + 1,
                           face->bbox.x,
                           face->bbox.y,
                           eye_state_to_string(face->left_eye_state),
                           eye_state_to_string(face->right_eye_state));
                }
            }
        }
        printf("\r\n");

        /* Delay before next frame */
        Cy_SysLib_Delay(DETECTION_LOOP_DELAY_MS);
    }
}

/*******************************************************************************
* Function Name: print_startup_message
********************************************************************************
* Summary:
* Prints startup information to the console.
*
*******************************************************************************/
static void print_startup_message(void)
{
    printf("\r\n");
    printf("============================================\r\n");
    printf("  PSOC Edge E84 AI Kit - Face Detection\r\n");
    printf("============================================\r\n");
    printf("Camera: OV7675 DVP (320x240 RGB565)\r\n");
    printf("Features:\r\n");
    printf("  - Face detection with position\r\n");
    printf("  - Eye state tracking (open/closed)\r\n");
    printf("  - Real-time console output\r\n");
    printf("============================================\r\n\r\n");
}

/* [] END OF FILE */
