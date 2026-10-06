import HID from "node-hid";
import { randomInt } from "node:crypto";

// HID++ 0x19b0 layout follows OpenLogi's haptic_feedback.rs:
// https://github.com/AprilNEA/OpenLogi/blob/master/crates/openlogi-hidpp/src/feature/haptic_feedback.rs
export const waveforms = Object.freeze({ "damp-state-change": 1, "subtle-collision": 4 });

export async function devices() {
  const entries = await HID.devicesAsync(0x046d, 0xb042);
  return [...new Map(entries.map((entry) => [entry.path, entry])).values()];
}

export async function play(waveform, serial) {
  if (!Object.hasOwn(waveforms, waveform)) throw new Error(`Unknown waveform: ${waveform}`);
  const matches = (await devices()).filter((device) => !serial || device.serialNumber === serial);
  if (matches.length !== 1) {
    throw new Error(matches.length === 0
      ? "No matching Bluetooth MX Master 4. Connect/wake the mouse; run list to check its serial."
      : "Multiple MX Master 4 mice found. Set serial in config.json to choose one.");
  }
  const device = await HID.HIDAsync.open(matches[0].path, { nonExclusive: true });
  // Nonzero software IDs distinguish our replies from other HID++ clients.
  const softwareId = randomInt(1, 16);
  async function call(feature, fn, payload = []) {
    const address = (fn << 4) | softwareId;
    const report = Buffer.alloc(20);
    report.set([0x11, 0xff, feature, address, ...payload]);
    await device.write([...report]);
    const deadline = Date.now() + 1500;
    while (Date.now() < deadline) {
      const reply = Buffer.from(await device.read(Math.max(1, deadline - Date.now())));
      if (reply.length < 7 || ![0x10, 0x11].includes(reply[0]) || reply[1] !== 0xff) continue;
      if ([0x8f, 0xff].includes(reply[2]) && reply[3] === feature && reply[4] === address) {
        throw new Error(`HID++ error 0x${reply[5].toString(16)} for feature 0x${feature.toString(16)}`);
      }
      if (reply[2] === feature && reply[3] === address) return reply.subarray(4);
    }
    throw new Error("HID++ reply timed out. Wake the mouse and check macOS Input Monitoring permission for the terminal running Herdr.");
  }
  try {
    const [feature] = await call(0, 0, [0x19, 0xb0, 0]);
    if (!feature) throw new Error("The mouse does not expose HID++ haptic feedback (0x19b0).");
    const capabilities = await call(feature, 0);
    if (capabilities.length < 8 || !(capabilities.readUInt32BE(4) & (1 << waveforms[waveform]))) {
      throw new Error(`Mouse does not advertise waveform ${waveform}.`);
    }
    const [enabled, intensity] = await call(feature, 1);
    if (enabled !== 1 || !intensity || intensity > 100) {
      throw new Error("Mouse haptics are disabled or intensity is zero. Enable haptics in your mouse settings first; this plugin does not change device-wide settings.");
    }
    await call(feature, 4, [waveforms[waveform], 0, 0]);
    return { device: matches[0].product, serial: matches[0].serialNumber, waveform, intensity };
  } finally {
    await device.close();
  }
}
