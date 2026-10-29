# NexVM — Brand Guide v1

**Name:** NexVM  
**Tagline:** Your OS. Your Freedom.  
**Personality:** open, premium, calm, trustworthy, technical.

## Color palette

| Token | Hex | Use |
|---|---|---|
| NexBlue | `#007AFF` | Primary |
| NexPurple | `#8B5CF6` | Supporting |
| NexCyan | `#22D3EE` | Supporting |
| NexDark | `#0B0F1A` | Supporting |
| NexGray | `#94A3B8` | Supporting |
| NexLight | `#F8FAFC` | Supporting |

## Typography
Use the macOS system typeface in SwiftUI (`.system`); do not bundle Apple font files. For web material use Inter or system sans serif.

## Logos
Use the horizontal lockup when space allows and the standalone N symbol for compact UI. Maintain breathing room around the mark. Do not stretch, recolor arbitrarily, or apply shadows to the flat SVG.

## Image quality note
The PNG app icon set is extracted from the generated presentation board (approx. 257 px source), then resampled. The 1024 px file is **not a native 1024 px master**. For final public release recreate/render the icon at native 1024 px to avoid softness. SVG files are editable approximations rebuilt from the visual concept, not exact vector traces.

## UI guidelines
Favor macOS-native window chrome and sidebar layout. Color should communicate active states and brand; avoid excessive gradients behind body text. Support dark/light mode, Dynamic Type, keyboard focus, and VoiceOver.
