import { NextRequest, NextResponse } from "next/server";
import { enrichWebsite } from "@/lib/enrich";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(req: NextRequest) {
  let body: { website?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  if (!body.website?.trim()) {
    return NextResponse.json({ error: "No website provided." }, { status: 400 });
  }

  const result = await enrichWebsite(body.website);
  return NextResponse.json(result);
}
