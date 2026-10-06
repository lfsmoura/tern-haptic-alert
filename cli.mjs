// Tern's entry to haptics.mjs (from lfsmoura/herdr-haptic-alert):
//   node cli.mjs play <waveform> [serial]   prints the playback result as JSON
//   node cli.mjs list                        prints matching mice as JSON
import { devices, play } from "./haptics.mjs";

const [command, waveform, serial] = process.argv.slice(2);
try {
  if (command === "list") {
    console.log(JSON.stringify(await devices()));
  } else if (command === "play" && waveform) {
    console.log(JSON.stringify(await play(waveform, serial || undefined)));
  } else {
    throw new Error("usage: node cli.mjs play <waveform> [serial] | list");
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
