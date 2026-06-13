# LeadFinder updater v8 - adds eye icon to password field.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'package.json')) { Write-Host 'Run from leadfinder folder.' -ForegroundColor Red; exit 1 }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-FileSafe($path, $content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $path) -and -not (Test-Path "$path.bak")) { Copy-Item $path "$path.bak" }
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), $content, $utf8NoBom)
  Write-Host "  updated $path" -ForegroundColor Green
}

# ---- src/app/login/page.tsx ----
$content = @'
"use client";

import { useState, Suspense } from "react";
import { useSearchParams } from "next/navigation";

function LoginForm() {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const searchParams = useSearchParams();
  const from = searchParams.get("from") ?? "/";

  const [showPassword, setShowPassword] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    if (res.ok) {
      window.location.href = from;
    } else {
      setError("Incorrect password.");
      setLoading(false);
    }
  }

  return (
    <div style={{
      minHeight: "100vh",
      background: "#0d0d0d",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      padding: "1.5rem",
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    }}>
      <div style={{
        background: "#141414",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: "12px",
        padding: "2.5rem 2rem",
        width: "100%",
        maxWidth: "360px",
        textAlign: "center",
      }}>
        <div style={{ fontSize: "2rem", marginBottom: "0.75rem" }}>&#9670;</div>
        <h1 style={{
          color: "#fff", fontSize: "1.4rem",
          fontWeight: 800, marginBottom: "0.5rem",
        }}>LeadFinder</h1>
        <p style={{
          color: "rgba(255,255,255,0.4)",
          fontSize: "13px", marginBottom: "1.75rem",
        }}>Home services lead extraction</p>

        {error && (
          <div style={{
            background: "rgba(232,69,10,0.1)",
            border: "1px solid rgba(232,69,10,0.3)",
            color: "#ff8a5c", fontSize: "13px",
            padding: "10px 14px", marginBottom: "1rem",
            borderRadius: "6px",
          }}>{error}</div>
        )}

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
          <div style={{ position: "relative" }}>
            <input
              type={showPassword ? "text" : "password"}
              placeholder="Enter password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              autoFocus
              required
              style={{
                width: "100%",
                padding: "13px 44px 13px 16px",
                fontSize: "15px",
                border: "1px solid rgba(255,255,255,0.12)",
                background: "#161616",
                color: "#fff",
                outline: "none",
                borderRadius: "6px",
                textAlign: "center",
                boxSizing: "border-box",
              }}
            />
            <button
              type="button"
              onClick={() => setShowPassword(v => !v)}
              style={{
                position: "absolute",
                right: "12px",
                top: "50%",
                transform: "translateY(-50%)",
                background: "transparent",
                border: "none",
                cursor: "pointer",
                color: "rgba(255,255,255,0.4)",
                padding: "4px",
                display: "flex",
                alignItems: "center",
              }}
              aria-label={showPassword ? "Hide password" : "Show password"}
            >
              {showPassword ? (
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/>
                  <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/>
                  <line x1="1" y1="1" x2="23" y2="23"/>
                </svg>
              ) : (
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                  <circle cx="12" cy="12" r="3"/>
                </svg>
              )}
            </button>
          </div>
          <button
            type="submit"
            disabled={loading || !password}
            style={{
              width: "100%",
              padding: "13px",
              background: loading || !password ? "rgba(255,255,255,0.1)" : "#e8521a",
              color: loading || !password ? "rgba(255,255,255,0.3)" : "#fff",
              border: "none",
              borderRadius: "6px",
              fontSize: "13px",
              fontWeight: 800,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              cursor: loading || !password ? "default" : "pointer",
              transition: "background 0.12s",
            }}
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

'@
Write-FileSafe 'src/app/login/page.tsx' $content

Write-Host 'Done. Now push to GitHub: git add . && git commit -m "Add eye icon" && git push origin master' -ForegroundColor Cyan