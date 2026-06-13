/**
 * Major US metros for "National Sweep" mode.
 *
 * The free OpenStreetMap/Overpass servers can't handle one nationwide query —
 * it times out. So national coverage works by running the search across these
 * metro centers in sequence and merging the results. This list covers the
 * largest population centers; coordinates are metro centroids.
 *
 * ~50 metros balances coverage against runtime (each is one Overpass call).
 */

export interface Metro {
  name: string;
  lat: number;
  lng: number;
}

export const US_METROS: Metro[] = [
  { name: "New York, NY", lat: 40.7128, lng: -74.006 },
  { name: "Los Angeles, CA", lat: 34.0522, lng: -118.2437 },
  { name: "Chicago, IL", lat: 41.8781, lng: -87.6298 },
  { name: "Houston, TX", lat: 29.7604, lng: -95.3698 },
  { name: "Phoenix, AZ", lat: 33.4484, lng: -112.074 },
  { name: "Philadelphia, PA", lat: 39.9526, lng: -75.1652 },
  { name: "San Antonio, TX", lat: 29.4241, lng: -98.4936 },
  { name: "San Diego, CA", lat: 32.7157, lng: -117.1611 },
  { name: "Dallas, TX", lat: 32.7767, lng: -96.797 },
  { name: "Austin, TX", lat: 30.2672, lng: -97.7431 },
  { name: "San Jose, CA", lat: 37.3382, lng: -121.8863 },
  { name: "Jacksonville, FL", lat: 30.3322, lng: -81.6557 },
  { name: "Fort Worth, TX", lat: 32.7555, lng: -97.3308 },
  { name: "Columbus, OH", lat: 39.9612, lng: -82.9988 },
  { name: "Charlotte, NC", lat: 35.2271, lng: -80.8431 },
  { name: "Indianapolis, IN", lat: 39.7684, lng: -86.1581 },
  { name: "San Francisco, CA", lat: 37.7749, lng: -122.4194 },
  { name: "Seattle, WA", lat: 47.6062, lng: -122.3321 },
  { name: "Denver, CO", lat: 39.7392, lng: -104.9903 },
  { name: "Washington, DC", lat: 38.9072, lng: -77.0369 },
  { name: "Boston, MA", lat: 42.3601, lng: -71.0589 },
  { name: "Nashville, TN", lat: 36.1627, lng: -86.7816 },
  { name: "Oklahoma City, OK", lat: 35.4676, lng: -97.5164 },
  { name: "Las Vegas, NV", lat: 36.1699, lng: -115.1398 },
  { name: "Portland, OR", lat: 45.5152, lng: -122.6784 },
  { name: "Memphis, TN", lat: 35.1495, lng: -90.049 },
  { name: "Louisville, KY", lat: 38.2527, lng: -85.7585 },
  { name: "Baltimore, MD", lat: 39.2904, lng: -76.6122 },
  { name: "Milwaukee, WI", lat: 43.0389, lng: -87.9065 },
  { name: "Albuquerque, NM", lat: 35.0844, lng: -106.6504 },
  { name: "Tucson, AZ", lat: 32.2226, lng: -110.9747 },
  { name: "Fresno, CA", lat: 36.7378, lng: -119.7871 },
  { name: "Sacramento, CA", lat: 38.5816, lng: -121.4944 },
  { name: "Kansas City, MO", lat: 39.0997, lng: -94.5786 },
  { name: "Atlanta, GA", lat: 33.749, lng: -84.388 },
  { name: "Miami, FL", lat: 25.7617, lng: -80.1918 },
  { name: "Raleigh, NC", lat: 35.7796, lng: -78.6382 },
  { name: "Omaha, NE", lat: 41.2565, lng: -95.9345 },
  { name: "Minneapolis, MN", lat: 44.9778, lng: -93.265 },
  { name: "Tampa, FL", lat: 27.9506, lng: -82.4572 },
  { name: "New Orleans, LA", lat: 29.9511, lng: -90.0715 },
  { name: "Cleveland, OH", lat: 41.4993, lng: -81.6944 },
  { name: "St. Louis, MO", lat: 38.627, lng: -90.1994 },
  { name: "Pittsburgh, PA", lat: 40.4406, lng: -79.9959 },
  { name: "Cincinnati, OH", lat: 39.1031, lng: -84.512 },
  { name: "Orlando, FL", lat: 28.5383, lng: -81.3792 },
  { name: "Salt Lake City, UT", lat: 40.7608, lng: -111.891 },
  { name: "Detroit, MI", lat: 42.3314, lng: -83.0458 },
  { name: "Richmond, VA", lat: 37.5407, lng: -77.436 },
  { name: "Birmingham, AL", lat: 33.5186, lng: -86.8104 },
];
