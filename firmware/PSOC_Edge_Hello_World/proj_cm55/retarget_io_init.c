/*******************************************************************************
 * File Name:   retarget_io_init.c
 *
 * Description: Simple retarget for printf to UART for CM55 core
 *              Uses the same UART as CM33 (assumes CM33 has already initialized it)
 *
 *******************************************************************************
* Copyright 2023-2025, Cypress Semiconductor Corporation (an Infineon company)
*******************************************************************************/

#include "retarget_io_init.h"
#include <stdio.h>

/*******************************************************************************
* Global Variables
*******************************************************************************/
/* None needed - using UART already initialized by CM33 */

/*******************************************************************************
* Function Name: init_retarget_io_cm55
*******************************************************************************/
void init_retarget_io_cm55(void)
{
    /* UART is already initialized by CM33, just store context for our use */
    /* The SCB is shared, so we don't re-init, just enable if needed */

    /* Note: In a production system, you would use IPC for console output
     * to avoid conflicts between cores. For this demo, we assume CM33
     * finishes its initial prints before CM55 starts heavy printing */
}

/*******************************************************************************
* _write - Low-level write function for printf
* Redirects stdout to UART
*******************************************************************************/
int _write(int file, char *ptr, int len)
{
    (void)file;

    for (int i = 0; i < len; i++)
    {
        /* Wait for TX FIFO to have space */
        while (Cy_SCB_UART_GetNumInTxFifo(CYBSP_DEBUG_UART_HW) >=
               Cy_SCB_GetFifoSize(CYBSP_DEBUG_UART_HW))
        {
            /* Wait */
        }

        /* Send character */
        Cy_SCB_UART_Put(CYBSP_DEBUG_UART_HW, (uint32_t)ptr[i]);
    }

    return len;
}

/* [] END OF FILE */
