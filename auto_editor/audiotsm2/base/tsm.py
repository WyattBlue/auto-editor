'''audiotsm2/base/tsm.py'''

class TSM():
    def run(self, reader, writer, flush=True):
        finished = False
        while not (finished and reader.empty):
            self.read_from(reader)
            _, finished = self.write_to(writer)

        if flush:
            finished = False
            while not finished:
                _, finished = self.flush_to(writer)

            self.clear()
