# Animated slide scenes

Silhouette-style animated scenes that replace the still illustrations in
`Slave_Dynasty_Mamluk_Presentation.pptx`. Each scene is a seamless loop drawn
with the PIL toolkit in `lib.py` and exported as an animated GIF (PowerPoint
plays GIFs automatically in slideshow mode).

| GIF (`../assets/anim/`) | Slide | Scene |
|---|---|---|
| `intro.gif`     | 3  | falling chains, crown, the freed figure — “from chains to crowns” |
| `market.gif`    | 5  | slave-market caravan — a boy is led away with a rope |
| `ghori.gif`     | 6  | Damyak 1206 — assassins creep into Ghori's tent |
| `aibak.gif`     | 7  | Aibak at chaugan (polo) with raining gold — “Lakh Baksh” |
| `iltutmish.gif` | 8  | the Caliph's robe of honour rides toward Delhi's gate |
| `mongol.gif`    | 9  | the horde waits across the Indus, arrows fly |
| `razia.gif`     | 10 | Razia on horseback, sword raised, cape flying |
| `puppet.gif`    | 11 | a puppet sultan on strings, the Forty whispering |
| `balban.gif`    | 12 | the sijda court — rows bow to the “Shadow of God” |
| `duel.gif`      | 13 | Khalji swords clash — 1290 |
| `tanka.gif`     | 14 | the silver tanka of Iltutmish, spinning |
| `minar.gif`     | 15 | the Qutb Minar rises, storey by storey |
| `legacy.gif`    | 16 | what they built still stands |
| `teddy.gif`     | 18 | plush teddy bear waves and says “Thank you mates!” |

## Regenerate

```bash
cd assignment/anim
python3 make_gifs.py            # rewrite all GIFs into ../assets/anim/
python3 make_gifs.py --sheet    # + per-scene contact sheets in /tmp/anim_sheets
python3 make_gifs.py razia      # only one scene
cd .. && python3 make_ppt.py    # rebuild the deck with the new GIFs
```

## Files

- `lib.py` — supersampled canvas (gradients, glows, alpha shapes), articulated
  silhouette `person` / `horse` / `camel` / `seated` rider / `cape`, `stars`.
  Limb angles: `0` = straight down, `90` = forward, `180` = up.
- `scenes1.py` — `hills`, `ground_strip`, `dust` + `razia`, `duel`, `mongol`
- `scenes2.py` — `ring`, `crown` + `intro`, `market`, `damyak`, `polo`, `iltutmish`
- `scenes3.py` — `puppet`, `balban`, `tanka`, `minar`, `legacy`, `teddy`
- `make_gifs.py` — scene registry, palette conversion, GIF export
