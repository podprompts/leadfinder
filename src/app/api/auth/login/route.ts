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
