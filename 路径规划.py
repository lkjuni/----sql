import psycopg2                       #数据库交互模块
from psycopg2 import OperationalError 
from geopy.distance import geodesic   # 计算两点之间的距离
import math
import get_gps_location  as loc       #获取盲人实时位置
import get_direction as dir           #获取盲人实时的朝向     
import pyttsx3                        #语音输出模块
import time                           #计时暂停模块



# 输入起点终点的node id
StartPoint = 3301
EndPoint = 102

# 数据库查询语句
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
            3301/*{StartPoint}*/,  -- 起点节点 ID
            102/*{EndPoint}*/,  -- 终点节点 ID
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

# 连接数据库并执行查询
try:
    connection = psycopg2.connect(
        dbname="bnuroating03",
        user="postgres",
        password="1612389578lkjlyy",
        host="39.107.254.252",
        port="5432"
    )

    cursor = connection.cursor()
    cursor.execute(query)
    route_data = cursor.fetchall()
    if cursor:
        cursor.close()
    if connection:
        connection.close()
except OperationalError as e:
    print(e)

# 设置语音引擎
def speak_instruction(text):
    engine = pyttsx3.init()
    engine.say(text)
    engine.runAndWait()

# 检查当前位置是否接近路线点
def is_nearby(coord1, coord2, threshold=2):
    # 使用geopy计算两点之间的距离，threshold表示多少米以内算接近
    distance = geodesic(coord1, coord2).meters
    return distance < threshold

print(route_data)

right_direction = 45  #初始化正确朝向
# 主循环：不断获取GPS位置并播放指令
while True:
    current_location = loc.get_gps_location()  #获取当前盲人位置
    current_direction=dir.get_direction() #获取盲人当前朝向

    #检测盲人是否到达导航节点，若到达，播报导航信息+更新right_direction
    for seq, lat, lon, next_azmuth,instruction in route_data:
        route_point = (lat, lon)
        if is_nearby(current_location, route_point):
          right_direction = next_azmuth   #更新 正确的方位 right_direction
          speak_instruction(instruction)
          time.sleep(1)  # 播放语音后等待1秒，避免重复播放
          break  # 避免多次触发同一指令
    
    #比较盲人朝向和正确朝向，生成矫正朝向的导航语音
    angle_difference = round(current_direction - math.degrees(right_direction)) 
    if abs(angle_difference) < 10:
        speak_instruction("朝向正确")  ##继续执行，无需语音播报 
    elif 180 > angle_difference > 10:
        speak_instruction(f"请右偏{abs(angle_difference)}度") 
    elif 360 >= angle_difference >= 180:
        speak_instruction(f"请左偏{(360-angle_difference)}度") 
    elif -180 <= angle_difference < -10:
        speak_instruction(f"请左偏{(-1*angle_difference)}度") 
    else: speak_instruction(f"请右偏{360+angle_difference}度")

    time.sleep(1.5)  # 每秒检查一次GPS位置

