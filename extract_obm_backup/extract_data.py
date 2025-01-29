#!./venv/bin/python

import pandas as pd
import json
import sys
import os
import re
from settings import SERVER_URL, PROJECT

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


def main(filename):
    server_url = SERVER_URL
    project_name = PROJECT

    bn = os.path.basename(filename).split('.')[0]

    with open(filename, 'r') as bak:
        data = json.load(bak)

        servers = json.loads(data['servers'])
        
        server = list(filter(lambda x: x['url'] == server_url,
                             servers['data']))
        
        server_data = server[0]['databases']['data']
        
        project_data = list(filter(lambda x: x['name'] == project_name,
                                   server_data))
        
        project_observations = project_data[0]['observations']['data']
        
        for po in project_observations:
            if 'measurements' in po:
                measurements_data = list(filter(lambda x: 'data' in x and 'isSynced' in x and x['isSynced'] == False,
                                                po['measurements']['data']))
                measurements_data_data = list(map(lambda x: x['data'],
                                                  measurements_data))
                measurements_data_data = list(map(geom_to_wkt,
                                                  measurements_data_data))
                df = pd.DataFrame(measurements_data_data)
                df.to_csv('output/' + bn + '_' + po['id']
                          + '.csv', index=False)

                print(bn + ': ' + str(df.shape[0]))

def loop(folder):
    for filename in os.scandir(folder):
        try:
            if filename.is_file():
                main(filename.path)
        except Exception as e:
            continue

if __name__ == '__main__':
    try:
        filename = sys.argv[1]
        if os.path.isfile(filename):
            main(filename)
        else:
            loop(filename)
    except Exception as e:
        raise
