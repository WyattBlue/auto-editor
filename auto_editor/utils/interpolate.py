'''utils/interpolate.py'''

import math

def linear(x, y, n):
    # type: (float, int, int) -> list[int | float]
    b = [x]
    step = (y - x) / n
    incre = x
    for _ in range(n - 2):
        incre += step
        b.append(incre)

    b.append(y)
    return b

# See how these formulas are derived:
# - https://www.desmos.com/calculator/jj4tociyb4

def sine(x, y, n):
    # type: (int, int, int) -> list[int | float]
    # slow -> fast -> slow

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += math.pi / n

        val = ((y - x)/2) * math.sin(incre - (math.pi / 2)) + ((y - x)/2) + x
        b.append(val)

    b.append(y)
    return b

# TODO: fix so it's not that same as sine()
def start_sine(x, y, n):
    # type: (int, int, int) -> list[int | float]
    # slow -> fast

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += math.pi / n
        val = ((y - x)/2) * math.sin(incre - (math.pi / 2)) + ((y - x)/2) + x
        b.append(val)

    b.append(y)
    return b

def end_sine(x, y, n):
    # type: (int, int, int) -> list[int | float]
    # fast -> slow

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += (math.pi / 2) / n

        val = x + math.sin(incre) * (y - x)
        b.append(val)

    b.append(y)
    return b

def interpolate(x, y, n, log, method='linear'):
    # type: (int, int, int, Any, str) -> list[int | float]
    if(method == 'linear'):
        return linear(x, y, n)
    if(method == 'sine'):
        return sine(x, y, n)
    if(method == 'start_sine'):
        return start_sine(x, y, n)
    if(method == 'end_sine'):
        return end_sine(x, y, n)

    log.error("Method: {} isn't implemented.".format(method))
