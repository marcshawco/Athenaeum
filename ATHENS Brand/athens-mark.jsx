// Athens — brand mark, in-app source of truth
// Source typeface: Fraunces (italic, 300; 400 below 32 px)
//
// Make sure Fraunces is loaded by the host page, e.g.:
//   <link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@1,9..144,300;1,9..144,400;0,9..144,400&display=swap" rel="stylesheet">

const TOKENS = {
  ink:     { bg: '#211F1B', fg: '#FBFAF7' },
  forest:  { bg: '#243A2D', fg: '#C8D4BE' },
  inverse: { bg: '#FBFAF7', fg: '#211F1B' },
  outline: { bg: 'transparent', fg: '#211F1B' },
};

/**
 * <AthensMark size={64} variant="ink" />
 * variants: "ink" | "forest" | "inverse" | "outline"
 */
function AthensMark({ size = 64, variant = 'ink', style, ...rest }) {
  const t = TOKENS[variant] || TOKENS.ink;
  const isOutline = variant === 'outline';
  const weight = size < 32 ? 400 : 300;
  return (
    <div
      role="img"
      aria-label="Athens"
      style={{
        width: size,
        height: size,
        background: t.bg,
        color: t.fg,
        borderRadius: size * 0.22,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: '"Fraunces", Georgia, serif',
        fontStyle: 'italic',
        fontWeight: weight,
        fontSize: Math.round(size * 0.78),
        lineHeight: 1,
        letterSpacing: '-0.02em',
        flexShrink: 0,
        boxShadow: isOutline ? 'inset 0 0 0 1px #211F1B' : '0 0 0 0.5px rgba(0,0,0,0.18)',
        ...style,
      }}
      {...rest}
    >
      <span style={{ transform: 'translate(1.5%, -3%)' }}>A</span>
    </div>
  );
}

/**
 * <AthensWordmark size={20} tracking={3} />
 * Capital-tracked ATHENS, set in Fraunces.
 */
function AthensWordmark({ size = 20, tracking = 3, color = '#211F1B', style, ...rest }) {
  return (
    <span
      style={{
        fontFamily: '"Fraunces", Georgia, serif',
        fontWeight: 400,
        fontSize: size,
        letterSpacing: tracking,
        color,
        lineHeight: 1,
        ...style,
      }}
      {...rest}
    >
      ATHENS
    </span>
  );
}

/**
 * <AthensLockup size={40} subtitle="Private archive" />
 * Horizontal mark + wordmark + eyebrow.
 */
function AthensLockup({ size = 40, subtitle = 'A private archive', variant = 'ink', style, ...rest }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: size * 0.35, ...style }} {...rest}>
      <AthensMark size={size} variant={variant} />
      <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1 }}>
        <AthensWordmark size={size * 0.46} tracking={size * 0.08} />
        {subtitle && (
          <span style={{
            fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
            fontSize: Math.max(9, size * 0.22),
            letterSpacing: 2,
            textTransform: 'uppercase',
            color: '#9C968B',
            marginTop: size * 0.1,
          }}>
            {subtitle}
          </span>
        )}
      </div>
    </div>
  );
}

export { AthensMark, AthensWordmark, AthensLockup };
