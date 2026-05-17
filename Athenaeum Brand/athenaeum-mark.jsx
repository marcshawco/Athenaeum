// Athenaeum — primary mark & lockups
// One source of truth: the Æ chip, the wordmark, and combined lockups.
//
// <AthenaeumMark size variant />
//   variant: 'ink' | 'inverse' | 'forest' | 'outline'
// <AthenaeumLockup size variant sub /> — mark + word
// <AthenaeumWordmark size color /> — just the word
//
// Sizes given in pixels; mark scales internally.

const BRAND = {
  ink:        '#211F1B',
  paper:      '#FBFAF7',
  paper2:     '#F4F2EC',
  forestDark: '#243A2D',
  forestSoft: '#C8D4BE',
  ink3:       '#9C968B',
};

function AthenaeumMark({ size = 32, variant = 'ink', radius, style = {} }) {
  // macOS-style rounded square: ~22% radius
  const r = radius != null ? radius : Math.round(size * 0.22);
  let bg, fg, border = 'transparent';
  switch (variant) {
    case 'inverse':  bg = BRAND.paper;      fg = BRAND.ink;        break;
    case 'forest':   bg = BRAND.forestDark; fg = BRAND.forestSoft; break;
    case 'outline':  bg = 'transparent';    fg = BRAND.ink;        border = BRAND.ink; break;
    case 'ink':
    default:         bg = BRAND.ink;        fg = BRAND.paper;      break;
  }
  return (
    <div style={{
      width: size, height: size, borderRadius: r,
      background: bg,
      border: variant === 'outline' ? `0.5px solid ${border}` : 'none',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      flexShrink: 0,
      lineHeight: 0,
      ...style,
    }} aria-label="Athenaeum">
      <span style={{
        fontFamily: '"Fraunces", Georgia, "Times New Roman", serif',
        fontStyle: 'italic',
        fontWeight: 300,
        // Æ optical-fit: tuned to sit centered in the square
        fontSize: Math.round(size * 0.66),
        color: fg,
        lineHeight: 1,
        // Italic glyph slightly off-axis — nudge for visual centering
        transform: `translate(${size * 0.01}px, ${size * -0.02}px)`,
        // Disable subpixel rendering changes
        WebkitFontSmoothing: 'antialiased',
      }}>Æ</span>
    </div>
  );
}

function AthenaeumWordmark({ size = 14, color = BRAND.ink, weight = 500, style = {} }) {
  return (
    <span style={{
      fontFamily: '"Fraunces", Georgia, serif',
      fontWeight: weight,
      fontSize: size,
      letterSpacing: 0.2,
      color,
      lineHeight: 1,
      ...style,
    }}>Athenaeum</span>
  );
}

function AthenaeumLockup({
  size = 30, variant = 'ink',
  wordSize = 13, wordColor = BRAND.ink, wordWeight = 500,
  sub = 'Private archive', subColor = BRAND.ink3,
  gap = 10, vertical = false, style = {},
}) {
  return (
    <div style={{
      display: 'inline-flex',
      flexDirection: vertical ? 'column' : 'row',
      alignItems: vertical ? 'center' : 'center',
      gap,
      ...style,
    }}>
      <AthenaeumMark size={size} variant={variant} />
      <div style={{ textAlign: vertical ? 'center' : 'left', marginTop: vertical ? 6 : 0 }}>
        <AthenaeumWordmark size={wordSize} color={wordColor} weight={wordWeight} />
        {sub && <div style={{
          fontSize: Math.max(9, Math.round(wordSize * 0.72)),
          color: subColor,
          marginTop: 2,
          fontFamily: '-apple-system, "SF Pro Text", sans-serif',
          letterSpacing: 0.1,
        }}>{sub}</div>}
      </div>
    </div>
  );
}

Object.assign(window, { AthenaeumMark, AthenaeumWordmark, AthenaeumLockup, BRAND });
