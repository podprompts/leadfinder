import type { BusinessCategory } from "./types";

/**
 * Central category definitions. Each entry knows:
 *  - how to label itself in the UI
 *  - which OpenStreetMap tags identify it (free provider)
 *  - which Google Places type/keyword identifies it (paid provider, ready to use)
 *
 * Add a category once here and every provider + the UI picks it up.
 */
export interface CategoryDef {
  key: BusinessCategory;
  label: string;
  /** OSM tag filters, OR'd together. Format: "key=value" or "key~regex" */
  osmFilters: string[];
  /** Google Places (New) text query keyword */
  googleKeyword: string;
}

export const CATEGORIES: CategoryDef[] = [
  {
    key: "handyman",
    label: "Handyman",
    osmFilters: ['craft=handyman', 'shop=trade', 'craft=builder'],
    googleKeyword: "handyman",
  },
  {
    key: "general_contractor",
    label: "General Contractor",
    osmFilters: ['craft=builder', 'office=construction_company', 'craft=carpenter'],
    googleKeyword: "general contractor",
  },
  {
    key: "hvac",
    label: "HVAC",
    osmFilters: ['craft=hvac', 'craft=heating_engineer', 'trade=hvac'],
    googleKeyword: "hvac contractor",
  },
  {
    key: "plumber",
    label: "Plumber",
    osmFilters: ['craft=plumber'],
    googleKeyword: "plumber",
  },
  {
    key: "electrician",
    label: "Electrician",
    osmFilters: ['craft=electrician'],
    googleKeyword: "electrician",
  },
  {
    key: "roofer",
    label: "Roofer",
    osmFilters: ['craft=roofer'],
    googleKeyword: "roofing contractor",
  },
  {
    key: "landscaper",
    label: "Landscaper",
    osmFilters: ['craft=gardener', 'shop=garden_centre', 'craft=landscape'],
    googleKeyword: "landscaper",
  },
  {
    key: "painter",
    label: "Painter",
    osmFilters: ['craft=painter'],
    googleKeyword: "painting contractor",
  },
  {
    key: "locksmith",
    label: "Locksmith",
    osmFilters: ['craft=locksmith', 'shop=locksmith'],
    googleKeyword: "locksmith",
  },
  {
    key: "pest_control",
    label: "Pest Control",
    osmFilters: ['craft=pest_control'],
    googleKeyword: "pest control",
  },
  {
    key: "cleaning",
    label: "Cleaning Service",
    osmFilters: ['craft=cleaning', 'shop=cleaning', 'office=cleaning'],
    googleKeyword: "cleaning service",
  },
  {
    key: "flooring",
    label: "Flooring",
    osmFilters: ['craft=floorer', 'shop=flooring'],
    googleKeyword: "flooring contractor",
  },
];

export const CATEGORY_MAP: Record<string, CategoryDef> = Object.fromEntries(
  CATEGORIES.map((c) => [c.key, c])
);

export function categoryLabel(key: string): string {
  return CATEGORY_MAP[key]?.label ?? key;
}
