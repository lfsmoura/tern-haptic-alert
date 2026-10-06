# tern-haptic-alert

Feel when your Tern agent needs you: a haptic pulse on a
Logitech MX Master 4 when an agent finishes or gets blocked. A Tern port of
[herdr-haptic-alert](https://github.com/lfsmoura/herdr-haptic-alert).

| Agent status | Feedback |
| --- | --- |
| done (working → idle, until you focus it) | `damp-state-change` pulse |
| blocked (waiting for your input) | `subtle-collision` pulse |
| anything else | nothing |

## Install

```sh
tern plugin install github.com/lfsmoura/tern-haptic-alert
```

On first use the plugin runs `npm install` in its directory to fetch
`node-hid`. Then run **Haptic: test done** from the palette with your hand on
the mouse.

## Requirements

- macOS, Node.js 22+ and npm (looked up on PATH, mise shims, Homebrew)
- A Logitech MX Master 4 connected directly over **Bluetooth** (no Bolt
  receiver), awake, with haptics enabled at a nonzero intensity
- HID access: macOS may ask for **Input Monitoring** permission for Tern

## Commands

- **Haptic: test done** / **Haptic: test blocked** — play a pulse now
- **Haptic: list mice** — toasts and copies the connected mice's serials

## Configuration

Edit the `CONFIG` table at the top of `window.luau`, then
`tern plugin reload`:

```lua
local CONFIG = {
	done = "damp-state-change",   -- or "subtle-collision", or false
	blocked = "subtle-collision", -- or "damp-state-change", or false
	serial = nil,                 -- serialNumber from "Haptic: list mice"
}
```

## How it works

Tern reports agent blocks as `idle | working | waiting_input | exited` without
a status event, so `agents.luau` polls `cx.agents:list()` every second and
derives Herdr's statuses. Only Tern agent blocks count, not an agent CLI typed
into a plain shell. Each pulse runs `node cli.mjs play <waveform>`;
`haptics.mjs` resolves HID++ feature `0x19b0`, checks the waveform and current
settings, and plays it. It never changes device-wide haptic settings.

Errors (mouse asleep, no permission, haptics off) show once as a toast and in
`~/Library/Logs/Tern/tern.log`.

Every Tern window runs its own copy, so two windows pulse twice.

## Credits

HID++ playback from [herdr-haptic-alert](https://github.com/lfsmoura/herdr-haptic-alert),
which follows [OpenLogi](https://openlogi.org/)'s reverse-engineered haptic
feature; transport by [node-hid](https://github.com/node-hid/node-hid).
Not affiliated with Logitech or Stencil.

## License

[MIT](LICENSE)
