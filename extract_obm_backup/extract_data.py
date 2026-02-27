#!./venv/bin/python

import json
import os
import re
import sys

import pandas as pd

try:
    from settings import SERVER_URL, PROJECT
except Exception:
    SERVER_URL = None
    PROJECT = None

def is_point_wkt(value):
    if not isinstance(value, str):
        return False
    pattern = r'^POINT\s*\(\s*(-?\d+(\.\d+)?)\s+(-?\d+(\.\d+)?)\s*\)$'
    return re.match(pattern, value) is not None

def is_latitude_longitude_dict(value):
    if not isinstance(value, dict):
        return False

    if 'latitude' in value and 'longitude' in value:
        return True
    else:
        return False

def geom_to_wkt(row):
    if row is None:
        return None
    if 'obm_geometry' in row.keys():
        if is_latitude_longitude_dict(row['obm_geometry']):
            lat = row['obm_geometry']['latitude']
            lng = row['obm_geometry']['longitude']
            row['obm_geometry'] = 'POINT(' + str(lng) + ' ' + str(lat) + ')'
        elif is_point_wkt(row['obm_geometry']):
            row['obm_geometry'] = row['obm_geometry']
        # {'wktType': 'point', 'wktValue': {'latitude': 46.9372883, 'longitude': 17.8206134, 'accuracy': 3, 'timestamp': 1708604561321}}
        elif isinstance(row['obm_geometry'], dict) and 'wktType' in row['obm_geometry'].keys() and row['obm_geometry']['wktType'] == 'point':
            wktValue = row['obm_geometry']['wktValue']
            row['obm_geometry'] = 'POINT(' + str(wktValue['longitude']) + ' ' + str(wktValue['latitude']) + ')'
        # do nothing
        else:
            row['obm_geometry'] = str(row['obm_geometry'])

    return row


def safe_get(obj, *keys, default=None):
    cur = obj
    for key in keys:
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            return default
    return cur


def parse_servers(data):
    raw = data.get('servers')
    if raw is None:
        raise ValueError("Missing 'servers' key in backup JSON.")
    if isinstance(raw, str):
        servers = json.loads(raw)
    elif isinstance(raw, dict):
        servers = raw
    else:
        raise ValueError("Unsupported 'servers' type in backup JSON.")

    servers_data = safe_get(servers, 'data', default=[])
    if not isinstance(servers_data, list):
        raise ValueError("Invalid servers format: expected list in servers['data'].")
    return servers_data


def choose_from_list(items, prompt, label_fn=str, default_index=None):
    if not items:
        return None

    print()
    for idx, item in enumerate(items, start=1):
        print(f"{idx}. {label_fn(item)}")

    while True:
        default_hint = f" [Enter = {default_index + 1}]" if default_index is not None else ""
        choice = input(f"{prompt}{default_hint}: ").strip()
        if choice == "" and default_index is not None:
            return items[default_index]
        if choice.lower() in {"q", "quit", "exit"}:
            return None
        if choice.isdigit():
            index = int(choice) - 1
            if 0 <= index < len(items):
                return items[index]
        print("Érvénytelen választás. Add meg a sorszámot, vagy 'q' a kilépéshez.")


def choose_multiple_from_list(items, prompt, label_fn=str):
    if not items:
        return []

    print()
    for idx, item in enumerate(items, start=1):
        print(f"{idx}. {label_fn(item)}")

    while True:
        choice = input(f"{prompt} (pl.: 1,3,5 vagy 'all'): ").strip().lower()
        if choice in {"all", "*"}:
            return items
        if choice in {"q", "quit", "exit"}:
            return []
        indices = []
        ok = True
        for part in choice.split(","):
            part = part.strip()
            if not part.isdigit():
                ok = False
                break
            idx = int(part) - 1
            if idx < 0 or idx >= len(items):
                ok = False
                break
            indices.append(idx)
        if ok and indices:
            return [items[i] for i in indices]
        print("Érvénytelen lista. Add meg sorszámokat vesszővel, 'all' vagy 'q'.")


def ask_yes_no(prompt, default=True):
    default_hint = "I/n" if default else "i/N"
    while True:
        choice = input(f"{prompt} [{default_hint}]: ").strip().lower()
        if choice == "":
            return default
        if choice in {"i", "igen", "y", "yes"}:
            return True
        if choice in {"n", "nem", "no"}:
            return False
        print("Érvénytelen válasz. Írj 'i' vagy 'n'.")


def export_project_observations(project, base_name, output_dir, only_unsynced=True, observations=None):
    observations_data = safe_get(project, 'observations', 'data', default=[])
    if not isinstance(observations_data, list):
        raise ValueError("Invalid project format: observations['data'] must be a list.")

    if observations is None:
        observations = observations_data

    exported = 0
    for obs in observations:
        measurements = safe_get(obs, 'measurements', 'data', default=[])
        if not isinstance(measurements, list):
            continue

        if only_unsynced:
            measurements = [
                x for x in measurements
                if isinstance(x, dict) and x.get('isSynced') is False and 'data' in x
            ]
        else:
            measurements = [
                x for x in measurements
                if isinstance(x, dict) and 'data' in x
            ]

        if not measurements:
            continue

        rows = [geom_to_wkt(x['data']) for x in measurements if 'data' in x]
        df = pd.DataFrame(rows)
        obs_id = str(obs.get('id', 'unknown'))
        out_path = os.path.join(output_dir, f"{base_name}_{obs_id}.csv")
        df.to_csv(out_path, index=False)
        exported += df.shape[0]
        print(f"{base_name}: {df.shape[0]} sor -> {out_path}")

    return exported


def observation_stats(project):
    observations_data = safe_get(project, 'observations', 'data', default=[])
    if not isinstance(observations_data, list):
        return (0, 0, 0)

    total = len(observations_data)
    with_measurements = 0
    with_unsynced = 0

    for obs in observations_data:
        measurements = safe_get(obs, 'measurements', 'data', default=[])
        if not isinstance(measurements, list):
            continue

        has_any = any(isinstance(x, dict) and 'data' in x for x in measurements)
        has_unsynced = any(
            isinstance(x, dict) and x.get('isSynced') is False and 'data' in x
            for x in measurements
        )

        if has_any:
            with_measurements += 1
        if has_unsynced:
            with_unsynced += 1

    return (total, with_measurements, with_unsynced)


def main(filename):
    bn = os.path.splitext(os.path.basename(filename))[0]

    with open(filename, 'r', encoding='utf-8') as bak:
        data = json.load(bak)

    servers = parse_servers(data)
    if not servers:
        print("Nincs elérhető szerver a backupban.")
        return

    def server_label(s):
        projects = safe_get(s, 'databases', 'data', default=[])
        if not isinstance(projects, list):
            return s.get('url', '<ismeretlen>')

        projects_with_data = 0
        for p in projects:
            total, with_measurements, _with_unsynced = observation_stats(p)
            if with_measurements > 0:
                projects_with_data += 1

        url = s.get('url', '<ismeretlen>')
        return f"{url} (projektek exportálható megfigyelésekkel: {projects_with_data}/{len(projects)})"

    default_server_index = None
    if SERVER_URL:
        for i, s in enumerate(servers):
            if s.get('url') == SERVER_URL:
                default_server_index = i
                break

    server = choose_from_list(
        servers,
        "Válassz szervert",
        label_fn=server_label,
        default_index=default_server_index,
    )
    if server is None:
        print("Kilépés: nincs kiválasztott szerver.")
        return

    projects = safe_get(server, 'databases', 'data', default=[])
    if not isinstance(projects, list) or not projects:
        print("A kiválasztott szerverhez nem található projekt.")
        return

    def project_label(p):
        name = p.get('name', '<névtelen>')
        total, with_measurements, with_unsynced = observation_stats(p)
        return (
            f"{name} (megfigyelések: {total}, "
            f"exportálható: {with_measurements}, "
            f"nem szinkronizált: {with_unsynced})"
        )

    default_project_index = None
    if PROJECT:
        for i, p in enumerate(projects):
            if p.get('name') == PROJECT:
                default_project_index = i
                break

    project = choose_from_list(
        projects,
        "Válassz projektet",
        label_fn=project_label,
        default_index=default_project_index,
    )
    if project is None:
        print("Kilépés: nincs kiválasztott projekt.")
        return

    observations_data = safe_get(project, 'observations', 'data', default=[])
    if not isinstance(observations_data, list) or not observations_data:
        print("A kiválasztott projektben nincs megfigyelés.")
        return

    only_unsynced = ask_yes_no("Csak a nem szinkronizált méréseket mentsem?", default=True)
    pick_obs = ask_yes_no("Szeretnél konkrét megfigyeléseket kiválasztani?", default=False)
    observations = None
    if pick_obs:
        def obs_label(o):
            obs_id = o.get('id', '<nincs id>')
            obs_name = o.get('name')
            if obs_name:
                return f"{obs_id} - {obs_name}"
            return f"{obs_id}"
        observations = choose_multiple_from_list(
            observations_data,
            "Válassz megfigyeléseket",
            label_fn=obs_label,
        )
        if not observations:
            print("Nincs kiválasztott megfigyelés.")
            return

    output_dir = os.path.join(os.getcwd(), "output")
    os.makedirs(output_dir, exist_ok=True)

    total = export_project_observations(
        project,
        bn,
        output_dir,
        only_unsynced=only_unsynced,
        observations=observations,
    )
    print(f"Kész. Összes exportált sor: {total}")

def loop(folder):
    for filename in os.scandir(folder):
        try:
            if filename.is_file():
                main(filename.path)
        except Exception as e:
            print(f"Hiba ({filename.path}): {e}")
            continue

if __name__ == '__main__':
    try:
        filename = sys.argv[1]
        if os.path.isfile(filename):
            main(filename)
        else:
            loop(filename)
    except Exception as e:
        print(f"Hiba: {e}")
        sys.exit(1)
