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
