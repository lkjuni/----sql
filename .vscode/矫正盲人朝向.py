import math

def calculate_target_bearing(current_lat, current_lon, target_lat, target_lon):
    # 将纬度和经度从度数转换为弧度
    lat1 = math.radians(current_lat)
    lon1 = math.radians(current_lon)
    lat2 = math.radians(target_lat)
    lon2 = math.radians(target_lon)
    
    delta_lon = lon2 - lon1
    
    x = math.sin(delta_lon) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(delta_lon)
    
    bearing = math.atan2(x, y)
    bearing = math.degrees(bearing)
    bearing = (bearing + 360) % 360  # 将结果转换为0-360度
    return bearing

