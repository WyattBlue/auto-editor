import av

c = av.open("/Users/wyattblue/Downloads/(Hi10)_New_Game!_-_01_(720p)_(Doki-Kuusou)_(0EFA884A).mkv")

for s in c.streams:
    print(s)
