const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const edgePath = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const appSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <!-- Background Gradient -->
    <linearGradient id="bgGrad" x1="15%" y1="0%" x2="85%" y2="100%">
      <stop offset="0%" stop-color="#1e1b4b"/>
      <stop offset="30%" stop-color="#0f172a"/>
      <stop offset="75%" stop-color="#020617"/>
      <stop offset="100%" stop-color="#02040a"/>
    </linearGradient>

    <!-- Top Gloss Rim -->
    <linearGradient id="rimGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.4"/>
      <stop offset="15%" stop-color="#ffffff" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.02"/>
    </linearGradient>

    <!-- Ambient Radial Glow -->
    <radialGradient id="coreGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#00f2fe" stop-opacity="0.32"/>
      <stop offset="45%" stop-color="#2563eb" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="#000" stop-opacity="0"/>
    </radialGradient>

    <!-- Shackle Electric Gradient -->
    <linearGradient id="shackleGrad" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#06b6d4"/>
      <stop offset="45%" stop-color="#38bdf8"/>
      <stop offset="100%" stop-color="#34d399"/>
    </linearGradient>

    <!-- Phone Glass Body Gradient -->
    <linearGradient id="phoneGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.04"/>
    </linearGradient>

    <!-- Lock Body Gradient -->
    <linearGradient id="lockBody" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#3b82f6"/>
      <stop offset="55%" stop-color="#1d4ed8"/>
      <stop offset="100%" stop-color="#1e40af"/>
    </linearGradient>

    <!-- Specular highlight on Lock Body -->
    <linearGradient id="lockHighlight" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>

    <!-- Keyhole Glow -->
    <radialGradient id="keyholeGlow" cx="50%" cy="40%" r="60%">
      <stop offset="0%" stop-color="#67e8f9"/>
      <stop offset="60%" stop-color="#06b6d4"/>
      <stop offset="100%" stop-color="#0284c7"/>
    </radialGradient>

    <filter id="shadowSquircle" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="16" stdDeviation="18" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
    
    <filter id="glowFilter" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="8" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>

    <filter id="glyphShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.45"/>
    </filter>
  </defs>

  <!-- Base Squircle -->
  <g filter="url(#shadowSquircle)">
    <rect x="36" y="36" width="440" height="440" rx="98" fill="url(#bgGrad)"/>
    <rect x="36" y="36" width="440" height="440" rx="98" fill="none" stroke="url(#rimGrad)" stroke-width="3"/>
  </g>

  <!-- Core Ambient Glow -->
  <circle cx="256" cy="256" r="190" fill="url(#coreGlow)"/>

  <!-- Phone Glass Outline (Sleek Apple Aesthetic) -->
  <g filter="url(#glyphShadow)">
    <!-- Phone Body -->
    <rect x="160" y="90" width="192" height="332" rx="42" fill="url(#phoneGlass)" stroke="rgba(255,255,255,0.22)" stroke-width="2.5"/>
    <!-- Inner Screen Bezel / Border -->
    <rect x="170" y="100" width="172" height="312" rx="34" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="1.5"/>
    <!-- Dynamic Island -->
    <rect x="230" y="112" width="52" height="14" rx="7" fill="#000000" fill-opacity="0.6"/>
    <!-- Speaker dot in dynamic island -->
    <circle cx="268" cy="119" r="2.5" fill="#1e293b"/>
    <!-- Home Bar -->
    <rect x="226" y="396" width="60" height="4.5" rx="2.25" fill="#ffffff" fill-opacity="0.4"/>
  </g>

  <!-- Unlocked Padlock (Aesthetic Glassmorphism & Neon Aura) -->
  <g filter="url(#glyphShadow)">
    <!-- Open Shackle: Anchored on left at (216, 230), curves up to (256, 142), and swings released to right (320, 202) -->
    <path d="M 216 230 V 190 C 216 152 240 142 268 142 C 298 142 320 158 320 190 V 204"
          fill="none"
          stroke="url(#shackleGrad)"
          stroke-width="20"
          stroke-linecap="round"
          filter="url(#glowFilter)"/>
          
    <!-- Sparkle at the unlocked tip of the shackle -->
    <path d="M 320 196 Q 320 186 325 186 Q 320 186 320 176 Q 320 186 315 186 Q 320 186 320 196 Z"
          fill="#34d399"
          filter="url(#glowFilter)"/>

    <!-- Padlock Body -->
    <rect x="186" y="224" width="140" height="114" rx="28" fill="url(#lockBody)"/>
    <!-- Gloss highlight across top of padlock -->
    <rect x="186" y="224" width="140" height="57" rx="28" fill="url(#lockHighlight)"/>
    <rect x="186" y="224" width="140" height="114" rx="28" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="2"/>

    <!-- Keyhole / Unlocking Core -->
    <circle cx="256" cy="270" r="14" fill="url(#keyholeGlow)" filter="url(#glowFilter)"/>
    <path d="M 252 274 L 249 296 C 249 298 251 300 253 300 H 259 C 261 300 263 298 263 296 L 260 274 Z"
          fill="url(#keyholeGlow)"
          filter="url(#glowFilter)"/>
    <!-- Center white core dot -->
    <circle cx="256" cy="270" r="6" fill="#ffffff"/>
  </g>

  <!-- Ambient Micro Sparkles (Aesthetic Apple Style) -->
  <circle cx="150" cy="160" r="2.5" fill="#38bdf8" fill-opacity="0.7"/>
  <circle cx="360" cy="140" r="3.5" fill="#34d399" fill-opacity="0.8"/>
  <circle cx="375" cy="330" r="2" fill="#38bdf8" fill-opacity="0.6"/>
</svg>`;

// Installer variant: includes setup/installation badge
const installerSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <!-- Background Gradient -->
    <linearGradient id="bgGrad" x1="15%" y1="0%" x2="85%" y2="100%">
      <stop offset="0%" stop-color="#1e1b4b"/>
      <stop offset="30%" stop-color="#0f172a"/>
      <stop offset="75%" stop-color="#020617"/>
      <stop offset="100%" stop-color="#02040a"/>
    </linearGradient>

    <!-- Top Gloss Rim -->
    <linearGradient id="rimGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.4"/>
      <stop offset="15%" stop-color="#ffffff" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.02"/>
    </linearGradient>

    <!-- Ambient Radial Glow -->
    <radialGradient id="coreGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#00f2fe" stop-opacity="0.32"/>
      <stop offset="45%" stop-color="#2563eb" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="#000" stop-opacity="0"/>
    </radialGradient>

    <!-- Shackle Electric Gradient -->
    <linearGradient id="shackleGrad" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#06b6d4"/>
      <stop offset="45%" stop-color="#38bdf8"/>
      <stop offset="100%" stop-color="#34d399"/>
    </linearGradient>

    <!-- Phone Glass Body Gradient -->
    <linearGradient id="phoneGlass" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.04"/>
    </linearGradient>

    <!-- Lock Body Gradient -->
    <linearGradient id="lockBody" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#3b82f6"/>
      <stop offset="55%" stop-color="#1d4ed8"/>
      <stop offset="100%" stop-color="#1e40af"/>
    </linearGradient>

    <!-- Specular highlight on Lock Body -->
    <linearGradient id="lockHighlight" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>

    <!-- Keyhole Glow -->
    <radialGradient id="keyholeGlow" cx="50%" cy="40%" r="60%">
      <stop offset="0%" stop-color="#67e8f9"/>
      <stop offset="60%" stop-color="#06b6d4"/>
      <stop offset="100%" stop-color="#0284c7"/>
    </radialGradient>

    <filter id="shadowSquircle" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="16" stdDeviation="18" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
    
    <filter id="glowFilter" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="8" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>

    <filter id="glyphShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.45"/>
    </filter>

    <filter id="badgeShadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000000" flood-opacity="0.6"/>
    </filter>
  </defs>

  <!-- Base Squircle -->
  <g filter="url(#shadowSquircle)">
    <rect x="36" y="36" width="440" height="440" rx="98" fill="url(#bgGrad)"/>
    <rect x="36" y="36" width="440" height="440" rx="98" fill="none" stroke="url(#rimGrad)" stroke-width="3"/>
  </g>

  <!-- Core Ambient Glow -->
  <circle cx="256" cy="256" r="190" fill="url(#coreGlow)"/>

  <!-- Phone Glass Outline (Sleek Apple Aesthetic) -->
  <g filter="url(#glyphShadow)">
    <rect x="160" y="90" width="192" height="332" rx="42" fill="url(#phoneGlass)" stroke="rgba(255,255,255,0.22)" stroke-width="2.5"/>
    <rect x="170" y="100" width="172" height="312" rx="34" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="1.5"/>
    <rect x="230" y="112" width="52" height="14" rx="7" fill="#000000" fill-opacity="0.6"/>
    <circle cx="268" cy="119" r="2.5" fill="#1e293b"/>
    <rect x="226" y="396" width="60" height="4.5" rx="2.25" fill="#ffffff" fill-opacity="0.4"/>
  </g>

  <!-- Unlocked Padlock (Aesthetic Glassmorphism & Neon Aura) -->
  <g filter="url(#glyphShadow)">
    <path d="M 216 230 V 190 C 216 152 240 142 268 142 C 298 142 320 158 320 190 V 204"
          fill="none"
          stroke="url(#shackleGrad)"
          stroke-width="20"
          stroke-linecap="round"
          filter="url(#glowFilter)"/>
          
    <path d="M 320 196 Q 320 186 325 186 Q 320 186 320 176 Q 320 186 315 186 Q 320 186 320 196 Z"
          fill="#34d399"
          filter="url(#glowFilter)"/>

    <rect x="186" y="224" width="140" height="114" rx="28" fill="url(#lockBody)"/>
    <rect x="186" y="224" width="140" height="57" rx="28" fill="url(#lockHighlight)"/>
    <rect x="186" y="224" width="140" height="114" rx="28" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="2"/>

    <circle cx="256" cy="270" r="14" fill="url(#keyholeGlow)" filter="url(#glowFilter)"/>
    <path d="M 252 274 L 249 296 C 249 298 251 300 253 300 H 259 C 261 300 263 298 263 296 L 260 274 Z"
          fill="url(#keyholeGlow)"
          filter="url(#glowFilter)"/>
    <circle cx="256" cy="270" r="6" fill="#ffffff"/>
  </g>

  <!-- Ambient Micro Sparkles -->
  <circle cx="150" cy="160" r="2.5" fill="#38bdf8" fill-opacity="0.7"/>
  <circle cx="360" cy="140" r="3.5" fill="#34d399" fill-opacity="0.8"/>

  <!-- Installer Setup Badge (Differentiating installer from app itself) -->
  <g filter="url(#badgeShadow)">
    <circle cx="392" cy="392" r="68" fill="#0f172a" stroke="#ffffff" stroke-width="4"/>
    <circle cx="392" cy="392" r="64" fill="url(#lockBody)"/>
    <circle cx="392" cy="392" r="64" fill="url(#lockHighlight)"/>
    <path d="M 392 360 V 404 M 374 388 L 392 406 L 410 388"
          fill="none"
          stroke="#ffffff"
          stroke-width="7"
          stroke-linecap="round"
          stroke-linejoin="round"/>
    <path d="M 368 418 H 416"
          fill="none"
          stroke="#ffffff"
          stroke-width="6.5"
          stroke-linecap="round"/>
  </g>
</svg>`;

const scratchDir = path.join(__dirname, 'scratch_icons');
if (!fs.existsSync(scratchDir)) fs.mkdirSync(scratchDir, { recursive: true });

function createHtml(svg, size) {
  return `<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: ${size}px;
      height: ${size}px;
      overflow: hidden;
      background: transparent;
    }
    svg {
      width: ${size}px;
      height: ${size}px;
      display: block;
    }
  </style>
</head>
<body>
  ${svg}
</body>
</html>`;
}

function renderPng(svg, size, outFile) {
  const htmlFile = path.join(scratchDir, `temp_${size}.html`);
  fs.writeFileSync(htmlFile, createHtml(svg, size));
  
  execFileSync(edgePath, [
    '--headless',
    '--disable-gpu',
    '--default-background-color=00000000',
    '--hide-scrollbars',
    `--window-size=${size},${size}`,
    `--screenshot=${outFile}`,
    htmlFile
  ]);
  
  if (fs.existsSync(htmlFile)) fs.unlinkSync(htmlFile);
}

// Convert a list of PNG buffers into an ICO file buffer
function createIco(pngBuffers) {
  const count = pngBuffers.length;
  const headerSize = 6;
  const dirEntrySize = 16;
  let offset = headerSize + count * dirEntrySize;
  
  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0); // Reserved
  header.writeUInt16LE(1, 2); // Type 1 = ICO
  header.writeUInt16LE(count, 4); // Number of images

  const entries = [];
  for (const { size, buffer } of pngBuffers) {
    const entry = Buffer.alloc(dirEntrySize);
    entry.writeUInt8(size >= 256 ? 0 : size, 0); // Width
    entry.writeUInt8(size >= 256 ? 0 : size, 1); // Height
    entry.writeUInt8(0, 2); // Palette colors
    entry.writeUInt8(0, 3); // Reserved
    entry.writeUInt16LE(1, 4); // Color planes
    entry.writeUInt16LE(32, 6); // Bits per pixel
    entry.writeUInt32LE(buffer.length, 8); // Image size in bytes
    entry.writeUInt32LE(offset, 12); // Offset to image data
    entries.push(entry);
    offset += buffer.length;
  }

  return Buffer.concat([header, ...entries, ...pngBuffers.map(p => p.buffer)]);
}

async function main() {
  console.log('Rendering modern aesthetic app icon PNGs and ICO...');
  const iconSizes = [16, 32, 48, 256];
  const appBuffers = [];
  const installerBuffers = [];

  for (const size of iconSizes) {
    const appPng = path.join(scratchDir, `app_${size}.png`);
    renderPng(appSvg, size, appPng);
    appBuffers.push({ size, buffer: fs.readFileSync(appPng) });

    const installerPng = path.join(scratchDir, `installer_${size}.png`);
    renderPng(installerSvg, size, installerPng);
    installerBuffers.push({ size, buffer: fs.readFileSync(installerPng) });
  }

  // 1. High-res 512x512 PNGs
  const app512 = path.join(scratchDir, 'app_512.png');
  renderPng(appSvg, 512, app512);

  const installer512 = path.join(scratchDir, 'installer_512.png');
  renderPng(installerSvg, 512, installer512);

  // 2. Generate ICO files
  const appIcoBuffer = createIco(appBuffers);
  const installerIcoBuffer = createIco(installerBuffers);

  // Destination paths
  const rootDir = path.resolve(__dirname, '..');
  const appPngDest1 = path.join(rootDir, 'apps', 'unlock_iphone', 'assets', 'icons', 'app_icon.png');
  const appPngDest2 = path.join(rootDir, 'packages', 'unlock_core', 'assets', 'icons', 'app_icon.png');
  const appIcoDest1 = path.join(rootDir, 'apps', 'unlock_iphone', 'windows', 'runner', 'resources', 'app_icon.ico');
  const appIcoDest2 = path.join(rootDir, 'apps', 'unlock_iphone', 'windows', 'runner', 'resources', 'app_icon_brand.ico');
  
  const installerPngDest = path.join(rootDir, 'installer', 'installer_icon.png');
  const installerIcoDest = path.join(rootDir, 'installer', 'installer_icon.ico');

  // Copy app icon files
  fs.copyFileSync(app512, appPngDest1);
  fs.copyFileSync(app512, appPngDest2);
  fs.writeFileSync(appIcoDest1, appIcoBuffer);
  fs.writeFileSync(appIcoDest2, appIcoBuffer);

  // Copy installer icon files
  fs.copyFileSync(installer512, installerPngDest);
  fs.writeFileSync(installerIcoDest, installerIcoBuffer);

  console.log('App and installer icons updated successfully!');
}

main().catch(console.error);
