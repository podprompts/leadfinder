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
import { NextRequest, NextResponse } from "next/server";

const COOKIE = "lf_auth";

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Always allow login page and API auth route
  if (pathname === "/login" || pathname.startsWith("/api/auth/")) {
    return NextResponse.next();
  }

  const expected = (process.env.LEADFINDER_PASSWORD ?? "").trim();
  const token = (req.cookies.get(COOKIE)?.value ?? "").trim();

  if (expected && token === expected) {
    return NextResponse.next();
  }

  const loginUrl = req.nextUrl.clone();
  loginUrl.pathname = "/login";
  loginUrl.searchParams.set("from", pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|favicon.png).*)",
  ],
};

'@
Write-FileSafe 'src/middleware.ts' $content
$content = @'
import { NextRequest, NextResponse } from "next/server";

const COOKIE = "lf_auth";
const COOKIE_MAX_AGE = 60 * 60 * 24 * 30;

export async function POST(req: NextRequest) {
  const { password } = await req.json();
  const expected = (process.env.LEADFINDER_PASSWORD ?? "").trim();
  const provided = (password ?? "").trim();

  if (!expected) {
    return NextResponse.json({ error: "Password not configured." }, { status: 500 });
  }

  if (provided !== expected) {
    return NextResponse.json({ error: "Incorrect password." }, { status: 401 });
  }

  const res = NextResponse.json({ ok: true });
  res.cookies.set(COOKIE, expected, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: COOKIE_MAX_AGE,
    path: "/",
  });
  return res;
}

'@
Write-FileSafe 'src/app/api/auth/login/route.ts' $content
Write-Host 'Done.' -ForegroundColor Cyan