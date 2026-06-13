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
