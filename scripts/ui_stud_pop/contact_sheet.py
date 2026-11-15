# Contact sheet: every portrait on the Stud Pop panel colour with a rarity frame, at 160 px and 96 px.
import sys
from PIL import Image, ImageDraw, ImageFont
tiers = {}
for i in range(1, 36):
    tiers[f"BRT_{i:03d}"] = ("Common" if i <= 10 else "Uncommon" if i <= 18 else "Rare" if i <= 25 else "Epic" if i <= 30
        else "Legendary" if i <= 33 else "Mythic" if i == 34 else "Secret")
col = {"Common": "#E3EAF3", "Uncommon": "#72E65B", "Rare": "#46A7FF", "Epic": "#B86CFF", "Legendary": "#FFAE3D", "Mythic": "#FF4B67", "Secret": "#DBD6E7"}
out, cell = sys.argv[1], int(sys.argv[2])
cols = 7; rows = 5; pad = 10; lab = 18
W = cols * (cell + pad) + pad; H = rows * (cell + pad + lab) + pad
sheet = Image.new("RGBA", (W, H), "#32246B"); d = ImageDraw.Draw(sheet)
try: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 13)
except Exception: font = None
for k, (sid, tier) in enumerate(tiers.items()):
    x = pad + (k % cols) * (cell + pad); y = pad + (k // cols) * (cell + pad + lab)
    d.rounded_rectangle([x, y, x + cell, y + cell], radius=cell // 8, fill="#4A36A0", outline=col[tier], width=max(3, cell // 30))
    p = Image.open(f"assets/ui/portraits/{sid}.png").resize((cell - 8, cell - 8), Image.LANCZOS)
    sheet.alpha_composite(p, (x + 4, y + 4))
    d.text((x + 2, y + cell + 2), f"{sid} {tier}", fill="#F7F5FC", font=font)
sheet.save(out); print(out, sheet.size)
