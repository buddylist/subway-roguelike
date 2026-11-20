"""Stand Clear backend: ghost teams, station turf and finished runs.

Deploy:  pip install modal && modal setup && modal deploy backend/app.py
Modal prints a URL like https://<workspace>--stand-clear-api.modal.run. Put it in
ios/project.yml (StandClearAPI) and regenerate the Xcode project.

Storage is two modal.Dicts, so there's no database to run. It scales to zero when
nobody's riding. There's no auth: anyone with the URL can post teams. Fine for a toy.
"""

import random
import time

import modal

app = modal.App("stand-clear")
image = modal.Image.debian_slim().pip_install("fastapi[standard]")
ghosts = modal.Dict.from_name("stand-clear-ghosts", create_if_missing=True)  # "L:3" -> [ghost, ...]
board = modal.Dict.from_name("stand-clear-board", create_if_missing=True)    # "turf:L" -> {...}, "runs" -> [...]

KEEP_PER_ROUND = 50
MAX_TEAM = 5


@app.function(image=image)
@modal.asgi_app()
def api():
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.responses import HTMLResponse

    web = FastAPI(title="Stand Clear")

    def clean_ghost(g: dict) -> dict:
        try:
            return {
                "player": str(g["player"])[:24] or "anon",
                "line": str(g["line"])[:2],
                "round": max(1, min(int(g["round"]), 100)),
                "team": list(g["team"])[:MAX_TEAM],
            }
        except (KeyError, TypeError, ValueError):
            raise HTTPException(400, "bad ghost")

    @web.post("/teams")
    async def post_team(req: Request):
        g = clean_ghost(await req.json())
        if not g["team"]:
            return {"ok": True}
        key = f'{g["line"]}:{g["round"]}'
        lst = ghosts.get(key, [])
        lst.append(g)
        ghosts[key] = lst[-KEEP_PER_ROUND:]
        return {"ok": True}

    # "from" is a Python keyword, so read the query string by hand.
    @web.get("/ghosts")
    def ghosts_for(req: Request):
        q = req.query_params
        line = q.get("line", "L")[:2]
        lo = max(1, int(q.get("from", 1)))
        hi = min(lo + 10, int(q.get("to", lo + 5)))
        out = []
        for rnd in range(lo, hi + 1):
            lst = ghosts.get(f"{line}:{rnd}", [])
            out += random.sample(lst, min(3, len(lst)))
        return out

    @web.get("/turf")
    def get_turf(line: str):
        held = board.get(f"turf:{line[:2]}", {})
        return {station: v["player"] for station, v in held.items()}

    @web.post("/turf")
    async def post_turf(req: Request):
        c = await req.json()
        key = f'turf:{str(c.get("line", ""))[:2]}'
        held = board.get(key, {})
        held[str(c.get("station", ""))[:8]] = {"player": str(c.get("player", "anon"))[:24], "team": list(c.get("team", []))[:MAX_TEAM], "at": time.time()}
        board[key] = held
        return {"ok": True}

    @web.post("/runs")
    async def post_run(req: Request):
        r = await req.json()
        r["at"] = time.time()
        runs = board.get("runs", [])
        runs.append(r)
        board["runs"] = runs[-200:]
        return {"ok": True}

    @web.get("/", response_class=HTMLResponse)
    def home():
        """A tiny status page, so the bare URL isn't a 404."""
        import html
        runs = list(reversed(board.get("runs", [])))[:15]
        turf = {k[5:]: v for k, v in board.items() if k.startswith("turf:")}
        rows = "".join(f"<li>{'🏁' if r.get('madeIt') else '💀'} <b>{html.escape(str(r.get('player','?')))}</b> on the {html.escape(str(r.get('line','?')))}: "
                       f"{r.get('wins',0)} wins, {r.get('stops',0)} stops, ended at {html.escape(str(r.get('endedAt','?')))}</li>" for r in runs) or "<li>No runs yet. Go ride.</li>"
        held = "".join(f"<li>{html.escape(line)} {html.escape(st)}: 👑 {html.escape(v['player'])}</li>" for line, t in turf.items() for st, v in t.items()) or "<li>Nobody holds anything yet.</li>"
        return f"""<!doctype html><meta name=viewport content="width=device-width"><title>Stand Clear</title>
<body style="background:#111;color:#eee;font:16px Helvetica;max-width:560px;margin:auto;padding:16px">
<h1>🚇 Stand Clear backend</h1><p>It's up. Ghost crews, station turf and runs live here.
API docs: <a style="color:#fccc0a" href="/docs">/docs</a></p>
<h2>Recent runs</h2><ul>{rows}</ul><h2>Turf</h2><ul>{held}</ul></body>"""

    @web.get("/runs")
    def get_runs(limit: int = 20):
        """Latest finished runs. Tim's fridge bridge can poll this."""
        return list(reversed(board.get("runs", [])))[: max(1, min(limit, 200))]

    return web
