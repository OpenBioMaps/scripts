import csv
from datetime import datetime
from statistics import mean

CPU_MAX_W = 60  # watt
MEM_W_PER_GB = 3
NET_W_PER_MB = 0.001  # elhanyagolható
DISK_W_PER_MB = 0.002  # elhanyagolható

def estimate_power(cpu_pct, mem_gb, net_mb, disk_mb):
    cpu_power = (cpu_pct / 100) * CPU_MAX_W
    mem_power = mem_gb * MEM_W_PER_GB
    net_power = net_mb * NET_W_PER_MB
    disk_power = disk_mb * DISK_W_PER_MB
    total = cpu_power + mem_power + net_power + disk_power
    return total  # watt

def main():
    data = []
    with open("sysload_log.csv") as f:
        reader = csv.reader(f)
        for row in reader:
            try:
                _, cpu, mem, net, disk = row
                data.append(estimate_power(float(cpu), float(mem), float(net), float(disk)))
            except Exception:
                continue

    if data:
        avg_watt = mean(data)
        est_kwh_day = avg_watt * 24 / 1000
        est_kwh_month = est_kwh_day * 30

        print(f"Átlagos teljesítmény: {avg_watt:.2f} W")
        print(f"Napi energiafogyasztás: {est_kwh_day:.2f} kWh")
        print(f"Havi energiafogyasztás: {est_kwh_month:.2f} kWh")
    else:
        print("Nincs elérhető adat a becsléshez.")

if __name__ == "__main__":
    main()
