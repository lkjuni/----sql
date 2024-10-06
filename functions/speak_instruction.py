import pyttsx3 
def speak_instruction(text):          # 设置语音引擎
    engine = pyttsx3.init()
    engine.say(text)
    engine.runAndWait()
