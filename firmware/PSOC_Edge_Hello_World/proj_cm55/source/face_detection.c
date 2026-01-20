/*******************************************************************************
* File Name        : face_detection.c
*
* Description      : Face detection with eye state tracking implementation
*                    Uses simple image processing for demonstration.
*                    Can be extended to use TensorFlow Lite or Ethos-U55 NPU.
*
********************************************************************************
* Copyright 2024, Infineon Technologies AG
*******************************************************************************/

#include "face_detection.h"
#include "cy_syslib.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

/*******************************************************************************
* Private Variables
*******************************************************************************/

static bool detection_initialized = false;
static detection_config_t current_config;
static uint32_t frame_counter = 0;

/* Preprocessed image buffer */
static uint8_t grayscale_buffer[FACE_INPUT_WIDTH * FACE_INPUT_HEIGHT];
static uint8_t resized_buffer[FACE_INPUT_WIDTH * FACE_INPUT_HEIGHT];

/* Integral image for fast feature computation */
static uint32_t integral_image[(FACE_INPUT_WIDTH + 1) * (FACE_INPUT_HEIGHT + 1)];

/*******************************************************************************
* Private Function Prototypes
*******************************************************************************/

static void compute_integral_image(const uint8_t *gray, uint16_t width, uint16_t height);
static uint32_t get_integral_sum(int x, int y, int w, int h, uint16_t img_width);
static int detect_skin_regions(const uint8_t *rgb565, uint16_t width, uint16_t height,
                               bbox_t *regions, int max_regions);
static float compute_eye_openness(const uint8_t *gray, uint16_t width,
                                   int eye_x, int eye_y, int eye_radius);
static void find_eye_positions(const uint8_t *gray, uint16_t width, uint16_t height,
                               const bbox_t *face_bbox,
                               eye_point_t *left_eye, eye_point_t *right_eye);

/*******************************************************************************
* Public Functions
*******************************************************************************/

detection_status_t face_detection_init(const detection_config_t *config)
{
    if (detection_initialized)
    {
        return DETECTION_OK;
    }

    /* Use default config if not provided */
    if (config == NULL)
    {
        current_config.confidence_threshold = FACE_DETECTION_THRESHOLD;
        current_config.eye_threshold = EYE_CLOSED_THRESHOLD;
        current_config.enable_eye_tracking = true;
        current_config.input_width = FACE_INPUT_WIDTH;
        current_config.input_height = FACE_INPUT_HEIGHT;
    }
    else
    {
        memcpy(&current_config, config, sizeof(detection_config_t));
    }

    frame_counter = 0;
    detection_initialized = true;

    return DETECTION_OK;
}

void face_detection_deinit(void)
{
    detection_initialized = false;
    frame_counter = 0;
}

detection_status_t face_detection_run(const uint8_t *image_data,
                                       uint16_t width,
                                       uint16_t height,
                                       detection_result_t *result)
{
    if (!detection_initialized)
    {
        return DETECTION_ERROR_INIT;
    }

    if (image_data == NULL || result == NULL)
    {
        return DETECTION_ERROR_INVALID_INPUT;
    }

    uint32_t start_time = 0;  /* Timing placeholder */

    /* Initialize result */
    memset(result, 0, sizeof(detection_result_t));
    result->frame_id = frame_counter++;

    /* Convert RGB565 to grayscale */
    rgb565_to_grayscale(image_data, grayscale_buffer, width, height);

    /* Resize to model input size */
    resize_image(grayscale_buffer, width, height,
                 resized_buffer, FACE_INPUT_WIDTH, FACE_INPUT_HEIGHT);

    /* Compute integral image for fast feature detection */
    compute_integral_image(resized_buffer, FACE_INPUT_WIDTH, FACE_INPUT_HEIGHT);

    /* Simple face detection using skin color and face-like features */
    bbox_t candidate_regions[MAX_FACES];
    int num_candidates = detect_skin_regions(image_data, width, height,
                                              candidate_regions, MAX_FACES);

    /* Process each candidate region */
    for (int i = 0; i < num_candidates && result->face_count < MAX_FACES; i++)
    {
        face_result_t *face = &result->faces[result->face_count];

        /* Scale bbox to original image coordinates */
        face->bbox = candidate_regions[i];

        /* Compute confidence based on region properties */
        float aspect_ratio = (float)face->bbox.width / (float)face->bbox.height;
        float size_score = (float)(face->bbox.width * face->bbox.height) /
                          (float)(width * height);

        /* Face typically has aspect ratio close to 1 and reasonable size */
        float aspect_score = 1.0f - fabsf(aspect_ratio - 1.0f);
        if (aspect_score < 0) aspect_score = 0;

        face->confidence = aspect_score * 0.5f + (size_score > 0.01f ? 0.5f : size_score * 50.0f);

        if (face->confidence < current_config.confidence_threshold)
        {
            continue;
        }

        /* Find eye positions within the face region */
        if (current_config.enable_eye_tracking)
        {
            find_eye_positions(grayscale_buffer, width, height,
                              &face->bbox, &face->left_eye, &face->right_eye);

            /* Compute eye openness scores */
            int eye_radius = face->bbox.width / 8;

            face->left_eye_openness = compute_eye_openness(
                grayscale_buffer, width,
                face->left_eye.x, face->left_eye.y, eye_radius);

            face->right_eye_openness = compute_eye_openness(
                grayscale_buffer, width,
                face->right_eye.x, face->right_eye.y, eye_radius);

            /* Determine eye states */
            face->left_eye_state = (face->left_eye_openness < current_config.eye_threshold)
                                   ? EYE_CLOSED : EYE_OPEN;
            face->right_eye_state = (face->right_eye_openness < current_config.eye_threshold)
                                    ? EYE_CLOSED : EYE_OPEN;
        }
        else
        {
            face->left_eye_state = EYE_UNKNOWN;
            face->right_eye_state = EYE_UNKNOWN;
        }

        face->valid = true;
        result->face_count++;
    }

    result->inference_time_ms = 0;
    (void)start_time;

    return DETECTION_OK;
}

detection_status_t face_detection_run_gray(const uint8_t *image_data,
                                            uint16_t width,
                                            uint16_t height,
                                            detection_result_t *result)
{
    if (!detection_initialized)
    {
        return DETECTION_ERROR_INIT;
    }

    if (image_data == NULL || result == NULL)
    {
        return DETECTION_ERROR_INVALID_INPUT;
    }

    uint32_t start_time = 0;  /* Timing placeholder */

    /* Initialize result */
    memset(result, 0, sizeof(detection_result_t));
    result->frame_id = frame_counter++;

    /* Copy grayscale data */
    memcpy(grayscale_buffer, image_data, width * height);

    /* Resize to model input size */
    resize_image(grayscale_buffer, width, height,
                 resized_buffer, FACE_INPUT_WIDTH, FACE_INPUT_HEIGHT);

    /* Compute integral image */
    compute_integral_image(resized_buffer, FACE_INPUT_WIDTH, FACE_INPUT_HEIGHT);

    /* For grayscale, use simple threshold-based detection */
    /* This is a simplified approach - real implementation would use ML model */

    result->inference_time_ms = 0;
    (void)start_time;

    return DETECTION_OK;
}

const char* eye_state_to_string(eye_state_t state)
{
    switch (state)
    {
        case EYE_OPEN:
            return "OPEN";
        case EYE_CLOSED:
            return "CLOSED";
        case EYE_UNKNOWN:
        default:
            return "UNKNOWN";
    }
}

void face_detection_print_results(const detection_result_t *result)
{
    if (result == NULL)
    {
        printf("No detection results\r\n");
        return;
    }

    printf("\r\n========== Face Detection Results ==========\r\n");
    printf("Frame ID: %lu | Inference Time: %lu ms\r\n",
           (unsigned long)result->frame_id,
           (unsigned long)result->inference_time_ms);
    printf("Faces Detected: %u\r\n", result->face_count);
    printf("--------------------------------------------\r\n");

    if (result->face_count == 0)
    {
        printf("No faces detected in this frame.\r\n");
    }
    else
    {
        for (uint8_t i = 0; i < result->face_count; i++)
        {
            const face_result_t *face = &result->faces[i];

            if (!face->valid)
            {
                continue;
            }

            printf("Face #%u:\r\n", i + 1);
            printf("  Position: (%d, %d) Size: %u x %u\r\n",
                   face->bbox.x, face->bbox.y,
                   face->bbox.width, face->bbox.height);
            printf("  Confidence: %.2f\r\n", face->confidence);
            printf("  Left Eye:  (%d, %d) - %s (openness: %.2f)\r\n",
                   face->left_eye.x, face->left_eye.y,
                   eye_state_to_string(face->left_eye_state),
                   face->left_eye_openness);
            printf("  Right Eye: (%d, %d) - %s (openness: %.2f)\r\n",
                   face->right_eye.x, face->right_eye.y,
                   eye_state_to_string(face->right_eye_state),
                   face->right_eye_openness);
            printf("--------------------------------------------\r\n");
        }
    }

    printf("=============================================\r\n\r\n");
}

void rgb565_to_grayscale(const uint8_t *rgb565,
                          uint8_t *gray,
                          uint16_t width,
                          uint16_t height)
{
    uint32_t total_pixels = width * height;

    for (uint32_t i = 0; i < total_pixels; i++)
    {
        /* RGB565: RRRRRGGG GGGBBBBB */
        uint16_t pixel = (rgb565[i * 2] << 8) | rgb565[i * 2 + 1];

        /* Extract RGB components */
        uint8_t r = (pixel >> 11) & 0x1F;
        uint8_t g = (pixel >> 5) & 0x3F;
        uint8_t b = pixel & 0x1F;

        /* Scale to 8-bit */
        r = (r << 3) | (r >> 2);
        g = (g << 2) | (g >> 4);
        b = (b << 3) | (b >> 2);

        /* Convert to grayscale using luminance formula */
        /* Y = 0.299*R + 0.587*G + 0.114*B */
        /* Using fixed-point: Y = (77*R + 150*G + 29*B) >> 8 */
        gray[i] = (uint8_t)((77 * r + 150 * g + 29 * b) >> 8);
    }
}

void resize_image(const uint8_t *input,
                   uint16_t input_width,
                   uint16_t input_height,
                   uint8_t *output,
                   uint16_t output_width,
                   uint16_t output_height)
{
    float x_ratio = (float)(input_width - 1) / output_width;
    float y_ratio = (float)(input_height - 1) / output_height;

    for (uint16_t y = 0; y < output_height; y++)
    {
        for (uint16_t x = 0; x < output_width; x++)
        {
            float src_x = x * x_ratio;
            float src_y = y * y_ratio;

            int x_l = (int)src_x;
            int y_l = (int)src_y;
            int x_h = x_l + 1;
            int y_h = y_l + 1;

            if (x_h >= input_width) x_h = input_width - 1;
            if (y_h >= input_height) y_h = input_height - 1;

            float x_weight = src_x - x_l;
            float y_weight = src_y - y_l;

            /* Bilinear interpolation */
            float a = input[y_l * input_width + x_l];
            float b = input[y_l * input_width + x_h];
            float c = input[y_h * input_width + x_l];
            float d = input[y_h * input_width + x_h];

            float value = a * (1 - x_weight) * (1 - y_weight) +
                         b * x_weight * (1 - y_weight) +
                         c * (1 - x_weight) * y_weight +
                         d * x_weight * y_weight;

            output[y * output_width + x] = (uint8_t)value;
        }
    }
}

/*******************************************************************************
* Private Functions
*******************************************************************************/

static void compute_integral_image(const uint8_t *gray, uint16_t width, uint16_t height)
{
    uint16_t ii_width = width + 1;

    /* Initialize first row and column to zero */
    for (uint16_t x = 0; x <= width; x++)
    {
        integral_image[x] = 0;
    }
    for (uint16_t y = 0; y <= height; y++)
    {
        integral_image[y * ii_width] = 0;
    }

    /* Compute integral image */
    for (uint16_t y = 1; y <= height; y++)
    {
        uint32_t row_sum = 0;
        for (uint16_t x = 1; x <= width; x++)
        {
            row_sum += gray[(y - 1) * width + (x - 1)];
            integral_image[y * ii_width + x] = row_sum + integral_image[(y - 1) * ii_width + x];
        }
    }
}

/* Reserved for future Haar cascade implementation */
__attribute__((unused))
static uint32_t get_integral_sum(int x, int y, int w, int h, uint16_t img_width)
{
    uint16_t ii_width = img_width + 1;

    /* Ensure bounds */
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + w > img_width) w = img_width - x;
    if (y + h > FACE_INPUT_HEIGHT) h = FACE_INPUT_HEIGHT - y;

    /* Sum = D - B - C + A */
    uint32_t a = integral_image[y * ii_width + x];
    uint32_t b = integral_image[y * ii_width + (x + w)];
    uint32_t c = integral_image[(y + h) * ii_width + x];
    uint32_t d = integral_image[(y + h) * ii_width + (x + w)];

    return d - b - c + a;
}

static int detect_skin_regions(const uint8_t *rgb565, uint16_t width, uint16_t height,
                               bbox_t *regions, int max_regions)
{
    int region_count = 0;

    /* Simple skin detection using RGB565 color thresholds */
    /* This is a basic approach - production code would use more sophisticated methods */

    /* Divide image into grid and find skin-colored regions */
    int grid_size = 32;
    int min_skin_pixels = (grid_size * grid_size) / 4;

    for (int gy = 0; gy < height - grid_size && region_count < max_regions; gy += grid_size / 2)
    {
        for (int gx = 0; gx < width - grid_size && region_count < max_regions; gx += grid_size / 2)
        {
            int skin_count = 0;

            /* Count skin-colored pixels in this grid cell */
            for (int y = gy; y < gy + grid_size && y < height; y++)
            {
                for (int x = gx; x < gx + grid_size && x < width; x++)
                {
                    int idx = (y * width + x) * 2;
                    uint16_t pixel = (rgb565[idx] << 8) | rgb565[idx + 1];

                    /* Extract RGB components */
                    uint8_t r = ((pixel >> 11) & 0x1F) << 3;
                    uint8_t g = ((pixel >> 5) & 0x3F) << 2;
                    uint8_t b = (pixel & 0x1F) << 3;

                    /* Simple skin color detection */
                    /* Skin typically has R > G > B and certain ranges */
                    if (r > 60 && r > g && g > b &&
                        (r - g) > 15 && (r - b) > 15 &&
                        r < 250 && g > 40 && b > 20)
                    {
                        skin_count++;
                    }
                }
            }

            /* If enough skin pixels found, consider it a face candidate */
            if (skin_count > min_skin_pixels)
            {
                /* Expand region to find face bounds */
                regions[region_count].x = gx;
                regions[region_count].y = gy;
                regions[region_count].width = grid_size;
                regions[region_count].height = grid_size;

                /* Try to expand the region */
                int expand = grid_size / 2;
                if (gx >= expand) regions[region_count].x -= expand;
                if (gy >= expand) regions[region_count].y -= expand;
                regions[region_count].width += expand * 2;
                regions[region_count].height += expand * 2;

                /* Clamp to image bounds */
                if (regions[region_count].x + regions[region_count].width > width)
                    regions[region_count].width = width - regions[region_count].x;
                if (regions[region_count].y + regions[region_count].height > height)
                    regions[region_count].height = height - regions[region_count].y;

                region_count++;

                /* Skip ahead to avoid overlapping detections */
                gx += grid_size;
            }
        }
    }

    return region_count;
}

static void find_eye_positions(const uint8_t *gray, uint16_t width, uint16_t height,
                               const bbox_t *face_bbox,
                               eye_point_t *left_eye, eye_point_t *right_eye)
{
    /* Eyes are typically in the upper third of the face */
    int eye_region_y = face_bbox->y + face_bbox->height / 5;
    int eye_region_height = face_bbox->height / 4;

    /* Left eye in left half, right eye in right half */
    int face_center_x = face_bbox->x + face_bbox->width / 2;

    /* Find darkest regions in each half (eyes are typically darker) */
    int left_min_brightness = 255;
    int right_min_brightness = 255;

    left_eye->x = face_bbox->x + face_bbox->width / 4;
    left_eye->y = eye_region_y + eye_region_height / 2;
    right_eye->x = face_bbox->x + 3 * face_bbox->width / 4;
    right_eye->y = eye_region_y + eye_region_height / 2;

    /* Search for darkest point in left eye region */
    for (int y = eye_region_y; y < eye_region_y + eye_region_height && y < height; y++)
    {
        for (int x = face_bbox->x; x < face_center_x && x < width; x++)
        {
            int brightness = gray[y * width + x];
            if (brightness < left_min_brightness)
            {
                left_min_brightness = brightness;
                left_eye->x = x;
                left_eye->y = y;
            }
        }
    }

    /* Search for darkest point in right eye region */
    for (int y = eye_region_y; y < eye_region_y + eye_region_height && y < height; y++)
    {
        for (int x = face_center_x; x < face_bbox->x + face_bbox->width && x < width; x++)
        {
            int brightness = gray[y * width + x];
            if (brightness < right_min_brightness)
            {
                right_min_brightness = brightness;
                right_eye->x = x;
                right_eye->y = y;
            }
        }
    }
}

static float compute_eye_openness(const uint8_t *gray, uint16_t width,
                                   int eye_x, int eye_y, int eye_radius)
{
    if (eye_radius < 2) eye_radius = 2;

    /* Compute vertical gradient around eye position */
    /* Open eyes have stronger horizontal edges (eyelids) */
    float vertical_gradient = 0;
    float horizontal_gradient = 0;
    int count = 0;

    for (int dy = -eye_radius; dy <= eye_radius; dy++)
    {
        for (int dx = -eye_radius; dx <= eye_radius; dx++)
        {
            int x = eye_x + dx;
            int y = eye_y + dy;

            if (x > 0 && x < width - 1 && y > 0 && y < FACE_INPUT_HEIGHT - 1)
            {
                /* Sobel-like gradient */
                int gx = gray[y * width + (x + 1)] - gray[y * width + (x - 1)];
                int gy = gray[(y + 1) * width + x] - gray[(y - 1) * width + x];

                horizontal_gradient += abs(gx);
                vertical_gradient += abs(gy);
                count++;
            }
        }
    }

    if (count == 0) return 0.5f;

    horizontal_gradient /= count;
    vertical_gradient /= count;

    /* Open eyes have more vertical gradient (from eyelids) */
    /* Closed eyes have more uniform appearance */
    float total = horizontal_gradient + vertical_gradient;
    if (total < 1.0f) return 0.5f;

    float openness = vertical_gradient / total;

    /* Normalize to 0-1 range */
    return openness;
}

/* [] END OF FILE */
