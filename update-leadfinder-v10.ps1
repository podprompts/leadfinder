$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'package.json')) { Write-Host 'Run from leadfinder folder.' -ForegroundColor Red; exit 1 }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-FileSafe($path, $content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), $content, $utf8NoBom)
  Write-Host "  updated $path" -ForegroundColor Green
}
$content = @'
.shell {
  display: grid;
  grid-template-columns: 320px 1fr;
  min-height: 100vh;
  background: var(--black);
  color: #fff;
}

/* ---------- Sidebar ---------- */
.sidebar {
  border-right: 1px solid rgba(255,255,255,0.08);
  padding: 1.75rem 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
}

.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 18px;
}
.brandMark { color: var(--coral); }
.brandName { font-weight: 400; letter-spacing: -0.01em; }
.brandName strong { font-weight: 800; }
.brandTag {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: rgba(255,255,255,0.35);
  margin-top: -0.75rem;
}

.field { display: flex; flex-direction: column; gap: 0.5rem; }
.label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.5);
  font-weight: 600;
}

.chipGrid { display: flex; flex-wrap: wrap; gap: 6px; }
.chip {
  font-size: 12px;
  padding: 6px 11px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.14);
  background: transparent;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
  transition: all 0.12s;
}
.chip:hover { border-color: rgba(255,255,255,0.3); color: #fff; }
.chipOn {
  background: var(--coral);
  border-color: var(--coral);
  color: #fff;
  font-weight: 600;
}

.input {
  padding: 11px 13px;
  font-size: 14px;
  background: var(--black-3, #161616);
  border: 1px solid rgba(255,255,255,0.12);
  color: #fff;
  outline: none;
  transition: border-color 0.15s;
}
.input:focus { border-color: var(--coral); }
.input::placeholder { color: rgba(255,255,255,0.3); }

.range { accent-color: var(--coral); width: 100%; }

.searchBtn {
  margin-top: 0.25rem;
  padding: 13px;
  background: var(--coral);
  color: #fff;
  border: none;
  font-size: 12px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  cursor: pointer;
  transition: background 0.12s;
}
.searchBtn:hover:not(:disabled) { background: var(--coral-light, #ff6a3d); }
.searchBtn:disabled { opacity: 0.5; cursor: default; }

.sourceNote {
  font-size: 11px;
  line-height: 1.6;
  color: rgba(255,255,255,0.35);
  border-top: 1px solid rgba(255,255,255,0.08);
  padding-top: 1rem;
  margin-top: auto;
}

.error {
  background: rgba(232,69,10,0.12);
  border: 1px solid rgba(232,69,10,0.3);
  color: #ff8a5c;
  font-size: 12px;
  padding: 9px 12px;
}

/* ---------- Main ---------- */
.main { padding: 1.75rem 2rem; min-width: 0; }

.empty {
  max-width: 380px;
  margin: 14vh auto 0;
  text-align: center;
}
.emptyMark { font-size: 2rem; color: var(--coral); margin-bottom: 1rem; }
.empty h2 { font-size: 1.4rem; font-weight: 700; margin-bottom: 0.6rem; }
.empty p { font-size: 0.9rem; color: rgba(255,255,255,0.5); line-height: 1.7; }

.resultsHead {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 1.5rem;
  gap: 1rem;
}
.resultsTitle { font-size: 1.6rem; font-weight: 800; letter-spacing: -0.02em; }
.resultsSub { font-size: 0.8rem; color: rgba(255,255,255,0.4); margin-top: 0.2rem; }

.actions { display: flex; gap: 0.6rem; }
.primaryBtn {
  padding: 10px 18px;
  background: var(--coral);
  color: #fff;
  border: none;
  font-size: 11px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  cursor: pointer;
}
.primaryBtn:disabled { opacity: 0.4; cursor: default; }
.ghostBtn {
  padding: 10px 16px;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.16);
  color: rgba(255,255,255,0.7);
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  cursor: pointer;
  transition: all 0.12s;
}
.ghostBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }

.statStrip {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 1px;
  background: rgba(255,255,255,0.08);
  border: 1px solid rgba(255,255,255,0.08);
  margin-bottom: 1.5rem;
}
.stat { background: var(--black); padding: 1rem 1.25rem; }
.statNum { font-size: 1.8rem; font-weight: 800; letter-spacing: -0.02em; }
.statAccent { color: var(--coral); }
.statLabel {
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.4);
  margin-top: 0.2rem;
}

.filterBar {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1rem;
  flex-wrap: wrap;
}
.filterInput {
  flex: 1;
  min-width: 200px;
  padding: 9px 12px;
  background: var(--black-3, #161616);
  border: 1px solid rgba(255,255,255,0.12);
  color: #fff;
  font-size: 13px;
  outline: none;
}
.filterInput:focus { border-color: var(--coral); }
.check {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
}
.check input { accent-color: var(--coral); }
.filterCount {
  font-size: 11px;
  color: rgba(255,255,255,0.35);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.tableWrap {
  border: 1px solid rgba(255,255,255,0.08);
  overflow-x: auto;
}
.table { width: 100%; border-collapse: collapse; font-size: 13px; }
.table thead th {
  text-align: left;
  padding: 11px 14px;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.4);
  font-weight: 600;
  border-bottom: 1px solid rgba(255,255,255,0.08);
  background: rgba(255,255,255,0.02);
}
.table tbody td {
  padding: 12px 14px;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  vertical-align: top;
}
.table tbody tr:hover { background: rgba(255,255,255,0.02); }

.bizName { font-weight: 600; }
.bizMeta { font-size: 11px; color: rgba(255,255,255,0.4); margin-top: 0.2rem; }

.tier {
  display: inline-block;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 3px 8px;
  border-radius: 4px;
  white-space: nowrap;
}
.tierGold { background: rgba(232,82,26,0.18); color: #ff8a5c; border: 1px solid rgba(232,82,26,0.4); }
.tierWebsite { background: rgba(255,255,255,0.08); color: #fff; border: 1px solid rgba(255,255,255,0.18); }
.tierPhone { background: rgba(255,255,255,0.04); color: rgba(255,255,255,0.6); border: 1px solid rgba(255,255,255,0.1); }
.tierThin { background: transparent; color: rgba(255,255,255,0.3); border: 1px solid rgba(255,255,255,0.08); }

.link { color: #ff8a5c; text-decoration: none; }
.link:hover { text-decoration: underline; }
.dim { color: rgba(255,255,255,0.25); }

.phoneType {
  display: inline-block;
  margin-left: 6px;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(255,255,255,0.4);
  border: 1px solid rgba(255,255,255,0.12);
  padding: 1px 5px;
  border-radius: 3px;
}

.enriched { margin-top: 4px; display: flex; flex-direction: column; gap: 2px; }
.enrichedItem { font-size: 11px; color: #7dd3a0; }

.enrichBtn {
  font-size: 11px;
  padding: 5px 10px;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.16);
  color: rgba(255,255,255,0.7);
  cursor: pointer;
  transition: all 0.12s;
  white-space: nowrap;
}
.enrichBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }
.enrichBtn:disabled { opacity: 0.5; cursor: default; }

/* ---------- Responsive ---------- */
@media (max-width: 880px) {
  .shell { grid-template-columns: 1fr; }
  .sidebar { position: static; height: auto; border-right: none; border-bottom: 1px solid rgba(255,255,255,0.08); }
  .statStrip { grid-template-columns: repeat(2, 1fr); }
}

.socials { display: flex; gap: 4px; margin-top: 5px; flex-wrap: wrap; }
.socialPill {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 2px 6px;
  border-radius: 3px;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.14);
  color: rgba(255,255,255,0.7);
  text-decoration: none;
  transition: all 0.12s;
}
.socialPill:hover { border-color: var(--coral); color: #fff; }

.sweepBtn {
  margin-top: 0.5rem;
  padding: 11px;
  background: transparent;
  color: rgba(255,255,255,0.7);
  border: 1px solid rgba(255,255,255,0.18);
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  cursor: pointer;
  transition: all 0.12s;
}
.sweepBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }
.sweepBtn:disabled { opacity: 0.5; cursor: default; }

.cityChips { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 8px; }
.cityChip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  padding: 4px 8px;
  border-radius: 4px;
  background: rgba(232,82,26,0.12);
  border: 1px solid var(--coral-border);
  color: #fff;
}
.cityChipX {
  background: none;
  border: none;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
  font-size: 14px;
  line-height: 1;
  padding: 0;
}
.cityChipX:hover { color: var(--coral-light); }

.savedLink {
  display: inline-block;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--coral);
  text-decoration: none;
  margin-top: -0.5rem;
  font-weight: 600;
}
.savedLink:hover { text-decoration: underline; }

/* ---------- Mobile ---------- */
@media (max-width: 768px) {
  .shell {
    grid-template-columns: 1fr;
    grid-template-rows: auto 1fr;
    overflow-x: hidden;
  }

  .sidebar {
    position: static;
    height: auto;
    overflow-y: visible;
    border-right: none;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    padding: 1.25rem 1rem;
  }

  .main {
    padding: 1rem;
    overflow-x: hidden;
    min-width: 0;
  }

  .resultsHead {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.75rem;
  }

  .actions {
    flex-wrap: wrap;
    width: 100%;
    gap: 0.5rem;
  }

  .primaryBtn,
  .ghostBtn {
    flex: 1;
    min-width: 0;
    text-align: center;
    font-size: 10px;
    padding: 10px 8px;
  }

  .statStrip {
    grid-template-columns: repeat(2, 1fr);
  }

  .tableWrap {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }

  .table {
    font-size: 12px;
    min-width: 500px;
  }
}

'@
Write-FileSafe 'src/components/dashboard.module.css' $content
Write-Host 'Done.' -ForegroundColor Cyan