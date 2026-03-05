"""BLE GATT Server for Raspberry Pi — iOS direct communication

Advertises a custom GATT service so the iOS app can read realtime data,
write settings/buzzer commands, and subscribe to notifications — all
without internet.  Falls back to a no-op simulated mode when the `bless`
library or BLE hardware is unavailable.

Requires: pip install bless
Hardware note: RPi 4 shares UART between BT and GPIO serial.  To use BLE
alongside a serial GPS, switch to `dtoverlay=miniuart-bt` in config.txt
(gives BLE the mini UART, GPS keeps PL011) or use a USB GPS adapter.
"""

import asyncio
import json
import threading
import time

# Custom service / characteristic UUIDs
SERVICE_UUID = "A1B2C3D4-E5F6-7890-ABCD-1234567890AB"
CHAR_REALTIME_UUID = "A1B2C3D4-E5F6-7890-ABCD-123456780001"
CHAR_SETTINGS_UUID = "A1B2C3D4-E5F6-7890-ABCD-123456780002"
CHAR_BUZZER_UUID = "A1B2C3D4-E5F6-7890-ABCD-123456780003"
CHAR_TRIP_UUID = "A1B2C3D4-E5F6-7890-ABCD-123456780004"
CHAR_RELAY_UUID = "A1B2C3D4-E5F6-7890-ABCD-123456780005"

DEVICE_NAME = "InfineonDMS"


class BluetoothServer:
    """BLE GATT peripheral that exposes vehicle data to the iOS app."""

    def __init__(self, device_name=DEVICE_NAME, on_settings_write=None, on_buzzer_write=None):
        self._device_name = device_name
        self._on_settings_write = on_settings_write
        self._on_buzzer_write = on_buzzer_write

        self._use_fake = False
        self._server = None
        self._loop = None
        self._thread = None
        self._connected = False
        self._lock = threading.Lock()

        # Cached payloads (compact JSON bytes, <200 B each)
        self._realtime_bytes = b"{}"
        self._settings_bytes = b"{}"
        self._trip_bytes = b"{}"
        self._relay_bytes = b"{}"

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self):
        """Start the BLE GATT server in a background daemon thread."""
        try:
            from bless import BlessServer  # noqa: F401 — availability check
        except ImportError as e:
            print(f"BLE unavailable (bless not installed: {e}), using simulated mode")
            self._use_fake = True
            return
        except Exception as e:
            print(f"BLE unavailable ({e}), using simulated mode")
            self._use_fake = True
            return

        self._thread = threading.Thread(target=self._run_server, daemon=True)
        self._thread.start()

    def stop(self):
        """Shut down the BLE server."""
        if self._use_fake:
            return
        if self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=3)
            self._thread = None
        print("[BLE] Server stopped")

    def update_realtime(self, data: dict):
        """Push new realtime data — triggers BLE notify if a client is subscribed."""
        payload = self._compact_realtime(data)
        with self._lock:
            self._realtime_bytes = payload
        if not self._use_fake and self._server and self._connected:
            self._schedule_notify(CHAR_REALTIME_UUID, payload)

    def update_settings(self, data: dict):
        """Cache the current feature settings for BLE reads."""
        payload = self._compact_settings(data)
        with self._lock:
            self._settings_bytes = payload

    def update_trip(self, data: dict):
        """Push new trip stats — triggers BLE notify if a client is subscribed."""
        payload = self._compact_trip(data)
        with self._lock:
            self._trip_bytes = payload
        if not self._use_fake and self._server and self._connected:
            self._schedule_notify(CHAR_TRIP_UUID, payload)

    def update_relay(self, data: dict):
        """Push Supabase-format data for iOS relay — triggers BLE notify.

        When the Pi has no internet, the iOS app reads this characteristic and
        uploads the data to Supabase on the Pi's behalf.
        """
        payload = json.dumps(data, separators=(",", ":")).encode("utf-8")
        with self._lock:
            self._relay_bytes = payload
        if not self._use_fake and self._server and self._connected:
            self._schedule_notify(CHAR_RELAY_UUID, payload)

    @property
    def is_connected(self):
        return self._connected

    @property
    def is_fake(self):
        return self._use_fake

    # ------------------------------------------------------------------
    # Internal — async server
    # ------------------------------------------------------------------

    def _run_server(self):
        """Entry point for the daemon thread — runs the async event loop."""
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._serve())
        except Exception as e:
            print(f"[BLE] Server error: {e}")
            self._use_fake = True

    async def _serve(self):
        from bless import BlessServer, BlessGATTCharacteristic, GATTCharacteristicProperties, GATTAttributePermissions

        self._server = BlessServer(name=self._device_name, loop=self._loop)
        self._server.read_request_func = self._on_read
        self._server.write_request_func = self._on_write

        await self._server.add_new_service(SERVICE_UUID)

        # Realtime — Read + Notify
        await self._server.add_new_characteristic(
            SERVICE_UUID, CHAR_REALTIME_UUID,
            GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
            None,
            GATTAttributePermissions.readable,
        )

        # Settings — Read + Write
        await self._server.add_new_characteristic(
            SERVICE_UUID, CHAR_SETTINGS_UUID,
            GATTCharacteristicProperties.read | GATTCharacteristicProperties.write,
            None,
            GATTAttributePermissions.readable | GATTAttributePermissions.writeable,
        )

        # Buzzer — Write only
        await self._server.add_new_characteristic(
            SERVICE_UUID, CHAR_BUZZER_UUID,
            GATTCharacteristicProperties.write,
            None,
            GATTAttributePermissions.writeable,
        )

        # Trip — Read + Notify
        await self._server.add_new_characteristic(
            SERVICE_UUID, CHAR_TRIP_UUID,
            GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
            None,
            GATTAttributePermissions.readable,
        )

        # Relay — Read + Notify (iOS relays this data to Supabase when Pi is offline)
        await self._server.add_new_characteristic(
            SERVICE_UUID, CHAR_RELAY_UUID,
            GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
            None,
            GATTAttributePermissions.readable,
        )

        await self._server.start()
        print(f"[BLE] GATT server advertising as '{self._device_name}'")

        # Keep running until loop is stopped
        try:
            while True:
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass
        finally:
            await self._server.stop()

    # ------------------------------------------------------------------
    # GATT callbacks
    # ------------------------------------------------------------------

    def _on_read(self, characteristic, **kwargs):
        uuid = str(characteristic.uuid).upper()
        with self._lock:
            if uuid == CHAR_REALTIME_UUID:
                characteristic.value = self._realtime_bytes
            elif uuid == CHAR_SETTINGS_UUID:
                characteristic.value = self._settings_bytes
            elif uuid == CHAR_TRIP_UUID:
                characteristic.value = self._trip_bytes
            elif uuid == CHAR_RELAY_UUID:
                characteristic.value = self._relay_bytes

    def _on_write(self, characteristic, value, **kwargs):
        uuid = str(characteristic.uuid).upper()
        try:
            data = json.loads(bytes(value).decode("utf-8"))
        except Exception as e:
            print(f"[BLE] Bad write payload on {uuid}: {e}")
            return

        if uuid == CHAR_SETTINGS_UUID:
            print(f"[BLE] Settings write received: {data}")
            if self._on_settings_write:
                self._on_settings_write(data)
        elif uuid == CHAR_BUZZER_UUID:
            print(f"[BLE] Buzzer command received: {data}")
            if self._on_buzzer_write:
                self._on_buzzer_write(data)

    # ------------------------------------------------------------------
    # Notify helper
    # ------------------------------------------------------------------

    def _schedule_notify(self, char_uuid, payload):
        """Thread-safe: schedule a notify on the async loop."""
        if self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(
                self._loop.create_task,
                self._do_notify(char_uuid, payload),
            )

    async def _do_notify(self, char_uuid, payload):
        if self._server:
            try:
                self._server.get_characteristic(char_uuid).value = payload
                self._server.update_value(SERVICE_UUID, char_uuid)
            except Exception as e:
                print(f"[BLE] Notify error ({char_uuid[-4:]}): {e}")

    # ------------------------------------------------------------------
    # Compact JSON builders — keep payloads <200 bytes for BLE MTU
    # ------------------------------------------------------------------

    @staticmethod
    def _compact_realtime(d: dict) -> bytes:
        compact = {
            "spd": int(d.get("speed_mph", 0)),
            "hdg": int(d.get("heading_degrees", 0)),
            "lat": round(float(d.get("latitude", 0) or 0), 4),
            "lng": round(float(d.get("longitude", 0) or 0), 4),
            "dir": str(d.get("compass_direction", "N")),
            "ds": str(d.get("driver_status", "unknown")),
            "ph": bool(d.get("is_phone_detected", False)),
            "dr": bool(d.get("is_drinking_detected", False)),
            "ix": int(d.get("intoxication_score", 0)),
            "sp": bool(d.get("is_speeding", False)),
            "sat": int(d.get("satellites", 0)),
        }
        return json.dumps(compact, separators=(",", ":")).encode("utf-8")

    @staticmethod
    def _compact_settings(d: dict) -> bytes:
        compact = {
            "yolo": bool(d.get("enable_yolo", True)),
            "stream": bool(d.get("enable_stream", True)),
            "shazam": bool(d.get("enable_shazam", True)),
            "mic": bool(d.get("enable_microphone", True)),
            "cam": bool(d.get("enable_camera", True)),
            "dash": bool(d.get("enable_dashcam", False)),
        }
        return json.dumps(compact, separators=(",", ":")).encode("utf-8")

    @staticmethod
    def _compact_trip(d: dict) -> bytes:
        compact = {
            "tid": str(d.get("trip_id", "")),
            "dur": int(d.get("duration", 0)),
            "mx_spd": int(d.get("max_speed", 0)),
            "avg_spd": round(float(d.get("avg_speed", 0)), 1),
            "spd_ev": int(d.get("speeding_events", 0)),
            "drw_ev": int(d.get("drowsy_events", 0)),
            "ph_ev": int(d.get("phone_events", 0)),
            "ix_max": int(d.get("max_intox_score", 0)),
        }
        return json.dumps(compact, separators=(",", ":")).encode("utf-8")


# Standalone test
if __name__ == "__main__":
    import signal

    server = BluetoothServer()
    server.start()

    if server.is_fake:
        print("Running in simulated mode (no BLE hardware)")
    else:
        print("BLE server started — use nRF Connect to verify")

    # Push sample data every 2 seconds
    running = True

    def _stop(sig, frame):
        global running
        running = False

    signal.signal(signal.SIGINT, _stop)

    while running:
        server.update_realtime({
            "speed_mph": 55, "heading_degrees": 180, "latitude": 37.33,
            "longitude": -122.0, "compass_direction": "S", "driver_status": "normal",
            "is_phone_detected": False, "is_drinking_detected": False,
            "intoxication_score": 0, "is_speeding": False, "satellites": 8,
        })
        server.update_trip({
            "trip_id": "test", "duration": 600, "max_speed": 70,
            "avg_speed": 42.5, "speeding_events": 1, "drowsy_events": 0,
            "phone_events": 0, "max_intox_score": 1,
        })
        time.sleep(2)

    server.stop()
    print("Done")
