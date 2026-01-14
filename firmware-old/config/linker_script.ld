/**
 * Linker Script for Infineon PSoC 6 (CY8C624ABZI-S2D44)
 * Cortex-M4 Core
 *
 * Memory Map:
 * - Flash: 2MB starting at 0x10000000
 * - SRAM:  1MB starting at 0x08000000
 *
 * For ModusToolbox projects, this is typically auto-generated.
 * This is a simplified version for standalone builds.
 */

/* Memory Regions */
MEMORY
{
    /* Cortex-M4 Flash - 2MB total, CM4 gets upper portion */
    FLASH (rx)    : ORIGIN = 0x10000000, LENGTH = 0x001F0000  /* 1984 KB */

    /* Cortex-M4 SRAM - 1MB total */
    RAM (rwx)     : ORIGIN = 0x08000000, LENGTH = 0x000F8000  /* 992 KB */

    /* Shared memory for IPC */
    SHARED (rw)   : ORIGIN = 0x080F8000, LENGTH = 0x00008000  /* 32 KB */
}

/* Entry Point */
ENTRY(Reset_Handler)

/* Stack and Heap sizes */
__stack_size = 0x10000;   /* 64 KB stack */
__heap_size  = 0x40000;   /* 256 KB heap for TFLite arena */

SECTIONS
{
    /* Interrupt Vector Table */
    .text.vectors :
    {
        . = ALIGN(4);
        KEEP(*(.vectors))
        . = ALIGN(4);
    } > FLASH

    /* Program Code */
    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.glue_7)
        *(.glue_7t)
        *(.eh_frame)

        KEEP(*(.init))
        KEEP(*(.fini))

        . = ALIGN(4);
        _etext = .;
    } > FLASH

    /* C++ Exception handling */
    .ARM.extab :
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } > FLASH

    .ARM :
    {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } > FLASH

    /* Constructor/Destructor tables */
    .preinit_array :
    {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } > FLASH

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > FLASH

    /* Initialized Data */
    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH

    _sidata = LOADADDR(.data);

    /* Zero-initialized Data */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        __bss_start__ = .;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end__ = .;
    } > RAM

    /* Heap */
    .heap (NOLOAD) :
    {
        . = ALIGN(8);
        __heap_start__ = .;
        . = . + __heap_size;
        __heap_end__ = .;
    } > RAM

    /* Stack */
    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        __stack_start__ = .;
        . = . + __stack_size;
        __stack_end__ = .;
        __StackTop = .;
    } > RAM

    /* Shared Memory for IPC */
    .shared (NOLOAD) :
    {
        . = ALIGN(4);
        *(.shared)
        . = ALIGN(4);
    } > SHARED

    /* Symbols for startup code */
    _end = .;
    PROVIDE(end = .);
}
