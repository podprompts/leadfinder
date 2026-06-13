import {
  parsePhoneNumberFromString,
  type PhoneNumber,
} from "libphonenumber-js";

/**
 * Free phone validation via libphonenumber-js (runs in our own code, no API).
 *
 * Honest limitation: this validates STRUCTURE (is it a well-formed, possible
 * US number, what type, what region) — it does NOT confirm the line is
 * actively connected. Live-connection checking always costs money (Twilio
 * Lookup etc.) and is the natural paid upgrade, slotted in the same way the
 * Google provider is.
 */

export type PhoneType =
  | "mobile"
  | "landline"
  | "voip"
  | "toll_free"
  | "fixed_or_mobile"
  | "unknown";

export interface PhoneCheck {
  raw: string;
  valid: boolean;
  formatted: string | null;
  e164: string | null;
  type: PhoneType;
}

function mapType(n: PhoneNumber): PhoneType {
  const t = n.getType();
  switch (t) {
    case "MOBILE":
      return "mobile";
    case "FIXED_LINE":
      return "landline";
    case "VOIP":
      return "voip";
    case "TOLL_FREE":
      return "toll_free";
    case "FIXED_LINE_OR_MOBILE":
      return "fixed_or_mobile";
    default:
      return "unknown";
  }
}

export function checkPhone(raw: string | null | undefined): PhoneCheck | null {
  if (!raw || !raw.trim()) return null;

  const parsed = parsePhoneNumberFromString(raw, "US");
  if (!parsed) {
    return { raw, valid: false, formatted: null, e164: null, type: "unknown" };
  }

  return {
    raw,
    valid: parsed.isValid(),
    formatted: parsed.formatNational(),
    e164: parsed.number,
    type: mapType(parsed),
  };
}
