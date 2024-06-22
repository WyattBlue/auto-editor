def convert_ass_to_text(ass_text: str) -> str:
    result = ""
    comma_count = i = 0

    while comma_count < 8 and i < len(ass_text):
        if ass_text[i] == ",":
            comma_count += 1
        i += 1

    state = False
    while i < len(ass_text):
        char = ass_text[i]
        next_char = "" if i + 1 >= len(ass_text) else ass_text[i + 1]

        if char == "\\" and next_char == "N":
            result += "\n"
            i += 2
            continue

        if not state:
            if char == "{":
                state = True
            else:
                result += ass_text[i]
        elif char == "}":
            state = False
        i += 1

    return result
