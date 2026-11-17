cmake_minimum_required(VERSION 3.16)
project(car_pc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# ------------------------------------------------------------------ Qt 位置
# 本机：Qt 5.12.9 + MinGW 7.3.0 64-bit
# 换机器时改这一行，或命令行传 -DCMAKE_PREFIX_PATH=...
if(NOT DEFINED CMAKE_PREFIX_PATH)
    set(CMAKE_PREFIX_PATH "E:/SoftWare/QT/Qt5.12.9/5.12.9/mingw73_64")
endif()

# A 阶段只用 Core/Gui/Widgets，少一个 DLL 依赖、少一个失败点。
# B 阶段接串口时，把下面第二行打开、第一行注释掉：
find_package(Qt5 5.12 REQUIRED COMPONENTS Core Gui Widgets)
# find_package(Qt5 5.12 REQUIRED COMPONENTS Core Gui Widgets SerialPort)

# ------------------------------------------------------------------ 主程序
add_executable(car_pc
    src/main.cpp
    src/protocol/protocol.h
    src/protocol/protocol.cpp
    src/source/ICarSource.h        # 纯接口、无同名 .cpp —— 必须显式列出，否则 AUTOMOC 不会 moc 它
    src/source/FakeCar.h
    src/source/FakeCar.cpp
    src/app/CarController.h
    src/app/CarController.cpp
    src/ui/MainWindow.h
    src/ui/MainWindow.cpp
)


target_include_directories(car_pc PRIVATE src)
target_link_libraries(car_pc PRIVATE Qt5::Core Qt5::Gui Qt5::Widgets)

# ------------------------------------------------------------------ 协议单测
# 不依赖 Qt，可以用任意编译器单独构建
add_executable(test_protocol
    src/protocol/protocol.cpp
    tests/test_protocol.cpp
)
target_include_directories(test_protocol PRIVATE src)
# 单测没有任何 Q_OBJECT，关掉 moc 省时间
set_target_properties(test_protocol PROPERTIES AUTOMOC OFF)