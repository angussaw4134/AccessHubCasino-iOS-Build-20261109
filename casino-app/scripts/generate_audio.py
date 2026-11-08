"""Original quiet interface effects synthesized from enveloped sine tones."""
from pathlib import Path
import math
import struct
import wave

folder = Path(__file__).resolve().parents[1] / "AccessHubCasino/Audio"
folder.mkdir(exist_ok=True)
effects = {"tap": [(520, 0.06)], "reveal": [(660, 0.07), (880, 0.09)], "collect": [(523.25, 0.10), (659.25, 0.10), (783.99, 0.18)], "reel": [(220, 0.05), (330, 0.05), (440, 0.07)], "finish": [(196, 0.10), (146.83, 0.18)], "win": [(659.25, 0.08), (783.99, 0.08), (987.77, 0.18)]}
for name, notes in effects.items():
    frames = bytearray()
    for frequency, duration in notes:
        count = int(duration * 44100)
        for sample in range(count):
            t = sample / 44100
            envelope = min(1, sample / 180) * (1 - sample / count) ** 2
            value = (math.sin(2*math.pi*frequency*t) + 0.2*math.sin(4*math.pi*frequency*t)) * envelope
            frames.extend(struct.pack("<h", int(value * 7000)))
    with wave.open(str(folder / f"{name}.wav"), "wb") as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(44100); output.writeframes(frames)
print("Generated six original sound effects.")
