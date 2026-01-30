# ls -l /dev/serial0
# should show: /dev/serial0 -> ttyS0 or ttyAMA0

# Make sure bluetooth isn't hogging it (Pi 4):
# sudo nano /boot/firmware/config.txt
# Add:
# dtoverlay=disable-bt

# sudo systemctl disable hciuart
# sudo reboot

import serial
import pynmea2

ser = serial.Serial('/dev/serial0', baudrate=9600, timeout=1)

def compass_dir(deg):
    dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
    return dirs[int((deg + 22.5) % 360 // 45)]

data = {'sats': 0, 'speed': 0, 'heading': 0, 'lat': 0, 'lon': 0}

while True:
    line = ser.readline().decode('ascii', errors='replace').strip()
    try:
        if line.startswith('$GPGGA'):
            msg = pynmea2.parse(line)
            data['sats'] = int(msg.num_sats or 0)
            data['lat'] = msg.latitude
            data['lon'] = msg.longitude
            
        elif line.startswith('$GPRMC'):
            msg = pynmea2.parse(line)
            data['speed'] = (msg.spd_over_grnd or 0) * 1.151  # knots to mph
            data['heading'] = msg.true_course or 0
            
            print(f"Sats: {data['sats']} | "
                  f"Speed: {data['speed']:.1f} mph | "
                  f"Heading: {data['heading']:.0f}° {compass_dir(data['heading'])} | "
                  f"Lat: {data['lat']:.6f} | "
                  f"Lon: {data['lon']:.6f}")
    except:
        pass
