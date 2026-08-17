proc smoothing*(val: var seq[bool], mincut, minclip: int) {.raises: [].} =
  # A lone run shorter than both minclip and mincut flips forever (all-true
  # -> all-false -> all-true); checking two states back exits that 2-cycle.
  var prev, prev2: seq[bool]
  while prev != val and prev2 != val:
    prev2 = prev
    prev = val
    var next = prev
    var startP = 0
    var active = false

    for j, item in prev.pairs:
      if item == true:
        if not active:
          startP = j
          active = true

        # j is the run's last index here (inclusive), not one-past like the
        # interior case below, so the run length needs the +1.
        if j == len(prev) - 1 and j - startP + 1 < minclip:
          for i in startP ..< prev.len:
            next[i] = false
      elif active:
        if j - startP < minclip:
          for i in startP ..< j:
            next[i] = false
        active = false

    startP = 0
    active = false

    for j, item in prev.pairs:
      if item == false:
        if not active:
          startP = j
          active = true

        if j == len(prev) - 1 and j - startP + 1 < mincut:
          for i in startP ..< prev.len:
            next[i] = true
      elif active:
        if j - startP < mincut:
          for i in startP ..< j:
            next[i] = true
        active = false

    val = next

proc mutMargin*(arr: var seq[bool], startM, endM: int) {.raises: [].} =
  # Find start and end indexes
  var startIndex = newSeqOfCap[int](32)
  var endIndex = newSeqOfCap[int](32)
  let arrlen = len(arr)
  for j in 1 ..< arrlen:
    if arr[j] != arr[j - 1]:
      if arr[j]:
        startIndex.add j
      else:
        endIndex.add j

  # Apply margin
  if startM > 0:
    for i in startIndex:
      for k in max(i - startM, 0) ..< i:
        arr[k] = true

  if startM < 0:
    for i in startIndex:
      for k in i ..< min(i - startM, arrlen):
        arr[k] = false

  if endM > 0:
    for i in endIndex:
      for k in i ..< min(i + endM, arrlen):
        arr[k] = true

  if endM < 0:
    for i in endIndex:
      for k in max(i + endM, 0) ..< i:
        arr[k] = false
