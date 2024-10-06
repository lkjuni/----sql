# 检查当前位置是否接近路线点
from geopy.distance import geodesic                                   #计算两点之间的距离

def is_nearby(coordinate1, coordinate2, threshold=2):
    # 使用geopy计算两点之间的距离，threshold表示多少米以内算接近
    distance = geodesic(coordinate1, coordinate2).meters
    return distance < threshold
