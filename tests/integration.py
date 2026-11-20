"""Exercise the public stdio contract against disposable libraries."""
import concurrent.futures
import contextlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

SERVER = str(Path(sys.argv.pop(1)).resolve())
PROTOCOL = "2025-11-25"


class Client:
    def __init__(self, db, *flags):
        self.proc = subprocess.Popen([SERVER, "--db", str(db), *flags],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, encoding="utf-8")
        self.seq = 0

    def send(self, packet):
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", **packet}) + "\n")
        self.proc.stdin.flush()

    def rpc(self, method, params=None, *, raw=False):
        """raw=True sends `params` exactly as given; None omits the member, like the TypeScript SDK."""
        self.seq += 1
        packet = {"method": method, "id": self.seq}
        if raw:
            if params is not None:
                packet["params"] = params
        else:
            packet["params"] = params or {}
        self.send(packet)
        line = self.proc.stdout.readline()
        if not line:
            raise AssertionError(self.proc.stderr.read())
        reply = json.loads(line)
        assert reply["id"] == self.seq, reply
        return reply

    def initialize(self):
        result = self.rpc("initialize", {"protocolVersion": PROTOCOL, "capabilities": {},
                          "clientInfo": {"name": "acceptance", "version": "1"}})["result"]
        assert result["protocolVersion"] == PROTOCOL and "tools" in result["capabilities"]
        self.send({"method": "notifications/initialized"})
        return self

    def call(self, tool, *, error=None, **args):
        result = self.rpc("tools/call", {"name": tool, "arguments": args})["result"]
        data = json.loads(result["content"][0]["text"])
        assert result["isError"] == bool(error), data
        if error:
            assert data["code"] == error, data
        return data

    def close(self):
        self.proc.stdin.close()
        try:
            assert self.proc.wait(timeout=5) == 0
            assert not self.proc.stdout.read(), "Unexpected stdout after EOF"
            assert not self.proc.stderr.read(), "Unexpected diagnostic output"
        finally:
            self.proc.kill()
            self.proc.stdout.close()
            self.proc.stderr.close()


class Contract(unittest.TestCase):
    def setUp(self):
        self.directory = self.enterContext(tempfile.TemporaryDirectory())
        self.db = Path(self.directory) / "biblioteca.sqlite3"
        self.client = self.connect()

    def connect(self, *flags):
        c = Client(self.db, *flags)
        self.addCleanup(c.close)
        return c.initialize()

    def test_unicode_persistence_search_and_paging(self):
        blocks = [{"type": t, "text": "Árbol 日本語 🌱 " + t}
                  for t in ("heading", "paragraph", "list", "task")]
        c = self.client
        p = c.call("create_page", title="Bitácora", blocks=blocks)
        other = self.connect()
        for offset in (0, 2):
            page = other.call("get_page", id=p["id"], limit=2, cursor=offset)
            self.assertEqual(page["blocks"][0]["text"], blocks[offset]["text"])
            self.assertEqual(page["next_cursor"], 2 if offset == 0 else None)
        other.call("create_page", title="Árbol de ideas")
        first = c.call("search_notes", query="ÁRBOL", limit=1)
        second = c.call("search_notes", query="ÁRBOL", limit=1, cursor=first["next_cursor"])
        self.assertNotEqual(first["pages"][0]["id"], second["pages"][0]["id"])
        self.assertIn("árbol", first["pages"][0]["snippet"].lower())
        self.assertIsNone(second["next_cursor"])
        self.assertIsNone(c.call("list_pages")["pages"][0]["parent_id"])

    def test_idempotency_atomicity_and_block_identity(self):
        c = self.client
        args = {"title": "A", "operation_key": "op-1"}
        p = c.call("create_page", **args)
        self.assertEqual(self.connect().call("create_page", **args), p)
        c.call("create_page", title="B", operation_key="op-1", error="operation_conflict")
        insert = {"op": "insert", "block": {"type": "task", "text": "Leer"}}
        bad = {"op": "move", "block_id": p["id"], "index": 3}
        expected = {"id": p["id"], "expected_revision": 1}
        c.call("apply_block_changes", **expected, changes=[insert,bad], error="invalid_argument")
        self.assertEqual(c.call("get_page", id=p["id"])["blocks"], [])
        change = dict(**expected, changes=[insert,insert], operation_key="op-2")
        r = c.call("apply_block_changes", **change)
        self.assertEqual(c.call("apply_block_changes", **change), r)
        a,b = c.call("get_page", id=p["id"])["blocks"]
        c.call("apply_block_changes", id=p["id"], expected_revision=2, changes=[
            {"op":"move","block_id":b["id"],"index":0},
            {"op":"remove","block_id":a["id"]},
            {"op":"update","block_id":b["id"],"block":{"type":"task","text":"Listo","checked":True}}])
        last = c.call("get_page", id=p["id"])["blocks"]
        self.assertEqual(last, [dict(b, checked=True, text="Listo")])

    def test_competing_processes(self):
        c = self.client
        p = c.call("create_page", title="Inicial")
        other = self.connect()
        def race(client, title):
            return client.rpc("tools/call", {"name":"update_page", "arguments":{
                "id":p["id"], "expected_revision":1, "title":title}})["result"]
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            replies = list(pool.map(race, [c,other], ["Primero","Segundo"]))
        self.assertEqual(sorted(r["isError"] for r in replies), [False,True])
        fail = next(r for r in replies if r["isError"])
        self.assertEqual(json.loads(fail["content"][0]["text"])["code"], "revision_conflict")
        with contextlib.closing(sqlite3.connect(self.db)) as db:
            db.execute("BEGIN IMMEDIATE")
            c.call("update_page", id=p["id"], expected_revision=2, title="Bloqueo", error="database_busy")
            db.rollback()
            self.assertEqual(db.execute("select count(*) from revisions").fetchone()[0], 2)

    def test_tree_and_separate_trash_batches(self):
        c = self.client
        root = c.call("create_page", title="Raíz")["id"]
        child = c.call("create_page", title="Hija", parent_id=root)["id"]
        nested = c.call("create_page", title="Nieta", parent_id=child)["id"]
        c.call("update_page", id=root, expected_revision=1, parent_id=nested, error="invalid_argument")
        c.call("trash_page", id=nested, expected_revision=1)
        self.assertEqual(c.call("trash_page", id=root, expected_revision=1)["affected"], 2)
        self.assertEqual(set(p["id"] for p in c.call("list_pages",trashed=True)["pages"]), {root,nested})
        self.assertEqual(c.call("search_notes",query="Hija")["pages"], [])
        self.assertEqual(c.call("restore_page", id=root, expected_revision=2)["affected"], 2)
        self.assertEqual(c.call("list_pages", parent_id=root)["pages"][0]["id"], child)
        self.assertEqual(c.call("list_pages", parent_id=child)["pages"], [])
        c.call("trash_page", id=root, expected_revision=3)
        c.call("restore_page", id=nested, expected_revision=2)
        self.assertIsNone(c.call("get_page", id=nested)["parent_id"])

    def test_readonly_discovery_and_validation(self):
        c = self.client
        ro = self.connect("--read-only")
        self.assertEqual(len(c.rpc("tools/list")["result"]["tools"]), 8)
        # Claude Desktop and Claude Code send tools/list and ping without params.
        self.assertEqual(len(c.rpc("tools/list", raw=True)["result"]["tools"]), 8)
        self.assertEqual(c.rpc("ping", raw=True)["result"], {})
        self.assertEqual(c.send({"method": "tools/list", "params": None, "id": 900}), None)
        self.assertEqual(len(json.loads(c.proc.stdout.readline())["result"]["tools"]), 8)
        self.assertEqual(c.rpc("tools/list", [], raw=True)["error"]["code"], -32602)
        tools = ro.rpc("tools/list")["result"]["tools"]
        self.assertEqual(len(tools), 3)
        self.assertTrue(all(t["annotations"]["readOnlyHint"] for t in tools))
        ro.call("create_page",title="No",error="read_only")
        for args in ({"query":"  "},{"query":"x","limit":0},{"query":"x","limit":True},{"query":"x","unexpected":1}):
            ro.call("search_notes",**args,error="invalid_argument")
        c.call("create_page",title=" ",error="invalid_argument")
        c.call("create_page",title="x",blocks=[{"type":"heading","text":"x","checked":True}],error="invalid_argument")
        c.call("get_page",id="00000000-0000-0000-0000-000000000000",error="not_found")
        self.assertEqual(c.rpc("nonexistent")["error"]["code"], -32601)
        # Comment threads travel with their span: author, time, state and replies.
        thread = {"id": "t1", "author": "Ana", "at": "2026-11-19T16:31:00Z", "resolved": False,
                  "replies": [{"author": "Luis", "at": "2026-11-19T16:40:00Z", "text": "Hecho"}]}
        page = c.call("create_page", title="Hilos", blocks=[{"type": "paragraph", "text": "Revisar esto",
                      "spans": [{"start": 0, "end": 7, "style": 0, "comment": "¿Fuente?", "thread": thread}]}])
        span = c.call("get_page", id=page["id"])["blocks"][0]["spans"][0]
        self.assertEqual(span["thread"], thread)
        for bad in ({"start": 0, "end": 7, "style": 0, "thread": {"id": "t2"}},
                    {"start": 0, "end": 7, "style": 0, "comment": "x", "thread": {"author": "Ana"}},
                    {"start": 0, "end": 7, "style": 0, "comment": "x", "thread": {"id": "t3", "extra": 1}}):
            c.call("create_page", title="Mal", blocks=[{"type": "paragraph", "text": "Revisar esto", "spans": [bad]}],
                   error="invalid_argument")

    def test_block_types_and_page_look(self):
        c = self.client
        blocks = [{"type": "heading", "text": "Uno", "level": 2}, {"type": "numbered", "text": "a"},
                  {"type": "numbered", "text": "b", "indent": 1}, {"type": "toggle", "text": "Más", "collapsed": True},
                  {"type": "paragraph", "text": "dentro", "indent": 1}, {"type": "quote", "text": "cita"},
                  {"type": "callout", "text": "ojo", "icon": "⚠️"}, {"type": "code", "text": "x = 1\ny = 2"},
                  {"type": "divider", "text": ""}]
        page = c.call("create_page", title="Bloques", icon="🎮", cover="gradient:aurora", blocks=blocks)
        got = c.call("get_page", id=page["id"])
        self.assertEqual((got["icon"], got["cover"]), ("🎮", "gradient:aurora"))
        self.assertEqual([b["type"] for b in got["blocks"]], [b["type"] for b in blocks])
        self.assertEqual((got["blocks"][0]["level"], got["blocks"][2]["indent"], got["blocks"][3]["collapsed"]), (2, 1, True))
        for bad in ({"type": "paragraph", "text": "x", "level": 2}, {"type": "divider", "text": "no"},
                    {"type": "quote", "text": "x", "icon": "⚠️"}, {"type": "list", "text": "x", "indent": 9},
                    {"type": "paragraph", "text": "x", "collapsed": True}, {"type": "heading", "text": "x", "level": 4}):
            c.call("create_page", title="Mal", blocks=[bad], error="invalid_argument")
        c.call("update_page", id=page["id"], expected_revision=got["revision"], cover="photo:" + "a" * 64, error="invalid_argument")
        c.call("update_page", id=page["id"], expected_revision=got["revision"], cover="degradado", error="invalid_argument")
        c.call("update_page", id=page["id"], expected_revision=got["revision"], icon=None, cover=None)
        again = c.call("get_page", id=page["id"])
        self.assertEqual((again["icon"], again["cover"], again["title"]), (None, None, "Bloques"))
        # Page mentions are links to lunqio://page/<id>; other lunqio:// targets are refused.
        mention = {"start": 4, "end": 11, "style": 0, "link": "lunqio://page/" + page["id"]}
        note = c.call("create_page", title="Mención", blocks=[{"type": "paragraph", "text": "Ver Bloques", "spans": [mention]}])
        self.assertEqual(c.call("get_page", id=note["id"])["blocks"][0]["spans"], [mention])
        for target in ("lunqio://otra", "lunqio://page/" + page["id"].upper(), "lunqio://page/123"):
            c.call("create_page", title="Mal", error="invalid_argument",
                   blocks=[{"type": "paragraph", "text": "Ver Bloques", "spans": [dict(mention, link=target)]}])
        # Renaming a page updates the mentions that still read its old title; the spans after them move too.
        link = "lunqio://page/" + page["id"]
        notes = c.call("create_page", title="Notas", blocks=[{"type": "paragraph", "text": "Ver Bloques y Bloques, mis bloques",
                       "spans": [{"start": 4, "end": 11, "style": 0, "link": link}, {"start": 14, "end": 21, "style": 1},
                                 {"start": 23, "end": 34, "style": 0, "link": link}]}])
        current = c.call("get_page", id=page["id"])["revision"]
        c.call("update_page", id=page["id"], expected_revision=current, title="Piezas")
        renamed = c.call("get_page", id=notes["id"])
        self.assertEqual(renamed["revision"], 2)
        self.assertEqual(renamed["blocks"][0]["text"], "Ver Piezas y Bloques, mis bloques")
        self.assertEqual([(s["start"], s["end"]) for s in renamed["blocks"][0]["spans"]], [(4, 10), (13, 20), (22, 33)])

    def test_text_look_and_page_typography(self):
        c = self.client
        blocks = [{"type": "paragraph", "text": "Hola mundo", "align": "center", "color": "blue", "background": "yellow",
                   "spans": [{"start": 0, "end": 4, "style": 1, "color": "red", "background": "gray"}]},
                  {"type": "heading", "text": "Plan", "level": 2, "align": "right"}]
        page = c.call("create_page", title="Aspecto", font="serif", small_text=True, blocks=blocks)
        got = c.call("get_page", id=page["id"])
        self.assertEqual((got["font"], got["small_text"], got["full_width"]), ("serif", True, False))
        self.assertEqual([{k: b.get(k) for k in ("align", "color", "background")} for b in got["blocks"]],
                         [{"align": "center", "color": "blue", "background": "yellow"}, {"align": "right", "color": None, "background": None}])
        self.assertEqual(got["blocks"][0]["spans"][0]["color"], "red")
        c.call("update_page", id=page["id"], expected_revision=got["revision"], font="mono", full_width=True)
        again = c.call("get_page", id=page["id"])
        self.assertEqual((again["font"], again["small_text"], again["full_width"]), ("mono", True, True))
        for bad in ({"type": "divider", "text": "", "align": "center"}, {"type": "paragraph", "text": "x", "color": "cyan"},
                    {"type": "paragraph", "text": "x", "align": "middle"},
                    {"type": "paragraph", "text": "xy", "spans": [{"start": 0, "end": 1, "style": 0, "background": "teal"}]}):
            c.call("create_page", title="Mal", blocks=[bad], error="invalid_argument")
        c.call("create_page", title="Mal", font="comic", error="invalid_argument")
        # Pages written before typography existed read as the default look.
        self.assertEqual(c.call("get_page", id=c.call("create_page", title="Normal")["id"])["font"], "sans")

    def test_blocks_round_trip(self):
        # What get_page returns can be sent back unchanged: no block carries "spans": null.
        c = self.client
        page = c.call("create_page", title="Ida y vuelta", blocks=[{"type": "paragraph", "text": "Sin formato"},
                      {"type": "heading", "text": "Título", "level": 2}])
        got = c.call("get_page", id=page["id"])
        self.assertTrue(all("spans" not in b or b["spans"] is not None for b in got["blocks"]))
        c.call("create_page", title="Copia", blocks=[{k: v for k, v in b.items() if k != "id"} for b in got["blocks"]])
        same = {k: v for k, v in got["blocks"][0].items() if k != "id"}
        c.call("apply_block_changes", id=page["id"], expected_revision=got["revision"],
               changes=[{"op": "update", "block_id": got["blocks"][0]["id"], "block": same}])

    def test_search_without_accents(self):
        c = self.client
        c.call("create_page", title="Bitácora", blocks=[{"type": "paragraph", "text": "Árbol del patio"}])
        c.call("create_page", title="Árbol genealógico")
        c.call("create_page", title="Arbol")
        found = c.call("search_notes", query="arbol")["pages"]
        # The title itself first, then titles that start with it, then pages that mention it.
        self.assertEqual([p["title"] for p in found], ["Arbol", "Árbol genealógico", "Bitácora"])
        self.assertEqual(found[2]["snippet"], "Árbol del patio")
        self.assertEqual([p["title"] for p in c.call("search_notes", query="GENEALOGICO")["pages"]], ["Árbol genealógico"])

    def test_full_restart_and_schema_guard(self):
        db = Path(self.directory) / "reinicio.sqlite3"
        first = Client(db).initialize()
        with contextlib.closing(first):
            p = first.call("create_page", title="Mañana 🌄",
                           blocks=[{"type":"paragraph","text":"日本語"}])
        with contextlib.closing(Client(db).initialize()) as restarted:
            read = restarted.call("get_page", id=p["id"])
            self.assertEqual(read["title"], "Mañana 🌄")
            self.assertEqual(read["blocks"][0]["text"], "日本語")
        with contextlib.closing(sqlite3.connect(db)) as future:
            future.execute("PRAGMA user_version=99")
        rejected = subprocess.run([SERVER,"--db",str(db)], input=b"", capture_output=True, timeout=8)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(rejected.stdout, b"")
        with contextlib.closing(sqlite3.connect(db)) as unchanged:
            self.assertEqual(unchanged.execute("PRAGMA user_version").fetchone()[0], 99)
            self.assertEqual(unchanged.execute("select title from pages").fetchone()[0], "Mañana 🌄")

    def test_upgrade_text_library_for_photos(self):
        db = Path(self.directory) / "anterior.sqlite3"
        with contextlib.closing(Client(db).initialize()) as c:
            page = c.call("create_page", title="Anterior")
        with contextlib.closing(sqlite3.connect(db)) as old:
            old.execute("DROP TABLE photos")
            old.execute("PRAGMA user_version=1")
            old.commit()
        with contextlib.closing(Client(db).initialize()) as c:
            self.assertEqual(c.call("get_page", id=page["id"])["title"], "Anterior")
            c.call("apply_block_changes", id=page["id"], expected_revision=1, changes=[
                {"op":"insert","block":{"type":"image","text":"No existe","asset":"f"*64,"width_percent":65}}
            ],error="invalid_argument")
            self.assertEqual(c.call("get_page", id=page["id"])["revision"],1)
        with contextlib.closing(sqlite3.connect(db)) as upgraded:
            self.assertEqual(upgraded.execute("PRAGMA user_version").fetchone()[0], 2)
        backup, = db.parent.glob(db.name + ".v1-*.sqlite3")
        with contextlib.closing(sqlite3.connect(backup)) as previous:
            self.assertEqual(previous.execute("PRAGMA user_version").fetchone()[0], 1)
            self.assertEqual(previous.execute("SELECT title FROM pages").fetchone()[0], "Anterior")


if __name__ == "__main__":
    unittest.main()
