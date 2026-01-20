/*******************************************************************************
 * File Name:   retarget_io_init.h
 *
 * Description:  Simple UART output for CM55 core
 *
 *******************************************************************************
* Copyright 2023-2025, Cypress Semiconductor Corporation (an Infineon company)
*******************************************************************************/

#ifndef _RETARGET_IO_INIT_H_
#define _RETARGET_IO_INIT_H_

#include "cybsp.h"
#include "cy_scb_uart.h"

/*******************************************************************************
* Function prototypes
*******************************************************************************/
void init_retarget_io_cm55(void);

/*******************************************************************************
* Function Name: handle_app_error
*******************************************************************************/
__STATIC_INLINE void handle_app_error(void)
{
    __disable_irq();
    CY_ASSERT(0);
    while(true);
}

#endif /* _RETARGET_IO_INIT_H_ */
