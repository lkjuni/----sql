import psycopg2                                         #数据库交互模块
from psycopg2 import OperationalError 

from functions.get_gps_location import get_gps_location #获取初始定位

def get_source_node():
    original_location=get_gps_location()
    
    query = f'''SELECT id   
    FROM all_nodes   
    ORDER BY ST_Distance \
    (all_nodes.geom, ST_SetSRID(ST_MakePoint({original_location[0]},{original_location[1]}), 3857))   
    LIMIT 1;''' #查询语句
    try:                                  # 连接数据库并执行查询
      connection = psycopg2.connect(
          dbname="bnuroating03",
          user="postgres",
          password="yahboom",
          host="39.107.254.252",
          port="5432"
      )
      cursor = connection.cursor()
      cursor.execute(query)
      target = cursor.fetchall()
      if cursor:
          cursor.close()
      if connection:
          connection.close()
      return target
    except OperationalError as e:
        print(e)

