"""Buzzer controller for Raspberry Pi with fallback to print statements

Hardware Setup:
- Connect buzzer to GPIO pin 18 (BCM numbering)
- Buzzer spec: 4000Hz resonant frequency, 3.5V nominal
- See: https://www.edcon-components.com/Webside/LIE/500377/Originale/141-cet12a3.5-42-2.0.pdf
"""

import threading
import time


class BuzzerController:
    """Hardware buzzer controller with fallback to simulated mode"""

    def __init__(self, pin=18):
        self.pin = pin
        self.use_fake = False
        self.pwm = None
        self.gpio = None
        self._lock = threading.Lock()
        self.last_speeding_alert = 0
        self.last_drowsy_alert = 0
        self.alert_cooldown = 3.0  # 3 seconds between alerts

    def start(self):
        """Initialize the buzzer hardware"""
        try:
            import RPi.GPIO as GPIO

            self.gpio = GPIO
            self.gpio.setmode(GPIO.BCM)
            self.gpio.setup(self.pin, GPIO.OUT)
            self.use_fake = False
            print(f"Buzzer connected on GPIO pin {self.pin}")
        except Exception as e:
            print(f"Buzzer unavailable ({e}), using simulated mode (print statements)")
            self.use_fake = True

    def stop(self):
        """Clean up GPIO resources"""
        with self._lock:
            if self.pwm:
                self.pwm.stop()
                # del pwm # TODO: possible fix to issue when testing
                self.pwm = None
            if self.gpio and not self.use_fake:
                self.gpio.cleanup()

    def _play_tone(self, frequency, duration, duty_cycle=50):
        """Play a tone at specified frequency and duration

        Args:
            frequency: Frequency in Hz (buzzer optimized for ~4000Hz)
            duration: Duration in seconds
            duty_cycle: PWM duty cycle (0-100), 50 is recommended
        """
        with self._lock:
            if self.use_fake:
                print(f"[BUZZER SIMULATED] Playing {frequency}Hz tone for {duration}s")
                return

            try:
                # Create PWM instance
                self.pwm = self.gpio.PWM(self.pin, frequency)
                self.pwm.start(duty_cycle)
                time.sleep(duration)
                self.pwm.stop()
                self.pwm = None
            except Exception as e:
                print(f"Error playing buzzer tone: {e}")

    def play_speeding_alert(self):
        """Play speeding warning sound (single medium beep)"""
        current_time = time.time()
        if current_time - self.last_speeding_alert > self.alert_cooldown:
            # Use 900Hz for speeding alert (lower pitch, warning)
            self._play_tone(frequency=900, duration=0.4)
            print("[BUZZER] Speeding alert played")
            self.last_speeding_alert = current_time

    def play_drowsy_alert(self):
        """Play drowsy/intoxicated warning sound (urgent double beep)"""
        current_time = time.time()
        if current_time - self.last_drowsy_alert > self.alert_cooldown:
            # Use 1200Hz for urgent drowsy alert (higher pitch, urgent)
            self._play_tone(frequency=1200, duration=0.2)
            time.sleep(0.25)
            self._play_tone(frequency=1200, duration=0.2)
            print("[BUZZER] Drowsy alert played (double beep)")
            self.last_drowsy_alert = current_time

    def play_distraction_alert(self):
        """Play distraction warning sound (phone/drinking detected)"""
        current_time = time.time()
        if current_time - self.last_drowsy_alert > self.alert_cooldown:
            # Use 600Hz for distraction (lower pitch, caution)
            self._play_tone(frequency=600, duration=0.5)
            print("[BUZZER] Distraction alert played")
            self.last_drowsy_alert = current_time

    @property
    def is_fake(self):
        """Whether using simulated mode (no hardware available)"""
        return self.use_fake


# For standalone testing
if __name__ == "__main__":
    buzzer = BuzzerController()
    buzzer.start()

    try:
        print("Testing buzzer alerts...")
        print("\n1. Speeding alert...")
        buzzer.play_speeding_alert()
        time.sleep(2)

        print("\n2. Drowsy alert...")
        buzzer.play_drowsy_alert()
        time.sleep(2)

        print("\n3. Distraction alert...")
        buzzer.play_distraction_alert()
        time.sleep(2)

        print("\nBuzzer test complete!")
    except KeyboardInterrupt:
        print("\nTest interrupted")
    finally:
        buzzer.stop()
        print("Buzzer stopped")
