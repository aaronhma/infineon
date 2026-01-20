/*******************************************************************************
* File Name        : ov7675_camera.c
*
* Description      : OV7675 DVP Camera driver - simplified for face detection
*                    Based on Infineon's official camera-dvp-ov7675 library
*
********************************************************************************
* Copyright 2024, Infineon Technologies AG
*******************************************************************************/

#include "ov7675_camera.h"
#include "cy_gpio.h"
#include "cy_syslib.h"
#include "cy_sysclk.h"
#include "cy_tcpwm_pwm.h"
#include "cycfg_peripherals.h"
#include <string.h>
#include <stdio.h>

/*******************************************************************************
* Macros
*******************************************************************************/
#define I2C_TIMEOUT         (100U)
#define I2C_CMD_DELAY_US    (2000U)
#define NUM_BYTES           (1U)

/*******************************************************************************
* Private Variables
*******************************************************************************/
static bool camera_initialized = false;
static volatile bool xclk_running = false;

/* Frame buffer in shared memory */
__attribute__((section(".cy_socmem_data")))
static uint8_t frame_buffer[CAMERA_FRAME_SIZE] __attribute__((aligned(4)));

static camera_frame_t current_frame;

/*******************************************************************************
* XCLK (Master Clock) Functions - Software Generation
* These must be defined first as I2C functions depend on them
*******************************************************************************/

/* Generate XCLK pulses using software (blocking) */
static void generate_xclk_pulses(uint32_t num_pulses)
{
    for (uint32_t i = 0; i < num_pulses; i++)
    {
        Cy_GPIO_Write(GPIO_PRT17, 4U, 1U);
        Cy_SysLib_DelayUs(1);  /* ~500kHz clock */
        Cy_GPIO_Write(GPIO_PRT17, 4U, 0U);
        Cy_SysLib_DelayUs(1);
    }
}

/* Start software XCLK generation */
static cy_rslt_t start_xclk(void)
{
    printf("  Starting XCLK on P17.4...\r\n");

    /* Debug: Show current pin configuration */
    printf("    Current P17 config:\r\n");
    printf("      CFG:  0x%08lX\r\n", (unsigned long)GPIO_PRT17->CFG);
    printf("      OUT:  0x%08lX\r\n", (unsigned long)GPIO_PRT17->OUT);
    printf("      IN:   0x%08lX\r\n", (unsigned long)GPIO_PRT17->IN);
    printf("      HSIOM: 0x%08lX\r\n", (unsigned long)HSIOM_PRT17->PORT_SEL0);

    /* Method 1: Try direct register writes to force GPIO control */
    printf("    Forcing GPIO mode via direct register writes...\r\n");

    /* Clear HSIOM for pin 4 (bits 16-20 in PORT_SEL0) to select GPIO */
    uint32_t hsiom_sel = HSIOM_PRT17->PORT_SEL0;
    hsiom_sel &= ~(0x1FUL << 16);  /* Clear bits 16-20 for pin 4 */
    HSIOM_PRT17->PORT_SEL0 = hsiom_sel;

    /* Configure pin 4 as strong drive output (bits 12-14 in CFG for pin 4) */
    uint32_t cfg = GPIO_PRT17->CFG;
    cfg &= ~(0x7UL << 12);  /* Clear drive mode bits for pin 4 */
    cfg |= (CY_GPIO_DM_STRONG_IN_OFF << 12);  /* Strong drive, no input */
    GPIO_PRT17->CFG = cfg;

    printf("    After config:\r\n");
    printf("      CFG:  0x%08lX\r\n", (unsigned long)GPIO_PRT17->CFG);
    printf("      HSIOM: 0x%08lX\r\n", (unsigned long)HSIOM_PRT17->PORT_SEL0);

    /* Test GPIO control */
    GPIO_PRT17->OUT_CLR = (1UL << 4);  /* Set pin 4 LOW */
    Cy_SysLib_DelayUs(10);
    int v0 = (GPIO_PRT17->IN >> 4) & 1;

    GPIO_PRT17->OUT_SET = (1UL << 4);  /* Set pin 4 HIGH */
    Cy_SysLib_DelayUs(10);
    int v1 = (GPIO_PRT17->IN >> 4) & 1;

    printf("    GPIO test: write 0->read %d, write 1->read %d\r\n", v0, v1);

    /* If GPIO doesn't work, try using the hardware PWM instead */
    if (v0 != 0 || v1 != 1)
    {
        printf("    GPIO control failed - trying hardware PWM...\r\n");

        /* Restore HSIOM to TCPWM LINE_COMPL4 (value 9) */
        hsiom_sel = HSIOM_PRT17->PORT_SEL0;
        hsiom_sel &= ~(0x1FUL << 16);
        hsiom_sel |= (9UL << 16);  /* P17_4_TCPWM0_LINE_COMPL4 = 9 */
        HSIOM_PRT17->PORT_SEL0 = hsiom_sel;

        /* Configure pin for peripheral function */
        cfg = GPIO_PRT17->CFG;
        cfg &= ~(0x7UL << 12);
        cfg |= (CY_GPIO_DM_STRONG_IN_OFF << 12);
        GPIO_PRT17->CFG = cfg;

        printf("      HSIOM set to TCPWM: 0x%08lX\r\n", (unsigned long)HSIOM_PRT17->PORT_SEL0);

        /* Enable clock for TCPWM0 channel 4 */
        Cy_SysClk_PeriPclkDisableDivider(PCLK_TCPWM0_CLOCK_COUNTER_EN4, CY_SYSCLK_DIV_16_5_BIT, 1U);
        Cy_SysClk_PeriPclkSetFracDivider(PCLK_TCPWM0_CLOCK_COUNTER_EN4, CY_SYSCLK_DIV_16_5_BIT, 1U, 3U, 0U);
        Cy_SysClk_PeriPclkEnableDivider(PCLK_TCPWM0_CLOCK_COUNTER_EN4, CY_SYSCLK_DIV_16_5_BIT, 1U);
        Cy_SysClk_PeriphAssignDivider(PCLK_TCPWM0_CLOCK_COUNTER_EN4, CY_SYSCLK_DIV_16_5_BIT, 1U);

        /* Initialize PWM with period=2 for 50% duty cycle */
        cy_stc_tcpwm_pwm_config_t pwm_config = {
            .pwmMode = CY_TCPWM_PWM_MODE_PWM,
            .clockPrescaler = CY_TCPWM_PWM_PRESCALER_DIVBY_1,
            .pwmAlignment = CY_TCPWM_PWM_LEFT_ALIGN,
            .deadTimeClocks = 0,
            .runMode = CY_TCPWM_PWM_CONTINUOUS,
            .period0 = 2,
            .compare0 = 1,
            .enableCompareSwap = false,
            .enablePeriodSwap = false,
            .interruptSources = 0,
            .invertPWMOut = CY_TCPWM_PWM_INVERT_DISABLE,
            .invertPWMOutN = CY_TCPWM_PWM_INVERT_DISABLE,
            .killMode = CY_TCPWM_PWM_STOP_ON_KILL,
            .swapInputMode = 3,
            .swapInput = CY_TCPWM_INPUT_0,
            .reloadInputMode = 3,
            .reloadInput = CY_TCPWM_INPUT_0,
            .startInputMode = 3,
            .startInput = CY_TCPWM_INPUT_0,
            .killInputMode = 3,
            .killInput = CY_TCPWM_INPUT_0,
            .countInputMode = 3,
            .countInput = CY_TCPWM_INPUT_1,
        };

        cy_rslt_t result = Cy_TCPWM_PWM_Init(TCPWM0, 4U, &pwm_config);
        printf("      PWM Init result: %lu\r\n", (unsigned long)result);

        Cy_TCPWM_PWM_Enable(TCPWM0, 4U);
        Cy_TCPWM_TriggerStart_Single(TCPWM0, 4U);

        uint32_t status = Cy_TCPWM_PWM_GetStatus(TCPWM0, 4U);
        printf("      PWM status: 0x%lX (running=%s)\r\n",
               (unsigned long)status,
               (status & CY_TCPWM_PWM_STATUS_COUNTER_RUNNING) ? "YES" : "NO");

        /* Check if pin is toggling now */
        Cy_SysLib_Delay(1);
        int transitions = 0;
        int last = (GPIO_PRT17->IN >> 4) & 1;
        for (int i = 0; i < 100; i++)
        {
            int curr = (GPIO_PRT17->IN >> 4) & 1;
            if (curr != last) { transitions++; last = curr; }
        }
        printf("      XCLK transitions in 100 samples: %d\r\n", transitions);

        if (transitions < 5 && !(status & CY_TCPWM_PWM_STATUS_COUNTER_RUNNING))
        {
            printf("    *** WARNING: XCLK may not be running, but continuing anyway ***\r\n");
        }
    }
    else
    {
        /* GPIO works - generate initial clock pulses */
        printf("    GPIO control works - generating XCLK pulses...\r\n");
        generate_xclk_pulses(10000);
    }

    xclk_running = true;
    printf("  XCLK setup complete\r\n");
    return CY_RSLT_SUCCESS;
}

/*******************************************************************************
* Bit-banged I2C with integrated XCLK generation
* More reliable for camera init since it generates XCLK during communication
*******************************************************************************/

static bool bitbang_i2c_start(void)
{
    /* Generate some XCLK first */
    generate_xclk_pulses(50);

    /* Configure I2C pins as GPIO */
    Cy_GPIO_SetHSIOM(GPIO_PRT17, 0U, HSIOM_SEL_GPIO);
    Cy_GPIO_SetHSIOM(GPIO_PRT17, 1U, HSIOM_SEL_GPIO);
    Cy_GPIO_SetDrivemode(GPIO_PRT17, 0U, CY_GPIO_DM_OD_DRIVESLOW);
    Cy_GPIO_SetDrivemode(GPIO_PRT17, 1U, CY_GPIO_DM_OD_DRIVESLOW);

    /* I2C Start: SDA goes LOW while SCL is HIGH */
    Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
    Cy_GPIO_Write(GPIO_PRT17, 1U, 1U);  /* SDA high */
    Cy_SysLib_DelayUs(5);
    generate_xclk_pulses(10);

    Cy_GPIO_Write(GPIO_PRT17, 1U, 0U);  /* SDA low */
    Cy_SysLib_DelayUs(5);
    generate_xclk_pulses(10);

    Cy_GPIO_Write(GPIO_PRT17, 0U, 0U);  /* SCL low */
    Cy_SysLib_DelayUs(5);

    return true;
}

static void bitbang_i2c_stop(void)
{
    generate_xclk_pulses(10);
    Cy_GPIO_Write(GPIO_PRT17, 1U, 0U);  /* SDA low */
    Cy_SysLib_DelayUs(5);
    Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
    Cy_SysLib_DelayUs(5);
    generate_xclk_pulses(10);
    Cy_GPIO_Write(GPIO_PRT17, 1U, 1U);  /* SDA high */
    Cy_SysLib_DelayUs(5);
}

static bool bitbang_i2c_write_byte(uint8_t byte)
{
    /* Write 8 bits MSB first */
    for (int i = 7; i >= 0; i--)
    {
        Cy_GPIO_Write(GPIO_PRT17, 1U, (byte >> i) & 1);  /* SDA */
        Cy_SysLib_DelayUs(3);
        generate_xclk_pulses(5);
        Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
        Cy_SysLib_DelayUs(5);
        generate_xclk_pulses(5);
        Cy_GPIO_Write(GPIO_PRT17, 0U, 0U);  /* SCL low */
        Cy_SysLib_DelayUs(3);
    }

    /* Read ACK */
    Cy_GPIO_Write(GPIO_PRT17, 1U, 1U);  /* Release SDA */
    Cy_SysLib_DelayUs(3);
    generate_xclk_pulses(5);
    Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
    Cy_SysLib_DelayUs(5);
    generate_xclk_pulses(5);
    bool ack = (Cy_GPIO_Read(GPIO_PRT17, 1U) == 0);
    Cy_GPIO_Write(GPIO_PRT17, 0U, 0U);  /* SCL low */
    Cy_SysLib_DelayUs(3);

    return ack;
}

static uint8_t bitbang_i2c_read_byte(bool send_ack)
{
    uint8_t byte = 0;

    Cy_GPIO_Write(GPIO_PRT17, 1U, 1U);  /* Release SDA for reading */

    /* Read 8 bits MSB first */
    for (int i = 7; i >= 0; i--)
    {
        Cy_SysLib_DelayUs(3);
        generate_xclk_pulses(5);
        Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
        Cy_SysLib_DelayUs(5);
        generate_xclk_pulses(5);
        if (Cy_GPIO_Read(GPIO_PRT17, 1U))
        {
            byte |= (1 << i);
        }
        Cy_GPIO_Write(GPIO_PRT17, 0U, 0U);  /* SCL low */
        Cy_SysLib_DelayUs(3);
    }

    /* Send ACK/NAK */
    Cy_GPIO_Write(GPIO_PRT17, 1U, send_ack ? 0U : 1U);
    Cy_SysLib_DelayUs(3);
    generate_xclk_pulses(5);
    Cy_GPIO_Write(GPIO_PRT17, 0U, 1U);  /* SCL high */
    Cy_SysLib_DelayUs(5);
    generate_xclk_pulses(5);
    Cy_GPIO_Write(GPIO_PRT17, 0U, 0U);  /* SCL low */
    Cy_SysLib_DelayUs(3);

    return byte;
}

/* Read camera register using bit-banged I2C with XCLK */
static camera_status_t bitbang_read_reg(uint8_t reg, uint8_t *val)
{
    bitbang_i2c_start();

    /* Send write address */
    if (!bitbang_i2c_write_byte(OV7675_I2C_ADDR << 1))
    {
        bitbang_i2c_stop();
        return CAMERA_ERROR_I2C;
    }

    /* Send register */
    if (!bitbang_i2c_write_byte(reg))
    {
        bitbang_i2c_stop();
        return CAMERA_ERROR_I2C;
    }

    /* Repeated start */
    bitbang_i2c_start();

    /* Send read address */
    if (!bitbang_i2c_write_byte((OV7675_I2C_ADDR << 1) | 1))
    {
        bitbang_i2c_stop();
        return CAMERA_ERROR_I2C;
    }

    /* Read value with NAK */
    *val = bitbang_i2c_read_byte(false);

    bitbang_i2c_stop();
    return CAMERA_OK;
}

/*******************************************************************************
* Public Functions
*******************************************************************************/

camera_status_t camera_init(const camera_config_t *config)
{
    uint8_t pid_h, pid_l;

    (void)config; /* Unused for now */

    if (camera_initialized)
    {
        return CAMERA_OK;
    }

    printf("=== OV7675 Camera Initialization ===\r\n");

    /* Step 1: Configure control pins */
    printf("  Configuring control pins...\r\n");

    /* PWDN pin - P17.7 */
    Cy_GPIO_Pin_FastInit(GPIO_PRT17, 7U, CY_GPIO_DM_STRONG_IN_OFF, 1U, HSIOM_SEL_GPIO);

    /* RESET pin - P17.5 */
    Cy_GPIO_Pin_FastInit(GPIO_PRT17, 5U, CY_GPIO_DM_STRONG_IN_OFF, 0U, HSIOM_SEL_GPIO);

    /* I2C pins - P17.0 (SCL), P17.1 (SDA) - open drain */
    Cy_GPIO_Pin_FastInit(GPIO_PRT17, 0U, CY_GPIO_DM_OD_DRIVESLOW, 1U, HSIOM_SEL_GPIO);
    Cy_GPIO_Pin_FastInit(GPIO_PRT17, 1U, CY_GPIO_DM_OD_DRIVESLOW, 1U, HSIOM_SEL_GPIO);

    /* Step 2: Start XCLK - camera needs clock before responding to I2C */
    if (start_xclk() != CY_RSLT_SUCCESS)
    {
        printf("  ERROR: Failed to start XCLK\r\n");
        return CAMERA_ERROR_INIT;
    }

    /* Step 3: Power sequence */
    printf("  Power sequence...\r\n");

    /* Power down (PWDN HIGH) */
    Cy_GPIO_Write(GPIO_PRT17, 7U, 1U);
    Cy_SysLib_Delay(10);

    /* Assert reset (RESET LOW) */
    Cy_GPIO_Write(GPIO_PRT17, 5U, 0U);
    Cy_SysLib_Delay(10);

    /* Generate XCLK while powered down */
    generate_xclk_pulses(5000);

    /* Power up (PWDN LOW) */
    Cy_GPIO_Write(GPIO_PRT17, 7U, 0U);
    Cy_SysLib_Delay(10);

    /* Generate more XCLK */
    generate_xclk_pulses(5000);

    /* Release reset (RESET HIGH) */
    Cy_GPIO_Write(GPIO_PRT17, 5U, 1U);
    Cy_SysLib_Delay(50);

    /* Generate XCLK for stabilization */
    generate_xclk_pulses(20000);

    /* Step 4: Debug - print pin states */
    printf("  Pin states:\r\n");
    printf("    P17.0 (SCL):   %lu\r\n", (unsigned long)Cy_GPIO_Read(GPIO_PRT17, 0));
    printf("    P17.1 (SDA):   %lu\r\n", (unsigned long)Cy_GPIO_Read(GPIO_PRT17, 1));
    printf("    P17.4 (XCLK):  %lu\r\n", (unsigned long)Cy_GPIO_Read(GPIO_PRT17, 4));
    printf("    P17.5 (RESET): %lu\r\n", (unsigned long)Cy_GPIO_Read(GPIO_PRT17, 5));
    printf("    P17.7 (PWDN):  %lu\r\n", (unsigned long)Cy_GPIO_Read(GPIO_PRT17, 7));

    /* Check I2C bus state */
    if (Cy_GPIO_Read(GPIO_PRT17, 0) == 0 || Cy_GPIO_Read(GPIO_PRT17, 1) == 0)
    {
        printf("  WARNING: I2C lines are LOW - bus may be stuck or camera not connected\r\n");
    }

    /* Step 5: Try to read camera ID using bit-banged I2C with XCLK */
    printf("  Reading camera ID (addr 0x%02X)...\r\n", OV7675_I2C_ADDR);

    camera_status_t status = bitbang_read_reg(OV7675_REG_PID, &pid_h);
    if (status != CAMERA_OK)
    {
        printf("  ERROR: No ACK from camera at address 0x%02X\r\n", OV7675_I2C_ADDR);
        printf("  Troubleshooting:\r\n");
        printf("    1) Check camera module is firmly seated in J14 connector\r\n");
        printf("    2) Check ribbon cable orientation (contacts facing correct way)\r\n");
        printf("    3) Verify no bent pins on camera module\r\n");
        printf("    4) Try reseating the camera module\r\n");
        return CAMERA_ERROR_NOT_FOUND;
    }

    status = bitbang_read_reg(OV7675_REG_VER, &pid_l);
    if (status != CAMERA_OK)
    {
        printf("  ERROR: Failed to read camera version register\r\n");
        return CAMERA_ERROR_I2C;
    }

    printf("  Camera ID: 0x%02X 0x%02X\r\n", pid_h, pid_l);

    /* Verify OV7675 (PID should be 0x76) */
    if (pid_h != 0x76)
    {
        printf("  WARNING: Unexpected camera ID (expected 0x76xx for OV7675)\r\n");
    }

    /* Initialize frame buffer */
    current_frame.data = frame_buffer;
    current_frame.size = CAMERA_FRAME_SIZE;
    current_frame.width = CAMERA_WIDTH;
    current_frame.height = CAMERA_HEIGHT;
    current_frame.ready = false;

    camera_initialized = true;
    printf("=== Camera initialized successfully! ===\r\n");

    return CAMERA_OK;
}

void camera_deinit(void)
{
    if (!camera_initialized)
    {
        return;
    }

    camera_set_power(false);
    camera_initialized = false;
}

camera_status_t camera_capture_frame(camera_frame_t *frame)
{
    if (!camera_initialized || frame == NULL)
    {
        return CAMERA_ERROR_INIT;
    }

    /* Note: Full DVP capture requires DMA setup */
    frame->data = frame_buffer;
    frame->size = CAMERA_FRAME_SIZE;
    frame->width = CAMERA_WIDTH;
    frame->height = CAMERA_HEIGHT;
    frame->ready = false;

    return CAMERA_ERROR_CAPTURE;  /* DVP capture not implemented */
}

void camera_set_power(bool power_on)
{
    if (power_on)
    {
        /* Power down pin LOW = camera active */
        Cy_GPIO_Write(GPIO_PRT17, 7U, 0U);
    }
    else
    {
        /* Power down pin HIGH = camera in standby */
        Cy_GPIO_Write(GPIO_PRT17, 7U, 1U);
    }
}

void camera_reset(void)
{
    /* Assert reset (LOW) */
    Cy_GPIO_Write(GPIO_PRT17, 5U, 0U);
    Cy_SysLib_Delay(10);

    /* Release reset (HIGH) */
    Cy_GPIO_Write(GPIO_PRT17, 5U, 1U);
    Cy_SysLib_Delay(50);

    /* Generate XCLK for stabilization */
    generate_xclk_pulses(10000);
}

camera_status_t camera_read_id(uint8_t *pid_h, uint8_t *pid_l)
{
    camera_status_t status;

    status = bitbang_read_reg(OV7675_REG_PID, pid_h);
    if (status != CAMERA_OK)
    {
        return status;
    }

    status = bitbang_read_reg(OV7675_REG_VER, pid_l);
    return status;
}

/* Stubs for unused functions */
camera_status_t camera_start_continuous(void) { return CAMERA_ERROR_INIT; }
void camera_stop_continuous(void) {}
bool camera_frame_available(void) { return false; }
camera_status_t camera_get_frame(camera_frame_t *frame) { (void)frame; return CAMERA_ERROR_INIT; }

/* [] END OF FILE */
