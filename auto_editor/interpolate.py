'''interpolate.py'''

def linear(x, y, n) -> list:
    b = [x]
    step = (y - x) / n
    incre = x
    for i in range(n - 2):
        incre += step
        b.append(incre)

    b.append(y)
    return b


def interpolate(x, y, n, log, method='linear') -> list:
    if(method == 'linear'):
        return linear(x, y, n)
    else:
        log.error(f"Method: {method} isn't implemented.")
