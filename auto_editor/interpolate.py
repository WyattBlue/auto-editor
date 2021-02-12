'''interpolate.py'''

import math

def linear(x: int, y: int, n: int) -> list:
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

def sine(x, y, n: int) -> list:
    # slow -> fast -> slow

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += math.pi / n

        val = ((y - x)/2) * math.sin(incre - (math.pi / 2)) + ((y - x)/2) + x
        b.append(val)

    b.append(y)
    return b

def start_sine(x, y, n: int) -> list:
    # slow -> fast

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += math.pi / n
        val = ((y - x)/2) * math.sin(incre - (math.pi / 2)) + ((y - x)/2) + x
        b.append(val)

    b.append(y)
    return b

def end_sine(x, y, n: int) -> list:
    # fast -> slow

    b = [x]
    incre = 0
    for _ in range(n - 2):
        incre += (math.pi / 2) / n

        val = x + math.sin(incre) * (y - x)
        b.append(val)

    b.append(y)
    return b

def interpolate(x, y, n, log, method='linear') -> list:
    if(method == 'linear'):
        return linear(x, y, n)
    elif(method == 'sine'):
        return sine(x, y, n)
    elif(method == 'start_sine'):
        return start_sine(x, y, n)
    elif(method == 'end_sine'):
        return end_sine(x, y, n)
    else:
        log.error(f"Method: {method} isn't implemented.")
