# Makefile for Infineon PSoC 6 AI Evaluation Kit
# Driver Monitoring System Firmware
#
# Standalone Makefile for use without ModusToolbox IDE
# For full MTB integration, use the application.mk system

################################################################################
# Project Configuration
################################################################################

PROJECT_NAME := driver_monitor
VERSION := 1.0.0

# Target hardware
TARGET_BOARD := CY8CKIT-062S2-AI
TARGET_DEVICE := CY8C624ABZI-S2D44
TARGET_CORE := CM4

################################################################################
# Toolchain Configuration
################################################################################

# Arm GNU Toolchain (installed via Homebrew or download)
TOOLCHAIN_PATH ?= /opt/homebrew/bin
CC := $(TOOLCHAIN_PATH)/arm-none-eabi-gcc
CXX := $(TOOLCHAIN_PATH)/arm-none-eabi-g++
AS := $(TOOLCHAIN_PATH)/arm-none-eabi-as
LD := $(TOOLCHAIN_PATH)/arm-none-eabi-gcc
OBJCOPY := $(TOOLCHAIN_PATH)/arm-none-eabi-objcopy
OBJDUMP := $(TOOLCHAIN_PATH)/arm-none-eabi-objdump
SIZE := $(TOOLCHAIN_PATH)/arm-none-eabi-size

################################################################################
# ModusToolbox Paths (adjust for your installation)
################################################################################

MTB_TOOLS_DIR ?= $(HOME)/ModusToolbox/tools_3.2
MTB_LIBS_DIR ?= $(HOME)/mtb_shared

# PSoC 6 PDL and HAL
PDL_DIR := $(MTB_LIBS_DIR)/mtb-pdl-cat1/release-v3.12.0
HAL_DIR := $(MTB_LIBS_DIR)/mtb-hal-cat1/release-v2.6.1
BSP_DIR := $(MTB_LIBS_DIR)/TARGET_$(TARGET_BOARD)/release-v1.0.0

# TensorFlow Lite Micro
TFLM_DIR := $(MTB_LIBS_DIR)/ml-middleware/release-v3.0.0
CMSIS_DIR := $(MTB_LIBS_DIR)/cmsis/release-v5.8.0

################################################################################
# Build Configuration
################################################################################

BUILD_DIR := build
DEBUG ?= 1

ifeq ($(DEBUG), 1)
    BUILD_TYPE := Debug
    OPT_FLAGS := -O0 -g3
    DEFINES += -DDEBUG
else
    BUILD_TYPE := Release
    OPT_FLAGS := -O2
    DEFINES += -DNDEBUG
endif

################################################################################
# Compiler Flags
################################################################################

# CPU flags for Cortex-M4 with FPU
CPU_FLAGS := -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16

# Warning flags
WARN_FLAGS := -Wall -Wextra -Wno-unused-parameter

# C flags
CFLAGS := $(CPU_FLAGS) $(OPT_FLAGS) $(WARN_FLAGS)
CFLAGS += -std=c11 -ffunction-sections -fdata-sections

# C++ flags
CXXFLAGS := $(CPU_FLAGS) $(OPT_FLAGS) $(WARN_FLAGS)
CXXFLAGS += -std=c++17 -ffunction-sections -fdata-sections -fno-rtti -fno-exceptions

# Assembler flags
ASFLAGS := $(CPU_FLAGS) -g

# Linker flags
LDFLAGS := $(CPU_FLAGS) -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/$(PROJECT_NAME).map
LDFLAGS += -specs=nano.specs -specs=nosys.specs

################################################################################
# Defines
################################################################################

DEFINES += -DCY8C624ABZI_S2D44
DEFINES += -DCOMPONENT_CAT1A
DEFINES += -DCOMPONENT_CM4
DEFINES += -DCORE_NAME_CM4_0
DEFINES += -DCY_USING_HAL
DEFINES += -DTF_LITE_STATIC_MEMORY
DEFINES += -DCMSIS_NN
DEFINES += -DARM_MATH_CM4
DEFINES += -D__FPU_PRESENT=1

################################################################################
# Include Paths
################################################################################

INCLUDES := -Iinclude
INCLUDES += -Imodels
INCLUDES += -I$(PDL_DIR)/devices/COMPONENT_CAT1A/include
INCLUDES += -I$(PDL_DIR)/drivers/include
INCLUDES += -I$(HAL_DIR)/include
INCLUDES += -I$(HAL_DIR)/COMPONENT_CAT1/include
INCLUDES += -I$(CMSIS_DIR)/CMSIS/Core/Include
INCLUDES += -I$(TFLM_DIR)/source

################################################################################
# Source Files
################################################################################

# Application sources
APP_SOURCES := \
    src/main.c \
    src/face_detector.c \
    src/eye_analyzer.c \
    src/alert_system.c \
    src/camera_driver.c

# Model data (generated)
MODEL_SOURCES := \
    models/face_detection_model.c

# Collect all sources
C_SOURCES := $(filter %.c, $(APP_SOURCES) $(MODEL_SOURCES))
CXX_SOURCES := $(filter %.cpp, $(APP_SOURCES))
ASM_SOURCES := $(filter %.s %.S, $(APP_SOURCES))

################################################################################
# Object Files
################################################################################

C_OBJECTS := $(patsubst %.c, $(BUILD_DIR)/%.o, $(notdir $(C_SOURCES)))
CXX_OBJECTS := $(patsubst %.cpp, $(BUILD_DIR)/%.o, $(notdir $(CXX_SOURCES)))
ASM_OBJECTS := $(patsubst %.s, $(BUILD_DIR)/%.o, $(notdir $(ASM_SOURCES)))
OBJECTS := $(C_OBJECTS) $(CXX_OBJECTS) $(ASM_OBJECTS)

VPATH := $(sort $(dir $(APP_SOURCES) $(MODEL_SOURCES)))

################################################################################
# Linker Script
################################################################################

LDSCRIPT := config/linker_script.ld

################################################################################
# Targets
################################################################################

.PHONY: all clean flash debug size help

all: $(BUILD_DIR)/$(PROJECT_NAME).hex $(BUILD_DIR)/$(PROJECT_NAME).bin
	@echo ""
	@echo "Build complete: $(BUILD_TYPE)"
	@$(SIZE) $(BUILD_DIR)/$(PROJECT_NAME).elf

$(BUILD_DIR):
	@mkdir -p $@

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	@echo "CC  $<"
	@$(CC) $(CFLAGS) $(DEFINES) $(INCLUDES) -c $< -o $@

$(BUILD_DIR)/%.o: %.cpp | $(BUILD_DIR)
	@echo "CXX $<"
	@$(CXX) $(CXXFLAGS) $(DEFINES) $(INCLUDES) -c $< -o $@

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	@echo "AS  $<"
	@$(AS) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR)/$(PROJECT_NAME).elf: $(OBJECTS)
	@echo "LD  $@"
	@$(LD) $(LDFLAGS) -T$(LDSCRIPT) $^ -o $@ -lm

$(BUILD_DIR)/$(PROJECT_NAME).hex: $(BUILD_DIR)/$(PROJECT_NAME).elf
	@echo "HEX $@"
	@$(OBJCOPY) -O ihex $< $@

$(BUILD_DIR)/$(PROJECT_NAME).bin: $(BUILD_DIR)/$(PROJECT_NAME).elf
	@echo "BIN $@"
	@$(OBJCOPY) -O binary $< $@

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)

flash: $(BUILD_DIR)/$(PROJECT_NAME).hex
	@echo "Flashing to target..."
	openocd -f interface/kitprog3.cfg -f target/psoc6_2m.cfg \
		-c "program $< verify reset exit"

debug:
	@echo "Starting debug server..."
	openocd -f interface/kitprog3.cfg -f target/psoc6_2m.cfg

size: $(BUILD_DIR)/$(PROJECT_NAME).elf
	@$(SIZE) --format=berkeley $<

help:
	@echo "Infineon PSoC 6 Driver Monitoring System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build firmware (default)"
	@echo "  clean   - Remove build artifacts"
	@echo "  flash   - Program firmware to target"
	@echo "  debug   - Start OpenOCD debug server"
	@echo "  size    - Show memory usage"
	@echo "  help    - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  DEBUG=1 - Build with debug symbols (default)"
	@echo "  DEBUG=0 - Build with optimizations"
	@echo ""
	@echo "Example:"
	@echo "  make DEBUG=0 flash"
