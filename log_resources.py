import psutil
import datetime
import time

t0_net = psutil.net_io_counters()
t0_disk = psutil.disk_io_counters()

cpu = psutil.cpu_percent(interval=60)
vmem = psutil.virtual_memory()
actual_used_mem = (vmem.total - vmem.available) / (1024 ** 3)  # GB

t1_net = psutil.net_io_counters()
t1_disk = psutil.disk_io_counters()

net_delta_bytes = (t1_net.bytes_sent + t1_net.bytes_recv) - (t0_net.bytes_sent + t0_net.bytes_recv)
disk_delta_bytes = (t1_disk.read_bytes + t1_disk.write_bytes) - (t0_disk.read_bytes + t0_disk.write_bytes)

now = datetime.datetime.now().isoformat()

data = {
    "timestamp": now,
    "cpu_percent": cpu,
    "mem_used_gb": actual_used_mem,
    "net_delta_mb": net_delta_bytes / (1024 ** 2),
    "disk_delta_mb": disk_delta_bytes / (1024 ** 2),
}

with open("/home/banm/sysload_log.csv", "a") as f:
    f.write(
        f"{data['timestamp']},{data['cpu_percent']:.2f},{data['mem_used_gb']:.2f},{data['net_delta_mb']:.2f},{data['disk_delta_mb']:.2f}\n"
    )
