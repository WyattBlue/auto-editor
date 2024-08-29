from .palet import Syntax


def all() -> dict[str, object]:
    return {
        "get-current-env": Syntax(lambda env, node: env.data.copy()),
        "proc-name": Syntax(
            lambda env, node: [proc := node[1].val, env[proc].name][-1]
        ),
    }
