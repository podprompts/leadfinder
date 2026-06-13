import { NextRequest, NextResponse } from "next/server";

const PASSWORD = process.env.LEADFINDER_PASSWORD ?? "changeme";
const COOKIE = "lf_auth";
const COOKIE_MAX_AGE = 60 * 60 * 24 * 30; // 30 days

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Always allow the login page and its POST action
  if (pathname === "/login") return NextResponse.next();

  // Check auth cookie
  const token = req.cookies.get(COOKIE)?.value;
  if (token === PASSWORD) return NextResponse.next();

  // Not authenticated — redirect to login
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
