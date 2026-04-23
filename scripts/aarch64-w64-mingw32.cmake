set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER aarch64-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER llvm-windres)

# find_program resolves full paths from PATH, which CMAKE_AR requires
find_program(CMAKE_AR llvm-ar REQUIRED)
find_program(CMAKE_RANLIB llvm-ranlib REQUIRED)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
