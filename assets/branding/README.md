# App icon

The original SVG combines the lesson pane, the target application and a pointer.
It uses the shared primary blue and white, with no application-specific symbol.
The transparent margin and rounded silhouette work on light and dark desktops.

`app_icon.png` is a 256 px preview. Windows consumes the multi-resolution
`windows/runner/resources/app_icon.ico` through `Runner.rc` and the window class.
Keep the SVG as the editable source.

To regenerate with Python, CairoSVG 2.9.0 and Pillow 12.2.0 available:

```python
from io import BytesIO
from pathlib import Path
import cairosvg
from PIL import Image

root = Path.cwd()  # Repository root.
source = root / 'assets/branding/app_icon.svg'
png = cairosvg.svg2png(url=str(source), output_width=1024, output_height=1024)
icon = Image.open(BytesIO(png)).convert('RGBA')
icon.resize((256, 256), Image.Resampling.LANCZOS).save(source.with_suffix('.png'))
icon.save(root / 'windows/runner/resources/app_icon.ico', format='ICO',
          sizes=[(n, n) for n in [16, 20, 24, 32, 40, 48, 64, 128, 256]])
```
