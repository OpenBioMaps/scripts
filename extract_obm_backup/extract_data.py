#!./venv/bin/python
import pandas as pd
import json
import sys
from os.path import basename
from settings import SERVER_URL, PROJECT


def geom_to_wkt(row):
    if row is None:
        return None
    lat = row['obm_geometry']['latitude']
    lng = row['obm_geometry']['longitude']
    row['obm_geometry'] = 'POINT(' + str(lng) + ' ' + str(lat) + ')'
    return row


def main(filename):
    server_url = SERVER_URL
    project_name = PROJECT

    bn = basename(filename).split('.')[0]

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
                measurements_data = list(filter(lambda x: 'data' in x,
                                                po['measurements']['data']))
                measurements_data_data = list(map(lambda x: x['data'],
                                                  measurements_data))
                measurements_data_data = list(map(geom_to_wkt,
                                                  measurements_data_data))
                df = pd.DataFrame(measurements_data_data)
                df.to_csv('output/' + bn + '_' + po['id']
                          + '.csv', index=False)

                print(bn + ': ' + str(df.shape[0]))

if __name__ == '__main__':
    try:
        filename = sys.argv[1]
        main(filename)
    except Exception as e:
        raise
