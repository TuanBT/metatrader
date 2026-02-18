#!/usr/bin/env python3
"""
Analyze SL Distance Distribution for BTC M5 Strategy
Goal: Understand why 99% of trades get blocked by MaxSLRisk=10%
"""

import re
import statistics
from collections import Counter

# Sample from latest log - BTC M5 trades that got blocked
log_data = """
2025.01.04 06:55:00   Risk: 15.2% ($152.42) > MaxSLRisk=10.0%   SL Distance: 1524.2 pips
2025.01.04 09:30:00   Risk: 17.8% ($178.2) > MaxSLRisk=10.0%    SL Distance: 1782.0 pips  
2025.01.04 21:05:00   Risk: 41.0% ($410.35) > MaxSLRisk=10.0%   SL Distance: 4103.5 pips
2025.01.04 22:05:00   Risk: 29.1% ($290.76) > MaxSLRisk=10.0%   SL Distance: 2907.6 pips
2025.01.05 18:00:00   Risk: 11.7% ($116.91) > MaxSLRisk=10.0%   SL Distance: 1169.1 pips
2025.01.05 19:30:00   Risk: 21.7% ($217.49) > MaxSLRisk=10.0%   SL Distance: 2174.9 pips
2025.01.05 22:40:00   Risk: 52.0% ($519.5) > MaxSLRisk=10.0%    SL Distance: 5195.0 pips
2025.01.06 12:15:00   Risk: 35.6% ($355.74) > MaxSLRisk=10.0%   SL Distance: 3557.4 pips
2025.01.06 15:20:00   Risk: 91.6% ($915.94) > MaxSLRisk=10.0%   SL Distance: 9159.4 pips
2025.01.06 22:10:00   Risk: 39.8% ($397.51) > MaxSLRisk=10.0%   SL Distance: 3975.1 pips
2025.01.07 07:05:00   Risk: 11.5% ($114.95) > MaxSLRisk=10.0%   SL Distance: 1149.5 pips
2025.01.07 11:10:00   Risk: 14.3% ($142.82) > MaxSLRisk=10.0%   SL Distance: 1428.2 pips
2025.01.07 15:40:00   Risk: 67.5% ($675.49) > MaxSLRisk=10.0%   SL Distance: 6754.9 pips
2025.01.07 17:35:00   Risk: 77.1% ($771.35) > MaxSLRisk=10.0%   SL Distance: 7713.5 pips
2025.01.08 05:55:00   Risk: 29.7% ($297.02) > MaxSLRisk=10.0%   SL Distance: 2970.2 pips
2025.01.08 10:10:00   Risk: 19.9% ($199.41) > MaxSLRisk=10.0%   SL Distance: 1994.1 pips
2025.01.08 17:45:00   Risk: 39.4% ($393.67) > MaxSLRisk=10.0%   SL Distance: 3936.7 pips
2025.01.08 22:10:00   Risk: 69.0% ($689.96) > MaxSLRisk=10.0%   SL Distance: 6899.6 pips
2025.01.08 22:40:00   Risk: 101.3% ($1012.5) > MaxSLRisk=10.0%  SL Distance: 10125.0 pips
2025.01.09 04:30:00   Risk: 61.4% ($613.81) > MaxSLRisk=10.0%   SL Distance: 6138.1 pips
2025.01.09 09:40:00   Risk: 66.2% ($662.08) > MaxSLRisk=10.0%   SL Distance: 6620.8 pips
2025.01.09 20:15:00   Risk: 49.8% ($497.98) > MaxSLRisk=10.0%   SL Distance: 4979.8 pips
2025.01.10 04:15:00   Risk: 23.0% ($229.78) > MaxSLRisk=10.0%   SL Distance: 2297.8 pips
2025.01.10 09:50:00   Risk: 28.5% ($284.75) > MaxSLRisk=10.0%   SL Distance: 2847.5 pips
2025.01.10 15:15:00   Risk: 28.1% ($280.56) > MaxSLRisk=10.0%   SL Distance: 2805.6 pips
2025.01.10 18:10:00   Risk: 71.4% ($714.39) > MaxSLRisk=10.0%   SL Distance: 7143.9 pips
2025.01.11 06:00:00   Risk: 37.6% ($375.98) > MaxSLRisk=10.0%   SL Distance: 3759.8 pips
2025.01.11 11:30:00   Risk: 11.6% ($116.34) > MaxSLRisk=10.0%   SL Distance: 1163.4 pips
2025.01.11 15:05:00   Risk: 14.9% ($149.05) > MaxSLRisk=10.0%   SL Distance: 1490.5 pips
2025.01.12 07:15:00   Risk: 15.0% ($150.33) > MaxSLRisk=10.0%   SL Distance: 1503.3 pips
2025.01.12 09:10:00   Risk: 10.6% ($106.26) > MaxSLRisk=10.0%   SL Distance: 1062.6 pips
2025.01.12 11:45:00   Risk: 23.6% ($235.77) > MaxSLRisk=10.0%   SL Distance: 2357.7 pips
2025.01.12 14:30:00   Risk: 45.6% ($456.24) > MaxSLRisk=10.0%   SL Distance: 4562.4 pips
2025.01.12 19:00:00   Risk: 22.5% ($225.39) > MaxSLRisk=10.0%   SL Distance: 2253.9 pips
2025.01.12 19:40:00   Risk: 16.2% ($162.16) > MaxSLRisk=10.0%   SL Distance: 1621.6 pips
2025.01.13 02:45:00   Risk: 113.5% ($1135.07) > MaxSLRisk=10.0% SL Distance: 11350.7 pips
2025.01.13 11:05:00   Risk: 56.1% ($560.65) > MaxSLRisk=10.0%   SL Distance: 5606.5 pips
2025.01.13 21:25:00   Risk: 65.4% ($653.52) > MaxSLRisk=10.0%   SL Distance: 6535.2 pips
2025.01.14 09:10:00   Risk: 28.4% ($283.63) > MaxSLRisk=10.0%   SL Distance: 2836.3 pips
2025.01.14 10:05:00   Risk: 36.7% ($366.59) > MaxSLRisk=10.0%   SL Distance: 3665.9 pips
2025.01.14 13:10:00   Risk: 34.6% ($346.3) > MaxSLRisk=10.0%    SL Distance: 3463.0 pips
2025.01.14 16:40:00   Risk: 57.6% ($575.71) > MaxSLRisk=10.0%   SL Distance: 5757.1 pips
2025.01.15 09:55:00   Risk: 20.9% ($209.05) > MaxSLRisk=10.0%   SL Distance: 2090.5 pips
2025.01.15 13:25:00   Risk: 25.4% ($254.39) > MaxSLRisk=10.0%   SL Distance: 2539.4 pips
"""

def extract_sl_distances():
    """Extract SL distances (in pips) from log data"""
    pattern = r"SL Distance: ([\d,]+\.?\d*) pips"
    matches = re.findall(pattern, log_data)
    
    distances = []
    for match in matches:
        # Remove commas and convert to float
        distance = float(match.replace(',', ''))
        distances.append(distance)
    
    return distances

def analyze_distribution(distances):
    """Analyze the distribution of SL distances"""
    print("=" * 70)
    print("BTC M5 SL DISTANCE ANALYSIS")
    print("=" * 70)
    print(f"Total blocked trades: {len(distances)}")
    print(f"Min SL Distance: {min(distances):,.1f} pips")
    print(f"Max SL Distance: {max(distances):,.1f} pips")
    print(f"Mean SL Distance: {statistics.mean(distances):,.1f} pips")
    print(f"Median SL Distance: {statistics.median(distances):,.1f} pips")
    print()
    
    # Quartiles
    q1 = statistics.quantiles(distances, n=4)[0]  # 25th percentile
    q3 = statistics.quantiles(distances, n=4)[2]  # 75th percentile
    print(f"Q1 (25th percentile): {q1:,.1f} pips")
    print(f"Q3 (75th percentile): {q3:,.1f} pips")
    print(f"IQR: {q3-q1:,.1f} pips")
    print()
    
    # Distribution ranges
    ranges = [
        (0, 1000),
        (1000, 2000),
        (2000, 3000),
        (3000, 5000),
        (5000, 7000),
        (7000, 10000),
        (10000, float('inf'))
    ]
    
    print("DISTRIBUTION BY RANGES:")
    for start, end in ranges:
        if end == float('inf'):
            count = sum(1 for d in distances if d >= start)
            print(f"  {start:,}+ pips: {count:2d} trades ({count/len(distances)*100:.1f}%)")
        else:
            count = sum(1 for d in distances if start <= d < end)
            print(f"  {start:,}-{end:,} pips: {count:2d} trades ({count/len(distances)*100:.1f}%)")
    print()
    
    # Risk % analysis (lot 0.01, balance $1000)
    print("RISK % ANALYSIS (0.01 lot, $1000 balance):")
    balance = 1000
    lot = 0.01
    for d in [1000, 2000, 3000, 5000, 7000, 10000]:
        risk_pct = (d * lot) / balance * 100
        print(f"  {d:,} pips → {risk_pct:.1f}% risk")
    print()
    
    # Calculate what MaxSLRisk would need to be
    print("REQUIRED MaxSLRisk TO ALLOW TRADES:")
    percentiles = [50, 75, 90, 95, 99]
    for p in percentiles:
        threshold = statistics.quantiles(distances, n=100)[p-1]
        risk_pct = (threshold * lot) / balance * 100
        print(f"  {p}% of trades: MaxSLRisk ≥ {risk_pct:.1f}% (SL ≤ {threshold:.0f} pips)")

if __name__ == "__main__":
    distances = extract_sl_distances()
    if distances:
        analyze_distribution(distances)
    else:
        print("No SL distance data found!")