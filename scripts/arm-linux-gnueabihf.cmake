set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

find_program(CMAKE_AR arm-linux-gnueabihf-ar REQUIRED)
find_program(CMAKE_RANLIB arm-linux-gnueabihf-ranlib REQUIRED)

set(CMAKE_C_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv3 -mfloat-abi=hard")
set(CMAKE_CXX_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv3 -mfloat-abi=hard")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
