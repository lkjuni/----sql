from functions.get_SOURCE_NODE import get_source_node               #获取起点ID     
from functions.get_route import get_route                           #获取导航路径
from functions.get_gps_location  import get_gps_location            #获取盲人实时位置
from functions.get_direction import get_direction                   #获取盲人实时的朝向
from functions.is_nearby import is_nearby                           #判断盲人是否靠近“关键点”
from functions.speak_instruction import speak_instruction           #语音输出模块
import time                                                         #计时暂停模块
import math



SOURCE_NODE = get_source_node()        # 输入起点、终点的node id 
TARGET_NODE = 102
RIGHT_DIRECTION = 45                   #初始化正确朝向 （导航的不同阶段对应不同的正确朝向）
DIRECTION_TOLERANCE = 10               #盲人朝向与正确朝向的最大误差，一旦超过最大误差就立刻提示盲人   

route_data = get_route(SOURCE_NODE,TARGET_NODE)  ##获取导航信息 
print(route_data)



# 主循环：不断获取GPS位置并播放指令
while True:
    current_location = get_gps_location()  #获取当前盲人位置
    current_direction= get_direction()     #获取盲人当前朝向

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
    if abs(angle_difference) < DIRECTION_TOLERANCE:
        speak_instruction("朝向正确")  ##继续执行，无需语音播报 
    elif 180 > angle_difference > DIRECTION_TOLERANCE:
        speak_instruction(f"请右偏{abs(angle_difference)}度") 
    elif 360 >= angle_difference >= 180:
        speak_instruction(f"请左偏{(360-angle_difference)}度") 
    elif -180 <= angle_difference < -1*DIRECTION_TOLERANCE:
        speak_instruction(f"请左偏{(-1*angle_difference)}度") 
    else: speak_instruction(f"请右偏{360+angle_difference}度")

    time.sleep(1.5)  # 每秒检查一次GPS位置

