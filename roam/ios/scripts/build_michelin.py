#!/usr/bin/env python3
"""Builds Roam/Resources/michelin.tsv (compact, bundled) from the open michelin-my-maps dataset.

Usage: python3 scripts/build_michelin.py path/to/michelin_my_maps.csv
Columns out: name, lat, lng, price(1-4), cuisine, award(0 selected,1 bib,2-4 stars), city, url
The app also refreshes this monthly on Wi-Fi from the dataset's GitHub copy.
"""
import csv, sys, os

AWARDS = {"Selected Restaurants": 0, "Bib Gourmand": 1, "1 Star": 2, "2 Stars": 3, "3 Stars": 4}

def clean(s):
    return (s or "").replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()

def main(src):
    out = os.path.join(os.path.dirname(__file__), "..", "Roam", "Resources", "michelin.tsv")
    n = 0
    with open(src, encoding="utf-8") as f, open(out, "w", encoding="utf-8") as o:
        for r in csv.DictReader(f):
            award = next((v for k, v in AWARDS.items() if k.lower() in (r["Award"] or "").lower()), None)
            try:
                lat, lng = float(r["Latitude"]), float(r["Longitude"])
            except ValueError:
                continue
            if award is None or (abs(lat) < 1e-4 and abs(lng) < 1e-4):
                continue
            price = min(4, max(1, len((r["Price"] or "").strip()))) if (r["Price"] or "").strip() else 2
            o.write("\t".join([clean(r["Name"]), f"{lat:.6f}", f"{lng:.6f}", str(price), clean(r["Cuisine"]),
                               str(award), clean(r["Location"]), clean(r["Url"])]) + "\n")
            n += 1
    print(f"wrote {n} restaurants to {os.path.normpath(out)}")

if __name__ == "__main__":
    main(sys.argv[1])
