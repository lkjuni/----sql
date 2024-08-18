def calculate_angle_difference(current_bearing, target_bearing):
    diff = target_bearing - current_bearing
    if diff > 180:
        diff -= 360
    elif diff < -180:
        diff += 360
    return diff

# 根据角度差生成导航指令
def generate_navigation_instruction(angle_difference):
    if abs(angle_difference) < 10:
        return "Continue straight"
    elif angle_difference > 10:
        return "Turn right"
    elif angle_difference < -10:
        return "Turn left"