# Intentive desktop asset provenance

LIFECYCLE: permanent

This is the shipping-source record for current Intentive desktop identity assets. The project owner supplied and explicitly approved the canonical icon and moss-garden inputs plus an experimental Dock-material reference and the DMG composition reference during S-30 on 2026-09-03. This records that product-use approval; it does not assert a separate third-party licence beyond the repository's governing licence and provenance.

## Owner-supplied sources

| Source | SHA-256 | Approved use |
|---|---|---|
| `intentive-icon.png` (1024 × 1024) | `8cd05bb91370e52aa99359ddda8b715309f63c260e58117a0dca03b3fbf3809a` | Canonical app icon and source geometry for monochrome product marks |
| `Moss garden.jpeg` (736 × 736) | `6748cc8817f39f249d93f66d12d61216460bb57036dbe41f6e06eba05a0546b4` | Sign-in and onboarding backdrop; preserve the complete square image |
| Grass-number reference (500 × 500) | `0ff053f66537d139f73ace51a797e1494e766de5a379d5dead932360e51e3cd8` | Evaluated for the Dock/app icon only; the experiment was rejected because the texture collapsed to flat green at Dock size and does not ship |
| Claude DMG reference screenshot (1304 × 762) | `401e05b7fb85ce3618c49cd9586fdc212d2ce4160179c299db22517718fc7161` | Visual composition reference for the warm drag-to-Applications installer |

The attachment paths are intentionally not committed; `.context/` is workspace-local. The hashes above let a maintainer match future source deliveries without making those paths part of the build.

## Shipping derivatives

| Shipping asset | Source and transformation |
|---|---|
| `Desktop/Sources/Resources/intentive_app_icon.png` | Exact owner-supplied black-and-white icon, uniformly scaled to an 824 × 824 tile and centered on a transparent 1024 × 1024 canvas. This preserves the original internal mark geometry while matching the standard macOS Dock footprint |
| `intentive_icon.icns` | Standard 16, 32, 128, 256, 512 and Retina representations generated from the optically inset canonical icon with `sips` and `iconutil` |
| `Desktop/Sources/Resources/intentive_mark.png` | Monochrome alpha template extracted from the canonical black head-and-asterisk geometry; no geometry was redrawn |
| `Desktop/Sources/Resources/intentive_menu_bar_icon.png` | 88 × 88 Retina template derivative of `intentive_mark.png`; rendered by AppKit at 21 × 21 points, matching the owner-provided Intentive menu-bar reference |
| `Desktop/Sources/Resources/intentive_signin_backdrop.png` | 4096 × 2304 composition. ImageGen extended only the left and right scene. The complete source square was then composited back, centered at full height, so no source content is cropped or repainted; blending occurs outside its bounds |
| `Desktop/Sources/Resources/intentive_permission_01_privacy.png` through `intentive_permission_04_return.png` | Four 4:3 ImageGen tutorial illustrations. Frames 3 and 4 use the canonical icon pixels composited over generated mockups. Swift renders the exact captions and cycles the frames; the art contains no instructional copy dependency |
| `Desktop/Sources/Resources/intentive_microphone_settings.png` | ImageGen permission-row illustration with the canonical icon composited over the generated mark |
| `docs/oauth-callback-success-preview.png` | ImageGen adaptation of the former preview with exact Intentive return copy |
| `dmg-assets/background.png` and `background@2x.png` | ImageGen-derived warm background and arrow from the approved DMG composition. Finder renders the live Intentive app icon, Applications alias and labels so the mounted installer does not contain doubled bitmap copies |

ImageGen generation record: `01a06210-7810-7000-9fd2-4b3e714ce05c`. Prompts required neutral/white Intentive styling, no purple or magenta, native macOS proportions, exact permission-step intent, and no extra logos or copy. The backdrop prompt additionally locked the square source and requested side-only scene continuation. A grass-material Dock experiment was assessed at real Dock size and deliberately rejected; the shipping app icon is the exact canonical black-and-white source with only a uniform standard-canvas inset. Menu bar, notch, and in-app brand marks likewise remain canonical monochrome assets.

## Retired inherited assets

S-30 removed the caller-free inherited `OmiIcon.icns`, `AppIcon.icns`, permission GIFs, folder screenshot, Omi wordmark/notch/tray art, onboarding lineup, rope artwork, demo video, and unused DMG design options. Git history remains the recovery and provenance record for those deletions.
