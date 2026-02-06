"""Microphone controller for audio recording with fallback to simulated mode

Hardware Setup:
- Any USB or built-in microphone
- Requires pyaudio package
"""

import threading
import time
import wave
from collections import deque
from io import BytesIO


class MicrophoneController:
    """Microphone controller with fallback to simulated mode"""

    def __init__(self, sample_rate=44100, channels=1, chunk_size=1024):
        """Initialize microphone controller

        Args:
            sample_rate: Audio sample rate in Hz (default: 44100)
            channels: Number of audio channels (default: 1 for mono)
            chunk_size: Size of audio chunks to read (default: 1024)
        """
        self.sample_rate = sample_rate
        self.channels = channels
        self.chunk_size = chunk_size
        self.use_fake = False
        self.pyaudio = None
        self.stream = None
        self.device_index = None

        # Recording state
        self.running = False
        self.thread = None
        self._lock = threading.Lock()

        # Audio buffer (stores last 10 seconds of audio)
        buffer_chunks = int(10 * sample_rate / chunk_size)
        self.audio_buffer = deque(maxlen=buffer_chunks)

    def start(self, device_index=None):
        """Initialize and start the microphone

        Args:
            device_index: Specific device index to use (None = default device)
        """
        try:
            import pyaudio

            self.pyaudio = pyaudio.PyAudio()

            # Find available input device if not specified
            if device_index is None:
                device_index = self._find_input_device()

            if device_index is None:
                raise RuntimeError("No input audio devices found")

            self.device_index = device_index

            # Get device info
            device_info = self.pyaudio.get_device_info_by_index(device_index)
            device_name = device_info.get('name', 'Unknown')

            # Open audio stream
            self.stream = self.pyaudio.open(
                format=pyaudio.paInt16,
                channels=self.channels,
                rate=self.sample_rate,
                input=True,
                input_device_index=device_index,
                frames_per_buffer=self.chunk_size,
                stream_callback=self._audio_callback
            )

            self.use_fake = False
            print(f"Microphone connected: {device_name} (device {device_index})")

        except Exception as e:
            print(f"Microphone unavailable ({e}), using simulated mode")
            self.use_fake = True

        # Start recording thread
        self.running = True
        self.thread = threading.Thread(target=self._recording_loop, daemon=True)
        self.thread.start()

    def stop(self):
        """Stop the microphone and clean up resources"""
        self.running = False

        if self.thread:
            self.thread.join(timeout=2)

        if self.stream:
            self.stream.stop_stream()
            self.stream.close()

        if self.pyaudio:
            self.pyaudio.terminate()

        print("Microphone stopped")

    def _find_input_device(self):
        """Find the first available input audio device

        Returns:
            Device index or None if no input device found
        """
        if not self.pyaudio:
            return None

        for i in range(self.pyaudio.get_device_count()):
            device_info = self.pyaudio.get_device_info_by_index(i)
            if device_info.get('maxInputChannels', 0) > 0:
                return i

        return None

    def list_devices(self):
        """List all available audio devices

        Returns:
            List of (index, name, channels) tuples for input devices
        """
        devices = []

        if not self.pyaudio:
            return devices

        for i in range(self.pyaudio.get_device_count()):
            device_info = self.pyaudio.get_device_info_by_index(i)
            channels = device_info.get('maxInputChannels', 0)

            if channels > 0:
                name = device_info.get('name', 'Unknown')
                devices.append((i, name, channels))

        return devices

    def _audio_callback(self, in_data, frame_count, time_info, status):
        """PyAudio callback to capture audio data"""
        if self.running:
            with self._lock:
                self.audio_buffer.append(in_data)

        import pyaudio
        return (None, pyaudio.paContinue)

    def _recording_loop(self):
        """Background thread for simulated mode"""
        while self.running:
            if self.use_fake:
                # Simulate audio data in fake mode
                with self._lock:
                    fake_data = b'\x00' * (self.chunk_size * 2)  # 16-bit samples
                    self.audio_buffer.append(fake_data)
                time.sleep(self.chunk_size / self.sample_rate)
            else:
                # Real mode uses callback, just sleep
                time.sleep(0.1)

    def get_audio_chunk(self, duration=5):
        """Get recent audio data as bytes

        Args:
            duration: Duration in seconds to retrieve (default: 5)

        Returns:
            bytes: Raw audio data (PCM 16-bit)
        """
        chunks_needed = int(duration * self.sample_rate / self.chunk_size)

        with self._lock:
            # Get last N chunks from buffer
            recent_chunks = list(self.audio_buffer)[-chunks_needed:]

        return b''.join(recent_chunks)

    def get_audio_wav(self, duration=5):
        """Get recent audio data as WAV format bytes

        Args:
            duration: Duration in seconds to retrieve (default: 5)

        Returns:
            BytesIO: WAV file data
        """
        audio_data = self.get_audio_chunk(duration)

        # Create WAV file in memory
        wav_buffer = BytesIO()
        with wave.open(wav_buffer, 'wb') as wav_file:
            wav_file.setnchannels(self.channels)
            wav_file.setsampwidth(2)  # 16-bit = 2 bytes
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(audio_data)

        wav_buffer.seek(0)
        return wav_buffer

    def save_audio(self, filename, duration=5):
        """Save recent audio to a WAV file

        Args:
            filename: Output filename (should end in .wav)
            duration: Duration in seconds to save (default: 5)
        """
        audio_data = self.get_audio_chunk(duration)

        with wave.open(filename, 'wb') as wav_file:
            wav_file.setnchannels(self.channels)
            wav_file.setsampwidth(2)  # 16-bit = 2 bytes
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(audio_data)

        print(f"Audio saved to {filename}")

    @property
    def is_recording(self):
        """Check if microphone is actively recording"""
        return self.running and (self.stream is not None or self.use_fake)

    @property
    def is_fake(self):
        """Whether using simulated mode (no hardware available)"""
        return self.use_fake

    @property
    def buffer_duration(self):
        """Get current buffer duration in seconds"""
        with self._lock:
            chunk_count = len(self.audio_buffer)

        return (chunk_count * self.chunk_size) / self.sample_rate


# For standalone testing
if __name__ == "__main__":
    mic = MicrophoneController()

    # List available devices
    if not mic.use_fake:
        print("\nAvailable audio input devices:")
        try:
            import pyaudio
            pa = pyaudio.PyAudio()
            mic.pyaudio = pa
            devices = mic.list_devices()
            for idx, name, channels in devices:
                print(f"  [{idx}] {name} ({channels} channels)")
            pa.terminate()
        except Exception as e:
            print(f"Could not list devices: {e}")

    # Start recording
    mic.start()

    try:
        print(f"\nRecording for 10 seconds...")
        print(f"Mode: {'SIMULATED' if mic.is_fake else 'REAL'}")

        for i in range(10):
            time.sleep(1)
            buffer_sec = mic.buffer_duration
            print(f"  {i+1}s - Buffer: {buffer_sec:.1f}s")

        # Save a 5-second clip
        output_file = "test_recording.wav"
        mic.save_audio(output_file, duration=5)
        print(f"\nSaved 5-second clip to {output_file}")

    except KeyboardInterrupt:
        print("\nRecording interrupted")
    finally:
        mic.stop()
        print("Test complete")
