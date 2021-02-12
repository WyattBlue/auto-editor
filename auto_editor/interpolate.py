'''interpolate.py'''

def linear(x: int, y: int, n: int) -> list:
    b = [x]
    step = (y - x) / n
    incre = x
    for i in range(n - 2):
        incre += step
        b.append(incre)

    b.append(y)
    return b


def sine(x: int, y: int, n: int) -> list:
    # slow -> fast -> slow
    import math

    b = [x]
    incre = 0
    for __ in range(n - 2):
        incre += math.pi / n

        val = ((y - x)/2) * math.sin(incre - (math.pi / 2)) + ((y - x)/2) + x
        b.append(val)

    b.append(y)
    return b

def half_sine(x: int, y: int, n: int) -> list:
    # fast -> slow

    import math

    b = [x]
    incre = 0
    for __ in range(n - 2):
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
    elif(method == 'half_sine'):
        return half_sine(x, y, n)
    else:
        log.error(f"Method: {method} isn't implemented.")

