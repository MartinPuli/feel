# Geist fonts

Official Vercel Geist fonts, bundled unmodified under SIL OFL 1.1.
Source: https://github.com/vercel/geist-font/tree/e1f671c727f6de7e97c1e1d26dbb44f349c19459

SHA-256:
```text
63eed3b8f533234e2ae120fae23e79c92d8dda96bccce4147480c62a2fbddba5  Geist-Regular.otf
877ce6187b69f063920dc67d516948a4901fd8f9456f47ab22e7a67cf6a95742  Geist-Medium.otf
0416da9be298af36716be61292eb930ad5bcced2dfe60c1bbca3af838eea34ef  Geist-SemiBold.otf
b23edd02fa88c86701214cd0aa90d43f63798d4eb4b1bc1c52fbf834ff30d113  Geist-Bold.otf
2ffe5187bb29941057a3dceac997eedc8f15e5e66b2139097aef642f2616c318  GeistMono-Regular.otf
c683bfbcc7e087f5d37a54ef628f10387c451a83ddc459b151403a164ac46c90  OFL.txt
```

## Geist Serif Regular

Added on 2026-10-31 from Vercel's official release, without conversion or modification.

- Announcement: https://vercel.com/blog/introducing-geist-serif
- Official download page: https://vercel.com/font?type=serif
- Release: https://github.com/vercel/geist-font/releases/tag/v1.9.0
- Archive: https://github.com/vercel/geist-font/releases/download/v1.9.0/geist-font-v1.9.0.zip
- Archive member: `geist-font/GeistSerif/ttf/GeistSerif-Regular.ttf`
- Archive SHA-256, matched against GitHub's release asset digest:
  `1f2dd9ea90e68d0358a1d234a5f156807b2c3e0e295d78d87980a6dbad1fa58c`
- Font SHA-256: `6c33e2138c7544455f7807ee11356d636ab23944fe214d6cefd3fd5b1e45e171`
- Size: 132,452 bytes. Font version: `Version 1.001`.
- Font name table: family `Geist Serif`, full name `Geist Serif Regular`,
  PostScript name `GeistSerif-Regular`.

The release's `geist-font/OFL.txt` is byte-for-byte identical to the bundled
`OFL.txt` above. The font also embeds SIL OFL 1.1 licensing and the 2026 copyright
notice reproduced in `GeistSerif-NOTICE.txt`. The license permits embedding and
redistributing the font with software while retaining its notices and license.

Vercel describes this release as a display face. FEEL uses it only through the
24-point, Dynamic Type-scaled `FeelTypography.brand` wordmark token; functional
controls and instructions keep Geist Sans. Both app targets register the static
TTF in `UIAppFonts`. `FeelFontTests` checks the built Lantern app's registration
and lookup by PostScript name; its runtime result must be reported separately
from the source and checksum checks above.
