#!/usr/bin/env python3
"""tools/xpad.py -- a virtual Xbox 360 controller, driven over a local TCP socket, for testing
Ess.Input.hijackController (and anything else in this project that reads real controller input).

Requires: `pip install vgamepad` + the ViGEmBus driver (a kernel-mode virtual-gamepad driver from the
open-source ViGEm project; vgamepad bundles its installer at
<site-packages>/vgamepad/win/vigem/install/x64/ViGEmBusSetup_x64.msi -- run that once, elevated, if
`python -c "import vgamepad; vgamepad.VX360Gamepad()"` doesn't work cleanly).

-------------------------------------------------------------------------------------------------
THE QUIRK THIS TOOL IS BUILT AROUND: Mercenaries 2 only detects a controller that was ALREADY present
when the game launched -- plugging one in after the game is already running does not get picked up.
So the workflow is always:

    1. Start the SERVER first (creates the virtual pad -- this IS "plugging it in"):
         python tools/xpad.py serve
       Leave it running. It keeps the virtual pad connected for as long as the process lives.

    2. THEN launch the game (or have it already configured to launch with a controller expected).

    3. Send it input from anywhere, any number of times, for the rest of the session:
         python tools/xpad.py send PRESS A
         python tools/xpad.py send TAP B 0.2
         python tools/xpad.py send STICK L 0.5 -1.0
         python tools/xpad.py send RESET

    4. `python tools/xpad.py send QUIT` when you're done (unplugs the virtual pad + stops the server).

Never restart the server mid-session unless you're also relaunching the game -- restarting it
disconnects and recreates the virtual pad, which is exactly the "unplugged after launch" case the game
won't notice.
-------------------------------------------------------------------------------------------------

PROTOCOL (plain text, one command per connection, newline-terminated, single-line reply):
    PRESS <btn>                 hold a button down
    RELEASE <btn>                let a button go
    TAP <btn> [seconds=0.1]      press, wait, release (blocks the server for `seconds` -- keep it short)
    STICK <L|R> <x> <y>          set a thumbstick, x/y each in [-1.0, 1.0]
    TRIGGER <L|R> <value>        set an analog trigger, value in [0.0, 1.0]
    RESET                        release everything, center both sticks, zero both triggers
    PING                         -> PONG (liveness check)
    QUIT                         disconnects the virtual pad and stops the server

Buttons: A B X Y LB RB LSTICK RSTICK START BACK GUIDE UP DOWN LEFT RIGHT   (dpad = UP/DOWN/LEFT/RIGHT)

Usage:
    python tools/xpad.py serve [--port 27051]
    python tools/xpad.py send <COMMAND...> [--port 27051]
"""
import socket
import sys
import time

DEFAULT_PORT = 27051
HOST = "127.0.0.1"

BUTTONS = None  # populated lazily so `send` mode (no vgamepad object needed) doesn't require the driver


def _button_map():
    global BUTTONS
    if BUTTONS is None:
        import vgamepad as vg
        B = vg.XUSB_BUTTON
        BUTTONS = {
            "A": B.XUSB_GAMEPAD_A, "B": B.XUSB_GAMEPAD_B, "X": B.XUSB_GAMEPAD_X, "Y": B.XUSB_GAMEPAD_Y,
            "LB": B.XUSB_GAMEPAD_LEFT_SHOULDER, "RB": B.XUSB_GAMEPAD_RIGHT_SHOULDER,
            "LSTICK": B.XUSB_GAMEPAD_LEFT_THUMB, "RSTICK": B.XUSB_GAMEPAD_RIGHT_THUMB,
            "START": B.XUSB_GAMEPAD_START, "BACK": B.XUSB_GAMEPAD_BACK, "GUIDE": B.XUSB_GAMEPAD_GUIDE,
            "UP": B.XUSB_GAMEPAD_DPAD_UP, "DOWN": B.XUSB_GAMEPAD_DPAD_DOWN,
            "LEFT": B.XUSB_GAMEPAD_DPAD_LEFT, "RIGHT": B.XUSB_GAMEPAD_DPAD_RIGHT,
        }
    return BUTTONS


def _handle(gp, line):
    parts = line.strip().split()
    if not parts:
        return "ERR empty command"
    cmd = parts[0].upper()
    try:
        if cmd == "PING":
            return "PONG"
        if cmd == "QUIT":
            return "BYE"
        if cmd == "RESET":
            gp.reset()
            gp.update()
            return "OK"
        if cmd in ("PRESS", "RELEASE"):
            btn = _button_map().get(parts[1].upper())
            if btn is None:
                return "ERR unknown button " + parts[1]
            if cmd == "PRESS":
                gp.press_button(button=btn)
            else:
                gp.release_button(button=btn)
            gp.update()
            return "OK"
        if cmd == "TAP":
            btn = _button_map().get(parts[1].upper())
            if btn is None:
                return "ERR unknown button " + parts[1]
            hold = float(parts[2]) if len(parts) > 2 else 0.1
            gp.press_button(button=btn)
            gp.update()
            time.sleep(hold)
            gp.release_button(button=btn)
            gp.update()
            return "OK"
        if cmd == "STICK":
            side, x, y = parts[1].upper(), float(parts[2]), float(parts[3])
            if side == "L":
                gp.left_joystick_float(x_value_float=x, y_value_float=y)
            elif side == "R":
                gp.right_joystick_float(x_value_float=x, y_value_float=y)
            else:
                return "ERR side must be L or R"
            gp.update()
            return "OK"
        if cmd == "TRIGGER":
            side, v = parts[1].upper(), float(parts[2])
            if side == "L":
                gp.left_trigger_float(value_float=v)
            elif side == "R":
                gp.right_trigger_float(value_float=v)
            else:
                return "ERR side must be L or R"
            gp.update()
            return "OK"
        return "ERR unknown command " + cmd
    except (IndexError, ValueError) as e:
        return "ERR bad arguments (" + str(e) + ")"


def serve(port=DEFAULT_PORT):
    import vgamepad as vg
    gp = vg.VX360Gamepad()  # created here = "plugged in"; stays connected for this process's lifetime
    print("[xpad] virtual X360 gamepad connected", flush=True)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, port))
    srv.listen(4)
    print(f"[xpad] listening on {HOST}:{port} -- launch the game now if it isn't running yet", flush=True)

    try:
        while True:
            conn, _ = srv.accept()
            with conn:
                data = conn.recv(4096).decode("utf-8", "ignore")
                reply = _handle(gp, data)
                conn.sendall((reply + "\n").encode("utf-8"))
                if data.strip().upper() == "QUIT":
                    break
    finally:
        gp.reset()
        gp.update()
        srv.close()
        print("[xpad] virtual gamepad disconnected, server stopped", flush=True)


def send(args, port=DEFAULT_PORT):
    line = " ".join(args)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect((HOST, port))
        s.sendall(line.encode("utf-8"))
        reply = s.recv(4096).decode("utf-8", "ignore").strip()
        print(reply)
        return reply


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("serve", "send"):
        print(__doc__)
        sys.exit(2)
    mode = sys.argv[1]
    rest = sys.argv[2:]
    port = DEFAULT_PORT
    if "--port" in rest:
        i = rest.index("--port")
        port = int(rest[i + 1])
        rest = rest[:i] + rest[i + 2:]
    if mode == "serve":
        serve(port)
    else:
        if not rest:
            print("usage: python tools/xpad.py send <COMMAND...> [--port N]")
            sys.exit(2)
        send(rest, port)


if __name__ == "__main__":
    main()
