"""Shazam music recognition using the shazamio library

Identifies songs from audio data using Shazam's recognition service.
Requires: pip install shazamio
"""

import asyncio
import time
from typing import Optional


class ShazamRecognizer:
    """Music recognition using Shazam API"""

    def __init__(self):
        """Initialize Shazam recognizer"""
        self.shazam = None
        self.use_fake = False
        self.last_recognition = None
        self.last_recognition_time = 0
        self.recognition_cooldown = 5.0  # Minimum 5 seconds between recognitions

    def start(self):
        """Initialize the Shazam client"""
        try:
            from shazamio import Shazam

            self.shazam = Shazam()
            self.use_fake = False
            print("Shazam recognizer initialized")
        except ImportError as e:
            print(f"Shazam library unavailable ({e}), using simulated mode")
            print("Install with: pip install shazamio")
            self.use_fake = True
        except Exception as e:
            print(f"Shazam initialization failed ({e}), using simulated mode")
            self.use_fake = True

    def recognize_from_file(self, audio_file_path: str) -> Optional[dict]:
        """Recognize song from an audio file

        Args:
            audio_file_path: Path to audio file (WAV, MP3, etc.)

        Returns:
            Dictionary with song info or None if not recognized
            {
                'title': str,
                'artist': str,
                'album': str (optional),
                'release_year': str (optional),
                'genres': list (optional),
                'label': str (optional),
                'shazam_url': str,
                'apple_music_url': str (optional),
                'spotify_url': str (optional),
            }
        """
        # Rate limiting
        current_time = time.time()
        if current_time - self.last_recognition_time < self.recognition_cooldown:
            print("Recognition rate limited, waiting...")
            time.sleep(self.recognition_cooldown - (current_time - self.last_recognition_time))

        if self.use_fake:
            return self._fake_recognition()

        try:
            # Run async recognition
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(self.shazam.recognize(audio_file_path))
            loop.close()

            self.last_recognition_time = time.time()

            if not result or 'track' not in result:
                print("No match found")
                return None

            # Parse the result
            track = result['track']
            song_info = self._parse_track_info(track)
            self.last_recognition = song_info

            return song_info

        except Exception as e:
            print(f"Error during recognition: {e}")
            return None

    def recognize_from_bytes(self, audio_bytes: bytes) -> Optional[dict]:
        """Recognize song from raw audio bytes

        Args:
            audio_bytes: Raw audio data (WAV format recommended)

        Returns:
            Dictionary with song info or None if not recognized
        """
        # Save to temporary file since shazamio works with files
        import tempfile
        import os

        temp_file = None
        try:
            # Create temporary file
            with tempfile.NamedTemporaryFile(mode='wb', suffix='.wav', delete=False) as f:
                temp_file = f.name
                f.write(audio_bytes)

            # Recognize from temp file
            result = self.recognize_from_file(temp_file)

            return result

        finally:
            # Clean up temp file
            if temp_file and os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except Exception:
                    pass

    def _parse_track_info(self, track: dict) -> dict:
        """Parse Shazam track info into simplified format

        Args:
            track: Raw track data from Shazam API

        Returns:
            Simplified song info dictionary
        """
        song_info = {
            'title': track.get('title', 'Unknown'),
            'artist': track.get('subtitle', 'Unknown Artist'),
            'shazam_url': track.get('url', ''),
        }

        # Optional metadata
        if 'sections' in track:
            for section in track['sections']:
                section_type = section.get('type', '')

                # Get metadata section
                if section_type == 'SONG':
                    metadata = section.get('metadata', [])
                    for item in metadata:
                        title = item.get('title', '').lower()
                        text = item.get('text', '')

                        if 'album' in title:
                            song_info['album'] = text
                        elif 'released' in title or 'release' in title:
                            song_info['release_year'] = text
                        elif 'label' in title:
                            song_info['label'] = text

        # Get genres
        if 'genres' in track:
            primary = track['genres'].get('primary', '')
            if primary:
                song_info['genres'] = [primary]

        # Get streaming URLs
        if 'hub' in track and 'providers' in track['hub']:
            for provider in track['hub']['providers']:
                provider_type = provider.get('type', '').lower()

                if 'applemusic' in provider_type:
                    actions = provider.get('actions', [])
                    if actions:
                        song_info['apple_music_url'] = actions[0].get('uri', '')

        # Spotify URL (if available in shares)
        if 'share' in track and 'href' in track['share']:
            share_url = track['share']['href']
            if 'spotify' in share_url:
                song_info['spotify_url'] = share_url

        return song_info

    def _fake_recognition(self) -> dict:
        """Return fake song data for testing"""
        fake_songs = [
            {
                'title': 'Bohemian Rhapsody',
                'artist': 'Queen',
                'album': 'A Night at the Opera',
                'release_year': '1975',
                'genres': ['Rock'],
                'shazam_url': 'https://www.shazam.com/track/123456',
            },
            {
                'title': 'Blinding Lights',
                'artist': 'The Weeknd',
                'album': 'After Hours',
                'release_year': '2019',
                'genres': ['Pop'],
                'shazam_url': 'https://www.shazam.com/track/789012',
            },
            {
                'title': 'Hotel California',
                'artist': 'Eagles',
                'album': 'Hotel California',
                'release_year': '1976',
                'genres': ['Rock'],
                'shazam_url': 'https://www.shazam.com/track/345678',
            },
        ]

        import random
        return random.choice(fake_songs)

    def format_song_info(self, song_info: dict) -> str:
        """Format song info as a readable string

        Args:
            song_info: Song information dictionary

        Returns:
            Formatted string
        """
        if not song_info:
            return "No song recognized"

        lines = [
            f"🎵 {song_info['title']}",
            f"🎤 {song_info['artist']}",
        ]

        if 'album' in song_info:
            lines.append(f"💿 {song_info['album']}")

        if 'release_year' in song_info:
            lines.append(f"📅 {song_info['release_year']}")

        if 'genres' in song_info:
            lines.append(f"🎸 {', '.join(song_info['genres'])}")

        if 'shazam_url' in song_info:
            lines.append(f"🔗 {song_info['shazam_url']}")

        return '\n'.join(lines)

    def get_last_recognition(self) -> Optional[dict]:
        """Get the last successfully recognized song

        Returns:
            Last song info or None
        """
        return self.last_recognition

    @property
    def is_fake(self):
        """Whether using simulated mode (no Shazam API available)"""
        return self.use_fake

    @property
    def is_ready(self):
        """Check if recognizer is ready to use"""
        return self.shazam is not None or self.use_fake


# For standalone testing
if __name__ == "__main__":
    import sys

    recognizer = ShazamRecognizer()
    recognizer.start()

    if len(sys.argv) > 1:
        audio_file = sys.argv[1]
        print(f"\nRecognizing song from: {audio_file}")
        print(f"Mode: {'SIMULATED' if recognizer.is_fake else 'REAL'}\n")

        song_info = recognizer.recognize_from_file(audio_file)

        if song_info:
            print("✓ Song recognized!")
            print(recognizer.format_song_info(song_info))
        else:
            print("✗ Could not recognize song")
    else:
        print("\nShazam Recognizer Test")
        print(f"Mode: {'SIMULATED' if recognizer.is_fake else 'REAL'}")
        print("\nUsage: python shazam.py <audio_file>")
        print("Example: python shazam.py test_recording.wav")

        # Demo fake mode
        if recognizer.is_fake:
            print("\n--- Simulated Recognition ---")
            song_info = recognizer.recognize_from_file("fake.wav")
            print(recognizer.format_song_info(song_info))
