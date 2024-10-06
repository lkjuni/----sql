import psycopg2                                   #数据库交互模块
from psycopg2 import OperationalError 

def get_route(source_node,target_node):
  query = f'''     
  --A*算法
  WITH nodelist AS(
      SELECT  seq,
              node,
              (SELECT ST_Transform(geom, 4326) FROM all_nodes r WHERE r.id = node) AS geom,
              (SELECT ST_X(ST_Transform(geom, 4326)) FROM all_nodes r WHERE r.id = node)  AS lon,
              (SELECT ST_Y(ST_Transform(geom, 4326)) FROM all_nodes r WHERE r.id = node)  AS lat,
              (SELECT class FROM all_nodes r WHERE r.id = node)  AS class
      FROM pgr_astar(
              'SELECT id AS id,
                  source, target, 
                  ST_Length(geom) AS cost,
                  ST_X(ST_StartPoint(geom)) AS x1, 
                  ST_Y(ST_StartPoint(geom)) AS y1, 
                  ST_X(ST_EndPoint(geom)) AS x2, 
                  ST_Y(ST_EndPoint(geom)) AS y2     
              FROM aaa
              ',
              3301/*{source_node}*/,  -- 起点节点 ID
              102/*{target_node}*/,  -- 终点节点 ID
              directed:=false
              )

      )

  , angles AS(  
      SELECT
      seq,
      node,
      geom,
      lat,
      lon,
      class,
      LEAD(geom) OVER (ORDER BY seq) AS next_geom,
      LAG(geom) OVER (ORDER BY seq)  AS prev_geom,
      CASE
        WHEN LAG(geom) OVER (ORDER BY seq) IS NULL THEN NULL
        ELSE ST_Azimuth(LAG(geom) OVER (ORDER BY seq), geom)
      END AS prev_azimuth,
      CASE
        WHEN LEAD(geom) OVER (ORDER BY seq)  IS NULL THEN NULL
        ELSE ST_Azimuth(geom, LEAD(geom) OVER (ORDER BY seq))
      END AS next_azimuth
    
    FROM nodelist
    WHERE class != '3' or seq = 1)


  SELECT
    seq,lat,lon,next_azimuth, 
    CASE
      when class = '3' and seq!=1 THEN null
      WHEN next_azimuth IS NULL THEN '到达终点'
      WHEN prev_azimuth IS NULL THEN '出发'
      WHEN abs(next_azimuth - prev_azimuth) < radians(15) THEN '继续直行'||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
      WHEN next_azimuth - prev_azimuth < 0 THEN '到达路口，左转，然后直行'||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
      ELSE '到达路口，右转，然后直行' ||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
    END AS instruction
  FROM
    angles;  --坐标系是wgs84

  '''   #查询语句
  try:                                  # 连接数据库并执行查询
      connection = psycopg2.connect(
          dbname="bnuroating03",
          user="postgres",
          password="1612389578lkjlyy",
          host="39.107.254.252",
          port="5432"
      )
      cursor = connection.cursor()
      cursor.execute(query)
      route = cursor.fetchall()
      if cursor:
          cursor.close()
      if connection:
          connection.close()
      return route
  except OperationalError as e:
        print(e)
