/**
 * @file alert_system.c
 * @brief Alert system implementation for Zephyr RTOS
 *
 * Infineon PSoC 6 AI Evaluation Kit
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/logging/log.h>

#include "alert_system.h"
#include "config.h"

LOG_MODULE_REGISTER(alert, LOG_LEVEL_INF);

/* LED GPIO nodes - adjust for your board */
#define LED0_NODE DT_ALIAS(led0)
#define LED1_NODE DT_ALIAS(led1)

#if DT_NODE_HAS_STATUS(LED0_NODE, okay)
static const struct gpio_dt_spec led_green = GPIO_DT_SPEC_GET(LED0_NODE, gpios);
#endif

#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
static const struct gpio_dt_spec led_red = GPIO_DT_SPEC_GET(LED1_NODE, gpios);
#endif

/* Alert state */
static struct {
    bool initialized;
    uint32_t last_speeding_alert_ms;
    uint32_t last_drowsy_alert_ms;
    led_status_t current_led_status;
} alert_state = {0};

int alert_system_init(void)
{
    int ret;

    if (alert_state.initialized) {
        return 0;
    }

#if DT_NODE_HAS_STATUS(LED0_NODE, okay)
    if (!gpio_is_ready_dt(&led_green)) {
        LOG_WRN("LED0 not ready");
    } else {
        ret = gpio_pin_configure_dt(&led_green, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_ERR("Failed to configure LED0: %d", ret);
        }
    }
#endif

#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
    if (!gpio_is_ready_dt(&led_red)) {
        LOG_WRN("LED1 not ready");
    } else {
        ret = gpio_pin_configure_dt(&led_red, GPIO_OUTPUT_INACTIVE);
        if (ret < 0) {
            LOG_ERR("Failed to configure LED1: %d", ret);
        }
    }
#endif

    alert_state.initialized = true;
    LOG_INF("Alert system initialized");
    return 0;
}

void alert_system_deinit(void)
{
    alert_state.initialized = false;
}

void alert_system_beep(uint16_t frequency_hz, uint16_t duration_ms)
{
    /* PWM buzzer - implement if PWM device is available */
    LOG_DBG("Beep: %d Hz for %d ms", frequency_hz, duration_ms);
    k_msleep(duration_ms);
}

void alert_system_trigger(alert_type_t type)
{
    if (!alert_state.initialized) {
        return;
    }

    switch (type) {
    case ALERT_TYPE_SPEEDING:
        LOG_WRN("ALERT: Speeding!");
        alert_system_beep(SPEEDING_BEEP_FREQ_HZ, BEEP_DURATION_MS);
        alert_system_set_led(LED_STATUS_ORANGE);
        break;

    case ALERT_TYPE_DROWSY:
        LOG_WRN("ALERT: Drowsy driver!");
        alert_system_beep(DROWSY_BEEP_FREQ_HZ, 200);
        k_msleep(100);
        alert_system_beep(DROWSY_BEEP_FREQ_HZ, 200);
        alert_system_set_led(LED_STATUS_ORANGE);
        break;

    case ALERT_TYPE_IMPAIRED:
        LOG_ERR("ALERT: Driver impaired!");
        alert_system_beep(DROWSY_BEEP_FREQ_HZ, 200);
        k_msleep(100);
        alert_system_beep(DROWSY_BEEP_FREQ_HZ, 200);
        k_msleep(100);
        alert_system_beep(DROWSY_BEEP_FREQ_HZ, 400);
        alert_system_set_led(LED_STATUS_RED);
        break;

    case ALERT_TYPE_FACE_NOT_FOUND:
        LOG_DBG("No face detected");
        alert_system_beep(600, 100);
        break;

    default:
        break;
    }
}

void alert_system_set_led(led_status_t status)
{
    if (!alert_state.initialized) {
        return;
    }

#if DT_NODE_HAS_STATUS(LED0_NODE, okay)
    gpio_pin_set_dt(&led_green, 0);
#endif
#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
    gpio_pin_set_dt(&led_red, 0);
#endif

    switch (status) {
    case LED_STATUS_GREEN:
#if DT_NODE_HAS_STATUS(LED0_NODE, okay)
        gpio_pin_set_dt(&led_green, 1);
#endif
        break;

    case LED_STATUS_RED:
    case LED_STATUS_BLINKING_RED:
#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
        gpio_pin_set_dt(&led_red, 1);
#endif
        break;

    case LED_STATUS_ORANGE:
        /* Orange = both LEDs on some boards */
#if DT_NODE_HAS_STATUS(LED0_NODE, okay)
        gpio_pin_set_dt(&led_green, 1);
#endif
#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
        gpio_pin_set_dt(&led_red, 1);
#endif
        break;

    default:
        break;
    }

    alert_state.current_led_status = status;
}

void alert_system_stop(void)
{
    /* Stop any active alerts */
}

bool alert_system_cooldown_elapsed(alert_type_t type)
{
    uint32_t current_time = k_uptime_get_32();

    switch (type) {
    case ALERT_TYPE_SPEEDING:
        return (current_time - alert_state.last_speeding_alert_ms) >= ALERT_COOLDOWN_MS;

    case ALERT_TYPE_DROWSY:
    case ALERT_TYPE_IMPAIRED:
        return (current_time - alert_state.last_drowsy_alert_ms) >= ALERT_COOLDOWN_MS;

    default:
        return true;
    }
}

void alert_system_process(uint32_t current_time_ms)
{
    if (!alert_state.initialized) {
        return;
    }

    /* Handle blinking LED */
    if (alert_state.current_led_status == LED_STATUS_BLINKING_RED) {
        static uint32_t last_blink = 0;
        static bool led_on = false;

        if ((current_time_ms - last_blink) >= 500) {
            led_on = !led_on;
#if DT_NODE_HAS_STATUS(LED1_NODE, okay)
            gpio_pin_set_dt(&led_red, led_on ? 1 : 0);
#endif
            last_blink = current_time_ms;
        }
    }
}
